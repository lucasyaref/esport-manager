#!/usr/bin/env bash
# One iteration of gauntlet loop 1 — the map. (Designer: you never need to run this.)
#
#   tools/gauntlet.sh iter04              -> gate + .shots/iter04.png
#   tools/gauntlet.sh iter04 --overlay    -> also .shots/iter04-overlay.png
#   tools/gauntlet.sh iter04 --bare       -> terrain only, no towers/nexus
#   tools/gauntlet.sh iter04 --size=1400
#
# Gate first, then render. That order is the point of this script existing: the
# machine guard rails (symmetry, reachability, anchors on walkable ground) are
# things an agent grading its own picture will not notice and will not think to
# check, so they are wired in front of the render where they cannot be skipped.
#
# A failing gate still renders — a broken map is exactly the map you want to look
# at — but the script exits non-zero so the orchestrator sees it.
#
# Protocol and stopping rule: .claude/skills/gauntlet-map/SKILL.md
# Rubric and iteration log: docs/gauntlet-map.md
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 || "$1" == -* ]]; then
  echo "usage: tools/gauntlet.sh <label> [--overlay] [--size=N]" >&2
  echo "  e.g. tools/gauntlet.sh iter04 --overlay" >&2
  exit 2
fi
LABEL="$1"; shift

OVERLAY=0
BARE=0
SIZE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --overlay) OVERLAY=1 ;;
    --bare)    BARE=1 ;;
    --size=*)  SIZE_ARG="$arg" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

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

echo "=== gauntlet: $LABEL ==="
echo
echo "--- gate: terrain guard rails ---"
GATE_OUT="$("$GODOT" --headless --path "$PROJECT_ROOT" \
  --script res://tools/terrain_tool.gd -- --check 2>&1 | grep -v '^Godot Engine v' || true)"
echo "$GATE_OUT"

GATE_PASS=0
if grep -q "all guard rails pass" <<<"$GATE_OUT"; then
  GATE_PASS=1
fi

echo
echo "--- render ---"
# Structures on by default: the critics grade the picture a player watches, and
# game/map_view.gd draws towers and nexuses over the terrain every frame. --bare
# renders the terrain layer alone when you want to judge that in isolation.
STRUCT_ARG="--structures"
[[ $BARE -eq 1 ]] && STRUCT_ARG=""
"$PROJECT_ROOT/tools/shot.sh" --out="res://.shots/${LABEL}.png" ${STRUCT_ARG:+"$STRUCT_ARG"} ${SIZE_ARG:+"$SIZE_ARG"} \
  2>&1 | grep -v '^Godot Engine v\|^Metal \|^Vulkan \|^OpenGL ' || true
if [[ $OVERLAY -eq 1 ]]; then
  "$PROJECT_ROOT/tools/shot.sh" --out="res://.shots/${LABEL}-overlay.png" --overlay ${STRUCT_ARG:+"$STRUCT_ARG"} ${SIZE_ARG:+"$SIZE_ARG"} \
    2>&1 | grep -v '^Godot Engine v\|^Metal \|^Vulkan \|^OpenGL ' || true
fi

echo
echo "=== $LABEL: gate $([[ $GATE_PASS -eq 1 ]] && echo PASS || echo '*** FAIL ***') ==="
echo "image: .shots/${LABEL}.png"
[[ $OVERLAY -eq 1 ]] && echo "overlay: .shots/${LABEL}-overlay.png"
if [[ $GATE_PASS -ne 1 ]]; then
  echo
  echo "The gate failed. Fix the guard rails before spending a critic pass on the look —"
  echo "an asymmetric or unreachable map is wrong regardless of how it looks."
  echo "Symmetry repairs itself:  godot --headless --path . --script res://tools/terrain_tool.gd -- --mirror=red --write"
  exit 1
fi
exit 0
