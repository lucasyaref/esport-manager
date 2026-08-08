extends SceneTree
## The gauntlet loop's camera: renders the map to a PNG and exits.
##
## This exists so the map can be iterated on without a human opening the game and
## taking a screenshot. One command produces one image; the image is compared to
## the reference in docs/reference/map/; the palette or data/terrain.txt is edited;
## repeat. See docs/gauntlet-map.md for the loop itself.
##
## It draws through the *same* TerrainView the match viewer uses, so what the loop
## grades is what the game shows. If you find yourself adding drawing code here,
## it belongs in game/terrain_view.gd instead.
##
## Godot cannot render in --headless (there is no rendering context, the viewport
## texture comes back null), so this runs windowed. tools/shot.sh parks the window
## off-screen so it does not steal focus.
##
## Usage:
##   godot --path . --script res://tools/shoot_map.gd -- [--out=PATH] [--size=N] [--overlay]
##
##   --out      output PNG path (default res://.shots/map.png)
##   --size     square edge in pixels (default 1024)
##   --overlay  draw the sim's own geometry (lanes, towers, pits, camps) on top,
##              to check the terrain and data/map.json still agree

const DEFAULT_OUT := "res://.shots/map.png"
const DEFAULT_SIZE := 1024
const MARGIN := 0.0


func _initialize() -> void:
	var args := _parse_args()
	var out_path: String = args.get("out", DEFAULT_OUT)
	var size := maxi(64, int(args.get("size", str(DEFAULT_SIZE))))
	var overlay := args.has("overlay")

	# --- data -----------------------------------------------------------------
	var errors: Array[String] = []
	var map_data := _load_json("res://data/map.json", errors)
	if not errors.is_empty():
		_fail(errors)
		return
	var map := SimMap.new(map_data)
	var terrain := Terrain.load_from("res://data/terrain.txt", map.size, errors)
	if not errors.is_empty():
		_fail(errors)
		return

	# This tool renders and says what it drew; it does not judge. The guard rails
	# have exactly one owner — tools/terrain_tool.gd -- --check, which tools/check.sh
	# and tools/gauntlet.sh both run — so there is never a second opinion about
	# whether the map is legal.
	print("terrain: %dx%d cells, %.1f world units per cell, %.0f%% walkable"
		% [terrain.n, terrain.n, terrain.cell_size, terrain.walkable_fraction() * 100.0])

	# --- render ---------------------------------------------------------------
	var canvas := ShotCanvas.new()
	canvas.terrain = terrain
	canvas.map = map
	canvas.px_per_world = (size - MARGIN * 2.0) / map.size
	canvas.origin = Vector2(MARGIN, MARGIN)
	canvas.overlay = overlay

	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(canvas)
	root.add_child(vp)

	# Two frames: one to lay the tree out, one to be sure the target is written.
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	if img == null:
		print("ERROR: no rendering context — run this windowed, not with --headless")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var err := img.save_png(out_path)
	if err != OK:
		print("ERROR: could not write %s (%d)" % [out_path, err])
		quit(1)
		return
	print("wrote %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)


func _parse_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			args[parts[0]] = parts[1]
		else:
			args[stripped] = "true"
	return args


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


func _fail(errors: Array[String]) -> void:
	for e in errors:
		print("ERROR: %s" % e)
	quit(1)


## The thing that actually draws. Terrain comes from TerrainView (shared with the
## match viewer); the overlay is diagnostic only and never ships in the game.
class ShotCanvas extends Node2D:
	var terrain: Terrain
	var map: SimMap
	var px_per_world := 10.0
	var origin := Vector2.ZERO
	var overlay := false

	const C_LANE_LINE := Color(1, 1, 1, 0.35)
	const C_TOWER := Color("f2e6c0")
	const C_CAMP := Color("d8c070")
	const C_DRAGON := Color("f2993d")
	const C_BARON := Color("b380ff")
	const C_BASE := {"blue": Color("4aa3ff"), "red": Color("ff5a5a")}

	func _draw() -> void:
		TerrainView.draw(self, terrain, origin, px_per_world)
		if overlay:
			_draw_overlay()

	func _w2s(w: Vector2) -> Vector2:
		return origin + Vector2(w.x, map.size - w.y) * px_per_world

	func _draw_overlay() -> void:
		for lane in SimMap.LANES:
			var pts := PackedVector2Array()
			for w in map.lane_paths[lane]:
				pts.append(_w2s(w))
			draw_polyline(pts, C_LANE_LINE, 2.0)
		for team: String in map.towers:
			for tier: String in map.towers[team]:
				for lane in SimMap.LANES:
					var p := _w2s(map.pos_on_lane(lane, float(map.towers[team][tier])))
					draw_circle(p, 5.0, C_TOWER)
					draw_circle(p, 3.0, C_BASE[team])
		for camp: Dictionary in map.camps:
			draw_circle(_w2s(camp.pos), 4.0, C_CAMP)
		for pit: String in map.pits:
			draw_circle(_w2s(map.pits[pit]), 7.0,
				C_DRAGON if pit == "dragon" else C_BARON)
		for team: String in map.bases:
			draw_circle(_w2s(map.bases[team]), 9.0, C_BASE[team])
