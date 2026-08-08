#!/usr/bin/env bash
# CI-style project check. (Designer: you can ignore this file.)
#
# Runs the headless determinism check. Exits 0 if everything passes.
# Usage: tools/check.sh   (from anywhere; finds the project root itself)
#
# Godot binary lookup order: $GODOT_BIN, `godot` on PATH, then the standard
# macOS app locations.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then echo "$GODOT_BIN"; return; fi
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  for app in "$HOME/Applications/Godot.app" "/Applications/Godot.app"; do
    if [[ -x "$app/Contents/MacOS/Godot" ]]; then echo "$app/Contents/MacOS/Godot"; return; fi
  done
  echo "ERROR: Godot not found. Install Godot 4.x or set GODOT_BIN." >&2
  exit 1
}

GODOT="$(find_godot)"
echo "Using Godot: $GODOT ($("$GODOT" --version | head -1))"

# --- RNG discipline lint -----------------------------------------------------
# The determinism rule forbids any global-RNG usage inside sim/. This catches:
#  - unqualified calls to global RNG utilities (randf(), randi_range(), ...).
#    NB: GDScript utility functions SHADOW same-named class methods on
#    unqualified calls — this exact bug shipped once in M0 (SimRNG.chance()
#    silently used the global randf). Qualified calls (rng.randf()) are fine.
#  - Array.shuffle()/pick_random() (both use the global RNG),
#  - RandomNumberGenerator instances outside sim/rng.gd.
echo "--- sim/ RNG discipline lint ---"
if find "$PROJECT_ROOT/sim" -name '*.gd' -print0 | xargs -0 perl -ne '
    next if /^\s*#/ || /^\s*func\s/;
    my $bad = 0;
    $bad = 1 if /(?<![\w.])(randf_range|randi_range|randfn|randf|randi|randomize|seed)\s*\(/;
    $bad = 1 if /(?<!rng)\.(shuffle|pick_random)\s*\(/;
    $bad = 1 if $ARGV !~ /rng\.gd$/ && /RandomNumberGenerator/;
    if ($bad) { print "VIOLATION $ARGV:$.: $_"; $found = 1; }
    close ARGV if eof;
    END { exit($found ? 1 : 0) }
  '; then
  echo "lint OK"
else
  echo "RNG DISCIPLINE LINT: FAIL (unseeded/global RNG usage in sim/)"
  exit 1
fi

# First-time / post-clone import so script class cache and resources exist.
"$GODOT" --headless --path "$PROJECT_ROOT" --import >/dev/null 2>&1 || true

echo "--- data validation ---"
"$GODOT" --headless --path "$PROJECT_ROOT" --script res://tools/data_check.gd

# data/terrain.txt is hand-editable by design, so its guard rails belong in CI:
# 180-degree symmetry (blue-side win rate is a tracked metric), every map.json
# anchor on walkable ground, and no pocket of jungle sealed off by a stray wall.
echo "--- terrain guard rails ---"
"$GODOT" --headless --path "$PROJECT_ROOT" --script res://tools/terrain_tool.gd -- --check

echo "--- determinism check ---"
"$GODOT" --headless --path "$PROJECT_ROOT" --script res://tools/determinism_check.gd

# Plays a whole match back through the real viewer code with no display: catches
# playback regressions (a moved snapshot column, an event that stopped firing,
# a combat visual that never draws) without needing the designer to watch.
echo "--- viewer playback selftest ---"
"$GODOT" --headless --path "$PROJECT_ROOT" -- --seed=42 --selftest
