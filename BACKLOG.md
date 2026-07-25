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
| **M5 — Macro play: cross-map coordination** | **in-progress — A–D done, E in progress, F–G to-do** |
| M5.5 — Viewer v2: combat readability & juice | done (playtest gate passed 2026-07-26; A–H in CHANGELOG.md) |
| M6 — Draft screen | to-do |
| M7 — PoC polish pass | to-do |
| M8 — Highlights & the close-up view | scoped, to-do (phase A pulled forward next to M5-G) |

## Now — M5: macro play, phase E (the sandwich)

M5.5 (viewer v2) is **done**: the designer's 2026-07-26 playtest passed it ("much better for readability"), the last note was answered in phase H, and the narrative moved to `CHANGELOG.md`. M5 resumes at phase E, whose spine is the designer's named play — the **sandwich** (item 6 below).

Carried out of M5.5 into M5: **sim-side body volume as a tunable lever** (measured: −6 pts macro win, blue-side 49.5→43.5%, conversion 66.3→71.1%, but gank connect 16→22% and first-tower-is-bot 10→27%) and, for M5-G, **a decisive endgame** (phase H's doorstep change is the first half of it).

## Next

### M5 — macro play, phases E–G (active again since 2026-07-26)

From the designer's M4.5 playtest (2026-07-23): bots stay lane-bound and passive, no pro-style coordinated cross-map plays. This is also the **macro win-vector** — the fix for the mechanics-over-macro win-split imbalance (target ~43/57 azure/crimson; last measured 36.5% after M5-D). Individual perception/blackboard already exist (M4.5-F); M5 adds *team-level* intent.

**Locked decisions still governing remaining phases:**
- **Blend gating** — a deterministic coordination baseline always fires (every team reads as a team on screen); each roster's `macro` scales *quality and frequency* on top. This is the lever on the win-split target.
- **Three-action model** — every character has auto-attack + one basic ability (active or passive, unlocks early) + ultimate (level 6). CC lives on the basic ability for a few jungle/support characters, so ganks can catch a target *in lane*. This is what makes M5-E's roams and M5-F's ganks connect instead of whiff (a first attempt at roams pre-dated this and was reverted for exactly that reason — see CHANGELOG.md).
- **Lane assignment** is a `TeamBrain.lane_assignment` team state (`standard` / `bot_top_swap` / `bot_mid_swap`), objective-triggered (bot duo takes bot T1 with the jungler, then rotates), with enemy mirroring — already shipped (M5-B, reframed in M5-D). Treat as existing infrastructure.
- A **base-defense priority** and a **punish-over-extension collapse** exist in code; the collapse is currently **gated off** (M5-D found it too blunt as a team-wide yank) — M5-F is expected to enable it properly as part of the multi-man layer.

**Remaining designer items** (item 4, lane swap, shipped in M5-B/D):
- **Item 1 — Gank coordination that reads as communication.** Followers avg only 1.07 today. Telegraph the gank earlier (post on approach/path, not at arrival) and have the target laner set up for it (freeze/shove to match the incoming jungler). → M5-F.
- **Item 2 — Proactive roams / opportunity detection.** A player with lane priority leaves lane when the team brain sees an opening (enemy overextended nearby, a local numbers edge) — a choice with priority as its cost, not random wandering. → M5-E.
- **Item 6 — The sandwich (designer, 2026-07-26), the concrete shape of items 2 + 3.** "Red mid is pushing blue's T2, the blue jungler is on blue buff or in the river, blue mid is defending T2 — this is a *perfect position* for sandwiching red mid; it should call for a gank." Designed in GDD §6.1; the scoping call is that it is **one detector plus a cut-off destination**, not a new subsystem:
  1. **Detector (board state, evaluated on the team brain's tick):** an enemy laner whose position is deeper than a threshold into our half *and* separated from its own nearest standing tower; our laner in that lane alive and behind our own tower; a free third body (jungler/support, not mid-camp, not mid-objective) whose ETA to the cut-off point beats the target's ETA home; no enemy body closer to the target than ours. Score = depth × numbers edge, cost = lane priority surrendered; `macro_gate` decides whether the team sees and takes it.
  2. **Cut-off destination (the actual new mechanic):** the dispatched body is sent to a point *between the target and its home* — a lane param on the target's retreat side — instead of at the target. That is what makes a catch possible at equal move speed, and it is cheap: lane params already exist, no pathfinding (GDD scope guard holds).
  3. **The laner sets up:** it is told the play is coming (blackboard, on approach — the same telegraph item 1 wants), holds the target rather than backing off, and commits when the cut-off lands.
  4. **Payoff and honesty:** a landed sandwich converts to tempo (tower/plate pressure or a recall bought); a whiffed one costs priority and shows on screen as it should. New metrics: sandwiches called / connected / killed per match, followers per play, priority lost.
- **Item 3 — Coordinated multi-man moves.** The team brain dispatches 2–3 players to converge on one lane/objective, with a target, a committed set, and a window; participation gated by `macro`. → M5-F.
- **Item 5 — Support mobility.** The support is the prime roamer — a roam cadence gated by `macro` and lane state, firing when there's a play, not always. → M5-E.

**Phases:**
- **M5-E — The sandwich, proactive roams + tempo trades** (items 6, 2 & 5). *E1 (the sandwich) is built — detector, cut-off destination, macro-gated call, feed line and batch metrics; report in `REPORTS/M5-E.md`.* Item 6's detector and cut-off destination come first — it is the designer's named play and the sub-mechanic (arrive between the target and its home) the rest depends on; then the macro-gated support/laner roam that fires only on connectable plays, with a tempo payoff (kill/recall → tower/plate pressure) and the cross-map trade reading on screen.
- **M5-F — Coordinated multi-man moves + gank telegraph** (items 1 & 3). `TeamBrain` dispatches 2–3 to converge (target, committed set, window), macro-gated; the gank is telegraphed on approach and the target sets up. Enable M5-D's punish-over-extension collapse here.
- **M5-G — Balance pass + batch sign-off + report.** Re-measure the win-split (target ~43/57, last 36.5%) and gold-lead conversion (target ~65%, last 66.3%); extend metrics (connect rate, tempo trades, multi-man plays); assertions; `REPORTS/M5.md`; designer 1x playtest gate.
  Two items inherited from M5.5: **a decisive endgame** (measured 2026-07-25: the losing nexus bleeds for ~6 min under minion chip alone, worst case 13; turrets stall at ~0 HP for minutes) and **sim-side body volume as a tunable** (measured: −6 pts macro win, blue-side 49.5→43.5%, conversion 66.3→71.1%, but gank connect 16→22% and first-tower-bot 10→27%). M8's scoping added a third: **the teamfight does not exist** — over 60 matches, *no* fight reached six participants and 92% of kill-moments are a single death (`REPORTS/M8-scoping.md`), so M5-E/F must be measured on "does a big fight ever happen", and M8-A's scorer is the instrument that measures it.

**New M5-G metric, from M8-A:** moments-per-match and their shape (deaths, participants, spread over the game clock). "Does this match contain 5–10 things worth watching?" is a balance question before it is a viewer question.

Standing guardrails: pure-GDScript `sim/`, determinism, `tools/check.sh`, headless batch, data-driven (new tunables → `data/balance.json`). GDD §6.1 has the macro model.

### M6 — Draft screen — to-do
Pick-only draft UI (order per GDD §5), AI opponent drafting, coach recommendations + follow/ignore modifiers, champion-pool warnings, hand-off into match sim. Post-game result screen (score, KDA, gold graph).

### M7 — PoC polish pass — to-do
Pacing/readability tuning from designer playtest feedback, event feed wording, minimal sound hooks (optional), bug pass. Tag `poc-1`.

### M8 — Highlights & the close-up view — scoped, to-do

Designer direction, 2026-07-25: a **second view**. The overview stays what it is (accelerated, whole map, silhouettes); 5–10 times a match the viewer drops into a **highlight** — zoomed on the action, characters as real sprites with animations and spell effects, played at **real speed** for ~30 s max. Ganks that turn into kills, teamfights, big fights. Actions are scored, the top 5–10 are selected, and anything under an absolute threshold is dropped even if it made the top 10. Full scoping, measurements and open questions: `REPORTS/M8-scoping.md`. Design model: GDD §7.2.

**Reference target named by the designer (2026-07-25): *Teamfight Manager 2*** — written up in GDD §7.3, evidence in `docs/reference/`. It corrects one assumption in this plan: it is **one renderer with a continuous zoom and an auto-camera**, not two views. So "highlight" = the camera director choosing a focus + the speed dropping, and the two modes share every line of code. It also adds three items to the phases below (minimap, kill banner, transport/replay) and confirms two things already flagged: **terrain is a prerequisite** for the close view, and **the sprite bar is low** — tiny pixel characters, not detailed art.

**Why here in the plan** (and the one phase that moves earlier):
- The **selection layer is cheap and useful now** — it is pure analysis of the sim's own event stream, headless-testable, and it doubles as a balance metric. **M8-A ships alongside M5-G**, not after M7.
- The **view layer is expensive, art-dependent, and premature until the sim earns it.** Measured over 60 matches: 92% of kill-moments are a single death and **no fight reached six participants**. Built today, the reel would be eight 2v1 ganks. **M5-E/F are a hard prerequisite** — the missing piece is the plays, not the camera.
- Ordering assumes the PoC exists to prove the loop *to the designer*. If it exists to **show someone else**, the zoomed fight beats the draft screen as a demo and M8 should jump ahead of M6 — question 1 in the scoping report.

**Phases:**
- **M8-A — Highlight scoring (headless, no view).** New pure module `sim/highlights.gd` (or `tools/` — it reads sim output, it does not run inside the sim): cluster events into candidate moments, score them, select with spacing + diversity + an absolute floor. Tunables in `data/highlights.json`. Batch report over 200+ sims: moments per match, kinds, scores, spread over the clock. **Deterministic — same seed ⇒ same reel.** Gate: the designer reads a text reel of one real match ("07:42 — jungle gank bot, 2 kills") and says those are the moments they'd want to watch. No art, no camera, no risk.
- **M8-B — The camera.** `MapView`'s world→screen transform becomes a camera (centre, **continuous zoom**, smoothing, follow-a-point); overview is the camera fitted to the world, so nothing changes visually on day one. Zoom-aware sizing for everything currently clamped in pixels. Manual zoom in/out controls, click-or-hotkey to follow a player (TFM2 binds F1–F10), and — because zooming in loses the map — a **minimap** with player dots, the viewport rectangle and objective timers. The minimap is a requirement of this phase, not polish.
- **M8-C — Real speed + the director.** A sub-1x playback speed (today's 1x is already **4× sim-time**; real speed is 0.25× of it), visual lifetimes rescaled below the current 4× cap, snapshot cadence raised to one per tick for viewer runs. An **auto-camera director** consumes M8-A's scored moments: it pushes the camera in and drops the speed for pre-roll (the approach) + action + aftermath, then pulls back out. Auto-camera is a toggle — manual camera always available. On-screen framing (what this highlight is, who it's about) and a skip control. Both pacing modes fall out of the same machinery: **full match** (highlights add ~3.5 min on top) and **highlights-only** (jump between moments, ~4–5 min a match). Transport to match the reference: skip-to-start / rewind / skip-to-end over the existing slider, which makes **"replay that highlight"** nearly free.
- **M8-D — Close-up actors.** Characters read as characters at 4× zoom: animation states (idle / run / attack / cast / hurt / die / recall), wind-up telegraphs, facing **reported by the sim** rather than inferred by the viewer. Default is richer *procedural* bodies (no art dependency); the `sprite` data field still overrides with real art and no code change (CLAUDE.md). **Blocked on designer question 3** (procedural vs. real sprite sheets) — the answer changes the actor contract, not the schedule.
- **M8-E — Spell effects at close range.** Per effect family, at the ability's real radius and real cast time: telegraph → cast → impact → aftermath. The overview's M5.5-C shapes stay as the far-view version of the same event.
- **M8-F — Pacing, modes & sign-off.** Measure the real minutes a watched match costs in each mode, tune the selection floor against the designer's answer, `REPORTS/M8.md`, playtest gate. Cheap broadcast juice from the reference target lands here if it hasn't already: a **full-width kill banner** with both portraits (we have a side feed; the banner is what makes a kill feel like an event).

**Prerequisite decisions this milestone forces** (both already on the books, both promoted by it):
- **Sim-side body volume** (parked at M5-E/F). Playback currently fakes separation by drawing bodies up to 1.9 world units off their sim positions. Invisible at overview scale; at 4× zoom a character is drawn away from the point its own attack beat comes from. The close-up view is the argument for taking the real lever.
- **Jungle walls / terrain / chokepoints** (parking lot, deferred since M4.5-C). A gank at a distance is dots converging; a gank *close up* is a story about a corridor, and characters walking through walls that don't exist will read as broken. Decision point before **M8-D** — at minimum a cosmetic terrain layer that steering respects. The reference target settles this: at close zoom, terrain is most of what you are looking at (GDD §7.3).

**Already-shipped work that M8 modifies** (none of it a rewrite):
- `game/map_view.gd` — `_scale()` / `_w2s()` replaced by the camera (M8-B); `CHAMP_R_MIN/MAX`, `TOWER_R`, `PIT_R`, `PAD` and font sizes are clamped for the fit-the-world assumption and must become zoom-aware.
- `game/main.gd` — `SPEEDS` gains a sub-1 entry; `BASE_TPS_1X` stays the 1x anchor; the visual-stretch helper (`min(SPEEDS[i], 4)`, ~line 711) must open downward or every M5.5 effect lingers 4× too long in the close-up. All the `*_TTL` / `*_TICKS` constants were tuned against the 4×-sim-time assumption and need re-checking at real speed.
- `SNAP := 2` (5 keyframes per sim-second) → 1 for viewer runs; measure the memory cost.
- **Snapshot contract** — the close-up needs things the viewer currently infers: facing (`_resolve_facing`), cast start/wind-up, hit vs. miss. Per Pillar 3 the sim reports them; a small snapshot extension exactly like M5.5-B's.
- `fight_end` — carries context/winner/pos/duration/kills today; M8-A wants the gold swing and the participant list on it so scoring doesn't re-derive them.
- `--selftest` + `tools/check.sh` — assert the reel is non-empty, spaced, within budget, and that entering/leaving a highlight doesn't drop frames.
- GDD §7 (playback speeds) and §7.2 (new).

Guardrails: the sim stays the source of truth (selection reads its output, never re-decides it), determinism holds for the reel as well as the match, no external art deps unless the designer lifts that in question 3, `data/highlights.json` for every tunable.

## Parking lot (PoC+, do not start)
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites.

**Wanted by the designer, deliberately deferred** (revisit after M4.5 lands, before M7):
- **Jungle walls, terrain and chokepoints** — "need wall around the jungle, complexify the map". `SimMap` is lane polylines plus point positions today; there is no notion of walkable space, so there are no corridors and no escapes. Deferred by scope call in M4.5-C, which does boundary clamping only. **Promoted 2026-07-25**: the close-up view makes missing walls visible, so this is now a decision point before **M8-D**, not an open-ended nice-to-have.
- **Basic ability kits** (slow / dash / stun / shield on short cooldowns). *Being brought forward in M5* via the three-action model (2026-07-24) — the basic-ability slot is the vehicle for early CC. M5 ships CC (slow/stun) on a few characters; the wider kit variety (dash/shield/etc. across the roster) stays deferred to post-PoC.
