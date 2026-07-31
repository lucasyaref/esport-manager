class_name LaneState
extends RefCounted
## Minion simulation for one lane, as marching squads.
##
## A squad is a group of minions at a point on the lane: it spawns at its own
## base end, walks toward the enemy one, stops when it runs into an enemy squad
## (or a tower it cannot pass), and grinds that squad down. Friendly squads that
## catch a stalled one merge into it. Individual minions are never simulated —
## a squad carries counts — so a lane is a handful of moving points and 1000-sim
## batches stay cheap.
##
## The "front" is no longer a number that drifts: it is *derived* from where the
## leading squads meet, which is what makes pushing a physical consequence of
## winning the wave rather than a formula.

## How close two squads have to be to fight, in world units.
const CONTACT := 1.6

var lane: String
var front_t := 0.5
var minions := {"blue": 0, "red": 0}   # regular minions in the lane (derived)
var cannons := {"blue": 0, "red": 0}   # cannon minions (extra gold, die last)
var squads: Array[Dictionary] = []     # {team, t, melee_caster, cannon}

var _map: SimMap
var _bal: Dictionary                    # balance.minions section
var _kill_acc := {"blue": 0.0, "red": 0.0}  # fractional deaths owed per side
var _contact: float                     # CONTACT in lane-param units
var _step: float                        # lane param covered per tick at walk speed


func _init(lane_name: String, map: SimMap, minion_balance: Dictionary) -> void:
	lane = lane_name
	_map = map
	_bal = minion_balance
	var length: float = _map.lane_lengths[lane]
	_contact = CONTACT / length
	_step = float(_bal.speed) / length / SimMatch.TICKS_PER_SECOND


## One wave per side, spawned at each base. They walk from here.
func spawn_wave(_t: int, wave_index: int) -> void:
	var cannon := 1 if wave_index % int(_bal.cannon_every_n_waves) == 0 else 0
	for team in SimMap.TEAMS:
		squads.append({
			"team": team, "t": 0.0 if team == "blue" else 1.0,
			"melee_caster": int(_bal.melee_per_wave) + int(_bal.caster_per_wave),
			"cannon": cannon,
		})


## Advances one tick. pressure = extra kill rate applied per side from players
## farming this lane (their side pushes while they're present). bounds =
## {lo, hi, shred_lo, shred_hi} from Objectives — squads can't walk past a
## standing tower, and a squad pinned on one gets shredded by it.
## Returns deaths as [{team: side_of_dead_minion, cannon: bool}], in order.
func tick(_t: int, pressure: Dictionary, bounds: Dictionary) -> Array[Dictionary]:
	_advance(bounds)
	_merge()
	var deaths := _fight(pressure, bounds)
	_drop_empty()
	_derive_front(bounds)
	_recount()
	return deaths


func front_pos() -> Vector2:
	return _map.pos_on_lane(lane, front_t)


## Lane param a farming player of `team` holds: slightly behind the front.
## SimMatch.lane_stand_pos turns this into a position, pulling it back out of
## enemy tower range first.
func farm_t(team: String) -> float:
	return front_t + (-0.03 if team == "blue" else 0.03)


## [[team, lane_param, count], ...] for the snapshot the viewer draws from.
func squad_rows() -> Array:
	var rows := []
	for s in squads:
		rows.append([0 if s.team == "blue" else 1, s.t, s.melee_caster + s.cannon])
	return rows


# --- internals ---------------------------------------------------------------

## Walk toward the enemy base, stopping on contact with the leading enemy squad
## or at the tower line. Leads are read before anything moves, so the result
## does not depend on the order squads sit in the array.
func _advance(bounds: Dictionary) -> void:
	var blue_lead := _lead("blue")
	var red_lead := _lead("red")
	for s in squads:
		if s.team == "blue":
			var stop: float = minf(float(bounds.hi), red_lead - _contact)
			s.t = minf(s.t + _step, stop) if s.t < stop else s.t
		else:
			var stop: float = maxf(float(bounds.lo), blue_lead + _contact)
			s.t = maxf(s.t - _step, stop) if s.t > stop else s.t


## The furthest-advanced squad of a side — the one an enemy runs into. When a
## side has none, the answer is "past the far end", so nothing blocks anyone.
func _lead(team: String) -> float:
	var best := -INF if team == "blue" else INF
	for s in squads:
		if s.team != team or s.melee_caster + s.cannon == 0:
			continue
		best = maxf(best, s.t) if team == "blue" else minf(best, s.t)
	if is_inf(best):
		return -1.0 if team == "blue" else 2.0
	return best


## A wave that catches a stalled one joins it rather than stacking on top.
func _merge() -> void:
	for i in squads.size():
		var a: Dictionary = squads[i]
		for j in range(i + 1, squads.size()):
			var b: Dictionary = squads[j]
			if b.team != a.team or a.melee_caster + a.cannon == 0 \
					or b.melee_caster + b.cannon == 0:
				continue
			if absf(a.t - b.t) > _contact:
				continue
			# The leading one absorbs: it is the one already in the fight.
			var a_leads: bool = (a.t >= b.t) if a.team == "blue" else (a.t <= b.t)
			var lead: Dictionary = a if a_leads else b
			var rear: Dictionary = b if a_leads else a
			lead.melee_caster += rear.melee_caster
			lead.cannon += rear.cannon
			rear.melee_caster = 0
			rear.cannon = 0


## Attrition between the two leading squads where they meet, plus tower shred.
## Armies are snapshotted before any deaths apply, so the exchange is symmetric.
func _fight(pressure: Dictionary, bounds: Dictionary) -> Array[Dictionary]:
	var deaths: Array[Dictionary] = []
	var blue_front: Variant = _front_squad("blue")
	var red_front: Variant = _front_squad("red")
	var engaged: bool = blue_front != null and red_front != null \
		and absf(blue_front.t - red_front.t) <= _contact * 1.5
	var army := {
		"blue": 0 if blue_front == null else blue_front.melee_caster + blue_front.cannon,
		"red": 0 if red_front == null else red_front.melee_caster + red_front.cannon,
	}
	var rate: float = _bal.combat_kill_rate
	var tower_rate: float = _bal.tower_kill_rate
	for team in SimMap.TEAMS:
		var squad: Variant = blue_front if team == "blue" else red_front
		if squad == null:
			_kill_acc[team] = 0.0
			continue
		var opp := "red" if team == "blue" else "blue"
		# A wave pinned on the defender's own tower line, with no counter-wave left
		# to fight — the siege you walk home to break. Before, players contributed
		# nothing here (pressure was only read when two waves had collided), so a
		# wave grinding an undefended nexus was literally invulnerable to the five
		# players standing on it: the 2026-07-26 remark-5 bug, together with the
		# lane-assignment presence test fixed in SimMatch._tick_lane.
		var at_wall: bool = (squad.t >= float(bounds.hi) - 0.001) if team == "blue" \
			else (squad.t <= float(bounds.lo) + 0.001)
		if engaged:
			_kill_acc[team] += rate * float(army[opp]) + float(pressure[opp])
		elif at_wall:
			# The siege case, and the only one where raising the per-player weight
			# means "defenders sweep the wave off their own tower" rather than
			# "everybody pushes harder" — a contested lane goes through the
			# `engaged` branch above and is untouched by this multiplier.
			#
			# M5-F1 raised `presence_pressure` itself, which hits both branches, and
			# the win split moved 4 to 13 points non-monotonically because lane
			# equilibria are threshold-y. This dial is the narrow version of that
			# question: 1.0 is M5-F1's shipped behaviour exactly. Measured settings
			# and the fidelity-vs-balance trade are in REPORTS/M5-F1.md §4.
			_kill_acc[team] += float(pressure[opp]) * float(_bal.defend_pressure_mult)
		# A squad pinned against an enemy tower is shredded by it. This is the
		# counterforce that keeps armies bounded: without it any surplus
		# compounds forever, because kill rate scales with army size.
		if team == "blue" and bounds.shred_hi and squad.t >= float(bounds.hi) - 0.001:
			_kill_acc[team] += tower_rate
		elif team == "red" and bounds.shred_lo and squad.t <= float(bounds.lo) + 0.001:
			_kill_acc[team] += tower_rate
		while _kill_acc[team] >= 1.0 and squad.melee_caster + squad.cannon > 0:
			_kill_acc[team] -= 1.0
			if squad.melee_caster > 0:
				squad.melee_caster -= 1
				deaths.append({"team": team, "cannon": false})
			else:
				squad.cannon -= 1
				deaths.append({"team": team, "cannon": true})
		if squad.melee_caster + squad.cannon == 0:
			_kill_acc[team] = 0.0
	return deaths


func _front_squad(team: String) -> Variant:
	var best: Variant = null
	for s in squads:
		if s.team != team or s.melee_caster + s.cannon == 0:
			continue
		if best == null:
			best = s
		elif (s.t > best.t) if team == "blue" else (s.t < best.t):
			best = s
	return best


func _drop_empty() -> void:
	var kept: Array[Dictionary] = []
	for s in squads:
		if s.melee_caster + s.cannon > 0:
			kept.append(s)
	squads = kept


## The front is where the leading squads meet — or, if only one side has
## minions, wherever that side has pushed to.
func _derive_front(bounds: Dictionary) -> void:
	var blue: Variant = _front_squad("blue")
	var red: Variant = _front_squad("red")
	if blue != null and red != null:
		front_t = (blue.t + red.t) * 0.5
	elif blue != null:
		front_t = blue.t
	elif red != null:
		front_t = red.t
	front_t = clampf(front_t, float(bounds.lo), float(bounds.hi))


func _recount() -> void:
	for team in SimMap.TEAMS:
		minions[team] = 0
		cannons[team] = 0
	for s in squads:
		minions[s.team] += s.melee_caster
		cannons[s.team] += s.cannon
