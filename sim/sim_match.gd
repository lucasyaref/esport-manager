class_name SimMatch
extends RefCounted
## Deterministic tick-based match simulation.
##
## M2 scope: real map, minion lanes, farming, jungle pathing, recalls,
## gold/XP economy — no combat between players yet (M3). Contract unchanged
## since M0: setup + data in, ordered events + snapshots + checksum out;
## same seed ⇒ byte-identical output.
##
## Pure GDScript — no Node/scene dependencies. Must run headless.

const TICKS_PER_SECOND := 10
const DEFAULT_DURATION_MIN := 30

var map: SimMap
var balance: Dictionary
var rng: SimRNG
var lanes: Dictionary = {}          # lane name -> LaneState
var camps: Array[Dictionary] = []   # {def, alive, respawn_tick}
var agents: Array[PlayerAgent] = []

var _setup: Dictionary
var _data: Dictionary
var _events: Array[Dictionary] = []
var _snapshots: Array[Dictionary] = []
var _snapshot_every: int


## setup: { seed: int, duration_ticks?: int, snapshot_every?: int,
##          teams?: {blue: team_id, red: team_id}, picks?: {player_id: char_id} }
## data: DataLoader.load_all() result with no errors.
func _init(setup: Dictionary, data: Dictionary) -> void:
	assert(data.errors.is_empty(), "SimMatch got invalid data: %s" % str(data.errors))
	_setup = setup
	_data = data
	rng = SimRNG.new(int(setup.get("seed", 0)))
	_snapshot_every = int(setup.get("snapshot_every", 1))
	map = SimMap.new(data.map)
	balance = data.balance
	for lane in SimMap.LANES:
		lanes[lane] = LaneState.new(lane, map, balance.minions)
	var first_spawn := int(float(balance.jungle.camp_first_spawn_s) * TICKS_PER_SECOND)
	for camp_def in map.camps:
		camps.append({"def": camp_def, "alive": false, "respawn_tick": first_spawn})
	_spawn_agents()


func run() -> Dictionary:
	var duration := int(_setup.get("duration_ticks", DEFAULT_DURATION_MIN * 60 * TICKS_PER_SECOND))
	var minions: Dictionary = balance.minions
	var first_wave := int(float(minions.first_wave_s) * TICKS_PER_SECOND)
	var wave_interval := int(float(minions.wave_interval_s) * TICKS_PER_SECOND)

	emit_event(0, "match_start", {
		"seed": int(_setup.get("seed", 0)),
		"picks": _picks_summary(),
	})
	for t in range(duration):
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
		for agent in agents:
			agent.update(t, self)
		if t % _snapshot_every == 0:
			_snapshots.append(_capture_snapshot(t))

	var summaries: Array[Dictionary] = []
	for agent in agents:
		summaries.append(agent.summary())
	emit_event(duration - 1, "match_end", {"players": summaries})
	return {
		"events": _events,
		"snapshots": _snapshots,
		"ticks": duration,
		"summary": summaries,
		"checksum": _checksum(),
	}


func emit_event(t: int, type: String, data: Dictionary) -> void:
	# "draws" = RNG draw count when the event fired; pinpoints desyncs.
	_events.append({"t": t, "type": type, "draws": rng.draw_count, "data": data})


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
	var deaths := lane.tick(t, pressure)
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
			agent.gold_total, agent.cs,
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
