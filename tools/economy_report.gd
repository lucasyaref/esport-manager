extends SceneTree
## M2 economy report: runs N full matches headless and prints per-role
## gold / CS / level curves (markdown). This is the tool that answers
## "do the economy curves look sane" with numbers.
##
## Usage:
##   godot --headless --path . --script res://tools/economy_report.gd -- [--sims=N] [--minutes=N]

const FIRST_SEED := 1000
const CHECK_MINUTES := [5, 10, 15, 20, 25, 30]


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			args[parts[0]] = parts[1]
	var sims := int(args.get("sims", "10"))
	var minutes := int(args.get("minutes", str(SimMatch.DEFAULT_DURATION_MIN)))

	var data := DataLoader.load_all()
	if not data.errors.is_empty():
		print("DATA ERRORS: %s" % str(data.errors))
		quit(1)
		return

	# role -> minute -> Array of values (one per player-sample)
	var gold := _empty_series()
	var cs := _empty_series()
	var levels := _empty_series()

	for i in range(sims):
		var setup := {
			"seed": FIRST_SEED + i,
			"duration_ticks": minutes * 60 * SimMatch.TICKS_PER_SECOND,
			"snapshot_every": 10,  # 1 snapshot per sim-second
		}
		var sim := SimMatch.new(setup, data)
		var result := sim.run()
		var role_of := {}
		for agent in sim.agents:
			role_of[agent.id] = agent.role
		for minute in CHECK_MINUTES:
			if minute > minutes:
				continue
			var snap_index: int = minute * 60
			if snap_index >= result.snapshots.size():
				snap_index = result.snapshots.size() - 1
			var snap: Dictionary = result.snapshots[snap_index]
			for row: Array in snap.players:
				var role: String = role_of[row[0]]
				gold[role][minute].append(float(row[4]))
				levels[role][minute].append(float(row[3]))
				cs[role][minute].append(float(row[5]))

	print("Economy report — %d sims × %d minutes (seeds %d..%d)\n" % [
		sims, minutes, FIRST_SEED, FIRST_SEED + sims - 1])
	_print_table("Average total gold", gold, minutes)
	_print_table("Average CS", cs, minutes)
	_print_table("Average level", levels, minutes)
	_print_gold_per_min(gold, minutes)
	quit(0)


func _empty_series() -> Dictionary:
	var out := {}
	for role in DataLoader.ROLES:
		out[role] = {}
		for minute in CHECK_MINUTES:
			out[role][minute] = []
	return out


func _print_table(title: String, series: Dictionary, minutes: int) -> void:
	print("## %s\n" % title)
	var header := "| Role |"
	var sep := "|---|"
	for minute in CHECK_MINUTES:
		if minute <= minutes:
			header += " @%d |" % minute
			sep += "---|"
	print(header)
	print(sep)
	for role in DataLoader.ROLES:
		var row := "| %s |" % role
		for minute in CHECK_MINUTES:
			if minute <= minutes:
				row += " %.1f |" % _avg(series[role][minute])
		print(row)
	print("")


func _print_gold_per_min(gold: Dictionary, minutes: int) -> void:
	print("## Gold per minute (per 5-minute bucket)\n")
	var buckets: Array = []
	for minute in CHECK_MINUTES:
		if minute <= minutes:
			buckets.append(minute)
	var header := "| Role |"
	var sep := "|---|"
	for i in buckets.size():
		var from: int = 0 if i == 0 else buckets[i - 1]
		header += " %d-%d |" % [from, buckets[i]]
		sep += "---|"
	print(header)
	print(sep)
	for role in DataLoader.ROLES:
		var row := "| %s |" % role
		for i in buckets.size():
			var from_val: float = 0.0 if i == 0 else _avg(gold[role][buckets[i - 1]])
			var span: float = float(buckets[i] - (0 if i == 0 else buckets[i - 1]))
			row += " %.0f |" % ((_avg(gold[role][buckets[i]]) - from_val) / span)
		print(row)
	print("")


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
