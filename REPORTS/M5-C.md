# M5-C — Three-action model + CC that catches — Report

## Why this phase existed
M5-B made a macro roster convert its edge through **towers and objectives** (gold-lead
conversion 70.8% → 63.2%). It did *not* fix fights: the first cut of laner roams was reverted
because with **equal move speed and no early crowd control**, proactive plays whiffed — a
healthy target just walks away — and the team that roams most (the macro team) ate the most
whiffs. The diagnostic pinned the constraint: the only signature spell was the ultimate at
level 6, so nothing could **catch** a target during laning.

The fix (designer decision, 2026-07-24) is the **three-action model**: every character now has
auto-attack + one **basic ability** (unlocks early) + the **ultimate** (level 6). CC moves onto
the basic ability for a few jungle/support characters, so a play can lock a target *in lane*.
Design truth: [GDD §3](../GDD.md) and [§6.1](../GDD.md).

## What changed
- **Basic-ability slot on every character** (`data/characters.json`). Same data shape as the
  ultimate — `effect` + `params` + `cooldown` + `unlock` — so it is a *second instance of the
  ultimate machine*, not a new subsystem. `Combat._try_ultimate` generalised to `_try_ability`,
  fired for either slot on its own cooldown/unlock. Reviewable in `tools/data_check.gd --report`
  (new **Basic** column).
- **Four CC carriers** (jungle/support skew) get an active **slow** basic that catches:
  Fenrik (Blood Scent), Thornmaw (Skewer), Gromm (Trample), Vessia (Ensnaring Mist). A slow
  cuts the target's move speed so an equal-speed pursuer closes — the whole point. The other
  **11 characters take a cheap passive** (persistent combat modifier, no activation AI):
  `passive_power` (+damage), `passive_bulwark` (−incoming), or `passive_sustain` (lifesteal).
- **Connectability gate on ganks** (`SimMatch.try_gank`). A gank only launches at a lane where
  it can actually catch someone: a CC carrier is on hand (the jungler, or a CC laner already in
  that lane), or the target is low, or shoved too far up to get home. Uncatchable ganks — the
  whiffs that cost the macro team lane presence for nothing — are no longer launched. This
  falls out cleanly along the roster: a CC jungler (Fenrik, Thornmaw) ganks freely; a farming
  jungler with no CC (Umbra) only ganks a target that is already catchable, exactly its intent.
- **The catch is a timing rule** (learned mid-phase; now GDD §6.1). A slow fired from max
  perception range is spent before the chaser can close, and the even-speed chase just resumes.
  So the slow is **held until the target is at catch range** (`fight.cc_catch_range`), where it
  lands as the target commits to fleeing. Before this fix the CC fired constantly and connected
  ~2% of the time; after it, ganks convert.
- **Metric + viewer.** `tools/batch_run.gd` reports a **gank connect rate** (a call that yields
  a kill by the calling team inside the gank's ~28 s life). The viewer shows a `basic_cast`
  popup (cooler/lighter than the gold ultimate popup) so the two abilities read differently.

All new tunables live in `data/balance.json` (`combat.basic_impact`, `fight.basic_damage_scale`,
`fight.cc_catch_range`, `ganks.connect_low_hp/connect_overext`). Determinism holds
(`tools/check.sh` green); the `sim/` RNG discipline is unchanged.

## The numbers — 200 sims (seeds 5000–5199)
| Metric | M4.5-G | M5-C | Note |
|---|---|---|---|
| **Azure Wolves (macro) win rate** | **30%** | **40%** | recovered +10 toward the 43/57 target |
| Crimson Ravens (mechanical) | 70% | 60% | |
| Gold-lead @15min → win | 70.8% | 59.4% | leads still matter, comeback-friendlier |
| Gank connect rate | (n/a) | 15% | ganks convert; jungle kill-share 7% → **10%** |
| Kills / match | 18.6 | 19.7 | |
| First blood (min) | 4.6 | 4.4 | CC ganks land a touch earlier |
| Match length avg (min) | 26.3 | 24.7 | 196/200 in 20–35 |
| First tower is bot | 26% (M5-B) | 44% | macro converting through the bot tower |
| Assertions (off-map / out-of-lane) | PASS | PASS | |

Kills stay spread across all five roles (mid 40 / carry 30 / top 12 / jungle 10 / support 8 %)
and all map regions. The macro team recovered by making its jungle plays connect **and** by the
snowball softening — a behind team now has a catch of its own to fight back with.

## What to look at in-game (1x)
- A **jungle gank that connects**: the jungler walks in, the CC popup fires (Blood Scent /
  Skewer) as the laner turns to run, the target visibly slows, and it dies or is forced home.
  Contrast with a **whiff**: against a healthy, safe target the gank simply is not launched.
- **Gromm/Vessia (engage supports)** catching in bot-lane skirmishes — the clearest, most
  frequent CC kill, since the bodies are already close.
- The **basic vs ultimate** read: a lighter cyan popup for the catch, the gold popup for the
  level-6 payoff.

## Open design questions (designer calls only)
1. **Blue-side win rate rose to 56%** (was ~49% pre-phase). The stronger, earlier slows amplify
   whoever gets the first play, and blue seems to convert its early ganks slightly better. Side
   balance is not an M5 goal and has its own dials (last tuned in M4.5-G) — flagging it to
   **fix in M5-F** (the balance pass), not now. Do you want it looked at sooner?
2. **Azure at 40%, not yet 43%.** The remaining gap is the *coordination* half: ganks still
   average ~1 follower, so most are 1v1 and connect ~15%. Multi-man convergence + gank
   telegraph (**M5-E**) is what turns the catch into a kill more often for a high-macro roster.
   Is 40% an acceptable M5-C waypoint, with the rest earned in D/E?
3. **Passive assignments** are in `characters.json` (reviewable via `data_check --report`):
   Bastion/Lumen bulwark, Morghast/Vael sustain, the rest power. Do these read right per
   character, or should any change archetype?

## Note for a later phase
Corvyn's ultimate (`aoe_cc` with `cc: slow`) now applies a real slow instead of the flat stun
every CC ult used to apply — a correctness fix that fell out of the unified CC path. He is not
in the signature-pick batch, so it does not affect the numbers above.
