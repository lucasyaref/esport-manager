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
# Kill-rate timeline (M5-G, designer remark "not enough deaths"). Kills are
# bucketed by the minute they happen in, and each bucket is divided by the
# sim-minutes actually PLAYED in it across the batch — a raw kill count would
# make late buckets look empty simply because most matches have already ended.
# The result is combined-kills-per-minute (CKPM) over game time, the same shape
# pro-play stats sites report (LCK/LEC 2025: ~28 kills over ~32-34 min ≈ 0.85).
const BAND_MIN := 5
const BAND_COUNT := 9       # 0-5, 5-10, ... 40-45


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
	# The sandwich (M5-E, designer item 6): calls made off a board read rather than
	# an opportunistic roll, and how often they convert. Kept apart from the plain
	# gank numbers so the designer can see whether the *named play* is happening.
	var sandwich_calls := 0
	var sandwich_reactors := 0
	var sandwich_hits := 0
	# Tempo (M5-E): a kill opens the victim's lane; did the team spend that window
	# on the tower, or take the gold and wander off?
	var tempo_calls := 0
	var tempo_towers := 0
	# The committed multi-man play (M5-F2, item 3). The question the designer asked
	# is whether 2-3 players ever converge on one thing: these count how often a
	# play is called, how many bodies actually agreed to come, and how often the
	# window produced a kill. A play that never converts is priority given away.
	var play_calls := 0
	var play_men := 0
	var play_hits := 0
	# Connect rate (M5-C): a gank/roam call "connects" when the calling team lands
	# a kill within the window after posting it — the measure of whether CC-that-
	# catches actually turns plays into kills instead of whiffing.
	var connect_hits := 0
	# The call is posted when the jungler starts pathing; the kill lands after it
	# walks to lane and the fight resolves, so the window spans the gank's life
	# (commit_timeout is 25 s) plus a little for the fight itself.
	const CONNECT_WINDOW := 28 * SimMatch.TICKS_PER_SECOND
	# The tempo window the sim posts (macro.tempo_window_s); a tower that falls
	# inside it is the play converting.
	const TEMPO_WINDOW := 45 * SimMatch.TICKS_PER_SECOND
	# The play's own window (defense.play_window_s) plus a little for the fight it
	# is meant to start.
	const PLAY_WINDOW := 16 * SimMatch.TICKS_PER_SECOND
	# Kill-rate over game time + who actually dies (designer remarks 2 and 3).
	var band_kills: Array[float] = []
	var band_minutes: Array[float] = []
	for _b in BAND_COUNT:
		band_kills.append(0.0)
		band_minutes.append(0.0)
	var role_deaths := {}
	var total_minutes := 0.0
	# Nexus defence (designer remark 5): every 2 s that a nexus is taking damage
	# the sim reports who is home. Undefended = not one player at the doorstep.
	var nexus_samples := 0
	var nexus_undefended := 0
	var nexus_defenders := 0
	var level_mid: Array[float] = []   # avg level at the ~30-min snapshot
	# --- macro metrics (M5; extended per phase as the plays land) ---
	var first_tower_min: Array[float] = []             # when the match's first tower falls
	var first_tower_lane := {"top": 0, "mid": 0, "bot": 0}
	var swap_events := 0                               # total lane swaps (both teams)
	var both_swapped := 0                              # matches where both teams swapped (mirror)
	# --- watchability (M6-A's scorer, used here as a balance instrument) ---
	# "Does this match contain 5-10 things worth watching?" is a balance question
	# before it is a viewer question (BACKLOG, M5-G). The reel is a pure read of
	# the sim's own event stream, so measuring it in batch costs nothing — and it
	# is the instrument for M8's finding that the teamfight does not exist.
	var hl_cfg := Highlights.load_config()
	var moments_total: Array[float] = []
	var reel_sizes: Array[float] = []
	var reel_scores: Array[float] = []
	var reel_kinds := {}
	var reel_thirds := [0, 0, 0]          # where the reel falls over the game clock
	var multi_death_moments := 0          # moments where one side lost 2+ bodies
	var biggest_fight: Array[float] = []  # bodies in the match's largest fight
	# Bodies present at the fight's peak, both sides — the honest "how big do
	# fights get" distribution. 6 counts as "6 or more".
	var fight_peak_hist := {2: 0, 3: 0, 4: 0, 5: 0, 6: 0}
	# Bodies standing at the fight vs bodies actually swinging. The ratio splits
	# "the team never came" from "the team came and didn't fight" — two different
	# fixes, and only the measurement says which one we have.
	var fight_present := 0
	var fight_engaged := 0
	# ...and when they came and didn't fight, why. Guessing at this is how you
	# end up tuning the wrong number.
	var decline_hist := {}
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
		total_minutes += minutes
		for b in BAND_COUNT:
			band_minutes[b] += clampf(minutes - b * BAND_MIN, 0.0, float(BAND_MIN))
		for row: Dictionary in result.summary:
			role_deaths[row.role] = role_deaths.get(row.role, 0) + int(row.deaths)
		for b in LENGTH_BUCKETS:
			if minutes <= b:
				length_hist[b] += 1
				break
		var kills := 0
		var match_peak := 0
		var fb := -1.0
		var first_tower_t := -1
		var swaps_this := 0
		var open_calls: Array = []   # {team, until, hit} for the connect-rate metric
		var open_tempo: Array = []   # {team, lane, until} for the tempo-conversion metric
		var open_plays: Array = []   # {team, until, hit} for the multi-man play metric
		for ev: Dictionary in result.events:
			match ev.type:
				"kill":
					kills += 1
					band_kills[mini(int(ev.t / (60.0 * BAND_MIN * SimMatch.TICKS_PER_SECOND)),
						BAND_COUNT - 1)] += 1.0
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
					# Credit the earliest open call by the killer's team still in window.
					var kteam: String = team_of.get(killer, "")
					if kteam != "":
						for c: Dictionary in open_calls:
							if not c.hit and c.team == kteam and ev.t <= int(c.until):
								c.hit = true
								break
						for p: Dictionary in open_plays:
							if not p.hit and p.team == kteam and ev.t <= int(p.until):
								p.hit = true
								break
				"fight_end":
					fight_count += 1
					fight_dur.append(float(ev.data.duration_s))
					var peak: int = int(ev.data.peak.blue) + int(ev.data.peak.red)
					match_peak = maxi(match_peak, peak)
					fight_peak_hist[clampi(peak, 2, 6)] += 1
					fight_present += int(ev.data.present.blue) + int(ev.data.present.red)
					fight_engaged += peak
					for why: String in ev.data.declines:
						decline_hist[why] = int(decline_hist.get(why, 0)) \
							+ int(ev.data.declines[why])
				"gank_call":
					var is_sandwich: bool = String(ev.data.get("kind", "gank")) == "sandwich"
					gank_calls += 1
					gank_reactors += int(ev.data.reactors)
					if is_sandwich:
						sandwich_calls += 1
						sandwich_reactors += int(ev.data.reactors)
					open_calls.append({
						"team": team_of.get(ev.data.by, ev.data.team),
						"until": ev.t + CONNECT_WINDOW, "hit": false, "sandwich": is_sandwich})
				"play_call":
					play_calls += 1
					play_men += int(ev.data.men.size())
					open_plays.append({"team": ev.data.team,
						"until": ev.t + PLAY_WINDOW, "hit": false})
				"tempo_call":
					tempo_calls += 1
					open_tempo.append({"team": ev.data.team, "lane": ev.data.lane,
						"until": ev.t + TEMPO_WINDOW})
				"nexus_pressure":
					nexus_samples += 1
					nexus_defenders += int(ev.data.defenders)
					if int(ev.data.defenders) == 0:
						nexus_undefended += 1
				"lane_swap":
					swaps_this += 1
				"objective_taken":
					if ev.data.objective == "dragon":
						dragons += 1
					else:
						barons += 1
				"tower_destroyed":
					towers += 1
					for tp: Dictionary in open_tempo:
						if tp.lane == ev.data.lane and tp.team != ev.data.team \
								and ev.t <= int(tp.until):
							tempo_towers += 1
							break
					if first_tower_t < 0:
						first_tower_t = int(ev.t)
						first_tower_lane[ev.data.lane] += 1
		kill_totals.append(kills)
		biggest_fight.append(match_peak)
		# The reel, scored the same way the viewer will score it (M6-A).
		var moms := Highlights.moments(result.events, result.ticks, hl_cfg)
		var reel := Highlights.select(moms, hl_cfg)
		moments_total.append(moms.size())
		reel_sizes.append(reel.size())
		for mom: Dictionary in moms:
			if maxi(int(mom.deaths.blue), int(mom.deaths.red)) >= 2:
				multi_death_moments += 1
		for mom: Dictionary in reel:
			reel_scores.append(float(mom.score))
			reel_kinds[mom.kind] = int(reel_kinds.get(mom.kind, 0)) + 1
			reel_thirds[mini(2, int(3.0 * float(mom.start) / maxf(1.0, result.ticks)))] += 1
		for c: Dictionary in open_calls:
			if c.hit:
				connect_hits += 1
				if bool(c.get("sandwich", false)):
					sandwich_hits += 1
		for p: Dictionary in open_plays:
			if p.hit:
				play_hits += 1
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
	print("| Biggest fight of the match (bodies) | %.1f |" % _avg(biggest_fight))
	print("| Bodies at the fight, fighting / standing there | %.2f / %.2f |" % [
		float(fight_engaged) / maxi(fight_count, 1), float(fight_present) / maxi(fight_count, 1)])
	var declines_total := 0
	for why: String in decline_hist:
		declines_total += int(decline_hist[why])
	var decline_names: Array = decline_hist.keys()
	decline_names.sort()
	for why: String in decline_names:
		print("| ...standing there because: %s | %.0f%% |" % [
			why, 100.0 * decline_hist[why] / maxi(declines_total, 1)])
	var fights_total := maxi(fight_count, 1)
	for size in [2, 3, 4, 5, 6]:
		print("| Fights at %s bodies | %.0f%% |" % [
			"6+" if size == 6 else str(size), 100.0 * fight_peak_hist[size] / fights_total])
	print("| Gank calls per match | %.1f |" % (float(gank_calls) / sims))
	print("| Gank followers avg | %.2f |" % (float(gank_reactors) / maxi(gank_calls, 1)))
	print("| Gank connect rate | %.0f%% |" % (100.0 * connect_hits / maxi(gank_calls, 1)))
	print("| Sandwich calls per match | %.2f |" % (float(sandwich_calls) / sims))
	print("| Sandwich share of calls | %.0f%% |" % (100.0 * sandwich_calls / maxi(gank_calls, 1)))
	print("| Sandwich followers avg | %.2f |" % (float(sandwich_reactors) / maxi(sandwich_calls, 1)))
	print("| Sandwich connect rate | %.0f%% |" % (100.0 * sandwich_hits / maxi(sandwich_calls, 1)))
	print("| Multi-man plays per match | %.2f |" % (float(play_calls) / sims))
	print("| Multi-man play men avg | %.2f |" % (float(play_men) / maxi(play_calls, 1)))
	print("| Multi-man play connect rate | %.0f%% |" % (100.0 * play_hits / maxi(play_calls, 1)))
	print("| Tempo windows per match | %.2f |" % (float(tempo_calls) / sims))
	print("| Tempo windows that took the tower | %.0f%% |" % (100.0 * tempo_towers / maxi(tempo_calls, 1)))
	print("| Avg level @30min | %.1f |" % _avg(level_mid))
	# Watchability (M6-A). The reel is what a viewer would actually be shown, so
	# "moments in the reel" is the designer-facing number and the candidate count
	# is only there to show how much the floor is throwing away.
	print("| Moments in the reel | %.1f |" % _avg(reel_sizes))
	print("| Candidate moments | %.1f |" % _avg(moments_total))
	print("| Reel score avg | %.0f |" % _avg(reel_scores))
	print("| Moments where a side lost 2+ | %.2f |" % (float(multi_death_moments) / sims))
	var reel_total := maxi(int(_avg(reel_sizes) * sims), 1)
	var kind_names: Array = reel_kinds.keys()
	kind_names.sort()
	for kind: String in kind_names:
		print("| Reel is %s | %.0f%% |" % [kind, 100.0 * reel_kinds[kind] / reel_total])
	print("| Reel spread early/mid/late | %.0f%% / %.0f%% / %.0f%% |" % [
		100.0 * reel_thirds[0] / reel_total, 100.0 * reel_thirds[1] / reel_total,
		100.0 * reel_thirds[2] / reel_total])
	print("")
	print("| Kill rate over game time | Kills/min | Share of kills |")
	print("|---|---|---|")
	print("| _pro reference (LCK/LEC 2025)_ | _~0.85 overall_ | _—_ |")
	for b in BAND_COUNT:
		if band_minutes[b] < 1.0:
			continue
		print("| %d–%d min | %.2f | %.0f%% |" % [b * BAND_MIN, (b + 1) * BAND_MIN,
			band_kills[b] / band_minutes[b], 100.0 * band_kills[b] / maxf(float(total_kills), 1.0)])
	print("| **whole game** | **%.2f** | 100%% |" % (float(total_kills) / maxf(total_minutes, 1.0)))
	print("")
	print("| Deaths per match by role | Value |")
	print("|---|---|")
	for role in DataLoader.ROLES:
		print("| %s | %.1f |" % [role, float(role_deaths.get(role, 0)) / sims])
	print("")
	print("| Nexus under attack (2 s samples) | Value |")
	print("|---|---|")
	print("| Samples per match | %.1f |" % (float(nexus_samples) / sims))
	print("| Nobody home (0 defenders) | %.0f%% |" % (100.0 * nexus_undefended / maxi(nexus_samples, 1)))
	print("| Defenders present avg | %.2f |" % (float(nexus_defenders) / maxi(nexus_samples, 1)))
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
	return map.region(pos, LANE_RADIUS, PIT_RADIUS)


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
