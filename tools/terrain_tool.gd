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
##
##   --check          validate and report (default if no other mode given)
##   --mirror=SIDE    make the map symmetric by copying SIDE's half onto the
##                    other. SIDE is "red" (the top-left half in reading order,
##                    which holds the red base) or "blue".
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
	print("mirror: wrote %s" % TERRAIN_PATH)

	# Re-validate what we just wrote: mirroring fixes symmetry and can, in
	# principle, seal a corridor that only existed on the discarded side.
	var problems := terrain.validate(map)
	if problems.is_empty():
		print("mirror: all guard rails pass")
	else:
		print("mirror: %d problem(s) remain:" % problems.size())
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
