extends SceneTree
## M6-A designer gate: run one match and print the moments it would show you.
##
## The whole point of the phase is that this is readable *before* any camera
## exists — if the reel does not describe a match worth watching, the problem is
## the sim, not the view (BACKLOG, M6 "why here in the plan").
##
## Usage:
##   godot --headless --path . --script res://tools/reel.gd -- [--seed=N] [--all]
##
## --all prints every candidate moment with its score, not just the selected
## reel, so the selection floor can be tuned against real numbers.


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			args[parts[0]] = parts[1]
		else:
			args[stripped] = "true"
	var match_seed := int(args.get("seed", "42"))

	var data := DataLoader.load_all()
	if not data.errors.is_empty():
		for e in data.errors:
			print("DATA ERROR: %s" % e)
		quit(1)
		return

	var map := SimMap.new(data.map)
	var cfg := Highlights.load_config()
	var result := SimMatch.new({"seed": match_seed}, data).run()
	var all_moments := Highlights.moments(result.events, result.ticks, cfg)
	var picked := Highlights.select(all_moments, cfg)

	print("seed=%d  %s wins  %.1f min  %d candidate moments, %d in the reel" % [
		match_seed, result.winner if result.winner != "" else "nobody",
		result.ticks / (60.0 * SimMatch.TICKS_PER_SECOND),
		all_moments.size(), picked.size()])
	print("")
	var shown: Array = all_moments if args.has("all") else picked
	var in_reel := {}
	for mom: Dictionary in picked:
		in_reel[mom.seq] = true
	for mom: Dictionary in shown:
		var mark := "*" if in_reel.has(mom.seq) else " "
		print("%s %-46s  %6.1f" % [mark, Highlights.describe(mom, map), mom.score])
	quit(0)
