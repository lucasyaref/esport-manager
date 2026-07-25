# MOBA Manager — Backlog (PoC)

Claude Code: work top-down, one milestone at a time. Keep statuses updated (todo / in-progress / done). End every milestone with a runnable build + report in `REPORTS/`.

Full rationale, diagnostics and batch numbers behind completed work live in `CHANGELOG.md` — this file only carries what's needed to know what's done and what's next.

## Status

| Milestone | Status |
|---|---|
| M0 — Project skeleton | done |
| M1 — Data model + content v1 | done |
| M2 — Sim core: map, minions, laning | done |
| M3 — Sim core: skirmishes, ganks, objectives, fights, win | done |
| M4 — Viewer v1 | done |
| M4.5 — Sim depth: space, health, agency | done |
| M5 — Macro play: cross-map coordination | paused — A–D done, E–G to-do (resumes after M5.5) |
| **M5.5 — Viewer v2: combat readability & juice** | **in-progress — A–G done, designer playtest is the gate** |
| M6 — Draft screen | to-do |
| M7 — PoC polish pass | to-do |

## Now — M5.5: viewer v2 (combat readability & juice)

From the designer's 2026-07-25 playtest (remarks 1, 2, 4): fights and CC aren't legible enough to judge the sim underneath them, so this is inserted **before M6** and before the remaining M5 macro phases — the 1x playtest is the real gate, and sim work the designer can't see can't be gated. Sim stays the source of truth (Pillar 3): playback/rendering only, with one deliberate exception (phase A's separation).

**Phases** (each runnable + committed; the designer's 1x playtest is the milestone gate):
- **A — Separation: champions stop stacking — done.** Shipped as a **playback layout pass** (`MatchViewer._spread_bodies`), not a sim mechanic. The sim-side version was built and measured first: same 200 seeds, it cost the macro team 6 points (36.5% → 30.5%), undid M5-D's blue-side fix (49.5% → 43.5%) and pushed snowball to 71.1%. Bodies having volume is a balance decision, so it is **parked for M5-E/F** as a deliberate lever (designer question in `REPORTS/M5.5.md`).
- **B — The attack beat + the catch — done.** Snapshot rows carry live combat state (target, last swing, stun/slow expiry, in-combat/disengaging); the viewer draws auto-attacks as a readable beat between attacker and target, and CC reads as a **catch** — a lock/slow mark on the victim plus a tether back to the caster (new `cc_applied` event). Answers remark 4 ("I did not see the control").
- **C — Ultimate impact — the "wow" — done.** `ultimate_cast` carries position/radius/targets hit; the viewer lands it with weight, distinct per effect family (aoe shockwave, single-target beam, execute, heal/shield bloom, self-steroid aura) and clearly bigger than the basic-ability beat.
- **D — Structure HP — done.** Tower and nexus HP in the snapshot; the viewer draws it, so a siege reads as sustained pressure and a dive under a chipped tower reads as a race instead of a sudden pop.
- **E — Placeholder combat sprites — done.** Per-role procedural silhouette + facing, so a fight reads as characters rather than dots; the data-driven `sprite` path per character still overrides it with no code change (CLAUDE.md).
- **F — Report + sign-off — done.** `REPORTS/M5.5.md` written; 200 sims reproduce M5-D's baseline
  exactly and a 30-seed fingerprint matches the pre-M5.5 commit, so everything added to `sim/`
  is report-only.
- **G — Playtest corrections (2026-07-25 notes) — done, awaiting the designer's second 1x
  playtest (the gate).** Root cause of three of the four notes was one thing: **playback at 1x
  runs 4x sim-time**, and every visual lifetime was written in sim ticks, so an ult impact was on
  screen 0.65 s and an attack beat 0.12 s. Lifetimes are now sized in real seconds at 1x and
  stretch with the speed button (capped at 4x). Plus:
  - The amber "fighting" halo meant `in_combat`, which the sim sets on standoffs too — only **30%
    of in-combat player-frames are real exchanges**. It now means *trading blows* (recent swing +
    still committed), in hot red so it stops competing with the amber CC mark; backing off draws
    retreat chevrons.
  - **Damage is visible**: playback diffs snapshot HP into floating numbers and a hit-flash
    ("the life does not move" — it moved 2 px a swing on a 22 px bar).
  - **Structures read**: turrets drain like a battery, rubble when destroyed, an orange pulse on
    anything losing HP this second, a permanent side-panel readout of turrets standing + nexus HP
    for both sides, and feed lines for every turret, "nexus exposed", and nexus 75/50/25/10%.
  - **Ultimates land**: white-hot flash on the caster, name on its pill for 2 s, one feed line
    each with its body count.
  - `--selftest` extended to assert all of the above (and to print the closing feed lines, so
    "can this ending be narrated?" is checked headlessly every run).
  - **Designer answer recorded**: drawn separation is accepted; sim-side body volume moves to
    M5-E/F as a tunable lever.
  - **Finding for M5-G, not fixed here**: the sim ends games by a slow minion grind — over 12
    seeds the losing nexus bleeds for 6 min on average (13 min worst case), often with no champion
    near it, and turrets stall at 1–9 HP of 3400 for minutes. That is balance, so it belongs to
    M5-G, not to a readability milestone.

Guardrails: no external art deps (placeholder / procedural only), the viewer reads only the tick + event stream and never mutates the sim, 1x ≈ 8-min pacing preserved, plus the standing guardrails below.

## Next

### M5 — macro play, phases E–G (paused, resumes after M5.5)

From the designer's M4.5 playtest (2026-07-23): bots stay lane-bound and passive, no pro-style coordinated cross-map plays. This is also the **macro win-vector** — the fix for the mechanics-over-macro win-split imbalance (target ~43/57 azure/crimson; last measured 36.5% after M5-D). Individual perception/blackboard already exist (M4.5-F); M5 adds *team-level* intent.

**Locked decisions still governing remaining phases:**
- **Blend gating** — a deterministic coordination baseline always fires (every team reads as a team on screen); each roster's `macro` scales *quality and frequency* on top. This is the lever on the win-split target.
- **Three-action model** — every character has auto-attack + one basic ability (active or passive, unlocks early) + ultimate (level 6). CC lives on the basic ability for a few jungle/support characters, so ganks can catch a target *in lane*. This is what makes M5-E's roams and M5-F's ganks connect instead of whiff (a first attempt at roams pre-dated this and was reverted for exactly that reason — see CHANGELOG.md).
- **Lane assignment** is a `TeamBrain.lane_assignment` team state (`standard` / `bot_top_swap` / `bot_mid_swap`), objective-triggered (bot duo takes bot T1 with the jungler, then rotates), with enemy mirroring — already shipped (M5-B, reframed in M5-D). Treat as existing infrastructure.
- A **base-defense priority** and a **punish-over-extension collapse** exist in code; the collapse is currently **gated off** (M5-D found it too blunt as a team-wide yank) — M5-F is expected to enable it properly as part of the multi-man layer.

**Remaining designer items** (item 4, lane swap, shipped in M5-B/D):
- **Item 1 — Gank coordination that reads as communication.** Followers avg only 1.07 today. Telegraph the gank earlier (post on approach/path, not at arrival) and have the target laner set up for it (freeze/shove to match the incoming jungler). → M5-F.
- **Item 2 — Proactive roams / opportunity detection.** A player with lane priority leaves lane when the team brain sees an opening (enemy overextended nearby, a local numbers edge) — a choice with priority as its cost, not random wandering. → M5-E.
- **Item 3 — Coordinated multi-man moves.** The team brain dispatches 2–3 players to converge on one lane/objective, with a target, a committed set, and a window; participation gated by `macro`. → M5-F.
- **Item 5 — Support mobility.** The support is the prime roamer — a roam cadence gated by `macro` and lane state, firing when there's a play, not always. → M5-E.

**Phases:**
- **M5-E — Proactive roams + tempo trades** (items 2 & 5). Macro-gated support/laner roam that fires only on connectable plays, with a tempo payoff (kill/recall → tower/plate pressure) and the cross-map trade reading on screen.
- **M5-F — Coordinated multi-man moves + gank telegraph** (items 1 & 3). `TeamBrain` dispatches 2–3 to converge (target, committed set, window), macro-gated; the gank is telegraphed on approach and the target sets up. Enable M5-D's punish-over-extension collapse here.
- **M5-G — Balance pass + batch sign-off + report.** Re-measure the win-split (target ~43/57, last 36.5%) and gold-lead conversion (target ~65%, last 66.3%); extend metrics (connect rate, tempo trades, multi-man plays); assertions; `REPORTS/M5.md`; designer 1x playtest gate.
  Two items inherited from M5.5: **a decisive endgame** (measured 2026-07-25: the losing nexus bleeds for ~6 min under minion chip alone, worst case 13; turrets stall at ~0 HP for minutes) and **sim-side body volume as a tunable** (measured: −6 pts macro win, blue-side 49.5→43.5%, conversion 66.3→71.1%, but gank connect 16→22% and first-tower-bot 10→27%).

Standing guardrails: pure-GDScript `sim/`, determinism, `tools/check.sh`, headless batch, data-driven (new tunables → `data/balance.json`). GDD §6.1 has the macro model.

### M6 — Draft screen — to-do
Pick-only draft UI (order per GDD §5), AI opponent drafting, coach recommendations + follow/ignore modifiers, champion-pool warnings, hand-off into match sim. Post-game result screen (score, KDA, gold graph).

### M7 — PoC polish pass — to-do
Pacing/readability tuning from designer playtest feedback, event feed wording, minimal sound hooks (optional), bug pass. Tag `poc-1`.

## Parking lot (PoC+, do not start)
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites.

**Wanted by the designer, deliberately deferred** (revisit after M4.5 lands, before M7):
- **Jungle walls, terrain and chokepoints** — "need wall around the jungle, complexify the map". `SimMap` is lane polylines plus point positions today; there is no notion of walkable space, so there are no corridors and no escapes. Deferred by scope call in M4.5-C, which does boundary clamping only.
- **Basic ability kits** (slow / dash / stun / shield on short cooldowns). *Being brought forward in M5* via the three-action model (2026-07-24) — the basic-ability slot is the vehicle for early CC. M5 ships CC (slow/stun) on a few characters; the wider kit variety (dash/shield/etc. across the roster) stays deferred to post-PoC.
