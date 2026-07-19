class_name PlayerAgent
extends RefCounted
## One pro player in the match: movement, farming intent, jungle pathing,
## recalls, gold/XP/level. M2 scope — no combat, no ganks, no deaths yet.

enum State { TO_LANE, FARMING, TO_CAMP, CLEARING, WAITING_CAMP, RECALLING }

const ARRIVE_DIST := 1.0
const SPEED_SCALE := 1.0 / 125.0  # character speed 335 -> ~2.7 map units/s

var id: String
var handle: String
var team: String                 # "blue" / "red"
var role: String
var lane: String                 # "" for jungle
var character: Dictionary
var attrs: Dictionary

var pos: Vector2
var state: int = State.TO_LANE
var level := 1
var xp := 0.0
var cs := 0
var gold_total := 0.0            # earned overall (economy curves read this)
var gold_carried := 0.0          # spent on recall (buy trigger)
var item_power := 0.0

var _state_until := 0            # tick when CLEARING / RECALLING ends
var _camp_index := -1            # camp being targeted / cleared
var _speed_per_tick: float


func _init(player: Dictionary, p_team: String, p_character: Dictionary, base_pos: Vector2,
		starting_gold: float) -> void:
	id = player.id
	handle = player.handle
	team = p_team
	role = player.role
	lane = {"top": "top", "mid": "mid", "carry": "bot", "support": "bot"}.get(role, "")
	character = p_character
	attrs = player.attributes
	pos = base_pos
	gold_total = starting_gold
	gold_carried = 0.0  # starting gold is considered already spent on boots etc.
	item_power = starting_gold
	state = State.TO_CAMP if role == "jungle" else State.TO_LANE
	_speed_per_tick = float(p_character.base.speed) * SPEED_SCALE / SimMatch.TICKS_PER_SECOND


## m = the SimMatch (map, balance, rng, lanes, camps, emit_event). Not stored.
func update(t: int, m: SimMatch) -> void:
	_earn_passive(m)
	match state:
		State.TO_LANE:
			if _move_toward(m.lanes[lane].farm_pos(team)):
				state = State.FARMING
		State.FARMING:
			_move_toward(m.lanes[lane].farm_pos(team))
			_maybe_recall(t, m)
		State.TO_CAMP:
			_jungle_step(t, m)
		State.WAITING_CAMP:
			_jungle_step(t, m)
		State.CLEARING:
			if t >= _state_until:
				_finish_camp(t, m)
		State.RECALLING:
			if t >= _state_until:
				_finish_recall(t, m)


func is_farming_lane(lane_name: String) -> bool:
	return state == State.FARMING and lane == lane_name


func add_xp(t: int, amount: float, m: SimMatch) -> void:
	var xp_bal: Dictionary = m.balance.xp
	xp += amount
	while level < DataLoader.MAX_LEVEL and xp >= _level_cost(xp_bal):
		xp -= _level_cost(xp_bal)
		level += 1
		m.emit_event(t, "level_up", {"player": id, "level": level})


func earn(amount: float) -> void:
	gold_total += amount
	gold_carried += amount


func summary() -> Dictionary:
	return {
		"player": id, "handle": handle, "team": team, "role": role,
		"character": character.id, "level": level, "cs": cs,
		"gold": roundi(gold_total), "item_power": roundi(item_power),
	}


# --- internals ---------------------------------------------------------------

func _level_cost(xp_bal: Dictionary) -> float:
	return float(xp_bal.level_up_base) + (level - 1) * float(xp_bal.level_up_step)


func _earn_passive(m: SimMatch) -> void:
	var eco: Dictionary = m.balance.economy
	var per_tick: float = float(eco.passive_gold_per_s) / SimMatch.TICKS_PER_SECOND
	if role == "support":
		per_tick += float(eco.support_income_per_s) / SimMatch.TICKS_PER_SECOND
	earn(per_tick)


func _move_toward(target: Vector2) -> bool:
	var dist := pos.distance_to(target)
	if dist <= ARRIVE_DIST:
		return true
	pos = pos.move_toward(target, _speed_per_tick)
	return false


func _maybe_recall(t: int, m: SimMatch) -> void:
	var eco: Dictionary = m.balance.economy
	var threshold: float = float(eco.buy_threshold_base) + level * float(eco.buy_threshold_per_level)
	if gold_carried < threshold:
		return
	state = State.RECALLING
	_state_until = t + int(float(eco.recall_channel_s) * SimMatch.TICKS_PER_SECOND)
	m.emit_event(t, "recall_start", {"player": id})


func _finish_recall(t: int, m: SimMatch) -> void:
	pos = m.map.bases[team]
	item_power += gold_carried
	m.emit_event(t, "item_power_up", {"player": id, "spent": roundi(gold_carried)})
	gold_carried = 0.0
	state = State.TO_CAMP if role == "jungle" else State.TO_LANE


func _jungle_step(t: int, m: SimMatch) -> void:
	if state == State.TO_CAMP and gold_carried >= 0.0:
		var eco: Dictionary = m.balance.economy
		var threshold: float = float(eco.buy_threshold_base) + level * float(eco.buy_threshold_per_level)
		if gold_carried >= threshold:
			state = State.RECALLING
			_state_until = t + int(float(eco.recall_channel_s) * SimMatch.TICKS_PER_SECOND)
			m.emit_event(t, "recall_start", {"player": id})
			return
	_pick_camp(t, m)
	if _camp_index < 0:
		return
	var camp: Dictionary = m.camps[_camp_index]
	if _move_toward(camp.def.pos):
		if camp.alive:
			var jungle_bal: Dictionary = m.balance.jungle
			var jitter: int = m.rng.randi_range(
				-int(float(jungle_bal.clear_jitter_s) * SimMatch.TICKS_PER_SECOND),
				int(float(jungle_bal.clear_jitter_s) * SimMatch.TICKS_PER_SECOND))
			state = State.CLEARING
			_state_until = t + int(float(camp.def.clear_s) * SimMatch.TICKS_PER_SECOND) + jitter
		else:
			state = State.WAITING_CAMP


## Chooses the nearest alive own-side camp; if none is up, the one that
## respawns soonest (ties broken by array order — deterministic).
func _pick_camp(t: int, m: SimMatch) -> void:
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
