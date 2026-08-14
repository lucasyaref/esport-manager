# M6-B — the camera

**Status: done, runnable, guard rails clean.** `game/map_view.gd` and `game/main.gd`.
Screenshots (local-only, git-ignored): `.shots/m6b_1_default.png`, `_2_zoomed.png`, `_3_follow.png`.

## What shipped

**A bug found while scoping this phase, fixed first.** `CHANGELOG.md`'s M6-T1 entry claimed
`game/terrain_view.gd` — the terrain art from T1's 51 gauntlet iterations — was "drawn by... the
match viewer and the still-frame capture rig, both." It wasn't. `map_view.gd`'s `_draw_field()`
still flat-filled a solid background colour; `TerrainView.draw()` only ever ran inside the offline
capture rig (`tools/shoot_map.gd`). Every match played to date has run on a flat rectangle. Fixed:
`Terrain` now threads from `main.gd`'s already-loaded `data.terrain` into
`MapView.setup_geometry()`, and `_draw_field()` calls `TerrainView.draw()` through the camera's own
origin/scale. The old flat lane/river/camp overlay only draws now as a fallback if terrain fails to
load. `CHANGELOG.md`'s M6-T1 entry corrected to say what's actually true.

**The camera itself**, per BACKLOG's M6-B spec and GDD §7.3 (the reference target's continuous-zoom
model):
- `MapView`'s fixed `_scale()`/`_w2s()` replaced by a real camera — `cam_center` + `cam_zoom`,
  eased toward a target every frame (exponential smoothing) instead of snapping. `ZOOM_MIN` (1.0)
  reproduces the old fit-the-whole-world transform exactly — a fresh match at rest looks the same
  as before this phase, plus terrain now being visible. `ZOOM_MAX` is 4.0 ("the lane fills the
  screen").
- **Zoom-aware sizing.** Every flat-pixel constant that used to be clamped for the one overview
  scale — turret glyphs, HP/nexus bars, badges, camp/pit/nexus circles, fonts — now grows with zoom
  (up to 3× its overview size at max zoom), so a close-up body reads as a body, not a dot pinned to
  overview scale.
- **Manual zoom**: mouse wheel over the map, plus `Zoom −`/`Zoom +` buttons in the bottom bar next
  to the speed controls.
- **Follow-a-player**: F1–F5 / F6–F10 jump the camera to each team's five players (matches the
  reference target's F1–F10 binding); clicking a champion body does the same. Escape or clicking
  empty map releases. The camera recenters on the followed player every frame until released.
- **Minimap**, bottom-left corner of the map panel, appears only once zoomed in (redundant at rest):
  lane skeleton for orientation, a team-coloured dot per living champion, the main camera's viewport
  as a rectangle, and dragon/baron pips (coloured = up, grey = down).
- **Clipping**: `clip_contents = true` on the map panel, so zoomed content can't bleed into the side
  panel or bottom bar.
- **Public API for M6-C** (`set_target`, `follow_player`, `stop_follow`, `toggle_follow`,
  `manual_override`, `zoom_step`, `reset_camera`) so the auto-camera director M6-C builds doesn't
  need new input-handling plumbing — it drives the same interface manual control does.

## What's verified

- `tools/check.sh` green end to end: RNG lint, data validation, terrain guard rails, determinism
  (3 seeds), and the viewer playback selftest (17,917 ticks / 4,480 frames, all assertions pass).
  Sim is untouched by this phase — expected, and confirmed.
- Independent screenshot check (`tester` subagent, driving `game/main.tscn` directly, not the
  offline capture rig): default view shows real terrain art (jungle, rock, river, road, pits) for
  the first time in the live game; zoomed view shows visibly larger bodies/labels, terrain texture
  legible up close, and the minimap correctly present with a moving viewport rectangle; follow view
  correctly recenters on the target player mid-gank. No clipping, no blank/flat frames, no UI
  overlap in any of the three. I reviewed the screenshots directly and confirm the same.

## Calls made without going back to the designer (all reversible, all cheap to retune)

- `ZOOM_MAX = 4.0`, growth curve up to 3× overview pixel sizes, `ZOOM_STEP = 0.4`, smoothing rate —
  all unmeasured "feels right" values, no playtest behind them yet. Easy to retune once someone
  watches it.
- Minimap: bottom-left, 132px, hidden at rest zoom, objective state shown as up/down colour only —
  no numeric spawn countdown. The sim only reports `dragon_up`/`baron_up` booleans today; a real
  countdown needs new data threaded from `sim/objectives.gd`'s spawn timing. Left as a follow-up
  rather than blocking this phase on new sim plumbing.
- Dropped the old flat lane/river/camp overlay once real terrain art is present, rather than
  layering both (they'd visually clash — confirmed against `shoot_map.gd`'s own `--structures`
  mode, which only ever overlays *dynamic* state like tower HP on top of terrain, nothing static).
- Terrain redraws every frame with no caching (~2,500 cells). No stutter observed in the check, but
  flagged as a possible follow-up (pre-render to a texture) if it's slow on lower-end hardware.

## What to look at

Run the game and: zoom with the mouse wheel or the `Zoom −`/`Zoom +` buttons, press F1 through F10
to jump between players, click a champion directly. Or just look at the three screenshots above —
they're the same three views without needing Godot open.

## Open decision

None that's blocking. The unmeasured zoom/growth constants above are the one thing worth a look —
if the zoomed-in view feels too big or too small once you've actually watched it for a minute, that's
a two-constant tweak (`ZOOM_MAX`, `ZOOM_PX_MULT_MAX`), not a redesign.

## Next by default

M6-C (real speed + the auto-camera director) is next in the phase list — it's what actually turns
this camera into "highlights," and it's built to drive the API this phase exposed. I'd start there
unless you'd rather look at this first.
