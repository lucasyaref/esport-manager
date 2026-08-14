# M6-C — real speed + the director

**Status: done, runnable, guard rails clean.** `game/main.gd`, `game/map_view.gd`,
`data/highlights.json`. Screenshots (local-only, git-ignored): `.shots/m6c_1_default.png` through
`m6c_7_after_transport.png`.

## What shipped

**Real speed.** A fourth playback tier, 0.25x, alongside the existing 1x/4x/16x — true 1:1 real time
against the sim clock (today's "1x" is already 4x sim-time). `SPEEDS` is now `Array[float] = [0.25,
1.0, 4.0, 16.0]`, typed so the fraction survives; default stays "1x". Fixed the bug this exposed on the
way in: `_time_scale()` (the helper that stretches on-screen effect lifetimes — damage numbers, hit
flashes, ult impacts — to read for the same real duration regardless of speed) used `mini()`, which
coerces its arguments to `int` and silently truncates `0.25` to `0`. At real speed that would have
zeroed out every effect's lifetime instead of shrinking it correctly. Swapped for `minf()`.
Snapshot cadence (`SNAP`) raised 2→1 tick, so the close-up has a fresh keyframe every sim tick to
interpolate against rather than one every 200ms of sim time.

**The auto-camera director.** Computes the match's highlight reel once per match, the same way
`tools/reel.gd` already does headless (`sim/highlights.gd`, read-only — nothing in `sim/` changed).
While playing, when the timeline enters a highlight's window (pre-roll + the moment itself +
aftermath — 3s/4s padding, tunable), the camera pushes in on the moment's location at zoom 3.2 (close
to max zoom, "the lane fills the screen") and playback speed drops to the real-speed tier
automatically; both revert to whatever they were before once the window ends. A toggle
("Auto-cam: ON/OFF") turns this off without losing the highlight banner/callouts. Manual camera input
— mouse-wheel zoom, clicking a champion, F1-F10 follow hotkeys — always takes the camera back for the
*current* highlight; the director resumes normally on the next one rather than fighting the user.

**On-screen framing.** A banner docked to the top of the map, visible only during an active highlight:
the moment's own one-line description (`Highlights.describe()`, the same text `tools/reel.gd` prints)
plus the players involved, resolved to their display names — e.g. "HIGHLIGHT 17:18 — fight bot, 2
kills, 5 men (Prowl, Talon, Breaker, Longshot)". Replay/Skip buttons on the banner jump the timeline to
the start/end of the current highlight.

**Both pacing modes**, off the same machinery: **Full** (default) plays continuously, camera dipping
in and out as highlights arrive. **Highlights** jumps straight from the end of one highlight's
aftermath to the start of the next one's pre-roll, skipping the dead time between — verified live: one
frame took playback from mid-highlight-0 to the start of highlight-1's window, ~192 sim-seconds
skipped in a jump.

**Transport.** Added a Rewind button (~8 sim-seconds back) next to the existing Skip ▸ Result and
↻ Rewatch; all three (plus Replay/Skip on the banner) reuse the existing `_seek()` primitive rather
than a second timeline-jump mechanism.

## What's verified

- `tools/check.sh` green end to end (RNG lint, data validation, terrain guard rails, determinism ×3
  seeds, viewer `--selftest`). `--selftest` now asserts the director actually engages when the reel
  is non-empty and prints reel size / entries / frames-in-highlight; confirmed across 6 seeds
  (1, 7, 42, 123, 987654321, 2026), reel sizes 6–10 moments, director entered every one every time.
- Independent live-scene check (`tester` subagent, `game/main.tscn` directly): all 8 checklist items
  passed — default view unaffected, director correctly zooms/slows on entry and restores state on
  exit exactly (`cam_zoom`, `speed_index` returned to their pre-highlight values), Auto-cam OFF
  suppresses the camera/speed push while keeping the banner, Highlights pacing skips dead air
  correctly (including flipping the toggle mid-playback jumping straight to the first highlight),
  manual F-key override during a highlight held and did not get snapped back, Replay/Skip/Rewind all
  moved the timeline as expected with no stuck UI state. I reviewed the screenshots directly and
  confirm the same. One pre-existing, non-blocking issue noted (not introduced by this phase):
  player name/level labels can crowd or clip at high zoom near the map panel edge — an M6-B-era
  label-density issue, flagged for later, not this phase's to fix.

## Calls made without going back to the designer (all reversible, all in `data/highlights.json`)

- New `director` config block: `preroll_s: 3.0`, `aftermath_s: 4.0`, `zoom: 3.2`, `rewind_s: 8.0` —
  unmeasured "feels right" values, deliberately not hand-tuned to the ~11-12 min / ~4-5 min pacing
  targets (that measurement + tuning pass is M6-F, not this phase).
- Banner placement (top of map panel) and control labels ("Auto-cam: ON/OFF", "Full"/"Highlights")
  are UI calls, not specified in the phase brief.

## What to look at

Run the game, let it play (or seed/seek into a fight) and watch the director take over: camera zooms
in, speed drops, the highlight banner names the moment and the players in it, then everything releases
back to normal once it's over. Toggle "Highlights" mode to see it skip straight between moments. Or
look at the seven screenshots above for the same beats without opening Godot.

## Open decision

None that's blocking. The `director` block's four numbers (preroll/aftermath/zoom/rewind) are the one
thing worth a look once someone's actually watched a highlight play out — if the push feels too
sudden, too tight, or too loose, that's a JSON edit, not a code change.

## Next by default

M6-F (pacing, modes & sign-off) is the natural next stop for *measuring* what this phase built —
real minutes per mode against the ~11-12 / ~4-5 min targets, tuning the selection floor. But
BACKLOG.md's phase list also has M6-D (close-up actors + base floors, now unblocked since the
designer's pixel-sprite-sheet answer) and M6-G (the broadcast header) still open and independent of
M6-C. I'd suggest M6-D next — sprite work is the most visible remaining gap at the close-up zoom this
phase just built — but M6-F is the cheaper, purely-data-driven option if you'd rather nail the pacing
numbers first. Your call.