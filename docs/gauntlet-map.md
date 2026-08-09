# Gauntlet loop 1 — the map

**Goal:** build the map to match the designer's reference images, and keep going until neither the
critics nor the designer can name a difference that would show at overview scale.

This file is the loop's **rubric and its log** — what the map has to achieve, and what each iteration
did about it. The **procedure** (roles, checkpoints, stopping rule) is
`.claude/skills/gauntlet-map/SKILL.md`. The map's design model is `GDD.md` §6.2; the phase plan is
`BACKLOG.md` under **M6-T**.

## Why a loop, and why it has critics in it

The map is the one artefact whose acceptance test is "does it look right?", which cannot be answered
by reading the code that drew it. So the work runs as a closed loop: render, compare, change one
thing, render again. That only pays because a render is one command and under a second.

The part that is easy to get wrong is who does the judging. An agent grading its own picture knows
what it was *trying* to draw, so it sees the intention instead of the pixels and converges on "looks
good to me" in about three iterations. So judging is split off to subagents that come in cold, having
seen only the image — no code, no design docs, no account of what changed. That coldness is the only
thing they provide, and the protocol in the skill file exists to protect it.

| Role | Who |
|---|---|
| Orchestrator + designer | the main agent |
| Machine critic | `Terrain.validate`, run by `tools/gauntlet.sh` and `tools/check.sh` |
| Fidelity critic | `map-fidelity-critic` subagent — render vs. reference |
| Legibility critic | `map-legibility-critic` subagent — can a cold viewer read this map at all |

## The rig

| | |
|---|---|
| `data/terrain.txt` | the map itself — a 50×50 character grid, one char per 2×2 world units, readable and editable as a picture in any text editor. Legend in the file's own header. |
| `sim/terrain.gd` | loads the grid and owns the guard rails. Pure GDScript, no Node deps — T2's navigation builds on it. |
| `game/terrain_view.gd` | draws it. **Shared** with the match viewer, so the loop grades the pixels the game shows. Every colour and detail knob is in one block at the top. |
| `tools/gauntlet.sh` | one iteration: gate, then render. |
| `tools/terrain_tool.gd` | the gate itself (`--check`), and symmetry repair (`--mirror`). |
| `tools/shot.sh` | the bare renderer, if you want an image without the gate. |

```bash
tools/gauntlet.sh iter04 --overlay      # gate + .shots/iter04.png + iter04-overlay.png
godot --headless --path . --script res://tools/terrain_tool.gd -- --mirror=red --write
```

Two things worth knowing:

- **It renders windowed, not headless.** Godot has no rendering context under `--headless` — the
  viewport texture comes back null. A small window is parked off-screen for a fraction of a second.
- **The picture is deterministic.** Per-cell tonal noise is hashed from the cell index, never from an
  RNG. Same map, same image, every run — otherwise two iterations could not be compared. The
  project's determinism rule applies to the picture for the same reason it applies to the sim.

Renders go to `.shots/` (gitignored). Reference images go to `docs/reference/map/` and **are**
committed: they are the acceptance criteria, and they must outlive the chat they arrived in.

## The rubric

**A — Guard rails.** Machine-checked, binary, must pass every iteration. Enforced by
`Terrain.validate` and wired into `tools/check.sh`:
- exactly N rows of N characters, no unknown characters
- **180° rotational symmetry** — blue-side win rate is a tracked balance metric, so an asymmetric map
  would poison every number the project has
- every base, pit, camp and tower position in `data/map.json` on walkable ground
- every walkable cell reachable from both bases (catches a wall typed across a corridor that seals off
  a pocket of jungle)

**B — Layout fidelity.** Judged by `map-fidelity-critic`. Lanes, river, pits, jungle quadrants, base
footprints, corridors and chokepoints, all against the reference.

**C — Look fidelity.** Same critic. Palette and especially contrast *relationships* (rock against
floor, lane against jungle); surface texture; edge treatment; and legibility at overview scale — the
map is normally seen whole, so detail that turns to mush at 1024 px is worse than no detail.

**C′ — What C does not cover, and the three buckets.** The critic compares the render to a picture.
The map's actual target is **GDD §6.3**, which the critic has never read and must never be told about.
So its findings land in three buckets, and the orchestrator does the sorting — never the critic.

| Bucket | Meaning | Blocks the exit? |
|---|---|---|
| `in-scope` | A real gap between the render and where the map is going. | **Yes.** Fix it. |
| `out-of-scope` | Unreachable by any knob this renderer has: per-object props, painted lighting, the vignette, the 4:3 frame, the watermark. | No. Logged. |
| `by-design` | Reachable, and refused. The reference has it; §6.3 says we do not want it. Density, even ornament, fine detail defining mass shape, overall richness. | No. Logged **with the §6.3 rule number** that overrules it. |

The `by-design` bucket is the one that can be abused, so it has a cost attached: every filing cites
a numbered rule in §6.3. If there is no rule to cite, it is not `by-design` — it is a finding you
did not want, and it goes in `in-scope`. Wanting to skip work is not a design position. If you find
yourself needing a rule that does not exist yet, that is a question for the designer and §6.3 is
theirs to amend, not yours.

This sorting is load-bearing. Without it the exit is unreachable: the panel returns the same texture,
lighting and density findings at every checkpoint, the loop either grinds forever or quietly lowers
its own bar, and neither outcome is visible in the log. Filing them explicitly keeps the critic sharp
and the ceiling honest — and it keeps the two rejections *different*, because "we cannot" and "we
chose not to" are not the same admission. If a finding filed `out-of-scope` is one you would actually
pay for, that is a decision to add an art layer and it belongs to the designer.

**D — Legibility, cold.** Judged by `map-legibility-critic`, which never sees the reference. Can
someone who has never seen this game find the lanes, the river, the pits, the bases? Every claim it
makes comes with coordinates, which the orchestrator verifies against `data/terrain.txt` — a confident
claim about something that is not there means the map is suggestive rather than legible, and is itself
a finding.

**E — Agreement with the sim.** `--overlay` draws `data/map.json`'s own geometry on the render. The
lanes drawn must be the lanes the minions walk. Where picture and data disagree, one of them is wrong
and it is not always the picture.

## Exit criteria

A single checkpoint producing all of: guard rails clean; no **in-scope** fidelity finding above
`cosmetic` (see C′ — findings filed `out-of-scope` or `by-design` are logged, not chased); every real feature
identified by the legibility critic with verifying coordinates and nothing claimed that is not there;
overlay agreeing with `map.json`.

Then the designer looks at the final render next to the reference and signs off. **That is the real
exit** — the rest exists so the designer is only ever asked to judge something that has already passed
everything a machine and two cold readers could.

## Log

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 00 | Rig built. Draft-1 grid from `REPORTS/M6-terrain-scoping.md`, baseline palette. | **FAIL** — 143 asymmetric cell pairs | — | Lanes and river read immediately; recognisably SR-shaped. Bases visibly different sizes (the asymmetry). Lane fill reads as a chequerboard of tiles, not a road. Rock faces invisible at this scale. Pits indistinguishable from walls. |
| 01 | `--mirror=red --write`. | **pass** | — | Symmetry fixed. The art problems in row 00 all stand — and are exactly what the reference decides, so left alone. |
| 02 | Loop built: two cold critics, orchestrator skill, `tools/gauntlet.sh`, terrain gate wired into `tools/check.sh`. Retired the unused sim-macro critic pipeline. | **pass** | not yet run | No visual change — this iteration was structural. |

| 03 | Reference image landed (`Pixel_art_MOBA_arena_map_…jpeg`). Baseline re-render, no change. | **pass** | — | Against the reference the render is inverted: navy rock over khaki roads, green nowhere. The reference is a *green* jungle cut by *grey stone*, lit by warm torches. |
| 04 | Repalette to the reference's hues and contrast ordering (lane lightest → floor → rock → void). Fixed a latent bug: `_draw_brush_tufts` painted with `C_CAMP_MARK`, not `C_BRUSH_TUFT`. | **pass** | — | Colour world now right. The lane chequerboard, previously masked by the khaki, is now the loudest defect. |
| 05 | Lanes: replaced the per-cell inset square with **banked edges** — flat surface, dark kerb only on sides facing off-road. | **pass** | — | Lanes read as continuous roads. Three routes legible at a glance. |
| 06 | Pits: bright stone rim wherever pit meets non-pit; floor darkened. | **pass** | **panel 1** ↓ | Pits became the clearest objects on the map. Darkening the floor was my guess, and it was wrong — see panel 1. |

### Panel 1 — on `iter06`

**Gate:** clean. **Fidelity:** 2 × `breaks-immersion` (bases are flat colour swatches; river severed into
puddles), 6 × `moderate` (mid lane too wide/straight/bright; pits read as holes — *contrast inverted vs
reference*; camps are dot grids; no map boundary; flat surfaces, no lighting; hard stair edges).
**Legibility:** identified lanes, river, both pits, both bases, brush and camps. Its five "actively
confusing" items led with *"the near-black green inside the ring is the same colour as the region
outside it — I cannot tell which greens are passable."*

**Coordinate verification — the reason this checkpoint is trustworthy.** Every claim checked against
the grid:

| Claim | Ground truth | |
|---|---|---|
| 8 camp clusters, all 8 coordinates | 8 clusters, all within 0.02 | ✓ |
| 2 pits at (.385,.385), (.625,.625) | (.38,.38), (.62,.62) | ✓ |
| River = 2 long arms + 2 small diamonds | 4 components: 65, 65, 18, 18 cells | ✓ |
| 9 brush patches | all 9 verify | ✓ |

**Zero confabulations** — nothing was claimed that is not in `data/terrain.txt`. On the features it
could see, the map is legible rather than merely suggestive. Its failures were all *omissions*, not
inventions. And the river finding was not a rendering artefact: the river genuinely is severed into
four components in the data, which both critics found independently and neither was told.

**Acted on the top three.** Deliberately left: camps-as-dot-grids, flat surfaces, hard edges — all
`moderate`, all texture work that wants its own iteration.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 07 | River continuity. **Ford**: lane cells with water on both sides get a translucent water band, so the channel carries across mid. Pit floor corrected to warm stone — *lighter* than surroundings, per the reference; iteration 06 had it backwards. | **pass** | — | First attempt drew nothing. Mid and the river cross at 90° to each other but 45° to the grid, so an axis-aligned scan found water on both sides of precisely zero cells. Adding the diagonal axes selects 16 cells, all at the centre crossing, stable for any reach 4–6. |
| 08 | Arena boundary. `Terrain.is_surround_cell()` flood-fills wall from the map border: 454 surround cells vs 640 interior rock, cleanly disjoint. Surround → near-black void; interior rock keeps its green and its lit face. | **pass** | — | The arena now has an edge. Directly answers the legibility critic's #1 confusion. |
| 09 | Bases as walled precincts: paved stone leaning to the team colour rather than a saturated fill, plus a masonry rim that treats LANE as inside, so the lane mouths stay open as gates. | **pass** | **panel 2** ↓ | Bases read as built ground instead of colour swatches. |

**Scope note — "no structures at all".** The legibility critic reported no towers, inhibitors or nexus
anywhere. Verified: `game/map_view.gd:115-116` draws bases, towers and nexus over the terrain every
frame; the still-frame rig draws the terrain layer alone. So this is an artefact of *what the loop
renders*, not a defect in the map, and adding structures to `TerrainView` would duplicate the viewer
and break the shared-renderer contract. Logged, not chased — but it does mean the panel is grading a
picture the player never quite sees, which is a question for the designer.

### Panel 2 — on `iter09`

**Gate:** clean. **Fidelity:** 3 × `breaks-immersion` (outer lanes and the boundary wall are the same
grey ring; bases still flat swatches, and they spill past the boundary; everything is flat fill, no
height or light — escalated from `moderate`), 3 × `moderate`, 1 × `cosmetic`. **Legibility:** the
arena boundary now reads as unambiguous out-of-bounds — panel 1's #1 confusion is gone. Both pits,
the river, the ford waist and the mid corridor are `certain`. New #1 confusion: *"the perimeter grey
vs. the diagonal grey — identical material, contradictory functions."*

**The two panels are describing one fault, not two.** Panel 1: "the outer wall is missing." Panel 2,
after I supplied a boundary: "the boundary and the lane are indistinguishable." This is the
oscillation pattern the skill warns about, and the diagnosis is that neither finding is about colour.
Measured against the grid: the outer lane sits **2 cells from the map edge** (4% of map width) and the
base footprints **1 cell**. There is physically nowhere for a rampart to live, so whatever I paint in
that margin either vanishes or competes with the road. The reference puts the road well inside a thick
wall with jungle between the two. The fix is layout, and palette iterations cannot reach it.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 10 | Rock height. Lit cap stays on the north edge, but the shadow now falls *forward onto the open ground to the south* instead of onto the rock itself, plus a contact line on the east/west faces. | **pass** | — | The single largest legibility gain so far. Rock reads as raised formations standing on a continuous grass floor; the "which greens are walkable" question that both panels led with is largely answered by shadow rather than by hue. |

**Deliberate difference — no vignette.** The fidelity critic asked for the reference's vignette twice.
Declining: the reference is a single framed illustration, the map is a viewport that pans and zooms, and
a vignette baked into terrain drawing would swim against the camera. If the designer wants one it
belongs in the viewer as a screen-space overlay, not here.

**Full suite green after the `sim/terrain.gd` change:** data validation, guard rails, determinism
across 3 seeds, viewer selftest.

### Designer decisions, 2026-08-08

Asked at the pause after panel 2, both answered:

1. **Inset the lanes** — match the reference, accept the pacing change, rebalance from data after.
2. **Add structures to the capture** — the panel should grade the picture a player actually watches.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 11 | Outer lanes inset by moving their **polylines in `data/map.json`** and re-rasterising the terrain band around them, half-width 3.6 world units. Towers needed no edit — they are stored as a fraction along the lane, so they ride the path. | **pass** | — | Margin 2 → 5 cells. But the new margin rendered *entirely black*: see below. |
| 12 | `is_surround_cell` → `is_void_cell`: border-connected **and** more than `RAMPART_DEPTH` from walkable ground. | **pass** | — | The band nearest the arena now reads as its wall, the deep part as nothing. Hierarchy is light road, dark rock wall, black void. |
| 13 | `tools/shoot_map.gd --structures`, on by default in `gauntlet.sh` (`--bare` opts out). Towers and nexuses drawn intact in the viewer's own idiom. | **pass** | **panel 3** ↓ | Towers sit on the roads, which is criterion E confirmed by eye: terrain and `map.json` now agree *by construction*, both being generated from the same polyline. |

**Four failed attempts before the one that worked**, all trying to transform `data/terrain.txt`
directly, and each failure was informative:

1. shift rows and columns by available room — tore the corners, where the row rule and the column
   rule fight over the same cells;
2. same, restricted to straight stretches — the top band is *diagonal*, so shifting each column
   independently sheared it;
3. trim the outer edge instead of shifting — a per-row rule cannot see that a lane run is a base
   *mouth*, and it walled both bases in;
4. windowed column pass — the window boundary became a cliff the band stepped off.

The band is a distance field around a path, so it had to be treated as one: move the path, repaint
the cells within half-width of it. That version also fixes criterion E for free, because the picture
and the sim are now generated from the same numbers rather than kept in sync by hand.

**A fix can create the next finding.** Iteration 11 passed the gate and looked *worse*: pulling the
lanes inward made the margin bigger, and since "out of bounds" was defined as *border-connected wall*,
a bigger margin was simply more black. The road went straight back to abutting the void — panel 2's
finding, restored by the change meant to close it. The definition had to become "outside **and** far
from walkable" before the geometry could pay off. Worth remembering: the guard rails cannot catch
this class of thing, and neither can a self-graded look at the render, because I knew what I had
changed and saw the intent.

### Panel 3 — on `iter13` (first render including structures)

**Gate:** clean. **Fidelity:** 2 × `breaks-immersion` — *"terrain is flat unshaded colour fill"* and
*"overall value and saturation much higher than reference"* — plus 6 × `moderate`. **Legibility:**
lanes, river, both pits, both bases, the ford and all nine towers per side identified; its
highest-priority confusion was again *"dark-green canopy vs mid-green ground — I would have mistaken
impassable terrain for open jungle with roughly 50/50 odds."*

**Coordinate verification:** 8 camps, 2 pits, 6 brush patches, ~9 towers per side — all verified
against `data/terrain.txt` and `data/map.json`. **Third panel running, still zero confabulations.**

The structures change paid for itself immediately: with towers on the map the cold reader could read
territory — *"the colour gradient along each lane makes ownership legible without any labels, which
is the map's strongest single success"* — a sentence no terrain-only render could ever have produced.

**Both critics converged on value structure**, from opposite directions: too bright and too flat
against the reference, and not enough separation between walkable floor and blocking canopy. Those
are compatible, and the fix is one change.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 14 | Lowered the whole key toward the reference's low-key palette, and split `is_void_cell` into `wall_class` → `ROCK` / `RAMPART` / `VOID`. Value hierarchy is now explicit: road › rampart › jungle floor › canopy › void. Pits to grey stone (the reference has no tan anywhere). Void loses its tonal jitter — speckled black reads as texture, and there is nothing out there to have texture. | **pass** | — | Canopy and floor now separate at a glance, which is the question both cold readers have led with since panel 1. The rampart reads as built wall rather than more jungle. |

## Reference swap — end of run 1

`Pixel_art_MOBA_arena_map_…jpeg` → **`terrain_moba_2.png`** (designer, 2026-08-08). The same
artwork, uncropped: the earlier file cut into the frame, this one shows the full rampart and the
corners, so it says something about the map's edge that the crop could not. The old file was deleted,
not kept — two versions of one picture is two answers to the same question, and the fidelity critic
globs the folder.

Two things landed with it, and neither is an art change:

- **Scope declared.** The image fixes the *look*; `data/terrain.txt` and `data/map.json` fix the
  *layout*. Run 1 spent panels re-deriving this — the critic ranks layout first, so an undeclared
  illustration invites the loop to move lanes to match a picture that has no mid lane, no towers and
  a 4:3 frame. Now written down in `docs/reference/map/README.md`, with the deliberate-differences
  table.
- **Rubric C′ added.** Props, painted lighting, vignette, frame and watermark are unreachable by a
  tile painter and are filed `out-of-scope` rather than counted toward the exit. The critic is not
  told — it stays cold and keeps reporting them; the orchestrator does the filing.

**Panels graded against the old crop do not compare to panels graded against this one.** Run 1's log
below is closed. The next checkpoint opens run 2, starting from a baseline re-render of the current
map against the new reference.

### And then the target moved (designer, 2026-08-08, same day)

Hours later the designer supplied a second source — a shipped esports-manager viewer's map — and
resolved the fork that had been open since GDD §7.3: **gravitate toward that, take warmth from the
painting, copy neither.** Their own read of it, and it is the accurate one: *the blocks are bigger
and the map is simpler.*

That makes `terrain_moba_2.png` a **palette and mood** source rather than the target, and it means
run 1's direction of travel was partly wrong — it was heading toward *more* painted, and the map
wants *less*. Three consequences for run 2:

- **The target is now GDD §6.3**, eight written rules, not a picture. §6.3 outranks every image in
  `docs/reference/`. Read it before the first iteration of a session.
- **The `by-design` bucket exists** (C′) because the fidelity critic will now, correctly, push the
  render toward a painting we have decided against. Each refusal cites a §6.3 rule number.
- **The second source is never given to a critic and never committed.** It is another game's
  screenshot, git-ignored in `docs/reference/inspirations/`. What we took from it is written up in
  our own vocabulary in §6.3 and §7.3; the image is evidence, the rules are the record. A critic
  handed both pictures would grade "how close to their map is this", which is the one outcome the
  designer explicitly does not want.

Run 2's baseline re-render is therefore graded against §6.3 with `terrain_moba_2.png` supplying
palette only — a different question from the one run 1 was answering.

## Run 2 — graded against §6.3

Reference demoted to palette-and-mood; the target is the eight rules. My own read of the
`iter15` baseline against them: rules 1, 2 and 5 broadly holding; **rule 6 violated** (the road was a
cold green-grey, the same hue and value as the rampart and the pit rims); **rule 4 violated** (canopy
masses were diagonal sawtooth blobs); **rule 7 violated** (the loudest, most saturated thing on the
map was eight amber camp dot-grids in the jungle, which rule 7 says is texture).

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 15 | Baseline re-render, no change. Opens run 2. | **pass** | — | See above. |
| 16 | **Rule 6.** Road to warm sand (`7a6e58`), highest value on the map; kerb warmed to match; pit rim dropped *below* the road, since rule 1 gives the lanes the top of the value scale and run 1 had the rim as the brightest thing on the map. | **pass** | — | This is what panels 2 and 3 were actually asking for. Three panels reported the road and the arena wall as *"identical material, contradictory functions"* and I read it as geometry twice — iteration 11 moved the lanes, iteration 12 redefined the void. It was hue. One palette line closed a finding two layout changes had not. |
| 17 | **Rule 7.** Camps from amber torch-fire to a near-neutral scuffed clearing. | **pass** | — | The jungle stops being the most decorated part of the map. Warm accent is now the road's alone. |
| 18 | **Rule 4**, via a new `--chunkify=N` in `terrain_tool.gd`: snap rock masses to a 2×2 block grid, a block with ≥N rock cells becoming all rock. Applied at N=3. | **pass** | **panel 4** ↓ | The diagonal serration is gone and the canopy is countable rectangles and Ls. But N=3 was the wrong threshold — see below. |

**Why the layout pass is a transform and not a hand edit.** Symmetry is *structural*: n is even, so the
2×2 decomposition maps onto itself under the 180° rotation, and the decision is a function of the rock
count alone. A symmetric grid in gives a symmetric grid out, with no mirror pass afterwards. The block
decides but the **cell vetoes** — lane, river, pit, camp, brush, base and rampart cells vote and are
then left alone, so no anchor is built over and the lanes and pits keep the exact shapes `map.json`
reads. The first version skipped any block that was not purely rock-and-floor; that disqualified 525
of 625 blocks and moved 34 cells, because brush is sprinkled through the whole jungle.

### Panel 4 — on `iter18`

**Gate:** clean. **Fidelity:** 2 × `breaks-immersion` — *"blockers are isolated islands, not walls;
nothing narrows"* and *"nothing in the interior reads as rock or as height"* — plus 5 × `moderate`.
**Legibility:** lanes, river, both pits, both bases, the ford, 9 towers per side, and the four-quadrant
wilderness all identified. Its top confusion, for the third panel running: *"dark-green blobs vs
dark-green blobs — cover or obstruction, I would not bet either way."*

**Coordinate verification.** Pits (0.38, 0.38) / (0.63, 0.62) ✓. Bases ✓. Towers: both critics counted
9 per side; `map.json` stores 3 tiers × 3 lanes = 9 ✓. River as 2 arms + 2 pools ✓. **Fourth panel,
still zero confabulations.**

**The top finding was mine, and the gate could not see it.** *"Nothing narrows"* is true and I caused
it at iteration 18. Measured on the grid — jungle cells with ≥2 wall neighbours, a proxy for corridor
pinch:

| | jungle cells | pinched |
|---|---|---|
| iter17, before chunkify | 302 | 66 (22%) |
| iter18, threshold 3 | 410 | 34 (**8%**) |
| iter19, threshold 2 | 326 | 44 (13%) |

Threshold 3 grew the jungle floor by 36% and erased two-thirds of the chokepoints. Rule 4 and the
map's chokepoints pull against each other — a one-cell gap cannot survive a two-cell block grid — and
threshold 2 is where that trade sits. **A guard rail that passes is not a change that worked.**

**The height cue was not missing; it was too small to survive.** Both critics reported no height
information. Cropping the render and upscaling it 4× showed the lit cap, both contact lines and the
cast shadow all drawn exactly as intended — and the shadow measuring 7 px at 33% black over an already
dark floor. Worth doing before touching a knob: *"the cue is absent"* and *"the cue is inaudible"* look
identical in a critic's report and want opposite fixes.

**The crop also found what neither critic could name.** Brush was `2a3a22` on tufts of `182712`, and
rock `16261a` — one dark-green blob family carrying two opposite meanings. That is the "cover or
obstruction" ambiguity every panel has led with, and it is a rule 3 violation (two of the five kinds
were not distinguishable), not the value problem it kept being reported as.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 19 | Re-ran chunkify at threshold 2. | **pass** | — | Masses stay chunky; pinch back to 13%. |
| 20 | **Rule 5.** Shadow 0.33 → 0.52 alpha and 0.34 → 0.42 deep; dark contact line extended to the south face, so a mass is outlined on every side facing open ground rather than on two. | **pass** | — | Masses stand off the floor instead of being stickers on it. |
| 21 | **Rule 3.** Brush inverted: `4e6338`, *lighter* than the floor, second only to the road, tufts a shade off the patch. | **pass** | — | Five kinds now separate. Panel 5 enumerated all three greens and placed them correctly. |
| 22 | **Rule 7.** Pit gets a dark contact ring cast onto the ground outside it — the same cue that says "raised" everywhere else, inverted to say "sunk" — under the existing light lip. | **pass** | **panel 5** ↓ | The bowls sit into the map instead of floating on it. |
| 23 | Void `080c0a` → `0a1113`. Pure black read as a cutout; the reference's surround is a very dark desaturated teal, and palette is what that image is authoritative for. | **pass** | — | Cosmetic. |

### Panel 5 — on `iter22`

**Gate:** clean. **Fidelity:** 2 × `breaks-immersion`, 4 × `moderate`. **Legibility:** everything above
still identified, plus the third and fourth ground textures now seen as distinct types. Its verdict
moved from panel 4's *"I would not bet either way"* to *"I read the dark blobs as blocking terrain, but
they could be brush"* — the same item, one confidence step better.

**The two critics contradicted each other, and the pixels settled it.** Fidelity's top finding was
*"jungle quadrants read as solid wall — essentially no walkable-looking floor"*. Legibility, on the
same image, described *"a medium olive-green that reads as walkable grass"* with dark blobs scattered
in it. Measured, over the quadrant rectangles the legibility critic itself gave:

| Quadrant | Grid walkable | Render pixels above 0.20 luminance |
|---|---|---|
| north | 62% | 63% |
| west | 60% | 57% |
| east | 59% | 59% |
| south | 53% | 54% |

The render's value split tracks the grid's walkable split within 3 points. The finding is a misread —
**logged, not acted on.** Worth recording as a method note: the rubric's coordinate check catches
invented *positions*, and this was an invented *proportion*, which needed the same treatment. A cold
critic is a good instrument and not an oracle, and the orchestrator holds the ground truth for value
claims exactly as much as for coordinates.

**Filed `by-design`,** each against a numbered rule:

| Finding | Rule |
|---|---|
| *"Lanes are warm dirt; reference lanes are cool paved stone"* — panels 4 and 5 both | **6** — the road is the only warm hue, and the highest-value surface. This is the rule doing its job; the reference is being overruled on record. |
| *"River too saturated"* | **2** — water is the one saturated thing, and that is why it reads when tiny. |
| *"No warm torch chain tracing the lanes"* | **7** — budget goes to bases, pits and river. Also props, so `out-of-scope` twice over. |
| *"Camps have no readable marker"* | **7** — deliberate, at iteration 17. |

**Filed `out-of-scope`:** painted lighting and per-object props on the rampart, statues and braziers on
the towers, nexus glow. Unreachable by a tile painter; unchanged from run 1.

**Three findings are verified, in scope, and not mine to fix.** Each has survived multiple panels and
each fix moves numbers in `data/map.json`:

1. **The river is severed at both pits.** Four components — two 65-cell arms, two 18-cell pools. Every
   panel since panel 1 has found it, and it is real in the data, not a rendering artefact. The pits sit
   *centred on* the river's diagonal; the reference has them beside the water. Routing a channel around
   either pit means overwriting camp anchor cells or carving rock.
2. **Both bases sit 1 cell from the map edge**, so they overlap the boundary the rampart draws.
   Iteration 11 inset the *lanes* on the designer's instruction; the bases were never part of it.
3. **The outer lanes form a closed rectangular ring**, so top and bot are one racetrack. Both critics
   independently said they could only tell it was two lanes from the tower colours.

**One in-scope item stays open and is mine.** Brush versus canopy is better — three greens now
separate and verify — but *which* green blocks is not fully answerable from a still. §6.3 rule 3
anticipates this (*"a viewer learns five shapes in the first ten seconds of their first match"*), which
is a claim about watching a match and not about a frame. Recording it as a limit of the rig rather than
banking it as solved.

## Superseded — the arena margin, for the designer

The loop has taken the look as far as palette and rendering can take it. What remains at
`breaks-immersion` is one geometric fact: **the arena has no outer margin.** Closing it means pulling
the outer lanes and both base footprints inward to leave a band of jungle and rampart against the
edge — which changes lane length, jungle volume, and the tower and lane-polyline coordinates in
`data/map.json`. Those are gameplay numbers, not art, so it is the designer's call and not mine.
See `REPORTS/` for the question as posed.

## Run 2, continued — the designer's three answers

The designer answered all three blocking questions. Answers 1 and 2 were applied and committed;
answer 3 asked for a mock before anything was committed, and that mock is below.

### Iterations 24–27 — pits off the centreline, bases inside the wall

**Answer 1: nudge the pits off the river's centreline.** `tools/terrain_paint.gd --pits=D` moves one
pit and *mirrors* the offset onto the other, because 180° symmetry is a balance guard rail and
rounding each pit independently is how that quietly stops being true. Camps tangent to a bowl travel
with it — the first attempt left them behind and the pit came out notched and a quarter smaller,
because painting correctly refuses to take a camp's cells. River went from 4 components to 2.

**Answer 2: inset the bases too.** `--bases=K` translates each footprint (area preserved exactly) and
snaps each lane path end onto the nexus.

Two latent defects surfaced, neither caused by these changes:

- **Four camps were not 180° symmetric**, drifted 3.6 world units, and every guard rail passed them.
  The rails check that the *grid* is symmetric and that anchors stand on walkable ground; nothing
  checked that anchor *positions* mirror each other. `Terrain._check_anchor_symmetry` now does, and
  caught all four on its first run.
- **`VIEWER SELFTEST: FAIL — a nexus fell with no minions drawn hitting it.`** `SIEGE_REACH` is 9.0
  and bot lane's doorstep landed 9.4 world units from the nexus. Pre-existing: bot was always ~9.7
  out, and it survived only because it depended on which lane won, so moving the bases changed seed
  42's outcome and exposed it. Fixed structurally — every lane path now ends *on* the nexus, where
  minions spawn. All six doorsteps are 1.5–2.1.

### Iteration 28 — the ford, and the last cut in the river

Answers 1 and 2 left the river at 2 components. The last cut was mid crossing it, and it was a rule,
not geometry: river was deliberately *not* protected from a lane band, on the reasoning that mid
crossing the water is a ford and those cells are road with water drawn over them. The renderer draws
one surface per cell, so what that produced was road.

A ford is water interrupting a road. River now outranks lane, and the erase hands a vacated road cell
back to the water it covered up. Doing that needs two bounds: the band gives the river's **width**,
but it runs corner to corner, so bounding by band alone flooded both neutral corners and cut the outer
road with a lake — which is what the first version did. The **length** bound comes free from the banks
that survived the erase: no road can have covered water further along than the furthest water still
standing. 32 cells come back, all of them mid's crossing.

**River: 1 component, 196 cells.** Gate clean, full suite green. `.shots/iter28.png`.

Vacated road also stops becoming open floor and becomes rock. It changes nothing on this geometry —
the bands are repainted where they were — and it is what makes the mock below viable.

### The bent-lane mock — answer 3, for the designer

Two attempts. The first moved only the neutral corner vertex of each outer lane; with one vertex the
segment to the far base swung across the middle, the ring vanished and the lanes flooded the river.
The bend needs an anchor on each edge run so it stays local to the corner. Second attempt, with `bot`
generated as the exact 180° mirror of `top` so symmetry is structural:

```
top: [[15,15], [14,34], [26,76], [66,86], [85,85]]
bot: [[15,15], [34,14], [74,24], [86,66], [85,85]]
```

Gate clean, full suite green, river still 1 component. `.shots/mock-bent2.png`; side by side against
iteration 28 in `.shots/ab-ring-vs-bent.png`.

| | ring (iter28) | bent (mock) |
|---|---|---|
| top / bot lane length | 140.1 | 123.0 |
| mid lane length | 99.0 | 99.0 |
| lane cells | 602 | 484 |
| rock cells | 1190 | 1326 |
| walkable | 52% | 47% |
| river components | 1 | 1 |

**The mock was built twice for a reason worth recording.** The first version of it, on the old paint
rules, was unfair to its own idea: the outer lanes clipped each river arm and orphaned a 6-cell pool
at each end (4 components again), and 234 cells of vacated road became featureless walkable field, so
the corners read as empty green rather than as jungle. Both were artefacts of the tool, not of the
bend. A mock that loses on its own artefacts answers the wrong question, so the tool was fixed first
— that fix is iteration 28 — and the mock rebuilt on top of it.

**The bend changes the silhouette, not just the lanes.** Vacated road becomes rock; rock that is
border-connected and more than `RAMPART_DEPTH` from walkable ground is VOID; so both neutral corners
go off-map and the playable field becomes a bevelled diamond rather than a square. That is a
consequence of the bend and not a separate decision, and it is most of what the eye sees in the
comparison. Flagged to the designer as such.
