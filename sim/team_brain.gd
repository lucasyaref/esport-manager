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
	"bot_mid_swap": {"top": "top", "mid": "bot", "carry": "mid", "support": "mid"},
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


## Objective-triggered lane swap (2026-07-25 reframe of item 4). The old version
## fired an OPENING swap at t=0, so both bot duos teleported top before minions —
## the designer's "botlane always goes top" bug. The real pro pattern is CAUSAL:
## focus bot with the jungler, take the enemy's bot outer (bot T1), and ONLY THEN
## rotate the bot duo onto a lane that still has a tower to snowball — top if the
## enemy's top outer stands, else mid. The team that wins bot first dictates the
## swap; the other reads it and matches so it is not left 2v1. Both rolls are
## macro-gated and one-shot, so a sharp roster rotates on its lead AND reliably
## answers an enemy rotation — that asymmetry is how a macro edge turns a bot-tower
## lead into a second tower (item 4).
func _consider_lane_swap(t: int, m: SimMatch) -> void:
	if formation != "standard":
		return  # committed to a rotation; hold it
	var mc: Dictionary = _macro_cfg
	var enemy := "red" if team == "blue" else "blue"
	# I took the enemy's bot outer -> rotate the bot duo onto a fresh tower.
	if not _swap_rolled and m.objectives.outer_down(enemy, "bot"):
		_swap_rolled = true
		var target := _rotation_target(enemy, m)
		if target != "" and m.rng.chance(macro_gate(float(mc.swap_base), float(mc.swap_lift))):
			set_formation("bot_top_swap" if target == "top" else "bot_mid_swap", t, m)
			return
	# The enemy rotated first -> match it so the map stays even (the answer).
	if not _mirror_rolled and m.brains[enemy].formation != "standard":
		_mirror_rolled = true
		if m.rng.chance(macro_gate(float(mc.mirror_base), float(mc.mirror_lift))):
			set_formation(m.brains[enemy].formation, t, m)


## Which lane the bot duo rotates to after taking the enemy's bot outer: top if
## the enemy's top outer still stands (a fresh tower to snowball), else mid, else
## none — both side outers already gone, nothing to rotate onto, so just group.
func _rotation_target(enemy: String, m: SimMatch) -> String:
	if not m.objectives.outer_down(enemy, "top"):
		return "top"
	if not m.objectives.outer_down(enemy, "mid"):
		return "mid"
	return ""


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
	# Objective-triggered now: fires whenever bot T1 has fallen (usually mid game),
	# so it runs every tick and self-limits, not just during laning.
	_consider_lane_swap(t, m)
	if m.phase_of(t) == "early":
		intent = "lane"
		return
	var enemy := "red" if team == "blue" else "blue"
	var new_intent := "farm"
	var new_rally := Vector2.ZERO
	var new_lane := ""
	var home_lane := _pushed_lane(m, team)

	# 1. Home in danger (2026-07-25 remark 6): a DEEP tower of ours (inner/base or
	#    the nexus) is under real minion+player pressure. Defending it outranks any
	#    siege or objective — you cannot trade a baron for your own nexus. This is
	#    the "nobody protects the base" fix; a shallow (outer) threat stays the
	#    lower-priority defend below.
	if home_lane != "" and _is_deep_threat(m, home_lane):
		new_intent = "defend"
		new_lane = home_lane
		new_rally = m.map.pos_on_lane(home_lane, m.objectives._bound_for(team, home_lane))

	if new_intent == "farm" and m.objectives.objective_soon(t) \
			and m.objectives.objective_pos() != Vector2.ZERO and _will_contest(t, m):
		# Macro gate: low-macro teams are slow to rotate. Once grouped, stay.
		if intent == "group_objective" or m.rng.chance(_macro_avg / float(_macro_cfg.rotate_divisor)):
			new_intent = "group_objective"
			new_rally = m.objectives.objective_pos()

	# 2. Punish an over-extended, isolated enemy caught on our side of the map
	#    (2026-07-25 remark 6). GATED OFF in M5-D (defense.punish_base/lift = 0):
	#    measured, a blunt team-wide collapse drags the macro team (it rolls the
	#    gate more, over-commits, and gets caught). M5-F enables and tunes it as a
	#    committed multi-man pick (subset + window), the right vehicle. Wired now so
	#    M5-F only turns the dial. Base defense (step 1) is remark 6's shipped half.
	if new_intent == "farm":
		var punish := _punish_target(t, m)
		if punish != Vector2.ZERO:
			new_intent = "collapse"
			new_rally = punish

	if new_intent == "farm":
		var siege_lane := _pushed_lane(m, enemy)
		if siege_lane != "":
			new_intent = "siege"
			new_lane = siege_lane
			new_rally = m.map.pos_on_lane(siege_lane, m.objectives._bound_for(enemy, siege_lane))
		elif home_lane != "":
			new_intent = "defend"
			new_lane = home_lane
			new_rally = m.map.pos_on_lane(home_lane, m.objectives._bound_for(team, home_lane))

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


## A deep tower of ours (inner/base, or the lane open to the nexus) is the one
## pinned on this lane — losing it is game-threatening, so defending it outranks
## a siege or an objective. Shallow (outer) pressure is a lower-priority defend.
func _is_deep_threat(m: SimMatch, lane: String) -> bool:
	var bound: float = m.objectives._bound_for(team, lane)
	var edge: float = float(m.balance.defense.deep_threat_bound)
	return bound <= edge if team == "blue" else bound >= 1.0 - edge


## An enemy caught over-extended and ALONE on our half of the map, where enough
## of ours can reach to make it a pick — the position to collapse on (remark 6).
## ZERO when there is nothing worth punishing. One macro-gated roll, latched via
## the `collapse` intent so it does not re-roll every tick: a sharp roster spots
## and converts the pick, a weak one lets it walk.
func _punish_target(_t: int, m: SimMatch) -> Vector2:
	var enemy := "red" if team == "blue" else "blue"
	var d: Dictionary = m.balance.defense
	var best := Vector2.ZERO
	var best_depth := 0.0
	for foe in m.agents:
		if foe.team != enemy or not foe.alive:
			continue
		var depth: float = _side_depth(foe.pos, m)
		if depth < float(d.punish_deep):
			continue
		if _has_ally_near(m, enemy, foe, float(d.punish_isolation_radius)):
			continue  # not isolated — help is close
		var collapsers := 0
		for mate in m.agents:
			if mate.team == team and mate.alive \
					and mate.pos.distance_to(foe.pos) < float(d.punish_collapse_radius):
				collapsers += 1
		if collapsers < int(d.punish_min_collapsers):
			continue
		if depth > best_depth:
			best_depth = depth
			best = foe.pos
	if best == Vector2.ZERO:
		return Vector2.ZERO
	if intent == "collapse" or m.rng.chance(macro_gate(float(d.punish_base), float(d.punish_lift))):
		return best
	return Vector2.ZERO


func _has_ally_near(m: SimMatch, side: String, of: PlayerAgent, radius: float) -> bool:
	for mate in m.agents:
		if mate.team == side and mate.idx != of.idx and mate.alive \
				and mate.pos.distance_to(of.pos) < radius:
			return true
	return false


## How deep `pos` sits on OUR side of the map: 1 at our base, 0 at the midline or
## beyond. An over-extended enemy near our base scores high.
func _side_depth(pos: Vector2, m: SimMatch) -> float:
	var base: Vector2 = m.map.bases[team]
	var enemy_base: Vector2 = m.map.bases["red" if team == "blue" else "blue"]
	var half := base.distance_to(enemy_base) * 0.5
	return clampf(1.0 - pos.distance_to(base) / half, 0.0, 1.0) if half > 0.0 else 0.0


func _apply(t: int, m: SimMatch) -> void:
	for agent in m.agents:
		if agent.team != team or not agent.alive:
			continue
		match intent:
			"lane", "farm":
				agent.set_farming_intent()
			"group_objective", "siege", "defend", "collapse":
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
