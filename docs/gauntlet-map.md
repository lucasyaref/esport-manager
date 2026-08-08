# Gauntlet loop 1 — the map

**Goal:** build the map to match the designer's reference images, and keep going until
neither of us can name a difference that would show at overview scale.

This file is the loop's rulebook and its logbook. It is process, not design — the map's
design model lives in `GDD.md` §6.2, and the phase plan in `BACKLOG.md` under **M6-T**.

## Why a loop

The map is the one artefact where "does it look right?" is the whole acceptance test, and
where I cannot tell whether I have got it right by reading my own code. So the work is
structured as a closed loop with a machine in it: render an image, put it next to the
reference, name the differences, change one thing, render again. The loop is only worth
running because every step is cheap — the render is one command and under a second.

The designer's involvement is deliberately at the two ends: supply the reference, and
sign off at the exit. Everything between is mine.

## The rig

| | |
|---|---|
| `data/terrain.txt` | the map itself — a 50×50 character grid, one char per 2×2 world units. Readable and editable as a picture in any text editor. Legend is in the file's own header. |
| `sim/terrain.gd` | loads that grid, and enforces the guard rails below. Pure GDScript, no Node deps — the T2 navigation will build on it. |
| `game/terrain_view.gd` | draws it. **Shared** with the match viewer, so the loop grades the pixels the game actually shows. All colour and detail knobs are in one block at the top of the file. |
| `tools/shot.sh` | the shutter. Renders the map to a PNG. |
| `tools/terrain_tool.gd` | checks the grid, and repairs symmetry by mirroring one half onto the other. |

```bash
tools/shot.sh --out=res://.shots/iter07.png --size=1024      # render
tools/shot.sh --overlay                                      # + lanes/towers/pits/camps from map.json
godot --headless --path . --script res://tools/terrain_tool.gd -- --check
godot --headless --path . --script res://tools/terrain_tool.gd -- --mirror=red --write
```

Two things worth knowing about the rig:

- **It runs windowed, not headless.** Godot has no rendering context under `--headless` —
  the viewport texture comes back null. `tools/shot.sh` parks a small window off-screen for
  the fraction of a second the render takes. It does not steal focus.
- **The picture is deterministic.** The per-cell tonal noise in `TerrainView` is hashed from
  the cell index, never from an RNG. Same map, same image, every run — otherwise two
  iterations could not be compared. The project's determinism rule applies to the picture
  for the same reason it applies to the sim.

Rendered images go to `.shots/` (gitignored). Reference images go to `docs/reference/map/`
and **are** committed — they are the acceptance criteria, and they must outlive the chat
they arrived in.

## The rubric

Checked every iteration, in this order. A is machine-checked and binary; B–D are my read
against the reference, and are what the iterations actually spend their time on.

**A — Guard rails (must be zero problems, every iteration).** Enforced by `Terrain.validate`:
- exactly N rows of N characters, no unknown characters
- **180° rotational symmetry** — blue-side win rate is a tracked balance metric, so an
  asymmetric map would poison every number the project has
- every base, pit, camp and tower position in `data/map.json` stands on walkable ground
- every walkable cell reachable from both bases (catches a wall typed across a corridor
  that seals off a pocket of jungle)

**B — Layout fidelity.** Three lanes where the reference puts them; river on the opposite
diagonal; two objective pits in their bowls; four jungle quadrants; brush where the
reference has brush; chokepoints where the reference has chokepoints; base footprints the
right size and shape.

**C — Look fidelity.** Palette; contrast between rock and walkable floor; how a rock face
reads as height; texture density; edge treatment; and above all **legibility at overview
scale** — the map is normally seen whole, so detail that turns to mush at 1024 px is worse
than no detail.

**D — Agreement with the sim.** `--overlay` puts `data/map.json`'s own geometry on top of
the render. The lanes drawn must be the lanes the minions walk. Where the picture and the
data disagree, one of them is wrong and it is not always the picture.

## Exit criteria

Loop 1 is done when all of:

1. Guard rails: zero problems.
2. I cannot name a difference from the reference that a designer would notice at overview
   scale, and the differences I *can* name are written down here as deliberate.
3. `--overlay` shows terrain and `data/map.json` agreeing.
4. The designer looks at the final render next to the reference and signs it off.

Criterion 4 is the real one. The other three exist so that the designer is only ever asked
to judge something that has already passed everything a machine can judge.

## Log

| # | Change | Guard rails | Read |
|---|---|---|---|
| 00 | Rig built. Draft-1 grid from `REPORTS/M6-terrain-scoping.md`, baseline palette. | **1 problem** — 143 asymmetric cell pairs | Lanes and river read immediately; recognisably SR-shaped. Bases visibly different sizes (the asymmetry). Lane fill reads as a chequerboard of tiles, not a road. Rock faces invisible at this scale — walls are flat dark blobs. Pits indistinguishable from walls. Camps too small to see. |
| 01 | `--mirror=red --write`. | **pass** | Symmetry fixed; both halves now identical under rotation. Everything else in row 00 still stands — those are art problems, and they are what the reference is for. |

**Waiting on:** the reference images (`docs/reference/map/`). Iteration 02 starts the moment
they land. Nothing between here and there is worth guessing at — the open items in row 01
are precisely the ones the reference decides.
