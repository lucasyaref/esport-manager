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

# --- lane assignment (M5-B): the lane swap as a team STATE ------------------
# A formation is a role->lane map; `standard` is the default 1-1-2. A swap is a
# transition to a different map — `bot_top_swap` sends the bot duo to top and the
# top solo to bot (the classic opening swap). Holding it as state is what makes a
# swap read on screen and lets the enemy DETECT it and mirror. Kept as a table so
# mid-collapse / 1-3-1 are just more entries later, no new machinery.
const FORMATIONS := {
	"standard":     {"top": "top", "mid": "mid", "carry": "bot", "support": "bot"},
	"bot_top_swap": {"top": "bot", "mid": "mid", "carry": "top", "support": "top"},
}
var formation := "standard"
var _swap_rolled := false     # the one-time "do we open swapped?" roll happened
var _mirror_rolled := false   # the one-time "enemy swapped, match it?" roll happened

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


## Transition to a formation, rewriting each laner's home lane. Because `lane`
## (not `role`) is what drives where a player farms and stands, this is all the
## swap needs — done at t=0 the laners route to the swapped lanes from the
## fountain, so it reads as an opening swap. No RNG here: deterministic.
func set_formation(new_formation: String, t: int, m: SimMatch) -> void:
	if new_formation == formation:
		return
	formation = new_formation
	var mapping: Dictionary = FORMATIONS[formation]
	for agent in m.agents:
		if agent.team == team and mapping.has(agent.role):
			agent.lane = mapping[agent.role]
	m.emit_event(t, "lane_swap", {"team": team, "formation": formation})


## The opening lane-swap decision (M5-B), run each brain tick but self-limiting:
## the initiate roll fires once (at t=0, before minions, so the swap is an
## opening), and the mirror roll fires once, when a standard team first sees the
## enemy swapped. Both are macro-gated through the blend primitive — a sharp
## roster sets up the 2v1 and, crucially, is rarely the one left 1v2, because it
## reliably reads and matches an enemy swap. That asymmetry is the point: it is
## how a macro edge turns into an early tower and a gold swing (item 4).
func _consider_lane_swap(t: int, m: SimMatch) -> void:
	var mc: Dictionary = _macro_cfg
	if not _swap_rolled:
		_swap_rolled = true
		if m.rng.chance(macro_gate(float(mc.swap_base), float(mc.swap_lift))):
			set_formation("bot_top_swap", t, m)
	if formation == "standard" and not _mirror_rolled:
		var enemy := "red" if team == "blue" else "blue"
		if m.brains[enemy].formation == "bot_top_swap":
			_mirror_rolled = true
			if m.rng.chance(macro_gate(float(mc.mirror_base), float(mc.mirror_lift))):
				set_formation("bot_top_swap", t, m)


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
		_consider_lane_swap(t, m)
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
