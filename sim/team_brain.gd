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

	if m.objectives.objective_soon(t) and m.objectives.objective_pos() != Vector2.ZERO \
			and _will_contest(t, m):
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
	_apply(t, m)


## Do we actually want this objective? A team that is clearly the weaker side
## right now gives it up and takes the trade elsewhere (siege, defend, farm)
## rather than feeding a fight it cannot win. Without this both teams camp the
## pit forever, nobody sieges, and the game never ends.
func _will_contest(t: int, m: SimMatch) -> bool:
	var mine := 0.0
	var theirs := 0.0
	for agent in m.agents:
		if not agent.alive:
			continue
		var power: float = m.combat.threat(agent, t) * agent.hp_fraction()
		if agent.team == team:
			mine += power
		else:
			theirs += power
	# Reading the enemy's strength correctly is a macro skill: a sharp team
	# judges the contest well, a weak one talks itself into bad fights.
	var read: float = float(m.balance.fight.contest_margin) \
		- (_macro_avg - 70.0) / float(m.balance.fight.contest_macro_divisor)
	return mine >= theirs * read


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


func _apply(t: int, m: SimMatch) -> void:
	for agent in m.agents:
		if agent.team != team or not agent.alive:
			continue
		match intent:
			"lane", "farm":
				agent.set_farming_intent()
			"group_objective", "siege", "defend":
				# The split-pusher (global TP ult) keeps pressuring a side lane
				# instead of grouping — unless the base is threatened, or the
				# teleport is up, in which case it pays to be in two places.
				if intent != "defend" and _is_splitpusher(agent):
					if rally != Vector2.ZERO and m.teleport_to(agent, rally, t):
						agent.set_grouping()
					else:
						agent.set_farming_intent()
				else:
					agent.set_grouping()


func _is_splitpusher(agent: PlayerAgent) -> bool:
	return agent.character.ultimate.effect == "global_teleport"
