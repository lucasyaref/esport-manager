class_name Highlights
extends RefCounted
## Turns a finished match's event stream into the handful of moments worth
## watching (M6-A). Pure analysis: it reads the sim's output, it never runs
## inside the sim and never influences it. That is also what makes it a balance
## instrument — "does this match contain 5-10 things worth watching?" is a
## question about the sim, and the answer is measurable before any camera work
## exists (BACKLOG, M5-G / M6-A).
##
## Deterministic by construction: one ordered pass over an ordered event list,
## with every sort tie broken by the event's own index. Same seed => same reel.
##
## Three stages, separately testable:
##   moments(events, ticks, cfg) -> every candidate moment, scored
##   select(moments, cfg)        -> the reel: floor, spacing, diversity, cap
##   describe(moment, map)       -> the one-line reel text the designer reads

## Most-interesting-first. A merged moment takes the best name in it, so a
## skirmish that ends with baron reads as "baron" and not as "skirmish".
const KIND_RANK: Array[String] = [
	"nexus", "baron", "teamfight", "tower_base", "dragon", "fight",
	"tower_inner", "skirmish", "tower_outer", "pick",
]

## Used when data/highlights.json is missing or partial. The file is the truth
## the designer tunes; this only keeps the module usable on its own.
const DEFAULT_CONFIG := {
	"merge_window_s": 8.0,
	"merge_radius": 18.0,
	"score": {
		"kill": 10.0,
		"multikill": 8.0,
		"ace": 25.0,
		"ace_deaths": 4,
		"participant": 3.0,
		"gold_per_1000": 6.0,
		"late_bonus": 0.6,
		"pick": 0.0, "skirmish": 0.0, "fight": 0.0, "teamfight": 0.0,
		"dragon": 12.0, "baron": 30.0,
		"tower_outer": 4.0, "tower_inner": 8.0, "tower_base": 14.0,
		"nexus": 200.0,
	},
	"select": {
		"max_moments": 10,
		"floor": 30.0,
		"min_spacing_s": 45.0,
		"max_per_kind": 4,
	},
}


static func load_config(path := "res://data/highlights.json") -> Dictionary:
	var cfg := DEFAULT_CONFIG.duplicate(true)
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


# --- stage 1: candidates ------------------------------------------------------

## Every candidate moment in the match, scored, in clock order.
##
## Kills, fights, objectives and structures all become *anchors* with a time
## span and a position; anchors that overlap in both are one moment. That is
## why a gank, the tower it buys and the dragon it enables read as one thing
## rather than three — which is how a viewer would see it.
static func moments(events: Array, ticks: int, cfg: Dictionary) -> Array:
	var tps := float(SimMatch.TICKS_PER_SECOND)
	var window := int(float(cfg.merge_window_s) * tps)
	var radius := float(cfg.merge_radius)

	var raw: Array[Dictionary] = []
	for i in events.size():
		var anchor := _anchor(events[i], i, tps)
		if not anchor.is_empty():
			raw.append(anchor)
	# fight_end fires at the *end* of its fight, so the stream's own order is not
	# start order. `seq` keeps the sort a total order regardless of ties.
	raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.start != b.start:
			return a.start < b.start
		return a.seq < b.seq)

	var done: Array[Dictionary] = []
	var open: Array[Dictionary] = []
	for anchor in raw:
		var still: Array[Dictionary] = []
		for mom in open:
			if anchor.start - int(mom.end) > window:
				done.append(mom)
			else:
				still.append(mom)
		open = still
		var host := {}
		for mom in open:
			if Vector2(mom.pos[0], mom.pos[1]).distance_to(
					Vector2(anchor.pos[0], anchor.pos[1])) <= radius:
				host = mom
				break
		if host.is_empty():
			open.append(_new_moment(anchor))
		else:
			_absorb(host, anchor)
	done.append_array(open)

	for mom in done:
		mom.kind = _best_kind(mom.kinds)
		mom.men = int(mom.peak.blue) + int(mom.peak.red)
		mom.score = _score(mom, ticks, cfg.score)
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.start != b.start:
			return a.start < b.start
		return a.seq < b.seq)
	return done


## One event -> one anchor, or {} for events that are not moments in themselves.
static func _anchor(ev: Dictionary, seq: int, tps: float) -> Dictionary:
	var t := int(ev.t)
	var d: Dictionary = ev.data
	var base := {
		"seq": seq, "start": t, "end": t, "pos": d.get("pos", [0.0, 0.0]),
		"kind": "", "kills": 0, "deaths": {"blue": 0, "red": 0},
		"peak": {"blue": 0, "red": 0}, "gold": 0,
		"victims": [], "killers": [], "objectives": [], "label": "",
	}
	match str(ev.type):
		"kill":
			base.kind = "pick"
			base.kills = 1
			base.deaths[str(d.get("victim_team", "blue"))] = 1
			base.victims = [str(d.victim)]
			if str(d.get("killer", "")) != "":
				base.killers = [str(d.killer)]
			return base
		"fight_end":
			# The span is the fight itself, so the kills inside it land in the
			# same moment rather than trailing off the end of a point event.
			base.kind = str(d.context)
			base.start = t - int(float(d.get("duration_s", 0)) * tps)
			base.peak = {"blue": int(d.peak.blue), "red": int(d.peak.red)}
			base.gold = absi(int(d.gold.blue) - int(d.gold.red))
			return base
		"objective_taken":
			base.kind = str(d.objective)
			base.objectives = [str(d.objective)]
			base.label = "%s to %s" % [d.objective, d.team]
			return base
		"tower_destroyed":
			base.kind = "tower_%s" % d.tier
			base.label = "%s's %s tower (%s)" % [d.team, d.tier, d.lane]
			return base
		"nexus_destroyed":
			base.kind = "nexus"
			base.label = "nexus falls, %s wins" % d.winner
			return base
	return {}


static func _new_moment(anchor: Dictionary) -> Dictionary:
	var mom := anchor.duplicate(true)
	mom.kinds = {anchor.kind: 1}
	# kind -> the thing that happened, for the reel line. Keyed by kind so a
	# moment that is named "baron" prints the baron and not the tower next to it.
	mom.labels = {anchor.kind: anchor.label} if anchor.label != "" else {}
	mom.erase("label")
	mom.kind = ""   # filled by _best_kind once the moment stops growing
	mom.men = 0
	mom.score = 0.0
	return mom


static func _absorb(mom: Dictionary, anchor: Dictionary) -> void:
	mom.end = maxi(int(mom.end), int(anchor.end))
	mom.start = mini(int(mom.start), int(anchor.start))
	mom.kinds[anchor.kind] = int(mom.kinds.get(anchor.kind, 0)) + 1
	mom.kills += int(anchor.kills)
	for side: String in mom.deaths:
		mom.deaths[side] = int(mom.deaths[side]) + int(anchor.deaths[side])
		# Peak is the largest either side ever got *at once*, so it is a max and
		# never a sum: two 2v2s eight seconds apart are not a 4v4.
		mom.peak[side] = maxi(int(mom.peak[side]), int(anchor.peak[side]))
	mom.gold = maxi(int(mom.gold), int(anchor.gold))
	mom.victims.append_array(anchor.victims)
	mom.killers.append_array(anchor.killers)
	mom.objectives.append_array(anchor.objectives)
	if anchor.label != "" and not mom.labels.has(anchor.kind):
		mom.labels[anchor.kind] = anchor.label


static func _best_kind(kinds: Dictionary) -> String:
	for kind in KIND_RANK:
		if kinds.has(kind):
			return kind
	return "pick"


static func _score(mom: Dictionary, ticks: int, w: Dictionary) -> float:
	var s := 0.0
	s += float(w.kill) * mom.kills
	var worst := maxi(int(mom.deaths.blue), int(mom.deaths.red))
	if worst > 1:
		s += float(w.multikill) * (worst - 1)
	if worst >= int(w.ace_deaths):
		s += float(w.ace)
	s += float(w.participant) * (int(mom.peak.blue) + int(mom.peak.red))
	s += float(w.gold_per_1000) * (float(mom.gold) / 1000.0)
	for kind: String in mom.kinds:
		s += float(w.get(kind, 0.0)) * int(mom.kinds[kind])
	# The same play is worth more at 30 minutes than at 4: later moments decide
	# the game, and a reel that opens on a level-2 invade is a reel nobody asked
	# for. A multiplier rather than a filter, so an early ace still makes it.
	var frac := clampf(float(mom.start) / maxf(1.0, float(ticks)), 0.0, 1.0)
	return s * (1.0 + float(w.late_bonus) * frac)


# --- stage 2: the reel --------------------------------------------------------

## The moments actually worth showing: an absolute floor (a bad match gets a
## short reel, it does not get padded), spacing so the reel is not five clips of
## one 40-second brawl, a per-kind cap for variety, and a hard count.
## The game ending is exempt from all four — a match always ends on its nexus.
static func select(all_moments: Array, cfg: Dictionary) -> Array:
	var sel: Dictionary = cfg.select
	var spacing := int(float(sel.min_spacing_s) * SimMatch.TICKS_PER_SECOND)
	var ranked := all_moments.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score:
			return a.score > b.score
		return a.seq < b.seq)

	var picked: Array[Dictionary] = []
	var per_kind := {}
	for mom in ranked:
		if str(mom.kind) != "nexus":
			if mom.score < float(sel["floor"]):
				continue
			if picked.size() >= int(sel.max_moments):
				continue
			if int(per_kind.get(mom.kind, 0)) >= int(sel.max_per_kind):
				continue
			var clash := false
			for p in picked:
				if absi(int(p.start) - int(mom.start)) < spacing:
					clash = true
					break
			if clash:
				continue
		picked.append(mom)
		per_kind[mom.kind] = int(per_kind.get(mom.kind, 0)) + 1
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.start != b.start:
			return a.start < b.start
		return a.seq < b.seq)
	return picked


static func reel(events: Array, ticks: int, cfg: Dictionary) -> Array:
	return select(moments(events, ticks, cfg), cfg)


# --- stage 3: reading it ------------------------------------------------------

## The line the designer reads at the M6-A gate: "07:42 — gank bot, 2 kills".
static func describe(mom: Dictionary, map: SimMap = null) -> String:
	var place := ""
	if map != null:
		var region: String = map.region(Vector2(mom.pos[0], mom.pos[1]))
		place = "" if region in ["pit", "river_jungle"] else " " + region
	var head: String = mom.labels.get(mom.kind, "")
	if head == "":
		match str(mom.kind):
			"pick":
				head = ("gank" if mom.kills > 0 else "trade") + place
			_:
				head = str(mom.kind) + place
	var bits: Array[String] = []
	if mom.kills > 0:
		bits.append("%d kill%s" % [mom.kills, "" if mom.kills == 1 else "s"])
	if int(mom.men) >= 4:
		bits.append("%d men" % mom.men)
	for kind: String in mom.labels:
		if kind != mom.kind:
			bits.append(str(mom.labels[kind]))
	var tail := (", " + ", ".join(bits)) if not bits.is_empty() else ""
	return "%s — %s%s" % [clock(int(mom.start)), head, tail]


static func clock(t: int) -> String:
	var total := int(t / float(SimMatch.TICKS_PER_SECOND))
	return "%02d:%02d" % [floori(total / 60.0), total % 60]
