# M6-T1 — gauntlet loop 1, first run against the reference

The reference image landed, so the loop ran for real for the first time: seven iterations
(`iter03`–`iter10`) and two critic panels. Full log with per-iteration detail in
`docs/gauntlet-map.md`.

## What to look at

`.shots/iter10.png` is the current map. Worth flipping between `iter03.png` (the pre-reference
baseline) and `iter10.png` — they are the same terrain grid, drawn differently, apart from one
rendering fix that changed no cells.

## What changed

Nothing in `data/terrain.txt`. Every change is in how the map is drawn.

- **Palette** pulled onto the reference's world: a green jungle cut by grey stone, warm torch
  accents. The baseline was the inverse — navy rock over khaki roads, green nowhere.
- **Lanes** stopped being a chequerboard. The road surface is flat and the *banks* are dark, so a
  straight run reads as one road instead of a chain of paving slabs.
- **Pits** got a bright stone rim. They are now the most findable things on the map, which is right
  — they are where the two biggest fights of a match happen.
- **A ford** where mid crosses the river, so the channel carries across the road instead of stopping
  dead at it.
- **An arena boundary.** Out-of-bounds is now near-black; rock *inside* the arena stays green. The
  map has an edge.
- **Bases** are paved precincts with a masonry wall, open at the lane mouths, rather than flat
  colour swatches.
- **Height.** Rock casts a shadow onto the ground south of it. This was the largest single
  legibility gain of the run — see below.

## The one number worth knowing

The cold reader's coordinates were checked against `data/terrain.txt` at both panels. It claimed 8
camp clusters, 2 pits, 4 river components and 9 brush patches, all with coordinates — **every one
verified, and it claimed nothing that was not there.** That matters more than any individual
finding: it means the map is legible rather than merely suggestive, and it means the panel's
*omissions* are the real signal. What it could not see was never "a feature I drew badly" but
"a feature that carries no cue at all".

The biggest of those: at both panels the reader could not tell which greens were walkable — roughly
half the map's area. Hue changes did not fix it. Casting rock shadows onto adjacent ground did,
because the cue for "you cannot walk here" is height, not colour.

## Question for you — the arena margin

This is the one thing I have stopped on, because it is a gameplay decision rather than an art one.

Both panels' top finding reduces to a single geometric fact: **the arena has no outer margin.** The
outer lanes run 2 cells from the map edge (4% of map width); the bases run 1 cell. In your reference
the outer road sits well inside a thick stone rampart, with jungle between the two — which is why
three lanes read instantly there and why, here, the perimeter road and the map boundary are the same
grey band doing two contradictory jobs.

Painting cannot reach this. Fixing it means pulling the outer lanes and both base footprints inward,
which changes:

- **lane length** — longer walk from base to the outer towers, so slower early rotations
- **jungle volume** — a new band of jungle outside the lanes, which is more space for the jungler
- **`data/map.json`** — lane polylines, tower positions, base anchors all move

So, three ways to go:

1. **Inset the lanes** — match the reference, accept the pacing change, and rebalance afterwards
   with the batch runner.
2. **Leave the geometry, sell the boundary differently** — a taller, more textured rampart drawn
   into the existing 2 cells. Cheaper, and it will be a compromise; the two panels will probably
   keep circling it.
3. **Declare it a deliberate difference** — the reference is an illustration, not a playable map,
   and a tight margin may be the right call for a viewport that is mostly watched zoomed out.

I would go with (1), on the grounds that it is the only option that closes the finding, and that
lane length is a number we can retune from data once the shape is right. But the pacing consequence
is yours to accept, not mine.

## Not done, deliberately

- **Camps read as bare orange dot grids.** Both panels flagged it; both rated it `moderate`. It
  wants camps to be *places* — a clearing with a rock — which is texture work best done in one pass
  with the other texture findings.
- **No vignette**, though the fidelity critic asked twice. The reference is a framed illustration;
  the map is a viewport that pans and zooms. If you want one it belongs in the viewer as a
  screen-space overlay, not baked into the terrain.
- **"No towers, inhibitors or nexus anywhere"** — reported by the cold reader at both panels, and
  an artefact of what the loop renders. `game/map_view.gd` draws all of them over the terrain every
  frame; the still-frame rig draws terrain alone. Worth deciding whether the panel should grade a
  render *with* structures, since that is the picture you actually watch a match on.

## State

Runnable. `tools/check.sh` green: data validation, terrain guard rails, determinism across three
seeds, viewer selftest.
