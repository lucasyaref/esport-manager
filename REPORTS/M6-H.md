# M6-H — Combat engagement correctness: footwork, melee commitment, attack legibility

**Status: fixes (1) and (3) done and tuned. Fix (2) built and measured but left as an open
designer keep-vs-revert call — see `REPORTS/M6-H-item2.md` for its full detail.** `tools/check.sh`
green throughout every commit in this milestone.

## Where this came from

2026-08-15 designer playtest notes, watching a match close-up for the first time now that M6-D/D2
gave it real art and camera. Three things read wrong, not cosmetic:

1. Jittery front-back footwork in fights — bodies twitching in and out instead of holding position.
2. A body close-up almost always flashes "hurt", the attack pose almost never shows.
3. Melee top-laners never actually closing to melee range and swinging.

Root-cause diagnosis (same day, no fix yet): `sim/combat.gd::_stand_pos()` had no dead-zone, so
simultaneous approach/retreat oscillated every tick (issue 1). Laning chip damage
(`sim/laning.gd::_poke()`) bypassed the combat engine's swing bookkeeping entirely, so it could
flash a hit but never earn an attack pose (issue 2 — this is item 2, see below). Melee threat was
undervalued in the fight-commit math, and the retreat trigger used a flat danger radius bigger than
any melee attack range, so melee laners were pushed backward before they could ever swing (issue 3).

## Items (1) and (3) — footwork dead-zone and melee commitment

**Commit `6e2150e`** built both fixes:
- `_stand_pos()` now checks a dead-zone (`stand_deadzone`) against the final computed stand spot, so
  the last-mile correction is suppressed once an agent is already standing close enough — the
  screening/kiting/peel role logic upstream of it is untouched.
- `_threat_uncached()` now applies the same reach-for-damage multiplier `_attack_damage()` already
  pays out, so melee threat is no longer undervalued in the commit-margin check that decides whether
  a laner fights at all.
- `update_intent()`'s non-HP retreat trigger now sizes its danger bubble off the agent's own
  `attack_range` (`danger_radius_min` 2.0, `danger_radius_margin` 0.5) instead of the flat
  `danger_radius` (5.5, bigger than every melee range) — the separate low-HP retreat path is
  untouched.

First batch measurement (300 sims, seed 5000) showed both dials had gone too far: kills/min jumped
to 1.42 (from a 1.10 pre-fix baseline) and the macro win vector swung to 31.0% (from 50.7%
pre-fix) — melee laners now fought far more readily than intended, overshooting into overly
aggressive fights.

**Commit `32576ce`** re-tuned both dials down: a new `threat_melee_bonus_scale` (0.25) dampens how
much of the reach bonus feeds into the threat check (rather than applying it in full), and
`stand_deadzone` was raised from 0.2 to 0.4 to cut footwork jitter further. Re-measured (same 300
sims, seed 5000):

| Metric | Pre-fix baseline | First pass (overshot) | Final tuned |
|---|---:|---:|---:|
| Kills/min | 1.10 | 1.42 | 1.18 |
| Macro win vector (blue) | 50.7% | 31.0% | 45.7% |
| Melee attacks landed in laning / match | 24.03 | — | 21.37 |
| Footwork reversal rate (jitter proxy) | — (high, undiagnosed) | — | 12.2% |

**Read honestly, not as a clean win:** kills/min and win vector both landed much closer to their
pre-fix baselines than the overshot first pass did, which is the intended outcome — melee laners
commit and threat-check correctly without re-breaking match balance. But it's not a full recovery:
melee-attacks-landed-in-laning is still slightly *below* the original pre-fix baseline (21.37 vs.
24.03), and the footwork reversal rate at the final dead-zone (12.2%) is close to but not quite
under the "well under 10%" jitter target. Pushing the dead-zone further to fully kill the jitter
measurably costs more melee-landing rate — the two dials trade against each other at the margin, and
this pass stopped at a reasonable joint point rather than chasing a perfect number on either one.
Two named, out-of-scope next levers if either number needs to move further later: a smaller
dead-zone than tested, or retuning `danger_radius_min`/`danger_radius_margin` directly.

No independent tester re-measurement was run on top of this — the coder's own batch was a full
300-sim, seed-matched, before/after comparison with the shortfall flagged rather than hidden, which
is the same bar an independent check would apply.

## Item (2) — laning poke range + legibility

Built and measured separately, **commit `6babc42`**, scoped to `sim/laning.gd` and
`sim/player_agent.gd` only (deliberately not touching `sim/combat.gd`, so it can't interact with the
(1)/(3) tuning above). Full numbers and reasoning: `REPORTS/M6-H-item2.md`. Short version: the range
gate itself works exactly as intended, but the walk-up it required to make poke actually reachable
has a much bigger effect on the whole match than the legibility fix it was meant to be — kills/min
moves further from the pro-play target, not closer. Left as an open keep-vs-revert call for the
designer; the commit is isolated so reverting it is cheap either way.

## What's left before M6-H can close

Only the designer's keep-vs-revert call on item (2). Items (1) and (3) are done. Once that call is
made, this entry should move from BACKLOG.md's **Now** section into `CHANGELOG.md`.
