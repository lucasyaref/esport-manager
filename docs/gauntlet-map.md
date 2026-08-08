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

**Waiting on:** the reference images (`docs/reference/map/`). Until they land the fidelity critic
cannot run, and the loop can only measure "is this readable", not "is this right". The legibility
critic *can* run now and is worth one pass on the current render as a baseline.
