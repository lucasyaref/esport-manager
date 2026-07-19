class_name SimMap
extends RefCounted
## Runtime view of data/map.json: lane polylines with param<->position math,
## bases, towers, jungle camps. Static geometry only — mutable state (camp
## timers, lane fronts) lives in the match. Pure GDScript.

const LANES: Array[String] = ["top", "mid", "bot"]
const TEAMS: Array[String] = ["blue", "red"]

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


## Lane fronts can't push past the outer towers until sieging exists (M3).
func clamp_front(t: float) -> float:
	return clampf(t, float(towers.blue.outer), float(towers.red.outer))


static func _vec(pt: Array) -> Vector2:
	return Vector2(float(pt[0]), float(pt[1]))
