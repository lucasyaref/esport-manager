# M5-E — The sandwich, roams and tempo trades

Status: **phase E1 (the sandwich) built and measured; E2 (roams + tempo payoff) next.**

This phase exists because of your 2026-07-26 note:

> "When jungle is behind the enemy (for example: Red-mid is pushing the blue tower2 (t2). Jungler
> blue is doing blue buff or in the river. Blue-mid is defending t2. This position is a 'perfect
> position' for sandwiching the red mid, it should call for a gank). => I am not sure how to
> technically scope this but it will be important."

## How I scoped it

Two pieces, no new subsystem — which is what makes it affordable now rather than "after the engine
grows".

**1. A detector that reads the board.** Every time the jungler would consider a gank, it first looks
for the position you described, in four conditions:

- an enemy laner pushed more than `sandwich_depth` past the midline onto our half (measured against
  the *midline*, not against their tower — standing a tower's length from home is ordinary laning,
  and testing that called a sandwich on every wave in the first cut);
- our laner alive and farming that lane — the near jaw of the pincer;
- our jungler can reach the cut-off point before the victim could walk home (`sandwich_eta_margin`);
- nobody of theirs within `sandwich_help_radius` to answer it.

If the board has it, the call happens — it is not gated behind the opportunistic gank dice any more.
Whether the *team* sees it is `macro`-gated, so the same position produces the call more often from a
sharp roster than a poor one, and never never for either (the blend model, GDD §6.1).

**2. The cut-off destination — the one genuinely new mechanic.** A ganker used to walk at the
victim's own stand position. With equal move speeds that just pushes the victim home, which is why
plain ganks whiffed (M5-C). A sandwich instead walks to a point *past* the victim, between it and its
own base, so the victim is between our jungler and our laner. Taking the escape route away is the
catch. It costs nothing structurally: lane params already exist, so there is still no pathfinding
(the GDD scope guard holds).

The laner half was already in place from M4.5-F — a player who hears the call steps up (`allin`
stance) instead of farming — and a sandwich adds `sandwich_react_bonus` to that roll, because a
telegraphed set-up is easier to read than a jungler simply turning up.

All of it is data: `ganks.sandwich_*` in `data/balance.json`.

## What to look at in-game

The feed now distinguishes the two plays: **"Azure Wolves sandwich mid (1 follow)"** versus the plain
"gank mid". When you see a sandwich line, watch the jungler's path — it should walk *past* the victim
toward the enemy's side of the lane rather than straight at it, and your laner should step up rather
than hold.

## Numbers

200 sims, seeds 5000–5199 — the set every M5 phase is measured on. "Before" is HEAD (M5.5-H, the
doorstep change); M5-D's pre-M5.5 baseline is in the last column for the longer view.

| Metric | before (M5.5-H) | **with the sandwich** | M5-D | target |
|---|---|---|---|---|
| **Azure Wolves (macro) win** | 33.0% | **36.0%** | 36.5% | ~43% |
| Blue-side win | 47.0% | 44.0% | 49.5% | ~50% |
| Gold-lead @15 → win | 64.8% | **65.0%** | 66.3% | ~65% |
| Match length avg (min) | 27.1 | 27.0 | 26.9 | 25–35 |
| Kills / match | 22.5 | 22.5 | 22.0 | |
| First blood (min) | 4.8 | 4.3 | 4.8 | |
| Gank calls / match | 9.7 | 14.1 | 9.7 | |
| Gank connect rate | 16% | 18% | 16% | |
| **Sandwich calls / match** | — | **6.17** (44% of calls) | — | |
| **Sandwich connect rate** | — | **21%** | — | |
| Jungle kill share | 10% | 11% | 10% | |
| Lane swap rate (team-games) | 24% | 28% | 24% | |
| Timeouts | 0 | 0 | 0 | 0 |

**The macro win-vector moved the right way: +3 points** (33.0 → 36.0), recovering everything the
doorstep change cost and landing back at M5-D's level *with* the doorstep kept. Gold-lead conversion
is exactly on target. Length, kill count and timeouts are unchanged, so nothing was bought with
pacing. The sandwich connects at **21% against 18% for calls overall** — it is a better play than the
gank it partly replaces, which is the whole premise.

**One flag for M5-G: blue-side win is drifting** (49.5 → 47.0 → 44.0). At n=200 that is about 1.7
standard errors from even, so it is a signal to watch rather than a proven regression — but M5-D
specifically fixed this metric once, so I am not letting it pass silently. It gets re-measured in
M5-G, where the side-balance dial lives.

## Not done yet

- **E2 — proactive roams (items 2 & 5) and the tempo payoff.** The support as the prime roamer, and a
  landed play converting into tower/plate pressure instead of evaporating.
- The win-split target (~43/57) is M5-G's sign-off, not this phase's.
