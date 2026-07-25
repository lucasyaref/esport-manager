# M8 scoping — highlights & the close-up view

Status: **scoping only, nothing built.** Your direction of 2026-07-25 (a second, zoomed,
real-speed view for 5–10 "highlight" moments per game) turned into a milestone plan in
`BACKLOG.md` and a design section in `GDD.md` §7.2. This report carries the measurements
behind the plan and the questions only you can answer.

## The short version

The feature is right and it is the biggest remaining upgrade to the core fantasy. Two parts of
it should be built at very different times:

- **Picking the highlights** is cheap, headless, testable, and it doubles as a *balance metric*
  ("does this match contain 8 moments worth watching?"). It should land early — alongside M5-G.
- **Showing them** (camera, real speed, animated characters, spell VFX) is the most expensive
  and most art-dependent work in the project. It belongs after the PoC is closed, and it has a
  hard prerequisite the numbers below make plain.

## The measurement (60 matches, seeds 1000–1059)

I clustered every kill into "moments" (kills within 12 s and 14 world units of each other are
one moment) and looked at what a reel could be built from today.

| | |
|---|---|
| match length | mean 27.6 min (p10 22.7 / p90 35.2) |
| kill-moments per match | mean 20.9, median 20 |
| deaths per moment | **1 death: 92%** · 2: 7% · 3: 1% · 4+: ~0% |
| of those, pure solo kills (no assists) | 44% |
| moments next to an objective take | 1.5 per match |
| moments before 14 min / after | 4.6 / 16.3 |
| detected fights (both teams engaged) | 23.0 per match, mean duration 6.3 s (p90 8 s) |
| fights with a kill in them | 4.3 per match |
| **fights with ≥6 participants** | **0.00 per match — none in 60 matches** |

### What this says

1. **There is plenty to choose from.** ~21 candidate moments per match against a target of 5–10
   selected means the scorer has real selection pressure to work with, and your "below a
   threshold, don't select it even if it's top-10" rule will actually bite. Good.
2. **Fight length fits the format.** Fights run 6.3 s mean, 8 s at p90, 22 s worst case. A 25–30 s
   highlight window comfortably holds pre-roll (the approach — the part that makes a gank read as
   a gank) + the fight + the aftermath. The 30 s budget you guessed at is the right budget.
3. **The teamfight you want to watch does not exist yet.** 92% of moments are a single death, and
   *no match in 60* produced a fight with six or more champions in it. If we built the close-up
   view today, the reel would be eight 2v1 ganks and a skirmish at dragon. That is the strongest
   argument for ordering: **M5-E/F (proactive roams, coordinated multi-man convergence) is a
   prerequisite for the highlight reel to contain what you asked for.** The camera is not the
   missing piece — the plays are.
4. **The reel would be back-loaded.** 16 of 21 moments land after 14 min. Selection needs an
   explicit spread rule (a minimum gap, and a reserved slot or two for the laning phase) or every
   highlight will come from the last third of the game.

## The thing to know about "real speed"

Today's **1x is already 4× sim-time** — playback runs 40 sim-ticks per real second, and the sim
runs 10 ticks per sim-second. That is what buys the 8-minute match. So "real speed" for a
highlight is **0.25× the current slowest speed**, a new speed below 1x, not a new label on an
existing one.

The consequence is pacing, and it is a decision for you (question 2 below). 8 highlights × ~25 s
of real-time action adds **~3.5 real minutes** to an 8-minute match — a watched match becomes
~11–12 minutes. Three ways out:

- **(a) Match gets longer.** Overview stays 1x, highlights add on top. Most immersive, ~12 min.
- **(b) Budget stays 8 min.** The overview runs faster between highlights to pay for them.
- **(c) Highlights-only mode** (what Football Manager calls "key highlights"): skip straight from
  moment to moment, overview only as a brief connective scrub. A whole match in ~4–5 minutes.

My recommendation: build (a) as the default and (c) as a mode, because they are the *same*
machinery — a highlight is a time window plus a camera focus, and the only difference is what
playback does between windows. (b) is a tuning knob on top of either. Once there is a season
calendar, (c) becomes the mode people actually live in.

## What already-shipped work this touches

Listed in `BACKLOG.md` under M8; the short version is that none of it is a rewrite, and one item
is a design decision rather than a code change:

- **The camera does not exist.** `MapView._scale()` / `_w2s()` assume the whole world fills the
  viewport. A camera (centre + zoom + smoothing) replaces them — contained, but every pixel
  constant in that file (body radii, tower radius, font sizes) is clamped for the fit-the-world
  assumption and has to become zoom-aware.
- **Snapshot cadence.** The viewer runs the sim at one snapshot per 2 ticks — 5 keyframes per
  sim-second. Fine at overview scale; at 4× zoom and real speed, interpolating across 200 ms will
  read as sliding. Viewer runs move to one snapshot per tick (a memory cost to measure, not a
  design change).
- **Visual lifetimes.** M5.5-G sized every transient in real seconds *at 1x*, stretching with the
  speed button and capped at 4×. That cap has to open downward for a sub-1x speed, or every
  effect will linger four times too long in the close-up.
- **Drawn body separation vs. sim positions.** Playback currently pushes overlapping bodies up to
  1.9 world units apart for legibility while the sim keeps them stacked. At overview scale that is
  invisible; at 4× zoom, a character is drawn away from the point its own attack beat is drawn
  from. This is the parked M5-E/F question about **sim-side body volume** — the close-up view is
  the argument for finally taking that lever rather than continuing to fake it in playback.
- **There is no terrain.** The map is lane polylines and points; there is no walkable space, so no
  walls, corridors or escapes. A gank watched from a distance is dots converging; a gank watched
  *close up* is a story about a corridor, and characters strolling through jungle "walls" that
  don't exist will read as broken. Your parked "jungle walls, terrain and chokepoints" item is
  promoted from nice-to-have to a **decision point before M8-D**.
- **Docs**: GDD §7 (playback speeds) and the new §7.2; `--selftest` and `tools/check.sh` gain
  highlight assertions.

## Questions for you

1. **Ordering.** My plan puts the draft screen (M6) and the PoC close (M7, tag `poc-1`) *before*
   the close-up view, with only the scoring layer pulled early. That is right if the PoC exists to
   prove the management loop to you. It is wrong if the PoC exists to **show someone else** — the
   zoomed fight is by far the better thing to put in front of a publisher or a community, and in
   that case highlights should jump ahead of the draft screen. Which is it?
2. **Pacing.** (a) longer watched match, (b) same 8-minute budget with faster overview, or (c)
   highlights-only as the default mode? (See above; I recommend building (a) + (c).)
3. **Art.** CLAUDE.md's standing guardrail is placeholder-only, no external art dependencies. A
   close-up view is where that starts to hurt. Three options: **(a)** richer *procedural*
   characters — animated limbs, squash/stretch, wind-up telegraphs, still zero art dependency;
   **(b)** a free/CC0 top-down character set as the shared placeholder; **(c)** real per-character
   art, post-PoC. I recommend (a) for the milestone and keeping the `sprite` data field so (b)/(c)
   drop in with no code change — but if you already know real art is coming, say so and I will
   shape the actor code around a sprite-sheet contract instead of shapes.
4. **What counts as a highlight.** My starting scoring model (GDD §7.2) weights: deaths in the
   window, participants, gold swing, objective/tower stakes, whether it changes the game's
   direction, plus rarity bonuses (first blood, a solo kill against the odds, a steal, a base
   defense) and a diversity/spacing penalty so the reel isn't six identical bot ganks. Anything
   you would add — or anything you'd want *never* selected?
