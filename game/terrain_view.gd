class_name TerrainView
extends RefCounted
## Draws a Terrain onto any CanvasItem.
##
## Deliberately not a Node: both the match viewer (game/map_view.gd) and the
## still-frame capture rig (tools/shoot_map.gd) call the same function, so the
## gauntlet loop judges exactly the pixels the game will show. If these ever
## diverge, the loop is grading the wrong image.
##
## Everything visual lives in the PALETTE / knobs block below. That block is what
## the gauntlet loop edits between iterations; the drawing code underneath should
## need to change only when the reference asks for a genuinely new *feature*
## (a new kind of edge, a new texture), not a new colour.

# --- palette (gauntlet iteration 0 — pre-reference baseline) -------------------
const PALETTE := {
	Terrain.WALL:       Color("1b2430"),
	Terrain.OPEN:       Color("2f4a34"),
	Terrain.BRUSH:      Color("1f3a26"),
	Terrain.RIVER:      Color("21455f"),
	Terrain.PIT:        Color("2a3446"),
	Terrain.LANE:       Color("6b6144"),
	Terrain.CAMP:       Color("3d4f31"),
	Terrain.BASE_BLUE:  Color("24384f"),
	Terrain.BASE_RED:   Color("4d2b30"),
}
## Top face of a rock, where it meets open ground — the single cue that reads as
## height in a top-down pixel map.
const C_WALL_LIT := Color("38465a")
const C_WALL_SHADE := Color("11171f")
const C_LANE_CORE := Color("857a56")
const C_RIVER_SHIMMER := Color("3d6d8f")
const C_CAMP_MARK := Color("6b7f4a")
const C_BRUSH_TUFT := Color("2c5333")
const C_OUTLINE := Color("0d1219")

## Per-cell tonal variation, so large fields of grass are not flat. Deterministic
## by construction (hashed from the cell index, never from an RNG) — the whole
## project's determinism rule applies to the picture too, or two runs of the
## capture rig would produce two different images and the loop could not compare.
const NOISE_AMOUNT := 0.035


## Draws the whole terrain. `origin` is the screen position of the map's
## top-left corner; `px_per_world` scales world units to pixels.
static func draw(ci: CanvasItem, t: Terrain, origin: Vector2, px_per_world: float) -> void:
	if t == null or t.n == 0:
		return
	var cell_px: float = t.cell_size * px_per_world
	# Half a pixel of overdraw: adjacent cell fills must not leave hairline seams.
	var bleed := 0.5

	for r in t.n:
		for c in t.n:
			var kind: int = t.kind_at_cell(c, r)
			var pos := origin + Vector2(c, r) * cell_px
			var rect := Rect2(pos - Vector2(bleed, bleed),
				Vector2(cell_px + bleed * 2.0, cell_px + bleed * 2.0))
			ci.draw_rect(rect, _tone(_base_color(kind), c, r))

	# Second pass for anything that reads as *on top of* the floor. Kept separate
	# so a cell's detail is never painted over by its neighbour's fill.
	for r in t.n:
		for c in t.n:
			var kind: int = t.kind_at_cell(c, r)
			var pos := origin + Vector2(c, r) * cell_px
			match kind:
				Terrain.WALL:
					_draw_rock_face(ci, t, c, r, pos, cell_px)
				Terrain.RIVER:
					_draw_shimmer(ci, c, r, pos, cell_px)
				Terrain.LANE:
					_draw_lane_core(ci, pos, cell_px)
				Terrain.CAMP:
					ci.draw_circle(pos + Vector2(cell_px, cell_px) * 0.5,
						cell_px * 0.22, C_CAMP_MARK)
				Terrain.BRUSH:
					_draw_brush_tufts(ci, c, r, pos, cell_px)

	var side: float = t.n * cell_px
	ci.draw_rect(Rect2(origin, Vector2(side, side)), C_OUTLINE, false, 2.0)


static func _base_color(kind: int) -> Color:
	return PALETTE.get(kind, Color.MAGENTA)


## A rock is lit on the edge that faces open ground above it and shadowed below.
## Two 1-cell bands are enough to read as height at overview scale; the reference
## will say whether it wants a taller face.
static func _draw_rock_face(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	if t.kind_at_cell(c, r - 1) != Terrain.WALL:
		ci.draw_rect(Rect2(pos, Vector2(cell_px, cell_px * 0.28)), C_WALL_LIT)
	if t.kind_at_cell(c, r + 1) != Terrain.WALL:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px * 0.78),
			Vector2(cell_px, cell_px * 0.22)), C_WALL_SHADE)


static func _draw_shimmer(ci: CanvasItem, c: int, r: int, pos: Vector2, cell_px: float) -> void:
	if (_hash(c, r) % 7) != 0:
		return
	ci.draw_rect(Rect2(pos + Vector2(cell_px * 0.2, cell_px * 0.45),
		Vector2(cell_px * 0.55, maxf(1.0, cell_px * 0.10))), C_RIVER_SHIMMER)


## The travelled centre of the road, drawn only where the lane continues, so a
## lane reads as a road rather than as a chain of tiles.
static func _draw_lane_core(ci: CanvasItem, pos: Vector2, cell_px: float) -> void:
	var inset := cell_px * 0.25
	ci.draw_rect(Rect2(pos + Vector2(inset, inset),
		Vector2(cell_px - inset * 2.0, cell_px - inset * 2.0)), C_LANE_CORE)


static func _draw_brush_tufts(ci: CanvasItem, c: int, r: int, pos: Vector2, cell_px: float) -> void:
	var h := _hash(c, r)
	for i in 3:
		var fx: float = float((h >> (i * 5)) % 100) / 100.0
		var fy: float = float((h >> (i * 5 + 3)) % 100) / 100.0
		ci.draw_rect(Rect2(pos + Vector2(fx, fy) * cell_px * 0.7,
			Vector2(maxf(1.0, cell_px * 0.16), maxf(1.0, cell_px * 0.3))), C_CAMP_MARK)


## Deterministic per-cell tone jitter.
static func _tone(col: Color, c: int, r: int) -> Color:
	var f: float = (float(_hash(c, r) % 1000) / 1000.0 - 0.5) * 2.0 * NOISE_AMOUNT
	return Color(clampf(col.r + f, 0.0, 1.0), clampf(col.g + f, 0.0, 1.0),
		clampf(col.b + f, 0.0, 1.0), col.a)


## Integer hash — same cell, same value, every run, on every machine.
static func _hash(c: int, r: int) -> int:
	var h: int = c * 73856093 ^ r * 19349663
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
