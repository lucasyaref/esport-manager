# M6-T1 — gauntlet loop 1, run 3

Run 3 is what happened after you answered run 2's three questions. Ten iterations (28–37), four
critic panels (6–9). Guard rails clean at every one; full suite green throughout (data validation,
terrain gate, determinism across 3 seeds, viewer selftest).

**Look at:** `.shots/final-vs-reference.png` — the map beside the reference, same height.
Just the map: `.shots/iter37.png`. Regenerate any time with `tools/gauntlet.sh iter37 --overlay`.

## Your three answers, applied

1. **Pits nudged off the river's centreline.** Done, plus the last cut in the water (below).
2. **Bases inset inside the wall.** Done.
3. **Keep the ring.** Done — recorded in GDD §6.2 as a deliberate divergence, with the consequence
   written down: top and bot are one shape, so telling them apart has to be carried by colour,
   towers or labels, never by layout. Both critics since have confirmed exactly that, independently.

The bent-lane mock is not committed. Its polylines are in `docs/gauntlet-map.md` if you ever want it
back in one command.

## What closed

**The river is one body of water, for the first time in the project.** Your answer to question 1 got
it from four pieces to two. The last cut was mid crossing it, and it was a *rule*, not geometry: the
paint tool deliberately let a lane band overwrite the channel, reasoning that mid crossing the water
is a ford and those cells are road with water drawn over them. The renderer draws one surface per
cell, so what that produced was road. A ford is water interrupting a road. 196 cells, one component.

**The oldest finding in the loop is closed.** Every panel ever run said a cold reader cannot tell
which greens block. Two iterations attacked it as contrast and both were wrong. Panel 7 said what it
actually was: *"mid-green grass and dark-green blobs occupy comparable areas and are both green."*
The reader could always **see** the two greens — it could not know which one meant "walk here", and
no amount of separation between two members of one family answers that. So blocking mass stopped
being green and became stone. Panel 9 now lists *"black = wall, tan = road, blue = water — the
material language is unambiguous"* under **reads instantly, zero effort**.

**The pits read as objectives.** Panel 6: *"I would plausibly have called them terrain obstacles."*
Panel 9: *"distinct built features"*, found at `certain`, both centres exact.

**Camps are findable again.** Measured at panel 9, a camp was luminance 0.286 and the grass it sits
in was 0.283 — the same surface. They now sit a step below it.

## Three things worth knowing

**A cue that goes quiet is worse than one never written.** The map already had a ford marker.
Iteration 28 switched it off — the test asked *lane* cells whether water lay either side, and the
same commit turned those cells into river. Nothing failed. The gate passed, the suite passed, and
the only thing that noticed was a cold reader two panels later. There is now a standing habit from
this: when a cell's kind changes, grep for every cue keyed on the old kind.

**A ratio is not a contrast.** Iteration 32 checked its own work by measuring and found the value
ladder monotone: void 0.061, rock 0.184, floor 0.284. Three times the void's luminance — and still
two blacks to look at, which both critics said in the next panel. Down at the bottom of the range,
arithmetic separation and visible separation are different things. Measuring is how you check a
*claim*; it is not how you check a design.

**"The cue is absent" and "the cue is inaudible" are the same sentence in a cold report.** Three
panels have now reported no height cue on renders that measurably had one — cap 0.380 against a rock
body of 0.222, cast shadow a 52% drop. Each time, measuring settled it. Twice it also turned up the
real defect underneath, which no critic had named: at iteration 31 the rock's lit cap was the same
value as walkable ground, so every mass read a cell too small at the top and a cell too big at the
bottom, and its true boundary was drawn nowhere.

## Two questions for you

Everything else still open is filed `by-design` against a numbered rule, or is out of reach of a tile
renderer. These two are not mine to decide.

### 1. The map is tan where the reference is green. Do you want the road to take less of it?

Side by side this is the biggest single difference, and the fidelity critic has led with it twice:
*"reading the image by value alone, it says pale desert floor with dark holes cut into it"*, against
a reference that is a dark green map with pale stone roads.

It is not a mistake — it is the arithmetic of two decisions already made. **Rule 6** gives the road
the only warm hue and the highest value on the map, and **the ring** gives it 602 cells against 296
of green. Together they make tan the dominant field.

The lever is lane width. The bands are half-width 4.4 world units; the reference's roads are
proportionally about half that. Narrowing them takes tan area back and gives it to the jungle, and it
is a **gameplay change** — less room to move in lane, more jungle volume, wider gaps between the road
and the rock — which is why it is yours. Options:

- **(a) Narrow the roads** to ~3.4 half-width. Green becomes the dominant field, chokepoints tighten,
  lane fights get more cramped.
- **(b) Keep the width, lower the road's value** so tan stops being the brightest thing. Cheaper, no
  gameplay change, but it works against rule 6 and the eye stops following the lanes.
- **(c) Leave it.** The map reads correctly to a cold viewer as it stands; it just does not look like
  the painted reference, which §6.3 already says is only evidence.

### 2. The walls: our two critics now disagree, so it is a design call

This is logged as a trade-off rather than chased, because the finding came back after I had already
moved it once.

| | Says |
|---|---|
| **Fidelity critic**, panels 8 and 9 | Rock is too dark and *"reads as pits punched through the ground"*. In the reference, rock is **lighter** than the ground it stands in — pale boulders on dark grass. |
| **Legibility critic**, panel 9 | *"Charcoal-grey slabs with black outlines that read unmistakably as walls or rock — my eye reads them as 'you cannot go here' immediately."* Filed under **certain, zero effort**. |

Three things bear on it:

1. **§6.3 already answers it, and answers against the reference.** The stated ordering is *lane
   lightest, floor mid, rock dark*, and rule 1 is "dark by default". `docs/reference/map/README.md`
   says §6.3 wins where the two disagree. Inverting it means changing rule 1.
2. **Part of the finding is measurably false** — *"no lighter cap, no cast shadow"* is the third
   panel to say that about a render where both are present and strong.
3. **They are answering different questions.** One asks "does this look like the picture", the other
   asks "can a cold viewer read it". They now give opposite answers, which is what a design decision
   looks like.

My read, for what it is worth: the legibility critic is the one measuring the thing the PoC needs,
and I would leave the walls alone. But rule 1 is yours to keep or change.

## Where the loop stands against its exit criteria

| | |
|---|---|
| Guard rails clean | ✅ |
| Overlay agrees with `map.json` | ✅ — lane polylines down the centre of every band, all 8 camp anchors on camp cells, both pit anchors on the pit eyes |
| Legibility: every real feature identified, nothing invented | ✅ features and coordinates verified; two standing gaps, below |
| No in-scope fidelity finding above `cosmetic` | ⚠️ — see below |

The fidelity criterion will not be met by iterating, and it is worth saying why plainly. That critic
grades against a painted illustration whose ornament, lighting, props and value structure we have
refused **on the record**, rule by rule. Its remaining findings are: bases as built structures
(no prop layer in M6-T1), torch chains and painted light (rule 7, and no decal layer), the two
objectives being visually distinct from each other (needs an icon layer), the value inversion
(question 1), and the walls (question 2). None of them is reachable by a tile renderer editing a
palette, which is what this loop is.

**Two things a still frame cannot answer**, both recorded as limits of the rig rather than banked as
solved:

- **Which green conceals.** Brush is a distinct surface and gets found, but nothing in a frame says
  standing in it hides you. §6.3 rule 3 answers this with *"a viewer learns five shapes in the first
  ten seconds of their first match"* — a claim about watching a match, not about a frame.
- **What each objective is.** Both pits are identical by construction. Dragon versus baron is an
  icon, not a terrain colour.

Both are yours to settle by watching a match, which is the next thing to do anyway.

---

## Answers, 2026-08-09 — both "leave it", and the loop is closed

**1. The road keeps its share of the map.** Recorded in GDD §6.3 rule 6, with its cost stated: this
rule plus the ring makes ours a tan map with green in it where the reference is a green map with pale
roads, and the lever offered — narrowing the lane bands — was gameplay space, not art.

**2. Rule 1 stands and the walls stay dark.** Recorded in GDD §6.3 rule 1 and in the reference
README's deliberate-differences table, because a cold critic cannot know either and will keep
reporting them. Rule 1 also picked up the two corollaries this loop paid for: a feature with *no*
value separation from its surroundings is invisible however small it is, and a ratio is not a
contrast.

**Gauntlet loop 1 is closed.** All four exit criteria met, designer sign-off given. M6-T1 is done;
the narrative moved to `CHANGELOG.md` and `BACKLOG.md` keeps a one-line status.

**What is still true and unanswered, and why it is not a defect:** a still frame cannot say which
green conceals, and cannot say which pit is dragon and which is baron. The first is §6.3 rule 3's own
claim about *watching a match*; the second needs an icon layer. Both are answered by playing one, not
by another iteration — which makes T2 (movement routing around walls) the next thing to build.
