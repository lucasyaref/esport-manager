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
	# Lighter than the floor it sits on, not darker. Run 1 drew brush as dark
	# canopy, which put it in the same value band as rock — so at overview scale
	# the map had two different dark-green blob families meaning "walk through
	# this" and "walk around this", and every cold reader has conflated them.
	# §6.3 rule 1 settles it: a thing the viewer must find is lighter than its
	# surroundings. Brush is now the second-lightest surface after the road.
	Terrain.BRUSH:      Color("4e6338"),
	Terrain.RIVER:      Color("2c5a72"),
	# Dropped a step at iteration 30. A pale flat disc is how a boulder field is
	# drawn, and that is what both cold readers called these — *"I would plausibly
	# have called them terrain obstacles, not fight sites"*. The floor keeps enough
	# value to stay lighter than the jungle around it (rule 1) and gives up the rest
	# to the tiers cut into it, which are what say bowl.
	Terrain.PIT:        Color("51554e"),
	# GDD §6.3 rule 6: the road is the *only* warm hue on the map, and the
	# highest-value surface on it. Run 1 left it a cold green-grey, which is why
	# three consecutive panels reported the road and the arena wall as "identical
	# material, contradictory functions" — the fault was never the geometry that
	# separates them, it was that they were the same colour.
	Terrain.LANE:       Color("7a6e58"),
	# A clearing trodden into the jungle floor, not a landmark on it. §6.3 rule 7
	# spends the ornament budget on the bases, the pits and the river; the jungle
	# is texture. So a camp is ground, marked — the same *kind* of thing as the
	# floor around it, which is also what keeps the shape vocabulary at five.
	Terrain.CAMP:       Color("42482e"),
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
##
## Strengthened at iteration 20. The cue was not missing — a crop of the render
## upscaled 4x showed the cap, the contact lines and the shadow all drawn exactly
## as intended — it was 7 px of 33% black over an already dark floor, which is a
## cue that exists at zoom and is gone at the scale the map is actually watched.
## Both cold readers reported no height information on a render that had it.
const C_ROCK_SHADOW := Color(0.0, 0.0, 0.0, 0.52)
## How far the shadow reaches into the cell south of the rock.
const ROCK_SHADOW_DEPTH := 0.42
## The kerb where paving meets dirt. Darker than the road, so the road's shape is
## carried by its banks rather than by a per-tile pattern. Warm, like the road —
## a cold kerb reads as a grey line drawn *on* the sand rather than its edge.
const C_LANE_EDGE := Color("463c2d")
## The carved stone lip of a pit. Cold stone, and deliberately a shade *under* the
## road: rule 1 says nothing competes with the lanes for brightness, and run 1 had
## this as the brightest thing on the map. It stays findable by being the lightest
## thing in its own neighbourhood, which is all a rim has ever needed to be.
const C_PIT_RIM := Color("6b726a")
## Cast onto the ground *around* a pit, so the bowl sits into the map instead of
## floating on it. Alpha for the same reason the rock shadow is: a pit borders
## jungle floor, rock and water, and one band has to work over all three.
const C_PIT_SHADOW := Color(0.0, 0.0, 0.0, 0.40)
## The second tier, cut one step below the first. A bowl is a thing with an inside;
## one flat disc with a lip around it is a thing with an edge, and an edge is what a
## boulder has.
const C_PIT_BASIN := Color(0.0, 0.0, 0.0, 0.22)
## The dais at the pit's eye — the one cell the objective stands on, and the
## lightest thing inside the bowl. Kept a shade under the road: rule 1 gives peak
## brightness to the lanes, and this earns its read by being one bright cell in a
## dark hollow rather than by out-shouting anything.
const C_PIT_EYE := Color("7f8479")
## The masonry ring around a base precinct — stone, deliberately not team-tinted,
## so the wall reads as built and the tint stays a property of the floor.
const C_BASE_WALL := Color("6b736c")
## Shallow water with the road's paving showing through it, laid over the *river*
## where mid crosses. The road stops at one bank and starts at the other, which is
## true of the ground and useless to a viewer: two cold readers looking at the same
## render could not tell whether the water could be crossed, and one of them could
## not tell whether mid was one lane or two. This is the road's own hue at low
## alpha, so the crossing reads as the lane continuing into the shallows rather
## than as a second kind of water — §6.3 rule 3 keeps the vocabulary at five, and a
## ford has to be a lane and a river doing something, never a sixth thing.
const C_FORD := Color(0.478, 0.431, 0.345, 0.45)
## How far a ford looks for paving. The mid lane is ~5 cells wide where it cuts the
## river, so anything less than that finds nothing.
const FORD_REACH := 5
const C_RIVER_SHIMMER := Color("5b96ad")
## Scuffed earth where the camp is fought over. Run 1 took the painted reference
## at its word and put torch fire on all eight camps, which made the jungle the
## most decorated part of the map and gave the map two warm accents competing at
## overview scale. Rule 6 gives the warm hue to the road alone, so this drops to a
## near-neutral olive-brown that reads as bare ground at zoom and disappears into
## texture at overview — which is what a camp should do to the eye.
const C_CAMP_MARK := Color("4c4a35")
## Foliage stipple *within* the brush patch — §6.3 rule 4's "noise lives inside a
## mass, never defining its shape". Only a shade off the patch itself: the patch
## is read by its value, and the tufts only say what kind of surface it is.
const C_BRUSH_TUFT := Color("3c5029")
const C_OUTLINE := Color("0a0f12")
## Everything outside the arena wall. Near-black, but not black: the reference's
## surround is a very dark desaturated teal, and pure #000 makes the map look like
## a cutout pasted on the page rather than a place with night around it. Palette
## is the one thing that reference is authoritative for, so it wins here.
const C_VOID := Color("0a1113")

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
					# Paving first, shimmer over it: the dashes are the water's
					# own cue and have to survive the crossing, or the ford reads
					# as a gap in the river instead of a gap in the road.
					if _is_ford(t, c, r):
						ci.draw_rect(Rect2(pos, Vector2(cell_px, cell_px)), C_FORD)
					_draw_shimmer(ci, c, r, pos, cell_px)
				Terrain.PIT:
					_draw_pit_rim(ci, t, c, r, pos, cell_px)
				Terrain.LANE:
					_draw_lane_edges(ci, t, c, r, pos, cell_px)
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
			Vector2(cell_px, maxf(1.0, cell_px * ROCK_SHADOW_DEPTH))), C_ROCK_SHADOW)
	# A dark contact line on every face that meets open ground — §6.3 rule 5's
	# "dark outline", which the mass previously only had east and west. An outline
	# that stops on two sides is not an outline: it reads as two stripes, and it
	# left the south face relying on a cast shadow alone to say the mass was there.
	var e: float = maxf(1.0, cell_px * 0.16)
	if t.kind_at_cell(c - 1, r) != Terrain.WALL:
		ci.draw_rect(Rect2(pos, Vector2(e, cell_px)), C_WALL_SHADE)
	if t.kind_at_cell(c + 1, r) != Terrain.WALL:
		ci.draw_rect(Rect2(pos + Vector2(cell_px - e, 0.0), Vector2(e, cell_px)), C_WALL_SHADE)
	if t.kind_at_cell(c, r + 1) != Terrain.WALL:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - e), Vector2(cell_px, e)), C_WALL_SHADE)


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
## findable at a glance — §6.3 rule 7 spends part of the ornament budget here.
##
## Two bands, not one, and the outer one is the point. A light lip alone made the
## pit a bright flat disc that both cold readers called a clearing or a hole; what
## says "bowl" is the same thing that says "raised rock" everywhere else on this
## map — a dark contact line on the ground outside it (rule 5). So: the lip stays
## inside the pit, and a shadow band is cast onto whatever the pit borders.
##
## The lip is also no longer the brightest thing on the map. Rule 1 gives that to
## the road, and a rim only ever needed to be the lightest thing in its *own*
## neighbourhood, which against dark jungle it comfortably is.
##
## What the lip alone still could not do is say *fight site* rather than *rock*. A
## flat disc with a hard edge is how this renderer draws a boulder field, and both
## cold readers at panel 6 read them that way — one of them was explicit that it
## would have called them obstacles. So the bowl is cut in tiers, and the tiers come
## out of the grid rather than out of `map.json`: measure how deep inside the pit a
## cell sits and the shape names its own centre. There is exactly one deepest cell
## in each pit, and it is the cell the objective stands on.
static func _draw_pit_rim(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	var depth := _pit_depth(t, c, r)
	if depth >= 2:
		ci.draw_rect(Rect2(pos, Vector2(cell_px, cell_px)), C_PIT_BASIN)
		# The step's own lip, so the two tiers read as cut stone rather than as a
		# stain on one floor. Same material as the outer lip — a pit is one thing.
		for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if _pit_depth(t, c + dir.x, r + dir.y) >= 2:
				continue
			var w: float = maxf(1.0, cell_px * 0.2)
			var lip := Rect2(pos, Vector2(cell_px, w)) if dir.y != 0 \
				else Rect2(pos, Vector2(w, cell_px))
			if dir.y > 0:
				lip.position.y += cell_px - w
			elif dir.x > 0:
				lip.position.x += cell_px - w
			ci.draw_rect(lip, C_PIT_RIM)
	if depth >= 3:
		ci.draw_circle(pos + Vector2(cell_px, cell_px) * 0.5, cell_px * 0.42, C_PIT_EYE)
	var d: float = maxf(1.0, cell_px * 0.22)
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if t.kind_at_cell(c + dir.x, r + dir.y) == Terrain.PIT:
			continue
		var band := Rect2(pos, Vector2(cell_px, d)) if dir.y != 0 \
			else Rect2(pos, Vector2(d, cell_px))
		if dir.y > 0:
			band.position.y += cell_px
		elif dir.y < 0:
			band.position.y -= d
		elif dir.x > 0:
			band.position.x += cell_px
		else:
			band.position.x -= d
		ci.draw_rect(band, C_PIT_SHADOW)
	_draw_rim(ci, t, c, r, pos, cell_px, [Terrain.PIT], C_PIT_RIM, 0.3)


## How far inside a pit a cell sits: 0 for anything that is not pit, 1 on the lip,
## rising toward the middle. Measured in all eight directions so the tiers come out
## as octagons rather than as crosses, and capped because nothing here needs to know
## the difference between deep and deeper.
##
## This is the whole reason the pit can be drawn without `data/map.json`. The
## renderer is handed a grid and nothing else, and on this map the measure has
## exactly one maximum in each bowl — cells (15,22) and (34,27), which is where the
## dragon and baron anchors are. The shape names its own centre, so nothing has to
## be kept in step with the data file.
const PIT_DEPTH_MAX := 3

static func _pit_depth(t: Terrain, c: int, r: int) -> int:
	if t.kind_at_cell(c, r) != Terrain.PIT:
		return 0
	var depth := PIT_DEPTH_MAX
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		for i in range(1, PIT_DEPTH_MAX + 1):
			if t.kind_at_cell(c + dir.x * i, r + dir.y * i) != Terrain.PIT:
				depth = mini(depth, i)
				break
	return depth


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


## A *river* cell is a ford if the road lies on both sides of it — the water the
## road runs through, rather than the road the water runs under.
##
## The test used to run the other way round, on lane cells with water either side,
## because the crossing cells used to be lane. They are river now: a ford is water
## interrupting a road, so the paint tool stopped letting a lane band overwrite the
## channel, and the river became one body instead of two. The consequence nobody
## looked for is that this cue went **inert** — it was still asking lane cells a
## question no lane cell could answer any more — and the next cold panel reported
## exactly what that leaves behind: *"whether the river can be crossed, I cannot
## tell"*, from both critics independently. A silent cue is worse than a missing
## one, because the code that draws it is still there to read.
##
## Scanning outward rather than testing neighbours is what makes this work at all:
## the road is several cells wide at the crossing, so no single cell in the channel
## ever touches paving on two sides. A wall found first stops the scan, which keeps
## water merely running alongside a road from reading as fordable down its length.
##
## The water has to continue on both sides as well, and that second test is not
## bookkeeping. Paving on two sides alone lit up both *ends* of the river, where the
## channel runs out into the corner of the ring road and is therefore surrounded by
## it — three pale patches on the map, only one of them a crossing. A ford is a road
## crossing a channel, so there has to be a channel: water ahead and water behind.
##
## The diagonals are not optional. Mid and the river cross at 90° to each other but
## at 45° to the grid, so an axis-aligned test finds paving on both sides of
## precisely nothing. Each entry is [direction the road runs, direction the water
## runs], and the two are always perpendicular.
const FORD_AXES: Array = [
	[Vector2i(1, 0), Vector2i(0, 1)],
	[Vector2i(0, 1), Vector2i(1, 0)],
	[Vector2i(1, 1), Vector2i(1, -1)],
	[Vector2i(1, -1), Vector2i(1, 1)],
]

static func _is_ford(t: Terrain, c: int, r: int) -> bool:
	for axis in FORD_AXES:
		var road: Vector2i = axis[0]
		var flow: Vector2i = axis[1]
		if _sees(t, c, r, road, Terrain.LANE) and _sees(t, c, r, -road, Terrain.LANE) \
				and _sees(t, c, r, flow, Terrain.RIVER) \
				and _sees(t, c, r, -flow, Terrain.RIVER):
			return true
	return false


static func _sees(t: Terrain, c: int, r: int, dir: Vector2i, kind: int) -> bool:
	for i in range(1, FORD_REACH + 1):
		var k: int = t.kind_at_cell(c + dir.x * i, r + dir.y * i)
		if k == kind:
			return true
		if k == Terrain.WALL:
			return false
	return false


## Bases are paved too, so a lane meeting a base must not draw a bank across the
## mouth of it — that would fence each base off behind a dark line.
## A ford counts as road here, and it has to. The kerb is drawn on every lane face
## that does not meet more road, so without this the paving draws itself a bank
## along the water and the road reads as stopping dead at the crossing — which is
## the opposite of what the ford is for.
static func _is_road(t: Terrain, c: int, r: int) -> bool:
	var k: int = t.kind_at_cell(c, r)
	if k == Terrain.RIVER:
		return _is_ford(t, c, r)
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
