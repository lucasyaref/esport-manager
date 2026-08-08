extends SceneTree
## Checks and repairs data/terrain.txt. Headless — no rendering involved.
##
## The one repair it does is symmetry, because that is the guard rail a human
## edit breaks most often and the one that is pure tedium to fix by hand: the map
## must be 180-degree rotationally symmetric or blue-side win rate — a tracked
## balance metric — stops meaning anything. Draw one side, mirror it, done.
##
## Usage:
##   godot --headless --path . --script res://tools/terrain_tool.gd -- --check
##   godot --headless --path . --script res://tools/terrain_tool.gd -- --mirror=red [--write]
##   godot --headless --path . --script res://tools/terrain_tool.gd -- --chunkify=3 [--write]
##
##   --check          validate and report (default if no other mode given)
##   --mirror=SIDE    make the map symmetric by copying SIDE's half onto the
##                    other. SIDE is "red" (the top-left half in reading order,
##                    which holds the red base) or "blue".
##   --chunkify=N     snap the jungle's rock masses to a 2x2 block grid; a block
##                    with N or more rock cells becomes all rock, the rest become
##                    all floor. See _chunkify.
##   --write          actually write data/terrain.txt; without it, a dry run that
##                    reports how many cells would change

const TERRAIN_PATH := "res://data/terrain.txt"


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
	var map_data := _load_json("res://data/map.json", errors)
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

	if args.has("mirror"):
		_mirror(terrain, map, str(args["mirror"]), args.has("write"))
		quit(0)
		return

	if args.has("chunkify"):
		_chunkify(terrain, map, int(str(args["chunkify"])), args.has("write"))
		quit(0)
		return
	# --check is a gate: tools/check.sh and tools/gauntlet.sh both depend on the
	# exit code, not on the text.
	quit(0 if _check(terrain, map) else 1)


func _check(terrain: Terrain, map: SimMap) -> bool:
	print("terrain: %dx%d cells, %.1f world units per cell, %.0f%% walkable"
		% [terrain.n, terrain.n, terrain.cell_size, terrain.walkable_fraction() * 100.0])
	var problems := terrain.validate(map)
	if problems.is_empty():
		print("terrain: all guard rails pass")
		return true
	print("terrain: %d problem(s):" % problems.size())
	for p in problems:
		print("  - %s" % p)
	return false


## Copies one half of the grid onto the other under 180-degree rotation.
##
## In reading order, cell i and cell (n*n - 1 - i) are always opposite each other,
## and the first half of the indices is exactly complementary to the second — so
## "the half to keep" is just a side of that split. Row 0 is the top of the map,
## which is red's corner, so the first half is red's.
func _mirror(terrain: Terrain, map: SimMap, side: String, write: bool) -> void:
	if not side in ["red", "blue"]:
		print("ERROR: --mirror needs \"red\" or \"blue\", got \"%s\"" % side)
		quit(1)
		return
	var total: int = terrain.n * terrain.n
	var keep_first := side == "red"
	var changed := 0
	for i in total / 2:
		var opposite: int = total - 1 - i
		var src: int = i if keep_first else opposite
		var dst: int = opposite if keep_first else i
		var want: int = Terrain._mirror_kind(terrain.cells[src])
		if terrain.cells[dst] != want:
			terrain.cells[dst] = want
			changed += 1

	print("mirror: %s half copied onto the other — %d cells %s"
		% [side, changed, "changed" if write else "would change"])
	if changed == 0:
		return
	if not write:
		print("mirror: dry run. Add --write to apply.")
		return
	# Mirroring fixes symmetry and can, in principle, seal a corridor that only
	# existed on the discarded side, so what was written is re-validated.
	_write_terrain(terrain, map, "mirror")


## GDD §6.3 rule 4 — "big blocks, not fine detail. Stone masses are chunky
## rectangles and Ls, sized so you could count them at full zoom-out."
##
## Run 1 read that as a palette problem for four iterations. It is not: the jungle
## masses were jagged because they are drawn at *cell* resolution, so every mass
## carries one-cell steps all along its outline and the eye reads a patchwork of
## small blobs instead of a few countable rocks. The fix is to give the masses a
## coarser grid than the cells they are made of — 4x4 world units rather than 2x2.
##
## So: cover the map in 2x2 blocks of cells and let each block hold one decision.
## A block with `rock_threshold` or more rock cells becomes all rock; anything
## less becomes all floor. Masses come out with 2-cell steps, which at overview
## scale is the difference between an edge and a serration.
##
## Three things make this safe to run against the guard rails, and they are the
## reason it can be a transform at all rather than a hand edit of 50 rows:
##
##   - **Symmetry is structural.** n is even, so the block decomposition maps onto
##     itself under the 180-degree rotation, and the decision is a function of the
##     rock *count* alone — which the rotation preserves. A symmetric grid in gives
##     a symmetric grid out, with no mirror pass needed afterwards.
##   - **The block decides; the cell vetoes.** Every cell in a block counts toward
##     the decision, but only plain floor and interior rock are ever rewritten.
##     Lane, river, pit, camp, brush, base and the arena's own rampart hold their
##     ground, so no anchor's cell is built over, the lanes and pits keep the exact
##     shapes the sim reads from `map.json`, and the map's edge — which took
##     iterations 08 and 12 to get right — is left alone.
##
##     Deciding per block but writing per cell is the correction that made this
##     pass worth running. Skipping any block that contained a single brush or
##     rampart cell disqualified 525 of 625 blocks and moved 34 cells: brush is
##     sprinkled through the whole jungle, so "pure rock-and-floor block" is a
##     condition the interesting parts of this map almost never meet.
##
## What it cannot guarantee is reachability: a two-cell corridor between two masses
## can close. That one is left to the gate, deliberately, because the answer when
## it happens is a judgement about the layout and not something a threshold should
## be silently deciding.
func _chunkify(terrain: Terrain, map: SimMap, rock_threshold: int, write: bool) -> void:
	if rock_threshold < 1 or rock_threshold > 4:
		print("ERROR: --chunkify needs a threshold of 1..4, got %d" % rock_threshold)
		quit(1)
		return

	var before := terrain.walkable_count()
	var changed := 0
	var blocks_rock := 0
	var blocks_open := 0
	var blocks_skipped := 0
	# Even n is what makes the block grid rotation-invariant, so it is not an
	# assumption worth leaving implicit.
	if terrain.n % 2 != 0:
		print("ERROR: chunkify needs an even grid, got %d" % terrain.n)
		quit(1)
		return
	var blocks: int = terrain.n >> 1
	for br in blocks:
		for bc in blocks:
			var writable: Array[int] = []
			var rock := 0
			for dr in 2:
				for dc in 2:
					var c: int = bc * 2 + dc
					var r: int = br * 2 + dr
					var kind: int = terrain.kind_at_cell(c, r)
					if kind == Terrain.WALL:
						rock += 1
						# Rampart and void belong to the map's edge, not its jungle:
						# they vote, and are then left where they are.
						if terrain.wall_class(c, r) == Terrain.ROCK:
							writable.append(r * terrain.n + c)
					elif kind == Terrain.OPEN:
						writable.append(r * terrain.n + c)
			if writable.is_empty():
				blocks_skipped += 1
				continue
			var want: int = Terrain.WALL if rock >= rock_threshold else Terrain.OPEN
			if want == Terrain.WALL:
				blocks_rock += 1
			else:
				blocks_open += 1
			for i in writable:
				if terrain.cells[i] != want:
					terrain.cells[i] = want
					changed += 1

	print("chunkify: threshold %d — %d blocks to rock, %d to floor, %d skipped "
		% [rock_threshold, blocks_rock, blocks_open, blocks_skipped]
		+ "(nothing in them this pass may rewrite)")
	print("chunkify: %d cells %s, walkable %d -> %d"
		% [changed, "changed" if write else "would change", before, terrain.walkable_count()])
	if changed == 0:
		return
	if not write:
		print("chunkify: dry run. Add --write to apply.")
		return
	_write_terrain(terrain, map, "chunkify")


## Writes the grid back, keeping the file's comment header — the legend in it is
## how the designer reads the map, so a transform must never strip it.
func _write_terrain(terrain: Terrain, map: SimMap, who: String) -> void:
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
		quit(1)
		return
	out.store_string("\n".join(header) + "\n" + terrain.to_text() + "\n")
	out.close()
	print("%s: wrote %s" % [who, TERRAIN_PATH])

	# Re-validated from the mutated grid rather than trusting the transform. The
	# in-memory Terrain's wall_class cache is stale after cells change, so the
	# check is run on a Terrain re-read from what was actually written.
	var errors: Array[String] = []
	var fresh := Terrain.load_from(TERRAIN_PATH, map.size, errors)
	if not errors.is_empty():
		for e in errors:
			print("ERROR: %s" % e)
		return
	var problems := fresh.validate(map)
	if problems.is_empty():
		print("%s: all guard rails pass" % who)
	else:
		print("%s: %d problem(s) remain:" % [who, problems.size()])
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
