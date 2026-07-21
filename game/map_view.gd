extends Control
## M4 match viewer — the play field. Pure presentation: it holds the static
## map geometry (lanes, towers, pits, camps, bases) and, each frame, a fully
## resolved `frame` dict handed to it by the MatchViewer. It knows nothing
## about ticks, the sim, or timing — it just draws what it is given. All sim
## state lives in sim/; this is playback only (GDD pillar 3).
##
## World coordinates are 0..100 (data/map.json). We flip Y on the way to the
## screen so blue sits bottom-left and red top-right — the LoL orientation,
## which makes the map read at a glance.

const PAD := 14.0            # inner margin, px
const CHAMP_R := 10.0        # champion disc radius, px (fixed, not world-scaled)
const TOWER_R := 6.0
const CAMP_R := 3.0
const MINION_R := 2.2
const PIT_R := 15.0
const NEXUS_R := 13.0

# Palette ---------------------------------------------------------------------
const C_BG := Color("101520")
const C_BORDER := Color("2a3446")
const C_LANE := Color(0.30, 0.32, 0.26, 0.55)
const C_LANE_CORE := Color(0.42, 0.44, 0.34, 0.55)
const C_RIVER := Color(0.20, 0.42, 0.72, 0.16)
const C_CAMP := Color(0.52, 0.50, 0.34)
const C_DRAGON := Color(0.95, 0.60, 0.24)
const C_BARON := Color(0.70, 0.50, 1.0)
const TEAM := {
	"blue": {"fill": Color(0.30, 0.55, 1.0), "ring": Color(0.62, 0.78, 1.0), "dark": Color(0.18, 0.30, 0.55)},
	"red": {"fill": Color(1.0, 0.42, 0.42), "ring": Color(1.0, 0.66, 0.66), "dark": Color(0.55, 0.22, 0.22)},
}
const ROLE_LETTER := {"top": "T", "jungle": "J", "mid": "M", "carry": "C", "support": "S"}

var world_size := 100.0
var geom := {}              # static geometry, world coords (set by setup_geometry)
var frame := {}             # resolved render state for the current playback tick

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup_geometry(map: SimMap, char_textures: Dictionary) -> void:
	world_size = map.size
	var lanes := {}
	for lane in SimMap.LANES:
		lanes[lane] = map.lane_paths[lane]
	var towers: Array = []
	for team in SimMap.TEAMS:
		for lane in SimMap.LANES:
			for tier: String in map.towers[team]:
				towers.append({
					"team": team, "lane": lane, "tier": tier,
					"pos": map.pos_on_lane(lane, float(map.towers[team][tier])),
				})
	var camps: Array = []
	for c in map.camps:
		camps.append(c.pos)
	geom = {
		"lanes": lanes,
		"towers": towers,
		"pits": {"dragon": map.pits.dragon, "baron": map.pits.baron},
		"camps": camps,
		"bases": {"blue": map.bases.blue, "red": map.bases.red},
		"textures": char_textures,  # char_id -> Texture2D (or absent)
	}
	queue_redraw()


func set_frame(f: Dictionary) -> void:
	frame = f
	queue_redraw()


# --- world -> screen ----------------------------------------------------------

func _scale() -> float:
	return (minf(size.x, size.y) - 2.0 * PAD) / world_size


func _w2s(w: Vector2) -> Vector2:
	var s := _scale()
	var span := world_size * s
	var ox := (size.x - span) * 0.5
	var oy := (size.y - span) * 0.5
	# Flip Y: world y=0 (blue side) renders at the bottom.
	return Vector2(ox + w.x * s, oy + (world_size - w.y) * s)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if geom.is_empty():
		return
	_draw_field()
	_draw_lanes()
	_draw_river()
	_draw_camps()
	_draw_pits()
	_draw_bases()
	_draw_towers()
	if frame.is_empty():
		return
	_draw_minions()
	_draw_wards()
	_draw_champions()
	_draw_effects()


func _draw_field() -> void:
	var tl := _w2s(Vector2(0, world_size))
	var span := world_size * _scale()
	var rect := Rect2(tl, Vector2(span, span))
	draw_rect(rect, C_BG, true)
	draw_rect(rect, C_BORDER, false, 2.0)


func _draw_lanes() -> void:
	var w := maxf(_scale() * 3.2, 4.0)
	for lane: String in geom.lanes:
		var pts := PackedVector2Array()
		for p: Vector2 in geom.lanes[lane]:
			pts.append(_w2s(p))
		draw_polyline(pts, C_LANE, w, true)
		draw_polyline(pts, C_LANE_CORE, w * 0.45, true)


func _draw_river() -> void:
	# The river runs along the anti-diagonal x + y = world_size, through the pits.
	var band := PackedVector2Array([
		_w2s(Vector2(0, world_size)), _w2s(Vector2(world_size * 0.28, world_size)),
		_w2s(Vector2(world_size, world_size * 0.28)), _w2s(Vector2(world_size, 0)),
		_w2s(Vector2(world_size * 0.72, 0)), _w2s(Vector2(0, world_size * 0.72)),
	])
	draw_colored_polygon(band, C_RIVER)


func _draw_camps() -> void:
	for p: Vector2 in geom.camps:
		draw_circle(_w2s(p), CAMP_R, C_CAMP)


func _draw_pits() -> void:
	_draw_pit(geom.pits.dragon, C_DRAGON, "D",
		frame.get("dragon_up", false), int(frame.get("dragon_total", 0)))
	_draw_pit(geom.pits.baron, C_BARON, "B",
		frame.get("baron_up", false), -1)


func _draw_pit(w: Vector2, col: Color, letter: String, up: bool, count: int) -> void:
	var c := _w2s(w)
	var glow := 0.30 if up else 0.12
	draw_circle(c, PIT_R - 2.0, Color(col.r, col.g, col.b, glow))
	draw_arc(c, PIT_R, 0, TAU, 32, col, 2.5 if up else 1.5, true)
	_centered(letter, c, 15, col)
	if count >= 0:
		_centered("x%d" % count, c + Vector2(0, PIT_R + 9), 11, col)


func _draw_bases() -> void:
	for team: String in geom.bases:
		var c := _w2s(geom.bases[team])
		var t: Dictionary = TEAM[team]
		var alive: bool = frame.get("winner", "") != _enemy(team)
		var col: Color = t.fill if alive else Color(0.35, 0.35, 0.35)
		draw_circle(c, NEXUS_R, Color(col.r, col.g, col.b, 0.22))
		draw_arc(c, NEXUS_R, 0, TAU, 28, col, 2.5, true)
		# Nexus diamond.
		var d := NEXUS_R * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), col)


func _draw_towers() -> void:
	var down: Dictionary = frame.get("towers_down", {})
	for tw: Dictionary in geom.towers:
		var key: String = "%s_%s_%s" % [tw.team, tw.lane, tw.tier]
		var c := _w2s(tw.pos)
		if down.has(key):
			draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color(0.30, 0.30, 0.30), 2.0)
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.30, 0.30, 0.30), 2.0)
			continue
		var t: Dictionary = TEAM[tw.team]
		var r := TOWER_R if tw.tier != "base" else TOWER_R + 1.5
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), t.dark, true)
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), t.ring, false, 1.5)


## Minion waves. Drawn under the champions so they read as background pressure:
## which lane is pushed, and by whom, at a glance.
func _draw_minions() -> void:
	for mn: Dictionary in frame.get("minions", []):
		var c := _w2s(mn.pos)
		var col: Color = TEAM[mn.team].fill
		draw_circle(c, MINION_R, Color(col.r, col.g, col.b, 0.75))


func _draw_wards() -> void:
	for wd: Dictionary in frame.get("wards", []):
		var c := _w2s(wd.pos)
		var col: Color = TEAM[wd.team].ring
		col.a = wd.alpha
		draw_arc(c, 4.0, 0, TAU, 12, col, 1.5, true)
		draw_circle(c, 1.5, col)


func _draw_champions() -> void:
	var textures: Dictionary = geom.get("textures", {})
	for ch: Dictionary in frame.get("champs", []):
		var base := _w2s(ch.pos)
		var t: Dictionary = TEAM[ch.team]
		if not ch.alive:
			_draw_dead(base, ch, t)
			continue
		var c: Vector2 = base + ch.get("shake", Vector2.ZERO)

		# Fight / ult flares (drawn under the disc).
		if ch.get("casting", 0.0) > 0.0:
			var a: float = ch.casting
			draw_arc(c, CHAMP_R + 6 + (1.0 - a) * 16.0, 0, TAU, 24,
				Color(1.0, 0.95, 0.5, a * 0.8), 2.0, true)
		if ch.get("fighting", false):
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 90.0)
			draw_arc(c, CHAMP_R + 4, 0, TAU, 20, Color(1.0, 0.85, 0.3, 0.4 + 0.4 * pulse), 2.0, true)
		if ch.get("recalling", false):
			var rp := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 120.0)
			draw_arc(c, CHAMP_R + 8, 0, TAU, 24, Color(0.4, 0.9, 0.9, 0.35 + 0.3 * rp), 2.0, true)

		# Body: real sprite if the character's texture exists, else placeholder disc.
		var tex: Texture2D = textures.get(ch.char_id, null)
		if tex != null:
			var ts := CHAMP_R * 2.2
			draw_texture_rect(tex, Rect2(c - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false, t.fill)
			draw_arc(c, CHAMP_R + 1, 0, TAU, 20, t.ring, 2.0, true)
		else:
			draw_circle(c, CHAMP_R, t.fill)
			draw_arc(c, CHAMP_R, 0, TAU, 20, t.ring, 2.0, true)
			_centered(ROLE_LETTER.get(ch.role, "?"), c, 12, Color.WHITE)

		# Level badge (top-right of disc).
		var bp := c + Vector2(CHAMP_R * 0.9, -CHAMP_R * 0.9)
		draw_circle(bp, 6.5, Color(0.08, 0.09, 0.12, 0.9))
		_centered(str(ch.level), bp, 10, Color(0.95, 0.9, 0.7))

		# Health bar + handle. Colour shifts green -> amber -> red as it drops,
		# so a hurt player is readable without reading the bar length.
		var hp_frac: float = ch.get("hp_frac", 1.0)
		_draw_bar(c + Vector2(0, CHAMP_R + 4), hp_frac, _hp_color(hp_frac))
		_centered(ch.name, c + Vector2(0, CHAMP_R + 16), 10, Color(0.85, 0.87, 0.92))


func _draw_dead(base: Vector2, ch: Dictionary, t: Dictionary) -> void:
	# Greyed disc at base + respawn bar filling toward return.
	draw_circle(base, CHAMP_R, Color(0.24, 0.25, 0.28))
	draw_arc(base, CHAMP_R, 0, TAU, 20, Color(0.4, 0.4, 0.42), 1.5, true)
	# Skull-ish mark.
	draw_line(base + Vector2(-3, -2), base + Vector2(3, -2), Color(0.6, 0.6, 0.6), 1.5)
	draw_line(base + Vector2(0, -4), base + Vector2(0, 3), Color(0.6, 0.6, 0.6), 1.5)
	_draw_bar(base + Vector2(0, CHAMP_R + 4), ch.get("respawn_frac", 0.0), t.dark)
	_centered(ch.name, base + Vector2(0, CHAMP_R + 16), 10, Color(0.5, 0.52, 0.56))


func _hp_color(frac: float) -> Color:
	if frac > 0.5:
		return Color(0.40, 0.85, 0.45)
	if frac > 0.25:
		return Color(0.95, 0.75, 0.25)
	return Color(0.95, 0.35, 0.30)


func _draw_bar(center: Vector2, frac: float, col: Color) -> void:
	var w := 22.0
	var h := 3.5
	var tl := center - Vector2(w * 0.5, h * 0.5)
	draw_rect(Rect2(tl, Vector2(w, h)), Color(0.05, 0.06, 0.08, 0.85), true)
	if frac > 0.0:
		draw_rect(Rect2(tl, Vector2(w * clampf(frac, 0.0, 1.0), h)), col, true)


func _draw_effects() -> void:
	for e: Dictionary in frame.get("effects", []):
		var c := _w2s(e.pos)
		var col: Color = e.color
		col.a = e.alpha
		match e.kind:
			"ring":
				draw_arc(c, e.radius, 0, TAU, 28, col, 2.5, true)
			"text":
				var rise: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise), int(e.get("font", 13)), col)
			"banner":
				var rise2: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise2), int(e.get("font", 18)), col)


func _centered(text: String, center: Vector2, font_size: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := center - sz * 0.5 + Vector2(0, sz.y * 0.5 - _font.get_descent(font_size) * 0.3)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _enemy(team: String) -> String:
	return "red" if team == "blue" else "blue"
