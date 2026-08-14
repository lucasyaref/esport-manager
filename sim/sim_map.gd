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
var towers: Dictionary = {}       # team -> {tier name: lane param}
var tier_order: Dictionary = {}   # team -> [tier names], outermost first
var pits: Dictionary = {}         # dragon/baron -> Vector2
var camps: Array[Dictionary] = [] # copies of camp defs with pos as Vector2
## Both null until DataLoader.load_all attaches them (M6-T2). Built once, from
## data/terrain.txt, and shared by every SimMap constructed from the same map
## data — never rebuilt per match, let alone per agent or per tick.
var terrain: Terrain = null
var nav: NavGrid = null


func _init(map_data: Dictionary) -> void:
	size = float(map_data.size)
	for team in TEAMS:
		bases[team] = _vec(map_data.bases[team])
	towers = map_data.towers
	for team in TEAMS:
		tier_order[team] = _tiers_outermost_first(team)
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


## A team's tower tiers, outermost first — derived from the lane params rather
## than hardcoded, so `data/map.json` alone decides how many towers a lane has.
## Lane param 0 is the blue end and 1 the red end, so "furthest from home" is the
## largest param for blue and the smallest for red. Sorting by name would be a
## trap: the names are labels, and a designer adding a "mid" tier between two
## others must not have to think about alphabetical order to place it.
func _tiers_outermost_first(team: String) -> Array:
	var tiers: Array = towers[team].keys()
	tiers.sort()  # stable, deterministic starting order before the param sort
	tiers.sort_custom(func(a: String, b: String) -> bool:
		var pa := float(towers[team][a])
		var pb := float(towers[team][b])
		return pa > pb if team == "blue" else pa < pb)
	return tiers


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


## Builds the flow-field navigation for every destination a body actually
## walks to (M6-T2): each lane treated as one region (every cell its
## polyline crosses, so "walk to top" routes to the nearest point ON that
## lane), each camp and each pit as a single cell. Called once, from
## DataLoader.load_all, and shared by every SimMap built from the same map
## data — see NavGrid's own doc comment for why that matters.
func build_nav(p_terrain: Terrain) -> NavGrid:
	var hubs: Dictionary = {}
	for lane in LANES:
		var seeds: Array[Vector2i] = []
		# Dense enough to hit every cell a 2-unit-per-cell polyline crosses;
		# duplicate seeds just re-mark the same cell at distance 0, harmless.
		var samples: int = maxi(p_terrain.n * 2, 64)
		for k in samples:
			seeds.append(p_terrain.cell_of(pos_on_lane(lane, float(k) / float(samples - 1))))
		hubs["lane_" + lane] = seeds
	for pit: String in pits:
		hubs["pit_" + pit] = [p_terrain.cell_of(pits[pit]) as Vector2i] as Array[Vector2i]
	for camp: Dictionary in camps:
		hubs["camp_%s" % camp.id] = [p_terrain.cell_of(camp.pos) as Vector2i] as Array[Vector2i]
	return NavGrid.new(p_terrain, hubs)
