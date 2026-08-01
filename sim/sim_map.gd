class_name SimMap
extends RefCounted
## Runtime view of data/map.json: lane polylines with param<->position math,
## bases, towers, jungle camps. Static geometry only — mutable state (camp
## timers, lane fronts) lives in the match. Pure GDScript.

const LANES: Array[String] = ["top", "mid", "bot"]
const TEAMS: Array[String] = ["blue", "red"]

## How close to the edge of the world anything may stand. Terrain comes later;
## the outer boundary is not optional — steering is free 2D movement, so a
## player fleeing a fight follows the away-vector straight off the map.
const EDGE_MARGIN := 2.0

var size: float
var bases: Dictionary = {}        # team -> Vector2
var lane_paths: Dictionary = {}   # lane -> PackedVector2Array
var lane_lengths: Dictionary = {} # lane -> float
var towers: Dictionary = {}       # team -> {outer/inner/base: lane param}
var pits: Dictionary = {}         # dragon/baron -> Vector2
var camps: Array[Dictionary] = [] # copies of camp defs with pos as Vector2


func _init(map_data: Dictionary) -> void:
	size = float(map_data.size)
	for team in TEAMS:
		bases[team] = _vec(map_data.bases[team])
	towers = map_data.towers
	for lane in LANES:
		var path := PackedVector2Array()
		for pt in map_data.lanes[lane].path:
			path.append(_vec(pt))
		lane_paths[lane] = path
		var length := 0.0
		for i in range(path.size() - 1):
			length += path[i].distance_to(path[i + 1])
		lane_lengths[lane] = length
	for pit: String in map_data.pits:
		pits[pit] = _vec(map_data.pits[pit])
	for camp: Dictionary in map_data.camps:
		var c := camp.duplicate()
		c.pos = _vec(camp.pos)
		camps.append(c)


## Position at lane param t (0 = blue end, 1 = red end).
func pos_on_lane(lane: String, t: float) -> Vector2:
	var path: PackedVector2Array = lane_paths[lane]
	var remaining: float = clampf(t, 0.0, 1.0) * lane_lengths[lane]
	for i in range(path.size() - 1):
		var seg: float = path[i].distance_to(path[i + 1])
		if remaining <= seg:
			return path[i].lerp(path[i + 1], remaining / seg if seg > 0.0 else 0.0)
		remaining -= seg
	return path[path.size() - 1]


## Confines a position to the playable square. Every position write in the sim
## goes through here (PlayerAgent.move_to, teleports).
func clamp_pos(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, EDGE_MARGIN, size - EDGE_MARGIN),
		clampf(p.y, EDGE_MARGIN, size - EDGE_MARGIN))


## For batch-run assertions: nothing should ever be found outside the map.
func in_bounds(p: Vector2) -> bool:
	return p.x >= EDGE_MARGIN - 0.001 and p.x <= size - EDGE_MARGIN + 0.001 \
		and p.y >= EDGE_MARGIN - 0.001 and p.y <= size - EDGE_MARGIN + 0.001


## The lane a position sits on, by nearest sample of the three polylines. Plays
## that are called on a *spot* rather than on a lane — answering a fight, a
## collapse — still need a lane name for the call on the blackboard.
func nearest_lane(p: Vector2) -> String:
	var best: String = LANES[0]
	var best_d := INF
	for lane in LANES:
		for k in 24:
			var d := p.distance_to(pos_on_lane(lane, k / 23.0))
			if d < best_d:
				best_d = d
				best = lane
	return best


## Coarse place-name for a position: one of the three lanes, an objective pit,
## or the river/jungle between them. The reports and M6-A's reel text both name
## places, and they must name them the same way.
func region(p: Vector2, lane_radius := 6.0, pit_radius := 8.0) -> String:
	for pit: String in pits:
		if p.distance_to(pits[pit]) < pit_radius:
			return "pit"
	var best: String = LANES[0]
	var best_d := INF
	for lane in LANES:
		for k in 24:
			var d := p.distance_to(pos_on_lane(lane, k / 23.0))
			if d < best_d:
				best_d = d
				best = lane
	return best if best_d <= lane_radius else "river_jungle"


## Lane fronts can't push past the outer towers until sieging exists (M3).
func clamp_front(t: float) -> float:
	return clampf(t, float(towers.blue.outer), float(towers.red.outer))


static func _vec(pt: Array) -> Vector2:
	return Vector2(float(pt[0]), float(pt[1]))
