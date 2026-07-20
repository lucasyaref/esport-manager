extends SceneTree
## Runs one match simulation headless and prints the scoreboard.
##
## Usage:
##   godot --headless --path . --script res://tools/headless_run.gd -- [--seed=N] [--minutes=N] [--events]
##
## --events prints the full event log (one JSON line per event).


func _initialize() -> void:
	var args := _parse_user_args()
	var match_seed := int(args.get("seed", "42"))
	var minutes := int(args.get("minutes", str(SimMatch.DEFAULT_DURATION_MIN)))

	var data := DataLoader.load_all()
	if not data.errors.is_empty():
		for e in data.errors:
			print("DATA ERROR: %s" % e)
		quit(1)
		return

	var setup := {"seed": match_seed, "duration_ticks": minutes * 60 * SimMatch.TICKS_PER_SECOND}
	var result := SimMatch.new(setup, data).run()

	print("seed=%d events=%d winner=%s length=%.1fmin checksum=%s" % [
		match_seed, result.events.size(),
		result.winner if result.winner != "" else "none (timeout)",
		result.ticks / (60.0 * SimMatch.TICKS_PER_SECOND), result.checksum,
	])
	print("%-10s %-8s %-9s %5s %5s %9s %7s %7s" % [
		"handle", "team", "role", "level", "cs", "k/d/a", "gold", "power"])
	for row: Dictionary in result.summary:
		print("%-10s %-8s %-9s %5d %5d %9s %7d %7d" % [
			row.handle, row.team, row.role, row.level, row.cs,
			"%d/%d/%d" % [row.kills, row.deaths, row.assists], row.gold, row.item_power])
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
