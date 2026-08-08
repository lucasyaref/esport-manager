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
##   godot --path . --script res://tools/shoot_map.gd -- [--out=PATH] [--size=N]
##       [--overlay] [--structures]
##
##   --out      output PNG path (default res://.shots/map.png)
##   --size     square edge in pixels (default 1024)
##   --structures  draw towers and nexuses over the terrain, intact, the way
##                 game/map_view.gd draws them every frame. Not diagnostic:
##                 this is the picture a player actually watches.
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
	var structures := args.has("structures")

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
	canvas.structures = structures

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

	var structures := false

	## Match game/map_view.gd's own values. The cold critics kept reporting "no
	## towers, no nexus anywhere" against a terrain-only still, which is a true
	## statement about the render and a useless one about the map — the viewer
	## draws all of it every frame. Drawn here at full health with none down,
	## i.e. the map as it stands at the first whistle.
	const TOWER_R := 6.0
	const NEXUS_R := 13.0
	const TEAM := {
		"blue": {"fill": Color(0.30, 0.55, 1.0), "ring": Color(0.62, 0.78, 1.0),
			"dark": Color(0.18, 0.30, 0.55)},
		"red": {"fill": Color(1.0, 0.42, 0.42), "ring": Color(1.0, 0.66, 0.66),
			"dark": Color(0.55, 0.22, 0.22)},
	}

	const C_LANE_LINE := Color(1, 1, 1, 0.35)
	const C_TOWER := Color("f2e6c0")
	const C_CAMP := Color("d8c070")
	const C_DRAGON := Color("f2993d")
	const C_BARON := Color("b380ff")
	const C_BASE := {"blue": Color("4aa3ff"), "red": Color("ff5a5a")}

	func _draw() -> void:
		TerrainView.draw(self, terrain, origin, px_per_world)
		if structures:
			_draw_structures()
		if overlay:
			_draw_overlay()

	func _w2s(w: Vector2) -> Vector2:
		return origin + Vector2(w.x, map.size - w.y) * px_per_world

	## Towers and nexuses as the viewer draws them, intact. Unlike the overlay,
	## this is not diagnostic — it is part of the picture a player watches, so the
	## critics should be grading it.
	func _draw_structures() -> void:
		for team: String in map.towers:
			var t: Dictionary = TEAM[team]
			for tier: String in map.towers[team]:
				for lane in SimMap.LANES:
					var c := _w2s(map.pos_on_lane(lane, float(map.towers[team][tier])))
					var r: float = TOWER_R if tier != "base" else TOWER_R + 2.0
					draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), t.dark, true)
					draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)),
						t.ring, false, 1.5)
		for team: String in map.bases:
			var t: Dictionary = TEAM[team]
			var c := _w2s(map.bases[team])
			draw_circle(c, NEXUS_R, Color(t.fill.r, t.fill.g, t.fill.b, 0.22))
			draw_arc(c, NEXUS_R, 0, TAU, 28, t.fill, 2.5, true)
			var d := NEXUS_R * 0.5
			var hull := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0),
				c + Vector2(0, d), c + Vector2(-d, 0)])
			draw_colored_polygon(hull, t.fill)
			var outline := hull.duplicate()
			outline.append(hull[0])
			draw_polyline(outline, Color(t.fill.r, t.fill.g, t.fill.b, 0.85), 1.4, true)


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
