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
| M5 — Macro play: cross-map coordination | done 2026-08-01 (report: REPORTS/M5.md; A–G in CHANGELOG.md) |
| M5.5 — Viewer v2: combat readability & juice | done (playtest gate passed 2026-07-26; A–H in CHANGELOG.md) |
| **M6 — Highlights & the close-up view** | **in-progress — A done (shipped with M5-G); T next, B–G to-do**; reordered ahead of the draft screen 2026-07-31 — the scene should look good before draft |
| M7 — PoC polish pass | to-do (scope: match + highlight view; draft screen not yet in scope, see below) |
| Draft screen | **deferred** — decision point after M7: go to draft, or keep the designer's focus on the sim/viewer |

## Now — M6: the close-up view (phase **T** next — terrain)

**Designer decisions, 2026-08-02** (answers to `REPORTS/M6-scoping.md` §Questions):
1. *Ordering* — already settled 2026-07-31: the view goes before the draft screen.
2. *Pacing* — **(a) the watched match gets longer.** Highlights add on top of the overview
   (~8 → ~11–12 real minutes); the overview is **not** sped up to pay for them. Highlights-only
   still ships as a mode. GDD §7.2.
3. *Art* — **(b) pixel sprite sheets**, not procedural bodies. This narrowly lifts the
   placeholder-only guardrail for a shared CC0/authored pixel set; the per-character `sprite`
   field still overrides with no code change. **M6-D is unblocked.** GDD §7.3.
4. *Highlight scoring* — weights left as shipped. The designer's answer was a **broadcast
   header** (kills / dragon pips / baron / turrets / team gold with `+1.7k` on the leader /
   clock), which is a HUD item, now GDD §7.4 and phase **M6-G** below.
5. *Terrain* — **build it, jointly.** Promoted out of the parking lot into phase **M6-T**,
   scheduled next. Design model: GDD §6.2. Working method and the first draft map:
   `REPORTS/M6-terrain-scoping.md`.


**M5 is done** (2026-08-01, `REPORTS/M5.md`). The macro win-vector target is **met**: the macro
roster wins **42.5%** against a ~43% target, up from 34.5% before M5-F2, and kills land exactly on
pro's 28. Phase G's own work was a diagnosis rather than a tuning pass — see below — and **M6-A
shipped alongside it** (`REPORTS/M6-A.md`): the highlight scorer, which is both the M6 selection
layer and the balance instrument that made the diagnosis possible.

**The one finding that shapes what comes next.** 65% of all fights in this sim are two bodies, and
that share held at 63–66% across *sixteen* measured arms — damage scale, disengage timers, respawn
timers, the hold rule, all of it. The cause is not macro: at the average fight **3.9 bodies stand
within reach of an enemy and only 2.6 swing**, and the teams do converge. Bodies arrive, exchange
for one to three seconds, break off, and the next exchange scores as a *new* fight. Making a real
5v5 happen is a change to **how long a committed body stays committed** — the combat model in GDD
§6.1, not a number in it. It is the largest remaining gap to a pro game, and M6's close-up view is
waiting on it: at 4× zoom, a reel of 2v2s is a reel of 2v2s.

**Three designer calls are open** (`REPORTS/M5.md` §5), none of them blocking:
1. Is a real 5v5 worth a combat-model change? *(the one worth spending a milestone on)*
2. `fight.hold_when_winning_edge` — shipped off at 99. Turning it to 1 buys multi-kill moments
   (2.4 → 3.0/match) and costs kill fidelity (28.4 → 31.9) and ~2.5 pts of win vector.
3. Match length is 29.1 min against pro's 32, which is also the whole of the kills-per-minute miss
   (0.97 against ~0.85). Tower and nexus HP are the direct levers; nothing else depends on them.

Also open from earlier phases and unchanged: `minions.defend_pressure_mult` (shipped at 1.0,
`REPORTS/M5-F1.md` §4 and the 2026-07-31 re-measurement), first tower at 7.4 min against pro's
10–12, and whether the support should *die* more or *be* weaker.

**Carried into M6:** **sim-side body volume as a tunable lever** (measured: −6 pts macro win,
blue-side 49.5→43.5%, conversion 66.3→71.1%, but gank connect 16→22% and first-tower-is-bot
10→27%). Playback fakes separation by drawing bodies up to 1.9 world units off their sim positions;
invisible at overview scale, wrong at 4× zoom. M6-B is the argument for taking the real lever.

## Next

### M5 — Macro play: cross-map coordination — **done** (2026-08-01)

All seven phases shipped. Sign-off: `REPORTS/M5.md`. Per-phase rationale and every batch number in
`CHANGELOG.md`; phase reports in `REPORTS/M5-C.md`, `M5-D.md`, `M5-E.md`, `M5-F1.md`, `M5-F2.md`.
The macro win-vector target is met (**42.5%** against ~43%) and all six designer coordination items
are settled — four shipped, two by construction. The open designer calls and the fight-size finding
are in **Now**, above.

Standing guardrails, unchanged and still binding: pure-GDScript `sim/`, determinism, `tools/check.sh`,
headless batch, data-driven (new tunables → `data/balance.json`). GDD §6.1 has the macro model.

### M6 — Highlights & the close-up view — in-progress (A done, B next)

Designer direction, 2026-07-25: a **second view**. The overview stays what it is (accelerated, whole map, silhouettes); 5–10 times a match the viewer drops into a **highlight** — zoomed on the action, characters as real sprites with animations and spell effects, played at **real speed** for ~30 s max. Ganks that turn into kills, teamfights, big fights. Actions are scored, the top 5–10 are selected, and anything under an absolute threshold is dropped even if it made the top 10. Full scoping, measurements and open questions: `REPORTS/M6-scoping.md`. Design model: GDD §7.2.

**Reference target named by the designer (2026-07-25): a shipped esports-manager viewer** — written up in GDD §7.3 (which is the durable record; the screenshots themselves are local-only and git-ignored). It corrects one assumption in this plan: it is **one renderer with a continuous zoom and an auto-camera**, not two views. So "highlight" = the camera director choosing a focus + the speed dropping, and the two modes share every line of code. It also adds three items to the phases below (minimap, kill banner, transport/replay) and confirms two things already flagged: **terrain is a prerequisite** for the close view, and **the sprite bar is low** — tiny pixel characters, not detailed art.

**Why here in the plan** (and the one phase that moves earlier):
- The **selection layer is cheap and useful now** — it is pure analysis of the sim's own event stream, headless-testable, and it doubles as a balance metric. ✅ **M6-A shipped alongside M5-G**, and it earned its keep twice over: it is also the instrument that diagnosed M5-G's fight-size problem.
- The **view layer is expensive, art-dependent, and premature until the sim earns it.** The scoping report's "no fight reached six participants" pre-dated M5-E/F and has expired — the average match's biggest fight is now 5.7 bodies. But **65% of all fights are still two bodies**, and M5-G established that no number fixes that: it is a combat-model question (how long a committed body stays committed, GDD §6.1). Built today, the reel would still be mostly 2v2s. **That, not the plays, is now the prerequisite** — see **Now**.
- Reordered ahead of the draft screen by designer direction (2026-07-31): the scene should look good before draft is built on top of it. Question 1 from the scoping report (whether the zoomed fight should jump ahead of the draft screen as a demo) is resolved by this — it does.

**Phases:**
- **M6-T — The map: terrain, walls and brush — in progress** (designer go-ahead 2026-08-02; design model
  GDD §6.2, working method `REPORTS/M6-terrain-scoping.md`). A real SR-shaped map authored as a
  human-readable ASCII grid (`data/terrain.txt`) the designer can read and edit directly; compiled
  at load into a navigation grid. Sub-phases, each measured before the next: **T1** author + compile
  + render the terrain (cosmetic, sim untouched — a runnable look-at-it build) — **done 2026-08-09,
  designer sign-off, narrative in `CHANGELOG.md`** (37 gauntlet iterations, 9 cold critic panels,
  reports `REPORTS/M6-T1-gauntlet-run2.md` and `-run3.md`, loop log `docs/gauntlet-map.md`).
  **T2** movement
  routes around walls (precomputed per-destination flow, no runtime search), with a batch delta on
  gank connect rate, escape rate and rotation cost; **T3** brush hides bodies and walls block sight,
  gated on its own batch measurement; **T4** camps and pits moved into their real pockets, sign-off.
  Ships before the camera because every later phase draws on top of it.
- **M6-A — Highlight scoring (headless, no view) — done** (2026-08-01, `REPORTS/M6-A.md`). `sim/highlights.gd` + `data/highlights.json` + `tools/reel.gd`, measured in batch: **8.0 moments per reel** over 400 sims, deterministic, floor/spacing/diversity/cap all live. **The designer gate is still open**: read a reel or three (`tools/reel.gd -- --seed=N`) and say whether those are the moments you would want to watch.
- **M6-B — The camera.** `MapView`'s world→screen transform becomes a camera (centre, **continuous zoom**, smoothing, follow-a-point); overview is the camera fitted to the world, so nothing changes visually on day one. Zoom-aware sizing for everything currently clamped in pixels. Manual zoom in/out controls, click-or-hotkey to follow a player (TFM2 binds F1–F10), and — because zooming in loses the map — a **minimap** with player dots, the viewport rectangle and objective timers. The minimap is a requirement of this phase, not polish.
- **M6-C — Real speed + the director.** A sub-1x playback speed (today's 1x is already **4× sim-time**; real speed is 0.25× of it), visual lifetimes rescaled below the current 4× cap, snapshot cadence raised to one per tick for viewer runs. An **auto-camera director** consumes M6-A's scored moments: it pushes the camera in and drops the speed for pre-roll (the approach) + action + aftermath, then pulls back out. Auto-camera is a toggle — manual camera always available. On-screen framing (what this highlight is, who it's about) and a skip control. Both pacing modes fall out of the same machinery: **full match** (highlights add ~3.5 min on top) and **highlights-only** (jump between moments, ~4–5 min a match). Transport to match the reference: skip-to-start / rewind / skip-to-end over the existing slider, which makes **"replay that highlight"** nearly free.
- **M6-D — Close-up actors.** Characters read as characters at 4× zoom: animation states (idle / run / attack / cast / hurt / die / recall), wind-up telegraphs, facing **reported by the sim** rather than inferred by the viewer. ✅ **Unblocked 2026-08-02: pixel sprite sheets** (designer answer (b), GDD §7.3). The actor is built around a sprite-sheet contract from the start — a 16–32 px animated body per role, shared placeholder set, per-character `sprite` field overriding it with no code change. Same pixel art direction as the M6-T terrain.
- **M6-E — Spell effects at close range.** Per effect family, at the ability's real radius and real cast time: telegraph → cast → impact → aftermath. The overview's M5.5-C shapes stay as the far-view version of the same event.
- **M6-G — The broadcast header** (designer direction 2026-08-02, GDD §7.4). One top strip that reads like a LoL broadcast: team names, kills either side of the clock, **dragon pips** per team, baron with its remaining duration, turret counts, team gold with the delta marked on the leader only (`+1.7k`). Replaces today's scattered clock / score / gold bar. Permanently on screen at every zoom, because a zoomed camera has lost the map and must still say who is winning. Everything in it is a read of the sim's own output — the HUD counts nothing the sim did not report. Ships with the **full-width kill banner** (both portraits) from the reference target; the side feed stays as narration.
- **M6-F — Pacing, modes & sign-off.** Measure the real minutes a watched match costs in each mode against the designer's **(a)** answer (target ~11–12 min for a full watched match; ~4–5 for highlights-only), tune the selection floor, `REPORTS/M6.md`, playtest gate.

**Prerequisite decisions this milestone forces:**
- **Sim-side body volume** (parked at M5-E/F). Playback currently fakes separation by drawing bodies up to 1.9 world units off their sim positions. Invisible at overview scale; at 4× zoom a character is drawn away from the point its own attack beat comes from. The close-up view is the argument for taking the real lever. **Still open** — and M6-T changes its terms, since a body that has to fit through a corridor has a size whether we model one or not.
- ✅ **Jungle walls / terrain / chokepoints** — resolved 2026-08-02: build it. Now phase **M6-T**, above.

**Already-shipped work that M6 modifies** (none of it a rewrite):
- `game/map_view.gd` — `_scale()` / `_w2s()` replaced by the camera (M6-B); `CHAMP_R_MIN/MAX`, `TOWER_R`, `PIT_R`, `PAD` and font sizes are clamped for the fit-the-world assumption and must become zoom-aware.
- `game/main.gd` — `SPEEDS` gains a sub-1 entry; `BASE_TPS_1X` stays the 1x anchor; the visual-stretch helper (`min(SPEEDS[i], 4)`, ~line 711) must open downward or every M5.5 effect lingers 4× too long in the close-up. All the `*_TTL` / `*_TICKS` constants were tuned against the 4×-sim-time assumption and need re-checking at real speed.
- `SNAP := 2` (5 keyframes per sim-second) → 1 for viewer runs; measure the memory cost.
- **Snapshot contract** — the close-up needs things the viewer currently infers: facing (`_resolve_facing`), cast start/wind-up, hit vs. miss. Per Pillar 3 the sim reports them; a small snapshot extension exactly like M5.5-B's.
- ✅ `fight_end` — now carries the participant lists, the gold swing, `peak` (largest either side got at once) and `present`/`declines` (bodies that could be swinging and are not, and why). Done in M6-A/M5-G.
- `--selftest` + `tools/check.sh` — assert the reel is non-empty, spaced, within budget, and that entering/leaving a highlight doesn't drop frames.
- GDD §7 (playback speeds) and §7.2 (new).

Guardrails: the sim stays the source of truth (selection reads its output, never re-decides it), determinism holds for the reel as well as the match, no external art deps unless the designer lifts that in question 3, `data/highlights.json` for every tunable.

### M7 — PoC polish pass — to-do
Pacing/readability tuning from designer playtest feedback on the sim + viewer (overview and close-up), event feed wording, minimal sound hooks (optional), bug pass. Scope is the match experience only — the draft screen is deferred (see below) and out of scope for this pass. Tag `poc-1`.

### Draft screen — deferred

Reordered out of the near-term plan by designer direction (2026-07-31): the match scene should look good — sim depth (M5) and the highlight/close-up view (M6) — before the draft screen is built on top of it. Held until after M7, at which point the designer decides between two paths:
1. **Build the draft screen** (pick-only UI per GDD §5, AI opponent drafting, coach recommendations + follow/ignore modifiers, champion-pool warnings, hand-off into match sim, post-game result screen), or
2. **Keep focusing on the sim/viewer** — the PoC isn't necessarily "done enough" on that front yet, decided fresh at that checkpoint rather than pre-committed now.

No work should start on this until that checkpoint.

## Parking lot (PoC+, do not start)
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites.

**Wanted by the designer, deliberately deferred** (revisit after M4.5 lands, before M7):
- ~~**Jungle walls, terrain and chokepoints**~~ — deferred at M4.5-C, promoted 2026-07-25, and
  **taken up 2026-08-02** on designer go-ahead. No longer parked: it is phase **M6-T**.
- **Basic ability kits** (slow / dash / stun / shield on short cooldowns). *Being brought forward in M5* via the three-action model (2026-07-24) — the basic-ability slot is the vehicle for early CC. M5 ships CC (slow/stun) on a few characters; the wider kit variety (dash/shield/etc. across the roster) stays deferred to post-PoC.
