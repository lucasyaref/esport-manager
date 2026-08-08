---
name: gauntlet-map
description: Run gauntlet loop 1 — iterate the MOBA Manager map's look until it matches the designer's reference images. Use when asked to work on the map, the terrain, how the map looks, or to run/continue the gauntlet loop. Orchestrates render, machine gate, and a two-critic panel with a falsifiable stopping rule.
---

# Gauntlet loop 1 — the map

You are the **orchestrator** and the **designer** of this loop. You are not its critic — that role is
held by subagents, on purpose, and the whole loop is worthless if you take it back.

The rubric and the iteration log live in `docs/gauntlet-map.md`. Read it before your first iteration
of a session; append to it at every checkpoint. This file is the procedure; that file is the record.

## The roles, and why they are split

| Role | Who | Does |
|---|---|---|
| Orchestrator | you | runs iterations, holds the stopping rule, catches oscillation, decides when to call the panel |
| Designer | you | edits `data/terrain.txt` (layout) and the knob block in `game/terrain_view.gd` (look) |
| Machine critic | `Terrain.validate`, via `tools/gauntlet.sh` | symmetry, reachability, anchors on walkable ground, grid legality |
| Fidelity critic | `map-fidelity-critic` subagent | render vs. the designer's reference images |
| Legibility critic | `map-legibility-critic` subagent | can a cold viewer identify anything on this map at all |

The split exists because you cannot grade your own picture. You know what you were trying to draw, so
you see the intention rather than the pixels, and you converge on "looks good to me" in about three
iterations. The critics come in cold and have no memory of the intent. **That coldness is the only
thing they are for — protect it.**

## Before you start

Check `docs/reference/map/` for reference images (any filename, PNG/JPG, ignore `README.md`).

- **References present** — run the full loop.
- **No references** — the fidelity critic cannot work and must not be spawned; it will correctly
  refuse. You may still run the loop on the legibility critic alone, which needs no reference. Say
  plainly in your report that this is a degraded loop measuring only "is this map readable", never
  "does this match what the designer wanted".

## The cycle

Iterate. Each iteration is one command and one change:

```bash
tools/gauntlet.sh iterNN --overlay
```

1. **Gate.** If the guard rails fail, fix them and nothing else. An asymmetric or unreachable map is
   wrong regardless of how it looks, and spending a critic pass on it wastes a cold read. Symmetry
   repairs itself with `terrain_tool.gd -- --mirror=red --write`.
2. **Look at the render yourself** with `Read`. You are allowed to have taste; you are just not
   allowed to be the last word.
3. **Make one coherent change** — one axis at a time. Layout goes in `data/terrain.txt`; colour and
   detail go in the knob block at the top of `game/terrain_view.gd`. Changing four things at once
   means the next critic pass cannot tell you which one worked.
4. Repeat. After **three or four** iterations, or sooner if you think you are done, call a checkpoint.

## The checkpoint

Spawn **both critics in parallel** — two `Agent` calls in a single message, `run_in_background: false`,
because you need their findings before you can do anything else.

What you send them is the discipline that makes this work. Send **only the image path**, and for the
fidelity critic the fact that references are in `docs/reference/map/`. Do **not** send: what you
changed, what you were trying to achieve, what a previous critic said, what you think is still wrong,
or any part of the rubric. Every one of those turns a cold read into a confirmation of your own view,
which is the failure this whole structure exists to prevent.

Then, before you act on anything:

- **Verify the legibility critic's coordinates against `data/terrain.txt`.** You hold the ground truth
  and it does not. A confident claim at coordinates where the grid has nothing is a confabulation, and
  it tells you the map is suggestive rather than legible — which is itself a finding worth logging.
- **Sort findings by severity, then act on the top two or three.** Do not chase every `cosmetic`.
- **Append the checkpoint to the log** in `docs/gauntlet-map.md`: iteration number, what changed,
  gate result, the findings and their severities, and what you did about them.

## Stopping

Exit the loop when a **single checkpoint** produces all of:

1. Gate: zero problems.
2. Fidelity critic: no finding above `cosmetic`.
3. Legibility critic: every feature that genuinely exists in `data/terrain.txt` identified at
   `certain` or `probable` with coordinates that verify — **and nothing claimed that is not there**.
4. `--overlay` shows the terrain and `data/map.json` agreeing on where the lanes and anchors are.

Then hand it to the designer with the final render and the reference side by side. **Their sign-off is
the real exit**; 1–4 exist so they are only ever asked to judge something that already passed
everything a machine and two cold readers could judge.

## Oscillation

If a finding you previously logged as fixed comes back, you are trading two axes against each other —
raising rock contrast is eating lane readability, or similar. Do not keep swinging. Stop, log both
positions as a trade-off, and put it to the designer as a choice. Two critics disagreeing is a design
decision, not a bug to fix.

## Cost discipline

Every critic pass is a fresh cold agent that re-derives its context from scratch, so it is the
expensive part of this loop.

- Do **not** call the panel every iteration. Three or four self-graded iterations per checkpoint.
- Do **not** spawn a critic to confirm a change you already know worked.
- Do **not** re-spawn a critic to argue with its finding. If you disagree, log the disagreement and
  let the designer settle it — re-rolling until you get the answer you want is just self-grading with
  extra steps.
