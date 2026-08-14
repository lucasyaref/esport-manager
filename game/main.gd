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

const SNAP := 1                     # snapshot cadence for playback (ticks) — M6-C:
                                     # raised from 2 so a close-up/real-speed director
                                     # frame has a fresh keyframe every tick to interpolate
                                     # against, not one every 200ms of sim time.
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
const RANGED_AT := 2.0              # attack_range (world units) at/above which a swing flies
const SELFTEST_STEP := 4.0          # playback ticks per step in --selftest

# Transient lifetimes, in ticks. Playback at 1x runs *four times* sim-time
# (BASE_TPS_1X = 40 ticks a real second against the sim's 10), so a lifetime
# written in sim ticks is on screen four times shorter than it reads on paper:
# M5.5's ult impact lasted 0.65 real seconds and its attack beat 0.12 s, which is
# why the designer could see something happening but not read it (2026-07-25
# playtest, remarks 2 and 3). These are sized in real seconds at 1x — the speed
# the match is meant to be watched at — with the conversion spelled out.
const SWING_TICKS := 8.0            # 0.20 s — one auto-attack beat (swings are ~0.35 s apart)
const FLINCH_TICKS := 10.0          # 0.25 s — the hit-flash on a body that just lost HP
const DMG_TTL := 44                 # 1.10 s — floating damage number
const BASIC_TTL := 34               # 0.85 s — basic-ability impact
const ULT_TTL := 64                 # 1.60 s — ultimate impact: the beat you must not miss
const ULT_TAG_TTL := 80             # 2.00 s — the ultimate's name, readable over a fight
const AURA_EXTRA := 60              # 1.50 s — self-buff auras outlive their own impact
const CC_TAG_TICKS := 28            # 0.70 s — "SLOWED"/"STUNNED" popup
const SIEGE_TICKS := 24             # 0.60 s — "structure is losing HP right now" pulse
const HIT_MIN_DMG := 6.0            # below this an HP tick is noise, not a blow
const HIT_MIN_HEAL := 25.0          # regen is not news; a heal ability is
const EXCHANGE_TICKS := 40.0        # 1.00 s — a swing given or taken this recently
                                    # means "trading blows", as opposed to a standoff
# Body separation, for drawing only (see _spread_bodies).
const BODY_SPACE := 1.9             # world units of personal space between bodies
const SPREAD_PASSES := 3            # relaxation passes per frame
const TPS := SimMatch.TICKS_PER_SECOND
const BASE_TPS_1X := 40.0           # sim ticks per real second at 1x (~8 min / match)
# M6-C: real speed is 0.25x of today's 1x (which is already 4x sim-time), i.e. true
# 1:1 real time against the sim clock (40 * 0.25 = 10 ticks/s = SimMatch.TICKS_PER_SECOND).
# Typed so 0.25 survives as a float and isn't coerced by an int-inferred array.
const SPEEDS: Array[float] = [0.25, 1.0, 4.0, 16.0]
const REAL_SPEED := 0.25            # the director's close-up tier; looked up in SPEEDS below
# F1-F5 / F6-F10 jump the camera to a player (GDD §7.3, TFM2's own binding). pmeta
# is built team-by-team (SimMatch._spawn_agents: blue's five roles, then red's), so
# index alone gives the split with no per-frame lookup.
const FOLLOW_KEYS := [
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
]
const FEED_MAX := 12
const C_BLUE := "6fa8ff"
const C_RED := "ff7f7f"
# How a structure is named in the feed, and the nexus levels worth announcing.
const TIER_NAME := {"outer": "T1", "inner": "T2", "base": "base turret"}
const NEXUS_MARKS := [0.75, 0.5, 0.25, 0.1]
const NEXUS_CELLS := 9              # cells in the side-panel nexus bar

# Minion dot layout (world units / lane param) — presentation only.
const MINION_DOTS_MAX := 8          # cap so a big army stays a clump, not a snake
const MINION_FRONT_GAP := 0.006     # first rank sits just behind the contact point
const MINION_SPACING := 0.010       # lane param between ranks
const MINION_RANK_OFFSET := 0.9     # world units either side of the lane centre
const SIEGE_REACH := 9.0            # how close a squad must be to the structure it chips

# M6-D: how a live body's position has to move between consecutive snapshots
# (world units, one SNAP tick apart) before it reads as "walking" rather than
# jitter from in-fight positioning. A full-speed champion covers ~0.27 world
# units/tick (335 speed, PlayerAgent.SPEED_SCALE, TPS=10); this is well under
# that, on purpose — unmeasured "feels right" placeholder (M6-D), same status
# as HIT_MIN_DMG/HIT_MIN_HEAL above.
const MOVE_EPS := 0.02
# M6-D: must match data/animation.json's default sheet.rows (and whatever a
# match's own data/animation.json overrides it to) — used only to sanity-check
# that `_anim_states` never emits a state the sheet has no row for.
const ANIM_STATES := ["idle", "run", "attack", "cast", "hurt", "die", "recall"]

# --- match data (rebuilt per sim run) ----------------------------------------
var data := {}
var anim_cfg := {}                  # data/animation.json (AnimConfig.load_config)
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
var struct_at := {}                 # siege key -> {pos, team}: where each structure stands

# --- playback state -----------------------------------------------------------
var sim_ready := false
var playing := false
var finished := false
var playback_tick := 0.0
var speed_index := 1                # SPEEDS[1] == 1.0 — unchanged default ("1x")
var event_cursor := 0
var selftest := false
var last_frame := {}                # the frame most recently handed to MapView

# --- M6-C: highlight director --------------------------------------------------
# The reel is computed once per match (sim/highlights.gd, read-only) and never
# changes; everything else here tracks where playback is *relative* to it.
var reel: Array = []                 # Highlights.select() output, plus window_start/end
var pacing_mode := "full"            # "full" (dip in/out) | "highlights" (jump between)
var auto_camera := true              # toggle: manual camera is always available regardless
var active_highlight := -1           # index into `reel`, or -1 if playback_tick is outside all
var highlight_released := false      # true once the user has taken the camera/speed back
                                      # for the *current* highlight (cleared on the next one)
var _cam_saved := {}                 # map.camera_state() captured on entering a highlight
var _speed_saved := -1               # speed_index captured on entering a highlight
var director_zoom := 3.2             # data/highlights.json director.zoom
var preroll_ticks := 0               # data/highlights.json director.preroll_s, in ticks
var aftermath_ticks := 0             # data/highlights.json director.aftermath_s, in ticks
var rewind_ticks := 0                # data/highlights.json director.rewind_s, in ticks
var pacing_btns: Array = []
var auto_cam_btn: Button

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
var hits: Array = []                # HP changes, tick-ordered: {t, k, amount, heal}
var sieges: Array = []              # structure HP losses, tick-ordered: {t, key}
var marks: Array = []               # synthetic feed lines, tick-ordered: {t, text}
var mark_cursor := 0
var facing := {}                    # row index -> unit world vector (sticky look direction)
# M6-D: row index -> {"state": String, "since": float}. Sticky the same way
# `facing` is: an animation pose has to hold its own frame clock from the tick
# it *became* the read state, not from a fixed epoch, or a swing landing
# mid-idle-bob would restart on a random column instead of frame 0.
var anim_since := {}
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
var struct_lbl: RichTextLabel
var slider: HSlider
var play_btn: Button
var speed_btns: Array = []
var overlay: Panel
var overlay_lbl: RichTextLabel
var highlight_banner: Panel
var highlight_lbl: RichTextLabel
var rows := {}                      # player id -> {name,champ,lvl,cs,kda,gold} Labels
var _slider_guard := false


func _ready() -> void:
	data = DataLoader.load_all()
	anim_cfg = AnimConfig.load_config()
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
			# Float, not int: SPEEDS now holds the 0.25 real-speed tier (M6-C).
			var v := float(a.split("=")[1])
			if SPEEDS.has(v):
				_set_speed(SPEEDS.find(v))
		elif a == "--selftest":
			selftest = true


## Camera follow hotkeys (GDD §7.3): F1-F5 jump to blue's five players in role
## order, F6-F10 to red's, same key again (or Escape) releases. The map itself
## handles wheel-zoom and click-to-follow directly (they need hover/hit-test
## against its own screen space); this is only for the keys with no natural home
## on a specific control.
func _unhandled_input(event: InputEvent) -> void:
	if not sim_ready or map == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		map.stop_follow()
		_release_director()
		get_viewport().set_input_as_handled()
		return
	var idx := FOLLOW_KEYS.find(key_event.keycode)
	if idx >= 0 and idx < pmeta.size():
		map.toggle_follow(pmeta[idx].id)
		_release_director()
		get_viewport().set_input_as_handled()


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
	_build_reel(int(res.ticks))

	smap = SimMap.new(data.map)
	_build_structures()
	_build_meta()
	_build_hits()
	_build_marks()
	_build_scoreboard()
	map.setup_geometry(smap, _char_textures(), data.get("terrain"), anim_cfg.get("sheet", {}))
	_reset_derived()
	playback_tick = 0.0
	finished = false
	playing = true
	sim_ready = true
	splash.visible = false
	slider.max_value = maxf(last_tick, 1)


## Team-coloured LPC art (M6-D2) is baked per side, not runtime-tinted like the
## procedural placeholder — a full-colour sprite multiplied by a saturated team
## colour shifts skin/hair hue along with the outfit, which a near-white
## placeholder never showed. `sprite_by_side` (keyed "blue"/"red") wins when
## present; `sprite` is the plain-path fallback, still the hook a true future
## per-character replacement (no team variants needed) drops into with no code
## change, per CLAUDE.md's placeholder contract.
##
## Keyed by char_id *and* team, not just char_id: data/players.json's
## champion_pool is per-role, and both sides' same-role players draw from the
## identical pool (e.g. azw_top and crv_top can both roll "bastion") — a
## same-champion mirror is an ordinary outcome here, not an edge case, and
## with team colour baked into the texture a char_id-only key would silently
## hand one side's instance the other side's colour.
func _char_textures() -> Dictionary:
	var out := {}
	for m: Dictionary in pmeta:
		var key := "%s|%s" % [m.char_id, m.team]
		if out.has(key):
			continue
		var char_def: Dictionary = data.characters[m.char_id]
		var by_side: Dictionary = char_def.get("sprite_by_side", {})
		var path: String = by_side.get(m.team, "") if not by_side.is_empty() else char_def.get("sprite", "")
		if path != "" and ResourceLoader.exists(path):
			var tex: Resource = load(path)
			if tex is Texture2D:
				out[key] = tex
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


## M6-C: the reel the auto-camera director works off of, computed once per match
## exactly the way `tools/reel.gd` does it headless — this is the only place `game/`
## calls into `sim/highlights.gd`, and it never feeds anything back into the sim.
## `window_start`/`window_end` (sim ticks) are the pre-roll/aftermath-padded span the
## director treats as "inside this highlight"; they're added onto the moment dicts
## Highlights.select() returns so the rest of the director can just compare
## `playback_tick` against them.
func _build_reel(ticks: int) -> void:
	var cfg := Highlights.load_config()
	var all_moments := Highlights.moments(events, ticks, cfg)
	reel = Highlights.select(all_moments, cfg)
	var dcfg: Dictionary = cfg.get("director", {})
	preroll_ticks = int(float(dcfg.get("preroll_s", 3.0)) * TPS)
	aftermath_ticks = int(float(dcfg.get("aftermath_s", 4.0)) * TPS)
	director_zoom = float(dcfg.get("zoom", 3.2))
	rewind_ticks = int(float(dcfg.get("rewind_s", 8.0)) * TPS)
	for mom: Dictionary in reel:
		mom.window_start = maxi(0, int(mom.start) - preroll_ticks)
		mom.window_end = mini(last_tick, int(mom.end) + aftermath_ticks)
	active_highlight = -1
	highlight_released = false


# --- playback loop ------------------------------------------------------------

func _process(delta: float) -> void:
	if not sim_ready or not playing or finished:
		return
	playback_tick += delta * BASE_TPS_1X * SPEEDS[speed_index]
	if playback_tick >= last_tick:
		playback_tick = last_tick
		_advance_events(last_tick)
		_update_director(true)
		_render()
		_finish()
		return
	_advance_events(int(playback_tick))
	_update_director(true)
	_render()


func _advance_events(upto: int) -> void:
	while event_cursor < events.size() and int(events[event_cursor].t) <= upto:
		_apply_event(events[event_cursor])
		event_cursor += 1
	# Feed lines the sim does not emit as events but the snapshots imply — the
	# nexus bleeding down is the clearest example (see _build_marks).
	while mark_cursor < marks.size() and int(marks[mark_cursor].t) <= upto:
		feed.append(String(marks[mark_cursor].text))
		_trim_feed()
		mark_cursor += 1


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
				_add_effect(t, tower_pos[key], "text", BASIC_TTL,
					Color(0.85, 0.8, 0.6), "TOWER", 0.0)
			# Structures were falling silently: nothing in the feed said who was
			# taking the map, so a game decided by a siege had no story
			# (2026-07-25 playtest, remark 4).
			var taker := _enemy(String(d.team))
			var tier_name: String = TIER_NAME.get(d.tier, String(d.tier))
			feed.append("[color=#%s]%s[/color] ⌂ %s %s%s" % [
				_teamhex(taker), _team_name(taker), d.lane, tier_name,
				"  (first blood tower)" if bool(d.get("first", false)) else ""])
			if String(d.tier) == "base":
				feed.append("[color=#ffd479]%s nexus is exposed on %s[/color]" % [
					_team_name(String(d.team)), d.lane])
			_trim_feed()
		"gank_call":
			# Macro on screen: how many team-mates read the call, and whether this was
			# a board-read *sandwich* (the jungler cutting the retreat while the laner
			# holds the target) or an opportunistic gank.
			var followers: int = int(d.reactors)
			var tail := " (%d follow)" % followers if followers > 0 else " (no follow-up)"
			# "answers" is the third kind: the jungler turning around for a fight
			# or a tower of his own instead of choosing a play of his own (M5-F).
			var play: String = {"sandwich": "sandwich", "answer": "answers"}.get(
				String(d.get("kind", "gank")), "gank")
			feed.append("[color=#%s]%s[/color] %s %s%s" % [
				_teamhex(d.team), _team_name(d.team), play, d.lane, tail])
			_trim_feed()
		"tempo_call":
			# The play converting: a kill opened that lane and they are spending the
			# window on it instead of walking home.
			feed.append("[color=#%s]%s[/color] press %s (%d)" % [
				_teamhex(d.team), _team_name(d.team), d.lane, int(d.men.size())])
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
	var ttl := ULT_TTL if is_ult else BASIC_TTL
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
			_add_effect(t, at, "aura", ttl + AURA_EXTRA, col, "", 0.0, {"heavy": is_ult})
		"global_teleport":
			_add_effect(t, at, "shockwave", ttl, col, "", 0.0,
				{"world_radius": 3.0, "heavy": false})
	# The name, as a tag rather than bare text, so it stays readable over a fight.
	_add_effect(t, at, "tag", ULT_TAG_TTL if is_ult else BASIC_TTL, col, d.name, 0.0,
		{"font": 15 if is_ult else 11, "heavy": is_ult})
	if not is_ult:
		return
	# An ultimate is the loudest thing a player does, so it also gets said out loud:
	# 54 in a 27-minute match, which the feed absorbs comfortably, and it lets the
	# designer connect a shape on the map to a name and a body count.
	_add_effect(t, at, "cast_flash", ULT_TTL, col, "", 0.0, {})
	var hit := targets.size()
	var tail := ""
	if hit > 0:
		var verb := "helped" if effect == "team_heal" or effect == "team_shield" else "hit"
		tail = " · %d %s" % [hit, verb]
	feed.append("[color=#%s]%s[/color] ult ▸ %s%s" % [
		_teamhex(team), _name(d.player), d.name, tail])
	_trim_feed()


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


# --- M6-C: highlight director ---------------------------------------------------
# The reel (`reel`, built once in _build_reel) is a list of moments, each with a
# `[window_start, window_end]` tick span padded by the pre-roll/aftermath tunables.
# This section's whole job is: know which window (if any) `playback_tick` is inside,
# push the camera + speed in on entry and restore them on exit, and — in
# highlights-only pacing — skip the dead air between one window and the next via
# `_seek()`, the same primitive the transport controls use. It never touches sim/
# state; it only reads `reel` and drives `map`'s existing public camera API.

## Called every frame playback advances (`auto_advance = true`, from `_process()`)
## and once after any timeline jump (`auto_advance = false`, from `_seek()`), so a
## scrub into or out of a highlight snaps the camera the same way natural playback
## does. `auto_advance` alone is allowed to jump the timeline itself (highlights-only
## pacing); a plain re-evaluation after a seek must not, or a scrub would fight itself.
func _update_director(auto_advance: bool) -> void:
	if reel.is_empty():
		return
	var idx := _highlight_at(playback_tick)
	if idx == -1 and auto_advance and pacing_mode == "highlights" \
			and playing and active_highlight != -1:
		var nxt := _next_highlight_after(active_highlight)
		if nxt == -1:
			# That was the last highlight: highlights-only mode has nothing left to
			# jump to, so it ends the match the same way "Skip ▸ Result" does.
			_leave_highlight()
			active_highlight = -1
			_seek(last_tick)
			_finish()
			return
		_seek(int(reel[nxt].window_start))   # re-enters _update_director(false) itself
		return
	if idx != active_highlight:
		if active_highlight != -1:
			_leave_highlight()
		active_highlight = idx
		if idx != -1:
			_enter_highlight(idx)


## The reel index whose padded window contains `pt`, or -1. Reel is small (≤ ~10
## entries per match), so a linear scan every frame is cheap and simple.
func _highlight_at(pt: float) -> int:
	for i in reel.size():
		var mom: Dictionary = reel[i]
		if pt >= float(mom.window_start) and pt <= float(mom.window_end):
			return i
	return -1


func _next_highlight_after(idx: int) -> int:
	return idx + 1 if idx + 1 < reel.size() else -1


## Entering a highlight: save wherever the camera/speed currently are (so leaving
## can put them back exactly), then push in. A no-op if auto-camera is off — the
## banner/skip controls still work off `active_highlight` alone.
func _enter_highlight(idx: int) -> void:
	highlight_released = false
	if not auto_camera:
		return
	_cam_saved = map.camera_state()
	_speed_saved = speed_index
	var mom: Dictionary = reel[idx]
	map.set_target(Vector2(float(mom.pos[0]), float(mom.pos[1])), director_zoom)
	_set_speed(SPEEDS.find(REAL_SPEED), true)


## Leaving a highlight: restore the camera/speed the director itself changed —
## unless the user already took control (`highlight_released`), in which case their
## choice stands and there's nothing of the director's own to put back.
func _leave_highlight() -> void:
	if auto_camera and not highlight_released and _speed_saved != -1:
		map.restore_camera_state(_cam_saved)
		_set_speed(_speed_saved, true)
	_speed_saved = -1
	highlight_released = false


## Manual camera input (wheel/click/F-keys/Escape) during an active highlight backs
## the director off for *this* highlight only — it does not fight the user, and it
## does not carry over to the next highlight, which the director picks up normally.
func _release_director() -> void:
	if active_highlight != -1:
		highlight_released = true


func _on_camera_touched() -> void:
	_release_director()


func _set_auto_camera(v: bool) -> void:
	auto_camera = v
	if active_highlight == -1:
		return
	if not v:
		if not highlight_released and _speed_saved != -1:
			map.restore_camera_state(_cam_saved)
			_set_speed(_speed_saved, true)
		_speed_saved = -1
		highlight_released = true
	else:
		# Picking the director back up mid-highlight: frame whatever's on screen now
		# instead of waiting for the next moment.
		_enter_highlight(active_highlight)


func _set_pacing(mode: String) -> void:
	pacing_mode = mode
	if pacing_btns.size() == 2:
		pacing_btns[0].button_pressed = (mode == "full")
		pacing_btns[1].button_pressed = (mode == "highlights")
	if mode != "highlights" or reel.is_empty() or not sim_ready:
		return
	if _highlight_at(playback_tick) == -1:
		_seek(int(reel[0].window_start))


## "Skip" on the banner: jump past the current highlight's aftermath rather than
## sitting through it — reuses `_seek()`, same as every other transport control.
func _skip_highlight() -> void:
	if active_highlight == -1:
		return
	_seek(mini(int(reel[active_highlight].window_end) + 1, last_tick))


## "Replay" on the banner: jump back to the current highlight's pre-roll.
func _replay_highlight() -> void:
	if active_highlight == -1:
		return
	_seek(int(reel[active_highlight].window_start))


func _rewind() -> void:
	if not sim_ready:
		return
	_seek(maxi(int(playback_tick) - rewind_ticks, 0))


## The banner text: the reel's own one-liner (`Highlights.describe`) plus resolved
## player names, the way the kill feed already does it — "who it's about" is the
## thing `describe()` alone doesn't carry (it names the *kind* of moment, not the
## people in it).
func _highlight_caption(mom: Dictionary) -> String:
	var text := Highlights.describe(mom, smap)
	var names: Array[String] = []
	for id: String in mom.get("killers", []):
		if meta_of.has(id) and not names.has(_name(id)):
			names.append(_name(id))
	for id: String in mom.get("victims", []):
		if meta_of.has(id) and not names.has(_name(id)):
			names.append(_name(id))
	if not names.is_empty():
		text += "  (%s)" % ", ".join(names)
	return text


func _update_highlight_banner() -> void:
	if active_highlight == -1 or active_highlight >= reel.size():
		highlight_banner.visible = false
		return
	highlight_banner.visible = true
	highlight_lbl.text = "[color=#ffd479][b]HIGHLIGHT[/b][/color]  %s" % \
		_highlight_caption(reel[active_highlight])


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
			"id": m.id, "pos": wpos, "team": m.team, "role": m.role, "name": m.name,
			"char_id": m.char_id, "level": int(r0[P_LEVEL]), "alive": alive,
			"hp_frac": clampf(float(r0[P_HP]) / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0,
			"respawn_frac": 1.0, "fighting": false, "casting": 0.0,
			"recalling": false, "shake": Vector2.ZERO,
			"stunned": false, "slowed": false, "backing_off": false,
			"facing": Vector2.RIGHT, "exchanging": false, "flinch": 0.0,
			"moving": false, "last_swing": -1e9,
			"anim_state": "idle", "anim_col": 0, "dying": false,
		}
		if not alive:
			var di: Dictionary = deaths_info.get(m.id, {})
			if di.has("at") and di.at > di.since:
				ch.respawn_frac = clampf((pt - di.since) / float(di.at - di.since), 0.0, 1.0)
			# M6-D: the body plays its die pose at the spot it actually fell
			# (deaths_info records that; the snapshot row itself has already
			# snapped the dead player to the fountain) for a short window before
			# handing off to the established fountain treatment — additive, that
			# treatment (_draw_dead) is unchanged and still what every death
			# settles into once the window passes.
			if di.has("since"):
				var since_death := pt - float(di.since)
				var die_window := float(anim_cfg.timing.die_ticks) * _time_scale()
				if since_death >= 0.0 and since_death <= die_window and die_window > 0.0:
					ch.dying = true
					ch.death_pos = di.get("pos", ch.pos)
					ch.anim_state = "die"
					ch.death_fade = clampf(1.0 - since_death / die_window, 0.0, 1.0)
					var frame_span := maxf(float(anim_cfg.timing.frame_ticks) * _time_scale(), 0.01)
					var cols := int(anim_cfg.sheet.cols)
					ch.anim_col = clampi(int(since_death / frame_span), 0, maxi(cols - 1, 0))
		else:
			# Combat state comes from the snapshot now, not from guessing off the
			# event stream: the sim knows exactly who is engaged, locked or slowed.
			ch.fighting = (flags & SimMatch.FLAG_IN_COMBAT) != 0
			ch.backing_off = (flags & SimMatch.FLAG_DISENGAGING) != 0
			ch.stunned = (flags & SimMatch.FLAG_STUNNED) != 0
			ch.slowed = (flags & SimMatch.FLAG_SLOWED) != 0
			ch.recalling = (flags & SimMatch.FLAG_RECALLING) != 0
			var lu: int = last_ult.get(m.id, -99999)
			ch.casting = clampf(1.0 - (pt - lu) / (float(ULT_TTL) * _time_scale()), 0.0, 1.0)
			ch.last_swing = float(r0[P_SWING])
			# M6-D: read straight off the raw snapshot delta (not the interpolated
			# `wpos`, which always moves a little from the lerp itself) — this is
			# the one flag `_anim_states` needs that isn't already derived above.
			ch.moving = (Vector2(r1[P_X], r1[P_Y]) - p0).length() > MOVE_EPS
			# "In combat" is not the same thing as trading blows: the sim sets it on
			# anyone who has committed to a nearby enemy, which includes two laners
			# standing off across the wave doing nothing to each other. Drawn as a
			# pulsing halo, that made a standoff look like a fight in which no life
			# moved (2026-07-25 playtest, remark 2). An *exchange* is a swing fired
			# or a blow taken in the last second — the taken half is filled in by
			# _hit_pops, which is reading real HP deltas.
			# Still committed to a fight *and* swinging in it. The "still committed"
			# half matters at 4x, where the recency window covers four seconds of sim
			# time and would otherwise outlive the fight it belongs to.
			ch.exchanging = ch.fighting \
				and (pt - float(r0[P_SWING])) <= EXCHANGE_TICKS * _time_scale()
			if ch.exchanging:
				ch.shake = Vector2(sin(pt * 3.3 + k) * 1.4, cos(pt * 2.7 + k) * 1.0)
		champs.append(ch)

	_spread_bodies(champs)
	_resolve_facing(s0, s1, champs)
	# Writes the hit-flash back onto the bodies, so it runs before the frame is
	# handed over.
	var pops := _hit_pops(pt, champs)
	# M6-D: which sprite pose each living body reads as — after _hit_pops, so it
	# can see the flinch (hurt) flag that just landed on the body.
	_anim_states(pt, champs)
	# Minion dots need it too: a besieging wave is drawn swinging at the structure
	# it is chipping, not walking past it.
	var siege := _siege_now(pt)

	last_frame = {
		"champs": champs,
		"beats": _render_beats(pt, s0, champs),
		"tethers": _render_tethers(pt, champs),
		"pops": pops,
		"minions": _minion_dots(s0, siege),
		"towers_down": towers_down,
		"tower_hp": _structure_hp(s0),
		"nexus_hp": _nexus_frac(s0),
		"siege": siege,
		"effects": _render_effects(pt),
		"wards": _render_wards(pt),
		"dragon_total": dragon_total, "dragon_up": dragon_up, "baron_up": baron_up,
		"winner": winner,
	}
	map.set_frame(last_frame)
	_purge(pt)
	_update_hud(pt, gold)
	_update_highlight_banner()


## Minion wave dots, drawn from the squads the sim actually walks down each
## lane (LaneState). A squad is one point carrying a count — individual minions
## are never simulated, which is what keeps 1000-sim batches cheap — so the
## dots are spread here at render time, backward from the squad's position
## toward its own base, two ranks wide. A squad that is chipping a structure
## right now carries the structure's position, so it can be drawn swinging at it.
func _minion_dots(s: Dictionary, siege: Dictionary) -> Array:
	var out: Array = []
	for row: Array in s.get("lanes", []):
		var lane: String = row[0]
		for q: Array in (row[4] if row.size() > 4 else []):
			var side: String = "blue" if int(q[0]) == 0 else "red"
			var lead := float(q[1])
			var dir := -1.0 if side == "blue" else 1.0
			var target: Variant = _siege_target(side, siege, smap.pos_on_lane(lane, lead))
			for i in mini(int(q[2]), MINION_DOTS_MAX):
				var lt := clampf(lead + dir * (MINION_FRONT_GAP + i * MINION_SPACING), 0.0, 1.0)
				var p := smap.pos_on_lane(lane, lt)
				var ahead := smap.pos_on_lane(lane, clampf(lt + 0.01, 0.0, 1.0))
				var perp := Vector2.ZERO
				if p.distance_to(ahead) > 0.001:
					perp = (ahead - p).orthogonal().normalized() * MINION_RANK_OFFSET
				var dot := {"pos": p + (perp if i % 2 == 0 else -perp), "team": side}
				if target != null:
					dot["hit"] = target
				out.append(dot)
	return out


## The structure this squad is grinding down, or null. The sim's siege rule is
## "the lane front is pinned at the defender's bound and the attacker has minions
## there" (`Objectives._update_siege`) — so it is the *wave* that takes a turret,
## and once a lane's turrets are gone, the nexus. Playback used to draw those
## minions walking, which is why a nexus could fall with nothing visibly hitting
## it (2026-07-25 playtest remark 4, confirmed by the designer 2026-07-26: "in
## reality minions are hitting nexus"). Matching is by proximity to a structure
## that is actually losing HP this instant, so nothing is drawn that the sim is
## not doing.
func _siege_target(attacker: String, siege: Dictionary, lead: Vector2) -> Variant:
	var best: Variant = null
	var best_d := SIEGE_REACH
	for key: String in siege:
		var st: Dictionary = struct_at.get(key, {})
		if st.is_empty() or st.team == attacker:
			continue
		var d: float = lead.distance_to(st.pos)
		if d < best_d:
			best_d = d
			best = st.pos
	return best


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
	var pops := 0
	var flinches := 0
	var siege_pulses := 0
	var in_combat_frames := 0
	var exchange_frames := 0
	var nexus_shown := 0
	var siege_minions := 0
	var nexus_besieged := 0
	var kinds := {}
	var anim_counts := {}                 # M6-D: anim_state -> frame count seen
	var dying_frames := 0
	var problems: Array[String] = []
	var frames := 0
	# M6-C: the director has to survive being driven every frame across a whole
	# match with no dropped frame / crash — this is the "entering/leaving a
	# highlight" assertion BACKLOG's M6-C asks --selftest for.
	var highlight_enters := 0
	var highlight_frames := 0
	var prev_highlight := -1
	playing = false
	playback_tick = 0.0
	_seek(0)
	while playback_tick < last_tick:
		playback_tick = minf(playback_tick + SELFTEST_STEP, last_tick)
		_advance_events(int(playback_tick))
		_update_director(true)
		_render()
		frames += 1
		if active_highlight != prev_highlight and active_highlight != -1:
			highlight_enters += 1
		if active_highlight != -1:
			highlight_frames += 1
		prev_highlight = active_highlight
		beats += last_frame.beats.size()
		tethers += last_frame.tethers.size()
		tower_bars = maxi(tower_bars, last_frame.tower_hp.size())
		pops += last_frame.pops.size()
		siege_pulses += last_frame.siege.size()
		for mn: Dictionary in last_frame.minions:
			if mn.has("hit"):
				siege_minions += 1
				if mn.hit == smap.bases.blue or mn.hit == smap.bases.red:
					nexus_besieged += 1
		for ch: Dictionary in last_frame.champs:
			if not ch.alive:
				if ch.get("dying", false):
					dying_frames += 1
				continue
			if ch.flinch > 0.0:
				flinches += 1
			if ch.fighting:
				in_combat_frames += 1
			if ch.exchanging:
				exchange_frames += 1
			var anim_state: String = ch.get("anim_state", "idle")
			anim_counts[anim_state] = int(anim_counts.get(anim_state, 0)) + 1
		for team: String in last_frame.nexus_hp:
			if float(last_frame.nexus_hp[team]) < 1.0:
				nexus_shown += 1
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
	# The 2026-07-25 playtest gaps: damage the eye can see, an exchange that
	# means blows are being traded, and a nexus that does not die silently.
	if pops == 0:
		problems.append("no damage numbers in the whole match")
	if flinches == 0:
		problems.append("no hit-flash on any body")
	if exchange_frames == 0:
		problems.append("nobody ever read as trading blows")
	if exchange_frames >= in_combat_frames and in_combat_frames > 0:
		problems.append("every in-combat frame counted as an exchange: the standoff"
			+ " case is not being separated")
	if winner != "" and siege_pulses == 0:
		problems.append("a nexus fell with no structure ever drawn taking damage")
	# Structures are chipped by the wave, so a chip with no minion swinging at it is
	# the "the nexus died on its own" bug (2026-07-26 designer note).
	if siege_pulses > 0 and siege_minions == 0:
		problems.append("structures were chipped but no besieging minions were drawn")
	if winner != "" and nexus_besieged == 0:
		problems.append("a nexus fell with no minions drawn hitting it")
	if winner != "" and marks.is_empty():
		problems.append("a nexus fell with no nexus-health line in the feed")
	# The reel and the director are read-only over frames already validated above
	# (`_frame_problems` runs every iteration regardless of highlight state), so this
	# only has to confirm the director actually engaged when there was something to
	# engage with — a silent director is as bad as a crashing one.
	if not reel.is_empty() and highlight_enters == 0:
		problems.append("reel has %d moments but the director never entered one" % reel.size())

	# M6-D: the animated pose has to actually track what the sim reported, the
	# same "what happened has to show up on screen" standard the checks above
	# hold every other visual to.
	var kills := 0
	for ev: Dictionary in events:
		if ev.type == "kill":
			kills += 1
	if int(anim_counts.get("idle", 0)) == 0:
		problems.append("nobody ever read as idle")
	if int(anim_counts.get("run", 0)) == 0:
		problems.append("nobody ever read as running")
	if beats > 0 and int(anim_counts.get("attack", 0)) == 0:
		problems.append("%d attack beats fired, no body ever read as attacking" % beats)
	if flinches > 0 and int(anim_counts.get("hurt", 0)) == 0:
		problems.append("%d hit-flashes, no body ever read as hurt" % flinches)
	if casts.ultimate_cast > 0 and int(anim_counts.get("cast", 0)) == 0:
		problems.append("%d ultimates cast, no body ever read as casting" % casts.ultimate_cast)
	if kills > 0 and dying_frames == 0:
		problems.append("%d kills, no body ever played its die pose" % kills)

	print("VIEWER SELFTEST (seed %d, %d ticks, %d frames)" % [seed_val, last_tick, frames])
	print("  attack beats: %d | catch tethers: %d | towers chipped (peak): %d" % [
		beats, tethers, tower_bars])
	print("  damage numbers: %d | hit-flashes: %d | siege pulses: %d" % [
		pops, flinches, siege_pulses])
	print("  besieging minion-dots: %d, of which swinging at a nexus: %d" % [
		siege_minions, nexus_besieged])
	print("  player-frames in combat: %d, of which trading blows: %d (%.0f%%)" % [
		in_combat_frames, exchange_frames,
		100.0 * float(exchange_frames) / float(maxi(in_combat_frames, 1))])
	print("  frames with a wounded nexus: %d | nexus feed lines: %d" % [
		nexus_shown, marks.size()])
	print("  effect kinds: %s" % str(kinds))
	print("  anim states (player-frames): %s | die-pose frames: %d" % [str(anim_counts), dying_frames])
	# The last thing the designer reads when a match ends: it has to explain the
	# result on its own ("finished without any understanding how", remark 4).
	print("  feed at the final whistle:")
	for line: String in feed.slice(maxi(feed.size() - 6, 0)):
		print("    %s" % _plain(line))
	print("  sim events: %d ultimates, %d CC applications" % [
		casts.ultimate_cast, casts.cc_applied])
	print("  reel: %d moments, director entered %d, %d/%d frames inside a highlight" % [
		reel.size(), highlight_enters, highlight_frames, frames])
	if problems.is_empty():
		print("VIEWER SELFTEST: PASS")
		get_tree().quit(0)
		return
	for p: String in problems:
		print("  FAIL: %s" % p)
	print("VIEWER SELFTEST: FAIL")
	get_tree().quit(1)


## How much longer a transient stays on screen at the current playback speed.
## Everything with a lifetime is measured in sim ticks, and 4x runs sixteen sim
## seconds a real second — an ult impact would be back to a 0.16 s flicker. So
## the *read* windows stretch with the speed, capped at 4x: past that the game is
## being skipped rather than watched, and stretching further would leave a hit
## marker on screen while its fight moved to another lane. This has to open
## *downward* too: at the 0.25x real-speed tier (M6-C), the sim runs four times
## slower than 1x, so a lifetime written for 1x would linger four times too long
## in the close-up unless it shrinks below 1. `mini()` truncates its args to int
## (mini(0.25, 4) == 0, which would zero out every effect's lifetime at real
## speed) — `minf()` is the float-safe version and is required here.
func _time_scale() -> float:
	return minf(SPEEDS[speed_index], 4.0)


## BBCode out, for printing a feed line to a terminal.
func _plain(line: String) -> String:
	var out := ""
	var depth := 0
	for ch in line:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth = maxi(depth - 1, 0)
		elif depth == 0:
			out += ch
	return out


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
		var sheet_rows: Array = anim_cfg.get("sheet", {}).get("rows", ANIM_STATES)
		if not sheet_rows.has(ch.get("anim_state", "idle")):
			out.append("%s has an anim_state \"%s\" with no sheet row" % [ch.name, ch.anim_state])
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


## Damage, made visible. Every snapshot carries each player's HP and every chipped
## structure's, so playback can diff consecutive snapshots and show blows *landing*:
## a hit-flash on the body plus a floating number, and a pulse on a structure that
## is losing HP this second.
##
## The designer watched two players trade for seconds and reported "the life does
## not move" (2026-07-25 playtest, remark 2). It was moving — a few pixels at a
## time on a 22-pixel bar, with no other sign that a swing had connected.
##
## Precomputed once per sim rather than diffed per frame: a frame at 1x covers less
## than one snapshot step, and a scrub jumps many, so per-frame diffing would both
## miss pops and double-count them. Read-only over the sim's output.
func _build_hits() -> void:
	hits.clear()
	sieges.clear()
	if snapshots.size() < 2:
		return
	var before := _structure_raw(snapshots[0])
	for i in range(1, snapshots.size()):
		var prev: Array = snapshots[i - 1].players
		var cur: Dictionary = snapshots[i]
		var t: int = cur.t
		for k in pmeta.size():
			var a: Array = prev[k]
			var b: Array = cur.players[k]
			# Dying is already a kill marker and respawning is not a heal.
			if int(a[P_ALIVE]) == 0 or int(b[P_ALIVE]) == 0:
				continue
			var delta := float(b[P_HP]) - float(a[P_HP])
			if delta <= -HIT_MIN_DMG:
				hits.append({"t": t, "k": k, "amount": -delta, "heal": false})
			elif delta >= HIT_MIN_HEAL:
				hits.append({"t": t, "k": k, "amount": delta, "heal": true})
		var now := _structure_raw(cur)
		for key: String in now:
			# A structure that has only just appeared in the snapshot took its first
			# damage this tick, so a missing previous value counts as a loss too.
			if float(now[key]) < float(before.get(key, INF)):
				sieges.append({"t": t, "key": key})
		before = now


## Feed lines for what the snapshots say but the sim never emits as an event: the
## nexus losing health. It matters because of *how* the sim ends games — measured
## over 12 seeds, the losing nexus bleeds for 6 minutes on average (13 in the worst
## case) under minion pressure, often with no champion anywhere near it. Watching
## that, the designer reported the match "finished without any understanding how"
## (2026-07-25 playtest, remark 4). The pacing itself is a balance question for
## M5-G; what playback owes the viewer is the running commentary.
func _build_marks() -> void:
	marks.clear()
	var next_mark := {"blue": 0, "red": 0}
	for s: Dictionary in snapshots:
		var n: Array = s.get("nexus", [])
		if n.size() != 2:
			continue
		for i in 2:
			var team := "blue" if i == 0 else "red"
			var frac := float(n[i]) / nexus_max_hp
			while next_mark[team] < NEXUS_MARKS.size() \
					and frac <= float(NEXUS_MARKS[next_mark[team]]):
				var level := float(NEXUS_MARKS[next_mark[team]])
				next_mark[team] += 1
				marks.append({"t": int(s.t), "text":
					"[color=#ffd479]%s nexus at %d%%[/color]" % [
						_team_name(team), int(round(level * 100.0))]})


## Raw HP of everything the sim reports as damaged, structures and both nexuses,
## under the keys the viewer draws them with.
## Where every structure stands, keyed the way the siege list keys it. Built once
## per sim run so the besieging-wave lookup is a dictionary hit per frame.
func _build_structures() -> void:
	struct_at.clear()
	for team: String in SimMap.TEAMS:
		for lane: String in SimMap.LANES:
			for tier: String in smap.tier_order[team]:
				struct_at["%s_%s_%s" % [team, lane, tier]] = {
					"pos": smap.pos_on_lane(lane, float(smap.towers[team][tier])),
					"team": team,
				}
		struct_at["nexus_%s" % team] = {"pos": smap.bases[team], "team": team}


func _structure_raw(s: Dictionary) -> Dictionary:
	var out := {}
	for row: Array in s.get("towers", []):
		out["%s_%s_%s" % [row[0], row[1], row[2]]] = float(row[3])
	var n: Array = s.get("nexus", [])
	if n.size() == 2:
		if float(n[0]) < nexus_max_hp:
			out["nexus_blue"] = float(n[0])
		if float(n[1]) < nexus_max_hp:
			out["nexus_red"] = float(n[1])
	return out


## Floating numbers for every HP change inside the last DMG_TTL ticks, and the
## hit-flash written back onto the bodies themselves.
func _hit_pops(pt: float, champs: Array) -> Array:
	var out: Array = []
	var window := float(DMG_TTL) * _time_scale()
	var i := _index_from(hits, pt - window)
	while i < hits.size() and float(hits[i].t) <= pt:
		var h: Dictionary = hits[i]
		i += 1
		var ch: Dictionary = champs[h.k]
		if not ch.alive:
			continue
		var age_ticks := pt - float(h.t)
		out.append({
			"pos": ch.pos, "amount": int(round(h.amount)), "heal": bool(h.heal),
			"age": clampf(age_ticks / window, 0.0, 1.0),
		})
		var flinch_window := FLINCH_TICKS * _time_scale()
		if not h.heal and age_ticks <= flinch_window:
			ch.flinch = maxf(ch.flinch, 1.0 - age_ticks / flinch_window)
	return out


## M6-D: which pose of the shared placeholder sprite sheet (game/map_view.gd
## _draw_body) a living body reads as this frame, and which frame of it —
## derived entirely from flags/timings the sim already reports or that
## playback already derives from them (Pillar 3: no new sim plumbing needed).
##
## Priority, highest first: recall (a channel the player chose to commit to)
## > hurt (a hit just landed — read it before anything queued behind it)
## > cast (an ultimate just fired) > attack (mid-swing, the same window
## `_render_beats` uses for the swing itself, so the pose and the beat are
## synced by construction) > run (moving) > idle. Which state wins when
## several are true at once is an unmeasured "feels right" call (M6-D), same
## status as M6-B/C's zoom and director constants — the sim reports what
## happened, this only decides which one pose the body shows for it.
##
## `anim_since` is sticky per row (like `facing`): a pose holds its own frame
## clock from the tick it *became* the read state, so a swing landing mid-idle
## starts its attack pose at frame 0 instead of some arbitrary column.
func _anim_states(pt: float, champs: Array) -> void:
	var frame_span := maxf(float(anim_cfg.timing.frame_ticks) * _time_scale(), 0.01)
	var cols := int(anim_cfg.sheet.cols)
	var attack_window := SWING_TICKS * _time_scale()
	for k in champs.size():
		var ch: Dictionary = champs[k]
		if not ch.alive:
			continue
		var state := "idle"
		if ch.recalling:
			state = "recall"
		elif ch.flinch > 0.0:
			state = "hurt"
		elif ch.casting > 0.0:
			state = "cast"
		elif (pt - float(ch.last_swing)) <= attack_window:
			state = "attack"
		elif ch.moving:
			state = "run"
		var prev: Dictionary = anim_since.get(k, {})
		if String(prev.get("state", "")) != state:
			prev = {"state": state, "since": pt}
			anim_since[k] = prev
		var elapsed := maxf(pt - float(prev.since), 0.0)
		ch.anim_state = state
		ch.anim_col = int(elapsed / frame_span) % maxi(cols, 1)


## Structures losing HP right now — the "something is being taken" cue, which is
## what a slow minion siege on an empty base was missing entirely (remark 4).
func _siege_now(pt: float) -> Dictionary:
	var out := {}
	var window := float(SIEGE_TICKS) * _time_scale()
	var i := _index_from(sieges, pt - window)
	while i < sieges.size() and float(sieges[i].t) <= pt:
		var s: Dictionary = sieges[i]
		i += 1
		out[s.key] = maxf(float(out.get(s.key, 0.0)), 1.0 - (pt - float(s.t)) / window)
	return out


## First entry of a tick-ordered list at or after `t`. Binary search: these lists
## run to tens of thousands of entries and are walked every frame.
func _index_from(list: Array, t: float) -> int:
	var lo := 0
	var hi := list.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if float(list[mid].t) < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


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
		var span := SWING_TICKS * _time_scale()
		if age < 0.0 or age > span:
			continue
		var tgt := int(row[P_TARGET])
		if tgt < 0 or tgt >= champs.size() or not champs[tgt].alive:
			continue
		out.append({
			"from": ch.pos, "to": champs[tgt].pos, "team": ch.team,
			"ranged": bool(pmeta[k].ranged), "frac": age / span,
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
	var scale := _time_scale()
	for e: Dictionary in effects:
		var age: float = (pt - e.born) / (float(e.ttl) * scale)
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
	_update_structures()


## Turrets standing and nexus health for both sides, every frame. This is the
## match clock the map alone never showed: who is ahead on the map, and how
## close the game is to ending.
func _update_structures() -> void:
	var nexus: Dictionary = last_frame.get("nexus_hp", {})
	var lines: Array[String] = []
	for team in ["blue", "red"]:
		var standing := 0
		for lane in SimMap.LANES:
			for tier: String in TIER_NAME:
				if not towers_down.has("%s_%s_%s" % [team, lane, tier]):
					standing += 1
		var frac := clampf(float(nexus.get(team, 1.0)), 0.0, 1.0)
		var filled := int(round(frac * float(NEXUS_CELLS)))
		var bar := "█".repeat(filled) + "░".repeat(NEXUS_CELLS - filled)
		var hue := "d6dbe6" if frac > 0.5 else ("ffd479" if frac > 0.25 else "ff6b5e")
		lines.append("[color=#%s]%s[/color]  ⌂%d  [color=#%s]%s[/color] %d%%" % [
			_teamhex(team), _team_name(team).substr(0, 10), standing,
			hue, bar, int(round(frac * 100.0))])
	struct_lbl.text = "\n".join(lines)


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
	var scale := _time_scale()
	effects = effects.filter(func(e): return pt < e.born + e.ttl * scale)
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
	mark_cursor = 0
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
	anim_since = {}
	effects = []
	feed = []
	feed_dirty = true
	# A restart/seek can happen mid-highlight; leave it cleanly (restoring whatever
	# camera/speed the director itself changed) before jumping the timeline, rather
	# than stranding the camera at a director push that no longer applies.
	if active_highlight != -1:
		_leave_highlight()
	active_highlight = -1
	highlight_released = false
	_speed_saved = -1


## `from_director` distinguishes the director's own speed pushes from a user
## pressing a speed button by hand — a manual press during an active highlight
## counts as taking the controls back, same as a manual camera touch does.
func _set_speed(i: int, from_director := false) -> void:
	if not from_director:
		_release_director()
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
	_update_director(false)   # snap the camera in if the new spot is inside a highlight
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
	# Manual camera input (wheel/click) during an active highlight releases the
	# director for it, same as the F-key/Escape hotkeys already do in _unhandled_input.
	map.camera_touched.connect(_on_camera_touched)

	_build_topbar()
	_build_sidepanel()
	_build_bottombar()
	_build_overlay()
	_build_highlight_banner()

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
	# Structures, always on screen. A match is won by taking these, and the sim
	# often wins one by grinding a nexus down over minutes with minions — with no
	# standing readout, the end came out of nowhere (2026-07-25 playtest, remark 4).
	_side_vbox.add_child(_small_label("STRUCTURES", "8a93a6"))
	struct_lbl = RichTextLabel.new()
	struct_lbl.bbcode_enabled = true
	struct_lbl.fit_content = true
	struct_lbl.scroll_active = false
	struct_lbl.add_theme_font_size_override("normal_font_size", 12)
	_side_vbox.add_child(struct_lbl)
	_side_vbox.add_child(HSeparator.new())
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
		var b := _ctl_button(_speed_label(SPEEDS[i]))
		b.toggle_mode = true
		b.button_pressed = (i == speed_index)
		var idx := i
		b.pressed.connect(func(): _set_speed(idx))
		speed_btns.append(b)
		h.add_child(b)

	# Manual zoom (M6-B): mouse wheel over the map is the primary control, these
	# are the secondary affordance next to the speed buttons per the phase spec.
	# Also counts as manual camera input (M6-C): releases the director for the
	# current highlight, same as wheel-zoom/click on the map itself.
	var zoom_out_btn := _ctl_button("Zoom −")
	zoom_out_btn.pressed.connect(func(): map.zoom_step(-1); _release_director())
	h.add_child(zoom_out_btn)
	var zoom_in_btn := _ctl_button("Zoom +")
	zoom_in_btn.pressed.connect(func(): map.zoom_step(1); _release_director())
	h.add_child(zoom_in_btn)

	# M6-C: auto-camera toggle and pacing mode. Auto-camera is a toggle, manual
	# camera is always available regardless of its state (BACKLOG M6-C).
	auto_cam_btn = _ctl_button("Auto-cam: ON")
	auto_cam_btn.toggle_mode = true
	auto_cam_btn.button_pressed = true
	auto_cam_btn.pressed.connect(func():
		_set_auto_camera(auto_cam_btn.button_pressed)
		auto_cam_btn.text = "Auto-cam: ON" if auto_camera else "Auto-cam: OFF")
	h.add_child(auto_cam_btn)

	pacing_btns.clear()
	var full_btn := _ctl_button("Full")
	full_btn.toggle_mode = true
	full_btn.button_pressed = true
	full_btn.pressed.connect(func(): _set_pacing("full"))
	pacing_btns.append(full_btn)
	h.add_child(full_btn)
	var highlights_btn := _ctl_button("Highlights")
	highlights_btn.toggle_mode = true
	highlights_btn.pressed.connect(func(): _set_pacing("highlights"))
	pacing_btns.append(highlights_btn)
	h.add_child(highlights_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var rewind_btn := _ctl_button("⏪ Rewind")
	rewind_btn.pressed.connect(_rewind)
	h.add_child(rewind_btn)

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


## M6-C: the on-screen framing for whatever highlight `playback_tick` is currently
## inside — "what this is, who it's about" — plus its own transport (replay/skip),
## so "replay that highlight" is one click from the thing that names it. Docked to
## the top of the map panel in _layout(); hidden whenever there's no active highlight.
func _build_highlight_banner() -> void:
	highlight_banner = _panel("1a2233")
	highlight_banner.name = "HighlightBanner"
	highlight_banner.visible = false
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10; h.offset_right = -10; h.offset_top = 4; h.offset_bottom = -4
	h.add_theme_constant_override("separation", 10)
	highlight_banner.add_child(h)

	highlight_lbl = RichTextLabel.new()
	highlight_lbl.bbcode_enabled = true
	highlight_lbl.fit_content = true
	highlight_lbl.scroll_active = false
	highlight_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	highlight_lbl.add_theme_font_size_override("normal_font_size", 14)
	h.add_child(highlight_lbl)

	var replay_btn := _ctl_button("↺ Replay")
	replay_btn.pressed.connect(_replay_highlight)
	h.add_child(replay_btn)

	var skip_hl_btn := _ctl_button("Skip ▸")
	skip_hl_btn.pressed.connect(_skip_highlight)
	h.add_child(skip_hl_btn)


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


## "1x"/"4x"/"16x" for the whole numbers SPEEDS used to hold; "0.25x" for the M6-C
## real-speed tier, which isn't one.
func _speed_label(v: float) -> String:
	return ("%.2fx" % v) if v < 1.0 else ("%dx" % int(round(v)))


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

	if highlight_banner != null:
		# Docked to the top edge of the map itself, so it always sits over the
		# thing it's narrating regardless of camera zoom/position underneath it.
		highlight_banner.position = Vector2(map.position.x, map_y + 6.0)
		highlight_banner.size = Vector2(map_side, 32.0)
