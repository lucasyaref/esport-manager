# M5-D — Behavioural corrections from the 2026-07-25 playtest — Report

## Why this phase existed
Your 1x playtest after M5-C surfaced six things. Two were a **readability wall** (fights and
CC not legible) → the new **M5.5 viewer milestone**, done before the draft. Three were sim
behaviours that looked wrong on screen — this phase fixes them. One (visuals for CC) is M5.5.

The corrections, each tied to a remark:

## What changed

### 1. Jungler no longer yo-yos (remark 5)
*You saw:* the jungler clears bot-side, ganks top, then walks **all the way back** to bot-side
while top-side camps are up.

*Cause, confirmed in code:* after a gank the jungler kept its **pre-gank camp target** — it had
committed to a bot-side camp, left to gank top, and on return still pathed to that far camp
instead of the nearest one. → `gank_over()` now drops the stale target
([player_agent.gd](../sim/player_agent.gd)), so the jungler re-picks the **nearest** camp from
where it actually stands. After a top gank it clears top-side, as you'd expect. Pure readability
fix, no RNG.

### 2. The lane swap is now objective-triggered, not an opening (remark 3)
*You saw:* "botlane always goes top; the swap concept is wrong."

*Cause, confirmed:* the swap was an **opening** swap fired at t=0 and mirrored by the enemy, so
in a swap game **both** bot duos teleported top before minions — decoupled from ever taking a
tower. That is the exact "always goes top" you caught.

*Your model, now built:* the swap is **causal**. A team plays bot standard, takes the enemy's
**bot outer (bot T1)**, and *only then* rotates its bot duo onto a lane that still has a tower to
snowball — **top if the enemy top outer stands, else mid**. The team that wins bot first dictates
the swap; the other **reads it and matches** so it is not left 2v1. Both decisions are macro-gated
and one-shot. New `bot_mid_swap` formation for the else-mid case; the machinery is the same
formation table, so 1-3-1 etc. still drop in later. (GDD §6.1 updated.)

### 3. Teams protect their base; over-extenders are (soon) punished (remark 6)
*You saw:* late game, nobody defends the base, and an over-extended pusher isn't punished.

*Cause, confirmed:* a siege opportunity **always outranked** defending your own base — a team
would keep pushing the enemy's tower while its own nexus was hit. And there was **no** logic at
all for collapsing on an isolated deep enemy.

*Fix:* the team brain now checks **home danger first**. When a *deep* tower of its own (inner,
base, or the nexus) is under real minion+player pressure, **defending it outranks any siege or
objective** — you don't trade a baron for your own nexus. This is the "protect the base" half,
and it ships on. The **punish-the-over-extension** half is *built and wired* but **gated off this
phase** — measured, a blunt team-wide collapse drags the macro team (details below); it belongs
with M5-F's multi-man pick play (committed subset + window), which is the right vehicle. M5-F only
turns the dial.

## The numbers — 200 sims (seeds 5000–5199)
| Metric | M4.5-G | M5-C | **M5-D** | Note |
|---|---|---|---|---|
| **Azure Wolves (macro) win** | 30% | 40% | **36.5%** | slight dip; opening-swap prop removed (below) |
| Crimson Ravens (mechanical) | 70% | 60% | 63.5% | |
| **Blue-side win** | ~48% | **56%** | **49.5%** | ✅ M5-C's blue-side flag is gone |
| **Gold-lead @15 → win** | 70.8% | 59.4% | **66.3%** | ✅ back on the ~65% target |
| Match length avg (min) | 26.3 | 24.7 | 26.9 | 197/200 in 20–35, 0 timeouts |
| Kills / match | 18.6 | 19.7 | 22.0 | |
| First blood (min) | 4.6 | 4.4 | 4.8 | |
| First tower is bot | 44% | 44% | 10% | expected — see below |
| Lane swap rate (team-games) | — | — | 24% | now bot-tower-triggered |
| Gank connect rate | 15% | 16% | 16% | |
| Assertions (off-map / out-of-lane) | PASS | PASS | **PASS** | |

Kills stay spread across roles (mid 37 / carry 32 / top 12 / jungle 10 / support 8 %) and regions.
Determinism holds; `tools/check.sh` green.

**"First tower is bot" fell 44% → 10%, and that's correct, not a regression.** In M5-C the *opening*
swap made bot a 2v1, so bot cracked first. With bot a real 2v2 again, the 1v1 solo lanes crack
first (first tower ~5.6 min, mostly top/mid) — exactly like real solo-lane snowballs. The swap no
longer needs bot to be *first*; it fires whenever a team takes the enemy bot outer (24% of
team-games) and rotates from there.

## The balance story (please read — it's mostly good news)
Fixing the swap correctly moved the win rates, and the net is **better than M5-C on three dials
out of four**:

- ✅ **Blue-side win 56% → 49.5%.** The M5-C flag ("blue-side crept to 56%") is *gone* — it was
  the opening swap amplifying whoever got the first play. Removing it re-balanced the sides for
  free.
- ✅ **Gold-lead conversion 59.4% → 66.3%** — back on the ~65% target.
- ➖ **Azure (macro) 40% → 36.5%** — a small dip, and an *honest* one. That extra ~4 points in
  M5-C came from the **opening-swap hack you flagged as wrong** (both bot duos top at minute
  zero) creating an early 2v1 snowball. It's gone, so Azure sits a little lower. The
  objective-triggered swap is correct but **macro-neutral right now** — it fires for *whoever
  wins bot first*, and in a real 2v2 bot lane that's often the mechanical team. Azure turns the
  swap into an *advantage* only once it can reliably **win bot first** and convert roams/multi-man
  — which is **M5-E/F**, the "rest earned in D/E" the M5-C report already promised. I did **not**
  prop this back up with the hack.

**Two things I tried and gated off**, because on a 60-sim probe both dragged Azure further (to
25% together):
- A **jungle bot-focus gank-bias** to make bot T1 fall first. It *backfired*: sending the jungler
  bot starves the 1v1 solo lanes, which then crack their towers first (first-tower-is-bot fell to
  10%, not rose). Bot focus needs to be *coordinated bot-taking* (M5-E), not a gank die-roll.
- The **punish-over-extension collapse** (see remark 6), for the reason given there.

Everything else stays healthy: length 26.9 min, 0 timeouts, kills 22, first blood 4.8 min,
determinism holds, assertions PASS (no agent off-map, no squad out of lane).

## What to look at in-game (1x)
- **Jungle path:** after a gank, the jungler now clears the **nearest** camps to where it ganked,
  not a round trip back across the map.
- **The swap as a *consequence*:** watch a team take **bot T1**, then its bot duo **walk to top**
  (or mid) to hit the next tower — instead of both botlanes leaving at minute zero. If the enemy
  is sharp, it matches the rotation.
- **Base defense (late):** when your nexus/inner tower is under pressure, the team **collapses
  home** instead of chasing a siege on the far side.
- Note: CC / spell legibility is still the M5.5 job — this phase is behaviour, not visuals.

## Open design questions (designer calls only)
1. **Azure at 36.5%, down ~4 from 40%.** The honest baseline after removing the opening-swap
   hack; the correct macro advantage is earned in M5-E/F (and side-balance + gold-conversion both
   *improved*). Are you OK carrying this small dip through D→E→F, or should I prioritise the M5-E
   bot-take + roams to claw it back sooner?
2. **Punish-over-extension deferred to M5-F.** Remark 6's "protect the base" ships now; the
   "punish the over-extended pusher" rides on M5-F's multi-man convergence. Good, or do you want a
   simpler version visible sooner even if rough?
3. **Swap target rule:** after taking bot T1 I send the bot duo **top if top T1 stands, else mid**.
   Does that priority read right, or would you rather they always contest mid (shorter, more
   central) once bot is won?
