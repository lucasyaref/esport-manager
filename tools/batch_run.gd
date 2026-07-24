extends SceneTree
## Batch validation: runs N full matches headless and reports the distributions
## that tell us whether the sim produces plausible *and* well-behaved games.
##
## M3 measured outcomes (win rate, length, kills) and passed while the behaviour
## underneath was broken — so M4.5-G adds behavioural metrics: where kills happen,
## solo vs assisted, before vs after 14 min, fight count and duration, gank
## coordination, mid-game levels — plus assertions for the bugs the designer had
## to catch by eye (nobody off the map, no squad out of its lane).
##
## Usage:
##   godot --headless --path . --script res://tools/batch_run.gd -- [--sims=N] [--start-seed=N]

const LENGTH_BUCKETS := [20, 25, 30, 35, 40, 45]
const LANE_RADIUS := 6.0    # within this of a lane polyline counts as that lane
const PIT_RADIUS := 8.0


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
	var map := SimMap.new(data.map)
	var role_of := {}
	for pid: String in data.players:
		role_of[pid] = data.players[pid].role
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
	# --- behavioural metrics (G) ---
	var solo_kills := 0
	var tower_kills := 0
	var early_kills := 0            # before 14 min
	var region_hist := {"top": 0, "mid": 0, "bot": 0, "river_jungle": 0, "pit": 0}
	var role_kills := {}
	var fight_count := 0
	var fight_dur: Array[float] = []
	var gank_calls := 0
	var gank_reactors := 0
	var level_mid: Array[float] = []   # avg level at the ~30-min snapshot
	# --- macro metrics (M5; extended per phase as the plays land) ---
	var first_tower_min: Array[float] = []             # when the match's first tower falls
	var first_tower_lane := {"top": 0, "mid": 0, "bot": 0}
	var swap_events := 0                               # total lane swaps (both teams)
	var both_swapped := 0                              # matches where both teams swapped (mirror)
	# Assertions: things the designer had to spot by eye. Any hit is a hard fail.
	var oob := 0
	var squad_oob := 0
	const EARLY_TICK := 14 * 60 * SimMatch.TICKS_PER_SECOND
	const MID_TICK := 30 * 60 * SimMatch.TICKS_PER_SECOND
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
			# Snapshots every 15 sim-min keep 1000-sim batches cheap while giving
			# us the 15-min gold checkpoint, the 30-min level checkpoint, and a
			# sampled position stream for the out-of-bounds assertions.
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
		var first_tower_t := -1
		var swaps_this := 0
		for ev: Dictionary in result.events:
			match ev.type:
				"kill":
					kills += 1
					if fb < 0:
						fb = ev.t / (60.0 * SimMatch.TICKS_PER_SECOND)
					if ev.data.assists.is_empty() and ev.data.get("killer", "") != "":
						solo_kills += 1
					if ev.data.get("source", "player") == "tower":
						tower_kills += 1
					if ev.t < EARLY_TICK:
						early_kills += 1
					region_hist[_region(map, _vec(ev.data.pos))] += 1
					var killer: String = ev.data.get("killer", "")
					if role_of.has(killer):
						role_kills[role_of[killer]] = role_kills.get(role_of[killer], 0) + 1
				"fight_end":
					fight_count += 1
					fight_dur.append(float(ev.data.duration_s))
				"gank_call":
					gank_calls += 1
					gank_reactors += int(ev.data.reactors)
				"lane_swap":
					swaps_this += 1
				"objective_taken":
					if ev.data.objective == "dragon":
						dragons += 1
					else:
						barons += 1
				"tower_destroyed":
					towers += 1
					if first_tower_t < 0:
						first_tower_t = int(ev.t)
						first_tower_lane[ev.data.lane] += 1
		kill_totals.append(kills)
		if fb >= 0:
			first_bloods.append(fb)
		if first_tower_t >= 0:
			first_tower_min.append(first_tower_t / (60.0 * SimMatch.TICKS_PER_SECOND))
		swap_events += swaps_this
		if swaps_this >= 2:
			both_swapped += 1
		# Snapshots: [0]=t0, [1]=15min, [2]=30min, ... Level checkpoint at 30 min,
		# and every snapshot feeds the position assertions.
		for si in range(result.snapshots.size()):
			var snap: Dictionary = result.snapshots[si]
			for row: Array in snap.players:
				if not map.in_bounds(Vector2(row[1], row[2])):
					oob += 1
			for lane_row: Array in snap.get("lanes", []):
				for q: Array in (lane_row[4] if lane_row.size() > 4 else []):
					if q[1] < -0.001 or q[1] > 1.001:
						squad_oob += 1
			if int(snap.t) == MID_TICK:
				var lv := 0.0
				for row: Array in snap.players:
					lv += row[3]
				level_mid.append(lv / snap.players.size())
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

	var total_kills := 0
	for v in kill_totals:
		total_kills += int(v)
	print("")
	print("| Behaviour | Value |")
	print("|---|---|")
	print("| Kills before 14 min | %.0f%% |" % (100.0 * early_kills / maxi(total_kills, 1)))
	print("| Solo kills (no assist) | %.0f%% |" % (100.0 * solo_kills / maxi(total_kills, 1)))
	print("| Tower kills | %.1f%% |" % (100.0 * tower_kills / maxi(total_kills, 1)))
	print("| Fights per match | %.1f |" % (float(fight_count) / sims))
	print("| Fight duration avg (s) | %.0f |" % _avg(fight_dur))
	print("| Gank calls per match | %.1f |" % (float(gank_calls) / sims))
	print("| Gank followers avg | %.2f |" % (float(gank_reactors) / maxi(gank_calls, 1)))
	print("| Avg level @30min | %.1f |" % _avg(level_mid))
	print("")
	print("| Kill region | Share |")
	print("|---|---|")
	for r: String in region_hist:
		print("| %s | %.0f%% |" % [r, 100.0 * region_hist[r] / maxi(total_kills, 1)])
	print("")
	print("| Killer role | Share |")
	print("|---|---|")
	for role in DataLoader.ROLES:
		print("| %s | %.0f%% |" % [role, 100.0 * role_kills.get(role, 0) / maxi(total_kills, 1)])

	print("")
	print("| Macro (M5) | Value |")
	print("|---|---|")
	print("| First tower avg (min) | %.1f |" % _avg(first_tower_min))
	var ft_total := first_tower_min.size()
	for lane in ["top", "mid", "bot"]:
		print("| First tower is %s | %.0f%% |" % [lane, 100.0 * first_tower_lane[lane] / maxi(ft_total, 1)])
	print("| Lane swap rate (team-games) | %.0f%% |" % (100.0 * swap_events / maxi(2 * sims, 1)))
	print("| Both teams swapped (mirror) | %.0f%% |" % (100.0 * both_swapped / sims))

	print("")
	if oob == 0 and squad_oob == 0:
		print("ASSERTIONS: PASS (no agent off the map, no squad out of its lane)")
	else:
		print("ASSERTIONS: FAIL — off-map player samples: %d, out-of-lane squad samples: %d" % [
			oob, squad_oob])
		quit(1)
		return
	quit(0)


## Classify where a kill happened: a pit, one of the three lanes, or the open
## river/jungle between them. Lanes are polylines, so we sample each and take the
## nearest — cheap and good enough for a distribution.
func _region(map: SimMap, pos: Vector2) -> String:
	if pos.distance_to(map.pits.dragon) < PIT_RADIUS or pos.distance_to(map.pits.baron) < PIT_RADIUS:
		return "pit"
	var best_lane := ""
	var best_d := INF
	for lane in SimMap.LANES:
		for k in 24:
			var d := pos.distance_to(map.pos_on_lane(lane, k / 23.0))
			if d < best_d:
				best_d = d
				best_lane = lane
	return best_lane if best_d <= LANE_RADIUS else "river_jungle"


func _vec(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


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
