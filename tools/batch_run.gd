extends SceneTree
## M3 batch validation: runs N full matches headless and reports the
## distributions that tell us whether the sim produces plausible games —
## side win rate, match length, kills, objectives, first blood.
##
## Usage:
##   godot --headless --path . --script res://tools/batch_run.gd -- [--sims=N] [--start-seed=N]

const LENGTH_BUCKETS := [20, 25, 30, 35, 40, 45]


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var stripped: String = arg.lstrip("-")
		if stripped.contains("="):
			var parts := stripped.split("=", true, 1)
			args[parts[0]] = parts[1]
	var sims := int(args.get("sims", "200"))
	var start_seed := int(args.get("start-seed", "5000"))

	var data := DataLoader.load_all()
	if not data.errors.is_empty():
		print("DATA ERRORS: %s" % str(data.errors))
		quit(1)
		return

	var team_ids: Array = data.teams.keys()
	var wins := {"blue": 0, "red": 0, "": 0}
	var team_wins := {team_ids[0]: 0, team_ids[1]: 0}
	var lengths: Array[float] = []
	var kill_totals: Array[float] = []
	var first_bloods: Array[float] = []
	var dragons := 0
	var barons := 0
	var towers := 0
	var length_hist := {}
	for b in LENGTH_BUCKETS:
		length_hist[b] = 0
	# Snowball measure: at 15 sim-min, which side leads in gold, and did they
	# win? "Leads matter" pushes this above 50%; "comeback-friendly" keeps it
	# well below 100%.
	const LEAD_TICK := 15 * 60 * SimMatch.TICKS_PER_SECOND
	var lead_decided := 0
	var lead_won := 0
	var lead_gaps: Array[float] = []

	var t_start := Time.get_ticks_msec()
	for i in range(sims):
		# Alternate which team plays blue side so side bias and team strength
		# are measured independently.
		var swap := i % 2 == 1
		var setup := {
			# Sparse snapshots (every 15 sim-min) keep 1000-sim batches cheap
			# while still giving us the 15-min gold checkpoint.
			"seed": start_seed + i, "snapshot_every": LEAD_TICK,
			"teams": {
				"blue": team_ids[1] if swap else team_ids[0],
				"red": team_ids[0] if swap else team_ids[1],
			},
		}
		var sim := SimMatch.new(setup, data)
		var team_of := {}
		for agent in sim.agents:
			team_of[agent.id] = agent.team
		var result := sim.run()
		wins[result.winner] += 1
		if result.winner != "":
			team_wins[setup.teams[result.winner]] += 1
			# snapshots[1] is the t=LEAD_TICK capture (snapshots[0] is t=0).
			if result.snapshots.size() >= 2:
				var gold := {"blue": 0.0, "red": 0.0}
				for row: Array in result.snapshots[1].players:
					gold[team_of[row[0]]] += row[4]
				var leader: String = "blue" if gold.blue >= gold.red else "red"
				lead_decided += 1
				lead_gaps.append(absf(gold.blue - gold.red))
				if leader == result.winner:
					lead_won += 1
		var minutes: float = result.ticks / (60.0 * SimMatch.TICKS_PER_SECOND)
		lengths.append(minutes)
		for b in LENGTH_BUCKETS:
			if minutes <= b:
				length_hist[b] += 1
				break
		var kills := 0
		var fb := -1.0
		for ev: Dictionary in result.events:
			match ev.type:
				"kill":
					kills += 1
					if fb < 0:
						fb = ev.t / (60.0 * SimMatch.TICKS_PER_SECOND)
				"objective_taken":
					if ev.data.objective == "dragon":
						dragons += 1
					else:
						barons += 1
				"tower_destroyed":
					towers += 1
		kill_totals.append(kills)
		if fb >= 0:
			first_bloods.append(fb)
	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0

	print("Batch: %d sims (seeds %d..%d) in %.1fs\n" % [sims, start_seed, start_seed + sims - 1, elapsed])
	print("| Metric | Value |")
	print("|---|---|")
	print("| Blue side win rate | %.1f%% |" % (100.0 * wins.blue / sims))
	print("| Red side win rate | %.1f%% |" % (100.0 * wins.red / sims))
	print("| %s win rate | %.1f%% |" % [team_ids[0], 100.0 * team_wins[team_ids[0]] / sims])
	print("| %s win rate | %.1f%% |" % [team_ids[1], 100.0 * team_wins[team_ids[1]] / sims])
	print("| Timeouts (no nexus by cap) | %d |" % wins[""])
	print("| Match length avg (min) | %.1f |" % _avg(lengths))
	print("| Match length min–max | %.1f – %.1f |" % [_amin(lengths), _amax(lengths)])
	print("| Kills per match avg | %.1f |" % _avg(kill_totals))
	print("| Kills min–max | %.0f – %.0f |" % [_amin(kill_totals), _amax(kill_totals)])
	print("| First blood avg (min) | %.1f |" % _avg(first_bloods))
	print("| Dragons per match | %.1f |" % (float(dragons) / sims))
	print("| Barons per match | %.1f |" % (float(barons) / sims))
	print("| Towers per match | %.1f |" % (float(towers) / sims))
	if lead_decided > 0:
		print("| Gold leader @15min won | %.1f%% |" % (100.0 * lead_won / lead_decided))
		print("| Avg gold gap @15min | %.0f |" % _avg(lead_gaps))
	print("")
	print("| Length bucket | Matches |")
	print("|---|---|")
	var prev := 0
	for b in LENGTH_BUCKETS:
		print("| %d–%d min | %d |" % [prev, b, length_hist[b]])
		prev = b
	quit(0)


func _avg(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _amin(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return values.reduce(func(a: float, b: float) -> float: return minf(a, b))


func _amax(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return values.reduce(func(a: float, b: float) -> float: return maxf(a, b))
