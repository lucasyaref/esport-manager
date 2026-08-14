extends Control
## M4 match viewer — the play field. Pure presentation: it holds the static
## map geometry (lanes, towers, pits, camps, bases) and, each frame, a fully
## resolved `frame` dict handed to it by the MatchViewer. It knows nothing
## about ticks, the sim, or timing — it just draws what it is given. All sim
## state lives in sim/; this is playback only (GDD pillar 3).
##
## World coordinates are 0..100 (data/map.json). We flip Y on the way to the
## screen so blue sits bottom-left and red top-right — the LoL orientation,
## which makes the map read at a glance.

const PAD := 14.0            # inner margin, px — the fit-the-world margin at ZOOM_MIN only;
                              # untouched by camera zoom, since it defines what "minimum zoom"
                              # (the whole map fitted to the panel) means in the first place.
# Champion body radius is world-derived (not a fixed pixel size) so that the
# playback separation (MatchViewer._spread_bodies, a body's width apart) actually
# reads on screen as five players standing together rather than one fat disc.
# Clamped so it stays legible in a small window. The max clamp grows with zoom
# (_zoom_mult) so a close-up body reads as a body, not a dot pinned to overview size.
const CHAMP_WORLD_R := 0.95   # world units
const CHAMP_R_MIN := 6.0      # px
const CHAMP_R_MAX := 11.0     # px, at ZOOM_MIN — unchanged from the pre-camera behavior
const TOWER_R := 6.0
const CAMP_R := 3.0
const MINION_R := 2.2
const PIT_R := 15.0
const NEXUS_R := 13.0

# --- M6-D: shared placeholder sprite sheets -------------------------------------
# Characters: sheet layout (frame size / cols / row order) comes from
# data/animation.json (threaded in through setup_geometry) — ANIM_ROWS below is
# only the fallback if that call never supplies one (e.g. an older caller).
# Structures (towers/nexus) have no per-tier or per-team art variation and no
# animation, so their sheet is small and fixed: one 32px frame each, tower then
# nexus, loaded directly here rather than threaded through main.gd — there is
# no data.json field for a structure "sprite" the way a character has one.
const ANIM_ROWS := ["idle", "run", "attack", "cast", "hurt", "die", "recall"]
const STRUCT_SHEET_PATH := "res://game/assets/structures/placeholder.png"
const STRUCT_FRAME := 32.0

# --- camera --------------------------------------------------------------------
# The world->screen transform is a real camera: a centre point (world coords) and
# a zoom factor, both eased toward a target rather than snapped, replacing the old
# fixed _scale()/_w2s(). ZOOM_MIN is defined so that zoom = ZOOM_MIN reproduces the
# old fit-the-whole-world-to-the-panel behavior exactly (see _base_scale) — a fresh
# match at rest looks pixel-identical to before this phase, modulo terrain now being
# visible (M6-B task 1). Higher zoom magnifies a region around the centre; the map
# has hard edges, so you cannot zoom out past ZOOM_MIN.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0                # design call: ~4x is "the lane fills the screen"
const ZOOM_STEP := 0.4               # per wheel notch / button press
const CAM_SMOOTH_RATE := 9.0         # exponential ease-to-target, 1/s (wall-clock, not sim time)
# How far flat-pixel sizes (turret glyphs, camp/minion/pit/nexus dots, badges,
# fonts, bars) grow between ZOOM_MIN and ZOOM_MAX. World-derived sizes (champion
# radius, lane width, effect radii) already scale with _scale() and don't need this.
const ZOOM_PX_MULT_MAX := 3.0
const FOLLOW_CLICK_SLACK := 4.0      # px of extra hit-test radius around a champion body

## M6-C: fired whenever the user directly drives the camera (wheel zoom, click-to-
## follow/deselect). The highlight director listens for this to back off for the
## current highlight rather than fighting the user's own input every frame — the
## F-key/Escape hotkeys are handled by `main.gd` itself (input owns those, not this
## node) and call `_release_director()` there directly instead of through this signal.
signal camera_touched

var cam_center := Vector2.ZERO       # smoothed camera centre, world coords
var cam_zoom := ZOOM_MIN             # smoothed
var _target_center := Vector2.ZERO
var _target_zoom := ZOOM_MIN
var follow_id := ""                  # player id the camera is locked onto, or ""
var terrain: Terrain

# Palette ---------------------------------------------------------------------
const C_BG := Color("101520")
const C_BORDER := Color("2a3446")
const C_LANE := Color(0.30, 0.32, 0.26, 0.55)
const C_LANE_CORE := Color(0.42, 0.44, 0.34, 0.55)
const C_RIVER := Color(0.20, 0.42, 0.72, 0.16)
const C_CAMP := Color(0.52, 0.50, 0.34)
const C_DRAGON := Color(0.95, 0.60, 0.24)
const C_BARON := Color(0.70, 0.50, 1.0)
const TEAM := {
	"blue": {"fill": Color(0.30, 0.55, 1.0), "ring": Color(0.62, 0.78, 1.0), "dark": Color(0.18, 0.30, 0.55)},
	"red": {"fill": Color(1.0, 0.42, 0.42), "ring": Color(1.0, 0.66, 0.66), "dark": Color(0.55, 0.22, 0.22)},
}
const ROLE_LETTER := {"top": "T", "jungle": "J", "mid": "M", "carry": "C", "support": "S"}

var world_size := 100.0
var geom := {}              # static geometry, world coords (set by setup_geometry)
var frame := {}             # resolved render state for the current playback tick

# M6-D: character sheet layout, normally supplied by setup_geometry from
# data/animation.json (main.gd owns loading it, same as char_textures does for
# the sprite paths); this default is only the fallback if it's never called.
var anim_sheet := {"frame_px": 64.0, "cols": 4, "rows": ANIM_ROWS}
var struct_tex: Texture2D = null

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# The camera now shows less than the whole world once zoomed in; without this,
	# drawn content bleeds past the panel into the side panel / bottom bar.
	clip_contents = true
	# Wheel-zoom and click-to-follow need mouse events; the map used to ignore them
	# entirely (nothing consumed input before this phase).
	mouse_filter = Control.MOUSE_FILTER_STOP
	_target_center = Vector2(world_size, world_size) * 0.5
	cam_center = _target_center
	# M6-D: the placeholder sheets are pixel art drawn a handful of px per
	# frame and then scaled up several times over (a 24px frame to a body that
	# can be 70+ px across at max zoom) — nearest-neighbour keeps every pixel a
	# hard-edged square instead of the project's default linear filter turning
	# it into a soft, blurry smear at exactly the size it's meant to be seen at.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(STRUCT_SHEET_PATH):
		var res: Resource = load(STRUCT_SHEET_PATH)
		if res is Texture2D:
			struct_tex = res


func setup_geometry(map: SimMap, char_textures: Dictionary, t: Terrain = null,
		sheet: Dictionary = {}) -> void:
	world_size = map.size
	terrain = t
	if not sheet.is_empty():
		anim_sheet = sheet
	reset_camera()
	var lanes := {}
	for lane in SimMap.LANES:
		lanes[lane] = map.lane_paths[lane]
	var towers: Array = []
	for team in SimMap.TEAMS:
		for lane in SimMap.LANES:
			for tier: String in map.towers[team]:
				towers.append({
					"team": team, "lane": lane, "tier": tier,
					"pos": map.pos_on_lane(lane, float(map.towers[team][tier])),
				})
	var camps: Array = []
	for c in map.camps:
		camps.append(c.pos)
	geom = {
		"lanes": lanes,
		"towers": towers,
		"pits": {"dragon": map.pits.dragon, "baron": map.pits.baron},
		"camps": camps,
		"bases": {"blue": map.bases.blue, "red": map.bases.red},
		"textures": char_textures,  # char_id -> Texture2D (or absent)
	}
	queue_redraw()


func set_frame(f: Dictionary) -> void:
	frame = f
	queue_redraw()


# --- camera: public interface --------------------------------------------------
# A future auto-camera director (M6-C) drives the camera entirely through these —
# no input-handling plumbing to redo. Manual control (wheel, click, hotkeys) goes
# through the same target_center/target_zoom this phase adds.

## Point the camera at an explicit world position and zoom, cancelling any follow.
## This is the hook a highlight director calls: "focus here, this zoomed".
func set_target(center: Vector2, zoom: float) -> void:
	follow_id = ""
	_target_center = center
	_target_zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)


## Lock the camera onto a player id; it recenters on their live position every
## frame (zoom is left alone) until stop_follow()/toggle_follow() cancels it.
func follow_player(id: String) -> void:
	follow_id = id
	var p: Variant = _champ_pos(id)
	if p != null:
		_target_center = p


func stop_follow() -> void:
	follow_id = ""


## Same id pressed/clicked twice = off; a different id = switch to it. This is
## what F1-F10 and clicking a champion body both drive.
func toggle_follow(id: String) -> void:
	if follow_id == id:
		follow_id = ""
	else:
		follow_player(id)


## Cancel any follow without changing where the camera is currently looking —
## the "clicked empty map" / Escape case.
func manual_override() -> void:
	follow_id = ""


## Deliberately does not touch follow_id or _target_center — zooming while
## following a player keeps following it, just closer/further.
func zoom_step(dir: int) -> void:
	_target_zoom = clampf(_target_zoom + dir * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func reset_camera() -> void:
	follow_id = ""
	_target_center = Vector2(world_size, world_size) * 0.5
	_target_zoom = ZOOM_MIN
	cam_center = _target_center
	cam_zoom = _target_zoom


## M6-C: a snapshot of where the camera is currently pointed (including a follow
## lock), for a caller that's about to push a temporary view — the highlight
## director — and wants to put the camera back exactly once it's done, rather than
## just resetting to the world overview.
func camera_state() -> Dictionary:
	return {"follow": follow_id, "center": _target_center, "zoom": _target_zoom}


## Inverse of camera_state(): restores exactly what it captured.
func restore_camera_state(s: Dictionary) -> void:
	var follow: String = String(s.get("follow", ""))
	if follow != "":
		follow_player(follow)
	else:
		set_target(s.get("center", _target_center), float(s.get("zoom", _target_zoom)))


func _process(delta: float) -> void:
	if geom.is_empty():
		return
	if follow_id != "":
		var p: Variant = _champ_pos(follow_id)
		if p != null:
			_target_center = p
	var t: float = 1.0 - exp(-CAM_SMOOTH_RATE * delta)
	cam_center = cam_center.lerp(_target_center, t)
	cam_zoom = lerpf(cam_zoom, _target_zoom, t)
	queue_redraw()


func _champ_pos(id: String) -> Variant:
	for ch: Dictionary in frame.get("champs", []):
		if String(ch.get("id", "")) == id:
			return ch.pos
	return null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_step(1)
			camera_touched.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_step(-1)
			camera_touched.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var hit := _champ_at(event.position)
			if hit != "":
				toggle_follow(hit)
			else:
				manual_override()
			camera_touched.emit()
			accept_event()


## Hit-test against champion bodies in current screen space, for click-to-follow.
func _champ_at(screen_pos: Vector2) -> String:
	var r := _champ_r() + FOLLOW_CLICK_SLACK
	for ch: Dictionary in frame.get("champs", []):
		if not ch.get("alive", true):
			continue
		if _w2s(ch.pos).distance_to(screen_pos) <= r:
			return String(ch.get("id", ""))
	return ""


# --- world -> screen ----------------------------------------------------------

## The fit-the-whole-world-to-the-panel scale — what _scale() used to always be,
## and what it still is exactly when cam_zoom == ZOOM_MIN. This is ZOOM_MIN's own
## definition, not a thing that changes with zoom itself.
func _base_scale() -> float:
	return (minf(size.x, size.y) - 2.0 * PAD) / world_size


func _scale() -> float:
	return _base_scale() * cam_zoom


func _zoom_frac() -> float:
	return clampf((cam_zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN), 0.0, 1.0)


## How far a flat-pixel size (not derived from world units) has grown at the
## current zoom: 1.0 at ZOOM_MIN (unchanged from pre-camera sizing), up to
## ZOOM_PX_MULT_MAX at ZOOM_MAX.
func _zoom_mult() -> float:
	return lerpf(1.0, ZOOM_PX_MULT_MAX, _zoom_frac())


## Zoom-aware font size: grows the same way flat-pixel radii do.
func _fs(px: int) -> int:
	return int(round(float(px) * _zoom_mult()))


## Champion body radius in px for the current window size and zoom. The min clamp
## is a legibility floor that never changes; the max clamp is ZOOM_MIN's overview
## cap, grown by the same curve as every other flat-pixel element.
func _champ_r() -> float:
	return clampf(CHAMP_WORLD_R * _scale(), CHAMP_R_MIN, CHAMP_R_MAX * _zoom_mult())


func _w2s(w: Vector2) -> Vector2:
	var s := _scale()
	# Flip Y (world y=0 / blue side renders at the bottom), then place relative to
	# the camera's centre rather than the world's — at cam_zoom == ZOOM_MIN and
	# cam_center == world centre this reduces to the old fit-the-world transform
	# exactly (verified algebraically; the two used to be the only possible state).
	var flipped := Vector2(w.x, world_size - w.y)
	var centre_flipped := Vector2(cam_center.x, world_size - cam_center.y)
	return size * 0.5 + (flipped - centre_flipped) * s


## Inverse of _w2s: a screen point back to world coords. Used for the minimap's
## viewport rectangle.
func _s2w(p: Vector2) -> Vector2:
	var s := _scale()
	var centre_flipped := Vector2(cam_center.x, world_size - cam_center.y)
	var flipped := (p - size * 0.5) / s + centre_flipped
	return Vector2(flipped.x, world_size - flipped.y)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if geom.is_empty():
		return
	_draw_field()
	if terrain == null:
		# Fallback only: no compiled terrain resource to draw (e.g. missing/invalid
		# data/terrain.txt). Draws the pre-M6-T flat sim geometry instead of a
		# blank field so the map still reads.
		_draw_lanes()
		_draw_river()
		_draw_camps()
	_draw_pits()
	_draw_bases()
	_draw_towers()
	if frame.is_empty():
		_draw_minimap()
		return
	_draw_minions()
	_draw_wards()
	_draw_tethers()      # under the bodies: a CC link belongs behind them
	_draw_champions()
	_draw_beats()        # over the bodies: the swing lands on top of the fight
	_draw_effects()
	_draw_pops()         # numbers last: they must survive a crowded fight
	_draw_minimap()       # corner overlay, always on top — the camera has left home


## Terrain art (game/terrain_view.gd, M6-T) draws the whole map — lanes, river,
## camps, pits, walls, brush — through the same TerrainView the offline capture
## rig grades. Previously this only flat-filled a background colour: 51 gauntlet
## iterations of terrain art were invisible in the live game (M6-B bug, found
## scoping this phase). Drawn through the camera's own origin/scale, so terrain
## pans and zooms with everything else instead of desyncing the moment zoom != 1.
func _draw_field() -> void:
	var tl := _w2s(Vector2(0, world_size))
	if terrain != null:
		TerrainView.draw(self, terrain, tl, _scale())
		return
	var span := world_size * _scale()
	var rect := Rect2(tl, Vector2(span, span))
	draw_rect(rect, C_BG, true)
	draw_rect(rect, C_BORDER, false, 2.0)


func _draw_lanes() -> void:
	var w := maxf(_scale() * 3.2, 4.0)
	for lane: String in geom.lanes:
		var pts := PackedVector2Array()
		for p: Vector2 in geom.lanes[lane]:
			pts.append(_w2s(p))
		draw_polyline(pts, C_LANE, w, true)
		draw_polyline(pts, C_LANE_CORE, w * 0.45, true)


func _draw_river() -> void:
	# The river runs along the anti-diagonal x + y = world_size, through the pits.
	var band := PackedVector2Array([
		_w2s(Vector2(0, world_size)), _w2s(Vector2(world_size * 0.28, world_size)),
		_w2s(Vector2(world_size, world_size * 0.28)), _w2s(Vector2(world_size, 0)),
		_w2s(Vector2(world_size * 0.72, 0)), _w2s(Vector2(0, world_size * 0.72)),
	])
	draw_colored_polygon(band, C_RIVER)


func _draw_camps() -> void:
	var r := CAMP_R * _zoom_mult()
	for p: Vector2 in geom.camps:
		draw_circle(_w2s(p), r, C_CAMP)


func _draw_pits() -> void:
	_draw_pit(geom.pits.dragon, C_DRAGON, "D",
		frame.get("dragon_up", false), int(frame.get("dragon_total", 0)))
	_draw_pit(geom.pits.baron, C_BARON, "B",
		frame.get("baron_up", false), -1)


func _draw_pit(w: Vector2, col: Color, letter: String, up: bool, count: int) -> void:
	var c := _w2s(w)
	var r := PIT_R * _zoom_mult()
	var glow := 0.30 if up else 0.12
	draw_circle(c, r - 2.0, Color(col.r, col.g, col.b, glow))
	draw_arc(c, r, 0, TAU, 32, col, 2.5 if up else 1.5, true)
	_centered(letter, c, _fs(15), col)
	if count >= 0:
		_centered("x%d" % count, c + Vector2(0, r + 9), _fs(11), col)


func _draw_bases() -> void:
	var nexus: Dictionary = frame.get("nexus_hp", {})
	var siege: Dictionary = frame.get("siege", {})
	var nr := NEXUS_R * _zoom_mult()
	for team: String in geom.bases:
		var c := _w2s(geom.bases[team])
		var t: Dictionary = TEAM[team]
		var alive: bool = frame.get("winner", "") != _enemy(team)
		var col: Color = t.fill if alive else Color(0.35, 0.35, 0.35)
		var frac: float = clampf(float(nexus.get(team, 1.0)), 0.0, 1.0)
		# M6-D: a built silhouette under the existing HP-drain diamond — this is
		# purely a skin, the drain/flash/bar machinery below is untouched, per the
		# gauntlet finding that both bases read as flat tinted glyphs with "no
		# structure silhouette" (BACKLOG M6-D scope note, 2026-08-09).
		if struct_tex != null:
			var sts := nr * 2.3
			draw_texture_rect_region(struct_tex, Rect2(c - Vector2(sts, sts) * 0.5, Vector2(sts, sts)),
				Rect2(STRUCT_FRAME, 0.0, STRUCT_FRAME, STRUCT_FRAME),
				Color(t.dark.r, t.dark.g, t.dark.b, 0.92))
		draw_circle(c, nr, Color(col.r, col.g, col.b, 0.22))
		draw_arc(c, nr, 0, TAU, 28, col, 2.5, true)
		# The nexus diamond drains as it takes damage: the sim can spend six minutes
		# grinding one down with minions, so its health has to be readable at a
		# glance and not only in a bar (2026-07-25 playtest, remark 4).
		var d := nr * 0.5
		var hull := PackedVector2Array([
			c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
		draw_colored_polygon(hull, Color(col.r, col.g, col.b, 0.20))
		if frac > 0.0:
			# Same diamond, scaled about its own centre — a shrinking core.
			var core := PackedVector2Array()
			for pnt: Vector2 in hull:
				core.append(c + (pnt - c) * frac)
			draw_colored_polygon(core, col)
		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, Color(col.r, col.g, col.b, 0.85), 1.4, true)
		if alive and frac < 1.0:
			_draw_bar(c + Vector2(0, nr + 7.0), frac, _hp_color(frac), true)
			_centered("%d%%" % int(round(frac * 100.0)), c + Vector2(0, nr + 18.0),
				_fs(11), _hp_color(frac))
		if alive:
			_draw_siege_pulse(c, nr + 3.0, float(siege.get("nexus_%s" % team, 0.0)))


## Towers, with health on the glyph itself. A turret drains like a battery — the
## coloured core shrinks with its HP — and adds a bar plus a red flash once it is
## really hurt. The thin bar alone was missed entirely in the 2026-07-25 playtest
## ("I do not see life of buildings"), even though it was on screen for 89% of a
## match: it is 3 px tall, sitting on top of a lane line.
func _draw_towers() -> void:
	var down: Dictionary = frame.get("towers_down", {})
	var hp: Dictionary = frame.get("tower_hp", {})
	var siege: Dictionary = frame.get("siege", {})
	for tw: Dictionary in geom.towers:
		var key: String = "%s_%s_%s" % [tw.team, tw.lane, tw.tier]
		var c := _w2s(tw.pos)
		if down.has(key):
			# Rubble: a dark stump where the turret was, so the hole in the map reads.
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0.13, 0.14, 0.17), true)
			draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color(0.34, 0.34, 0.36), 2.0)
			draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), Color(0.34, 0.34, 0.36), 2.0)
			continue
		var t: Dictionary = TEAM[tw.team]
		var base_r := TOWER_R if tw.tier != "base" else TOWER_R + 2.0
		var r := base_r * _zoom_mult()
		var frac: float = clampf(float(hp.get(key, 1.0)), 0.0, 1.0)
		# Shell (a built silhouette if the M6-D structure sheet is present, else
		# the pre-M6-D flat square shell), then a core scaled to health, then the
		# outline on top. The core/bar/flash below is unchanged either way — the
		# sprite is a skin, not a replacement for the HP-drain read.
		if struct_tex != null:
			var sts := r * 2.3
			draw_texture_rect_region(struct_tex, Rect2(c - Vector2(sts, sts) * 0.5, Vector2(sts, sts)),
				Rect2(0.0, 0.0, STRUCT_FRAME, STRUCT_FRAME),
				Color(t.dark.r, t.dark.g, t.dark.b, 0.95))
		else:
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)),
				Color(t.dark.r, t.dark.g, t.dark.b, 0.35), true)
		if frac > 0.0:
			# With the sprite present the core is a glow inset within the built
			# silhouette (capped well under its own radius) rather than a box the
			# same size as the structure — at full HP that box exactly covered the
			# sprite and defeated the entire point of drawing one. Without a sprite
			# this is unchanged: the pre-M6-D full-size draining square.
			# Circle, not a square (M6-D tester fix): the sprite's tiered plinth
			# is drawn as concentric octagons, and a square glow's corners reach
			# ~1.4x farther than its edges — at frac 1.0 the old 0.55r square's
			# corners landed almost exactly on the inner tier's own vertices,
			# swallowing it everywhere except thin cardinal slivers and reading
			# as a plain disc. A circle at a slightly smaller radius sits inside
			# the inner tier's inradius on every side, leaving both tiers and
			# the corner merlons visible as rings even at full HP.
			var cr := r * frac * 0.46 if struct_tex != null else r * frac
			if struct_tex != null:
				draw_circle(c, cr, t.dark)
			else:
				draw_rect(Rect2(c - Vector2(cr, cr), Vector2(cr * 2, cr * 2)), t.dark, true)
		if struct_tex != null:
			draw_arc(c, r + 1.0, 0, TAU, 20, t.ring, 1.5, true)
		else:
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), t.ring, false, 1.5)
		_draw_siege_pulse(c, r + 3.0, float(siege.get(key, 0.0)))
		if frac >= 1.0:
			continue
		_draw_bar(c + Vector2(0, r + 6.0), frac, _hp_color(frac), true)
		# Under real pressure it also flashes, so the eye is pulled to the siege.
		if frac < 0.35:
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 110.0)
			draw_rect(Rect2(c - Vector2(r + 2, r + 2), Vector2((r + 2) * 2, (r + 2) * 2)),
				Color(1.0, 0.45, 0.35, 0.35 + 0.4 * pulse), false, 2.0)


## "This structure is losing health right now." `heat` is 1 at the moment of the
## hit and fades out, so a siege reads as ongoing work rather than a number that
## quietly changed.
func _draw_siege_pulse(c: Vector2, r: float, heat: float) -> void:
	if heat <= 0.0:
		return
	var grow := r + 7.0 * (1.0 - heat)
	draw_arc(c, grow, 0, TAU, 24, Color(1.0, 0.55, 0.25, 0.85 * heat), 2.4, true)
	for i in 4:
		var dir := Vector2.from_angle(TAU * float(i) / 4.0 + 0.4)
		draw_line(c + dir * (grow + 1.0), c + dir * (grow + 5.0),
			Color(1.0, 0.7, 0.4, 0.8 * heat), 2.0, true)


## Minion waves. Drawn under the champions so they read as background pressure:
## which lane is pushed, and by whom, at a glance.
func _draw_minions() -> void:
	var ms := float(Time.get_ticks_msec())
	var dots: Array = frame.get("minions", [])
	var mr := MINION_R * _zoom_mult()
	for i in dots.size():
		var mn: Dictionary = dots[i]
		var c := _w2s(mn.pos)
		var col: Color = TEAM[mn.team].fill
		draw_circle(c, mr, Color(col.r, col.g, col.b, 0.75))
		if not mn.has("hit"):
			continue
		# This wave is chipping a structure right now, and in this sim the wave is
		# what takes a turret — and then the nexus. Left as walking dots, that read
		# as "the nexus fell on its own" (2026-07-26 designer note). Each minion
		# pokes at the structure on its own beat, so a clump reads as a crew at work.
		var dir := _w2s(mn.hit) - c
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var beat := 0.5 + 0.5 * sin(ms / 70.0 + float(i) * 1.7)
		draw_line(c + dir * mr, c + dir * (mr + 2.0 + 4.0 * beat),
			Color(1.0, 0.72, 0.38, 0.30 + 0.55 * beat), 1.6, true)


func _draw_wards() -> void:
	for wd: Dictionary in frame.get("wards", []):
		var c := _w2s(wd.pos)
		var col: Color = TEAM[wd.team].ring
		col.a = wd.alpha
		draw_arc(c, 4.0, 0, TAU, 12, col, 1.5, true)
		draw_circle(c, 1.5, col)


## One drawn beat per swing the sim fired. Ranged characters send a projectile
## across to the target, melee ones swing an arc at it; either way the last part
## of the beat lands as a spark on the victim, so an exchange reads as blows
## being traded rather than two dots resting next to each other.
func _draw_beats() -> void:
	var r := _champ_r()
	for b: Dictionary in frame.get("beats", []):
		var from := _w2s(b.from)
		var to := _w2s(b.to)
		var col: Color = TEAM[b.team].ring
		var f: float = b.frac
		var gap := to - from
		if gap.length() < 0.001:
			continue
		if b.ranged:
			var head := from.lerp(to, f)
			var tail := from.lerp(to, maxf(f - 0.28, 0.0))
			draw_line(tail, head, Color(col.r, col.g, col.b, 0.5), 1.6, true)
			draw_circle(head, 2.6, Color(col.r, col.g, col.b, 0.95))
		else:
			var ang := gap.angle()
			var centre := from + gap.normalized() * minf(gap.length(), r * 1.6) * 0.6
			var spread: float = 1.15 - 0.7 * f
			draw_arc(centre, r * 0.85, ang - spread, ang + spread, 12,
				Color(1.0, 0.95, 0.85, 0.9 * (1.0 - f)), 2.2, true)
		if f > 0.65:
			var s: float = (f - 0.65) / 0.35
			draw_circle(to, 1.5 + 3.0 * (1.0 - s), Color(1.0, 0.92, 0.72, 0.85 * (1.0 - s)))


## The CC link: victim tied back to whoever locked it, for as long as the lock
## runs. Dashed so it reads as a hold rather than an attack line.
func _draw_tethers() -> void:
	const DASHES := 9
	for th: Dictionary in frame.get("tethers", []):
		var from := _w2s(th.from)
		var to := _w2s(th.to)
		var col: Color = th.color
		col.a = th.alpha
		for i in DASHES:
			if i % 2 == 1:
				continue
			draw_line(from.lerp(to, float(i) / DASHES),
				from.lerp(to, float(i + 1) / DASHES), col, 1.8, true)


## The catch, on the victim. A slow is an icy ring with crystalline spurs (it
## drags you); a hard lock is an amber ring with stars orbiting the head (you are
## not going anywhere). Either way it lasts exactly as long as the sim's CC does.
func _draw_cc_mark(c: Vector2, r: float, stunned: bool) -> void:
	if stunned:
		draw_arc(c, r + 3.0, 0, TAU, 24, Color(1.0, 0.82, 0.30, 0.85), 2.2, true)
		var phase := float(Time.get_ticks_msec()) / 260.0
		for i in 3:
			var a := phase + TAU * float(i) / 3.0
			var orbit := Vector2(cos(a) * (r + 4.0), sin(a) * (r + 4.0) * 0.35)
			draw_circle(c + orbit - Vector2(0, r + 5.0), 2.0, Color(1.0, 0.95, 0.55, 0.95))
		return
	draw_arc(c, r + 3.0, 0, TAU, 24, Color(0.45, 0.85, 1.0, 0.85), 2.0, true)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.25
		var dir := Vector2.from_angle(a)
		draw_line(c + dir * (r + 1.0), c + dir * (r + 5.5),
			Color(0.60, 0.92, 1.0, 0.9), 1.6, true)


func _draw_champions() -> void:
	var textures: Dictionary = geom.get("textures", {})
	var r := _champ_r()
	var champs: Array = frame.get("champs", [])
	# Screen positions up front: the handle labels need to know who is crowded.
	var screen: Array = []
	for ch: Dictionary in champs:
		screen.append(_w2s(ch.pos))
	for i in champs.size():
		var ch: Dictionary = champs[i]
		var base: Vector2 = screen[i]
		var t: Dictionary = TEAM[ch.team]
		if not ch.alive:
			if ch.get("dying", false):
				_draw_dying(ch, t, i)
			else:
				_draw_dead(base, ch, t, i)
			continue
		var c: Vector2 = base + ch.get("shake", Vector2.ZERO)

		# Fight / ult flares (drawn under the disc).
		if ch.get("casting", 0.0) > 0.0:
			var a: float = ch.casting
			draw_arc(c, r + 6 + (1.0 - a) * 16.0, 0, TAU, 24,
				Color(1.0, 0.95, 0.5, a * 0.8), 2.0, true)
		# Trading blows — a swing given or taken in the last second, not merely
		# "an enemy is nearby". Hot red so it never reads as the amber CC mark.
		if ch.get("exchanging", false):
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 90.0)
			draw_arc(c, r + 4, 0, TAU, 20, Color(1.0, 0.42, 0.24, 0.45 + 0.45 * pulse), 2.2, true)
		# Backing off: chevrons trailing behind, pointing the way out. A retreat is
		# a decision the sim makes constantly and the viewer used to draw as a fight.
		if ch.get("backing_off", false):
			_draw_retreat(c, r, ch.get("facing", Vector2.RIGHT), t)
		if ch.get("recalling", false):
			var rp := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 120.0)
			draw_arc(c, r + 8, 0, TAU, 24, Color(0.4, 0.9, 0.9, 0.35 + 0.3 * rp), 2.0, true)

		# Body: real sprite if the character's texture exists, else the placeholder
		# silhouette for its role. Keyed char_id+team (see main.gd _char_textures) —
		# same-role players share a champion_pool, so both sides can field the same
		# character in one match.
		_draw_body(c, r, ch, t, textures.get("%s|%s" % [ch.char_id, ch.team], null))

		# Just hit: a white flash on the body itself. HP bars move a couple of
		# pixels a swing, which is why a real exchange read as "nothing is
		# happening" (2026-07-25 playtest, remark 2).
		var flinch: float = ch.get("flinch", 0.0)
		if flinch > 0.0:
			draw_circle(c, r + 1.5, Color(1.0, 0.95, 0.92, 0.55 * flinch))
		# Caught: the lock/slow mark sits over the body so it can't be missed.
		if ch.get("stunned", false) or ch.get("slowed", false):
			_draw_cc_mark(c, r, ch.get("stunned", false))

		# Level badge (top-right of disc).
		var bp := c + Vector2(r * 0.9, -r * 0.9)
		draw_circle(bp, 6.5 * _zoom_mult(), Color(0.08, 0.09, 0.12, 0.9))
		_centered(str(ch.level), bp, _fs(10), Color(0.95, 0.9, 0.7))

		# Health bar + handle. Colour shifts green -> amber -> red as it drops,
		# so a hurt player is readable without reading the bar length.
		var hp_frac: float = ch.get("hp_frac", 1.0)
		_draw_bar(c + Vector2(0, r + 4), hp_frac, _hp_color(hp_frac))
		# Handles in a grouped fight would print on top of each other, so each one
		# in a crowd drops to its own line instead of overlapping.
		_centered(ch.name, c + Vector2(0, r + 16 + 11.0 * _zoom_mult() * _label_slot(screen, i)),
			_fs(10), Color(0.85, 0.87, 0.92))


## Combat body: the shared placeholder sprite sheet (M6-D — animated pixel body,
## idle/run/attack/cast/hurt/die/recall, `ch.anim_state`/`ch.anim_col` computed
## by game/main.gd off flags the sim already reports) if the character's
## texture resolves, else the pre-M6-D procedural silhouette. Either way the
## body is tinted by team and marked per role by the letter badge — reusing
## five different procedural shapes for a shared *sprite* body would just be
## five more sheets to draw and animate, which is exactly what CLAUDE.md's
## original placeholder plan ruled out ("one shared character sprite,
## recolored/tinted per team and marked per role (icon or letter)").
##
## The placeholder contract from CLAUDE.md is unchanged: a character's `sprite`
## data field, when it points at a real texture, takes over here with no code
## change, and the same facing/tint applies to it — a real per-character
## replacement is expected to follow the same sheet layout (data/animation.json)
## the placeholder does, so nothing here has to special-case which texture it is.
func _draw_body(c: Vector2, r: float, ch: Dictionary, t: Dictionary, tex: Texture2D) -> void:
	# World Y is flipped on the way to the screen, so the look vector flips with it.
	var look: Vector2 = ch.get("facing", Vector2.RIGHT)
	var ang := Vector2(look.x, -look.y).angle()
	if tex != null:
		_draw_sprite(c, r, tex, t.fill, look.x < 0.0,
			String(ch.get("anim_state", "idle")), int(ch.get("anim_col", 0)))
		draw_arc(c, r + 1.0, 0, TAU, 20, t.ring, 2.0, true)
	else:
		var pts := _role_shape(String(ch.role), c, r, ang)
		draw_colored_polygon(pts, t.fill)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, t.ring, 1.6, true)
		if ch.role == "support":
			# Octagon plus a cross: the helper reads at a glance.
			var f := Vector2.from_angle(ang)
			var s := f.orthogonal()
			draw_line(c - f * r * 0.55, c + f * r * 0.55, t.ring, 1.6, true)
			draw_line(c - s * r * 0.55, c + s * r * 0.55, t.ring, 1.6, true)
	# Facing pip: which way this player is pointed (at its target, or where it walks).
	var nose := Vector2.from_angle(ang)
	draw_line(c + nose * r * 0.7, c + nose * (r + 3.5), t.ring, 2.0, true)
	# The procedural support shape already marks itself with the octagon+cross
	# above; a sprite body has no such per-role silhouette, so it always gets
	# the letter — same badge every other role already relies on.
	#
	# Corner badge, not a center overlay (M6-D tester fix): the level badge
	# already claims the top-right corner at bp = c + (0.9r, -0.9r) with its
	# own dark backdrop disc, drawn *after* this. A role letter centered on
	# the body used to sit directly under that badge at zoomed-in fights
	# (zoom ~3.2-4.0, where the badge grows large enough to reach past the
	# body's center) and read as unlabeled. Mirroring the level badge into the
	# opposite corner — same offset magnitude, same backdrop/size formula —
	# keeps the two markers geometrically as far apart as the disc allows at
	# every zoom level, and gives the letter the same guaranteed contrast
	# against terrain that the level badge already relies on.
	if tex != null or ch.role != "support":
		var lp := c + Vector2(-r * 0.9, -r * 0.9)
		draw_circle(lp, 6.5 * _zoom_mult(), Color(0.08, 0.09, 0.12, 0.9))
		_centered(ROLE_LETTER.get(ch.role, "?"), lp, _fs(10), Color(0.95, 0.95, 0.98))


## Selects and draws one frame of the shared sheet: `state` picks the row
## (falling back to row 0 / idle if the sheet has no row by that name — should
## not happen, game/main.gd's --selftest asserts anim_state always has one),
## `col` the column, both already resolved by the caller. Horizontal-flip-only
## facing (M6-D design call): a placeholder sheet drawn facing one way and
## mirrored reads fine at this size and is far cheaper than a directional frame
## set; the separate facing pip already carries the *exact* look direction.
func _draw_sprite(c: Vector2, r: float, tex: Texture2D, tint: Color, flip: bool,
		state: String, col: int) -> void:
	var fw: float = float(anim_sheet.get("frame_px", 64.0))
	var cols: int = maxi(int(anim_sheet.get("cols", 4)), 1)
	var rows: Array = anim_sheet.get("rows", ANIM_ROWS)
	var row := maxi(rows.find(state), 0)
	var cc := clampi(col, 0, cols - 1)
	var src := Rect2(float(cc) * fw, float(row) * fw, fw, fw)
	if flip:
		# Negative-width src rect: a cheap, well-supported way to mirror the UV
		# read without a second flipped copy of the sheet.
		src = Rect2(src.position + Vector2(fw, 0.0), Vector2(-fw, fw))
	var ts := r * 2.2
	draw_texture_rect_region(tex, Rect2(c - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), src, tint)


## The die pose (M6-D): a short window, right where the body actually fell
## (`ch.death_pos`, from the kill event — the snapshot row itself has already
## snapped the dead player to the fountain by the time `alive` reads false),
## fading out as it hands off to the established fountain treatment below. Only
## draws anything if a real texture exists; the procedural fallback has no die
## pose, so an untextured death goes straight to `_draw_dead` as it always has.
## (Every real texture's sheet — placeholder or M6-D2's LPC-derived art — is
## guaranteed a "die" row: game/main.gd's --selftest asserts it.)
func _draw_dying(ch: Dictionary, t: Dictionary, row: int) -> void:
	var textures: Dictionary = geom.get("textures", {})
	var tex: Texture2D = textures.get("%s|%s" % [ch.char_id, ch.team], null)
	if tex == null:
		_draw_dead(_w2s(ch.pos), ch, t, row)
		return
	var c := _w2s(ch.get("death_pos", ch.pos))
	var r := _champ_r()
	var fade: float = ch.get("death_fade", 1.0)
	var m := Color(t.fill.r, t.fill.g, t.fill.b, t.fill.a * fade)
	var look: Vector2 = ch.get("facing", Vector2.RIGHT)
	_draw_sprite(c, r, tex, m, look.x < 0.0, "die", int(ch.get("anim_col", 0)))
	draw_arc(c, r + 1.0, 0, TAU, 20, Color(t.ring.r, t.ring.g, t.ring.b, t.ring.a * fade), 2.0, true)


## Role silhouettes: broad hexagon for the toplaner (it stands in front), an
## arrowhead for the jungler (it arrives), a star for the mid (it casts), a
## pentagon for the carry, an octagon for the support.
func _role_shape(role: String, c: Vector2, r: float, ang: float) -> PackedVector2Array:
	match role:
		"top":
			return _ngon(6, c, r * 1.1, ang)
		"jungle":
			var f := Vector2.from_angle(ang)
			var s := f.orthogonal()
			return PackedVector2Array([
				c + f * r * 1.45, c - f * r * 0.65 + s * r * 1.0,
				c - f * r * 0.2, c - f * r * 0.65 - s * r * 1.0])
		"mid":
			return _star(4, c, r * 1.25, r * 0.52, ang)
		"carry":
			return _ngon(5, c, r * 1.1, ang)
	return _ngon(8, c, r, ang)


func _ngon(sides: int, c: Vector2, radius: float, ang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(c + Vector2.from_angle(ang + TAU * float(i) / float(sides)) * radius)
	return pts


func _star(spikes: int, c: Vector2, outer: float, inner: float, ang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var radius := outer if i % 2 == 0 else inner
		pts.append(c + Vector2.from_angle(ang + TAU * float(i) / float(spikes * 2)) * radius)
	return pts


## How many lines down this champion's handle has to go to clear its neighbours.
## Grows with zoom along with the label font itself — the crowding distance is
## only meaningful relative to how wide the name it's protecting against now is.
func _label_slot(screen: Array, i: int) -> int:
	const CLEARANCE := 42.0
	var clearance := CLEARANCE * _zoom_mult()
	var slot := 0
	for j in i:
		if screen[j].distance_to(screen[i]) < clearance:
			slot += 1
	return slot


## The dead sit in the fountain. The sim parks them all on the exact base point,
## so playback fans them around it by row index — five grey discs on one pixel
## tell you nothing about who is down and for how long.
func _draw_dead(base: Vector2, ch: Dictionary, t: Dictionary, row: int) -> void:
	var r := _champ_r()
	var c := base + Vector2.from_angle(TAU * float(row % 5) / 5.0 - PI * 0.5) * (r * 1.9)
	draw_circle(c, r, Color(0.24, 0.25, 0.28))
	draw_arc(c, r, 0, TAU, 20, Color(0.4, 0.4, 0.42), 1.5, true)
	# Skull-ish mark.
	draw_line(c + Vector2(-3, -2), c + Vector2(3, -2), Color(0.6, 0.6, 0.6), 1.5)
	draw_line(c + Vector2(0, -4), c + Vector2(0, 3), Color(0.6, 0.6, 0.6), 1.5)
	_draw_bar(c + Vector2(0, r + 4), ch.get("respawn_frac", 0.0), t.dark)
	_centered(ch.name, c + Vector2(0, r + 14), _fs(9), Color(0.5, 0.52, 0.56))


func _hp_color(frac: float) -> Color:
	if frac > 0.5:
		return Color(0.40, 0.85, 0.45)
	if frac > 0.25:
		return Color(0.95, 0.75, 0.25)
	return Color(0.95, 0.35, 0.30)


## Backing off, drawn as motion: two chevrons behind the body pointing the way it
## is leaving. The sim breaks off fights constantly (hysteresis, on purpose), and
## before this a retreat looked exactly like a fight.
func _draw_retreat(c: Vector2, r: float, look: Vector2, t: Dictionary) -> void:
	var ang := Vector2(look.x, -look.y).angle()
	var back := Vector2.from_angle(ang + PI)
	var side := back.orthogonal()
	var col := Color(t.ring.r, t.ring.g, t.ring.b, 0.55)
	for i in 2:
		var base := c + back * (r + 3.0 + 4.0 * float(i))
		draw_line(base + side * 3.5, base - back * 3.0, col, 1.6, true)
		draw_line(base - side * 3.5, base - back * 3.0, col, 1.6, true)


## Floating damage numbers. The one unambiguous answer to "is the life actually
## moving?" — every number here is a real HP delta the sim produced, read off
## consecutive snapshots (MatchViewer._build_hits).
func _draw_pops() -> void:
	for h: Dictionary in frame.get("pops", []):
		var age: float = h.age
		var c := _w2s(h.pos) - Vector2(0, _champ_r() + 6.0 + 20.0 * age)
		var alpha := clampf(1.0 - age * age, 0.0, 1.0)
		var heal: bool = h.heal
		var col := Color(0.55, 1.0, 0.6, alpha) if heal else Color(1.0, 0.86, 0.45, alpha)
		var txt: String = ("+%d" if heal else "%d") % int(h.amount)
		var fsize := _fs(11 if int(h.amount) < 120 else 14)
		# Dark outline: numbers land on top of bodies, minions and lane lines.
		_centered(txt, c + Vector2(1, 1), fsize, Color(0.0, 0.0, 0.0, 0.7 * alpha))
		_centered(txt, c, fsize, col)


## `strong` is for structures: a wider, taller, outlined bar. The player-sized
## one is deliberately small — ten of them share the screen.
func _draw_bar(center: Vector2, frac: float, col: Color, strong := false) -> void:
	var m := _zoom_mult()
	var w := (30.0 if strong else 22.0) * m
	var h := (5.5 if strong else 3.5) * m
	var tl := center - Vector2(w * 0.5, h * 0.5)
	draw_rect(Rect2(tl, Vector2(w, h)), Color(0.05, 0.06, 0.08, 0.9), true)
	if frac > 0.0:
		draw_rect(Rect2(tl, Vector2(w * clampf(frac, 0.0, 1.0), h)), col, true)
	if strong:
		draw_rect(Rect2(tl, Vector2(w, h)), Color(0.0, 0.0, 0.0, 0.55), false, 1.0)


## The transient layer: everything with a lifetime. `progress` (0 -> 1) is the
## effect's age, resolved by the viewer; nothing here keeps state of its own.
##
## The ability shapes carry `heavy` when they came from an ultimate — same shape
## family, bigger and louder — so a level-6 ult never reads like a basic ability.
func _draw_effects() -> void:
	for e: Dictionary in frame.get("effects", []):
		var c := _w2s(e.pos)
		var col: Color = e.color
		col.a = e.alpha
		var p: float = e.get("progress", 0.0)
		var heavy: bool = e.get("heavy", false)
		match e.kind:
			"ring":
				draw_arc(c, e.radius, 0, TAU, 28, col, 2.5, true)
			"text":
				var rise: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise), _fs(int(e.get("font", 13))), col)
			"banner":
				var rise2: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise2), _fs(int(e.get("font", 18))), col)
			"tag":
				_draw_tag(c - Vector2(0, e.get("rise", 0.0) + 12.0), e.text,
					_fs(int(e.get("font", 12))), col, e.alpha)
			"shockwave":
				_draw_shockwave(c, float(e.get("world_radius", 6.0)) * _scale(), p, e.color, heavy)
			"beam":
				_draw_beam(c, _w2s(e.get("to", e.pos)), p, e.color, heavy,
					e.get("pierce", false), e.get("finisher", false))
			"bloom":
				var rb := _champ_r() + 4.0 + 12.0 * p
				draw_circle(c, rb * 0.92, Color(col.r, col.g, col.b, 0.16 * (1.0 - p)))
				draw_arc(c, rb, 0, TAU, 28, Color(col.r, col.g, col.b, 0.9 * (1.0 - p)),
					3.0 if heavy else 2.0, true)
			"cast_flash":
				# The caster flares white-hot for an instant, so an ultimate is visible
				# even when its impact lands on someone else across the fight.
				var cf := 1.0 - p
				draw_circle(c, (_champ_r() + 3.0) * (1.0 + 1.6 * p),
					Color(1.0, 1.0, 1.0, 0.30 * cf))
				draw_arc(c, (_champ_r() + 5.0) * (1.0 + 2.2 * p), 0, TAU, 28,
					Color(col.r, col.g, col.b, 0.9 * cf), 3.0 * cf + 1.0, true)
			"aura":
				var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 70.0)
				var ra := _champ_r() + 4.0 + 2.5 * pulse
				draw_arc(c, ra, 0, TAU, 24, Color(col.r, col.g, col.b, 0.75 * (1.0 - p)), 2.5, true)
				for i in 8:
					var ang := TAU * float(i) / 8.0 + pulse
					var dir := Vector2.from_angle(ang)
					draw_line(c + dir * ra, c + dir * (ra + 4.0),
						Color(col.r, col.g, col.b, 0.7 * (1.0 - p)), 1.6, true)


## An ability's area, at its real radius: a flash disc, a ring racing out to the
## edge of the effect, and — for an ultimate — the spikes that give it its punch.
func _draw_shockwave(c: Vector2, full_r: float, p: float, col: Color, heavy: bool) -> void:
	var grown := full_r * (0.28 + 0.72 * (1.0 - pow(1.0 - p, 3.0)))
	draw_circle(c, grown, Color(col.r, col.g, col.b, (0.28 if heavy else 0.14) * (1.0 - p)))
	draw_arc(c, grown, 0, TAU, 40, Color(col.r, col.g, col.b, 1.0 - p),
		(4.0 if heavy else 2.0) * (1.0 - 0.5 * p), true)
	if not heavy or p > 0.45:
		return
	var fade := 1.0 - p / 0.45
	for i in 8:
		var dir := Vector2.from_angle(TAU * float(i) / 8.0 + 0.2)
		draw_line(c + dir * grown * 0.55, c + dir * grown * 1.15,
			Color(1.0, 1.0, 1.0, 0.5 * fade), 2.0, true)


## A single-target ability: the line goes out, then bursts on the victim. A snipe
## carries through past its target; an execute stamps a cross where it finished.
func _draw_beam(from: Vector2, to: Vector2, p: float, col: Color, heavy: bool,
		pierce: bool, finisher: bool) -> void:
	var gap := to - from
	if gap.length() < 0.001:
		return
	var head := from.lerp(to, minf(p / 0.3, 1.0))
	var width: float = maxf((5.0 if heavy else 2.5) * (1.0 - 0.6 * p), 1.2)
	draw_line(from, head, Color(col.r, col.g, col.b, 0.95 * (1.0 - 0.7 * p)), width, true)
	if pierce and p >= 0.3:
		var beyond := gap.normalized() * 22.0 * (1.0 - p)
		draw_line(to, to + beyond, Color(col.r, col.g, col.b, 0.6 * (1.0 - p)), width * 0.7, true)
	if p < 0.3:
		return
	var burst := (p - 0.3) / 0.7
	draw_circle(to, 2.0 + (width + 6.0) * (1.0 - burst),
		Color(col.r, col.g, col.b, 0.8 * (1.0 - burst)))
	if finisher:
		var arm := (_champ_r() + 5.0) * (1.0 - burst * 0.4)
		var fc := Color(1.0, 0.9, 0.9, 0.9 * (1.0 - burst))
		draw_line(to + Vector2(-arm, -arm), to + Vector2(arm, arm), fc, 2.4, true)
		draw_line(to + Vector2(-arm, arm), to + Vector2(arm, -arm), fc, 2.4, true)


## Text on a dark pill. A bare string disappears over minions and rings; this
## keeps an ability name (or a CC tag) readable in the middle of a fight.
func _draw_tag(centre: Vector2, text: String, font_size: int, col: Color, alpha: float) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(5.0, 3.0)
	var rect := Rect2(centre - sz * 0.5 - pad, sz + pad * 2.0)
	draw_rect(rect, Color(0.04, 0.05, 0.08, 0.75 * alpha), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.85 * alpha), false, 1.0)
	_centered(text, centre, font_size, Color(col.r, col.g, col.b, alpha))


func _centered(text: String, center: Vector2, font_size: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := center - sz * 0.5 + Vector2(0, sz.y * 0.5 - _font.get_descent(font_size) * 0.3)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _enemy(team: String) -> String:
	return "red" if team == "blue" else "blue"


# --- minimap --------------------------------------------------------------------
# Required by this phase, not polish (BACKLOG M6-B): once zoom shows less than the
# whole world, this is the only place left that shows all of it. Bottom-left
# corner of the map panel itself, so by construction it can never collide with the
# side panel / bottom bar / top bar — those are sibling panels laid out by
# main.gd, this control never draws outside its own rect (clip_contents).
const MINIMAP_SIZE := 132.0
const MINIMAP_PAD := 8.0
const MINIMAP_MARGIN := 10.0
const C_MINIMAP_BG := Color(0.04, 0.05, 0.08, 0.90)
const C_MINIMAP_VIEWPORT := Color(1.0, 1.0, 1.0, 0.65)

func _minimap_rect() -> Rect2:
	return Rect2(Vector2(MINIMAP_MARGIN, size.y - MINIMAP_MARGIN - MINIMAP_SIZE),
		Vector2(MINIMAP_SIZE, MINIMAP_SIZE))


## Skipped once the real camera is already showing the whole map (zoom at rest):
## a minimap identical to the main view is noise, not information.
func _draw_minimap() -> void:
	if cam_zoom <= ZOOM_MIN + 0.02:
		return
	var rect := _minimap_rect()
	var mscale: float = (rect.size.x - 2.0 * MINIMAP_PAD) / world_size
	var origin := rect.position + Vector2(MINIMAP_PAD, MINIMAP_PAD)
	draw_rect(rect, C_MINIMAP_BG, true)
	# Lane skeleton, for orientation only — the minimap is a locator, not a second
	# terrain render.
	for lane: String in geom.lanes:
		var pts := PackedVector2Array()
		for p: Vector2 in geom.lanes[lane]:
			pts.append(_mini_w2s(p, origin, mscale))
		draw_polyline(pts, C_LANE_CORE, 1.0, true)
	for team: String in geom.bases:
		draw_circle(_mini_w2s(geom.bases[team], origin, mscale), 2.6, TEAM[team].fill)
	# Objective state: coloured = up, grey = down. No countdown number — the sim
	# only reports dragon_up/baron_up today, not a spawn timer (see M6-B report).
	_mini_objective(origin, mscale, geom.pits.dragon, C_DRAGON, frame.get("dragon_up", false))
	_mini_objective(origin, mscale, geom.pits.baron, C_BARON, frame.get("baron_up", false))
	# A dot per living champion, tinted by team.
	for ch: Dictionary in frame.get("champs", []):
		if not ch.get("alive", true):
			continue
		draw_circle(_mini_w2s(ch.pos, origin, mscale), 2.2, TEAM[ch.team].fill)
	# The viewport rectangle: what the main camera is currently showing, so the
	# minimap explains why the main view looks the way it does.
	var w0 := _s2w(Vector2.ZERO)
	var w1 := _s2w(size)
	var p0 := _mini_w2s(w0, origin, mscale)
	var p1 := _mini_w2s(w1, origin, mscale)
	var vp := Rect2(p0, p1 - p0).abs()
	draw_rect(vp, Color(1.0, 1.0, 1.0, 0.06), true)
	draw_rect(vp, C_MINIMAP_VIEWPORT, false, 1.2)
	draw_rect(rect, C_BORDER, false, 1.5)


func _mini_w2s(w: Vector2, origin: Vector2, mscale: float) -> Vector2:
	return origin + Vector2(w.x, world_size - w.y) * mscale


func _mini_objective(origin: Vector2, mscale: float, w: Vector2, col: Color, up: bool) -> void:
	var c := _mini_w2s(w, origin, mscale)
	draw_circle(c, 3.2, col if up else Color(0.4, 0.4, 0.42, 0.6))
