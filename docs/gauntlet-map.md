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

**Answer 3: keep the ring** (designer, 2026-08-09). Chosen from the two pictures. The mock is not
committed; its polylines are recorded above so it can be rebuilt in one command if the call is ever
revisited. GDD §6.2 now records the ring as deliberate, with the consequence spelled out: a viewer
cannot tell top from bot by shape, so anything distinguishing the two lanes has to be carried by
colour, towers or labels.

All three blocking questions are now answered, which clears the last thing standing between the loop
and its exit criteria. The geometry has moved a long way since panel 5 — both pits, both bases, every
lane path end, and the river — so the exit has to be re-tested by a fresh cold panel on `iter28`,
not inherited from panel 5.

## Run 2, continued — panels 6 and 7, iterations 29–33

### Panel 6 (on `iter28`) — coordinate check

| Claim | Verified against `data/terrain.txt` |
|---|---|
| 6 camp positions (brown-dot clusters) | **6/6 exact.** Every one lands on a `c` cell. |
| 2 pit centres | **2/2 exact** — (15,22) and (34,27). |
| Mid's road stops at ~(0.48,0.54), resumes ~(0.53,0.45) | **True.** Both cells are river; the resume cell is lane. |
| 8 brush patches | **5/8.** Two landed on solid rock and on river caustics. Self-flagged weak by the critic, which is the right call. |

Two findings arrived from both critics independently, which is the signal worth acting on:
the pits reading as impassable rock, and nothing on the map saying whether the river can be
crossed.

### Iteration 29 — the ford had gone inert

The map already had a ford cue. Iteration 28 had switched it off one commit earlier. The test
asked *lane* cells whether water lay either side, which was right while the crossing cells were
lane; making the river outrank the lane turned them into river, so the test went on asking a
question no lane cell could answer and drew nothing.

**A cue that has gone quiet is worse than one never written, because the code that draws it is
still there to read.** Nothing failed. The gate passed, the suite passed, and the only thing that
noticed was a cold reader.

Inverted: a *river* cell is a ford when road lies on both sides. Two things fell out — requiring
water ahead and behind as well, because paving alone lit both river *mouths* where the channel
runs into the ring road; and teaching the kerb that a ford counts as road, or the paving drew
itself a bank and the road still stopped dead at the water. 22 cells at the crossing, 8 at each
mouth, the mouths left alone as a true thing to say.

**Panel 7 confirmed it:** *"the water is noticeably lighter — probable that this is a shallow ford
where the diagonal road crosses"*, and mid read as one lane crossing water rather than two stubs.

### Iteration 30 — the bowls get cut in tiers

A lip is an edge, and an edge is what a boulder has. The tiers are measured off the grid, not read
from `map.json`: depth inside the pit, taken in eight directions, has **exactly one maximum in
each bowl** — (15,22) and (34,27), which is where the dragon and baron anchors already are. The
shape names its own centre, so there is no second copy of the pit positions to fall out of step.

Panel 7 moved from *"I would plausibly have called them terrain obstacles"* to *"pale grey masonry
… read as built structures"*.

### Iteration 31 — a measurement that refuted its own finding and found a real one

Panel 6 and panel 7 both reported no height cue. Measured off the render:

| | luminance |
|---|---|
| plain jungle floor | 0.283 |
| floor shadowed by rock | 0.137 |
| rock's lit north cap | 0.306 |
| rock body | 0.117 |

The cast shadow is a 52% drop — the cue is there, as it was at iteration 20 when the same report
came in. But the cap sat 0.023 above the floor, so **the top edge of every mass was the same value
as walkable ground, and the shadow below it was the same value as the rock.** The mass read a cell
too small at the top, a cell too big at the bottom, and its true boundary was drawn nowhere. Cap
raised to 0.381.

Method note, twice earned: *"the cue is absent"* and *"the cue is inaudible"* are the same
sentence in a cold report and want opposite fixes. Only measuring separates them — and this time
measuring found the actual defect, which neither critic named.

### Iteration 32 — the oldest finding in the loop, closed

Every panel this loop has run has said a cold reader cannot tell which greens block. Iterations 20
and 31 both treated it as contrast. Panel 7 said what it actually was:

> *"Mid-green grass and dark-green blobs occupy comparable areas and are both green, so the map's
> largest surface is ambiguous terrain."*

The reader could always **see** the two greens. It could not know which one meant "walk here", and
no amount of separation between two members of one family answers that. Fidelity said the same
from the other side — *"nothing anywhere reads as a rock face"* — and §6.3 rule 3 lists ground and
stone mass as two of its five shapes, which this renderer had been drawing as one material.

So the family changed. **Green is ground you can stand on; blocking mass is stone.** The grid has
one kind of wall, so the distinction is carried by material rather than by data.

First pass took the stone almost to black and traded one collision for another — the masses read
as holes and crowded the off-map void. The ladder as it stands:

| surface | luminance |
|---|---|
| void | 0.061 |
| rock | 0.184 |
| rampart | 0.243 |
| floor | 0.284 |
| pit | 0.309 |
| brush | 0.343 |
| road | 0.438 |

Monotone, and every green surface on the map is walkable.

### Iteration 33 — the bowls stop being machinery

Iteration 30 overshot. Panel 7: *"grey machinery"*, *"a cross/cog silhouette"*, *"the brightest,
highest-contrast shapes on the map"*. Not oscillation — the direction held across both panels and
only the magnitude was wrong — but worth naming as the loop's standing hazard.

The cog was a lighting mistake, not decoration. The inner tier of an octagon is a plus, and
iteration 30 lit every face of it. Everything else raised on this map catches light on its north
face and nowhere else; the step in a bowl was the only feature inventing its own sun.

### Standing `by-design` after panel 7

| Finding | Rule |
|---|---|
| *"Lanes are warm tan, not cool grey stone"* — five panels running | **6**, on record |
| *"The map reads as a sand frame around a green core"* | Consequence of the ring, chosen by the designer 2026-08-09 (GDD §6.2) |
| *"Bases are flat team-coloured rectangles"* | Team identity is what a manager's map is for; the reference is a player's map |
| *"Towers are UI squares, not stone platforms"* | Out of scope — no prop layer in M6-T1 |
| *"No torch pools, no glows"* | **7**, and out of scope twice over |
| *"What the grey structures actually **are**"* | Genuinely unanswerable by terrain. Needs an icon layer. |

## Run 2, continued — panels 8 and 9, iterations 34–37

### Iteration 34 — a ratio is not a contrast

Iteration 32 closed the loop's oldest finding and opened the next one. Panel 8 led with it from
both critics independently: *"wall masses read as black holes … like cut-out voids"*, and, cold on
the same image from the other critic, masses touching the edge *"look like the frame intruding
rather than in-play terrain"*.

Iteration 32 had checked the ladder and found it monotone — void 0.061, rock 0.184, floor 0.284.
Three times the void's luminance, a full step under the floor, and **still two blacks to look at**.
Down at the bottom of the range a 3× ratio is not a contrast, and a ladder can be monotone in
arithmetic while two of its rungs are the same rung to the eye. Method note worth keeping next to
the one about audible cues: *measuring is how you check a claim, not how you check a design.*

Stone to 0.223, rampart to 0.266.

### Iteration 35 — the same sun, the other way round

Panel 8, both critics: *"raised bright pads"*, *"raised plazas or podiums, not sunken pits"*.

Iteration 33 had fixed the pits' shape by putting them under the map's lighting rule — and under
the rule for the wrong kind of object. A raised thing catches light on its north face. A hollow is
the same sun and the opposite surface: the wall descending at the north edge faces away from the
light and is shaded, the far wall at the south edge faces into it and is lit. **A hole is dark at
the top and light at the bottom, the exact inverse of the rock convention.**

### Iteration 36 — one team's ground was ambiguous and the other's was not

*"Close enough in hue to the blue base wash that I briefly read it as a second blue territory."*
Blue was a teal-leaning slate and so is the river; red was unmistakable. A one-sided failure is
worse than a symmetric one on a map that is read through its symmetry. Blue leans indigo now.

### Panel 9 — coordinate check, and what it exposed

| Claim | Verified |
|---|---|
| 2 pit centres | **2/2 exact** |
| 3 chokepoints | all 3 land on lane or river cells as described |
| 7 "textured green / possible brush" patches | **4 are camps**, 1 brush, 1 pit, 1 plain floor |

The critic also said outright: *"any camp, neutral spawn, ward spot or point of interest inside the
green areas — I found none at all."* Measured, **camp 0.286 against jungle floor 0.283** — the same
surface.

### Iteration 37 — camps get a step, and no props

Iteration 17 quietened the camps on rule 7's authority and was right to; run 1 had torch fire on
all eight and the jungle was the most decorated part of the map. But rule 7 withholds *ornament*
from the jungle, and iteration 17 read it as withholding existence. Rule 1 is the other half: a
thing the viewer must find differs in value from what surrounds it.

Camp to 0.24 — trodden bare ground, **down** where brush goes up. Two walkable greens that depart
from the floor in opposite directions are far easier to hold apart than two that depart by amount.
Same lesson as iteration 32, one rung quieter.

## Oscillation: the walls, and the two critics who disagree about them

Logged as a **trade-off, not a bug**, per this loop's own rule.

| Position | Who | Says |
|---|---|---|
| Walls are too dark; rock should be *lighter* than the ground it stands in | fidelity critic, panels 8 **and** 9 | *"reads as pits punched through the ground"*; the reference has pale boulders on dark grass |
| Walls read correctly and instantly | legibility critic, panel 9 | *"charcoal-grey slabs with black outlines that read unmistakably as walls or rock … my eye reads them as 'you cannot go here' immediately"* — filed under **certain, zero effort** |

The finding came back after iteration 34 moved rock from 0.184 to 0.223, so the loop stops swinging
here. Three things bear on the designer's call:

1. **§6.3 wins over the reference on record.** The palette block's stated ordering is *lane
   lightest, floor mid, rock dark, void darkest*, and rule 1 is "dark by default". The reference
   inverts it. `docs/reference/map/README.md` says §6.3 wins where they disagree.
2. **Part of the finding is measurably false.** *"No lighter cap, no cast shadow"* — third panel to
   say it. Cap 0.380 against a rock body of 0.222; cast shadow a 52% drop, 0.283 → 0.137. Both
   present, both strong, on the render being judged.
3. **The two critics are answering different questions.** Fidelity asks "does this look like the
   picture"; legibility asks "can a cold viewer read it". On this item they now give opposite
   answers, which is the definition of a design decision.

## Where run 2 ends

Every remaining in-scope finding is `by-design` against a numbered rule, out of reach of a tile
renderer, or a question for the designer. The full disposition is in
`REPORTS/M6-T1-gauntlet-run3.md`.

## Exit — gauntlet loop 1 closed, designer sign-off 2026-08-09

Both open questions were put to the designer with the final render beside the reference
(`.shots/final-vs-reference.png`) and both came back **leave it**:

- **The road keeps its share of the map.** Rule 6 plus the ring make tan the dominant field; the
  lever was lane width, which is gameplay space. Recorded in GDD §6.3 rule 6.
- **Rule 1 stands, and the walls stay dark.** The two critics gave opposite answers on the same
  image, and the decision went to the one measuring whether a cold viewer can read the map.
  Recorded in GDD §6.3 rule 1 and in the reference README's deliberate-differences table.

**Exit criteria at close:**

| | |
|---|---|
| Gate: zero problems | ✅ |
| Overlay agrees with `map.json` | ✅ |
| Legibility: every real feature identified, nothing invented | ✅ |
| No in-scope fidelity finding above `cosmetic` | ✅ by disposition — every remaining finding is `by-design` against a numbered rule or out of reach of a tile renderer, and both contested ones are now designer decisions on record |
| **Designer sign-off — the real exit** | ✅ 2026-08-09 |

**Nine panels, zero confabulated coordinates.** Every position a legibility critic ever claimed
verified against the grid. The two failures were of a different kind and both worth remembering: an
invented *proportion* at panel 5 (*"essentially no walkable floor"*, measured within 3 points of the
grid's own walkable fraction), and a *category merge* at panel 9, where four camps were offered as
possible brush. Neither is a coordinate error, and the rubric's coordinate check catches neither —
value and category claims need the same treatment positions get.

### What this loop is for, in one line each

- **A passing gate is not a working change.** Chunkify at threshold 3 passed every rail and erased
  two-thirds of the jungle's chokepoints.
- **A cue that goes quiet is worse than one never written.** The ford marker was switched off by a
  commit that changed a cell's kind, and every automated check passed for two panels.
- **A ratio is not a contrast.** Rock at three times the void's luminance was still two blacks.
- **"Absent" and "inaudible" are the same sentence in a cold report,** want opposite fixes, and only
  measuring separates them.
- **Two critics disagreeing is a design decision.** It happened twice, and both times the answer
  was the designer's, not another iteration.

## Run 4 — the reference changed under a closed loop

Loop 1 exited on 2026-08-09 with designer sign-off. Hours later the designer replaced the reference:
`terrain_moba_2.png` deleted, **`terrain_moba_3.png`** committed. `docs/reference/map/README.md` was
updated in the same commit and already records what the new image is authoritative for, the
deliberate differences, the designer's own hand-edit artefacts, and **two open reversals** left
undecided.

A sign-off is against a reference. When the reference changes, the sign-off does not transfer, so
the exit has to be re-tested by a cold panel rather than inherited — the same rule applied at
panel 5 → panel 6 when the geometry moved. That is what iterations 38–39 do.

**The tree also carried uncommitted sim work** — tower tiers 3 → 2 per lane, a designer decision of
the same day — so the render grades 6 structures a side, not 9, and this is the first panel to see
them. Full suite green with it in.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 38 | Baseline re-render, no change. Opens run 4 against the new reference. | **pass** | **panel 10** ↓ | The new reference inverts the map's two largest surfaces. Ours is a tan road field with grey stone masses; it is a green field with narrow grey stone roads and dark canopy as the blocker. |

### Panel 10 — on `iter38`

**Gate:** clean. **Fidelity:** 4 × `breaks-immersion` (jungle is bare ground, not forest; rock value
inverted vs the reference's pale masonry; rock occupies most of the jungle interior; bases and
turrets are flat markers), 5 × `moderate`. **Legibility:** the strongest cold read the loop has had
— lanes, river, ford, both pits, both bases, all four jungle wedges, the 180° symmetry and *which
corner is which team* all `certain`, and it narrated the map unprompted.

**Coordinate verification — tenth panel, still zero confabulated positions.**

| Claim | Ground truth | |
|---|---|---|
| 2 pit centres | both land on `o`; exact | ✓ |
| 6 camp clusters | **6/6 land on `c`**, all within 0.015 | ✓ |
| 8 camps exist in `map.json` | the 2 missed are the ones tangent to a pit bowl — omission, not invention | — |
| ford at (0.53, 0.49) | `~` with `=` adjacent — the ford exactly | ✓ |
| 6 brush patches | **5/6 land on `,`**; one lands on `#` with brush in its 3×3 | ~ |
| 9 chokepoints | mid-road pinches all land on `=`/`#`; the four "pit entrances" land *inside* the bowls | ~ |

The y axis flips between world and image (`image_y = 1 − world_y/100`), which is worth writing down:
checked naively, every pit and camp claim looks wrong by exactly the reflection.

**Two category merges, no positional errors** — the same failure mode as panel 9, and the rubric's
coordinate check still does not catch it. A cold critic's *positions* have been trustworthy for ten
panels; its *categories* and *proportions* have not, and both need the orchestrator's measurement.

**The census settles the biggest finding, and it is not a palette question.**

| surface | cells | share |
|---|---|---|
| rock | 1190 | **48%** |
| road | 602 | 24% |
| river | 196 | 8% |
| green floor + brush | 248 | **10%** |
| pit / camp / bases | 264 | 10% |

*"Rock occupies most of the jungle interior"* is measurably true: the map's largest surface by a
wide margin is blocking mass, and walkable green is a tenth of it. The reference is close to the
inverse. **Lane width and rock volume are gameplay numbers**, so this is the designer's, not mine —
it is put to them below with a picture.

### Iteration 39 — brush gets a silhouette

The one `breaks-immersion`-adjacent finding both critics named that is independent of every open
question. Fidelity: brush should be *"unmistakable at a glance"*. Legibility, cold and much blunter:
*"I cannot confidently identify any [bushes] … one shade off from ordinary grass, no border, no
shadow, no silhouette"*, and *"I would have mistaken the camps for bushes, or vice versa"*.

Brush was the only feature on this map drawn as **interior texture with no edge**. The lane has its
kerb, a rock its contact line and lit cap, a pit its lip and shadow ring — every feature a cold
reader can find is a feature with a boundary.

The direction of the edge is the whole decision. A *dark* rim is this renderer's way of saying
"raised and solid", so putting one around brush argues that it blocks — the exact ambiguity runs 2
and 3 spent four iterations closing. So the rim goes *lighter* than the patch: blade tips where the
tall grass ends, the same inversion the pits used at iteration 35 to say "sunk" with the cue that
everywhere else says "raised". Kept under the road, so rule 1 keeps peak brightness on the lanes.

| | iter38 | iter39 |
|---|---|---|
| brush (whole-cell mean) | 0.333 | **0.352** |
| floor | 0.266 | 0.266 |
| road | 0.412 | 0.412 |

Ladder still monotone, road still brightest, gate clean, full suite green.

### A measurement trap worth the entry: I measured the mark, not the surface

Sampling cell centres, camp came out at 0.286 against a floor of 0.284 — *identical*, which is
verbatim what panel 9 reported and what iteration 37 was supposed to have fixed. It looked exactly
like a cue that had gone quiet, which this loop has now seen three times.

It had not. A camp draws `C_CAMP_MARK` as a disc of radius 0.28 cells **at the cell centre**, so the
sampler was reading the mark and never the ground. Whole-cell means put camp at 0.245 against floor
0.266 — iteration 37 landed and is intact.

Adds a clause to the loop's own method note. *"Absent"* and *"inaudible"* are the same sentence in a
cold report and want opposite fixes; **and a measurement can be neither, if it is aimed at the wrong
pixel.** Sample the surface, not the ornament drawn on top of it.

### What panel 10 was refused, and why

| Finding | Filed | Cited |
|---|---|---|
| *"Rock value inverted — reference has pale masonry"* | `by-design` | **Rule 1**, and the designer's 2026-08-09 decision on this exact trade-off. The new reference restates the fidelity critic's side; the legibility critic, cold on the same image, again put walkable-vs-solid under `certain` — *"the contrast is strong and unambiguous everywhere"*. Same two answers, already decided. **Logged, not swung.** |
| *"Lane surface is sand, not paved stone"* | `by-design` | **Rule 6** — sixth panel running. Coupled to open question A below. |
| *"Bases and turrets are flat colour markers"* | `by-design` + `out-of-scope` | Team identity is what a manager's map is for; props need a sprite layer, not M6-T1. |
| *"Pits should sit at the river's ends and look different from each other"* | `out-of-scope` | The reference **is not the layout** (README); pit positions are `map.json` and mirror by construction. Distinguishing dragon from baron is an icon layer. |
| *"River loses continuity at the centre"* | misread, logged | It is the ford, and the *other* critic read it correctly as one — *"noticeably lighter … a shallow ford where the diagonal road crosses"*. Same treatment as panel 5's invented proportion. |
| *"Elevation not conveyed — flat silhouettes"* | measured, refused | Cap 0.380 vs body 0.239; cast shadow 0.145 against plain floor 0.296, a **51% drop**. The cue says *raised*; what it cannot say is *cliff vs wall vs high ground*, which is the icon-layer item already standing since panel 7. |
| *"Outer fringe looks like traversable forest"* | logged, not acted on | Real, and the critic self-resolved it (*"its position outside the tan ring settles it"*). The rampart's value sits in the middle of a three-panel oscillation between wall, road and rock; not swinging there on a first-impression finding. |

### Open — three questions for the designer, with a picture

The README already carried two open reversals. Panel 10 raises a third and makes the first
measurable, and all three are one question: **is the new reference a re-direction of the look, or
just a palette and mood source like the last one?**

- **A. Green as the field, stone roads through it.** Measured above: rock 48%, road 24%, green 10%.
  Getting to the reference's ratio means narrowing lanes and converting rock to floor — lane length,
  jungle volume and chokepoint count are all gameplay, so this is not reachable by any knob.
- **B. Trees as the blocking terrain.** Iteration 32 made blocking mass *stone* precisely so it would
  stop being green, which closed the oldest finding in the log. The new reference blocks with canopy.
- **C. Cool paved lanes instead of warm tan.** Rule 6 on record, six panels; the new reference agrees
  with the critic rather than the rule.

**Mocked, so the choice is two pictures and not a paragraph.** `.shots/ab-shipped-vs-green.png` —
left `iter39` as shipped, right a palette-only mock (canopy blocks, grass is the field, roads cool
grey). Reverted immediately; `tools/gauntlet.sh mock-green` rebuilds it from the recipe in this log.

The mock is a palette swap and **not a converged design**, and it visibly costs two things the loop
already paid for once: with the road grey, the ring road and the rampart become one material again
(panel 2's finding, restored), and the pits stop being distinguishable from the roads. If the answer
is "re-direct", those are solvable — but it is several iterations of run 4, not a one-line change.

**Until the designer answers, the shipped look stands and none of this blocks.** Iteration 39 is
independent of all three and is committed.

### The designer's answer, 2026-08-09: *"look only — canopy blocks, cool roads, keep the layout"*

B and C adopted, A declined. Translated into GDD §6.3 before any code: **rule 6 reversed on hue**
(lanes are cool paved stone; what survives is that they hold the top of the value scale), **rule 6′
added** (blocking mass is canopy; stone is what people built), **rule 3 re-cut** along the same line
(the five kinds now split by *who made it* — canopy is grown and blocks, stone is built and you walk
on it), and **rule 5 promoted to load-bearing**, because with green on both sides of the
walkable/blocking line, shadow and value are the only things carrying it.

Rule 6′ was written with its own falsification clause, and this is why: it reverses iteration 32,
which closed the oldest finding in this log. *"The loop is expected to prove with a cold reader that
it holds. If it does not, the honest options are to go back to stone or to add a sixth shape, not to
keep re-tinting two greens."*

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 40 | **Rule 6 reversed.** Lanes to cool paved stone at 0.51, kerb and ford cooled to match. The value is up from the tan's 0.44 because hue used to separate the road from the pit rims (0.43) and base walls (0.43); with all three grey, they would be one value. | **pass** | — | Lanes unmistakable and clearly the top of the scale. |
| 41 | **Rule 6′.** Blocking mass from grey stone to canopy. Canopy interior 0.135 against floor 0.283 — *a wider value gap than grey-on-green ever had*. | **pass** | **panel 11** ↓ | Numerically stronger, and it failed. |

### Panel 11 — on `iter41`, and the cleanest A/B this loop has run

One variable changed between panels 10 and 11. The same cold reader, on the same geometry:

| | verdict on walkable vs blocking |
|---|---|
| **Panel 10** — grey stone blockers | *"the contrast is strong and unambiguous everywhere"* — **certain** |
| **Panel 11** — canopy blockers | *"Nothing distinguishes walkable jungle from wall … I genuinely cannot tell which"* — **invisible** |

It also downgraded everything downstream: the jungle wedges went to *"guessing that they are
traversable"*, and chokepoints to *"probable, **and only if** the dark green is solid"*. The fidelity
critic, independently: *"terrain is exactly two categories — green block or grey floor … nothing
reads as raised."*

**Coordinate verification — brush 8/8, camps 6/6, chokepoints all on lane or river cells.** Panel 10
had brush at 5/6 with the critic calling it *"cannot confidently identify any"*; panel 11 volunteers
eight positions and every one lands on a `,`. **Iteration 39 is confirmed by a cold reader**, which
is the one unambiguous win of the session.

Its *"small rectangles outside the play field, I have no idea what they are"* land on **real brush
cells stranded in the boundary margin**. Iteration 39 gave brush a silhouette and thereby made a
pre-existing layout oddity visible for the first time. Logged; not chased.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 42 | Canopy gets **crowns** — round foliage with shade under it, clipped inside the cell so rule 4 keeps the mass's silhouette on the grid. The hypothesis: the problem is not contrast but *material*, since a viewer knows what stone does and not what a green rectangle does. | **pass** | **panel 12** ↓ | Reads convincingly as forest, and made the legibility worse. |

### Panel 12 — on `iter42`: a fidelity win that cost legibility

Still **invisible**, verbatim: *"Which green is walkable. Nothing distinguishes 'trees you walk
through' from 'trees that are wall.' This is the single biggest gap."* And a new regression in
`by-design` territory: *"the out-of-bounds vegetation frame and the in-bounds forest are the same
family of dark green — without the thin white boundary line, I could not tell where the map stops."*
Panel 10 had the boundary as unambiguous.

**The failure named its own cause.** Once the masses read as forest, the *ground* was read as forest
too. So the diagnosis is not tone and not texture — **rule 6′ and layout question A are coupled**. In
the reference, green is the field and tree clumps are objects standing on it, so *green = ground* is
what a viewer assumes. Here the ratio is inverted — 48% canopy against 10% walkable floor — so
*green = blocked* is what a viewer assumes, and the floor becomes the exception rather than the rule.
Keeping the layout while taking the reference's blockers means **the ground cannot also be green.**

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 43 | **Floor to earth** (`564a37`). The split goes back to material, which is what grey was quietly providing all along: vegetation is green, earth is walkable. Brush stays the one light green — walkable but vegetation, which is exactly what brush is. | **pass** | **panel 13** ↓ | The decisive question moves for the first time. |

### Panel 13 — on `iter43`

Unprompted, in its opening description: *"the canopy reads as blocked or at least not-road, while
grey, brown and the small light-green squares read as traversable."* Three panels of *"I cannot tell
which"* end there.

What remains under `invisible` is a **narrower** question — *"whether the dark canopy is impassable
wall or slow/vision-blocking ground"* — i.e. canopy versus brush, not walkable versus blocking. That
is a game-rules distinction a terrain renderer arguably cannot answer without a legend, and it is the
same item §6.3 rule 3 has always known is settled by watching a match rather than a frame.

It introduced one new finding, and it is real: *"three greens that do similar-looking work — dark
canopy, mid olive blobs, bright speckled squares … the single biggest legibility problem."* The
olive blobs are the camps, and it found only four of six and could not name them. On an earth floor
the camps are no longer trodden ground against grass; they are a third green against a brown field.
**Open, and mine** — the camps need re-siting in the ladder, one iteration, no designer input.

### Where run 4 stands — not mine to close

| | walkable vs blocking, by cold read |
|---|---|
| iter38/39 — stone blockers, green floor, tan roads | **certain** |
| iter41 — canopy blockers, green floor, grey roads | **invisible** |
| iter42 — + crown texture | **invisible** |
| iter43 — + earth floor | **canopy reads as not-road**; residual canopy-vs-brush ambiguity |

The designer's direction is **recoverable, but not on its own terms**: it costs the green floor. What
they asked for was a green field with canopy blockers; what survives a cold reader is a forest with
earth paths and stone roads. That is a third look, close to the reference's *jungle interior* but not
to its overall figure-ground, and it is a design choice rather than a bug — so it goes back to them
with three pictures: `.shots/ab-three-options.png`.

Per this loop's oscillation rule, **the swinging stops here.** Two attempts and one recovery is
enough to characterise the trade; a fourth would be self-grading with extra steps.

### The designer takes question A, 2026-08-09: *"green becomes the field"*

Chosen from the three pictures, explicitly as the option that gets the reference's figure-ground.
This is layout, so it moves gameplay numbers, and `tools/terrain_paint.gd` grew the levers for it:
`--lane-half=W` (lane width was a constant; it is now the argument that decides whether the map is a
road with green in it or a green field with roads through it), `--vacated=rock|floor` (iteration 28
chose rock, which is right when re-rasterising in place and exactly wrong when narrowing), and
`--erode=N`. `Terrain.invalidate_wall_classes()` came with it — the wall-class cache is documented as
never needing invalidation because a loaded Terrain is immutable, which is true of every reader in
the game and false of the editing tools that mutate `cells` and keep asking questions.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 44 | Lanes narrowed 4.4 → 3.0 half-width, vacated road to floor; canopy eroded one pass; floor back to grass green. Canopy 48%→40%, road 24%→20%, **green 10%→22%**. | **pass** | **panel 14** ↓ | Figure-ground inverted as intended, and the jungle was destroyed doing it. |

### Panel 14 — on `iter44`: the ratio moved and the map got worse

Both critics, independently. Legibility: *"**Any wall, cliff or impassable terrain inside the play
area. There is none I can see.** The playfield reads as one continuous open surface with decorative
variation."* It read the canopy clumps as **cover**, not obstruction. Fidelity: *"jungle quadrants
are open green fields with scattered stamps."*

**Erosion was the wrong instrument, and measuring the masses said why.** A one-cell rim off every
mass does not shrink a jungle proportionally — it *deletes* every mass two cells wide or thinner and
halves the rest. Chunkify afterwards made it worse, taking pinch from 50 cells to 24.

**And the measurement that should have come first exposed a bad number I had given the designer.**
Decomposing the canopy into connected masses:

| | cells |
|---|---|
| border wall (one connected blob, the arena's frame) | **886** |
| interior jungle masses (12 of them, largest 48) | **304** |

The map's headline *"rock is 48%"* — the figure that framed question A in the first place — is 35%
frame and **12% actual in-play blocking terrain**. Green never had to beat 48% of anything. Eroding
186 cells took roughly a third of the real jungle, which is why one pass was catastrophic where the
census made it look modest.

**Method note, and it is the sharpest one this loop has produced.** *A census counts cells; it does
not know what a shape is.* Every number I reported about this map for two sessions — 48% rock, the
green/road ratio, the whole framing of question A — was computed over cells with no notion of
connectivity, and it hid an 886-cell object in plain sight. The pinch metric was doing the same
thing from the other side: it went **up** (28 → 50) on the change that erased the jungle, because
more walkable area with fewer walls still produces more wall-adjacent cells.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 45 | Erosion and chunkify reverted; **lane narrowing kept**. Interior masses back to 12, largest 48; pinch 54; green 14%; grass now exists outside the lane ring, which panel 11's fidelity critic had asked for. | **pass** | **panel 15** ↓ | The layout half of question A, in the form that survives. |

### Panel 15 — on `iter45`, and where run 4 actually stands

Suite green, gate clean, and the same sentence for the fourth panel running: *"Whether the dark-green
tree masses are walkable jungle or impassable wall. **This is the single biggest gap.**"*

**Rule 6′ has now been tested four ways and failed three of them.**

| Blockers | Floor | Layout | Cold read on walkable vs blocking |
|---|---|---|---|
| grey stone | green | original | **certain** — *"strong and unambiguous everywhere"* |
| canopy | green | original | **invisible** |
| canopy + crown texture | green | original | **invisible** |
| canopy + crowns | **earth** | original | **passes** — *"canopy reads as blocked, grey and brown read as traversable"* |
| canopy + crowns | green | **narrowed lanes** | **invisible** |

The ratio was not the variable. The only thing that has ever separated walkable from blocking on this
map is **material** — stone against green, or green against earth. Two greens have failed every time,
at every ratio, with and without texture, which is precisely what §6.3 rule 6′ was written to find
out. Its falsification clause names the honest options: go back to stone, or take the sixth shape.
Re-tinting two greens a fifth time is the one thing it rules out, so the loop stops and the choice
goes back to the designer.

**Kept regardless of that choice**, because none of it depends on the answer: the narrowed lanes and
the grass outside the ring (iteration 45), the brush silhouette (39, confirmed 8/8 by a cold reader),
the cool stone roads (40), and the crown texture (42, which is a fidelity gain in every variant).

**Still open and mine:** the camps. Panel 13 found four of six and could not name them; panel 15 filed
them *"guessing"*. They have been re-sited twice under two different floors and want one iteration
once the floor stops moving.

### The designer takes the sixth shape, 2026-08-09

Of the two options rule 6′ left open, the more expensive one. **The mass stays trees; its boundary
becomes stone.** Rule 3's vocabulary goes from five kinds to six, which that rule warns costs more
than it looks — accepted on record.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 46 | Stone escarpment drawn on every canopy face that meets walkable ground: pale masonry, lit on the north like everything else raised on this map, with the old dark contact line demoted to the seam *under* it. Drawn only at the boundary, so it is a silhouette and costs nothing in a mass's interior. | **pass** | **panel 16** ↓ | The best result the canopy direction has had. |

### Panel 16 — on `iter46`

Suite green, gate clean. **The sixth shape works, and does not finish the job.**

The critic's own opening description — written before it is asked anything — now reads *"large
dark-green blobs with visible round canopy texture and hard dark outlines that **read as tree masses
/ blocked terrain**"*, and under hiding places, *"I read those as blocking walls, not hiding spots,
because of their hard outline and their role in separating lanes from jungle"*, filed `probable`.
Three panels running had this at **invisible**. It still declines to call it `certain`.

**Both critics then converged on the same next cause, from opposite ends.** Fidelity: *"the
reference's interior is mostly canopy with paths cut through it, the render's is mostly open ground
with forest strips laid on top — jungle coverage is the single most valuable difference to close."*
Legibility could see the masses and would not commit to what they do. Measured, both are describing
one fact: **interior jungle is 304 cells in 12 masses**, against a much larger walkable interior.
There is too little jungle for jungle to be the obvious reading — and since canopy is itself green,
adding it serves the green-field direction rather than competing with it.

### Iteration 47 — `--dilate`, reverted, and the second half of a lesson

Wrote the inverse of `--erode` and it failed twice over in one pass:

- **The gate caught it.** *"2 of 1164 walkable cells are cut off from the blue — a wall is sealing a
  pocket of the map."* Growing every mass by a cell closed a corridor somewhere.
- **It ate the thing it was serving.** Walkable green 356 → 210 cells, 14% → 8% — the green field the
  designer had just chosen, spent in a single pass.

Reverted; gate clean again.

**Global morphology is the wrong instrument on this grid, in both directions.** Erode and dilate are
each a one-cell change applied everywhere at once, and the interior masses are 34–71 cells — so a
single pass is a third of the jungle either way. There is no setting between "no change" and "too
much", because the operator has no notion of the shape it is editing. Erode deleted every mass two
cells wide; dilate sealed a corridor and drank the field. What the remaining finding actually wants
is a **shape-aware** edit — grow *these* masses along *this* axis, leave that corridor alone — which
is either a real tool or a hand edit to `data/terrain.txt`, and is a decision about the map's rooms
rather than a knob.

**Kept from run 4, all gate-clean and suite-green:** narrowed lanes and grass outside the ring (45),
the stone escarpment (46), the brush silhouette (39, 8/8 on a cold read), cool stone roads (40),
canopy crowns (42). **Open:** interior jungle density, and the camps.

## Run 5, 2026-08-09 — the designer takes the jungle question, and the census answers a different one

The designer's call on the panel-16 finding: **thicken the quadrants, keep the corridors.** Grow the
interior masses so the jungle reads as forest with paths cut through it, but leave every corridor and
lane approach at its current width.

That instruction is what exposed the next measurement error, and it is the same class as the 886-cell
frame hiding inside "rock is 48%".

### Iteration 48 attempt 1 — shape-aware growth, and why it moved six cells

Iteration 47 had established that global morphology is the wrong instrument in both directions, so the
growth was written shape-aware: grow a mass into a neighbouring cell only where the passage it eats
into stays at least three cells wide, apply every edit together with its 180° partner so symmetry holds
by construction, and refuse the whole pass if any walkable cell is cut off.

It found **six cells**. Decomposing the green said why:

| | |
|---|---|
| green (open + brush) | 356 cells, in **54 connected regions** |
| largest region | 45 cells, max clearance **3** |
| regions of 1 cell | 34 of them |

**There is no open field to convert.** The green is already 54 thin seams, none of them wider than five
cells. "Thicken the quadrants" had no material to work with, and the only way to add 200 cells of
canopy would have been to delete the green field the designer chose nine days ago — which is the option
they explicitly declined.

### What the interior is actually made of

Normalised over the play area — the frame and the void excluded, because the reference is a crop and
has neither:

| | render (iter47) | reference |
|---|---|---|
| green | 43.9% | 44.1% |
| road | 30.6% | ~15% |
| road : green | 1.28 | 0.32 |

**The green was never short. The road is double.** Both critics at panel 16 asked for more jungle from
opposite ends, and both were describing this ratio from the wrong side of it. The interior does not
want more canopy; it wants less pavement.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 48–49 | **The road gets a verge** (§6.3 rule 6″): paving held back `LANE_VERGE` from the edge of its own lane cells, the vacated ground drawn as the field it crosses. Tried at 0.35, kept at 0.45. Every lane cell stays walkable — corridor widths, `map.json`, the gate and the sim are untouched, and the mid lane's stair steps chamfer for free. road:green 1.28 → **0.68**, green 33.8% → **45.8%** against the reference's 47.2%. | **pass** | — | The map stops being a pavement ring with jungle in the gaps. |
| 50 | **Camps become clearings.** The patch gets a boundary — the instrument that fixed brush at iteration 39 — plus a size hierarchy in the marks, so a camp reads as a group with something large in it rather than as one dot per cell repeated. | **pass** | **panel 17** ↓ | Camps stop being texture. |

### Panel 17 — on `iter50`

Gate clean. Both critics cold, image path only.

**Camps: closed.** Panels 13 and 15 had them at "four of six found, none named, guessing". The
legibility critic now locates **six of six** by coordinate — (0.545,0.195), (0.335,0.365), (0.20,0.555),
(0.455,0.815), (0.80,0.455), (0.655,0.635), every one of which verifies against `data/terrain.txt` —
and reads them as *"a different, smaller kind of site — likely camps rather than arenas"*, `probable`
as a feature class. The edge did for camps exactly what it did for brush.

**The verge is confirmed by the fidelity critic, in the one line that matters:** *"the lane-versus-grass
value contrast is close to the reference's, so the lane ring is legible at a squint"* — the road got
narrower and lost nothing.

**Two verified findings, both acted on.**

1. **The ford, and it is a regression the verge caused.** Legibility: *"between roughly (0.44,0.55) and
   (0.56,0.45) the grey is overlaid by the widened river — I cannot tell whether mid is continuous
   through the centre or is genuinely severed there."* Fidelity, independently: *"the grey path simply
   stops at the waterline."* The grid says mid does cross there, as a ford. The cue was firing; it was
   drawn to the **full cell**, so once the road either side narrowed to 55% of a cell the crossing came
   out *wider* than the road feeding it, and a pale wash replaced a line continuing. Fixed by giving
   the ford the road's drawn width. This is now the general clause on rule 6″: anything that continues
   a road across something else carries the road's *drawn* width, never its cell width.
2. **Brush marooned outside the lane ring.** *"Two speckled patches outside the ring at (0.72,0.07) and
   (0.265,0.93) look like brush stranded in out-of-bounds; I would have mistaken them for a hidden path
   off the map."* Verified exactly: brush at row 3 cols 35–36 and its 180° partner at row 46 cols
   13–14, both in the jungle pocket behind the lane. Real, and a confusing place to put a hiding spot.
   Converted to open ground (4 cells, symmetric, gate clean). The pocket stays walkable.

| # | Change | Gate | Panel | Read |
|---|---|---|---|---|
| 51 | Ford drawn at the road's width; the four marooned brush cells returned to open ground. | **pass** | — | Mid reads as continuous across the centre. |

### Where run 5 stops, and what it is stopping on

The stopping rule is **not** met, and the two reasons are both worth the designer's time rather than
another self-graded iteration.

- **The bases are the fidelity critic's top finding, unprompted and new:** *"both bases read as flat
  tinted rectangles, not built ground — no floor material, no perimeter wall, no structure silhouette
  ... the one place a viewer would not believe this is the same map"*, filed `breaks-immersion`. Rule 7
  already spends the ornament budget on the bases, so this is in-rule and mine to do; it is a genuinely
  new feature (paved floor) rather than a knob, which is why it did not get folded into this run.
- **Jungle density is still open, and the census has changed what the question means.** It can no
  longer be read as "grow the masses" — there is nothing to grow into. It is now a question about the
  map's rooms: the open pockets the fidelity critic named, e.g. cols 29–33 rows 10–14 and its mirror,
  are the only places canopy could go, and putting it there is a hand edit to `data/terrain.txt` that
  changes where bodies can walk.

**Still standing, unchanged by this run:** whether the canopy reads as blocking. The legibility critic
described the masses as *"dark-green lumpy blobs with raised pale outlines that read as solid tree
walls"* and listed them under what is not walkable — then filed the inference itself as `guessing` in
its verdict. That is panel 16's position holding, not improving: the escarpment is carrying the read,
and it is carrying it on inference rather than on certainty.

### The designer closes run 5, 2026-08-09

Both open calls answered, and together they close gauntlet loop 1.

- **The bases: hold for M6-D.** Building a plaza under placeholder squares fixes half a picture, so
  the base floor ships with the pixel sprites that stand on it. The fidelity critic's
  `breaks-immersion` finding is therefore **accepted and deferred, not fixed** — it is the one item
  the loop is exiting with open, and it is open by decision.
- **Jungle density: dropped.** Green is at the reference's share; the picture no longer needs it, and
  the only remaining way to buy it costs walkable ground. The question that ran from panel 14 to
  panel 17 is closed by measurement rather than by an edit.

**The loop stops here.** It does not pass its own stopping rule — see the two clauses above and the
canopy read still filed as inference — and it is exiting anyway, deliberately, because both surviving
findings are now scheduled rather than unsolved. That is what the rule is for: it made the loop say
out loud what it was leaving behind instead of declaring itself done.

**Final state:** `.shots/iter51.png`. 51 iterations, 17 cold panels, gate clean.
