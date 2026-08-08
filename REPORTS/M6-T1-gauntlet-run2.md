# M6-T1 — gauntlet loop 1, run 2

Run 2 is the first run graded against **GDD §6.3** — the eight written rules — rather than against a
picture. `terrain_moba_2.png` supplies palette and mood only. Nine iterations (15–23) and two critic
panels. Guard rails clean at every one; full suite green (data validation, terrain gate, determinism
across 3 seeds, viewer selftest).

**Look at:** `.shots/iter23.png`, next to `docs/reference/map/terrain_moba_2.png`.
Regenerate any time with `tools/gauntlet.sh iter23 --overlay`.

## What changed

Baseline `iter15` broke three of the eight rules. Each got one iteration:

- **Rule 6 — the road is the only warm hue, and the highest value on the map.** It was a cold
  green-grey, the same hue as the arena wall and the pit rims. Now warm sand.
- **Rule 7 — the ornament budget goes to bases, pits and river.** The loudest thing on the map was
  eight amber torch-lit camp clusters in the jungle. Camps are now scuffed clearings.
- **Rule 4 — big blocks, not fine detail.** The canopy was diagonal sawtooth blobs. A new
  `terrain_tool.gd --chunkify=N` snaps rock masses to a 2×2 block grid.

Then the panel's findings drove four more: chokepoint repair (below), a stronger height cue, brush
separated from canopy, and the pits given an outer shadow ring so they read as sunk rather than flat.

**The oldest finding turned out to be a palette line.** Panels 2 and 3 both led with the road and the
arena wall being *"identical material, contradictory functions"*. I read it as geometry twice — moved
the lanes in iteration 11, redefined the void in iteration 12. It was hue. Rule 6 closed it in one
line.

**`--chunkify` is worth knowing about** because it is reusable and it is safe by construction:
symmetry is structural (the block grid is invariant under the 180° rotation), and while every cell in
a block votes, only plain floor and interior rock are ever rewritten — lanes, river, pits, camps,
brush, bases and the rampart hold their ground, so no `map.json` anchor is ever built over.

## Two things the loop caught that the guard rails could not

**A passing gate is not a working change.** Chunkify at threshold 3 passed every rail and quietly
erased two-thirds of the jungle's chokepoints — pinched cells fell 22% → 8% and the jungle floor grew
36%. The fidelity critic caught it cold as *"nothing narrows"*. Threshold 2 is where rule 4 and the
map's chokepoints balance; a one-cell gap cannot survive a two-cell block grid, so some loss is
inherent.

**The two critics contradicted each other and the pixels settled it.** Fidelity called the jungle
quadrants *"solid wall, essentially no walkable floor"*; legibility, on the same image, called them
*"walkable grass with dark blobs scattered"*. Measured, the render's light-pixel fraction tracks the
grid's walkable fraction within 3 points in all four quadrants — 63/57/59/54% against 62/60/59/53%. The
fidelity finding was a misread and was not acted on. The rubric already verifies critics' *coordinates*
against the grid; this was an invented *proportion*, and it needed the same treatment.

Five panels now, still zero confabulated coordinates.

## Design questions

Three findings are verified true in the data, have survived several panels, and are blocking the
loop's exit — but every one of them moves numbers in `data/map.json`, which is gameplay and yours.

**1. The river is cut in two by the two pits.** It is four separate bodies of water: two long arms and
two small pools. Each pit sits *centred on* the river's diagonal, so the water runs into the bowl and
resumes on the far side. Every panel since the first has reported it independently, and it is real in
the data, not a rendering artefact. The reference — and Summoner's Rift — put the pits *beside* the
water with the river flowing past. Options:

- **(a) Nudge both pits off the river centreline** so the water flows past them. Cleanest, matches the
  reference, changes the dragon/baron pit coordinates and the fights around them.
- **(b) Carve a channel around each pit.** Keeps pit positions, but the only routes available run
  through camp cells, so a jungle camp moves.
- **(c) Leave it.** The river is cosmetic and walkable, so nothing about play changes — but the map's
  single strongest read (rule 2: water is the one saturated thing, which is why it reads instantly)
  stays broken into pieces.

**2. Both bases sit 1 cell from the map edge**, so each overlaps the boundary wall instead of sitting
inside it — three panels have called the bases "pasted over the wall line". You had me inset the
*lanes* for exactly this reason at iteration 11; the bases were not part of that instruction. Insetting
them shrinks each base footprint and moves the nexus and base-turret coordinates. Do you want the same
treatment applied to the bases?

**3. The outer lanes form a closed rectangular ring.** Top and bot run as one continuous racetrack
around all four sides, and both critics independently said they could only tell it was two lanes from
the tower colours — *"I would have narrated 'they're running the outer ring' instead of 'pushing top'."*
On Summoner's Rift the two side lanes read as separate because the map is a diamond and they meet only
at the bases. Making ours read that way means breaking the ring somewhere — bending the lanes inward at
the two neutral corners, which changes lane length and rotation timings. Worth doing, or is the ring
fine?

## Where the loop stands against its exit criteria

| | |
|---|---|
| Guard rails clean | ✅ |
| No in-scope fidelity finding above `cosmetic` | ❌ — three, all layout, all listed above |
| Legibility: every real feature identified, nothing invented | ✅ features and coordinates; ⚠️ one standing ambiguity, below |
| Overlay agrees with `map.json` | ✅ — true by construction since iteration 11 |

The standing ambiguity is **which green blocks**. Brush, jungle floor and canopy are now three
clearly distinct surfaces — panel 5 enumerated all three and placed them correctly — but a cold reader
still cannot tell from a still frame which one you can walk through. §6.3 rule 3 answers this with *"a
viewer learns five shapes in the first ten seconds of their first match"*, which is a claim about
watching a match, not about a frame. It may simply be untestable by this rig, and the person to settle
it is you, watching one.

Answering the three questions above unblocks the exit; leaving them answered "no change" also
unblocks it, with the differences logged as deliberate.
