# Map reference images

**Designer: drop the images here.** Any filename, PNG or JPG. That is the whole handover —
I read the folder, not the chat, so the reference survives the conversation it arrived in.

These are evidence for **gauntlet loop 1** (`docs/gauntlet-map.md`). They are no longer the
acceptance criteria on their own: **the criteria are GDD §6.3**, the eight rules the map obeys.
Where an image here and §6.3 disagree, §6.3 wins and the difference is logged `by-design`.
Read §6.3 before the loop's first iteration of a session.

Useful, if you have them, but never blocking — one image is enough to start:

- **the whole map**, top-down, the way it is normally seen. This is the one that matters most,
  because it is the view the game is in for most of a match.
- **a closer crop** of any part of it — jungle, a lane, a pit. Says what the texture and edge
  detail should be at zoom, which the whole-map shot cannot.
- **anything you like the look of but do not want copied.** Say so in a line of text next to
  it and I will record it as a deliberate difference rather than chase it.

If an image is meant to fix the *layout* (where the walls and corridors go) rather than the
*look* (colour, texture, edges), it is worth saying which — they pull on different halves of
the rubric, and I will otherwise assume an image is aiming at both.

---

## What is in here now

### `terrain_moba_3.png` — the only reference (designer, 2026-08-09)

The third and best. `terrain_moba_2.png` and the crop before it were both **deleted** — the
folder is globbed, so two pictures in two different hands are two contradictory targets and a
broken instrument. One picture, one answer.

Why this one supersedes the paintings: it is genuinely **top-down**, so nothing has to be
translated out of a 3/4 projection, and it is the first reference whose layout is actually a
MOBA map — three readable lanes, a diagonal river running correctly against the base diagonal,
bases in opposite corners, brush as tall grass, towers standing on lanes. It is also closer to
pixel art than to painting, which is what a tile renderer can actually reach.

**It is still not the layout.** `data/terrain.txt` and `data/map.json` own that, and they are
gate-checked for 180° symmetry, which no generated image is. Do not trace it.

One layout fact it *confirms* rather than dictates: the designer restored the second river
alcove on 2026-08-09 so the two objective pits mirror each other. Measured from the image, the
midpoint of the two pit centres lands within ~1% of the image centre — they are proper 180°
mirrors. That matches `map.json` (`baron [31,55]`, `dragon [69,45]`) and settles the
one-boss question: **two pits stay.**

**Deliberate differences — present in the reference, not wanted in the map:**

| In the reference | Why we are not chasing it |
|---|---|
| Statues, torches, braziers, tower and nexus sprites, per-object props | Authored art on a bitmap. The terrain layer is a tile painter; props need a decal/sprite layer, which is not M6-T1. Towers and the nexus *are* drawn by `game/map_view.gd` over the terrain — that is the structures layer, not this one. |
| Crystal glow, torch bloom, soft cast light | Value *hierarchy* is in scope; painted light is not. |
| The dark tree border framing the arena | A vignette by another name. It is a framed picture; our map pans and zooms, so a baked-in dark edge would slide across the world. Screen-space overlay in the viewer if ever wanted. |
| 4:3 aspect | Artefact of the frame. The world is square 100×100. |
| Stray white sparkles | Generator residue. Not a map feature. |
| Ornament spread evenly over the whole map | GDD §6.3 rule 7 — the budget goes to the bases, the two pits and the river; jungle is texture. |
| Fine-grained detail defining the shape of a mass | §6.3 rule 4 — masses are big and chunky, noise lives *inside* a mass. |
| Rich overall saturation | §6.3 rule 2 — water is the only strongly saturated thing on the map. |
| Stone lighter than the ground it stands in — pale walls on dark green | §6.3 rule 1, upheld by designer decision 2026-08-09. Reported twice as *"pits punched through the ground"*; the legibility critic read the same walls as *"unmistakably walls, immediately"*. Two critics disagreeing is a design decision, and it was decided for the reader. |
| Two visually distinct objective sites (a dry grey basin, a glowing teal one) | Needs an icon layer. Both pits are identical by construction; dragon versus baron is an icon, not a terrain colour. Out of scope for M6-T1. |

**Manual-edit artefacts — the designer's own note, 2026-08-09.** The image was photoshopped to
restore the second alcove, and some marks survived. They are damage, not design, and no critic
finding that points at them is real:

| Artefact | Where |
|---|---|
| A disconnected stub of river | Bottom-right corner, outside the arena, not joined to the main channel. The most misleading of the three — it invites *"the river forks"*, which would be a genuine finding against a map where it does not. |
| An orphan gate structure connected to nothing | Top-left corner. |
| Free-standing stone arches in open jungle | Mid-left and mid-right. These read as ruins and are plausibly deliberate scenery; listed for completeness, not as a defect to chase. |

The riverside wall remnant reported on 2026-08-09 is **fixed** — restoring the alcove removed it.

### Open — the two reversals, not yet decided

Two things in this image contradict decisions taken during gauntlet run 3 and signed off on
2026-08-09. They are recorded here as **open**, deliberately *not* filed as `by-design`
refusals, because the designer may be re-directing rather than disagreeing:

1. **Green as the dominant field, with narrower stone roads through it.** The shipped map is
   602 road cells to 296 green — tan road is the field. That ratio was raised as a finding and
   kept on 2026-08-09, but it was kept against a *different* reference.
2. **Trees as the blocking terrain.** In this image the thing you cannot walk through is dark
   canopy. In the shipped map it is grey rock, and *"blocking terrain stops being green"* was a
   whole iteration closing the oldest finding in the log.

Until the designer answers, the shipped look stands and these two do not block anything.
If the answer is "re-direct", it is **gauntlet run 4** and it reopens M6-T1's look.

**Still missing, and worth having:** a close crop of one jungle quadrant, at zoom. The designer
showed a six-panel detail sheet on 2026-08-09 but it was never saved here. Two caveats if it
lands: it is drawn in 3/4, not top-down, so take the shading recipe (lit top face, dark side,
cast shadow) and refuse the projection; and four of its six panels are ornament-budget places,
so its jungle and river panels will pull toward a density §6.3 rule 7 refuses. Note also that
the render rig has no crop option yet — comparing a whole-map render against a close crop
inflates every texture finding, so that is a prerequisite, not an afterthought.
