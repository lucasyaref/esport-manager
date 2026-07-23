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

var pmeta: Array = []               # row index -> {id, team, role, name, char_id, char_name}
var idx_of := {}                    # player id -> snapshot row index
var meta_of := {}                   # player id -> pmeta entry
var tower_pos := {}                 # "team_lane_tier" -> Vector2 (world)

# balance-derived durations (ticks)
var fight_window := 30
var respawn_base := 0.0
var respawn_per_level := 0.0
var baron_dur := 0
var ward_ttl := 0
var recall_ticks := 0

# --- playback state -----------------------------------------------------------
var sim_ready := false
var playing := false
var finished := false
var playback_tick := 0.0
var speed_index := 0
var event_cursor := 0

# --- derived state (rebuilt on reset/seek) ------------------------------------
var kda := {}
var team_score := {"blue": 0, "red": 0}
var towers_down := {}
var dragon_total := 0
var dragon_up := false
var baron_up := false
var deaths_info := {}
var active_fights: Array = []
var last_ult := {}
var recall_until := {}
var wards: Array = []
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
	recall_ticks = int(float(data.balance.economy.recall_channel_s) * TPS)


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
		var entry := {
			"id": id, "team": sr.team, "role": sr.role, "name": sr.handle,
			"char_id": sr.character, "char_name": data.characters[sr.character].name,
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
			var ids := {}
			for id in d.blue:
				ids[id] = true
			for id in d.red:
				ids[id] = true
			active_fights.append({"ids": ids, "until": t + fight_window})
			_add_effect(t, _vec(d.pos), "ring", fight_window, Color(1.0, 0.8, 0.3), "", 22.0)
		"ultimate_cast":
			last_ult[d.player] = t
			_add_effect(t, _pos_of(d.player, t), "text", 14, Color(1.0, 0.92, 0.5), d.name, 0.0)
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
		"recall_start":
			recall_until[d.player] = t + recall_ticks
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
		var alive: bool = int(r0[6]) == 1
		var wpos := Vector2(r0[1], r0[2]).lerp(Vector2(r1[1], r1[2]), frac)
		gold[m.team] += float(r0[4])
		var max_hp := float(r0[8])
		var ch := {
			"pos": wpos, "team": m.team, "role": m.role, "name": m.name,
			"char_id": m.char_id, "level": int(r0[3]), "alive": alive,
			"hp_frac": clampf(float(r0[7]) / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0,
			"respawn_frac": 1.0, "fighting": false, "casting": 0.0,
			"recalling": false, "shake": Vector2.ZERO,
		}
		if not alive:
			var di: Dictionary = deaths_info.get(m.id, {})
			if di.has("at") and di.at > di.since:
				ch.respawn_frac = clampf((pt - di.since) / float(di.at - di.since), 0.0, 1.0)
		else:
			ch.fighting = _in_fight(m.id, pt)
			var lu: int = last_ult.get(m.id, -99999)
			ch.casting = clampf(1.0 - (pt - lu) / 14.0, 0.0, 1.0)
			ch.recalling = pt < float(recall_until.get(m.id, -1))
			if ch.fighting:
				ch.shake = Vector2(sin(pt * 3.3 + k) * 1.4, cos(pt * 2.7 + k) * 1.0)
		champs.append(ch)

	map.set_frame({
		"champs": champs,
		"minions": _minion_dots(s0),
		"towers_down": towers_down,
		"effects": _render_effects(pt),
		"wards": _render_wards(pt),
		"dragon_total": dragon_total, "dragon_up": dragon_up, "baron_up": baron_up,
		"winner": winner,
	})
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


func _render_effects(pt: float) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		var age: float = (pt - e.born) / float(e.ttl)
		if age < 0.0 or age > 1.0:
			continue
		var col: Color = e.color
		out.append({
			"pos": e.pos, "kind": e.kind, "text": e.text, "color": col,
			"alpha": 1.0 - age, "rise": age * 26.0,
			"radius": e.grow + age * 18.0, "font": 18 if e.kind == "banner" else 13,
		})
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

func _add_effect(born: int, pos: Vector2, kind: String, ttl: int, col: Color, text: String, grow: float) -> void:
	effects.append({"born": born, "pos": pos, "kind": kind, "ttl": maxi(ttl, 1),
		"color": col, "text": text, "grow": grow})


func _purge(pt: float) -> void:
	effects = effects.filter(func(e): return pt < e.born + e.ttl)
	active_fights = active_fights.filter(func(f): return pt < f.until)
	wards = wards.filter(func(w): return w.expires > pt)


func _in_fight(id: String, pt: float) -> bool:
	for f: Dictionary in active_fights:
		if pt < f.until and f.ids.has(id):
			return true
	return false


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
	active_fights = []
	last_ult = {}
	recall_until = {}
	wards = []
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
