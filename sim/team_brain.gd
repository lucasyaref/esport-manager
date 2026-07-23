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
var _macro_cfg: Dictionary = {}      # balance.macro: pivot / span / floor_frac / ...
# The blackboard: calls a player posts for team-mates to read, keyed by name
# ("gank_bot"). A call names who to react and until when — macro decides who
# hears it (rolled once at post time, so it stays stable and deterministic).
var _calls: Dictionary = {}


func macro_avg() -> float:
	return _macro_avg


## The blend model (M5). Every team gets a deterministic BASELINE of coordination
## so it always reads as a team on screen; a roster's `macro` scales the quality
## and frequency on top. macro_gate() is the single place that shape lives: pass
## the probability an *average* roster (macro == pivot) should hit and how much a
## full `span` of extra macro lifts it, and get back a probability to roll
## against. Below-pivot rosters sink toward a floor (base * floor_frac) but never
## to zero — that floor is the "always reads as a team" guarantee. Above-pivot
## rosters climb toward `ceil_p`. The per-player version (gank reactors, roam
## decisions) shares the maths against one player's macro instead of the average.
func macro_gate(base: float, lift: float, ceil_p := 1.0) -> float:
	return macro_gate_of(_macro_avg, base, lift, ceil_p)


func macro_gate_of(macro: float, base: float, lift: float, ceil_p := 1.0) -> float:
	var p: float = base + lift * (macro - float(_macro_cfg.pivot)) / float(_macro_cfg.span)
	return clampf(p, base * float(_macro_cfg.floor_frac), ceil_p)


func _init(p_team: String, agents: Array, macro_cfg: Dictionary) -> void:
	team = p_team
	_macro_cfg = macro_cfg
	for agent: PlayerAgent in agents:
		if agent.team == team:
			_macro_avg += float(agent.attrs.macro)
	_macro_avg /= float(DataLoader.ROLES.size())


## Posts a gank call: the jungler is committing to `lane`, so team-mates should
## think about following up. Who actually reacts is rolled here, once, from each
## eligible laner's macro — a sharp player reads the play and collapses, a poor
## one keeps farming and the gank goes 1v1. This is macro made visible (Pillar 1).
func post_gank(t: int, lane: String, by_idx: int, until: int, m: SimMatch) -> void:
	var reactors: Array[int] = []
	var norm: float = float(m.balance.ganks.react_macro_norm)
	for agent in m.agents:
		if agent.team != team or agent.idx == by_idx or not agent.alive:
			continue
		if agent.role == "jungle":
			continue
		# Laners in the ganked lane collapse; a shoved-in mid may roam to it.
		var eligible: bool = agent.lane == lane \
			or (agent.role == "mid" and agent.lane_stance == "push")
		if eligible and m.rng.chance(float(agent.attrs.macro) / norm):
			reactors.append(agent.idx)
	_calls["gank_" + lane] = {"lane": lane, "by": by_idx, "until": until, "reactors": reactors}
	m.emit_event(t, "gank_call", {"team": team, "lane": lane,
		"by": m.agents[by_idx].id, "reactors": reactors.size()})


## Is `idx` a player who heard the active gank call on `lane`?
func gank_reactor(t: int, lane: String, idx: int) -> bool:
	var c: Dictionary = _calls.get("gank_" + lane, {})
	return not c.is_empty() and t <= int(c.until) and idx in c.reactors


## A lane with a live gank call this player should rotate to (for roams).
func gank_call_lane(t: int, idx: int) -> String:
	for key: String in _calls:
		var c: Dictionary = _calls[key]
		if t <= int(c.until) and idx in c.reactors:
			return c.lane
	return ""


func update(t: int, m: SimMatch) -> void:
	for key: String in _calls.keys():
		if t > int(_calls[key].until):
			_calls.erase(key)
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
		if intent == "group_objective" or m.rng.chance(_macro_avg / float(_macro_cfg.rotate_divisor)):
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


## Do we actually want this objective — fight for it, or give it up and trade?
## A team that is clearly weaker right now gives it up and takes the trade
## elsewhere (siege, defend, farm) rather than feeding a fight it cannot win.
## Without this both teams camp the pit forever, nobody sieges, and the game
## never ends. The judgement is gated on **vision**: a team that cannot see the
## pit is guessing at the enemy's strength, so it plays it safer (needs a
## clearer advantage before it commits blind). That is what makes a ward at the
## objective worth placing.
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
	if not m.vision_of(team, m.objectives.objective_pos()):
		read *= float(m.balance.fight.no_vision_caution)
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
