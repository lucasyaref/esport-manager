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

**D — Legibility, cold.** Judged by `map-legibility-critic`, which never sees the reference. Can
someone who has never seen this game find the lanes, the river, the pits, the bases? Every claim it
makes comes with coordinates, which the orchestrator verifies against `data/terrain.txt` — a confident
claim about something that is not there means the map is suggestive rather than legible, and is itself
a finding.

**E — Agreement with the sim.** `--overlay` draws `data/map.json`'s own geometry on the render. The
lanes drawn must be the lanes the minions walk. Where picture and data disagree, one of them is wrong
and it is not always the picture.

## Exit criteria

A single checkpoint producing all of: guard rails clean; no fidelity finding above `cosmetic`; every
real feature identified by the legibility critic with verifying coordinates and nothing claimed that
is not there; overlay agreeing with `map.json`.

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

## Open — the arena margin, for the designer

The loop has taken the look as far as palette and rendering can take it. What remains at
`breaks-immersion` is one geometric fact: **the arena has no outer margin.** Closing it means pulling
the outer lanes and both base footprints inward to leave a band of jungle and rampart against the
edge — which changes lane length, jungle volume, and the tower and lane-polyline coordinates in
`data/map.json`. Those are gameplay numbers, not art, so it is the designer's call and not mine.
See `REPORTS/` for the question as posed.
