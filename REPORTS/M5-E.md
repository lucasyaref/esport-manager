# M5-E — The sandwich, roams and tempo trades

Status: **done — the sandwich and the tempo payoff shipped, the roam widening measured and rejected. Your 1x playtest is the gate.**

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

200 sims, seeds 5000–5199 — the set every M5 phase is measured on. "Before" is the previous commit
(M5.5-H, the doorstep change); the middle columns are the two builds this phase measured, the bold
column is what shipped.

| Metric | before (M5.5-H) | sandwich (E1) | roams + tempo (rejected) | **shipped (E1 + tempo)** | target |
|---|---|---|---|---|---|
| **Azure Wolves (macro) win** | 33.0% | 36.0% | 33.0% | **36.0%** | ~43% |
| Blue-side win | 47.0% | 44.0% | 40.0% | **49.0%** | ~50% |
| Gold-lead @15 → win | 64.8% | 65.0% | 64.3% | **66.5%** | ~65% |
| Match length avg (min) | 27.1 | 27.0 | 27.2 | 27.1 | 25–35 |
| Kills / match | 22.5 | 22.5 | 23.3 | 22.9 | |
| First blood (min) | 4.8 | 4.3 | 4.2 | 4.3 | |
| Gank calls / match | 9.7 | 14.1 | 14.3 | 14.2 | |
| Gank connect rate | 16% | 18% | 18% | 17% | |
| Gank followers avg | 1.09 | 1.08 | 1.05 | 1.09 | |
| **Sandwich calls / match** | — | 6.17 | 6.18 | **6.12** (43% of calls) | |
| **Sandwich connect rate** | — | 21% | 21% | **20%** | |
| **Tempo windows / match** | — | — | 0.69 | **0.65** | |
| **Windows that took the tower** | — | — | 23% | **27%** | |
| Lane swap rate (team-games) | 24% | 28% | 30% | 28% | |
| Timeouts | 0 | 0 | 0 | 0 | 0 |

**The macro win-vector moved the right way: +3 points** (33.0 → 36.0), recovering everything the
doorstep change cost and landing back at M5-D's level *with* the doorstep kept. Gold-lead conversion
sits on target, side balance is back to even (49.0%), and length, kill count and timeouts are
unchanged — nothing was bought with pacing. The sandwich connects at **20% against 17% for calls
overall**: it is a better play than the gank it partly replaces, which was the premise.

A note on the blue-side column, since I flagged it mid-phase: E1's 44.0% looked like a drift worth
watching, and the rejected roam build made it worse (40.0%). With roams reverted it is 49.0% — so the
drift was the roams plus sampling noise, not the sandwich. Nothing carries to M5-G on that count.

The macro split is still 36/64 against a ~43/57 target. That gap is what M5-F (multi-man plays) and
M5-G (the balance pass) are for; E was never going to close it alone.

## E2 — roams and the tempo payoff

Two changes on top of the sandwich.

**Roams (items 2 and 5) — built, measured, reverted.** I widened follower eligibility from "the play
is in your lane (or you are a shoved-in mid)" to "any laner with lane priority who is close enough to
arrive while it matters, support favoured". Over 200 sims it cost the macro team **3 points**
(36.0% → 33.0%), pushed blue-side win to 40.0%, and did not even raise the follower count
(1.08 → 1.05). That is the M5-C roam revert happening a second time, for the same structural reason:
**leaving lane costs priority immediately and pays only if the play converts**, and the macro team —
which by construction makes the most plays — eats the most of that cost. A wider dice roll is not the
missing piece. The committed multi-man play *is*: a named target, a committed set, and a window, so
the roamers who leave arrive together and the play is worth the priority. That is **M5-F**, and this
result is the argument for building it that way.

**Tempo (the payoff).** A kill used to be worth its gold and nothing else. Now killing a laner opens
a window on that lane, and whoever is nearby spends it there — the jungler presses instead of walking
back to a camp. Macro-gated, so a sharp roster turns a pick into a turret and a poor one takes the
gold and wanders off.

The first cut of this made the macro team *worse*, and the reason was the M5-C lesson repeating:
plays that cost farm and pay nothing hurt whoever makes the most of them, which is the macro team by
construction. So the window only opens where there is something to spend it on — **our wave is alive
in that lane and the front is already within reach of their tower**. That took tempo windows from
7.1 a match at a 7% conversion to 0.65 a match at **27%**: rarer, and actually a play.

*Method note:* the 40-sim probes I use while iterating carry about ±7.5 points of noise on a win
rate, so they are only good for behaviour counts (how often does this fire, does it convert). Every
balance decision below is made on the 200-sim set.

## Not done yet

- The win-split target (~43/57) is M5-G's sign-off, not this phase's.
- **M5-F** still owns the multi-man convergence and the gank telegraph (items 1 and 3), plus enabling
  M5-D's punish-over-extension collapse.
