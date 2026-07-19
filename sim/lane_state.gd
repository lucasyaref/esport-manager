class_name LaneState
extends RefCounted
## Minion simulation for one lane, modeled as a "front": a contact point that
## drifts along the lane param [0..1] plus aggregate minion counts per side.
## Individual minions are not simulated — waves travel to the front as timed
## reinforcements, armies grind each other down, and each discrete minion
## death is reported so the match can award CS gold and XP.

var lane: String
var front_t := 0.5
var minions := {"blue": 0, "red": 0}   # regular minions at the front
var cannons := {"blue": 0, "red": 0}   # cannon minions (extra gold, die last)

var _map: SimMap
var _bal: Dictionary                    # balance.minions section
var _incoming: Array[Dictionary] = []   # {tick, team, melee_caster, cannon}
var _kill_acc := {"blue": 0.0, "red": 0.0}  # fractional deaths owed per side


func _init(lane_name: String, map: SimMap, minion_balance: Dictionary) -> void:
	lane = lane_name
	_map = map
	_bal = minion_balance


## Queues one wave per side; arrival delayed by travel from base to the front.
func spawn_wave(t: int, wave_index: int) -> void:
	var cannon := 1 if wave_index % int(_bal.cannon_every_n_waves) == 0 else 0
	for team in SimMap.TEAMS:
		var spawn_t := 0.0 if team == "blue" else 1.0
		var dist: float = _map.lane_lengths[lane] * absf(front_t - spawn_t)
		var travel_ticks := int(dist / float(_bal.speed) * SimMatch.TICKS_PER_SECOND)
		_incoming.append({
			"tick": t + travel_ticks, "team": team,
			"melee_caster": int(_bal.melee_per_wave) + int(_bal.caster_per_wave),
			"cannon": cannon,
		})


## Advances one tick. pressure = extra kill rate applied per side from players
## farming this lane (their side pushes while they're present).
## Returns deaths as [{team: side_of_dead_minion, cannon: bool}], in order.
func tick(t: int, pressure: Dictionary) -> Array[Dictionary]:
	var arrived: Array[Dictionary] = []
	for wave in _incoming:
		if wave.tick <= t:
			minions[wave.team] += wave.melee_caster
			cannons[wave.team] += wave.cannon
			arrived.append(wave)
	for wave in arrived:
		_incoming.erase(wave)

	var deaths: Array[Dictionary] = []
	var rate: float = _bal.combat_kill_rate
	# Armies snapshotted before any deaths apply, so combat is symmetric —
	# processing one side first must not shield it from full return damage.
	var army := {
		"blue": minions.blue + cannons.blue,
		"red": minions.red + cannons.red,
	}
	# Tower attrition: a wave pinned against an enemy tower gets shredded by
	# it. This is the counterforce that keeps armies bounded — without it, any
	# army surplus compounds forever (kill rate scales with army size).
	var tower_rate: float = _bal.tower_kill_rate
	var at_blue_tower := front_t <= float(_map.towers.blue.outer) + 0.001
	var at_red_tower := front_t >= float(_map.towers.red.outer) - 0.001
	for team in SimMap.TEAMS:
		var opp := "red" if team == "blue" else "blue"
		var opp_army: float = army[opp]
		_kill_acc[team] += rate * opp_army + float(pressure[opp])
		if (team == "red" and at_blue_tower) or (team == "blue" and at_red_tower):
			_kill_acc[team] += tower_rate
		while _kill_acc[team] >= 1.0 and minions[team] + cannons[team] > 0:
			_kill_acc[team] -= 1.0
			if minions[team] > 0:
				minions[team] -= 1
				deaths.append({"team": team, "cannon": false})
			else:
				cannons[team] -= 1
				deaths.append({"team": team, "cannon": true})
		if minions[team] + cannons[team] == 0:
			_kill_acc[team] = 0.0

	front_t = _map.clamp_front(front_t + float(_bal.front_drift) * (
		minions.blue + cannons.blue - minions.red - cannons.red))
	return deaths


func front_pos() -> Vector2:
	return _map.pos_on_lane(lane, front_t)


## Where a farming player of `team` stands: slightly behind the front.
func farm_pos(team: String) -> Vector2:
	var offset := -0.03 if team == "blue" else 0.03
	return _map.pos_on_lane(lane, front_t + offset)
