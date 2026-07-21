# MOBA Manager — Backlog (PoC)

Claude Code: work top-down, one milestone at a time. Keep statuses updated (todo / in-progress / done). End every milestone with a runnable build + report in `REPORTS/`.

## M0 — Project skeleton — done
Godot 4 project, folder structure (`sim/`, `game/`, `data/`, `tools/`, `REPORTS/`), git init, headless run script, seeded RNG utility, tick loop stub proving determinism (same seed ⇒ same event log). CI-style check script the designer can ignore.

## M1 — Data model + content v1 — done
Character schema + 15 characters (3/role) in data files. Player schema + 10 players, 2 teams. Loader + validation. Short data report (stat spreads per role).

## M2 — Sim core: map, minions, laning — done
Logical map graph (lanes, jungle camps, river, pits, towers, nexus). Minion waves, farming, gold/XP curves, role assignment to lanes, jungle pathing. Headless output: gold/XP curves per role look sane (carry/mid > support, etc.).

## M3 — Sim core: skirmishes, ganks, objectives, fights, win — done
Gank logic (jungle/roams), skirmish + teamfight resolver (stats, ultimates, mechanics, comp modifiers, seeded variance), Dragon/Baron contests, tower/nexus destruction, full match to victory. Batch runner: 1000 matches → win-rate by side ~50%, length distribution 25–35 min, kill totals plausible. Report numbers.

## M4 — Viewer v1 — done
Map scene, sprite playback from tick stream (interpolated movement), team tint + role marker, HP/level display, animations (Move/Attack/Ultimate/Hurt/Die/Recall), kill feed, clock, gold bar, speed controls (1x/4x/16x/skip). Success = "watchable" per CLAUDE.md criteria.
Built: top-down match viewer (`game/main.gd` + `game/map_view.gd`) plays the deterministic tick stream — champions move on interpolated positions, fights/ganks/objectives/towers/recalls/wards fire off the event stream, with kill feed, live scoreboard, clock, gold bar, result overlay, and 1x/4x/16x/skip + timeline scrub. Runs clean headless. (Correction: the champion bar shipped as a always-full placeholder — there was no HP concept in the sim to drive it. Real HP bars land in M4.5-A.)
Playtested 2026-07-21. Verdict: readable enough to follow, but players don't behave like players — see M4.5.

## M4.5 — Sim depth: space, health, agency — in-progress
From the designer's M4 playtest. Root cause: map positions were decorative — the sim computed outcomes from aggregate power scores. Design truth in GDD §6.1.

Designer calls so far: sim depth before the draft screen · **full spatial combat** · lane HP trading that converts into solo kills · **boundary clamp only** for the map, jungle terrain parked · minions fixed properly as **real marching squads**, not a viewer trick · chases fixed **mechanically** (leash, tower threat, target spread) before any ability kits.

Every phase ends runnable, playtested and committed. Per-phase gate: `tools/check.sh` green, `tools/batch_run.gd --sims=200` (1000 in G), and a designer playtest at 1x — that playtest is the real gate.

- **A — Foundations — done** (`f536b24`): live HP on players (regen, fountain heal, low-HP recall, HP in snapshots); per-character combat stats (`attack_range`, `preferred_range`, `attack_speed`, `fight_role`) + validation; real HP bars in the viewer; minion dots rendered from the aggregate lane front; XP curve retuned (solos were level 12–14 at 30 min, now 17.1–17.6; jungler 16.2; bot lane 15.6).
- **B — Spatial combat engine — done** (`67ccead`): `Combat.resolve()` is gone. Every tick players perceive, decide whether to commit, pick a target, steer to their character's range, and swing; deaths happen at 0 HP. Ultimates fire on conditions. A fight detector clusters engagements so the kill feed still works. Two design rules fell out of it and are now GDD truth: reach is paid for in damage (melee hit harder), and contest an objective only if you can win it. 200-sim batch: 0–3 timeouts, 34.8 min avg, 41.8 kills, first blood 6.9 min, kills spread across all lanes and all five roles. Cost 1.9 s/sim (~32 min for a 1000-sim balance run) — acceptable, and the reason combat perception runs at 5 Hz while attacks stay at 10 Hz.
  - **Known regression, for G**: gold leader at 15 min now wins only ~50% (M3: 66%, GDD target ~65%), and match length runs ~35–37 min, at the top of the 25–35 target. Same cause for both: advantage is weakly coupled to victory because sieging and lane pressure barely exist yet — a team that is behind simply declines fights and farms. Not tunable with `power_item_divisor` (swept 10000/6000/4000, no effect). Expect C–E to restore the coupling; re-measure before touching dials.
- **C — Bounds, towers, ending chases — done**. Four things the designer watched go wrong in the second playtest (2026-07-21), each verified in code first:
  1. *Players walk off the map* — nothing clamps `pos` anywhere in `sim/`, and `Combat._retreat_pos` steers away from enemies, so a player pinned against the edge keeps going. → `SimMap.clamp_pos()` over the playable area, with every position write in `sim/` routed through it (both `PlayerAgent._move_toward` and the combat branch of `PlayerAgent.update`). A few lines; ship it first and alone.
  2. *Turrets deal no damage* — `Combat._deal_damage` is only ever called with a `PlayerAgent` attacker; towers only *receive* damage, in `Objectives._update_siege`. → towers get range + dps and LoL-style aggro: minions first, else the nearest enemy player in range, switching to whoever attacks an allied player inside the zone. A tower kill has no player killer: credit the nearest diver within a generous radius, else emit an empty killer — and guard `game/main.gd:_on_kill`, which today does `kda[killer].k += 1` and would crash on it.
  3. *Infinite chasing* — no leash, no give-up rule, no chase timer exists at all. → break off when the target has been out of attack range for `chase_patience_s`, when the chase has dragged the attacker more than `leash_radius` from where it committed, or when continuing means diving a tower it cannot afford. Reuses the `disengage_until` hysteresis from B; needs `_commit_pos` / `_last_hit_at` on `PlayerAgent`.
  4. *Teamfights are five people chasing one runner* — every ally scores targets with nearly the same formula in `Combat._select_target`. → divide an enemy's score by `1 + focus_penalty * (allies already targeting it)`, read from the previous tick's assignments, so a team splits between the frontline in its face and the carry behind it.
  - Two things fell out of making towers real. **Laners now farm from outside enemy turret range** (`SimMatch.lane_stand_pos`) — walking under a turret is a dive, a fight decision, not something farming does by accident. And a **dive has to be paid for**: you only enter the zone for a target already nearly dead or with better than a 2:1 local power advantage, which is what turns a jungler's arrival into a dive and keeps a laner who merely won the trade out.
  - **Map data fixed as a consequence**: outer towers sat at lane param 0.42/0.58, so the entire laning zone was inside turret range and laners could never reach each other once turrets could shoot. Towers moved to 0.30/0.18/0.08 (mirrored), which is roughly where LoL puts them. Lane push rate raised to match the longer distance (`front_drift` 0.0001 → 0.00018).
  - 40–60 sim batches: no agent ever outside the playable area; 0 timeouts (was 10 mid-phase), 29.3 min avg length, 20 kills, first blood 9.3 min, gold-lead conversion 60% (up from ~50% — towers and dives give an advantage somewhere to land). Tower kills ~3% of all kills, none before 5 min, all during sieges and dives.
- **D — Minions march — todo**: waves stop teleporting to the front. A squad `{team, lane_t, melee_caster, cannon}` replaces the `_incoming` arrival queue in `sim/lane_state.gd` — squads spawn at their base end, walk at `minions.speed`, stop on contact, grind each other down with the existing `combat_kill_rate` / `tower_kill_rate`, and a friendly squad catching a stalled one merges into it. They never leave their lane by construction, which is the "stay in lane, no chasing" the designer asked for. `front_t` **becomes derived** from the leading contact point — load-bearing for `farm_pos`, `try_gank` overextension, `TeamBrain._pushed_lane`, `Objectives._update_siege` and the viewer, all of which must keep working unchanged. Lane snapshot row carries squad positions; `game/main.gd:_minion_dots` draws from those instead of deriving them from `front_t`.
- **E — Lane agency — todo**: unblocked by C and D. Lane stances (push / freeze / trade / back / roam) driven by wave state, relative HP/level and the `laning` attribute; HP trading that converts into **solo kills**; dives that cost tower damage. First real attempt at the gold-conversion regression from B.
- **F — Intent, perception, reaction — todo**: team blackboard on `TeamBrain` — players post intent ("ganking bot, ETA 12s", "committing to drake") and allies react gated by their `macro` attribute, which is how macro becomes visible on screen (GDD Pillar 1). Vision-gated perception via the existing `ward_near`. Objective decisions: fight / trade / give it up. Mid–top roams.
- **G — Rebalance + behavioral metrics — todo**: M3 passed on *outcome* metrics while behavior was broken, so extend `tools/batch_run.gd` with **behavioral** ones — kill distribution by map region, solo kills, kills before vs after 14 min, level at 20/30 min, fight participation and deaths by role, fight count and duration, plus what this pass earns: deaths under tower, average chase length, time spent out of lane. Add assertions for the bugs the designer had to catch by eye: no agent ever outside the playable area, no squad outside its lane, chase length has a finite maximum. Then retune to GDD targets — 25–35 min, ~50% side win rate, ~65% gold-lead conversion — and write `REPORTS/M4.5.md` with before/after behavioral numbers.

## M6 — Draft screen — todo
Pick-only draft UI (order per GDD §5), AI opponent drafting, coach recommendations + follow/ignore modifiers, champion-pool warnings, hand-off into match sim. Post-game result screen (score, KDA, gold graph).

## M7 — PoC polish pass — todo
Pacing/readability tuning from designer playtest feedback, event feed wording, minimal sound hooks (optional), bug pass. Tag `poc-1`.

## Parking lot (PoC+, do not start)
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites.

**Wanted by the designer, deliberately deferred** (revisit after M4.5 lands, before M7):
- **Jungle walls, terrain and chokepoints** — "need wall around the jungle, complexify the map". `SimMap` is lane polylines plus point positions today; there is no notion of walkable space, so there are no corridors and no escapes. Deferred by scope call in M4.5-C, which does boundary clamping only.
- **Basic ability kits** (slow / dash / stun / shield on short cooldowns). The main remaining lever for fight excitement once M4.5-C fixes chases mechanically — equal move speed with no CC is why fights read as one long chase.
