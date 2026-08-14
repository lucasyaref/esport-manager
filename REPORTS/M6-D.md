# M6-D — Close-up actors, and the bases they stand in

**Status: done, runnable, guard rails clean.** `tools/make_sprites.gd` (new),
`game/assets/characters/placeholder.png` (generated), `game/assets/structures/placeholder.png`
(generated), `data/animation.json` (new), `game/anim_config.gd` (new), `game/main.gd`,
`game/map_view.gd`. Screenshots (local-only, git-ignored): `.shots/m6d_*.png` (first pass, 12
shots) and `.shots/m6d-fix_*.png` (re-verification after two fixes, 7 shots).

## What shipped

**A shared placeholder pixel sprite sheet, generated in-repo.** `data/characters.json` has pointed
every character's `sprite` field at `res://game/assets/characters/placeholder.png` since M1 — the
file simply never existed, so every match to date silently drew the old procedural
silhouette/disc. `tools/make_sprites.gd` is a headless, pure-`Image`-pixel-ops generator (no
rendering context needed) that authors that file directly: 96×168, 24px frames, 7 rows × 4 cols
covering the animation states GDD §7/§7.2 call for — idle, run, attack, cast, hurt, die, recall.
One shared body (not five per-role bodies), grayscale so the existing team-tint modulate keeps
working unchanged, marked per-role by the existing letter badge rather than five separate
silhouettes — CLAUDE.md's original placeholder plan ("one shared character sprite, recolored per
team, marked per role") carried forward into the sprite-sheet form the designer asked for
2026-08-02. This is the "authored here" placeholder GDD §7.3 explicitly allows in place of a CC0
asset. A second small sheet, `game/assets/structures/placeholder.png`, gives towers and the nexus
a built silhouette (tiered plinth + spire; a faceted crystal) — closing the last piece of the
2026-08-09 gauntlet finding ("no structure silhouette") that M6-D's scope note picked up; the
other two pieces of that finding (paved base floor, masonry perimeter wall) turned out to already
be shipped, in later M6-T1 iterations.

**Animation state derived from what the sim already reports — no new sim plumbing.** `game/main.gd`
computes `ch.anim_state` each frame from the same snapshot flags M5.5/M6-B already derived
(`FLAG_IN_COMBAT`, `FLAG_DISENGAGING`, `FLAG_STUNNED/SLOWED`, `FLAG_RECALLING`, the last-swing
tick, facing, alive) plus the existing HP-diff-derived flinch — priority recall > hurt > cast >
attack > run > idle. A short `dying` fade window plays a distinct collapsed pose at the actual
death position before handing off to the untouched `_draw_dead` fountain/skull treatment. Facing
is conveyed by a horizontal flip only (a placeholder-appropriate simplification, not full
directional frames). `data/animation.json` + `game/anim_config.gd` hold the sheet layout and the
two new timing tunables (`frame_ticks: 4.0`, `die_ticks: 20.0`), following the same
`load_config()`-over-a-default shape as `sim/highlights.gd` / M6-C's `director` block. Frame
advance is scaled through the existing `_time_scale()` pattern, so it stays correct at every
playback speed including M6-C's 0.25x real-speed tier.

**Two fixes from the first tester pass, both re-verified live:**
- The role letter was drawn dead-center on the body and, at the auto-camera director's own zoom
  (3.2, `data/highlights.json`) through max zoom (4.0), was overlapped/clipped by the level badge
  drawn afterward at the body's top-right corner. Moved to a mirrored top-left corner badge —
  confirmed legible on both a solo champion and a real 3-body fight at both ends of that range.
- The tower HP-drain core was an axis-aligned square whose corner reach at full HP almost exactly
  matched the sprite's inner-tier octagon vertices, and both were the same team-tinted color —
  visually fusing into one blob. Switched the core to a circle and trimmed its radius coefficient
  (0.55→0.46). Re-verified by pixel sampling: three distinct bands (outer ring / inner ring /
  core) at full HP, clearly a tiered structure by eye at the higher end of the zoom range and on
  the larger base-tier tower; present but subtler on the smaller outer-lane tower at the low end
  of the range (~3.2-3.6) — a real fix, not a re-fusion, just not equally striking everywhere.

## What's verified

- `tools/check.sh` green end to end: RNG lint, data validation, terrain guard rails, determinism
  ×3 seeds (checksums unchanged — `sim/` untouched by this phase, confirmed), viewer `--selftest`
  extended with new anim-state assertions (attack beats ⇒ attack pose, flinches ⇒ hurt pose, ults
  ⇒ cast pose, kills ⇒ die pose) and all passing.
- Two independent live-scene verification passes (`tester` subagent, an in-engine capture harness
  driving the real `game/main.tscn` — OS-level `screencapture` was unavailable in this sandbox for
  both the coder and tester, so frames were grabbed via `get_viewport().get_texture()` instead,
  same live scene, not the offline `tools/shoot_map.gd` rig). First pass: sprites read as real
  team-tinted pixel bodies at zoom (not flat discs), death pose confirmed distinct from the
  fountain treatment, recall VFX intact, nexus silhouette clear, no missing-texture squares or
  console errors — but flagged the two issues above. Second pass, after the fixes: both confirmed
  resolved, no new regressions, same seed-42 highlight moments (13:55 gank, nexus-falls ending)
  reproduced correctly. I reviewed both rounds of screenshots directly and confirm the same.
- Run/idle and recall-pose distinction were not reliably confirmable by eye in a still screenshot
  at this sprite scale — noted as expected and not a failure, per the tester's brief.

## Calls made without going back to the designer (all reversible)

- One shared body marked by the role letter, rather than five per-role silhouettes — avoids 5×
  the placeholder art/animation surface; the per-character `sprite` field still overrides with
  real art and no code change whenever real art exists.
- Horizontal-flip-only facing (no directional frame set) — cheapest technical option for a
  placeholder sheet, explicitly allowed in the brief.
- `frame_ticks: 4.0`, `die_ticks: 20.0` in `data/animation.json`, and the anim-state priority order
  (recall > hurt > cast > attack > run > idle) — unmeasured "feels right" values, same category as
  M6-B's zoom constants and M6-C's `director` block.
- Role-letter and tower-core fix specifics (corner placement, backdrop styling, `0.46` coefficient)
  — small inline visual tuning, not exposed to `data/` since they're geometry constants matching
  how the level badge and the original `0.55` coefficient were already inline.

## What to look at

Run the game, zoom in on a fight (mouse wheel, or let the auto-camera director pull you in) and
watch characters read as small animated pixel bodies with a legible role letter and level badge in
opposite corners; watch a tower or the nexus up close for the new built silhouette, most visible at
higher zoom and on the bigger base-tier towers. Or look at the `.shots/m6d_*` and `.shots/m6d-fix_*`
screenshots for the same beats without opening Godot.

## Open decision

None that's blocking. The tower silhouette's legibility scaling with zoom/tower size (strong at
max zoom on a base tower, subtler on a smaller outer-lane tower at the director's own 3.2 zoom) is
the one thing worth a look once someone's actually watched a siege — if it still reads too flat at
the lower end, that's a coefficient/contrast tweak, not a redesign.

## Next by default

M6-F (pacing, modes & sign-off) and M6-G (the broadcast header) are both still open and
independent of M6-D. M6-G is GDD-specified in detail already (designer direction 2026-08-02) and
is the more visible remaining gap now that actors and structures both read correctly at zoom — a
zoomed camera has lost the map and needs the header to still say who's winning. M6-F is the
cheaper, purely-data-driven option (measure real minutes per mode against the ~11-12 / ~4-5
targets) if pacing sign-off matters more right now. I'd suggest M6-G next; your call.
