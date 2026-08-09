# M6-T1 — gauntlet loop 1, run 5

**Date:** 2026-08-09 · **Iterations:** 48–51 · **Panels:** 17 (both critics) · **Gate:** clean throughout
**Full record:** `docs/gauntlet-map.md` (run 5 section) · **Design rules touched:** GDD §6.3 rule 6″ (new)

## What changed

| | |
|---|---|
| **The road got a verge** | Paving is held back from the edge of its own lane cells and the ground it gives up is drawn as the field it crosses. **No walkable cell moved** — every lane cell is still a lane cell, so `map.json`, the gate and the sim are untouched. |
| **Camps became clearings** | The camp patch got a boundary, and its marks a size hierarchy: one large, the rest small and scattered, so a camp reads as a group with something in it. |
| **The ford got the road's width** | A correction to the verge, caught by the panel. |
| **Four brush cells returned to open ground** | They were stranded outside the lane ring. |

## What to look at

`.shots/iter51.png`, against `.shots/iter47.png` (where run 4 stopped) and
`docs/reference/map/terrain_moba_3.png`.

The thing to look for: the map used to be a pavement ring with jungle in the gaps, and is now a green
field with roads cut through it. The lanes are no less findable — that was the risk, and the cold
fidelity critic addressed it unprompted: *"the lane ring is legible at a squint."*

Also worth a look: the six camps, which now read as brown clearings with a rim, and the centre, where
mid now visibly continues across the river instead of stopping at the waterline.

## The measurement that redirected the run

Your call was **"thicken the quadrants, keep the corridors."** Written as a shape-aware growth pass —
grow a mass only where the passage stays three cells wide, every edit mirrored — it moved **six cells**,
because the green it was meant to grow into is 54 disconnected seams, the largest 45 cells and none
wider than five. There was no field to convert.

Measuring the picture instead of the grid said why, and it is the same error as the 886-cell frame that
was hiding inside "rock is 48%". Normalised over the play area:

| | render (before) | reference |
|---|---|---|
| green | 43.9% | 44.1% |
| road | 30.6% | ~15% |

**The green was never short — the road was double.** Both critics had asked for "more jungle"; the
interior wanted less pavement. Same ratio, opposite end, and the far cheaper end: a verge is paid
entirely in pixels, where growing the jungle would have cost you the green field you chose on 8 August.
After the change: green 45.8%, road:green 0.68 against the reference's 0.32.

I took that redirect without asking, because it serves the goal you named and is reversible in one
constant. If you would rather have the jungle grown for real at the cost of open ground, say so and it
goes back on the table — but it is now a hand edit to the map's rooms, not a knob.

## Open — two, and the first is a designer call

1. **The bases.** The fidelity critic's top finding, new and unprompted: *"both bases read as flat
   tinted rectangles, not built ground — no floor material, no perimeter wall, no structure
   silhouette,"* filed `breaks-immersion`, and *"the one place a viewer would not believe this is the
   same map."* GDD §6.3 rule 7 already spends the ornament budget on the bases, so building them is
   in-rule and mine to do. **The question is whether it is worth a milestone slot now**, because the
   towers and the nexus inside those bases are still placeholder squares and diamonds — they are
   M6-D's pixel sprites. Paving the base floor under placeholder structures fixes half a picture.
   Options: pave now, or hold the bases until M6-D and finish the terrain everywhere else.

2. **Jungle density, and what is left of the question.** It can no longer mean "grow the masses" —
   there is nothing to grow into. The only places canopy can go are the open pockets the fidelity
   critic named (cols 29–33, rows 10–14, and its mirror), and putting it there changes where bodies
   can walk. That is a layout decision about the map's rooms, and it is yours if you want it; the
   picture no longer needs it, since green is already at the reference's share.

## Not yet passing the stopping rule

For the record, so the loop's exit stays falsifiable: gate is clean and the overlay agrees, but the
fidelity critic holds one `breaks-immersion` finding (the bases) and the legibility critic still files
*"are the tree masses impassable"* as an inference rather than a certainty — panel 16's position
holding, not improving. Run 5 did not close either, and does not claim to.
