class_name NavGrid
extends RefCounted
## Precomputed grid navigation for the sim (M6-T2). Bodies route around walls
## by following a flow field to the nearest cell of their destination region,
## instead of walking through rock.
##
## The field for every destination a body actually walks to — each lane, each
## jungle camp, each objective pit — is built once, here, when match data
## loads (SimMap.build_nav, called from DataLoader.load_all and shared by
## every match built from that data). Nothing in PlayerAgent does a per-tick
## or per-agent search: it is an O(1) array lookup (next_point) or a bounded
## line check (has_los). That is CLAUDE.md's determinism rule ("no per-agent
## search at runtime, and it stays deterministic") applied to movement.
##
## A hub is a named destination region — a set of seed cells: a whole lane's
## polyline for "lane_top" etc., a single cell for a camp or a pit. Multi-
## source BFS from those seeds gives every walkable cell a hop-distance to
## the nearest seed and a direction to step to shrink it by one — the
## standard flow-field / Dijkstra-map technique, cheap at this grid's size
## (50x50) even computed once per hub.
##
## What this does *not* cover, on purpose (REPORTS/M6-terrain-scoping.md §4):
## combat's own steering (PlayerAgent.desired_pos) skips it — a fight's stand
## position is a few units from where a body already is, inside the open
## pockets terrain leaves around a fight, not through rock. Per-body collision
## is still out of scope; this only keeps a body from walking through a wall
## on its way somewhere.

## N, S, W, E in a fixed order, so BFS tie-breaks (which neighbour a cell's
## flow direction points to, when more than one sits at the winning distance)
## are the same on every run — the determinism rule again.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const NO_DIR := 255  # "already in the hub's own region, or unreachable"

var terrain: Terrain
var _dist: Dictionary = {}      # hub id -> PackedInt32Array (hop count; -1 = unreached)
var _dir: Dictionary = {}       # hub id -> PackedByteArray (index into DIRS, or NO_DIR)
var _centroid: Dictionary = {}  # hub id -> Vector2, world centre of its seeds (nearest_hub)


## `hubs`: hub id -> Array[Vector2i] of seed cells (SimMap.build_nav assembles
## these from the lanes/camps/pits it already knows).
func _init(p_terrain: Terrain, hubs: Dictionary) -> void:
	terrain = p_terrain
	for hub_id: String in hubs:
		_build_field(hub_id, hubs[hub_id])


func _build_field(hub_id: String, seeds: Array) -> void:
	var n := terrain.n
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	var sum := Vector2.ZERO
	var count := 0
	for s: Vector2i in seeds:
		if not terrain.walkable_cell(s.x, s.y):
			continue  # a seed off walkable ground (bad data) just can't anchor the field
		sum += Vector2(s.x, s.y)
		count += 1
		var idx := s.y * n + s.x
		if dist[idx] != -1:
			continue
		dist[idx] = 0
		queue.append(s)
	_centroid[hub_id] = terrain.center_of(int(sum.x / count), int(sum.y / count)) \
		if count > 0 else Vector2.ZERO

	# Plain BFS via an index into the queue array (not pop_front, which is
	# O(n) per call in GDScript) — FIFO order is what makes `dist` an honest
	# shortest hop-count from the seed set.
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var d: int = dist[cell.y * n + cell.x]
		for delta in DIRS:
			var nb := cell + delta
			if nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
				continue
			var idx := nb.y * n + nb.x
			if dist[idx] != -1 or not terrain.walkable_cell(nb.x, nb.y):
				continue
			dist[idx] = d + 1
			queue.append(nb)

	# Second pass: each cell's direction is whichever fixed-order neighbour
	# sits exactly one hop closer. Cells at distance 0 (already in the hub)
	# or never reached both stay NO_DIR — the caller's cue to stop following
	# the field and steer directly instead.
	var dir := PackedByteArray()
	dir.resize(n * n)
	dir.fill(NO_DIR)
	for r in n:
		for c in n:
			var idx := r * n + c
			if dist[idx] <= 0:
				continue
			for di in DIRS.size():
				var nb := Vector2i(c, r) + DIRS[di]
				if nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
					continue
				if dist[nb.y * n + nb.x] == dist[idx] - 1:
					dir[idx] = di
					break
	_dist[hub_id] = dist
	_dir[hub_id] = dir


## World point one step closer to `hub_id`, or `from` unchanged once already
## inside the hub's own region or if the cell can't reach it at all — both
## cases mean "nothing left for the flow field to do; steer directly."
func next_point(hub_id: String, from: Vector2) -> Vector2:
	if not _dir.has(hub_id):
		return from
	var cell := terrain.cell_of(from)
	var idx := cell.y * terrain.n + cell.x
	var d: int = _dir[hub_id][idx]
	if d == NO_DIR:
		return from
	var nb: Vector2i = cell + DIRS[d]
	return terrain.center_of(nb.x, nb.y)


## Whether a straight line from a to b never crosses a wall cell. A bounded
## grid raycast (Bresenham), not a search: its cost is the number of cells the
## segment crosses, at most ~2x the grid side. Lets a body walking on open
## ground (most of the map, most of the time) skip the flow field entirely.
func has_los(a: Vector2, b: Vector2) -> bool:
	var ca := terrain.cell_of(a)
	var cb := terrain.cell_of(b)
	var x0 := ca.x
	var y0 := ca.y
	var x1 := cb.x
	var y1 := cb.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	# Bounded, not `while true`: a Bresenham walk between two cells on an NxN
	# grid never takes more than ~2N steps, and a hard cap keeps this a
	# provably-terminating loop rather than one that merely always has in
	# practice.
	for _step in terrain.n * 2 + 2:
		if not terrain.walkable_cell(x, y):
			return false
		if x == x1 and y == y1:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true  # unreachable in practice; a non-wall path found nothing blocking


## The known hub whose seed region sits closest to an arbitrary point. Used
## for the one destination with no hub of its own — a multi-man play's target
## is a live enemy position (TeamBrain._punish_target), not a lane/camp/pit.
## An O(hub count) scan over ~13 stored centroids, done once when the play is
## called (every few seconds per team), not per tick and not per agent.
func nearest_hub(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for hub_id: String in _centroid:
		var d: float = pos.distance_to(_centroid[hub_id])
		if d < best_d:
			best_d = d
			best = hub_id
	return best
