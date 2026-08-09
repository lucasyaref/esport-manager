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
	# Stone, not canopy — changed at iteration 32, and it is the answer to the
	# oldest finding in this loop. Every panel since the first has said a cold reader
	# cannot tell which greens block, and iterations 20 and 31 both attacked it as a
	# contrast problem. Panel 7 finally said what the problem actually is: *"mid-green
	# grass and dark-green blobs occupy comparable areas and are both green, so the
	# map's largest surface is ambiguous terrain"*. The reader could always see the
	# two greens. It could not know which one meant "walk here", and no amount of
	# separation between two members of the same family answers that question.
	#
	# So the family changes. Green is ground you can stand on — floor and brush — and
	# blocking mass is stone. §6.3 rule 3 names ground and stone mass as two of its
	# five shapes and this renderer had been drawing them as one; the grid only has
	# one kind of wall, so the distinction has to be carried by material.
	#
	# Raised again at iteration 34, and this is what "monotone and legible" costs when
	# it is checked against a number instead of an eye. Stone at 0.184 measures three
	# times the void's 0.061 and reads as the same black: panel 8 called the masses
	# "black holes ... like cut-out voids", and the second critic, cold and separately,
	# said masses touching the edge "look like the frame intruding rather than in-play
	# terrain". A ratio is not a contrast. Now 0.223 — one step under the floor it
	# stands in, which is where the reference puts it, and the height is carried by the
	# lit cap and the cast shadow rather than by being dark.
	# Canopy, not stone — GDD §6.3 rule 6′, designer decision 2026-08-09. This
	# reverses iteration 32, which made blockers grey precisely so that blocking
	# terrain would stop being green, and which closed the oldest finding in the
	# gauntlet log. Going back to green re-opens it knowingly, so the separation
	# that hue used to provide has to be bought elsewhere:
	#
	#   canopy body   0.18   <- this
	#   floor         0.285
	#
	# A 0.10 step, where grey-on-green never needed one because the hue did the
	# work. Plus the two cues rule 5 names, both of which measured strong at panel
	# 10 and neither of which is touched here: a lit cap on the north edge and a
	# cast shadow on the ground south, a 51% drop.
	Terrain.WALL:       Color("24331f"),
	# Grass, and green again — the designer took gauntlet question A on 2026-08-09
	# and the layout moved underneath this decision.
	#
	# Iteration 43 made this earth for a good reason that has since expired. Two cold
	# panels had filed *"which green is walkable"* as **invisible**, and the cause was
	# neither tone nor texture: green meant "blocked" 48% of the map and "walk here"
	# 10% of it, so the floor was the exception rather than the rule and no amount of
	# separation between two greens could fix which one a viewer assumed. Earth
	# sidestepped it by leaving the green family altogether.
	#
	# The layout pass removes the reason. Canopy 48% -> 40%, road 24% -> 20%, walkable
	# green 10% -> 22%: green ground now outweighs the roads, and the field can carry
	# the meaning the reference gives it. Whether that is *enough* is a cold reader's
	# call and not mine — this is the third attempt at one question and the two before
	# it were both wrong.
	#
	# Kept under the brush it borders, 0.317 against 0.358. Brush is the one light
	# green and has had its own silhouette since iteration 39; the floor must not
	# climb into it.
	Terrain.OPEN:       Color("415838"),
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
	# GDD §6.3 rule 6, as reversed on hue by the designer on 2026-08-09: paved
	# stone, cool, and still the highest-value surface on the map. The warm sand
	# stood for six panels against a fidelity critic that asked for grey every
	# time; the third reference made the lanes cool stone through a green field and
	# the designer took it.
	#
	# What the warmth was doing is now done by value alone, and that is why this is
	# 0.51 rather than the 0.44 the tan sat at. Hue was separating the road from the
	# pit rims (0.43) and the base walls (0.43); with every one of them grey, a road
	# at 0.44 would be three built surfaces at one value, which is panel 2's
	# "identical material, contradictory functions" arriving by a different route.
	# Rule 1 gives the top of the scale to the lanes, so the road takes the room it
	# needs and the rims keep theirs.
	Terrain.LANE:       Color("7e8385"),
	# A clearing trodden into the jungle floor, not a landmark on it. §6.3 rule 7
	# spends the ornament budget on the bases, the pits and the river; the jungle
	# is texture. So a camp is ground, marked — the same *kind* of thing as the
	# floor around it, which is also what keeps the shape vocabulary at five.
	#
	# Iteration 17 took that to mean *no separation at all*, and the measurement at
	# panel 9 was camp 0.286 against floor 0.283 — the same surface. A cold reader
	# said so: "any camp, neutral spawn or point of interest inside the green areas,
	# I found none at all", and four of the seven patches it did point at as possible
	# brush were camps. Rule 7 withholds *ornament* from the jungle. It does not ask a
	# feature to be invisible, and rule 1 says a thing the viewer must find is lighter
	# or darker than what surrounds it.
	#
	# So a camp gets a value step and no props: ground trodden bare, one step under
	# the grass, going down where brush goes up. Two walkable greens that differ in
	# opposite directions from the floor are much easier to hold apart than two that
	# differ by amount.
	Terrain.CAMP:       Color("3a4029"),
	# Paved stone first, team second. The baseline read as two flat swatches
	# because the tint *was* the surface; here it only leans the grey.
	#
	# Blue leans *indigo*, not teal, and that is the river's fault. At panel 8 a cold
	# reader looking at the map's bottom-right water said it was "close enough in hue
	# to the blue base wash that I briefly read it as a second blue territory", and
	# noted the failure is not symmetric — red is unmistakable, so only one team's
	# ground is ambiguous, which is worse than both being. Team colour has to be
	# readable against every surface it can sit next to, and on this map blue sits
	# next to a river.
	Terrain.BASE_BLUE:  Color("4a4c64"),
	Terrain.BASE_RED:   Color("5e4a4d"),
}
## Top face of a rock, where it meets open ground — the single cue that reads as
## height in a top-down pixel map. In the reference this face is bare grey stone
## breaking out of the canopy, so it is much lighter than the rock body.
##
## Raised at iteration 31, and the number is the reason. Measured off the render,
## this face sat at 0.306 luminance against a jungle floor of 0.283 — a gap of
## 0.023, which is no gap. So the top edge of every rock mass was the same value as
## the ground you can walk on, and the shadow it casts (0.137) was the same value as
## the rock body (0.117): the mass read a cell too small at the top and a cell too
## big at the bottom, and its real boundary was drawn nowhere. That is a better
## account of why three panels could not tell which greens block than "the height
## cue is missing", which is what the panels said and which the same measurement
## refutes — the cast shadow is a 52% drop and always was.
##
## Now 0.38, which clears the floor by a full step and still sits under the road at
## 0.43, so rule 1 keeps its promise that nothing outshines the lanes.
## Now sunlit leaf rather than bare rock (rule 6′), and the value is the whole
## argument. It has to clear the floor it borders — iteration 31 proved a cap level
## with the ground draws the mass a cell too small at the top — while staying under
## the brush it can sit beside, or the map gains a third light green and rule 3's
## vocabulary quietly grows a sixth item.
##
##   floor 0.285  <  cap 0.324  <  brush 0.352  <  brush rim 0.401  <  road 0.510
##
## That is a 0.039 clearance over the floor and 0.028 under the brush, which is
## tighter than any other gap on the map and is the price of the reversal. What
## keeps brush safe at that distance is that brush is read by its *silhouette*
## since iteration 39, not by value alone.
const C_WALL_LIT := Color("435a38")
## The arena's own wall: quarried stone, not canopy. It needs to be lighter than
## the rock inside the arena and darker than the road, or the boundary reads as
## either more jungle or a second lane — both of which the panels reported when
## the rampart shared the rock colour.
const C_RAMPART := Color("3f4640")
const C_WALL_SHADE := Color("101413")
## The two tones a crown is made of. Both sit *below* the walkable floor (0.283),
## which is the point: this texture must make the mass read as trees without ever
## lifting a blocking cell into the floor's value band. Rule 1 is not being spent
## here — the mass keeps its dark, and only gains a surface.
const C_CANOPY_CROWN := Color("31452a")
const C_CANOPY_UNDER := Color("16210f")
## The sixth shape: the stone escarpment a canopy mass stands on, drawn only where
## the mass meets ground you can walk on.
##
## Grey, and that is the entire point — it is the *material* cue, not another value
## step. Four cold panels could not tell two greens apart at three different ratios;
## the two configurations that ever worked both had a hard material boundary. So the
## rim rejoins the built-stone family that the roads, pit rims and base walls belong
## to, and the mass it edges stays canopy.
##
##   grass 0.317  <  stone rim 0.430  <  lit rim 0.489  <  road 0.510
##
## Kept under the road, so rule 1 keeps peak brightness on the lanes — but only
## just, because this is the one edge on the map a player collides with and the
## reference draws it as pale masonry, not as shadow.
const C_ROCK_EDGE := Color("6b6f66")
const C_ROCK_EDGE_LIT := Color("7b7f75")
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
## carried by its banks rather than by a per-tile pattern. It used to be warm
## because the road was — a cold kerb on warm sand read as a line drawn *on* the
## surface rather than as its edge. With the road now cool stone (rule 6, reversed
## 2026-08-09) the same argument runs the other way and the kerb goes cool with it.
const C_LANE_EDGE := Color("363b3d")
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
const C_PIT_BASIN := Color(0.0, 0.0, 0.0, 0.14)
## The shaded inside of a bowl's northern wall — the surface that faces away from
## the light. Alpha, so one value works on both tiers.
const C_PIT_WALL_SHADE := Color(0.0, 0.0, 0.0, 0.34)
## The dais at the pit's eye — the one cell the objective stands on, and the
## lightest thing inside the bowl. Kept a shade under the road: rule 1 gives peak
## brightness to the lanes, and this earns its read by being one bright cell in a
## dark hollow rather than by out-shouting anything.
const C_PIT_EYE := Color("767b71")
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
const C_FORD := Color(0.494, 0.514, 0.522, 0.45)
## How far a ford looks for paving. The mid lane is ~5 cells wide where it cuts the
## river, so anything less than that finds nothing.
const FORD_REACH := 5
const C_RIVER_SHIMMER := Color("5b96ad")
## Scuffed earth where the camp is fought over. Run 1 took the painted reference
## at its word and put torch fire on all eight camps, which made the jungle the
## most decorated part of the map and gave the map two warm accents competing at
## overview scale. Rule 7 keeps the jungle as texture rather than scenery, so this
## is a near-neutral olive-brown that reads as bare ground at zoom and disappears
## into texture at overview — which is what a camp should do to the eye. (Rule 6
## used to be the citation here, on the grounds that the road owned the map's only
## warm hue; that clause was reversed on 2026-08-09 and rule 7 is what actually
## holds the camps down.)
const C_CAMP_MARK := Color("4c4a35")
## Foliage stipple *within* the brush patch — §6.3 rule 4's "noise lives inside a
## mass, never defining its shape". Only a shade off the patch itself: the patch
## is read by its value, and the tufts only say what kind of surface it is.
const C_BRUSH_TUFT := Color("3c5029")
## Blade tips where a brush patch meets open ground — the patch's silhouette.
## Lighter than the brush it edges (0.40 against 0.36) and under the road (0.44),
## so it gives brush a shape without taking rule 1's peak brightness off the lanes.
const C_BRUSH_EDGE := Color("5a6e3e")
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
						cell_px * 0.28, C_CAMP_MARK)
				Terrain.BRUSH:
					_draw_brush_tufts(ci, t, c, r, pos, cell_px)
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
	var is_canopy: bool = t.wall_class(c, r) == Terrain.ROCK
	if is_canopy:
		_draw_canopy_crowns(ci, c, r, pos, cell_px)
	var n_open: bool = t.kind_at_cell(c, r - 1) != Terrain.WALL
	var s_open: bool = t.kind_at_cell(c, r + 1) != Terrain.WALL
	var w_open: bool = t.kind_at_cell(c - 1, r) != Terrain.WALL
	var e_open: bool = t.kind_at_cell(c + 1, r) != Terrain.WALL

	# The sixth shape (§6.3 rule 3, designer decision 2026-08-09): a canopy mass is
	# trees, but its *boundary* is stone. Four cold panels filed "which green is
	# walkable" as invisible, at three different green/canopy ratios, with and
	# without crown texture. The variable was never tone or ratio — it was material,
	# and the only two configurations that ever read were stone-against-green and
	# green-against-earth. This buys the material distinction back without giving up
	# the canopy the designer asked for: the mass stays green, and the edge a player
	# would actually collide with is rock.
	#
	# Drawn only where the mass meets open ground, so it is the silhouette rather
	# than a fill, and it costs nothing in the mass's interior.
	var b: float = maxf(1.0, cell_px * 0.30)
	if is_canopy:
		if s_open:
			ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - b), Vector2(cell_px, b)), C_ROCK_EDGE)
		if w_open:
			ci.draw_rect(Rect2(pos, Vector2(b, cell_px)), C_ROCK_EDGE)
		if e_open:
			ci.draw_rect(Rect2(pos + Vector2(cell_px - b, 0.0), Vector2(b, cell_px)), C_ROCK_EDGE)
		# North last and lighter: the face the light hits, same sun as everything
		# else raised on this map. Drawn over the side bands so a corner reads as
		# one lit cap rather than two materials meeting.
		if n_open:
			ci.draw_rect(Rect2(pos, Vector2(cell_px, b)), C_ROCK_EDGE_LIT)
	elif n_open:
		# The rampart is masonry already and keeps the older treatment.
		ci.draw_rect(Rect2(pos, Vector2(cell_px, maxf(1.0, cell_px * 0.26))), C_WALL_LIT)

	if s_open:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px),
			Vector2(cell_px, maxf(1.0, cell_px * ROCK_SHADOW_DEPTH))), C_ROCK_SHADOW)
	# A dark contact line on every face that meets open ground — §6.3 rule 5's
	# "dark outline", which the mass previously only had east and west. An outline
	# that stops on two sides is not an outline: it reads as two stripes, and it
	# left the south face relying on a cast shadow alone to say the mass was there.
	# It is now the seam *under* the stone rather than the mass's whole edge.
	var e: float = maxf(1.0, cell_px * 0.10 if is_canopy else cell_px * 0.16)
	if w_open:
		ci.draw_rect(Rect2(pos, Vector2(e, cell_px)), C_WALL_SHADE)
	if e_open:
		ci.draw_rect(Rect2(pos + Vector2(cell_px - e, 0.0), Vector2(e, cell_px)), C_WALL_SHADE)
	if s_open:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - e), Vector2(cell_px, e)), C_WALL_SHADE)


## Foliage, drawn as crowns rather than as fill.
##
## Panel 11 is why this exists, and it is the clearest A/B the loop has run. One
## variable changed between panels 10 and 11 — blocking mass went from grey stone
## to canopy (rule 6′) — and the same cold reader's verdict on *"which of these can
## I walk through"* went from "strong and unambiguous everywhere", filed `certain`,
## to "I genuinely cannot tell which", filed **invisible**. Both critics described
## the masses the same way: flat outlined polygons.
##
## The diagnosis is not contrast. Measured, canopy interior sits at 0.135 against a
## floor of 0.283 — a wider value gap than grey-on-green ever had. What grey was
## silently providing was not separation but *material*: a viewer knows stone blocks
## and does not know what a green shape does. So the fix has to say **tree**, and a
## tree is a round crown with shade under it, not a rectangle.
##
## Rule 4 is the constraint: noise lives inside a mass and never defines its shape.
## So crowns are clipped to the cell, the mass's silhouette is still the grid's, and
## the cap, contact line and cast shadow all draw over the top of this.
static func _draw_canopy_crowns(ci: CanvasItem, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	var h := _hash(c, r)
	for i in 2:
		var fx: float = 0.28 + float((h >> (i * 7)) % 45) / 100.0
		var fy: float = 0.26 + float((h >> (i * 7 + 4)) % 45) / 100.0
		var centre := pos + Vector2(fx, fy) * cell_px
		var rad: float = cell_px * (0.20 + float((h >> (i * 3)) % 9) / 100.0)
		# Shade under the crown before the crown itself, offset south: the same sun
		# that lights every cap on this map from the north, applied one scale down.
		ci.draw_circle(centre + Vector2(0.0, rad * 0.34), rad, C_CANOPY_UNDER)
		ci.draw_circle(centre, rad, C_CANOPY_CROWN)


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
		_draw_hollow_walls(ci, pos, cell_px,
			_pit_depth(t, c, r - 1) < 2, _pit_depth(t, c, r + 1) < 2)
	if depth >= 3:
		ci.draw_circle(pos + Vector2(cell_px, cell_px) * 0.5, cell_px * 0.34, C_PIT_EYE)
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
	_draw_hollow_walls(ci, pos, cell_px,
		t.kind_at_cell(c, r - 1) != Terrain.PIT, t.kind_at_cell(c, r + 1) != Terrain.PIT)


## The inside faces of a hollow, lit by the same northern sun as everything else —
## and therefore lit the other way round.
##
## Every raised thing on this map catches light on its north face and casts shadow
## south. A hollow is the same sun and the opposite surface: standing at the north
## edge of a bowl, the wall descending in front of you faces *away* from the light
## and is shaded, while the far wall at the south edge faces into it and is lit. So
## a hole is a dark band at the top and a light band at the bottom, which is exactly
## the inverse of the rock convention.
##
## Getting this backwards is what made both critics at panel 8 call the pits "raised
## bright pads" and "raised plazas or podiums, not sunken pits" — iteration 33 had
## fixed their *shape* by putting them under the map's lighting rule, and put them
## under the rule for the wrong kind of object. The tell was there in the same
## reports: the reference's objectives are "recessed ... sunk into the terrain".
static func _draw_hollow_walls(ci: CanvasItem, pos: Vector2, cell_px: float,
		north_open: bool, south_open: bool) -> void:
	var w: float = maxf(1.0, cell_px * 0.2)
	if north_open:
		ci.draw_rect(Rect2(pos, Vector2(cell_px, w)), C_PIT_WALL_SHADE)
	if south_open:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - w), Vector2(cell_px, w)), C_PIT_RIM)


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


## Tufts give a brush cell texture; they do not give a brush *patch* a shape. Every
## feature on this map that a cold reader can find has an edge — the lane its kerb,
## a rock its contact line, a pit its lip — and brush was the only one drawn as
## interior detail alone. So a patch got no silhouette, and the report that follows
## from that is the one every panel has filed: "one shade off ordinary grass, no
## border, no shadow", and camps and brush mistaken for each other.
##
## The rim is *lighter* than the patch, and that direction is the whole point. A dark
## contact line is how this renderer says "raised and solid" (rule 5), so putting one
## around brush would argue it blocks — which is the exact ambiguity runs 2 and 3
## spent four iterations closing. Brush is walkable and lighter than the floor by
## rule 1, so it gets brighter at its boundary: blade tips catching the light where
## the tall grass ends, the same inversion the pits used to say "sunk" with the cue
## that everywhere else says "raised".
##
## Kept under the road. Rule 1 gives peak brightness to the lanes and a rim only ever
## needs to be the lightest thing in its own neighbourhood.
static func _draw_brush_tufts(ci: CanvasItem, t: Terrain, c: int, r: int,
		pos: Vector2, cell_px: float) -> void:
	var h := _hash(c, r)
	for i in 3:
		var fx: float = float((h >> (i * 5)) % 100) / 100.0
		var fy: float = float((h >> (i * 5 + 3)) % 100) / 100.0
		ci.draw_rect(Rect2(pos + Vector2(fx, fy) * cell_px * 0.7,
			Vector2(maxf(1.0, cell_px * 0.16), maxf(1.0, cell_px * 0.3))), C_BRUSH_TUFT)
	var w: float = maxf(1.0, cell_px * 0.18)
	# north, south, west, east — every face that does not meet more brush
	if t.kind_at_cell(c, r - 1) != Terrain.BRUSH:
		ci.draw_rect(Rect2(pos, Vector2(cell_px, w)), C_BRUSH_EDGE)
	if t.kind_at_cell(c, r + 1) != Terrain.BRUSH:
		ci.draw_rect(Rect2(pos + Vector2(0.0, cell_px - w), Vector2(cell_px, w)), C_BRUSH_EDGE)
	if t.kind_at_cell(c - 1, r) != Terrain.BRUSH:
		ci.draw_rect(Rect2(pos, Vector2(w, cell_px)), C_BRUSH_EDGE)
	if t.kind_at_cell(c + 1, r) != Terrain.BRUSH:
		ci.draw_rect(Rect2(pos + Vector2(cell_px - w, 0.0), Vector2(w, cell_px)), C_BRUSH_EDGE)


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
