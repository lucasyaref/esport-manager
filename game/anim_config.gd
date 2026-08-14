class_name AnimConfig
extends RefCounted
## M6-D/M6-D2: the character sprite sheet's layout (rows/cols/frame size) and
## its frame-advance timing. Viewer-only presentation config — nothing here can
## change how a match plays out, only how the already-reported state is
## drawn — so it lives in game/ rather than sim/, deliberately mirroring
## sim/highlights.gd's own load_config() shape (a file merges over an
## in-code default, section by section) even though it isn't sim analysis.
##
## M6-D2: sheet source moved from the procedural 24px placeholder to per-role
## LPC-derived art at 64px (tools/fetch_lpc_sprites.mjs) — frame size changed,
## row list didn't. game/main.gd's --selftest hard-asserts every anim_state
## the game can ever assign has a real row, so "die" and "recall" (poses the
## generator has no equivalent of) are still rows here, just built by reusing
## frames from an animation it does have rather than a dedicated LPC pose —
## see that script for exactly which frames. Both `sprite` (single path) and
## `sprite_by_side` (team-keyed) characters read this same global layout —
## there's one sheet shape for the whole roster, not one per texture.

const DEFAULT_CONFIG := {
	"sheet": {
		"frame_px": 64,
		"cols": 4,
		"rows": ["idle", "run", "attack", "cast", "hurt", "die", "recall"],
	},
	"timing": {
		"frame_ticks": 4.0,
		"die_ticks": 20.0,
	},
}


static func load_config(path := "res://data/animation.json") -> Dictionary:
	var cfg: Dictionary = DEFAULT_CONFIG.duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return cfg
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return cfg
	for key: String in parsed:
		if typeof(cfg.get(key)) == TYPE_DICTIONARY and typeof(parsed[key]) == TYPE_DICTIONARY:
			cfg[key].merge(parsed[key], true)
		else:
			cfg[key] = parsed[key]
	return cfg
