#!/usr/bin/env bash
# Render the map to a PNG. (Designer: you never need to run this.)
#
# This is the gauntlet loop's shutter button — see docs/gauntlet-map.md.
#
#   tools/shot.sh                        -> .shots/map.png
#   tools/shot.sh --out=res://.shots/a.png --size=1400 --overlay
#   tools/shot.sh --out=res://.shots/a.png --structures
#
# Godot has no rendering context under --headless (the viewport texture comes
# back null), so this runs a real window. It is parked off-screen and lives for
# well under a second, but it does exist — that is why this is a script and not
# a flag on tools/check.sh.
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

# The window only has to exist for the render target to be valid; keep it small
# and out of the way. The image size is --size, not the window size.
"$GODOT" --path "$PROJECT_ROOT" \
  --script res://tools/shoot_map.gd \
  --resolution 320x240 \
  --position 6000,6000 \
  -- "$@"
