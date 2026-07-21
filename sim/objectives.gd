class_name Objectives
extends RefCounted
## Towers, nexus, Dragon and Baron: spawn timers, contests, sieges,
## destruction, team buffs. Owns the win condition state.

var m: SimMatch  # back-reference; cleared by SimMatch at end of run()

# towers[team][lane] = array of standing tower tiers, outermost first.
var towers := {}
var nexus_hp := {}
var winner := ""                 # set when a nexus falls

var dragon := {}                 # {alive, spawn_tick, stacks: {blue, red}}
var baron := {}                  # {alive, spawn_tick, buff_until: {blue, red}}
var _channel := {}               # objective -> {team, done_tick} while taking


func _init(match_ref: SimMatch) -> void:
	m = match_ref
	var bal: Dictionary = m.balance
	for team in SimMap.TEAMS:
		towers[team] = {}
		for lane in SimMap.LANES:
			towers[team][lane] = [
				{"tier": "outer", "hp": float(bal.towers.hp)},
				{"tier": "inner", "hp": float(bal.towers.hp)},
				{"tier": "base", "hp": float(bal.towers.hp)},
			]
		nexus_hp[team] = float(bal.towers.nexus_hp)
	dragon = {
		"alive": false,
		"spawn_tick": int(float(bal.objectives.dragon_first_spawn_s) * SimMatch.TICKS_PER_SECOND),
		"stacks": {"blue": 0, "red": 0},
	}
	baron = {
		"alive": false,
		"spawn_tick": int(float(bal.objectives.baron_first_spawn_s) * SimMatch.TICKS_PER_SECOND),
		"buff_until": {"blue": -1, "red": -1},
	}


## Current lane push bounds given standing towers, plus whether a tower (or
## the nexus turret) shreds waves pinned at each bound.
func lane_bounds(lane: String) -> Dictionary:
	return {
		"lo": _bound_for("blue", lane), "hi": _bound_for("red", lane),
		"shred_lo": true, "shred_hi": true,
	}


func team_buff(team: String) -> float:
	var bal: Dictionary = m.balance.objectives
	var buff: float = dragon.stacks[team] * float(bal.dragon_buff_per_stack)
	if baron.buff_until[team] >= 0 and m.now <= baron.buff_until[team]:
		buff += float(bal.baron_buff_power)
	return buff


func baron_active(team: String) -> bool:
	return baron.buff_until[team] >= 0 and m.now <= baron.buff_until[team]


func update(t: int) -> void:
	_update_pit(t, "dragon", dragon)
	_update_pit(t, "baron", baron)
	for lane in SimMap.LANES:
		_update_siege(t, lane, "blue")
		_update_siege(t, lane, "red")


## Where a team should rally for the current objective, or ZERO if none.
func objective_pos() -> Vector2:
	if baron.alive:
		return m.map.pits.baron
	if dragon.alive:
		return m.map.pits.dragon
	return Vector2.ZERO


func objective_soon(t: int) -> bool:
	var lead := 20 * SimMatch.TICKS_PER_SECOND
	return dragon.alive or baron.alive \
		or (dragon.spawn_tick >= 0 and t + lead >= dragon.spawn_tick) \
		or (baron.spawn_tick >= 0 and t + lead >= baron.spawn_tick)


# --- pits (dragon / baron) ---------------------------------------------------

func _update_pit(t: int, name: String, obj: Dictionary) -> void:
	if not obj.alive and obj.spawn_tick >= 0 and t >= obj.spawn_tick:
		obj.alive = true
		m.emit_event(t, "objective_spawn", {"objective": name})
	if not obj.alive or t % int(float(m.balance.objectives.decision_interval_s)
			* SimMatch.TICKS_PER_SECOND) != 0:
		return
	var pit: Vector2 = m.map.pits[name]
	var present := {"blue": [], "red": []}
	for agent in m.agents:
		if agent.alive and agent.state in [PlayerAgent.State.HOLDING, PlayerAgent.State.GROUPING] \
				and agent.pos.distance_to(pit) < 14.0:
			present[agent.team].append(agent)
	# You can start the objective with a squad here and the enemy not in a
	# position to contest — either absent, or already down to a man or two
	# because the fight around the pit went your way.
	var blue_ready: bool = present.blue.size() >= 3 and present.red.size() <= 1
	var red_ready: bool = present.red.size() >= 3 and present.blue.size() <= 1
	if not blue_ready and not red_ready and present.blue.size() >= 3 \
			and present.red.size() >= 3:
		# Contested: nobody gets a free take. The combat engine is already
		# fighting them over the pit; whoever is still standing here at the next
		# decision tick starts the channel.
		_channel.erase(name)
	elif blue_ready or red_ready:
		var team := "blue" if blue_ready else "red"
		if not _channel.has(name) or _channel[name].team != team:
			_channel[name] = {"team": team, "done_tick": t + int(
				float(m.balance.objectives.take_channel_s) * SimMatch.TICKS_PER_SECOND)}
		elif t >= _channel[name].done_tick:
			_channel.erase(name)
			_take(t, name, obj, team)
	else:
		_channel.erase(name)


func _take(t: int, name: String, obj: Dictionary, team: String) -> void:
	var bal: Dictionary = m.balance.objectives
	obj.alive = false
	if name == "dragon":
		obj.stacks[team] += 1
		obj.spawn_tick = t + int(float(bal.dragon_respawn_s) * SimMatch.TICKS_PER_SECOND)
		m.award_team(t, team, float(bal.dragon_gold_per_player), float(bal.dragon_xp_per_player))
		m.emit_event(t, "objective_taken", {
			"objective": "dragon", "team": team, "stacks": obj.stacks[team]})
	else:
		obj.buff_until[team] = t + int(float(bal.baron_duration_s) * SimMatch.TICKS_PER_SECOND)
		obj.spawn_tick = t + int(float(bal.baron_respawn_s) * SimMatch.TICKS_PER_SECOND)
		m.award_team(t, team, float(bal.baron_gold_per_player), float(bal.baron_xp_per_player))
		m.emit_event(t, "objective_taken", {"objective": "baron", "team": team})


# --- towers / nexus ----------------------------------------------------------

func _bound_for(team: String, lane: String) -> float:
	var standing: Array = towers[team][lane]
	if standing.is_empty():
		# Lane open to the nexus: front can push to just outside the base.
		return 0.06 if team == "blue" else 0.94
	return float(m.map.towers[team][standing[0].tier])


## `defender` owns the tower under threat on this lane.
func _update_siege(t: int, lane: String, defender: String) -> void:
	if winner != "":
		return
	var attacker := "red" if defender == "blue" else "blue"
	var lane_state: LaneState = m.lanes[lane]
	var bound := _bound_for(defender, lane)
	var pinned: bool = absf(lane_state.front_t - bound) < 0.005
	if not pinned:
		return
	var army: int = lane_state.minions[attacker] + lane_state.cannons[attacker]
	if army <= 0:
		return
	var bal: Dictionary = m.balance.towers
	var tower_pos := m.map.pos_on_lane(lane, bound)
	var attackers_here: Array = []
	var defenders_here: Array = []
	for agent in m.agents:
		if agent.alive and agent.pos.distance_to(tower_pos) < 12.0:
			(attackers_here if agent.team == attacker else defenders_here).append(agent)

	# A defended tower takes no player damage: the attackers are busy being
	# fought (the combat engine handles that), so only the wave chips away.
	var contested: bool = defenders_here.size() >= 2 \
		and defenders_here.size() >= attackers_here.size()
	var dps: float = army * float(bal.minion_dps)
	if not contested:
		for agent in attackers_here:
			dps += float(bal.player_base_dps) \
				* (1.0 + agent.item_power / float(m.balance.combat.power_item_divisor))
	if baron_active(attacker):
		dps *= float(m.balance.objectives.baron_siege_mult)

	var standing: Array = towers[defender][lane]
	if standing.is_empty():
		nexus_hp[defender] -= dps / SimMatch.TICKS_PER_SECOND
		if nexus_hp[defender] <= 0.0:
			winner = attacker
			m.emit_event(t, "nexus_destroyed", {"team": defender, "winner": attacker})
		return
	standing[0].hp -= dps / SimMatch.TICKS_PER_SECOND
	if standing[0].hp <= 0.0:
		var tier: String = standing[0].tier
		standing.pop_front()
		m.award_team(t, attacker, float(bal.gold_per_player), 0.0)
		m.emit_event(t, "tower_destroyed", {"team": defender, "lane": lane, "tier": tier})
