extends Control
## M4 — Match Viewer. Runs the deterministic sim once (it is pure GDScript, so
## in-process playback is byte-identical to a headless run), captures the event
## stream + per-tick snapshots, then plays the match back on a top-down map:
## champions move along interpolated positions, fights/ganks/objectives/towers
## fire off the exact-tick event stream, with a kill feed, scoreboard, clock,
## gold bar and 1x/4x/16x/skip playback controls.
##
## Architecture: this script owns the clock and all time-based state; MapView is
## a dumb renderer fed a resolved frame each tick. Nothing here mutates the sim.

const SNAP := 2                     # snapshot cadence for playback (ticks)
# Snapshot player-row columns (SimMatch._capture_snapshot; positional, append-only).
const P_X := 1
const P_Y := 2
const P_LEVEL := 3
const P_GOLD := 4
const P_CS := 5
const P_ALIVE := 6
const P_HP := 7
const P_MAX_HP := 8
const P_TARGET := 9
const P_FLAGS := 10
const P_SWING := 11
const SWING_TICKS := 5.0            # how long one auto-attack beat is drawn (ticks)
const RANGED_AT := 2.0              # attack_range (world units) at/above which a swing flies
const CC_TAG_TICKS := 12            # "SLOWED"/"STUNNED" popup life (ticks)
const SELFTEST_STEP := 4.0          # playback ticks per step in --selftest
# Body separation, for drawing only (see _spread_bodies).
const BODY_SPACE := 1.9             # world units of personal space between bodies
const SPREAD_PASSES := 3            # relaxation passes per frame
const TPS := SimMatch.TICKS_PER_SECOND
const BASE_TPS_1X := 40.0           # sim ticks per real second at 1x (~8 min / match)
const SPEEDS := [1, 4, 16]
const FEED_MAX := 12
const C_BLUE := "6fa8ff"
const C_RED := "ff7f7f"

# Minion dot layout (world units / lane param) — presentation only.
const MINION_DOTS_MAX := 8          # cap so a big army stays a clump, not a snake
const MINION_FRONT_GAP := 0.006     # first rank sits just behind the contact point
const MINION_SPACING := 0.010       # lane param between ranks
const MINION_RANK_OFFSET := 0.9     # world units either side of the lane centre

# --- match data (rebuilt per sim run) ----------------------------------------
var data := {}
var seed_val := 42
var events: Array = []
var snapshots: Array = []
var summary: Array = []
var winner := ""
var last_tick := 0
var blue_name := "Blue"
var red_name := "Red"
var smap: SimMap

var pmeta: Array = []               # row index -> {id, team, role, name, char_id, char_name, ranged}
var idx_of := {}                    # player id -> snapshot row index
var meta_of := {}                   # player id -> pmeta entry
var tower_pos := {}                 # "team_lane_tier" -> Vector2 (world)

# balance-derived durations (ticks)
var fight_window := 30
var respawn_base := 0.0
var respawn_per_level := 0.0
var baron_dur := 0
var ward_ttl := 0
var tower_max_hp := 1.0
var nexus_max_hp := 1.0

# --- playback state -----------------------------------------------------------
var sim_ready := false
var playing := false
var finished := false
var playback_tick := 0.0
var speed_index := 0
var event_cursor := 0
var selftest := false
var last_frame := {}                # the frame most recently handed to MapView

# --- derived state (rebuilt on reset/seek) ------------------------------------
var kda := {}
var team_score := {"blue": 0, "red": 0}
var towers_down := {}
var dragon_total := 0
var dragon_up := false
var baron_up := false
var deaths_info := {}
var last_ult := {}
var wards: Array = []
var catches: Array = []             # live CC: {source, victim, kind, born, until}
var facing := {}                    # row index -> unit world vector (sticky look direction)
var effects: Array = []
var feed: Array = []
var feed_dirty := true

# --- nodes --------------------------------------------------------------------
var map: Control
var splash: Label
var clock_lbl: Label
var score_blue_lbl: Label
var score_red_lbl: Label
var goldbar_blue: ColorRect
var goldbar_red: ColorRect
var golddiff_lbl: RichTextLabel
var feed_lbl: RichTextLabel
var slider: HSlider
var play_btn: Button
var speed_btns: Array = []
var overlay: Panel
var overlay_lbl: RichTextLabel
var rows := {}                      # player id -> {name,champ,lvl,cs,kda,gold} Labels
var _slider_guard := false


func _ready() -> void:
	data = DataLoader.load_all()
	_build_ui()
	_layout()
	resized.connect(_layout)
	if not data.errors.is_empty():
		splash.text = "DATA ERROR\n" + "\n".join(data.errors.slice(0, 8))
		return
	_read_balance()
	_apply_cmdline()
	await get_tree().process_frame   # let the "Simulating…" splash paint first
	_run_sim(seed_val)
	if selftest:
		_run_selftest()


## Dev/QA affordances: `-- --seed=N --speed=16` when launching, so the designer
## (or a headless smoke run) can jump straight to a fast playback of a chosen game.
func _apply_cmdline() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_val = int(a.split("=")[1])
		elif a.begins_with("--speed="):
			var v := int(a.split("=")[1])
			if SPEEDS.has(v):
				_set_speed(SPEEDS.find(v))
		elif a == "--selftest":
			selftest = true


# --- sim run ------------------------------------------------------------------

func _read_balance() -> void:
	var cb: Dictionary = data.balance.combat
	# Fights no longer have a fixed length — they run until someone dies or
	# breaks off. This is just how long a champion keeps its "in a fight" glow
	# after the last fight_start touching it.
	fight_window = int(float(data.balance.fight.fight_end_grace_s) * TPS)
	respawn_base = float(cb.respawn_base_s)
	respawn_per_level = float(cb.respawn_per_level_s)
	baron_dur = int(float(data.balance.objectives.baron_duration_s) * TPS)
	ward_ttl = int(float(data.balance.wards.ward_duration_s) * TPS)
	tower_max_hp = maxf(float(data.balance.towers.hp), 1.0)
	nexus_max_hp = maxf(float(data.balance.towers.nexus_hp), 1.0)


func _run_sim(s: int) -> void:
	splash.visible = true
	splash.text = "Simulating match (seed %d)…" % s
	overlay.visible = false
	var team_ids: Array = data.teams.keys()
	blue_name = data.teams[team_ids[0]].get("name", team_ids[0])
	red_name = data.teams[team_ids[1]].get("name", team_ids[1])

	var res: Dictionary = SimMatch.new({"seed": s, "snapshot_every": SNAP}, data).run()
	events = res.events
	snapshots = res.snapshots
	summary = res.summary
	winner = res.winner
	last_tick = res.ticks - 1

	smap = SimMap.new(data.map)
	_build_meta()
	_build_scoreboard()
	map.setup_geometry(smap, _char_textures())
	_reset_derived()
	playback_tick = 0.0
	finished = false
	playing = true
	sim_ready = true
	splash.visible = false
	slider.max_value = maxf(last_tick, 1)


func _char_textures() -> Dictionary:
	var out := {}
	for m: Dictionary in pmeta:
		var cid: String = m.char_id
		if out.has(cid):
			continue
		var path: String = data.characters[cid].get("sprite", "")
		if path != "" and ResourceLoader.exists(path):
			var tex: Resource = load(path)
			if tex is Texture2D:
				out[cid] = tex
	return out


func _build_meta() -> void:
	pmeta.clear()
	idx_of.clear()
	meta_of.clear()
	var by_id := {}
	for row: Dictionary in summary:
		by_id[row.player] = row
	var rows0: Array = snapshots[0].players
	for k in rows0.size():
		var id: String = rows0[k][0]
		var sr: Dictionary = by_id[id]
		var char_def: Dictionary = data.characters[sr.character]
		var entry := {
			"id": id, "team": sr.team, "role": sr.role, "name": sr.handle,
			"char_id": sr.character, "char_name": char_def.name,
			# A swing from reach reads as a projectile; a melee one as a slash.
			"ranged": float(char_def.combat.attack_range) >= RANGED_AT,
		}
		pmeta.append(entry)
		idx_of[id] = k
		meta_of[id] = entry
	# tower world positions for effect placement
	tower_pos.clear()
	for team in SimMap.TEAMS:
		for lane in SimMap.LANES:
			for tier: String in smap.towers[team]:
				tower_pos["%s_%s_%s" % [team, lane, tier]] = smap.pos_on_lane(lane, float(smap.towers[team][tier]))


# --- playback loop ------------------------------------------------------------

func _process(delta: float) -> void:
	if not sim_ready or not playing or finished:
		return
	playback_tick += delta * BASE_TPS_1X * SPEEDS[speed_index]
	if playback_tick >= last_tick:
		playback_tick = last_tick
		_advance_events(last_tick)
		_render()
		_finish()
		return
	_advance_events(int(playback_tick))
	_render()


func _advance_events(upto: int) -> void:
	while event_cursor < events.size() and int(events[event_cursor].t) <= upto:
		_apply_event(events[event_cursor])
		event_cursor += 1


func _apply_event(ev: Dictionary) -> void:
	var t: int = ev.t
	var d: Dictionary = ev.data
	match ev.type:
		"kill":
			_on_kill(t, d)
		"fight_start":
			# Marker only: who is in the fight is read per-player off the snapshot
			# flags now, so the viewer no longer tracks fight membership itself.
			_add_effect(t, _vec(d.pos), "ring", fight_window, Color(1.0, 0.8, 0.3), "", 22.0)
		"ultimate_cast":
			last_ult[d.player] = t
			_on_cast(t, d, true)
		"basic_cast":
			_on_cast(t, d, false)
		"cc_applied":
			_on_cc(t, d)
		"teleport":
			# A split-pusher crossing the map would otherwise read as a glitch jump.
			_add_effect(t, _vec(d.pos), "shockwave", 24, Color(0.55, 0.9, 0.85), "", 0.0,
				{"world_radius": 4.0, "heavy": true})
		"objective_spawn":
			if d.objective == "dragon": dragon_up = true
			else: baron_up = true
		"objective_taken":
			_on_objective(t, d)
		"tower_destroyed":
			var key: String = "%s_%s_%s" % [d.team, d.lane, d.tier]
			towers_down[key] = true
			if tower_pos.has(key):
				_add_effect(t, tower_pos[key], "text", 14, Color(0.85, 0.8, 0.6), "TOWER", 0.0)
		"gank_call":
			# Macro on screen: how many team-mates read the jungler's call.
			var followers: int = int(d.reactors)
			var tail := " (%d follow)" % followers if followers > 0 else " (no follow-up)"
			feed.append("[color=#%s]%s[/color] gank %s%s" % [
				_teamhex(d.team), _team_name(d.team), d.lane, tail])
			_trim_feed()
		"ward_placed":
			wards.append({"pos": _vec(d.pos), "team": _team(d.player), "expires": t + ward_ttl})
		"nexus_destroyed":
			winner = d.winner
			_add_effect(t, smap.bases[d.team], "banner", 30,
				Color(1.0, 0.9, 0.4), "NEXUS DESTROYED", 0.0)


func _on_kill(t: int, d: Dictionary) -> void:
	# A turret can finish someone with no player behind it: killer is then "",
	# nobody scores, and the feed says so.
	var killer: String = d.get("killer", "")
	var victim: String = d.victim
	var by_player: bool = kda.has(killer)
	if by_player:
		kda[killer].k += 1
		team_score[_team(killer)] += 1
	kda[victim].d += 1
	for a in d.assists:
		kda[a].a += 1
	var vlevel: int = _level_of(victim, t)
	var rt := int((respawn_base + respawn_per_level * vlevel) * TPS)
	var vpos := _pos_of(victim, t)
	deaths_info[victim] = {"since": t, "at": t + rt, "pos": vpos}
	_add_effect(t, vpos, "text", 18, Color(1.0, 0.5, 0.5), "✖ " + _name(victim), 0.0)
	var by := "[color=#%s]%s[/color]" % [_hex(killer), _name(killer)] if by_player \
		else "[color=#%s]TURRET[/color]" % _teamhex(_enemy(_team(victim)))
	feed.append("%s ✚ [color=#%s]%s[/color]" % [by, _hex(victim), _name(victim)])
	_trim_feed()


## An ability went off. The ultimate is the match's loudest moment (level 6, a
## ~100 s cooldown), so it lands with real weight and a shape that says *what* it
## did — the "wow" the designer asked for — while the basic ability keeps a
## smaller, cooler beat so the two never read as the same event.
##
## Playback only: the shapes are chosen from the effect the sim already resolved,
## and the numbers (who was hit, how wide) come straight off the cast event.
func _on_cast(t: int, d: Dictionary, is_ult: bool) -> void:
	var effect: String = d.get("effect", "")
	var at := _vec(d.pos) if d.has("pos") else _pos_of(d.player, t)
	var team: String = _team(d.player)
	var radius: float = float(d.get("radius", 0.0))
	var targets: Array = d.get("targets", [])
	var col := _effect_color(effect, team)
	var ttl := 26 if is_ult else 14
	match effect:
		"aoe_cc", "aoe_damage", "zone_denial":
			# A circle you can measure: the shockwave grows to the ability's real
			# radius, so an ult that caught four people looks like it caught four.
			_add_effect(t, at, "shockwave", ttl, col, "", 0.0,
				{"world_radius": maxf(radius, 4.0), "heavy": is_ult})
		"single_burst", "snipe", "single_cc", "execute":
			for vid: String in targets:
				_add_effect(t, at, "beam", ttl, col, "", 0.0,
					{"to": _pos_of(vid, t), "heavy": is_ult,
					"pierce": effect == "snipe", "finisher": effect == "execute"})
		"team_heal", "team_shield":
			for vid: String in targets:
				_add_effect(t, _pos_of(vid, t), "bloom", ttl, col, "", 0.0, {"heavy": is_ult})
		"self_steroid":
			_add_effect(t, at, "aura", ttl + 20, col, "", 0.0, {"heavy": is_ult})
		"global_teleport":
			_add_effect(t, at, "shockwave", ttl, col, "", 0.0,
				{"world_radius": 3.0, "heavy": false})
	# The name, as a tag rather than bare text, so it stays readable over a fight.
	_add_effect(t, at, "tag", ttl, col, d.name, 0.0,
		{"font": 14 if is_ult else 11, "heavy": is_ult})


## Ultimates read by family, not by champion: hostile red-golds for damage,
## amber for a lock, green for healing, team colour for a personal buff.
func _effect_color(effect: String, team: String) -> Color:
	match effect:
		"aoe_cc", "single_cc":
			return Color(1.0, 0.82, 0.30)
		"team_heal", "team_shield":
			return Color(0.45, 0.95, 0.60)
		"self_steroid":
			return Color(C_BLUE) if team == "blue" else Color(C_RED)
		"zone_denial":
			return Color(0.72, 0.52, 1.0)
		"execute":
			return Color(1.0, 0.35, 0.35)
	return Color(1.0, 0.78, 0.35)


## A CC landed. The lock itself rides the snapshot flags (so the victim carries
## its mark for exactly as long as the sim says), while this records who cast it
## for the tether, and pops a short tag so the moment is unmissable at 1x.
func _on_cc(t: int, d: Dictionary) -> void:
	var kind: String = d.cc
	catches.append({
		"source": d.source, "victim": d.victim, "kind": kind,
		"born": t, "until": int(d.until),
	})
	_add_effect(t, _pos_of(d.victim, t), "tag", CC_TAG_TICKS, _cc_color(kind),
		kind.to_upper(), 0.0, {"font": 11})


func _on_objective(t: int, d: Dictionary) -> void:
	if d.objective == "dragon":
		dragon_up = false
		dragon_total += 1
		_add_effect(t, smap.pits.dragon, "banner", 26, Color(0.95, 0.6, 0.24),
			"DRAGON ▸ %s" % _team_name(d.team).to_upper(), 0.0)
		feed.append("[color=#e09a3d]Dragon[/color] ▸ [color=#%s]%s[/color]" % [
			_teamhex(d.team), _team_name(d.team)])
	else:
		baron_up = false
		_add_effect(t, smap.pits.baron, "banner", 26, Color(0.7, 0.5, 1.0),
			"BARON ▸ %s" % _team_name(d.team).to_upper(), 0.0)
		feed.append("[color=#b07dff]Baron[/color] ▸ [color=#%s]%s[/color]" % [
			_teamhex(d.team), _team_name(d.team)])
	_trim_feed()


func _finish() -> void:
	playing = false
	finished = true
	play_btn.text = "▶"
	var wname := _team_name(winner) if winner != "" else "Nobody (timeout)"
	var whex := _teamhex(winner) if winner != "" else "cccccc"
	overlay_lbl.text = "[center][font_size=30][color=#%s]%s[/color][/font_size]\n[font_size=18]wins in %s[/font_size]\n\n%s[/center]" % [
		whex, wname, _clock(last_tick), _final_kda_bbcode()]
	overlay.visible = true


# --- per-frame render ---------------------------------------------------------

func _render() -> void:
	var pt := playback_tick
	var champs: Array = []
	var gold := {"blue": 0.0, "red": 0.0}
	var s0 := _snap_le(pt)
	var s1 := _snap_ge(pt)
	var frac := 0.0
	if s1.t > s0.t:
		frac = clampf((pt - s0.t) / float(s1.t - s0.t), 0.0, 1.0)
	for k in pmeta.size():
		var m: Dictionary = pmeta[k]
		var r0: Array = s0.players[k]
		var r1: Array = s1.players[k]
		var alive: bool = int(r0[P_ALIVE]) == 1
		var p0 := Vector2(r0[P_X], r0[P_Y])
		var wpos := p0.lerp(Vector2(r1[P_X], r1[P_Y]), frac)
		gold[m.team] += float(r0[P_GOLD])
		var max_hp := float(r0[P_MAX_HP])
		var flags := int(r0[P_FLAGS])
		var ch := {
			"pos": wpos, "team": m.team, "role": m.role, "name": m.name,
			"char_id": m.char_id, "level": int(r0[P_LEVEL]), "alive": alive,
			"hp_frac": clampf(float(r0[P_HP]) / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0,
			"respawn_frac": 1.0, "fighting": false, "casting": 0.0,
			"recalling": false, "shake": Vector2.ZERO,
			"stunned": false, "slowed": false, "backing_off": false,
			"facing": Vector2.RIGHT,
		}
		if not alive:
			var di: Dictionary = deaths_info.get(m.id, {})
			if di.has("at") and di.at > di.since:
				ch.respawn_frac = clampf((pt - di.since) / float(di.at - di.since), 0.0, 1.0)
		else:
			# Combat state comes from the snapshot now, not from guessing off the
			# event stream: the sim knows exactly who is engaged, locked or slowed.
			ch.fighting = (flags & SimMatch.FLAG_IN_COMBAT) != 0
			ch.backing_off = (flags & SimMatch.FLAG_DISENGAGING) != 0
			ch.stunned = (flags & SimMatch.FLAG_STUNNED) != 0
			ch.slowed = (flags & SimMatch.FLAG_SLOWED) != 0
			ch.recalling = (flags & SimMatch.FLAG_RECALLING) != 0
			var lu: int = last_ult.get(m.id, -99999)
			ch.casting = clampf(1.0 - (pt - lu) / 14.0, 0.0, 1.0)
			if ch.fighting and not ch.backing_off:
				ch.shake = Vector2(sin(pt * 3.3 + k) * 1.4, cos(pt * 2.7 + k) * 1.0)
		champs.append(ch)

	_spread_bodies(champs)
	_resolve_facing(s0, s1, champs)

	last_frame = {
		"champs": champs,
		"beats": _render_beats(pt, s0, champs),
		"tethers": _render_tethers(pt, champs),
		"minions": _minion_dots(s0),
		"towers_down": towers_down,
		"tower_hp": _structure_hp(s0),
		"nexus_hp": _nexus_frac(s0),
		"effects": _render_effects(pt),
		"wards": _render_wards(pt),
		"dragon_total": dragon_total, "dragon_up": dragon_up, "baron_up": baron_up,
		"winner": winner,
	}
	map.set_frame(last_frame)
	_purge(pt)
	_update_hud(pt, gold)


## Minion wave dots, drawn from the squads the sim actually walks down each
## lane (LaneState). A squad is one point carrying a count — individual minions
## are never simulated, which is what keeps 1000-sim batches cheap — so the
## dots are spread here at render time, backward from the squad's position
## toward its own base, two ranks wide.
func _minion_dots(s: Dictionary) -> Array:
	var out: Array = []
	for row: Array in s.get("lanes", []):
		var lane: String = row[0]
		for q: Array in (row[4] if row.size() > 4 else []):
			var side: String = "blue" if int(q[0]) == 0 else "red"
			var lead := float(q[1])
			var dir := -1.0 if side == "blue" else 1.0
			for i in mini(int(q[2]), MINION_DOTS_MAX):
				var lt := clampf(lead + dir * (MINION_FRONT_GAP + i * MINION_SPACING), 0.0, 1.0)
				var p := smap.pos_on_lane(lane, lt)
				var ahead := smap.pos_on_lane(lane, clampf(lt + 0.01, 0.0, 1.0))
				var perp := Vector2.ZERO
				if p.distance_to(ahead) > 0.001:
					perp = (ahead - p).orthogonal().normalized() * MINION_RANK_OFFSET
				out.append({"pos": p + (perp if i % 2 == 0 else -perp), "team": side})
	return out


## Headless QA (`--headless -- --selftest`): plays the whole match back with no
## display, driving the same frame builder the real viewer uses, then checks the
## frame stream is sane *and* that the combat visuals actually happened — swings,
## ability impacts, catches, chipped towers, all cross-checked against the events
## the sim emitted. A silent playback regression (a snapshot column that moved, an
## event that stopped firing) fails here instead of in the designer's playtest.
## Rendering itself is not exercised; there is no display in headless.
func _run_selftest() -> void:
	var beats := 0
	var tethers := 0
	var tower_bars := 0
	var kinds := {}
	var problems: Array[String] = []
	var frames := 0
	playing = false
	playback_tick = 0.0
	_seek(0)
	while playback_tick < last_tick:
		playback_tick = minf(playback_tick + SELFTEST_STEP, last_tick)
		_advance_events(int(playback_tick))
		_render()
		frames += 1
		beats += last_frame.beats.size()
		tethers += last_frame.tethers.size()
		tower_bars = maxi(tower_bars, last_frame.tower_hp.size())
		for e: Dictionary in last_frame.effects:
			kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
		if problems.is_empty():
			problems = _frame_problems(last_frame)

	# What the sim said happened has to show up on screen.
	var casts := {"ultimate_cast": 0, "cc_applied": 0}
	for ev: Dictionary in events:
		if casts.has(ev.type):
			casts[ev.type] += 1
	var impacts := 0
	for kind: String in ["shockwave", "beam", "bloom", "aura"]:
		impacts += int(kinds.get(kind, 0))
	if beats == 0:
		problems.append("no auto-attack beats in the whole match")
	if casts.ultimate_cast > 0 and impacts == 0:
		problems.append("%d ultimates cast, no impact drawn" % casts.ultimate_cast)
	if casts.cc_applied > 0 and tethers == 0:
		problems.append("%d CC applications, no catch tether drawn" % casts.cc_applied)
	if tower_bars == 0:
		problems.append("no tower ever showed damage")

	print("VIEWER SELFTEST (seed %d, %d ticks, %d frames)" % [seed_val, last_tick, frames])
	print("  attack beats: %d | catch tethers: %d | towers chipped (peak): %d" % [
		beats, tethers, tower_bars])
	print("  effect kinds: %s" % str(kinds))
	print("  sim events: %d ultimates, %d CC applications" % [
		casts.ultimate_cast, casts.cc_applied])
	if problems.is_empty():
		print("VIEWER SELFTEST: PASS")
		get_tree().quit(0)
		return
	for p: String in problems:
		print("  FAIL: %s" % p)
	print("VIEWER SELFTEST: FAIL")
	get_tree().quit(1)


## Sanity of one built frame: positions on the map, fractions in range, no NaN.
func _frame_problems(f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for ch: Dictionary in f.champs:
		var p: Vector2 = ch.pos
		if is_nan(p.x) or is_nan(p.y) or p.x < 0.0 or p.y < 0.0 \
				or p.x > smap.size or p.y > smap.size:
			out.append("%s drawn off the map at %s" % [ch.name, str(p)])
		if ch.hp_frac < 0.0 or ch.hp_frac > 1.0:
			out.append("%s hp_frac out of range: %f" % [ch.name, ch.hp_frac])
		if not is_finite(ch.facing.x) or not is_finite(ch.facing.y):
			out.append("%s has a non-finite facing" % ch.name)
	return out


## Bodies occupy space — on screen. The sim has no collision (steering is free 2D
## movement toward a desired point), and team-mates routinely aim at the *same*
## point: the rally spot, one lane stand position for the bot duo, one objective
## pit. Drawn raw, five players merge into a single fat dot and a fight is
## unreadable (2026-07-25 playtest, remark 1).
##
## So playback relaxes overlapping bodies apart before drawing them. Each pass
## splits the overlap evenly between the two bodies, which preserves the group's
## centre of mass: the cluster still sits where the fight is, it just has five
## legible bodies in it. Beats, tethers and labels all read these positions, so
## everything stays consistent with itself.
##
## Deliberately *not* a sim mechanic. A sim-side version was built and measured
## (200 sims, same seeds): body collision changes fights, and it moved the macro
## split by ~6 points and undid M5-D's blue-side fix. Bodies having volume is a
## real design question with real balance consequences — it belongs to a balance
## milestone, not to a rendering one (see CHANGELOG M5.5-A).
func _spread_bodies(champs: Array) -> void:
	var n := champs.size()
	var push: Array[Vector2] = []
	push.resize(n)
	for _pass in SPREAD_PASSES:
		push.fill(Vector2.ZERO)
		for i in n:
			if not champs[i].alive:
				continue
			for j in range(i + 1, n):
				if not champs[j].alive:
					continue
				var delta: Vector2 = champs[j].pos - champs[i].pos
				var dist := delta.length()
				if dist >= BODY_SPACE:
					continue
				# Exactly co-located: split along an axis fixed by the pair, so the
				# same stack always resolves the same way frame to frame.
				var dir := delta / dist if dist > 0.001 \
					else Vector2.from_angle(TAU * float(i * n + j) / float(n * n))
				var step := dir * (BODY_SPACE - dist) * 0.5
				push[i] -= step
				push[j] += step
		for i in n:
			champs[i].pos += push[i]


## Which way each body is turned: at its target when it has one, otherwise along
## its own movement. Sticky — a player standing still keeps the last direction
## instead of spinning — and purely cosmetic, derived from positions the sim gave us.
func _resolve_facing(s0: Dictionary, s1: Dictionary, champs: Array) -> void:
	for k in champs.size():
		var ch: Dictionary = champs[k]
		var want := Vector2.ZERO
		var tgt := int(s0.players[k][P_TARGET])
		if ch.alive and tgt >= 0 and tgt < champs.size() and tgt != k:
			want = champs[tgt].pos - ch.pos
		else:
			want = Vector2(s1.players[k][P_X], s1.players[k][P_Y]) \
				- Vector2(s0.players[k][P_X], s0.players[k][P_Y])
		if want.length() > 0.01:
			facing[k] = want.normalized()
		elif not facing.has(k):
			# Opening frames: look up the map, the way this side is playing.
			facing[k] = (smap.bases[_enemy(ch.team)] - ch.pos).normalized()
		ch.facing = facing[k]


## Health of the structures the sim has reported as chipped, keyed the same way
## the viewer keys towers. Anything absent is still at full health.
func _structure_hp(s: Dictionary) -> Dictionary:
	var out := {}
	for row: Array in s.get("towers", []):
		out["%s_%s_%s" % [row[0], row[1], row[2]]] = clampf(float(row[3]) / tower_max_hp, 0.0, 1.0)
	return out


func _nexus_frac(s: Dictionary) -> Dictionary:
	var n: Array = s.get("nexus", [nexus_max_hp, nexus_max_hp])
	return {
		"blue": clampf(float(n[0]) / nexus_max_hp, 0.0, 1.0),
		"red": clampf(float(n[1]) / nexus_max_hp, 0.0, 1.0),
	}


## Auto-attack beats. The sim stamps the tick of every swing it fires
## (`last_swing_at`), so playback can show the exchange itself: a projectile
## crossing to the target for a ranged character, a slash for a melee one. This
## is the smallest readable unit of "a fight is happening here" (M5.5-B).
func _render_beats(pt: float, s0: Dictionary, champs: Array) -> Array:
	var out: Array = []
	for k in pmeta.size():
		var ch: Dictionary = champs[k]
		if not ch.alive:
			continue
		var row: Array = s0.players[k]
		var swing := float(row[P_SWING])
		var age := pt - swing
		if age < 0.0 or age > SWING_TICKS:
			continue
		var tgt := int(row[P_TARGET])
		if tgt < 0 or tgt >= champs.size() or not champs[tgt].alive:
			continue
		out.append({
			"from": ch.pos, "to": champs[tgt].pos, "team": ch.team,
			"ranged": bool(pmeta[k].ranged), "frac": age / SWING_TICKS,
		})
	return out


## The catch, drawn as a link: while a CC is running, a dashed line ties the
## victim to whoever locked it — that is the difference between "he stopped" and
## "the jungler caught him" (2026-07-25 playtest, remark 4).
func _render_tethers(pt: float, champs: Array) -> Array:
	var out: Array = []
	for c: Dictionary in catches:
		if pt < c.born or pt > c.until:
			continue
		var src: Dictionary = champs[idx_of[c.source]]
		var vic: Dictionary = champs[idx_of[c.victim]]
		if not src.alive or not vic.alive:
			continue
		var left: float = (c.until - pt) / maxf(c.until - c.born, 1.0)
		out.append({
			"from": src.pos, "to": vic.pos, "color": _cc_color(c.kind),
			"alpha": clampf(0.25 + 0.5 * left, 0.0, 0.85),
		})
	return out


## Blue-white for a slow (it drags), amber for a hard lock (it stops you dead).
func _cc_color(kind: String) -> Color:
	return Color(0.45, 0.85, 1.0) if kind == "slow" else Color(1.0, 0.82, 0.30)


## Resolves every live effect for this playback tick: the renderer gets a flat
## dict with the age already turned into alpha / rise / grown radius, plus any
## kind-specific fields the effect was created with.
func _render_effects(pt: float) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		var age: float = (pt - e.born) / float(e.ttl)
		if age < 0.0 or age > 1.0:
			continue
		var item := e.duplicate()
		item.erase("born")
		item.erase("ttl")
		item.erase("grow")
		item["progress"] = age
		item["alpha"] = 1.0 - age
		item["rise"] = age * 26.0
		item["radius"] = float(e.grow) + age * 18.0
		item["font"] = int(e.get("font", 18 if e.kind == "banner" else 13))
		out.append(item)
	return out


func _render_wards(pt: float) -> Array:
	var out: Array = []
	for w: Dictionary in wards:
		if w.expires <= pt:
			continue
		var left: float = (w.expires - pt) / float(ward_ttl)
		out.append({"pos": w.pos, "team": w.team, "alpha": clampf(left * 2.0, 0.15, 0.7)})
	return out


func _update_hud(pt: float, gold: Dictionary) -> void:
	clock_lbl.text = _clock(int(pt))
	score_blue_lbl.text = str(team_score.blue)
	score_red_lbl.text = str(team_score.red)
	var total: float = maxf(gold.blue + gold.red, 1.0)
	goldbar_blue.size_flags_stretch_ratio = maxf(gold.blue / total, 0.02)
	goldbar_red.size_flags_stretch_ratio = maxf(gold.red / total, 0.02)
	var diff: float = gold.blue - gold.red
	var lead := "blue" if diff >= 0 else "red"
	golddiff_lbl.text = "[center][color=#%s]%s +%.1fk[/color][/center]" % [
		_teamhex(lead), _team_name(lead), absf(diff) / 1000.0]
	# scoreboard rows
	var s0 := _snap_le(pt)
	for k in pmeta.size():
		var m: Dictionary = pmeta[k]
		var r: Array = s0.players[k]
		var cells: Dictionary = rows[m.id]
		cells.lvl.text = str(int(r[3]))
		cells.cs.text = str(int(r[5]))
		var kd: Dictionary = kda[m.id]
		cells.kda.text = "%d/%d/%d" % [kd.k, kd.d, kd.a]
		cells.gold.text = "%.1fk" % (float(r[4]) / 1000.0)
	if not _slider_guard:
		_slider_guard = true
		slider.value = pt
		_slider_guard = false
	if feed_dirty:
		feed_lbl.text = "\n".join(feed)
		feed_dirty = false


# --- effects / helpers --------------------------------------------------------

## One entry in the transient visual layer. `extra` carries whatever a kind needs
## beyond the common fields — an impact's world radius, a beam's endpoints — and
## is passed through to the renderer untouched.
func _add_effect(born: int, pos: Vector2, kind: String, ttl: int, col: Color, text: String,
		grow: float, extra: Dictionary = {}) -> void:
	var e := {"born": born, "pos": pos, "kind": kind, "ttl": maxi(ttl, 1),
		"color": col, "text": text, "grow": grow}
	e.merge(extra)
	effects.append(e)


func _purge(pt: float) -> void:
	effects = effects.filter(func(e): return pt < e.born + e.ttl)
	wards = wards.filter(func(w): return w.expires > pt)
	catches = catches.filter(func(c): return pt < c.until)


func _trim_feed() -> void:
	while feed.size() > FEED_MAX:
		feed.pop_front()
	feed_dirty = true


# --- snapshot access ----------------------------------------------------------

func _snap_le(pt: float) -> Dictionary:
	@warning_ignore("integer_division")
	var i := clampi(int(pt) / SNAP, 0, snapshots.size() - 1)
	return snapshots[i]


func _snap_ge(pt: float) -> Dictionary:
	@warning_ignore("integer_division")
	var i := clampi(int(pt) / SNAP + 1, 0, snapshots.size() - 1)
	return snapshots[i]


func _snap_at(t: int) -> Dictionary:
	return snapshots[clampi(int(round(t / float(SNAP))), 0, snapshots.size() - 1)]


func _pos_of(id: String, t: int) -> Vector2:
	var r: Array = _snap_at(t).players[idx_of[id]]
	return Vector2(r[1], r[2])


func _level_of(id: String, t: int) -> int:
	return int(_snap_at(t).players[idx_of[id]][3])


func _team(id: String) -> String: return meta_of[id].team
func _name(id: String) -> String: return meta_of[id].name
func _hex(id: String) -> String: return C_BLUE if meta_of[id].team == "blue" else C_RED
func _teamhex(team: String) -> String: return C_BLUE if team == "blue" else C_RED
func _enemy(team: String) -> String: return "red" if team == "blue" else "blue"
func _team_name(team: String) -> String: return blue_name if team == "blue" else red_name
func _vec(a: Array) -> Vector2: return Vector2(float(a[0]), float(a[1]))
func _clock(t: int) -> String:
	var secs := int(t / float(TPS))
	@warning_ignore("integer_division")
	var mins := secs / 60
	return "%02d:%02d" % [mins, secs % 60]


# --- controls -----------------------------------------------------------------

func _reset_derived() -> void:
	event_cursor = 0
	kda = {}
	for m: Dictionary in pmeta:
		kda[m.id] = {"k": 0, "d": 0, "a": 0}
	team_score = {"blue": 0, "red": 0}
	towers_down = {}
	dragon_total = 0
	dragon_up = false
	baron_up = false
	deaths_info = {}
	last_ult = {}
	wards = []
	catches = []
	facing = {}
	effects = []
	feed = []
	feed_dirty = true


func _set_speed(i: int) -> void:
	speed_index = i
	for j in speed_btns.size():
		speed_btns[j].button_pressed = (j == i)


func _toggle_play() -> void:
	if finished:
		_restart()
		return
	playing = not playing
	play_btn.text = "❚❚" if playing else "▶"


func _restart() -> void:
	_reset_derived()
	playback_tick = 0.0
	finished = false
	playing = true
	overlay.visible = false
	play_btn.text = "❚❚"


func _skip_to_result() -> void:
	_seek(last_tick)
	_finish()


func _seek(target: int) -> void:
	_reset_derived()
	playback_tick = clampf(target, 0, last_tick)
	_advance_events(int(playback_tick))
	if playback_tick >= last_tick:
		_finish()
	else:
		finished = false
		overlay.visible = false
		if not playing:
			play_btn.text = "▶"
	_render()


func _on_slider(v: float) -> void:
	if _slider_guard:
		return
	_seek(int(v))


func _new_match() -> void:
	sim_ready = false
	seed_val += 1
	_run_sim(seed_val)


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0b0e15")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	map = Control.new()
	map.set_script(load("res://game/map_view.gd"))
	add_child(map)

	_build_topbar()
	_build_sidepanel()
	_build_bottombar()
	_build_overlay()

	splash = Label.new()
	splash.text = "Loading…"
	splash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	splash.add_theme_font_size_override("font_size", 22)
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(splash)


func _panel(color: String) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color("222b3a")
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _build_topbar() -> void:
	var p := _panel("141a26")
	p.name = "TopBar"
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 16)
	box.offset_left = 16; box.offset_right = -16; box.offset_top = 4; box.offset_bottom = -14
	p.add_child(box)

	score_blue_lbl = _big_label("0", C_BLUE)
	score_blue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_blue_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(score_blue_lbl)

	clock_lbl = _big_label("00:00", "e8ecf4")
	clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_lbl.custom_minimum_size.x = 120
	box.add_child(clock_lbl)

	score_red_lbl = _big_label("0", C_RED)
	score_red_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_red_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(score_red_lbl)

	# gold bar pinned to the panel's bottom edge
	var gb := HBoxContainer.new()
	gb.add_theme_constant_override("separation", 0)
	gb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	gb.offset_left = 8; gb.offset_right = -8; gb.offset_top = -10; gb.offset_bottom = -4
	p.add_child(gb)
	goldbar_blue = ColorRect.new()
	goldbar_blue.color = Color(C_BLUE)
	goldbar_blue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gb.add_child(goldbar_blue)
	goldbar_red = ColorRect.new()
	goldbar_red.color = Color(C_RED)
	goldbar_red.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gb.add_child(goldbar_red)

	golddiff_lbl = RichTextLabel.new()
	golddiff_lbl.bbcode_enabled = true
	golddiff_lbl.fit_content = true
	golddiff_lbl.scroll_active = false
	golddiff_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	golddiff_lbl.offset_top = -32; golddiff_lbl.offset_bottom = -12
	golddiff_lbl.add_theme_font_size_override("normal_font_size", 12)
	p.add_child(golddiff_lbl)


func _build_sidepanel() -> void:
	var p := _panel("141a26")
	p.name = "SidePanel"
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12; v.offset_right = -12; v.offset_top = 10; v.offset_bottom = -10
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	_side_vbox = v


func _build_scoreboard() -> void:
	# built after the sim so rosters are known; rebuild wipes previous
	for c in _side_vbox.get_children():
		c.queue_free()
	rows.clear()
	_team_block(_side_vbox, "blue", blue_name)
	_team_block(_side_vbox, "red", red_name)
	var sep := HSeparator.new()
	_side_vbox.add_child(sep)
	var feed_title := _small_label("KILL FEED", "8a93a6")
	_side_vbox.add_child(feed_title)
	feed_lbl = RichTextLabel.new()
	feed_lbl.bbcode_enabled = true
	feed_lbl.scroll_active = true
	feed_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_lbl.add_theme_font_size_override("normal_font_size", 13)
	_side_vbox.add_child(feed_lbl)


func _team_block(parent: VBoxContainer, team: String, tname: String) -> void:
	var hex := C_BLUE if team == "blue" else C_RED
	var head := _small_label(tname.to_upper(), hex)
	head.add_theme_font_size_override("font_size", 14)
	parent.add_child(head)
	# column header
	parent.add_child(_row_line("", "", "L", "CS", "K/D/A", "GOLD", "6b7484"))
	for m: Dictionary in pmeta:
		if m.team != team:
			continue
		var role_tag := "%s · %s" % [m.role.substr(0, 3).capitalize(), m.char_name]
		var line := _row_cells(m.name, role_tag, hex)
		parent.add_child(line.node)
		rows[m.id] = line.cells


func _row_line(a: String, b: String, l: String, cs: String, k: String, g: String, hex: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var widths := [92, 96, 24, 40, 66, 52]
	var texts := [a, b, l, cs, k, g]
	for i in texts.size():
		var lbl := _small_label(texts[i], hex)
		lbl.custom_minimum_size.x = widths[i]
		if i >= 2:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(lbl)
	return h


func _row_cells(handle: String, champ: String, hex: String) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var name_lbl := _small_label(handle, hex)
	name_lbl.custom_minimum_size.x = 92
	var champ_lbl := _small_label(champ, "aeb6c6")
	champ_lbl.custom_minimum_size.x = 96
	champ_lbl.clip_text = true
	var lvl := _num_cell(24)
	var cs := _num_cell(40)
	var kdal := _num_cell(66)
	var gold := _num_cell(52)
	for c in [name_lbl, champ_lbl, lvl, cs, kdal, gold]:
		h.add_child(c)
	return {"node": h, "cells": {"lvl": lvl, "cs": cs, "kda": kdal, "gold": gold}}


func _num_cell(w: int) -> Label:
	var l := _small_label("—", "d6dbe6")
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _build_bottombar() -> void:
	var p := _panel("141a26")
	p.name = "BottomBar"
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14; v.offset_right = -14; v.offset_top = 10; v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 1
	slider.value_changed.connect(_on_slider)
	slider.custom_minimum_size.y = 16
	v.add_child(slider)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)

	play_btn = _ctl_button("❚❚")
	play_btn.pressed.connect(_toggle_play)
	h.add_child(play_btn)

	speed_btns.clear()
	for i in SPEEDS.size():
		var b := _ctl_button("%dx" % SPEEDS[i])
		b.toggle_mode = true
		b.button_pressed = (i == 0)
		var idx := i
		b.pressed.connect(func(): _set_speed(idx))
		speed_btns.append(b)
		h.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var skip_btn := _ctl_button("Skip ▸ Result")
	skip_btn.pressed.connect(_skip_to_result)
	h.add_child(skip_btn)

	var restart_btn := _ctl_button("↻ Rewatch")
	restart_btn.pressed.connect(_restart)
	h.add_child(restart_btn)

	var new_btn := _ctl_button("New Match")
	new_btn.pressed.connect(_new_match)
	h.add_child(new_btn)


func _build_overlay() -> void:
	overlay = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color("2a3446")
	overlay.add_theme_stylebox_override("panel", sb)
	overlay.visible = false
	add_child(overlay)
	overlay_lbl = RichTextLabel.new()
	overlay_lbl.bbcode_enabled = true
	overlay_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_lbl.offset_left = 24; overlay_lbl.offset_right = -24
	overlay_lbl.offset_top = 24; overlay_lbl.offset_bottom = -24
	overlay.add_child(overlay_lbl)


func _final_kda_bbcode() -> String:
	var lines := ["[font_size=14]"]
	for team in ["blue", "red"]:
		for m: Dictionary in pmeta:
			if m.team != team:
				continue
			var kd: Dictionary = kda[m.id]
			lines.append("[color=#%s]%-10s[/color] %s  %d/%d/%d" % [
				_teamhex(team), m.name, m.char_name, kd.k, kd.d, kd.a])
	lines.append("[/font_size]")
	return "\n".join(lines)


func _big_label(text: String, hex: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(hex))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _small_label(text: String, hex: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(hex))
	return l


func _ctl_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.focus_mode = Control.FOCUS_NONE
	return b


var _side_vbox: VBoxContainer


# --- layout -------------------------------------------------------------------

func _layout() -> void:
	var M := 12.0
	var top_h := 60.0
	var bottom_h := 92.0
	var top := get_node_or_null("TopBar")
	var side := get_node_or_null("SidePanel")
	var bottom := get_node_or_null("BottomBar")
	if top == null:
		return
	var mid_y0 := M + top_h + M
	var mid_h := size.y - mid_y0 - bottom_h - M
	var side_w: float = clampf(size.x * 0.30, 300.0, 400.0)
	var map_side: float = minf(mid_h, size.x - side_w - 3.0 * M)
	var map_y := mid_y0 + (mid_h - map_side) * 0.5
	# Center the map + side-panel block horizontally so the map reads as the focus.
	var block_w := map_side + M + side_w
	var left := maxf((size.x - block_w) * 0.5, M)

	top.position = Vector2(M, M)
	top.size = Vector2(size.x - 2 * M, top_h)

	map.position = Vector2(left, map_y)
	map.size = Vector2(map_side, map_side)

	side.position = Vector2(left + map_side + M, mid_y0)
	side.size = Vector2(side_w, mid_h)

	bottom.position = Vector2(M, size.y - bottom_h)
	bottom.size = Vector2(size.x - 2 * M, bottom_h - M)

	if overlay != null:
		var ow := 420.0
		var oh := 320.0
		overlay.position = Vector2(map.position.x + (map_side - ow) * 0.5, map_y + (map_side - oh) * 0.5)
		overlay.size = Vector2(ow, oh)
