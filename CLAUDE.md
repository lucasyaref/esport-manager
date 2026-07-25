# MOBA Manager — Project Instructions for Claude Code

You (Claude Code) are the sole developer of this project. The human acts as **game designer only**: they give direction in plain language, answer design questions, and playtest. They never write or edit code. Minimize the actions you ask of them.

## Product vision (long-term)
A "Football Manager for MOBA esports": the player owns an esports club — roster, coaching staff, budget, transfer market (mercato), marketing, tournament calendar. Matches are simulated MOBA games, watchable top-down in accelerated time. The core fantasy: pre-game decisions (players, mood, draft, following coach recommendations or not) visibly shape how the simulated match plays out.

## Current phase: PoC
Scope, strictly:
1. **Draft screen** — picks only, no bans. Order: B1 / R1 R2 / B2 B3 / R3 R4 / B4 B5 / R5. AI opponent drafts from a role-priority list. A coach recommendation is displayed each pick; following or ignoring it sets a sim modifier.
2. **Match simulation + viewer** — watchable, reads like a real LoL game (see GDD.md).

Out of scope for PoC (do not build yet): club creation, calendar, budget, mercato, marketing, save system beyond a single match.

## Frozen technical decisions
- **Engine**: Godot 4.x (latest stable), GDScript.
- **Architecture**: strict separation of simulation core and rendering.
  - `sim/`: pure GDScript, no Node/scene dependencies. Deterministic, tick-based (10 ticks/sim-second), seeded RNG. Input: match setup (teams, players, draft, modifiers, seed). Output: ordered event stream + per-tick world snapshots (positions, HP, levels, gold).
  - `game/`: Godot scenes that play back the tick stream (interpolation, animations, UI). Playback speed controls: 1x / 4x / 16x / skip-to-result. Default 1x ≈ 8 real minutes per match.
  - The sim must run **headless** (`godot --headless --script`) for batch balancing runs.
- **Determinism rule**: same input + seed ⇒ identical match. Never break this (no unseeded randf, no frame-dependent logic in sim/).

## Working methodology
- Maintain `GDD.md` (design truth), `BACKLOG.md` (status + active work only), and `CHANGELOG.md` (full rationale/history for completed work). Update them as you work; when the designer gives new direction, translate it into GDD/BACKLOG edits before coding.
- Work milestone by milestone from BACKLOG.md. Each milestone ends with:
  1. A runnable state (project opens and runs in Godot).
  2. A short report in `REPORTS/` — what changed, what to look at in-game, open design questions (only questions a designer must answer; decide technical matters yourself).
  3. When a milestone (or phase) is marked done, move its detailed narrative from BACKLOG.md into CHANGELOG.md, leaving only a one-line status entry behind.
- **Balancing is data-driven**: write headless batch runners (e.g. 500–1000 sims) reporting win rate by side/comp, game length distribution, kill counts. Bring the designer numbers, not guesses.
- All game data (characters, players, teams) lives in data files (JSON or Godot resources), never hardcoded, so the designer can review/tune values by reading a file.
- Commit with clear messages at each coherent step. Keep the project runnable at every commit.
- Placeholder art: one shared character sprite, recolored/tinted per team and marked per role (icon or letter). Structure sprite handling so per-character sprites can be dropped in later without code changes (sprite path = data field on the character).

## Definition of "watchable" (PoC success criteria)
A person watching at 1x for 8 minutes should be able to narrate the match: "top is split-pushing, jungler ganked mid, they're grouping for dragon, carry is fed and carrying fights." If a match reads as random dots wandering, the milestone is not done.
