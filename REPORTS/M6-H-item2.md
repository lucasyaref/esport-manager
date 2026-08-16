# M6-H item 2 — laning poke: a real range check and a walk-up

**Status: built, measured, keep-vs-revert call open — not a clean "ship it."** The range gate does
exactly what it was asked to do. The walk-up it required has a much bigger effect on the whole match
than the legibility fix it was meant to be. Designer decides; the commit is deliberately isolated so
reverting it is cheap.

## 1. The bug, restated

`sim/laning.gd::_poke()` traded HP between a laner and the *nearest* enemy laner every
`poke_interval_s` with **no distance check at all**, and never set `last_swing_at` — the field
`Combat.resolve_attacks()` stamps on a landed real swing, which is what the viewer's M6-D2 pose
plumbing reads to show an attack pose instead of only a hit-flash. Net effect (2026-08-15 playtest
diagnosis): lane damage read as instant, distance-free chip, and a body in a close-up almost never
showed an attack pose because the thing dealing most lane damage (poke) never earned one.

## 2. What changed

`sim/laning.gd` and `sim/player_agent.gd` only — `sim/combat.gd` untouched, by scope (a deliberate
boundary; the melee-commitment tuning that landed there separately must not be disturbed).

- **Range gate.** A poke now only lands if the poking agent is within its own
  `character.combat.attack_range` of the victim. That's the poking agent's own real attack range —
  the same number `Combat.resolve_attacks()` gates a landed swing on — not a new
  `laning.poke_range` tunable. Reasoning: "must actually be in range" should mean the same thing a
  real swing already means it; a second, independently-tuned range number would just be a duplicate
  of the same concept with its own drift risk, for no expressive gain (a caster's poke already reads
  as a spell/ranged auto at its real range; a melee laner's poke now genuinely requires standing
  next to the target, same as a real melee swing would).
- **Same swing bookkeeping.** A landed poke now sets `agent.last_swing_at = t` — nothing else. Not
  `target_idx` or `in_combat`: those are `Combat`'s own fields, read every tick by
  `resolve_attacks()` regardless of FSM state, so setting them from `laning.gd` would risk a FARMING
  agent's poke also triggering a second, independent real auto-attack resolution the same tick — an
  interaction with `combat.gd` this task was explicitly scoped away from. `last_swing_at` alone is
  sufficient: `game/main.gd::_anim_states()` keys the attack pose off it exclusively, so the M6-D2
  plumbing picks poke up for free with no viewer change.
- **Walk-up.** A laner in `trade` or `allin` stance (the two "ahead, step up" stances) that isn't
  yet in range now sets a new field, `PlayerAgent.poke_target_pos`, to the victim's live position.
  Recomputed fresh every tick by `Laning.update` (which always runs before `PlayerAgent.update` in
  the tick order — see `SimMatch.run()`), so it's never a tick stale. `PlayerAgent`'s existing
  FARMING movement branch — the same `elif` chain that already lets a gank call or a tempo window
  override the default `lane_stand_pos` walk target — checks this field and, if set, walks there
  instead of the stance's fixed abstract stand point. `freeze`/`back` (the two "hold, don't commit"
  stances) never get a pursuit target — they still poke back reactively if the enemy closes into
  their range, but don't walk to force it, matching their existing design intent ("hold, deny, wait
  for help" / "give ground"). No new movement system: this is one more entry in the FARMING branch's
  existing override chain, same shape as the `roam`/`press` checks already there.

Damage math (`_poke_damage`, the ramp/stance multipliers/floor) is unchanged — the range gate didn't
force a change there.

## 3. Measured (300 sims, seed 5000, before = HEAD at 32576ce, after = this change)

| Metric | Before | After | Δ |
|---|---:|---:|---:|
| Poke connect rate | 44.0% | 3.0% | −93% |
| Avg poke *attempt* distance | 8.11 | 6.27 | (was never gated — many attempts were never in reach) |
| Poke HP traded / match | 17,684 | 1,348 | −92% |
| Laning-phase real swings landed / match¹ | 103.9 | 198.0 | **+90%** |
| Kills / match | 31.8 | 42.1 | **+32%** |
| Kills/min (whole game) | 1.18 | 1.57 | **+33%, further from ~0.85 pro** |
| First blood (avg min) | 3.2 | 1.9 | −41% |
| Kills before 14 min | 23% | 38% | +65% |
| Solo kills | 43% | 52% | +21% |
| First blood, blue/red split | 45% / 55% | 32% / 68% | skews harder |
| Gank connect rate | 26% | 34% | +31% |
| Sandwich connect rate | 34% | 36% | +6% |
| Lane swap rate | 26% | 38% | +46% |
| Match length avg | 27.0 min | 26.8 min | ~flat |
| Blue-side win rate | 57.0% | 56.3% | ~flat |
| `tools/check.sh` | — | PASS | RNG lint, data validation, determinism ×3 seeds, viewer `--selftest` all green |

¹ Instrumentation-only counters (`Combat.resolve_attacks` landing while `agent.state == FARMING`,
`Laning`'s own poke-attempt/connect/HP tallies), added for this measurement pass and reverted before
the commit — not shipped.

## 4. Reading the numbers honestly

The range gate itself is correct and did what it says: "poke connects" used to be a meaningless
100%-whenever-both-present number (no check existed); it now means "actually landed a hit within
real attack range," and it duly collapses for a roster where most lane attack ranges (1.2–5.2) are
far smaller than the 8-unit average distance laners were poking from. That part is not a surprise
and not, by itself, a problem — it's the fix working.

**The walk-up's side effect is the finding that needs a decision.** It nearly doubles real
`Combat`-resolved swings landing while a body is nominally still in the FARMING state, and that
alone explains most of the rest: kills/match up 32%, kills/min up 33% (moving *away* from the pro
target, not toward it), first blood 41% earlier, more of the match's kills happening solo and before
14 minutes. The mechanism, best guess from the shape of the numbers: `Combat`'s own commit decision
(`_wants_to_fight`, unrelated to Laning and untouched here) was already firing on trade/allin laners
before this change — what wasn't happening was the *swing landing*, because the laner was standing
at `lane_stand_pos`'s fixed offset spot, not necessarily within real attack range. The walk-up
effectively pre-pays that approach cost. Once `Combat` decides to commit, the fight is already at
melee/cast distance instead of needing its own few ticks to close — ticks during which, before this
change, a lane often reset or one side disengaged instead of trading. More lane commits now convert
into an actual landed exchange instead of fizzling.

That's arguably closer to the "walk up, land a hit, back off" feel the designer asked for — but the
scale is large enough (every headline batch number moved, and the one number this project has
explicitly tracked toward a pro-play target got worse, not better) that this reads as more than a
legibility fix, and calling it "keep as measured" isn't this report's call to make.

## 5. What's next

Designer reads the numbers (and, if useful, watches a top-lane close-up) and picks:
- **Keep as measured** — the kills/min move becomes a fresh target for the M6-H (1)/(3) pass and any
  later balancing, on the theory that lane fights that actually connect are a real improvement even
  at the cost of moving kills/min.
- **Revert** — this landed as one clean, self-contained commit specifically so that's cheap; nothing
  else in the tree depends on `poke_target_pos` or the new `_engage` shape.

Either way, `sim/combat.gd` was not touched, so this doesn't reopen or interact with the
melee-commitment tuning that shipped separately in M6-H (1)/(3).
