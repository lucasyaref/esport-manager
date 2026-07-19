extends SceneTree
## Runs one match simulation headless and prints a summary.
##
## Usage:
##   godot --headless --path . --script res://tools/headless_run.gd -- [--seed=N] [--ticks=N] [--events]
##
## --events prints the full event log (one JSON line per event).


func _initialize() -> void:
	var args := _parse_user_args()
	var match_seed := int(args.get("seed", "42"))
	var ticks := int(args.get("ticks", str(60 * SimMatch.TICKS_PER_SECOND)))

	var result := SimMatch.new({"seed": match_seed, "duration_ticks": ticks}).run()

	print("seed=%d ticks=%d events=%d checksum=%s" % [
		match_seed, ticks, result.events.size(), result.checksum,
	])
	if args.has("events"):
		for ev in result.events:
			print(JSON.stringify(ev))
	quit(0)


func _parse_user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			out[parts[0]] = parts[1]
		else:
			out[stripped] = "true"
	return out
