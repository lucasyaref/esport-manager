extends SceneTree
## Moves a *feature* of the map — a pit, a base, a lane — and repaints the cells
## around it, keeping data/terrain.txt and data/map.json saying the same thing.
##
## The lesson this tool exists to encode was learned the hard way at iteration 11.
## Four attempts to edit data/terrain.txt directly all failed, because a lane band
## is not a set of rows and columns: it is a distance field around a path. Move the
## path and repaint everything within half-width of it, and the picture and the sim
## stay in agreement *by construction* rather than by hand. Same for a pit, which is
## a disc around a point, and a base, which is a blob anchored to a corner.
##
## So every mode here does the same two things in the same order: change the number
## in map.json, then repaint the cells that number owns. Neither half is edited
## alone, which is what stops criterion E — "the lanes drawn are the lanes the
## minions walk" — from drifting.
##
## Usage:
##   godot --headless --path . --script res://tools/terrain_paint.gd -- --pits=10 [--write]
##   godot --headless --path . --script res://tools/terrain_paint.gd -- --bases=4 [--write]
##   godot --headless --path . --script res://tools/terrain_paint.gd -- --lanes [--write]
##
##   --pits=D    slide both pits D world units along the river's perpendicular, so
##               the channel runs past them instead of into them.
##   --bases=K   pull both base footprints, their nexus and their lane mouths K
##               cells in from the map edge.
##   --lanes     re-rasterise the lane bands from the polylines in map.json.
##   --write     apply. Without it, a dry run that reports what would change.
##
## Every mode re-reads what it wrote and re-runs the full guard rails, and prints
## the river's connected-component sizes, which is the thing --pits exists to fix.

const TERRAIN_PATH := "res://data/terrain.txt"
const MAP_PATH := "res://data/map.json"

## Measured off the map itself, not chosen: river cells span +-4.2 world units
## either side of the axis, and the hand-authored pits were 32 cells each.
const RIVER_HALF := 4.5
## 7.0 rather than the 5.7 the old bowls measured, because a disc rasterised at
## 5.7 and then de-spiked came out a 25-cell square. At 7.0 it lands on a 35-cell
## octagon, which is both the original footprint and an actual bowl shape.
const PIT_RADIUS := 7.0
## How far a camp's own cells lie from the position map.json records for it. The
## eight camps average 6 cells each, so this only has to be wide enough to gather
## one cluster and narrow enough not to reach its neighbour.
const CAMP_RADIUS := 5.0
## Half-width of a lane band. 4.4 rather than iteration 11's nominal 3.6: the
## hand-authored band was wider than its own spec in places, and re-rasterising at
## 3.6 shed 78 lane cells, thinning every road and leaving a green fringe where the
## drawn lane used to reach. 4.4 reproduces the original weight.
const LANE_HALF := 4.4
## The river runs along x + y = size. Both pits sat exactly on it, which is why
## the water arrived at each bowl and started again on the far side.
func _perp(p: Vector2, size: float) -> float:
	return (p.x + p.y - size) / sqrt(2.0)


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			args[parts[0]] = parts[1]
		else:
			args[stripped] = "true"

	var errors: Array[String] = []
	var map_data := _load_json(MAP_PATH, errors)
	if not errors.is_empty():
		for e in errors:
			print("ERROR: %s" % e)
		quit(1)
		return
	var map := SimMap.new(map_data)
	var terrain := Terrain.load_from(TERRAIN_PATH, map.size, errors)
	if not errors.is_empty():
		for e in errors:
			print("ERROR: %s" % e)
		quit(1)
		return

	var write: bool = args.has("write")
	var changed := 0
	if args.has("pits"):
		changed = _move_pits(terrain, map_data, float(str(args["pits"])))
	elif args.has("bases"):
		changed = _inset_bases(terrain, map_data, int(str(args["bases"])))
	elif args.has("lanes"):
		changed = _paint_lanes(terrain, map_data)
	else:
		print("ERROR: need one of --pits=D, --bases=K, --lanes")
		quit(1)
		return

	print("paint: %d cells %s" % [changed, "changed" if write else "would change"])
	_report_river(terrain)
	if not write:
		print("paint: dry run. Add --write to apply.")
		quit(0)
		return
	_write_all(terrain, map_data)
	quit(0)


## Slides both pits off the river's centreline.
##
## The offset is applied to one pit and *mirrored* onto the other rather than
## applied twice, because 180-degree symmetry is a balance guard rail: the two
## pits have to remain each other's image exactly, and rounding each independently
## is how that quietly stops being true.
func _move_pits(t: Terrain, map_data: Dictionary, delta: float) -> int:
	var size: float = map_data["size"]
	var step: float = delta / sqrt(2.0)
	var pits: Dictionary = map_data["pits"]
	var old_dragon := Vector2(pits["dragon"][0], pits["dragon"][1])
	var old_baron := Vector2(pits["baron"][0], pits["baron"][1])
	var dragon := (old_dragon + Vector2(step, step)).round()
	var baron := Vector2(size, size) - dragon
	print("pits: dragon %s -> %s (perp %+.1f -> %+.1f), baron mirrored to %s"
		% [str(pits["dragon"]), str(dragon), _perp(old_dragon, size),
			_perp(dragon, size), str(baron)])
	pits["dragon"] = [dragon.x, dragon.y]
	pits["baron"] = [baron.x, baron.y]

	var changed := 0

	# A camp tangent to a pit travels with it. The two were authored as one
	# arrangement — the camp flanks the objective — so moving the bowl and leaving
	# the camp behind does not preserve the layout, it just puts the camp in the
	# bowl's way. Doing exactly that was the first attempt, and the pit came out
	# notched and a quarter smaller, because painting correctly refuses to take a
	# camp's cells. Moving them together keeps both features their original size.
	var travelling := {}  # camp id -> [old world pos, shift]
	for camp: Dictionary in map_data["camps"]:
		var p := Vector2(camp["pos"][0], camp["pos"][1])
		var to_dragon: float = minf(p.distance_to(old_dragon), p.distance_to(dragon))
		var to_baron: float = minf(p.distance_to(old_baron), p.distance_to(baron))
		# Either flanking the bowl before the move, or standing where it lands.
		# Testing only the old position misses the second case, and a camp the
		# arriving pit would swallow is the one that most needs to get out of it.
		if minf(to_dragon, to_baron) > PIT_RADIUS + CAMP_RADIUS:
			continue
		var d := Vector2(step, step) if to_dragon < to_baron else Vector2(-step, -step)
		d = d.round()
		travelling[camp["id"]] = [p, d]
		print("pits: camp %s travels with its pit, %s -> %s"
			% [camp["id"], str(camp["pos"]), str(p + d)])
		camp["pos"] = [p.x + d.x, p.y + d.y]

	# Vacate. A cell the pit used to occupy goes back to being river if it lies
	# within the channel, and to jungle floor otherwise — that refill is what
	# reconnects the two arms through the hole the bowl had punched in them.
	var camp_moves: Array = []
	for r in t.n:
		for c in t.n:
			var kind: int = t.kind_at_cell(c, r)
			var here := t.center_of(c, r)
			if kind == Terrain.CAMP:
				for cid: String in travelling:
					if here.distance_to(travelling[cid][0]) > CAMP_RADIUS:
						continue
					camp_moves.append([Vector2i(c, r), travelling[cid][1]])
					t.cells[r * t.n + c] = Terrain.OPEN
					changed += 1
					break
			elif kind == Terrain.PIT:
				t.cells[r * t.n + c] = Terrain.RIVER \
					if absf(_perp(here, size)) <= RIVER_HALF else Terrain.OPEN
				changed += 1

	# Paint the pits, then put the travelling camps down on top. Order matters:
	# the camp is tangent to the bowl by design, so it has to be able to reclaim
	# the cells the disc would otherwise have taken from it.
	for centre in [dragon, baron]:
		for r in t.n:
			for c in t.n:
				if t.center_of(c, r).distance_to(centre) > PIT_RADIUS:
					continue
				var kind: int = t.kind_at_cell(c, r)
				# Brush is taken, not spared: a carved bowl does not have bushes
				# growing in it, and sparing them punched holes in the disc that
				# read as a cross rather than a pit.
				if kind != Terrain.OPEN and kind != Terrain.RIVER \
						and kind != Terrain.BRUSH and kind != Terrain.WALL:
					continue
				if kind == Terrain.WALL and t.wall_class(c, r) != Terrain.ROCK:
					continue
				t.cells[r * t.n + c] = Terrain.PIT
				changed += 1
	# A disc rasterised onto a coarse grid leaves single-cell spikes wherever the
	# boundary clips one cell of a row. §6.3 rule 4 refuses fine detail that defines
	# a mass's shape, so a pit cell with one orthogonal neighbour or none is not a
	# pit, it is an artefact of the radius.
	for _pass in 2:
		var spikes: Array[Vector2i] = []
		for r in t.n:
			for c in t.n:
				if t.kind_at_cell(c, r) != Terrain.PIT:
					continue
				var neighbours := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if t.kind_at_cell(c + d.x, r + d.y) == Terrain.PIT:
						neighbours += 1
				if neighbours <= 1:
					spikes.append(Vector2i(c, r))
		for cell in spikes:
			var here := t.center_of(cell.x, cell.y)
			t.cells[cell.y * t.n + cell.x] = Terrain.RIVER \
				if absf(_perp(here, size)) <= RIVER_HALF else Terrain.OPEN
			changed += 1
	for move: Array in camp_moves:
		var cell: Vector2i = move[0]
		var d: Vector2 = move[1]
		var c: int = cell.x + int(d.x / t.cell_size)
		# Row 0 is the top of the map, so +y in world is -1 in row.
		var r: int = cell.y - int(d.y / t.cell_size)
		if c < 0 or r < 0 or c >= t.n or r >= t.n:
			continue
		t.cells[r * t.n + c] = Terrain.CAMP
		changed += 1
	return changed


## Pulls both bases K cells in from the map edge.
##
## A translation, not a reshape: the footprint keeps its exact area and outline, so
## base size — which is a gameplay number — is unchanged and only its distance from
## the wall moves. The nexus and each lane's base-end path point travel by the same
## vector, so the lane mouths still meet the base they belong to.
func _inset_bases(t: Terrain, map_data: Dictionary, k: int) -> int:
	var size: float = map_data["size"]
	var shift := float(k) * t.cell_size
	var moved := {
		Terrain.BASE_BLUE: Vector2(shift, shift),
		Terrain.BASE_RED: Vector2(-shift, -shift),
	}
	var old_cells := {}
	for kind: int in moved:
		old_cells[kind] = []
	for r in t.n:
		for c in t.n:
			var kind: int = t.kind_at_cell(c, r)
			if moved.has(kind):
				old_cells[kind].append(Vector2i(c, r))

	var changed := 0
	# Vacated ground becomes wall. It sits against the map edge, so the void pass
	# in sim/terrain.gd will classify it as rampart and it reads as the arena's
	# own wall rather than as a hole where a base used to be.
	for kind: int in old_cells:
		for cell: Vector2i in old_cells[kind]:
			t.cells[cell.y * t.n + cell.x] = Terrain.WALL
			changed += 1
	for kind: int in old_cells:
		# Row 0 is the top of the map, so a shift of +y in world is -1 in row.
		var dc := int(moved[kind].x / t.cell_size)
		var dr := -dc
		for cell: Vector2i in old_cells[kind]:
			var c: int = cell.x + dc
			var r: int = cell.y + dr
			if c < 0 or r < 0 or c >= t.n or r >= t.n:
				continue
			t.cells[r * t.n + c] = kind
			changed += 1

	var bases: Dictionary = map_data["bases"]
	for team: String in bases:
		var d: Vector2 = moved[Terrain.BASE_BLUE if team == "blue" else Terrain.BASE_RED]
		var p := Vector2(bases[team][0], bases[team][1]) + d
		print("bases: %s nexus %s -> %s" % [team, str(bases[team]), str(p)])
		bases[team] = [p.x, p.y]

	# Each lane's path ends at a base, so both ends are snapped *onto* the nexus
	# rather than translated alongside it.
	#
	# Translating looked equivalent and was not. The three lanes left the base at
	# three different distances from the nexus — top and mid within 5 world units,
	# bot at 9.4 — and the viewer only draws minions besieging a structure within
	# SIEGE_REACH (9.0) of the wave front. So a nexus taken down bot fell with
	# nothing visibly hitting it, which is the exact 2026-07-25 playtest complaint
	# `game/main.gd:620` was written to fix. It survived because it depended on
	# which lane happened to win the match; moving the bases changed the outcome of
	# seed 42 and exposed it. Anchoring every lane at the nexus makes the doorstep
	# the same short distance out on all three, and is where minions spawn anyway.
	var lanes: Dictionary = map_data["lanes"]
	for lane: String in lanes:
		var path: Array = lanes[lane]["path"]
		for i in [0, path.size() - 1]:
			var p := Vector2(path[i][0], path[i][1])
			var blue := Vector2(bases["blue"][0], bases["blue"][1])
			var red := Vector2(bases["red"][0], bases["red"][1])
			var anchor: Vector2 = blue if p.distance_to(blue) < p.distance_to(red) else red
			path[i] = [anchor.x, anchor.y]
	return changed


## Re-rasterises every lane band from its polyline.
##
## Erase-then-repaint, because a band is defined by its path and nothing else. The
## erase deliberately does not touch base cells: a lane running into a base is the
## base's ground, and clearing it would wall the mouths shut — which is exactly how
## attempt 3 at iteration 11 failed.
func _paint_lanes(t: Terrain, map_data: Dictionary) -> int:
	var changed := 0
	for r in t.n:
		for c in t.n:
			if t.kind_at_cell(c, r) == Terrain.LANE:
				t.cells[r * t.n + c] = Terrain.OPEN
				changed += 1
	var lanes: Dictionary = map_data["lanes"]
	for lane: String in lanes:
		var path: Array = lanes[lane]["path"]
		for i in range(path.size() - 1):
			var a := Vector2(path[i][0], path[i][1])
			var b := Vector2(path[i + 1][0], path[i + 1][1])
			for r in t.n:
				for c in t.n:
					var kind: int = t.kind_at_cell(c, r)
					# A road does not run through a base, a camp, an objective pit
					# or a bush patch; where the band meets one, the other feature
					# keeps its cells and the lane edge takes the notch. River is
					# deliberately *not* protected — mid crossing the water is the
					# ford, and those cells are lane with water drawn over them.
					if kind == Terrain.BASE_BLUE or kind == Terrain.BASE_RED \
							or kind == Terrain.CAMP or kind == Terrain.PIT \
							or kind == Terrain.BRUSH:
						continue
					if _dist_to_segment(t.center_of(c, r), a, b) > LANE_HALF:
						continue
					t.cells[r * t.n + c] = Terrain.LANE
					changed += 1
	return changed


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var tt: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * tt)


## The river's connected components, largest first. --pits is judged on this
## number reaching 1: four bodies of water is the finding every critic panel has
## reported since the first, and it is real in the data, not a rendering artefact.
func _report_river(t: Terrain) -> void:
	var seen := {}
	var sizes: Array[int] = []
	for r in t.n:
		for c in t.n:
			var key := r * t.n + c
			if t.kind_at_cell(c, r) != Terrain.RIVER or seen.has(key):
				continue
			var stack: Array[Vector2i] = [Vector2i(c, r)]
			seen[key] = true
			var count := 0
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				count += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = cell + d
					if nb.x < 0 or nb.y < 0 or nb.x >= t.n or nb.y >= t.n:
						continue
					var nk: int = nb.y * t.n + nb.x
					if seen.has(nk) or t.kind_at_cell(nb.x, nb.y) != Terrain.RIVER:
						continue
					seen[nk] = true
					stack.append(nb)
			sizes.append(count)
	sizes.sort()
	sizes.reverse()
	print("river: %d component(s) %s" % [sizes.size(), str(sizes)])


func _write_all(terrain: Terrain, map_data: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(TERRAIN_PATH)
	var header := PackedStringArray()
	for raw in text.split("\n"):
		if raw.begins_with(Terrain.COMMENT_PREFIX):
			header.append(raw)
		elif not raw.strip_edges().is_empty():
			break
	var out := FileAccess.open(TERRAIN_PATH, FileAccess.WRITE)
	if out == null:
		print("ERROR: cannot write %s" % TERRAIN_PATH)
		return
	out.store_string("\n".join(header) + "\n" + terrain.to_text() + "\n")
	out.close()
	var mf := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if mf == null:
		print("ERROR: cannot write %s" % MAP_PATH)
		return
	mf.store_string(JSON.stringify(map_data, " ") + "\n")
	mf.close()
	print("paint: wrote data/terrain.txt and data/map.json")

	var errors: Array[String] = []
	var fresh_map := SimMap.new(_load_json(MAP_PATH, errors))
	var fresh := Terrain.load_from(TERRAIN_PATH, fresh_map.size, errors)
	if not errors.is_empty():
		for e in errors:
			print("ERROR: %s" % e)
		return
	var problems := fresh.validate(fresh_map)
	if problems.is_empty():
		print("paint: all guard rails pass")
	else:
		print("paint: %d problem(s):" % problems.size())
		for p in problems:
			print("  - %s" % p)


func _load_json(path: String, errors: Array[String]) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: missing or empty file" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		errors.append("%s: invalid JSON" % path)
		return {}
	return parsed
