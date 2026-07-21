class_name SimMatch
extends RefCounted
## Deterministic tick-based match simulation.
##
## M3 scope: full game — farming economy (M2) plus ganks, skirmishes,
## teamfights with ultimates, Dragon/Baron, tower/nexus destruction and a win
## condition. Contract unchanged since M0: setup + data in, ordered events +
## snapshots + checksum out; same seed ⇒ byte-identical output.
##
## Pure GDScript — no Node/scene dependencies. Must run headless.

const TICKS_PER_SECOND := 10
const DEFAULT_DURATION_MIN := 45  # hard cap; matches normally end by nexus kill
const BRAIN_INTERVAL := 20        # macro decisions every 2 s

var map: SimMap
var balance: Dictionary
var comp_rules: Dictionary
var rng: SimRNG
var now := 0
var lanes: Dictionary = {}          # lane name -> LaneState
var camps: Array[Dictionary] = []   # {def, alive, respawn_tick}
var agents: Array[PlayerAgent] = []
var combat: Combat
var objectives: Objectives
var brains: Dictionary = {}         # team -> TeamBrain
var wards: Dictionary = {"blue": [], "red": []}

var _setup: Dictionary
var _data: Dictionary
var _events: Array[Dictionary] = []
var _snapshots: Array[Dictionary] = []
var _snapshot_every: int
var _comp_static := {"blue": 1.0, "red": 1.0}
var _moods: Dictionary = {}
var _next_fight_allowed := 0


## setup: { seed: int, duration_ticks?: int, snapshot_every?: int (0 = none),
##          teams?: {blue: id, red: id}, picks?: {player_id: char_id},
##          moods?: {player_id: -1|0|1}, cohesion?: {blue: float, red: float} }
## data: DataLoader.load_all() result with no errors.
func _init(setup: Dictionary, data: Dictionary) -> void:
	assert(data.errors.is_empty(), "SimMatch got invalid data: %s" % str(data.errors))
	_setup = setup
	_data = data
	rng = SimRNG.new(int(setup.get("seed", 0)))
	_snapshot_every = int(setup.get("snapshot_every", 1))
	_moods = setup.get("moods", {})
	map = SimMap.new(data.map)
	balance = data.balance
	comp_rules = data.comp_rules
	for lane in SimMap.LANES:
		lanes[lane] = LaneState.new(lane, map, balance.minions)
	var first_spawn := int(float(balance.jungle.camp_first_spawn_s) * TICKS_PER_SECOND)
	for camp_def in map.camps:
		camps.append({"def": camp_def, "alive": false, "respawn_tick": first_spawn})
	_spawn_agents()
	combat = Combat.new(self)
	objectives = Objectives.new(self)
	for team in SimMap.TEAMS:
		brains[team] = TeamBrain.new(team, agents)
	_compute_comp_modifiers()


func run() -> Dictionary:
	var duration := int(_setup.get("duration_ticks", DEFAULT_DURATION_MIN * 60 * TICKS_PER_SECOND))
	var minions: Dictionary = balance.minions
	var first_wave := int(float(minions.first_wave_s) * TICKS_PER_SECOND)
	var wave_interval := int(float(minions.wave_interval_s) * TICKS_PER_SECOND)

	emit_event(0, "match_start", {
		"seed": int(_setup.get("seed", 0)),
		"picks": _picks_summary(),
	})
	var end_tick := duration
	for t in range(duration):
		now = t
		if t >= first_wave and (t - first_wave) % wave_interval == 0:
			@warning_ignore("integer_division")  # exact: only reached when modulo == 0
			var wave_index := (t - first_wave) / wave_interval + 1
			for lane in SimMap.LANES:
				lanes[lane].spawn_wave(t, wave_index)
		for camp in camps:
			if not camp.alive and t >= camp.respawn_tick:
				camp.alive = true
		for lane in SimMap.LANES:
			_tick_lane(t, lane)
		if t % BRAIN_INTERVAL == 0:
			for team in SimMap.TEAMS:
				brains[team].update(t, self)
		for agent in agents:
			agent.update(t, self)
		objectives.update(t)
		if _snapshot_every > 0 and t % _snapshot_every == 0:
			_snapshots.append(_capture_snapshot(t))
		if objectives.winner != "":
			end_tick = t + 1
			break

	var summaries: Array[Dictionary] = []
	var team_kills := {"blue": 0, "red": 0}
	for agent in agents:
		summaries.append(agent.summary())
		team_kills[agent.team] += agent.kills
	emit_event(end_tick - 1, "match_end", {
		"winner": objectives.winner, "duration_s": roundi(end_tick / float(TICKS_PER_SECOND)),
		"kills": team_kills, "players": summaries,
	})
	var result := {
		"events": _events,
		"snapshots": _snapshots,
		"ticks": end_tick,
		"winner": objectives.winner,
		"summary": summaries,
		"checksum": _checksum(),
	}
	# Break RefCounted reference cycles so 1000-sim batches don't leak.
	combat.m = null
	objectives.m = null
	return result


func emit_event(t: int, type: String, data: Dictionary) -> void:
	# "draws" = RNG draw count when the event fired; pinpoints desyncs.
	_events.append({"t": t, "type": type, "draws": rng.draw_count, "data": data})


# --- combat / macro services (called by agents, brains, objectives) ----------

func phase_of(t: int) -> String:
	var minute := float(t) / (60.0 * TICKS_PER_SECOND)
	if minute < float(comp_rules.phases.mid_start_min):
		return "early"
	if minute < float(comp_rules.phases.late_start_min):
		return "mid"
	return "late"


func phase_curve_mult(curve: String, t: int) -> float:
	return float(comp_rules.curves[curve][phase_of(t)])


func team_comp_mult(team: String, _t: int) -> float:
	return _comp_static[team]


func mood_mult(player_id: String) -> float:
	return 1.0 + 0.05 * float(_moods.get(player_id, 0))


func rally_pos(team: String) -> Vector2:
	return brains[team].rally


func award_team(t: int, team: String, gold_each: float, xp_each: float) -> void:
	for agent in agents:
		if agent.team == team:
			agent.earn(gold_each)
			if xp_each > 0.0:
				agent.add_xp(t, xp_each, self)


func place_ward(team: String, pos: Vector2, t: int) -> void:
	var ttl := int(float(balance.wards.ward_duration_s) * TICKS_PER_SECOND)
	wards[team].append({"pos": pos, "expires": t + ttl})


func ward_near(team: String, pos: Vector2) -> bool:
	var active: Array = wards[team].filter(
		func(w: Dictionary) -> bool: return w.expires >= now)
	wards[team] = active
	for w: Dictionary in active:
		if w.pos.distance_to(pos) < 25.0:
			return true
	return false


## Starts a fight unless the global fight cooldown blocks it (ganks bypass:
## they're gated by the jungler's own interval). Returns winner or "".
func start_fight(t: int, blue: Array, red: Array, location: Vector2, context: String) -> String:
	if context != "gank" and t < _next_fight_allowed:
		return ""
	var blue_alive: Array = blue.filter(func(a: PlayerAgent) -> bool: return a.alive)
	var red_alive: Array = red.filter(func(a: PlayerAgent) -> bool: return a.alive)
	if context in ["objective", "siege_defense"]:
		_join_teleporters(blue_alive, red_alive, t)
	if blue_alive.is_empty() or red_alive.is_empty():
		return ""
	var end := t + int(float(balance.combat.fight_duration_s) * TICKS_PER_SECOND)
	for agent: PlayerAgent in blue_alive + red_alive:
		agent.busy_until = end
	_next_fight_allowed = end + int(float(balance.combat.fight_cooldown_s) * TICKS_PER_SECOND)
	return combat.resolve(t, blue_alive, red_alive, location, context)


## Split-pushers with a ready global teleport join big fights (their whole
## point: pressure the map, TP in when it matters).
func _join_teleporters(blue: Array, red: Array, t: int) -> void:
	for agent in agents:
		if not agent.alive or not agent.ult_ready(t):
			continue
		if agent.character.ultimate.effect != "global_teleport":
			continue
		var side: Array = blue if agent.team == "blue" else red
		if not side.has(agent):
			side.append(agent)


## Laning-phase gank attempt: pick an overextended lane, roll, go.
func try_gank(jungler: PlayerAgent, t: int) -> bool:
	if phase_of(t) != "early":
		return false
	var g: Dictionary = balance.ganks
	var check_ticks := int(float(g.check_interval_s) * TICKS_PER_SECOND)
	if t % check_ticks != 0:
		return false
	if t - jungler.last_gank_tick() < int(float(g.min_interval_s) * TICKS_PER_SECOND):
		return false
	var chance: float = float(g.base_chance_early_tag) if "early" in jungler.character.tags \
		else float(g.base_chance_other)
	if not rng.chance(chance):
		return false
	var enemy := "red" if jungler.team == "blue" else "blue"
	var lane_names: Array[String] = []
	var weights: Array[float] = []
	for lane in SimMap.LANES:
		var has_victim := false
		for agent in agents:
			if agent.team == enemy and agent.is_farming_lane(lane):
				has_victim = true
				break
		if not has_victim:
			continue
		var front: float = lanes[lane].front_t
		# Overextension: how far the enemy laner is pushed toward the
		# jungler's side of the map (easier to reach, further from safety).
		var overext: float = clampf(
			((0.5 - front) if jungler.team == "blue" else (front - 0.5)) / 0.08, 0.0, 1.0)
		lane_names.append(lane)
		weights.append(1.0 + float(g.overextend_weight) * overext)
	if lane_names.is_empty():
		return false
	jungler.start_gank(t, lane_names[rng.weighted_index(weights)])
	return true


## Jungler arrived on the gank lane: spotted check, then a lane skirmish.
func execute_gank(jungler: PlayerAgent, lane_name: String, t: int) -> void:
	var enemy := "red" if jungler.team == "blue" else "blue"
	jungler.gank_over()
	var victims: Array = []
	var allies: Array = [jungler]
	for agent in agents:
		if agent.is_farming_lane(lane_name):
			(victims if agent.team == enemy else allies).append(agent)
	if victims.is_empty():
		return
	var g: Dictionary = balance.ganks
	var front_pos: Vector2 = lanes[lane_name].front_pos()
	var success: float = float(g.success_base) \
		- float(victims[0].attrs.mechanics) / float(g.escape_mechanics_divisor)
	if ward_near(enemy, front_pos):
		success -= float(g.ward_penalty)
	if not rng.chance(success):
		emit_event(t, "gank_spotted", {"player": jungler.id, "lane": lane_name})
		return
	emit_event(t, "gank", {"player": jungler.id, "lane": lane_name})
	if jungler.team == "blue":
		start_fight(t, allies, victims, front_pos, "gank")
	else:
		start_fight(t, victims, allies, front_pos, "gank")


# --- setup -------------------------------------------------------------------

func _spawn_agents() -> void:
	var team_ids: Dictionary = _setup.get("teams", _default_teams())
	var picks: Dictionary = _setup.get("picks", _signature_picks(team_ids))
	for side in SimMap.TEAMS:
		var roster: Dictionary = _data.teams[team_ids[side]].roster
		for role in DataLoader.ROLES:
			var player: Dictionary = _data.players[roster[role]]
			var character: Dictionary = _data.characters[picks[player.id]]
			agents.append(PlayerAgent.new(
				player, side, character, map.bases[side],
				float(balance.economy.starting_gold)))


## First two teams in file order: first = blue, second = red.
func _default_teams() -> Dictionary:
	var ids: Array = _data.teams.keys()
	return {"blue": ids[0], "red": ids[1]}


## Every player on their highest-proficiency character (signature pick).
func _signature_picks(team_ids: Dictionary) -> Dictionary:
	var picks := {}
	for side in SimMap.TEAMS:
		var roster: Dictionary = _data.teams[team_ids[side]].roster
		for role in DataLoader.ROLES:
			var player: Dictionary = _data.players[roster[role]]
			var best := ""
			var best_prof := -1
			for char_id: String in player.champion_pool:
				var prof := int(player.champion_pool[char_id])
				if prof > best_prof:
					best_prof = prof
					best = char_id
			picks[player.id] = best
	return picks


## Draft-level comp modifiers are static for the whole match: tag synergies,
## tag counters vs the enemy draft, plus the draft-cohesion bonus (M5).
func _compute_comp_modifiers() -> void:
	var team_tags := {"blue": [], "red": []}
	for agent in agents:
		for tag in agent.character.tags:
			team_tags[agent.team].append(tag)
	var cohesion: Dictionary = _setup.get("cohesion", {})
	for team in SimMap.TEAMS:
		var enemy := "red" if team == "blue" else "blue"
		var bonus: float = float(cohesion.get(team, 0.0))
		for syn: Dictionary in comp_rules.synergies:
			if syn.tags[0] in team_tags[team] and syn.tags[1] in team_tags[team]:
				bonus += float(syn.bonus)
		for counter: Dictionary in comp_rules.counters:
			if counter.strong in team_tags[team] and counter.weak in team_tags[enemy]:
				bonus += float(counter.bonus)
		_comp_static[team] = 1.0 + bonus


func _picks_summary() -> Array:
	var out := []
	for agent in agents:
		out.append({"player": agent.id, "character": agent.character.id, "team": agent.team})
	return out


# --- per-tick ----------------------------------------------------------------

## Runs lane minion combat, then routes each minion death: CS gold to the
## lane's designated farmer (top/mid solo, carry in bot; support never
## last-hits), XP to every farming player on the killing side.
func _tick_lane(t: int, lane_name: String) -> void:
	var lane: LaneState = lanes[lane_name]
	var present := {"blue": [], "red": []}
	for agent in agents:
		if agent.is_farming_lane(lane_name):
			present[agent.team].append(agent)
	var pressure := {
		"blue": present.blue.size() * float(balance.minions.presence_pressure),
		"red": present.red.size() * float(balance.minions.presence_pressure),
	}
	var deaths := lane.tick(t, pressure, objectives.lane_bounds(lane_name))
	for death in deaths:
		var killer_side: String = "red" if death.team == "blue" else "blue"
		var killers: Array = present[killer_side]
		if killers.is_empty():
			continue
		var share: float = 1.0 if killers.size() == 1 else float(balance.xp.duo_share)
		for agent: PlayerAgent in killers:
			agent.add_xp(t, float(balance.minions.xp_per_minion) * share, self)
		var farmer := _designated_farmer(killers)
		if farmer == null:
			continue
		var chance: float = minf(
			float(balance.cs.base_chance) + float(farmer.attrs.laning) / float(balance.cs.laning_divisor)
				+ (float(balance.cs.support_assist_bonus) if killers.size() > 1 else 0.0),
			float(balance.cs.max_chance))
		if rng.chance(chance):
			farmer.cs += 1
			farmer.earn(_minion_gold(death))


func _designated_farmer(killers: Array) -> PlayerAgent:
	for agent: PlayerAgent in killers:
		if agent.role != "support":
			return agent
	return null


func _minion_gold(death: Dictionary) -> float:
	var minions: Dictionary = balance.minions
	if death.cannon:
		return float(minions.gold_cannon)
	# Melee/caster mix is not tracked per minion; use their average value.
	return (float(minions.gold_melee) + float(minions.gold_caster)) / 2.0


func _capture_snapshot(t: int) -> Dictionary:
	var players := []
	for agent in agents:
		players.append([
			agent.id, agent.pos.x, agent.pos.y, agent.level,
			agent.gold_total, agent.cs, 1 if agent.alive else 0,
			agent.hp, agent.max_hp,
		])
	var lane_rows := []
	for lane in SimMap.LANES:
		var l: LaneState = lanes[lane]
		lane_rows.append([lane, l.front_t,
			l.minions.blue + l.cannons.blue, l.minions.red + l.cannons.red])
	return {"t": t, "players": players, "lanes": lane_rows}


## MD5 over byte-exact serialized events + snapshots. var_to_bytes keeps full
## float precision — JSON.stringify rounds, which can hide tiny divergences.
func _checksum() -> String:
	var payload := var_to_bytes({"events": _events, "snapshots": _snapshots})
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(payload)
	return ctx.finish().hex_encode()
