class_name Objectives
extends RefCounted
## Towers, nexus, Dragon and Baron: spawn timers, contests, sieges,
## destruction, team buffs. Owns the win condition state.

var m: SimMatch  # back-reference; cleared by SimMatch at end of run()

# towers[team][lane] = array of standing tower tiers, outermost first.
var towers := {}
var nexus_hp := {}
var winner := ""                 # set when a nexus falls
var first_tower_taken := false   # first-blood tower gives a one-off bonus swing

var tower_damage := {"blue": 0.0, "red": 0.0}  # dealt by each side's towers (stats)

var dragon := {}                 # {alive, spawn_tick, stacks: {blue, red}}
var baron := {}                  # {alive, spawn_tick, buff_until: {blue, red}}
var _channel := {}               # objective -> {team, done_tick} while taking


func _init(match_ref: SimMatch) -> void:
	m = match_ref
	var bal: Dictionary = m.balance
	for team in SimMap.TEAMS:
		towers[team] = {}
		for lane in SimMap.LANES:
			var standing: Array = []
			for tier: String in m.map.tier_order[team]:
				standing.append({
					"tier": tier, "hp": float(bal.towers.hp),
					"pos": m.map.pos_on_lane(lane, float(m.map.towers[team][tier])),
				})
			towers[team][lane] = standing
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
	_update_tower_threat(t)


## True if `pos` sits under a standing enemy tower of `team`. Read by the combat
## engine before it chases someone home.
func under_enemy_tower(team: String, pos: Vector2) -> bool:
	var enemy := "red" if team == "blue" else "blue"
	var reach := float(m.balance.towers.range)
	for lane in SimMap.LANES:
		for tower: Dictionary in towers[enemy][lane]:
			if pos.distance_to(tower.pos) <= reach:
				return true
	return false


## Has `team`'s outer tower on `lane` fallen? The objective-triggered lane swap
## reads this: taking the enemy's bot outer is what cues the bot duo to rotate
## (2026-07-25 designer model — take bot T1 first, then swap).
func outer_down(team: String, lane: String) -> bool:
	var standing: Array = towers[team][lane]
	return standing.is_empty() or str(standing[0].tier) != "outer"


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
			"objective": "dragon", "team": team, "stacks": obj.stacks[team],
			"pos": [m.map.pits.dragon.x, m.map.pits.dragon.y]})
	else:
		obj.buff_until[team] = t + int(float(bal.baron_duration_s) * SimMatch.TICKS_PER_SECOND)
		obj.spawn_tick = t + int(float(bal.baron_respawn_s) * SimMatch.TICKS_PER_SECOND)
		m.award_team(t, team, float(bal.baron_gold_per_player), float(bal.baron_xp_per_player))
		m.emit_event(t, "objective_taken", {"objective": "baron", "team": team,
			"pos": [m.map.pits.baron.x, m.map.pits.baron.y]})


# --- towers / nexus ----------------------------------------------------------

## Towers shoot back. Until now they only ever *received* damage, so nothing on
## the map punished a dive and a chase could run all the way into the enemy
## base for free (M4.5-B playtest).
func _update_tower_threat(t: int) -> void:
	var bal: Dictionary = m.balance.towers
	var dps: float = float(bal.player_dps) / SimMatch.TICKS_PER_SECOND
	for defender in SimMap.TEAMS:
		for lane in SimMap.LANES:
			for tower: Dictionary in towers[defender][lane]:
				var victim := _tower_target(t, defender, lane, tower.pos)
				if victim != null:
					m.combat.tower_damage(t, defender, tower.pos, victim, dps)
					tower_damage[defender] += dps


## LoL aggro, in priority order: a player attacking one of ours inside the zone
## takes the shot immediately (that is what makes a dive cost something), else
## the wave holds aggro if there is one, else the nearest enemy player.
func _tower_target(t: int, defender: String, lane: String, tower_pos: Vector2) -> PlayerAgent:
	var reach := float(m.balance.towers.range)
	var attacker := "red" if defender == "blue" else "blue"
	var in_range: Array[PlayerAgent] = []
	for agent in m.agents:
		if agent.alive and agent.team == attacker and agent.pos.distance_to(tower_pos) <= reach:
			in_range.append(agent)
	if in_range.is_empty():
		return null

	var window := int(float(m.balance.towers.aggro_window_s) * SimMatch.TICKS_PER_SECOND)
	for agent in in_range:
		if agent.target_idx < 0 or t - agent.last_hit_at > window:
			continue
		var victim: PlayerAgent = m.agents[agent.target_idx]
		if victim.team == defender and victim.pos.distance_to(tower_pos) <= reach:
			return agent

	var lane_state: LaneState = m.lanes[lane]
	if lane_state.minions[attacker] + lane_state.cannons[attacker] > 0 \
			and lane_state.front_pos().distance_to(tower_pos) <= reach:
		return null  # busy with the wave

	var nearest: PlayerAgent = in_range[0]
	for agent in in_range:
		if agent.pos.distance_to(tower_pos) < nearest.pos.distance_to(tower_pos):
			nearest = agent
	return nearest


## Turret plating, abstracted. In the real game a tower is armoured by plates
## until 14:00, which is why a pro first tower falls around 11–14 min; our 200-sim
## baseline had it at 5.6, and an early game where towers fall to the first shove
## has nothing left to play for (2026-07-26 remarks 2 and 6). So a tower takes
## `plating_reduction` less damage at minute zero, easing to none by
## `plating_until_s`. Both data values; set the reduction to 0 to switch it off.
func _plating_mult(t: int) -> float:
	var bal: Dictionary = m.balance.towers
	var until: float = float(bal.plating_until_s) * SimMatch.TICKS_PER_SECOND
	if until <= 0.0:
		return 1.0
	return 1.0 - float(bal.plating_reduction) * clampf((until - t) / until, 0.0, 1.0)


func _bound_for(team: String, lane: String) -> float:
	var standing: Array = towers[team][lane]
	if standing.is_empty():
		# Lane open to the nexus: the wave walks all the way to the base and grinds
		# it down from there. It used to stop at 0.06/0.94 — 11 to 14 world units
		# short of the nexus, an eighth of the map — so a nexus visibly fell with
		# the enemy wave nowhere near it ("no enemy hitting nexus, too far from
		# it", 2026-07-25 playtest; confirmed 2026-07-26). Data-tunable because it
		# is also how fast a won lane converts into a win.
		var doorstep: float = float(m.balance.towers.open_lane_front)
		return doorstep if team == "blue" else 1.0 - doorstep
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
	dps *= _plating_mult(t)

	var standing: Array = towers[defender][lane]
	if standing.is_empty():
		nexus_hp[defender] -= dps / SimMatch.TICKS_PER_SECOND
		# The nexus is being hit: say so, with who is home. The designer's remark
		# ("blue left the nexus undefended while minions pushed", 2026-07-26) is a
		# claim about defender counts, so the sim states them and the batch run
		# measures them instead of anyone having to watch for it. Sim-inert.
		if t % (2 * SimMatch.TICKS_PER_SECOND) == 0:
			m.emit_event(t, "nexus_pressure", {
				"team": defender, "lane": lane, "hp": roundi(nexus_hp[defender]),
				"defenders": defenders_here.size(), "attackers": attackers_here.size(),
				"army": army})
		if nexus_hp[defender] <= 0.0:
			winner = attacker
			m.emit_event(t, "nexus_destroyed", {"team": defender, "winner": attacker,
				"pos": [m.map.bases[defender].x, m.map.bases[defender].y]})
		return
	standing[0].hp -= dps / SimMatch.TICKS_PER_SECOND
	if standing[0].hp <= 0.0:
		var tier: String = standing[0].tier
		var where: Vector2 = standing[0].pos
		standing.pop_front()
		m.award_team(t, attacker, float(bal.gold_per_player), 0.0)
		# First tower of the match is a real swing — the tempo a coordinated
		# team's lane swap / dive is racing for (M5-B, item 4).
		var is_first: bool = not first_tower_taken
		if is_first:
			first_tower_taken = true
			m.award_team(t, attacker, float(bal.first_tower_bonus_per_player), 0.0)
		m.emit_event(t, "tower_destroyed", {
			"team": defender, "lane": lane, "tier": tier, "first": is_first,
			"pos": [where.x, where.y]})
