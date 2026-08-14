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
| **M6 — Highlights & the close-up view** | **in-progress — A done (shipped with M5-G); T built (T1–T4 done, guard rails clean); B done 2026-08-12 (`REPORTS/M6-B.md`); C done 2026-08-12 (`REPORTS/M6-C.md`); D done 2026-08-14 (`REPORTS/M6-D.md`); D2 done 2026-08-14 (`REPORTS/M6-D2.md`); F/G next**; reordered ahead of the draft screen 2026-07-31 — the scene should look good before draft |
| M7 — PoC polish pass | to-do (scope: match + highlight view; draft screen not yet in scope, see below) |
| Draft screen | **deferred** — decision point after M7: go to draft, or keep the designer's focus on the sim/viewer |

## Now — M6: the close-up view (phase **D**/**D2** done — F, G next)

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
6. *Baron/dragon value parity* (`REPORTS/M6-T-diagnosis.md` §7–13), 2026-08-12 — **it's a numbers
   question**, split out of M6-T into its own balance phase, not blocking M6. The designer's first
   pick — buff dragon (a "Soul" spike at 4 stacks) instead of nerfing baron — measured **inert**: 0
   of 300 games ever had a team reach 4 dragon stacks (this sim only sees ~2.1 dragons taken *in
   total* per match; real LoL: 4–6). Kept in the data anyway (harmless), and the low-uptake cause is
   parked as its own unscoped follow-up. The `baron_siege_mult` sweep that followed **found the fix**:
   3.0 (shipped) → 61.3% blue; 2.0 → 53.0%; **1.5 → 50.3%**, on target, with no red-side overshoot.
   `data/balance.json` is currently back at 3.0, uncommitted — **designer sign-off open** on shipping
   1.5 (`REPORTS/M6-T-diagnosis.md` §12–13). M6-T's terrain scope (T1–T4) is otherwise complete; the
   milestone continues on **M6-B/C** without waiting on this.


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

### M6 — Highlights & the close-up view — in-progress (A, T, B, C, D, D2 done; F, G next)

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
  + render the terrain (cosmetic, sim untouched — a runnable look-at-it build) — signed off
  2026-08-09 after 37 iterations and 9 panels (narrative in `CHANGELOG.md`), then **re-opened the
  same day by designer direction** and carried through runs 4 and 5 — **51 iterations, 17 panels**,
  reports `REPORTS/M6-T1-gauntlet-run2.md`, `-run3.md`, `-run5.md`, loop log `docs/gauntlet-map.md`.
  **Closed 2026-08-09** on both open calls: the **base floors move to M6-D** (a plaza under
  placeholder squares fixes half a picture), and **jungle density is dropped** — green already
  measures the reference's share, and the only remaining way to buy more costs walkable ground.
  Gauntlet loop 1 exits with one accepted-and-deferred fidelity finding (the bases) rather than a
  clean stopping rule, by decision and on the record.
  **T2 — movement routes around walls — shipped 2026-08-11** (`sim/nav_grid.gd`, `REPORTS/M6-T2.md`).
  Precomputed flow fields to every destination a body walks (lanes/camps/pits), built once at load,
  no per-agent runtime search — determinism holds. Batch delta (300 sims): gank/sandwich/multi-man
  connect rates all fall 3–6 pts as designed, kills/min moves toward pro (1.11→0.96 against ~0.85),
  and the **macro win-vector lands on M5's ~43% target as a side effect** (32.3%→42.3%), unplanned.
  Two open watch items, both traced to the same known T4 cause (camps sitting inside the dragon/baron
  pits): blue-side win rate moved 49.7%→55.0%, and first-tower's lane split shifted bot↔mid. Designer
  gate open: keep as measured, and pick T3 vs. pulling T4 forward — `REPORTS/M6-T2.md` §7.
  **T3 — brush hides bodies, walls block sight — built and measured 2026-08-11**
  (`sim/combat.gd:_can_see`, `sim/terrain.gd:has_sight`, `REPORTS/M6-T3.md`). Every hostile
  perception check in combat now runs through one gate: a wall blocks sight outright, a body in
  brush is invisible past 3.5 units (vs. the normal 9.0), asymmetric by design — the mechanism the
  scoping report called "the most fun mechanic" here. Batch delta (300 sims, vs. T2): the ambush
  effect is real and outweighs T2's travel-cost effect — gank/sandwich/multi-man connect rates all
  rise (24→28%, 32→41%, 28→34%, the last two above their pre-T2 numbers), kills/min reverts to
  1.11 (pre-T2 level, away from pro's ~0.85), the macro win vector overshoots to 51.0% (target
  ~43%), and blue-side win rate worsens again (55.0%→57.7%). Unlike T2, **not called "keep as
  measured"** — flagged `brush_reveal_radius` (3.5, unmeasured guess) as the lever to tune first.
  **Follow-up sweep (3.5/4.5/5.5, `REPORTS/M6-T3.md` §6) ruled that out**: every metric held flat
  across a 57% wider reveal window, so the radius isn't the lever — concealment reads as roughly
  binary, not a dial. Open question moved from "what radius" to "keep the mechanic as-is, or does
  it need a structural change (e.g. only concealing a stationary body)" — `REPORTS/M6-T3.md` §8.
  **T4 — camps separated from their pits — built 2026-08-11**
  (`tools/terrain_paint.gd --camps=D`, `REPORTS/M6-T4.md`). The four camps that sat cell-touching
  the dragon/baron pits now have a real ~7–8 unit gap. Guard rails clean. Batch delta (300 sims, vs.
  T3): **the working theory was wrong.** Every metric T2/T3 had traced to this overlap held flat
  (macro win vector 51.0→50.7%, connect rates, lane split) — separating camp from pit fixed none of
  it — and blue-side win rate got *worse* (57.7%→61.3%), the third phase running to push it further
  from the ~50% target (49.7%→55.0%→57.7%→61.3% across T1-baseline→T2→T3→T4).
  **Diagnosis pass — cause found 2026-08-11** (`tools/batch_run.gd`'s new per-side breakdown,
  `REPORTS/M6-T-diagnosis.md`). Every proximate combat number is even (kills, gold, deaths, fight
  wins, gank connect rate all ~50/50) — but **barons taken is 61% blue**, almost exactly matching
  the 61.3% win-rate split. Cause: `data/map.json`'s pits never moved all milestone, and blue's base
  sits 43.1 units from baron vs. red's 61.8 (the map's exact 180° mirror of red being closer to
  dragon) — fair *if the two objectives are worth the same*. They aren't:
  `data/balance.json`'s baron carries a **3.0× siege damage multiplier** and 3× dragon's gold, dragon
  is a small stacking buff with no siege component. Blue drew the stronger half of a
  geometrically-fair map. T2/T3/T4's working theory (camp/pit overlap) is now formally ruled out —
  it never touched this lever. Why it only appeared at T2: pre-T2 movement ignored walls, so the
  proximity gap was a small constant a whole game could wash out; T2 made real path cost matter, and
  T3/T4 both then landed changes in baron's own neighbourhood without touching the actual cause.
  **Terrain scope (T1–T4) done 2026-08-12.** The balance fix this diagnosis pass recommended is
  **split out into its own phase, run by the designer in parallel** (decision above, §Now item 6) —
  it doesn't block M6 moving on to the camera.
  Ships before the camera because every later phase draws on top of it.
  **Scoping M6-B found one more thing to fix first, filed here since it's the same file:** despite
  the CHANGELOG's M6-T1 entry saying `game/terrain_view.gd` is "drawn by... the match viewer and the
  still-frame capture rig, both" — it is not. `game/map_view.gd`'s `_draw_field()` still flat-fills a
  solid background; `TerrainView.draw()` is only ever called from the offline capture rig
  (`tools/shoot_map.gd`). 51 gauntlet iterations of terrain art are invisible in the actual game. Not
  a new phase — folded into M6-B as its first task, since the camera is pointless to build against a
  flat grey map and both touch the same draw path.
- **M6-A — Highlight scoring (headless, no view) — done** (2026-08-01, `REPORTS/M6-A.md`). `sim/highlights.gd` + `data/highlights.json` + `tools/reel.gd`, measured in batch: **8.0 moments per reel** over 400 sims, deterministic, floor/spacing/diversity/cap all live. **The designer gate is still open**: read a reel or three (`tools/reel.gd -- --seed=N`) and say whether those are the moments you would want to watch.
- **M6-B — The camera — done 2026-08-12** (`REPORTS/M6-B.md`). Fixed a wiring bug found while
  scoping this phase: `TerrainView.draw()` (M6-T's terrain art) was never actually called from the
  live match viewer, only from the offline capture rig — every match played to date ran on a flat
  background. Wired it into `map_view.gd`'s `_draw_field()`, through the camera's own scale so it
  pans/zooms with everything else. Then the camera itself: `MapView`'s fixed world→screen transform
  replaced by `cam_center`/`cam_zoom`, eased toward a target (not snapped); `ZOOM_MIN` reproduces
  the old fit-the-world transform exactly, so a match at rest looks the same as before plus terrain
  now visible. Zoom-aware sizing for every flat-pixel element (turret glyphs, bars, fonts, badges —
  up to 3× their overview size at max zoom). Manual zoom (mouse wheel, `Zoom −`/`Zoom +` buttons).
  Follow-a-player: F1–F10 (TFM2's own binding, GDD §7.3) or click a champion body, released via
  Escape or clicking empty map. A minimap (bottom-left, appears only once zoomed in) with
  team-coloured player dots, the camera's own viewport rectangle, and dragon/baron up/down pips —
  no numeric spawn countdown yet, the sim doesn't report one, flagged as a follow-up. `tools/check.sh`
  green (sim untouched, as expected); verified visually via an independent screenshot check
  (screenshots local-only, git-ignored). Public camera API (`set_target`/`follow_player`/etc.) built
  so **M6-C**'s auto-camera director can drive it without new input plumbing.
- **M6-C — Real speed + the director — done 2026-08-12** (`REPORTS/M6-C.md`). A fourth playback tier,
  0.25x — true 1:1 real time against the sim clock — alongside 1x/4x/16x; fixed `_time_scale()`'s
  `mini()`-truncates-a-fraction-to-zero bug on the way in (`minf()` now), which would otherwise have
  zeroed every effect lifetime at real speed. Snapshot cadence raised 2→1 tick. An **auto-camera
  director** computes the match's highlight reel once (`sim/highlights.gd`, read-only, same as
  `tools/reel.gd`) and, while playing, pushes the camera to zoom 3.2 and drops to real-speed for each
  moment's pre-roll (3s) + action + aftermath (4s), then restores the exact prior camera/speed state
  on exit — all four numbers live in `data/highlights.json`'s new `director` block, unmeasured
  "feels right" values left for a later tuning pass. Auto-camera is a toggle; manual camera input
  (wheel zoom, click, F1–F10) always takes the camera back for the current highlight without the
  director fighting it, and resumes normally on the next one. An on-screen banner names the moment
  and the players in it (`Highlights.describe()` + resolved names) with Replay/Skip controls, plus a
  new Rewind transport button — all timeline jumps reuse the existing `_seek()` primitive, no second
  mechanism. Both pacing modes share this machinery: **Full** (default, camera dips in/out
  continuously) and **Highlights** (jumps straight between moments, skipping the dead time — verified
  live, one frame skipped ~192 sim-seconds between two highlights). `tools/check.sh` green
  (sim untouched, as expected — `--selftest` now also asserts the director engages whenever the reel
  is non-empty, checked across 6 seeds); verified visually via an independent screenshot check
  (screenshots local-only, git-ignored) covering all of the above plus exact state restoration on
  exit. One pre-existing, non-blocking issue noted, not introduced here: player name/level labels can
  crowd/clip at high zoom near the map edge (an M6-B-era label-density gap).
- **M6-D — Close-up actors, and the bases they stand in — done 2026-08-14** (`REPORTS/M6-D.md`).
  ➕ **Scope added 2026-08-09** (designer call closing gauntlet run 5): the **base floors** ship
  here rather than in M6-T1. Gauntlet loop 1's last unclosed fidelity finding is *"both bases read
  as flat tinted rectangles, not built ground — no floor material, no perimeter wall, no structure
  silhouette"*, filed `breaks-immersion`. Two of the three turned out to already be shipped, in
  later M6-T1 iterations (paved base floor colour, `_draw_base_wall`'s masonry ring); the remaining
  piece, structure silhouette, ships here as a tower/nexus sprite sheet (tiered plinth + spire;
  faceted crystal) layered under the existing HP-drain/bar/flash/rubble drawing.
  Characters now read as characters at zoom: a shared, generated (`tools/make_sprites.gd`) pixel
  sprite sheet — `game/assets/characters/placeholder.png`, 24px frames, idle / run / attack / cast
  / hurt / die / recall — replaces the procedural silhouette that every match had silently drawn
  since M1 (`data/characters.json`'s `sprite` field pointed at this path all along; the file just
  never existed). ✅ **Unblocked 2026-08-02: pixel sprite sheets** (designer answer (b), GDD §7.3),
  shipped as an "authored here" placeholder per that same section, since no CC0 set was vendored
  and there's no image-generation tool in this environment. Animation state is derived client-side
  each frame from flags the sim already reports (combat/disengage/CC/recall flags, last-swing tick,
  facing, alive, HP-diff flinch) — **no new sim plumbing needed**, same pattern M6-B already used
  for `casting`. The per-character `sprite` field still overrides the shared sheet with real art
  and no code change. Two legibility issues found by the first tester pass (role-letter badge
  occluded by the level badge; tower silhouette fusing into a blob at full HP) were fixed and
  re-verified live — see the report for both. `tools/check.sh` green throughout (sim untouched, as
  expected).
- **M6-D2 — Character art: LPC role sprites, both team colors — done 2026-08-14**
  (`REPORTS/M6-D2.md`). Role-level pixel art (one look × 5 roles × 2 team colors) replaces the
  procedural placeholder; `sprite_by_side` resolves per character+team. One follow-up flagged, not
  fixed: level/role corner badges read oversized against the new (visually smaller) bodies at high
  zoom. **Long-term intent, still on record and unstarted: one real sprite per character** — see the
  parking lot below.
- **M6-E — Spell effects at close range.** Per effect family, at the ability's real radius and real cast time: telegraph → cast → impact → aftermath. The overview's M5.5-C shapes stay as the far-view version of the same event.
- **M6-G — The broadcast header** (designer direction 2026-08-02, GDD §7.4). One top strip that reads like a LoL broadcast: team names, kills either side of the clock, **dragon pips** per team, baron with its remaining duration, turret counts, team gold with the delta marked on the leader only (`+1.7k`). Replaces today's scattered clock / score / gold bar. Permanently on screen at every zoom, because a zoomed camera has lost the map and must still say who is winning. Everything in it is a read of the sim's own output — the HUD counts nothing the sim did not report. Ships with the **full-width kill banner** (both portraits) from the reference target; the side feed stays as narration.
- **M6-F — Pacing, modes & sign-off.** Measure the real minutes a watched match costs in each mode against the designer's **(a)** answer (target ~11–12 min for a full watched match; ~4–5 for highlights-only), tune the selection floor, `REPORTS/M6.md`, playtest gate.

**Prerequisite decisions this milestone forces:**
- **Sim-side body volume** (parked at M5-E/F). Playback currently fakes separation by drawing bodies up to 1.9 world units off their sim positions. Invisible at overview scale; at 4× zoom a character is drawn away from the point its own attack beat comes from. The close-up view is the argument for taking the real lever. **Still open** — and M6-T changes its terms, since a body that has to fit through a corridor has a size whether we model one or not.
- ✅ **Jungle walls / terrain / chokepoints** — resolved 2026-08-02: build it. Now phase **M6-T**, above.

**Already-shipped work that M6 modifies** (none of it a rewrite):
- ✅ `game/map_view.gd` — `_scale()` / `_w2s()` replaced by the camera; `CHAMP_R_MIN/MAX`, `TOWER_R`, `PIT_R` and font sizes are now zoom-aware. Done in M6-B, `REPORTS/M6-B.md`.
- `game/main.gd` — `SPEEDS` gains a sub-1 entry; `BASE_TPS_1X` stays the 1x anchor; the visual-stretch helper (`min(SPEEDS[i], 4)`, ~line 711) must open downward or every M5.5 effect lingers 4× too long in the close-up. All the `*_TTL` / `*_TICKS` constants were tuned against the 4×-sim-time assumption and need re-checking at real speed.
- `SNAP := 2` (5 keyframes per sim-second) → 1 for viewer runs; measure the memory cost.
- **Snapshot contract** — ✅ resolved 2026-08-14, without a new extension: M6-D found facing,
  combat/disengage/CC/recall flags, the last-swing tick and HP-diffs already sufficient to derive
  every animation state client-side (same pattern M6-B used for `casting`), so this item closes
  without touching `sim/`.
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
Club creation · league calendar + standings + headless league sims · match history · budget/mercato · coaching staff system · marketing · per-character sprites (**confirmed designer long-term intent, 2026-08-14** — see M6-D2, `REPORTS/M6-D2.md`; still parked, the PoC step shipped role-level art, not per-character).

**Wanted by the designer, deliberately deferred** (revisit after M4.5 lands, before M7):
- ~~**Jungle walls, terrain and chokepoints**~~ — deferred at M4.5-C, promoted 2026-07-25, and
  **taken up 2026-08-02** on designer go-ahead. No longer parked: it is phase **M6-T**.
- **Basic ability kits** (slow / dash / stun / shield on short cooldowns). *Being brought forward in M5* via the three-action model (2026-07-24) — the basic-ability slot is the vehicle for early CC. M5 ships CC (slow/stun) on a few characters; the wider kit variety (dash/shield/etc. across the roster) stays deferred to post-PoC.
