class_name PlayerAgent
extends RefCounted
## One pro player in the match: movement, farming, jungle pathing, recalls,
## gold/XP/level (M2) + combat life-cycle, ganking, grouping, warding (M3).

enum State {
	TO_LANE, FARMING, TO_CAMP, CLEARING, WAITING_CAMP, RECALLING,
	GROUPING, HOLDING, GANKING, DEAD,
}

const ARRIVE_DIST := 1.0
const SPEED_SCALE := 1.0 / 125.0  # character speed 335 -> ~2.7 map units/s

var idx := -1                    # index into SimMatch.agents (targets are stored
                                 # as indices, never references — agents are
                                 # RefCounted and mutual refs would leak)
var id: String
var handle: String
var team: String                 # "blue" / "red"
var role: String
var lane: String                 # "" for jungle
var character: Dictionary
var attrs: Dictionary

var pos: Vector2
var state: int = State.TO_LANE
var hp := 0.0                    # live health; drives retreat/recall and death
var max_hp := 0.0
var level := 1
var xp := 0.0
var cs := 0
var gold_total := 0.0            # earned overall (economy curves read this)
var gold_carried := 0.0          # spent on recall (buy trigger)
var item_power := 0.0

# Combat state, owned by Combat and read back here for movement.
var in_combat := false           # Combat has taken over this agent's movement
var disengaging := false         # backing off rather than committing
var target_idx := -1             # who we are attacking (index into agents)
var desired_pos := Vector2.ZERO  # where Combat wants us to stand this tick
var speed_mult := 1.0            # gap-closer bonus while committing to a fight
var attack_ready_at := 0
var last_swing_at := -999999     # tick of the last auto-attack fired (viewer beat)
var disengage_until := -1        # broke off a fight; won't re-commit until then
# Why this agent is not fighting, when an enemy is in sight. Diagnostic only —
# nothing in the sim reads it — but "how big do fights get" is an M5-G balance
# question and guessing at the reason is how you tune the wrong number.
var decline_reason := ""         # "" | low_hp | locked | numbers | chase | tower
var stunned_until := -1
var slowed_until := -1           # movement slowed by CC (a basic ability that catches)
var slow_mult := 1.0             # speed multiplier while slowed (< 1.0)
var steroid_until := -1          # self-buff ultimates
var last_damaged_at := -999999
var commit_pos := Vector2.ZERO   # where this agent committed to its current fight
var last_hit_at := -999999       # last tick it landed a hit (chase patience)
var lane_stance := "push"        # push / trade / allin / freeze / back (Laning)

var alive := true
var kills := 0
var deaths := 0
var assists := 0
var kill_streak := 0
var death_streak := 0

var _respawn_at := 0
# Per-slot cooldown timers (§3 three-action model): each ability slot runs on its
# own cooldown and unlock level, so the basic ability is a second instance of the
# ultimate machine rather than a new subsystem.
var _ability_ready_at := {"basic_ability": 0, "ultimate": 0}
var _has_cc := false             # basic ability is an active CC (catches a target)
# Passive basic abilities are persistent combat modifiers, resolved once at spawn
# and read by Combat (public, like stunned_until / steroid_until).
var passive_power := 1.0         # multiplies threat and outgoing damage
var passive_guard := 1.0         # multiplies incoming damage (< 1.0 = tankier)
var passive_sustain := 0.0       # heals this fraction of damage dealt
var _move_step := 0.0            # this tick's movement distance (base speed x slow)
var _state_until := 0            # tick when CLEARING / RECALLING ends
var _camp_index := -1
var _last_ward_t := -999999
var _last_gank_t := -999999
var _gank_lane := ""
var _gank_cut := Vector2.ZERO     # sandwich cut-off point (M5-E); ZERO = walk at the lane
var _tempo_lane := ""             # lane to press after a play landed (M5-E)
var _tempo_until := 0
var _play_pos := Vector2.ZERO     # committed multi-man play destination (M5-F2)
var _play_until := 0
var _play_hub := ""               # nav hub nearest the play target (M6-T2)
var _speed_per_tick: float
var _map: SimMap                 # static geometry only — no cycle back to us


func _init(p_idx: int, player: Dictionary, p_team: String, p_character: Dictionary,
		map: SimMap, starting_gold: float) -> void:
	idx = p_idx
	id = player.id
	handle = player.handle
	team = p_team
	role = player.role
	lane = {"top": "top", "mid": "mid", "carry": "bot", "support": "bot"}.get(role, "")
	character = p_character
	attrs = player.attributes
	_map = map
	pos = map.bases[p_team]
	gold_total = starting_gold
	gold_carried = 0.0  # starting gold is considered already spent on boots etc.
	item_power = starting_gold
	state = State.TO_CAMP if role == "jungle" else State.TO_LANE
	_speed_per_tick = float(p_character.base.speed) * SPEED_SCALE / SimMatch.TICKS_PER_SECOND
	max_hp = DataLoader.stat_at_level(character, "hp", level)
	hp = max_hp
	_init_basic_ability()


## m = the SimMatch. Not stored (would leak a RefCounted cycle).
func update(t: int, m: SimMatch) -> void:
	if not alive:
		if t >= _respawn_at:
			alive = true
			hp = max_hp
			state = State.TO_CAMP if role == "jungle" else State.TO_LANE
		return
	_earn_passive(m)
	_regen(t, m)
	if t < stunned_until:
		return
	# One place computes this tick's movement distance so every mover — combat
	# steering and the FSM's walk helpers — is slowed together when CC lands.
	_move_step = _eff_speed(t)
	# Combat owns movement whenever this agent is engaged or backing off:
	# the FSM's farm/camp/group destinations resume once the danger passes.
	if in_combat:
		# Not _move_toward: its ARRIVE_DIST slack is for walking to a lane or a
		# camp. In a fight, stopping a unit short of where you meant to stand
		# means a melee character never reaches its own attack range.
		move_to(pos.move_toward(desired_pos, _move_step * speed_mult))
		return
	if role == "support":
		_maybe_ward(t, m)
	# A committed play (M5-F2) overrides where this body walks, for the states where
	# walking is all it is doing. It deliberately does NOT interrupt a recall, a camp
	# clear or a gank already in flight — the team brain never dispatches those
	# players, and honouring it here too keeps the two ends of the rule in one shape.
	var play := play_pos(t)
	if play != Vector2.ZERO and state in [State.TO_LANE, State.FARMING, State.TO_CAMP,
			State.WAITING_CAMP, State.GROUPING, State.HOLDING]:
		_move_toward(play, _play_hub)
		return
	match state:
		State.TO_LANE:
			if _move_toward(m.lane_stand_pos(lane, team, lane_stance), "lane_" + lane):
				state = State.FARMING
		State.FARMING:
			# A laner that shoved its wave and heard a gank call rotates to it —
			# the roam the designer wanted instead of pushing back and forth.
			var roam: String = m.brains[team].gank_call_lane(t, idx)
			var press := tempo_pos(t, m)
			if roam != "" and roam != lane:
				_move_toward(m.lane_stand_pos(roam, team, "trade"), "lane_" + roam)
			elif press != Vector2.ZERO:
				# A play landed on that lane and it is briefly free: spend the
				# window on it rather than walking home to farm.
				_move_toward(press, "lane_" + _tempo_lane)
			else:
				_move_toward(m.lane_stand_pos(lane, team, lane_stance), "lane_" + lane)
			_maybe_recall(t, m)
		State.TO_CAMP, State.WAITING_CAMP:
			# A jungler whose gank just landed presses the lane it opened instead
			# of walking straight back to a camp — the tempo half of the play.
			var press := tempo_pos(t, m)
			if press != Vector2.ZERO:
				_move_toward(press, "lane_" + _tempo_lane)
				return
			if role == "jungle" and m.try_gank(self, t):
				return
			if _check_buy(t, m):
				return
			_jungle_step(t, m)
		State.CLEARING:
			if t >= _state_until:
				_finish_camp(t, m)
		State.GANKING:
			# Walk to the lane and let proximity do the rest — the fight, if
			# there is one, is resolved by the combat engine like any other.
			# A sandwich walks to its cut-off point instead: behind the victim,
			# on the road home, so the victim is between us and our laner. Both
			# sit on/near _gank_lane, so that lane is the right hub either way.
			var gank_target: Vector2 = _gank_cut if _gank_cut != Vector2.ZERO \
				else m.lane_stand_pos(_gank_lane, "red" if team == "blue" else "blue")
			if _move_toward(gank_target, "lane_" + _gank_lane) or t - _last_gank_t > m.gank_timeout_ticks():
				m.gank_arrived(self, _gank_lane, t)
		State.GROUPING:
			if _move_toward(m.rally_pos(team), m.rally_hub(team)):
				state = State.HOLDING
		State.HOLDING:
			_move_toward(m.rally_pos(team), m.rally_hub(team))
		State.RECALLING:
			if t >= _state_until:
				_finish_recall(t, m)


## The only way this agent's position ever changes. The map has edges: steering
## is free 2D movement, so anything that produces a direction — fleeing a fight,
## kiting, a teleport — can point off the world if nothing stops it.
func move_to(p: Vector2) -> void:
	pos = _map.clamp_pos(p)


func is_farming_lane(lane_name: String) -> bool:
	return state == State.FARMING and lane == lane_name and alive


func add_xp(t: int, amount: float, m: SimMatch) -> void:
	var xp_bal: Dictionary = m.balance.xp
	xp += amount
	while level < DataLoader.MAX_LEVEL and xp >= _level_cost(xp_bal):
		xp -= _level_cost(xp_bal)
		level += 1
		# Levelling grants the HP growth as bonus current health, LoL-style.
		var new_max := DataLoader.stat_at_level(character, "hp", level)
		hp += new_max - max_hp
		max_hp = new_max
		m.emit_event(t, "level_up", {"player": id, "level": level})


func earn(amount: float) -> void:
	gold_total += amount
	gold_carried += amount


## An ability slot is castable when it is unlocked (its level) and off cooldown.
## Both the basic ability and the ultimate go through here — one machine, two
## slots (§3). Ultimates default to unlock 6 (LoL-like); the basic ability's
## unlock comes from its data (early, laning phase).
func ability_ready(slot_name: String, t: int) -> bool:
	var slot: Dictionary = character.get(slot_name, {})
	if slot.is_empty():
		return false
	var unlock: int = int(slot.get("unlock", 6 if slot_name == "ultimate" else 1))
	return alive and level >= unlock and t >= int(_ability_ready_at[slot_name])


## `extra` rides along in the cast event — where it went off, how wide, and who
## it caught (filled in by Combat, which is what knows the affected set). Playback
## needs that to land an ultimate with weight instead of printing its name.
func cast_ability(slot_name: String, t: int, m: SimMatch, extra: Dictionary = {}) -> void:
	var slot: Dictionary = character[slot_name]
	_ability_ready_at[slot_name] = t + int(float(slot.cooldown) * SimMatch.TICKS_PER_SECOND)
	var type := "ultimate_cast" if slot_name == "ultimate" else "basic_cast"
	var data := {"player": id, "name": slot.name, "effect": slot.effect,
		"pos": [pos.x, pos.y]}
	data.merge(extra)
	m.emit_event(t, type, data)


## Kept for the callers that only care about the ultimate (split-push teleport).
func ult_ready(t: int) -> bool:
	return ability_ready("ultimate", t)


func cast_ult(t: int, m: SimMatch) -> void:
	cast_ability("ultimate", t, m)


## Whether this player carries an active-CC basic ability — the tool that catches
## a target for a gank/roam. Read by the connectability gate on ganks (§6.1).
func has_cc() -> bool:
	return _has_cc


## Apply a movement slow (a CC that catches). Keeps the strongest overlapping
## slow and the latest expiry, so re-applying does not weaken an active slow.
func apply_slow(t: int, until: int, mult: float) -> void:
	slow_mult = minf(mult, slow_mult) if t < slowed_until else mult
	slowed_until = maxi(slowed_until, until)


func die(t: int, m: SimMatch) -> void:
	var c: Dictionary = m.balance.combat
	alive = false
	hp = 0.0
	deaths += 1
	death_streak += 1
	kill_streak = 0
	state = State.DEAD
	pos = m.map.bases[team]
	in_combat = false
	disengaging = false
	target_idx = -1
	stunned_until = -1
	slowed_until = -1
	slow_mult = 1.0
	steroid_until = -1
	_camp_index = -1
	_respawn_at = t + int((float(c.respawn_base_s) + float(c.respawn_per_level_s) * level)
		* SimMatch.TICKS_PER_SECOND)


## Applies damage without resolving death — the caller decides whether a
## player at 0 HP dies now (and who gets the kill credit).
func take_damage(amount: float, t: int = -999999) -> void:
	hp = maxf(hp - amount, 0.0)
	last_damaged_at = maxi(last_damaged_at, t)


func hp_fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


## Called by combat when this player gets a kill.
func credit_kill_reset() -> void:
	death_streak = 0


## Move to a rally point (set by the team brain).
func set_grouping() -> void:
	if state in [State.CLEARING, State.RECALLING, State.GANKING, State.DEAD]:
		return  # finish what they're doing first
	state = State.GROUPING


func set_farming_intent() -> void:
	if state in [State.GROUPING, State.HOLDING]:
		state = State.TO_CAMP if role == "jungle" else State.TO_LANE


## `cut` (M5-E) is the sandwich's destination: a point *past* the victim, between it
## and its own base, instead of the victim's own stand position. Walking at a target
## with equal move speeds just pushes it home; arriving behind it takes the retreat
## away. ZERO keeps the old behaviour (walk to the lane and let proximity do it).
func start_gank(t: int, target_lane: String, cut := Vector2.ZERO) -> void:
	state = State.GANKING
	_gank_lane = target_lane
	_gank_cut = cut
	_last_gank_t = t


## Put on the lane a landed play just opened, until `until` (M5-E tempo payoff).
## Not a state: the agent keeps farming/clearing rules, it just farms *there*, so
## nothing here can fight the combat engine or the jungle route for control.
func set_tempo(lane_name: String, until: int) -> void:
	_tempo_lane = lane_name
	_tempo_until = until


## Committed to a multi-man play until `until` (M5-F2). Like set_tempo this is a
## destination, not a state: the agent keeps its FSM state, so combat still takes
## over the moment a fight starts and a camp clear in progress still finishes.
## `hub` (M6-T2) is the nav hub nearest the target, resolved once by the
## caller (TeamBrain._consider_play) when the play is called rather than
## re-derived every tick: a live enemy position has no hub of its own, so
## this is the one destination that needs NavGrid.nearest_hub at all.
func set_play(p: Vector2, until: int, hub: String = "") -> void:
	_play_pos = p
	_play_until = until
	_play_hub = hub


## Where the play wants this body, or ZERO once the window has shut.
func play_pos(t: int) -> Vector2:
	if _play_pos == Vector2.ZERO or t >= _play_until:
		_play_pos = Vector2.ZERO
		_play_hub = ""
		return Vector2.ZERO
	return _play_pos


## Where this agent should press, or ZERO once the window has run out.
func tempo_pos(t: int, m: SimMatch) -> Vector2:
	if _tempo_lane == "" or t >= _tempo_until:
		_tempo_lane = ""
		return Vector2.ZERO
	return m.lane_stand_pos(_tempo_lane, team, "push")


func gank_over() -> void:
	state = State.TO_CAMP
	_gank_cut = Vector2.ZERO
	# Drop the pre-gank camp target: after ganking (e.g. top) the jungler is now
	# far from the camp it was walking to (e.g. bot-side), so re-pick the nearest
	# camp from where it stands instead of yo-yoing all the way back (2026-07-25
	# playtest, remark 5). _pick_camp re-selects on the next jungle step.
	_camp_index = -1


func last_gank_tick() -> int:
	return _last_gank_t


func summary() -> Dictionary:
	return {
		"player": id, "handle": handle, "team": team, "role": role,
		"character": character.id, "level": level, "cs": cs,
		"kills": kills, "deaths": deaths, "assists": assists,
		"gold": roundi(gold_total), "item_power": roundi(item_power),
	}


# --- internals ---------------------------------------------------------------

func _level_cost(xp_bal: Dictionary) -> float:
	return float(xp_bal.level_up_base) + (level - 1) * float(xp_bal.level_up_step)


## Resolve the basic-ability slot once at spawn (§3 three-action model). A passive
## becomes a set of persistent combat multipliers; an active CC only flags this
## player as a catcher (the firing itself is Combat's job, like the ultimate).
func _init_basic_ability() -> void:
	var slot: Dictionary = character.get("basic_ability", {})
	var effect: String = str(slot.get("effect", ""))
	_has_cc = effect in ["single_cc", "aoe_cc"]
	var pct: float = float(slot.get("params", {}).get("pct", 0.0))
	match effect:
		"passive_power":
			passive_power = 1.0 + pct
		"passive_bulwark":
			passive_guard = 1.0 - pct
		"passive_sustain":
			passive_sustain = pct


## This tick's per-tick movement distance: base speed, cut while slowed by CC.
func _eff_speed(t: int) -> float:
	return _speed_per_tick * (slow_mult if t < slowed_until else 1.0)


func _earn_passive(m: SimMatch) -> void:
	var eco: Dictionary = m.balance.economy
	var per_tick: float = float(eco.passive_gold_per_s) / SimMatch.TICKS_PER_SECOND
	if role == "support":
		per_tick += float(eco.support_income_per_s) / SimMatch.TICKS_PER_SECOND
	earn(per_tick)


## Out-of-combat regen: slow on the map, fast in the fountain, none for a few
## seconds after taking a hit. This is what makes a low-HP player choose to go
## home instead of grinding at 20%.
func _regen(t: int, m: SimMatch) -> void:
	if hp >= max_hp:
		return
	var health: Dictionary = m.balance.health
	if t - last_damaged_at < int(float(health.regen_lockout_s) * SimMatch.TICKS_PER_SECOND):
		return
	var pct: float = float(health.regen_pct_per_s)
	if pos.distance_to(m.map.bases[team]) < 6.0:
		pct = float(health.base_regen_pct_per_s)
	hp = minf(hp + max_hp * pct / SimMatch.TICKS_PER_SECOND, max_hp)


## `hub` names which NavGrid flow field (M6-T2) covers this destination —
## "lane_top", "camp_b_camp_top", "pit_dragon", etc. — so a body more than a
## glance from its target routes around walls instead of through them. Leave
## it "" when the map has no terrain/nav yet (degrades to the pre-T2 straight
## line) or when the caller has no natural hub for this target.
func _move_toward(target: Vector2, hub: String = "") -> bool:
	var dist := pos.distance_to(target)
	if dist <= ARRIVE_DIST:
		return true
	move_to(_step_toward(target, hub))
	return false


## Where to step this tick: straight at the target when nothing blocks the
## line (the common case — most of the map is open ground), otherwise the
## next cell of `hub`'s precomputed flow field. Falls back to the straight
## line if `hub` is empty, unknown, or its field has nothing left to say
## (already inside the hub's own region) — always a safe default, never a
## stall. Combat's own steering (desired_pos) never calls this: a fight's
## stand position is a few units away in the open pocket the fight is
## already standing in, not through rock (REPORTS/M6-terrain-scoping.md §4).
func _step_toward(target: Vector2, hub: String) -> Vector2:
	var nav: NavGrid = _map.nav
	if nav != null and hub != "" and not nav.has_los(pos, target):
		var step := nav.next_point(hub, pos)
		if step != pos:
			return pos.move_toward(step, _move_step)
	return pos.move_toward(target, _move_step)


func _buy_threshold(m: SimMatch) -> float:
	var eco: Dictionary = m.balance.economy
	return float(eco.buy_threshold_base) + level * float(eco.buy_threshold_per_level)


## Two reasons to go home: enough gold to buy, or low enough health that
## staying out is not worth the risk.
func _should_go_home(m: SimMatch) -> bool:
	return gold_carried >= _buy_threshold(m) \
		or hp_fraction() <= float(m.balance.health.recall_hp_threshold)


func _maybe_recall(t: int, m: SimMatch) -> void:
	if _should_go_home(m):
		_start_recall(t, m)


func _check_buy(t: int, m: SimMatch) -> bool:
	if _should_go_home(m):
		_start_recall(t, m)
		return true
	return false


func _start_recall(t: int, m: SimMatch) -> void:
	state = State.RECALLING
	_state_until = t + int(float(m.balance.economy.recall_channel_s) * SimMatch.TICKS_PER_SECOND)
	m.emit_event(t, "recall_start", {"player": id})


func _finish_recall(t: int, m: SimMatch) -> void:
	pos = m.map.bases[team]
	hp = max_hp
	item_power += gold_carried
	m.emit_event(t, "item_power_up", {"player": id, "spent": roundi(gold_carried)})
	gold_carried = 0.0
	state = State.TO_CAMP if role == "jungle" else State.TO_LANE


func _maybe_ward(t: int, m: SimMatch) -> void:
	var wards_bal: Dictionary = m.balance.wards
	if t - _last_ward_t < int(float(wards_bal.support_ward_interval_s) * SimMatch.TICKS_PER_SECOND):
		return
	_last_ward_t = t
	# Ward halfway between current position and the nearest objective pit —
	# covers the river approach a gank would come through.
	var pit: Vector2 = m.map.pits.dragon
	if pos.distance_to(m.map.pits.baron) < pos.distance_to(pit):
		pit = m.map.pits.baron
	var ward_pos := pos.lerp(pit, 0.5)
	m.place_ward(team, ward_pos, t)
	m.emit_event(t, "ward_placed", {"player": id, "pos": [ward_pos.x, ward_pos.y]})


func _jungle_step(t: int, m: SimMatch) -> void:
	_pick_camp(m)
	if _camp_index < 0:
		return
	var camp: Dictionary = m.camps[_camp_index]
	if _move_toward(camp.def.pos, "camp_%s" % camp.def.id):
		if camp.alive:
			var jungle_bal: Dictionary = m.balance.jungle
			var jitter: int = m.rng.randi_range(
				-int(float(jungle_bal.clear_jitter_s) * SimMatch.TICKS_PER_SECOND),
				int(float(jungle_bal.clear_jitter_s) * SimMatch.TICKS_PER_SECOND))
			state = State.CLEARING
			_state_until = t + int(float(camp.def.clear_s) * SimMatch.TICKS_PER_SECOND) + jitter
		else:
			state = State.WAITING_CAMP


func _pick_camp(m: SimMatch) -> void:
	if _camp_index >= 0 and m.camps[_camp_index].alive:
		return
	var best := -1
	var best_dist := INF
	for i in m.camps.size():
		var camp: Dictionary = m.camps[i]
		if camp.def.side != team or not camp.alive:
			continue
		var d: float = pos.distance_to(camp.def.pos)
		if d < best_dist:
			best_dist = d
			best = i
	if best < 0:
		var soonest := 0x7FFFFFFFFFFFFFFF
		for i in m.camps.size():
			var camp: Dictionary = m.camps[i]
			if camp.def.side == team and camp.respawn_tick < soonest:
				soonest = camp.respawn_tick
				best = i
	if best != _camp_index:
		_camp_index = best
		if state == State.WAITING_CAMP:
			state = State.TO_CAMP


func _finish_camp(t: int, m: SimMatch) -> void:
	var camp: Dictionary = m.camps[_camp_index]
	camp.alive = false
	camp.respawn_tick = t + int(float(m.balance.jungle.camp_respawn_s) * SimMatch.TICKS_PER_SECOND)
	earn(float(camp.def.gold))
	cs += 4
	add_xp(t, float(camp.def.xp), m)
	m.emit_event(t, "camp_cleared", {"player": id, "camp": camp.def.id})
	_camp_index = -1
	state = State.TO_CAMP
