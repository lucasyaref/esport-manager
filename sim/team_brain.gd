class_name TeamBrain
extends RefCounted
## Per-team macro decisions after laning: group for objectives, siege, defend,
## or farm. Decision quality is driven by the roster's average macro attribute
## — low-macro teams react late to objective spawns (they fail the roll and
## keep farming for a few more seconds).

var team: String
var intent := "lane"        # lane / farm / group_objective / siege / defend
var rally := Vector2.ZERO
var target_lane := ""

var _macro_avg := 0.0


func macro_avg() -> float:
	return _macro_avg


func _init(p_team: String, agents: Array) -> void:
	team = p_team
	for agent: PlayerAgent in agents:
		if agent.team == team:
			_macro_avg += float(agent.attrs.macro)
	_macro_avg /= float(DataLoader.ROLES.size())


func update(t: int, m: SimMatch) -> void:
	if m.phase_of(t) == "early":
		intent = "lane"
		return
	var enemy := "red" if team == "blue" else "blue"
	var new_intent := "farm"
	var new_rally := Vector2.ZERO
	var new_lane := ""

	if m.objectives.objective_soon(t) and m.objectives.objective_pos() != Vector2.ZERO:
		# Macro gate: low-macro teams are slow to rotate. Once grouped, stay.
		if intent == "group_objective" or m.rng.chance(_macro_avg / 600.0):
			new_intent = "group_objective"
			new_rally = m.objectives.objective_pos()
	if new_intent == "farm":
		var siege_lane := _pushed_lane(m, enemy)
		var threat_lane := _pushed_lane(m, team)
		if siege_lane != "":
			new_intent = "siege"
			new_lane = siege_lane
			new_rally = m.map.pos_on_lane(siege_lane, m.objectives._bound_for(enemy, siege_lane))
		elif threat_lane != "":
			new_intent = "defend"
			new_lane = threat_lane
			new_rally = m.map.pos_on_lane(threat_lane, m.objectives._bound_for(team, threat_lane))

	intent = new_intent
	rally = new_rally
	target_lane = new_lane
	_apply(m)


## Lane whose front is pinned on `owner`'s tower line (their tower is under
## minion pressure) — the natural siege/defend target. Deepest pin wins.
func _pushed_lane(m: SimMatch, owner: String) -> String:
	var best := ""
	var best_depth := -1.0
	for lane in SimMap.LANES:
		var bound: float = m.objectives._bound_for(owner, lane)
		var lane_state: LaneState = m.lanes[lane]
		if absf(lane_state.front_t - bound) < 0.005:
			var enemy := "red" if owner == "blue" else "blue"
			var army: int = lane_state.minions[enemy] + lane_state.cannons[enemy]
			var depth := absf(bound - 0.5) * 10.0 + army
			if army > 0 and depth > best_depth:
				best_depth = depth
				best = lane
	return best


func _apply(m: SimMatch) -> void:
	for agent in m.agents:
		if agent.team != team or not agent.alive:
			continue
		match intent:
			"lane", "farm":
				agent.set_farming_intent()
			"group_objective", "siege", "defend":
				# The split-pusher (global TP ult) keeps pressuring a side
				# lane instead of grouping — unless the base is threatened.
				if intent != "defend" and _is_splitpusher(agent):
					agent.set_farming_intent()
				else:
					agent.set_grouping()


func _is_splitpusher(agent: PlayerAgent) -> bool:
	return agent.character.ultimate.effect == "global_teleport"
