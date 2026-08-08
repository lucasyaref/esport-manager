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

# --- palette (gauntlet iteration 4 — first pass against the reference) --------
## The reference's dominant impression is a *green* jungle cut by *grey stone*
## paths, lit by warm torches. The pre-reference baseline was the opposite: navy
## rock over khaki roads, green nowhere. These values pull the three big fields
## (rock, floor, lane) onto the reference's hues and, more importantly, onto its
## contrast ordering — lane lightest, floor mid, rock dark, void darkest.
const PALETTE := {
	Terrain.WALL:       Color("16261a"),
	Terrain.OPEN:       Color("3c4f30"),
	Terrain.BRUSH:      Color("2a3a22"),
	Terrain.RIVER:      Color("2c5a72"),
	Terrain.PIT:        Color("5d6058"),
	Terrain.LANE:       Color("5f6862"),
	Terrain.CAMP:       Color("445a35"),
	# Paved stone first, team second. The baseline read as two flat swatches
	# because the tint *was* the surface; here it only leans the grey.
	Terrain.BASE_BLUE:  Color("46545f"),
	Terrain.BASE_RED:   Color("5e4a4d"),
}
## Top face of a rock, where it meets open ground — the single cue that reads as
## height in a top-down pixel map. In the reference this face is bare grey stone
## breaking out of the canopy, so it is much lighter than the rock body.
const C_WALL_LIT := Color("46514a")
## The arena's own wall: quarried stone, not canopy. It needs to be lighter than
## the rock inside the arena and darker than the road, or the boundary reads as
## either more jungle or a second lane — both of which the panels reported when
## the rampart shared the rock colour.
const C_RAMPART := Color("3a4038")
const C_WALL_SHADE := Color("0d150f")
## Cast onto the ground south of a rock. Alpha, not a colour: it has to work
## over grass, over lane stone and over water without being retuned for each.
const C_ROCK_SHADOW := Color(0.0, 0.0, 0.0, 0.33)
## The kerb where paving meets dirt. Darker than the road, so the road's shape is
## carried by its banks rather than by a per-tile pattern.
const C_LANE_EDGE := Color("3c433e")
## The carved stone lip of a pit — the lightest thing on the map, on purpose.
const C_PIT_RIM := Color("7e867c")
## The masonry ring around a base precinct — stone, deliberately not team-tinted,
## so the wall reads as built and the tint stays a property of the floor.
const C_BASE_WALL := Color("6b736c")
## Water shallow enough to walk: laid over the *lane* where mid crosses the
## river, so the channel reads as continuing under the road instead of being
## erased by it. Alpha, not a flat colour — the paving has to stay visible.
const C_FORD := Color(0.29, 0.60, 0.72, 0.42)
## How far a ford looks for water. The mid lane is ~5 cells wide where it cuts
## the river, so anything less than that finds nothing.
const FORD_REACH := 5
const C_RIVER_SHIMMER := Color("5b96ad")
## Warm amber: the reference marks every camp and path junction with torch fire,
## and it is the only warm hue on an otherwise entirely cool-green map.
const C_CAMP_MARK := Color("b3762f")
## Brush is dense canopy seen from above — darker than the floor it sits on, not
## the bright grass the baseline drew.
const C_BRUSH_TUFT := Color("182712")
const C_OUTLINE := Color("0a0f12")
## Everything outside the arena wall. The reference drops it to near-black and
## lets the rampart's lit edge do the work of drawing the boundary.
const C_VOID := Color("080c0a")

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
			var col: Color = _base_color(kind)
			var jitter := true
			# Three values where there used to be one: rock inside the arena stays
			# green so it reads as terrain to walk around, the arena's wall is
			# quarried stone, and beyond it the map has ended. The void takes no
			# tonal jitter — speckled black reads as texture, and there is nothing
			# out there to have texture.
			if kind == Terrain.WALL:
				match t.wall_class(c, r):
					Terrain.RAMPART:
						col = C_RAMPART
					Terrain.VOID:
						col = C_VOID
						jitter = false
			ci.draw_rect(rect, _tone(col, c, r) if jitter else col)

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
				Terrain.PIT:
					_draw_pit_rim(ci, t, c, r, pos, cell_px)
				Terrain.LANE:
					_draw_lane_edges(ci, t, c, r, pos, cell_px)
					if _is_ford(t, c, r):
						ci.draw_rect(Rect2(pos, Vector2(cell_px, cell_px)), C_FORD)
				Terrain.CAMP:
					ci.draw_circle(pos + Vector2(cell_px, cell_px) * 0.5,
						cell_px * 0.22, C_CAMP_MARK)
				Terrain.BRUSH:
					_draw_brush_tufts(ci, c, r, pos, cell_px)
				Terrain.BASE_BLUE, Terrain.BASE_RED:
					_draw_base_wall(ci, t, c, r, pos, cell_px)

	var side: float = t.n * cell_px
	ci.draw_rect(Rect2(origin, Vector2(side, side)), C_OUTLINE, false, 2.0)


static func _base_color(kind: int) -> Color:
	return PALETTE.get(kind, Color.MAGENTA)


## Height, with the light coming from the north.
##
## The baseline drew both bands *inside* the rock cell, which is why the map read
## as flat: a shape that only shades itself is still a sticker. What actually
## sells elevation is the rock darkening its neighbour — so the cap stays on the
## rock's north edge, and the shadow is cast forward onto the open ground to the
## south. The detail pass runs after every fill, so drawing into the neighbour's
## square here is safe.
static func _draw_rock_face(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	if t.kind_at_cell(c, r - 1) != Terrain.WALL:
		ci.draw_rect(Rect2(pos, Vector2(cell_px, maxf(1.0, cell_px * 0.26))), C_WALL_LIT)
	if t.kind_at_cell(c, r + 1) != Terrain.WALL:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px),
			Vector2(cell_px, maxf(1.0, cell_px * 0.34))), C_ROCK_SHADOW)
	# A contact line on the east and west faces. Without it the green rock and the
	# green grass dissolve into each other and half the map's walkability goes
	# unreadable — which is exactly what the cold reader reported.
	var e: float = maxf(1.0, cell_px * 0.16)
	if t.kind_at_cell(c - 1, r) != Terrain.WALL:
		ci.draw_rect(Rect2(pos, Vector2(e, cell_px)), C_WALL_SHADE)
	if t.kind_at_cell(c + 1, r) != Terrain.WALL:
		ci.draw_rect(Rect2(pos + Vector2(cell_px - e, 0.0), Vector2(e, cell_px)), C_WALL_SHADE)


static func _draw_shimmer(ci: CanvasItem, c: int, r: int, pos: Vector2, cell_px: float) -> void:
	if (_hash(c, r) % 7) != 0:
		return
	ci.draw_rect(Rect2(pos + Vector2(cell_px * 0.2, cell_px * 0.45),
		Vector2(cell_px * 0.55, maxf(1.0, cell_px * 0.10))), C_RIVER_SHIMMER)


## A road is defined by its *banks*, not by its tiles. The baseline drew an inset
## square in every lane cell, which at overview scale reads as a chequerboard of
## paving slabs — the one thing the reference's paths never do. So: leave the
## surface flat, and darken only the sides that face off-road. A straight run of
## lane then has two continuous rails and an unbroken middle, and a junction
## opens out on its own.
static func _draw_lane_edges(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	var w: float = maxf(1.0, cell_px * 0.22)
	# north, south, west, east
	if not _is_road(t, c, r - 1):
		ci.draw_rect(Rect2(pos, Vector2(cell_px, w)), C_LANE_EDGE)
	if not _is_road(t, c, r + 1):
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - w), Vector2(cell_px, w)), C_LANE_EDGE)
	if not _is_road(t, c - 1, r):
		ci.draw_rect(Rect2(pos, Vector2(w, cell_px)), C_LANE_EDGE)
	if not _is_road(t, c + 1, r):
		ci.draw_rect(Rect2(pos + Vector2(cell_px - w, 0.0), Vector2(w, cell_px)), C_LANE_EDGE)


## The two pits are where the match's biggest fights happen, so they have to be
## findable at a glance. Same trick as the lane banks, inverted: a *bright* stone
## rim wherever the pit meets anything else, which closes the bowl into a ring
## and stops it reading as one more grey blob among the rocks.
static func _draw_pit_rim(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	_draw_rim(ci, t, c, r, pos, cell_px, [Terrain.PIT], C_PIT_RIM, 0.3)


## A base is a walled precinct in the reference, not a coloured rectangle: a
## paved floor with a masonry wall around it, open only where its lane runs out.
## Counting LANE as part of the enclosure is what leaves those gates open — the
## rim is drawn against jungle and rock, and stops at the lane mouths.
static func _draw_base_wall(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	_draw_rim(ci, t, c, r, pos, cell_px,
		[Terrain.BASE_BLUE, Terrain.BASE_RED, Terrain.LANE], C_BASE_WALL, 0.26)


## Bands on whichever sides of a cell face *out* of `inside`. One helper because
## a pit lip and a base wall are the same drawing problem seen from two sides.
static func _draw_rim(ci: CanvasItem, t: Terrain, c: int, r: int, pos: Vector2,
		cell_px: float, inside: Array, col: Color, width_frac: float) -> void:
	var w: float = maxf(1.0, cell_px * width_frac)
	if not inside.has(t.kind_at_cell(c, r - 1)):
		ci.draw_rect(Rect2(pos, Vector2(cell_px, w)), col)
	if not inside.has(t.kind_at_cell(c, r + 1)):
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - w), Vector2(cell_px, w)), col)
	if not inside.has(t.kind_at_cell(c - 1, r)):
		ci.draw_rect(Rect2(pos, Vector2(w, cell_px)), col)
	if not inside.has(t.kind_at_cell(c + 1, r)):
		ci.draw_rect(Rect2(pos + Vector2(cell_px - w, 0.0), Vector2(w, cell_px)), col)


## A lane cell is a ford if the river lies on *both* sides of it. Scanning
## outward rather than testing neighbours is what makes this work at all: the
## road is several cells wide at the crossing, so no single lane cell ever
## touches water on two sides. A wall found first stops the scan, which keeps a
## lane merely running alongside the river from flooding along its whole length.
##
## The diagonals are not optional. Mid and the river cross at 90° to each other
## but at 45° to the grid, and the channel enters at (22,24) and leaves at
## (27,25) — one row apart — so an axis-aligned test finds water on both sides of
## precisely nothing. With the diagonals it selects 16 cells, all of them at the
## centre crossing, and the selection is stable for any reach from 4 to 6.
const FORD_AXES: Array = [
	[Vector2i(1, 0), Vector2i(-1, 0)],
	[Vector2i(0, 1), Vector2i(0, -1)],
	[Vector2i(1, 1), Vector2i(-1, -1)],
	[Vector2i(1, -1), Vector2i(-1, 1)],
]

static func _is_ford(t: Terrain, c: int, r: int) -> bool:
	for axis in FORD_AXES:
		var a: Vector2i = axis[0]
		var b: Vector2i = axis[1]
		if _sees_river(t, c, r, a.x, a.y) and _sees_river(t, c, r, b.x, b.y):
			return true
	return false


static func _sees_river(t: Terrain, c: int, r: int, dx: int, dy: int) -> bool:
	for i in range(1, FORD_REACH + 1):
		var k: int = t.kind_at_cell(c + dx * i, r + dy * i)
		if k == Terrain.RIVER:
			return true
		if k == Terrain.WALL:
			return false
	return false


## Bases are paved too, so a lane meeting a base must not draw a bank across the
## mouth of it — that would fence each base off behind a dark line.
static func _is_road(t: Terrain, c: int, r: int) -> bool:
	var k: int = t.kind_at_cell(c, r)
	return k == Terrain.LANE or k == Terrain.BASE_BLUE or k == Terrain.BASE_RED


static func _draw_brush_tufts(ci: CanvasItem, c: int, r: int, pos: Vector2, cell_px: float) -> void:
	var h := _hash(c, r)
	for i in 3:
		var fx: float = float((h >> (i * 5)) % 100) / 100.0
		var fy: float = float((h >> (i * 5 + 3)) % 100) / 100.0
		ci.draw_rect(Rect2(pos + Vector2(fx, fy) * cell_px * 0.7,
			Vector2(maxf(1.0, cell_px * 0.16), maxf(1.0, cell_px * 0.3))), C_BRUSH_TUFT)


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
