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

## M4.5 — Sim depth: spatial combat, HP, lane agency, intent — in-progress
From the designer's M4 playtest. Root cause: map positions were decorative — the sim computed outcomes from aggregate power scores. Design truth in GDD §6.1. Designer calls: sim depth before the draft screen, **full spatial combat**, lane HP trading that converts into solo kills.

- **A — Foundations — done**: live HP on players (regen, fountain heal, low-HP recall, HP in snapshots); per-character combat stats (`attack_range`, `preferred_range`, `attack_speed`, `fight_role`) + validation; real HP bars in the viewer; minion dots rendered from the aggregate lane front; XP curve retuned (solos were level 12–14 at 30 min, now 17.1–17.6; jungler 16.2; bot lane 15.6).
- **B — Spatial combat engine — todo**: replace the instant `Combat.resolve()` with per-tick threat scan, target selection, steering to preferred range, attacks, condition-driven ultimates and disengage. Fight detector keeps the event stream intact. Performance gate: time a 200-sim batch before committing.
- **C — Lane agency — todo**: lane stances, HP trading, solo kills, tower aggro and dives.
- **D — Intent, perception, reaction — todo**: team blackboard (post/read intent, gated by `macro`), physical ganks with ally reaction, vision-gated objective decisions (fight / trade / give), mid-top roams.
- **E — Rebalance + behavioral metrics — todo**: extend the batch runner with *behavioral* metrics (kill distribution by region/lane, solo kills, kills before vs after 14 min, level at 20/30 min, fight participation by role), then retune to GDD targets. M3's numbers do not survive B–D.

## M6 — Draft screen — todo
Pick-only draft UI (order per GDD §5), AI opponent drafting, coach recommendations + follow/ignore modifiers, champion-pool warnings, hand-off into match sim. Post-game result screen (score, KDA, gold graph).

## M7 — PoC polish pass — todo
Pacing/readability tuning from designer playtest feedback, event feed wording, minimal sound hooks (optional), bug pass. Tag `poc-1`.

## Parking lot (PoC+, do not start)
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites.
