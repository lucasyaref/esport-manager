extends SceneTree
## Generates the shared placeholder pixel art (M6-D): the character sprite
## sheet at game/assets/characters/placeholder.png and the tower/nexus
## silhouette sheet at game/assets/structures/placeholder.png.
##
## "Procedural, not hand-painted" — same spirit as the terrain art being
## tile-rendered code (game/terrain_view.gd) rather than drawn in an external
## editor. Unlike tools/shoot_map.gd this runs entirely off Image pixel
## operations, no SubViewport/rendering context, so it works under
## --headless — there's nothing to display, only pixels to set and a PNG to
## write.
##
## Everything is drawn in grayscale (white = lit, mid-gray = shadow, near-black
## edge from the outline pass): game/map_view.gd tints these with
## draw_texture_rect_region(..., modulate)`, multiplying the sheet's own
## per-pixel brightness by the team colour, so white reads as the bright team
## colour and gray as a darker shade of it — one sheet, both teams, no baked-in
## colour to fight the tint (the exact constraint the phase brief called out:
## draw_texture_rect_region's tint is one colour, so shading has to come from
## luminance, not hue).
##
## Character sheet layout (rows/cols/frame size) matches data/animation.json's
## "sheet" block — if you change frame_px/cols/rows there, regenerate here too
## with matching --frame/--cols, or the two will disagree about where a pose
## lives on the sheet.
##
## Usage:
##   godot --headless --path . --script res://tools/make_sprites.gd -- [--frame=24]
##
## Both output paths are fixed (they are exactly what data/characters.json's
## "sprite" field and game/map_view.gd's STRUCT_SHEET_PATH already point at);
## there is nothing else here for the designer to configure by hand.

const CHAR_OUT := "res://game/assets/characters/placeholder.png"
const STRUCT_OUT := "res://game/assets/structures/placeholder.png"
const ROWS := ["idle", "run", "attack", "cast", "hurt", "die", "recall"]
const COLS := 4
const STRUCT_FRAME := 32

# Grayscale tones. FILL is the body's base tone, SHADE a second, dimmer tone
# for a bit of internal depth (front leg vs. back leg, etc.), EDGE the
# outline-pass colour (a silhouette pixel adjacent to empty space), HILITE a
# bright accent for weapon swings / cast glow / recall sparkle — drawn last, so
# it survives the outline pass instead of being darkened by it.
const FILL := Color(0.80, 0.80, 0.80, 1.0)
const SHADE := Color(0.55, 0.55, 0.55, 1.0)
const EDGE := Color(0.22, 0.22, 0.22, 1.0)
const HILITE := Color(1.0, 1.0, 1.0, 1.0)


func _initialize() -> void:
	var args := _parse_args()
	var frame := int(args.get("frame", "24"))

	var char_img := Image.create_empty(frame * COLS, frame * ROWS.size(), false, Image.FORMAT_RGBA8)
	for row in ROWS.size():
		var state: String = ROWS[row]
		for col in COLS:
			var buf := _new_buf(frame)
			_draw_pose(buf, frame, state, col)
			buf = _outline_pass(buf, frame, EDGE)
			_draw_extras(buf, frame, state, col)  # bright accents, after the outline pass
			_blit(char_img, buf, frame, col * frame, row * frame)
	_write(char_img, CHAR_OUT)

	var struct_img := Image.create_empty(STRUCT_FRAME * 2, STRUCT_FRAME, false, Image.FORMAT_RGBA8)
	var tower_buf := _new_buf(STRUCT_FRAME)
	_draw_tower(tower_buf, STRUCT_FRAME)
	tower_buf = _outline_pass(tower_buf, STRUCT_FRAME, EDGE)
	_blit(struct_img, tower_buf, STRUCT_FRAME, 0, 0)
	var nexus_buf := _new_buf(STRUCT_FRAME)
	_draw_nexus(nexus_buf, STRUCT_FRAME)
	nexus_buf = _outline_pass(nexus_buf, STRUCT_FRAME, EDGE)
	_blit(struct_img, nexus_buf, STRUCT_FRAME, STRUCT_FRAME, 0)
	_write(struct_img, STRUCT_OUT)

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


func _write(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		print("ERROR: could not write %s (%d)" % [path, err])
		quit(1)
		return
	print("wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])


# --- local per-frame pixel buffer ----------------------------------------------
# Every pose is composed in its own FRAME x FRAME buffer of Color (alpha 0 =
# untouched) before being blitted onto the sheet — the outline pass (a
# silhouette pixel next to empty space becomes EDGE) needs to see the whole
# pose at once, which a direct-to-sheet draw can't give it without also
# catching the neighbouring frame's pixels at the buffer's edge.

func _new_buf(n: int) -> Array:
	var a: Array = []
	a.resize(n * n)
	a.fill(Color(0, 0, 0, 0))
	return a


func _lset(buf: Array, n: int, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	buf[y * n + x] = col


func _lget(buf: Array, n: int, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= n or y >= n:
		return Color(0, 0, 0, 0)
	return buf[y * n + x]


func _lrect(buf: Array, n: int, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_lset(buf, n, x, y, col)


func _lcircle(buf: Array, n: int, cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				_lset(buf, n, x, y, col)


func _lline(buf: Array, n: int, x0: int, y0: int, x1: int, y1: int, col: Color, w := 1) -> void:
	# Integer Bresenham; `w` thickens the line by also stamping the
	# perpendicular neighbour, enough for a 1-2px weapon/spire mark at this scale.
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		_lset(buf, n, x, y, col)
		if w > 1:
			_lset(buf, n, x + 1, y, col)
			_lset(buf, n, x, y + 1, col)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


func _lpolygon(buf: Array, n: int, pts: PackedVector2Array, col: Color) -> void:
	# Even-odd ray-cast fill — correct for the non-convex star shapes below, not
	# just convex ones. Cheap enough at 24-32px per side to brute-force per pixel.
	for y in n:
		for x in n:
			if _point_in_poly(pts, float(x) + 0.5, float(y) + 0.5):
				_lset(buf, n, x, y, col)


func _point_in_poly(pts: PackedVector2Array, x: float, y: float) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var xi := pts[i].x
		var yi := pts[i].y
		var xj := pts[j].x
		var yj := pts[j].y
		if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
			inside = not inside
		j = i
	return inside


func _ngon(cx: float, cy: float, radius: float, sides: int, ang0 := -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := ang0 + TAU * float(i) / float(sides)
		pts.append(Vector2(cx + cos(a) * radius, cy + sin(a) * radius))
	return pts


func _star(cx: float, cy: float, outer: float, inner: float, spikes: int,
		ang0 := -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var radius := outer if i % 2 == 0 else inner
		var a := ang0 + TAU * float(i) / float(spikes * 2)
		pts.append(Vector2(cx + cos(a) * radius, cy + sin(a) * radius))
	return pts


## A filled silhouette pixel next to an empty one becomes `edge_col` — gives
## every pose a consistent dark rim with no per-shape outline bookkeeping.
func _outline_pass(buf: Array, n: int, edge_col: Color) -> Array:
	var out := buf.duplicate()
	const NEI := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in n:
		for x in n:
			var c: Color = _lget(buf, n, x, y)
			if c.a <= 0.0:
				continue
			for d: Vector2i in NEI:
				if _lget(buf, n, x + d.x, y + d.y).a <= 0.0:
					out[y * n + x] = edge_col
					break
	return out


func _blit(img: Image, buf: Array, n: int, ox: int, oy: int) -> void:
	for y in n:
		for x in n:
			var c: Color = buf[y * n + x]
			if c.a > 0.0:
				img.set_pixel(ox + x, oy + y, c)


# --- character poses ------------------------------------------------------------
# One shared humanoid silhouette, facing right (screen-space +x — see
# game/map_view.gd's horizontal-flip for left), 24px-frame coordinates below.
# `dx`/`dy` shift the whole body (lean/bob), the per-limb `*_dy` offsets pose
# the arms, `leg_l_dx`/`leg_r_dx` stagger the legs *sideways* rather than up or
# down — a leg's own top edge always sits exactly at the torso's bottom edge,
# so no combination of these can pull a leg away from the torso and leave the
# outline pass a detached, separately-ringed blob hanging in mid-air (the
# first version of "run" did exactly that with a vertical leg offset). Frame
# size is a parameter (see --frame) but the pose geometry below is only tuned
# to read at the default 24px; a very different --frame would need the
# offsets re-tuned, not just scaled, since these are pixel-integer positions,
# not proportions.

func _humanoid(buf: Array, n: int, dx: int, dy: int, leg_l_dx: int, leg_r_dx: int,
		arm_l_dy: int, arm_r_dy: int, torso_h: int) -> void:
	var cx := 12 + dx
	var top := 10 + dy
	var leg_y := top + torso_h
	_lcircle(buf, n, cx, 7 + dy, 3, FILL)
	_lrect(buf, n, cx - 3, top, 6, torso_h, FILL)
	_lrect(buf, n, cx - 5, 11 + dy + arm_l_dy, 2, 4, SHADE)
	_lrect(buf, n, cx + 3, 11 + dy + arm_r_dy, 2, 4, FILL)
	_lrect(buf, n, cx - 3 + leg_l_dx, leg_y, 2, 4, SHADE)
	_lrect(buf, n, cx + 1 + leg_r_dx, leg_y, 2, 4, FILL)


## Base silhouette per state/column — the humanoid only; bright accents
## (weapon swing, cast glow, recall sparkle) are added afterward by
## `_draw_extras`, past the outline pass, so they read as a highlight rather
## than getting darkened into the silhouette's rim.
func _draw_pose(buf: Array, n: int, state: String, col: int) -> void:
	match state:
		"idle":
			# A gentle four-frame breathing bob.
			var bob: int = [0, -1, 0, 1][col]
			_humanoid(buf, n, 0, bob, 0, 0, 0, 0, 7)
		"run":
			# Legs stagger sideways (opposite directions) and arms counter-swing;
			# frames 1/3 are the neutral catch between strides, same shape as
			# idle's own top-of-bob frame.
			var poses := [
				{"ll": -1, "lr": 1, "al": 1, "ar": -1, "dy": 0},
				{"ll": 0, "lr": 0, "al": 0, "ar": 0, "dy": -1},
				{"ll": 1, "lr": -1, "al": -1, "ar": 1, "dy": 0},
				{"ll": 0, "lr": 0, "al": 0, "ar": 0, "dy": -1},
			]
			var p: Dictionary = poses[col]
			_humanoid(buf, n, 0, p.dy, p.ll, p.lr, p.al, p.ar, 7)
		"attack":
			# Windup (arm drawn back) -> strike (lean in, arm forward) ->
			# follow-through -> reset. `_draw_extras` adds the weapon line on
			# the strike/follow-through columns, timed with game/main.gd's
			# attack-pose window (the same SWING_TICKS the beat itself uses).
			var poses := [
				{"dx": -1, "ar": -2}, {"dx": 1, "ar": 1}, {"dx": 1, "ar": 2}, {"dx": 0, "ar": 0},
			]
			var p: Dictionary = poses[col]
			_humanoid(buf, n, p.dx, 0, 0, 0, 0, p.ar, 7)
		"cast":
			# Arms raise and stay there; `_draw_extras` grows a glow above the
			# head across the same four columns.
			var arm: int = [-2, -3, -3, -1][col]
			_humanoid(buf, n, 0, 0, 0, 0, arm, arm, 7)
		"hurt":
			# Recoil away from "forward", easing back toward neutral.
			var dx: int = [-2, -3, -2, -1][col]
			var arm: int = [1, 1, 0, 0][col]
			_humanoid(buf, n, dx, 0, 0, 0, arm, arm, 7)
		"die":
			# Collapsing over four frames: shrinking torso, sinking lower, until
			# a low, flat silhouette. game/main.gd fades this out over
			# data/animation.json's timing.die_ticks as it plays.
			var poses := [
				{"dx": -1, "dy": 1, "th": 6}, {"dx": -2, "dy": 3, "th": 4},
				{"dx": -3, "dy": 6, "th": 2}, {"dx": -3, "dy": 8, "th": 1},
			]
			var p: Dictionary = poses[col]
			_humanoid(buf, n, p.dx, p.dy, 0, 0, 0, 0, p.th)
		"recall":
			# Near-idle (the player chose to stand still and channel) with a
			# rising sparkle added by `_draw_extras`.
			var bob: int = [0, -1, 0, -1][col]
			_humanoid(buf, n, 0, bob, 0, 0, 0, 0, 7)
		_:
			_humanoid(buf, n, 0, 0, 0, 0, 0, 0, 7)


## Bright accents layered on top of the already-outlined silhouette: a weapon
## swing, a rising cast glow, or recall sparkles. Kept separate from
## `_draw_pose` so the outline pass never darkens them.
func _draw_extras(buf: Array, n: int, state: String, col: int) -> void:
	match state:
		"attack":
			if col == 1:
				_lline(buf, n, 17, 12, 22, 12, HILITE, 2)
			elif col == 2:
				_lline(buf, n, 17, 13, 20, 13, HILITE, 1)
		"cast":
			# A small hovering orb above the head, clear of it (head spans down to
			# y=4) so a growing radius reads as a charging glow, not a fatter head.
			var r: int = [1, 2, 2, 1][col]
			_lcircle(buf, n, 12, 1, r, HILITE)
		"recall":
			var spark: Vector2i = [Vector2i(9, 4), Vector2i(15, 2), Vector2i(9, 0), Vector2i(15, -2)][col]
			_lset(buf, n, spark.x, spark.y, HILITE)
			_lset(buf, n, spark.x, spark.y + 1, HILITE)


# --- structure silhouettes -------------------------------------------------------
# One resting pose each, no animation (BACKLOG M6-D scope note) — the existing
# HP-drain core/bar/flash/rubble states (game/map_view.gd) layer on top of
# these unchanged.

## A tiered plinth + spire, viewed from above: two octagon tiers (dim outer
## base, brighter inner tier) plus a bright circular spire-top and four small
## corner merlons for a "built", not-just-a-square read.
func _draw_tower(buf: Array, n: int) -> void:
	var c := float(n) * 0.5
	_lpolygon(buf, n, _ngon(c, c, float(n) * 0.46, 8), SHADE)
	_lpolygon(buf, n, _ngon(c, c, float(n) * 0.34, 8), FILL)
	_lcircle(buf, n, int(c), int(c), int(float(n) * 0.14), HILITE)
	var mr := float(n) * 0.40
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var mx := int(c + cos(a) * mr)
		var my := int(c + sin(a) * mr)
		_lrect(buf, n, mx - 1, my - 1, 3, 3, SHADE)


## A faceted crystal: an outer octagram (broad facets) with a brighter inner
## octagram (the core) — the "built ground, not a flat diamond" the gauntlet
## finding asked for, at the same silhouette game/map_view.gd already drains.
func _draw_nexus(buf: Array, n: int) -> void:
	var c := float(n) * 0.5
	_lpolygon(buf, n, _star(c, c, float(n) * 0.44, float(n) * 0.30, 8), SHADE)
	_lpolygon(buf, n, _star(c, c, float(n) * 0.30, float(n) * 0.18, 8), FILL)
	_lpolygon(buf, n, _star(c, c, float(n) * 0.16, float(n) * 0.08, 4), HILITE)
