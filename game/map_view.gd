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
# Champion body radius is world-derived (not a fixed pixel size) so that the
# playback separation (MatchViewer._spread_bodies, a body's width apart) actually
# reads on screen as five players standing together rather than one fat disc.
# Clamped so it stays legible in a small window.
const CHAMP_WORLD_R := 0.95   # world units
const CHAMP_R_MIN := 6.0      # px
const CHAMP_R_MAX := 11.0     # px
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


## Champion body radius in px for the current window size.
func _champ_r() -> float:
	return clampf(CHAMP_WORLD_R * _scale(), CHAMP_R_MIN, CHAMP_R_MAX)


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
	_draw_tethers()      # under the bodies: a CC link belongs behind them
	_draw_champions()
	_draw_beats()        # over the bodies: the swing lands on top of the fight
	_draw_effects()
	_draw_pops()         # numbers last: they must survive a crowded fight


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
	var nexus: Dictionary = frame.get("nexus_hp", {})
	var siege: Dictionary = frame.get("siege", {})
	for team: String in geom.bases:
		var c := _w2s(geom.bases[team])
		var t: Dictionary = TEAM[team]
		var alive: bool = frame.get("winner", "") != _enemy(team)
		var col: Color = t.fill if alive else Color(0.35, 0.35, 0.35)
		var frac: float = clampf(float(nexus.get(team, 1.0)), 0.0, 1.0)
		draw_circle(c, NEXUS_R, Color(col.r, col.g, col.b, 0.22))
		draw_arc(c, NEXUS_R, 0, TAU, 28, col, 2.5, true)
		# The nexus diamond drains as it takes damage: the sim can spend six minutes
		# grinding one down with minions, so its health has to be readable at a
		# glance and not only in a bar (2026-07-25 playtest, remark 4).
		var d := NEXUS_R * 0.5
		var hull := PackedVector2Array([
			c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
		draw_colored_polygon(hull, Color(col.r, col.g, col.b, 0.20))
		if frac > 0.0:
			# Same diamond, scaled about its own centre — a shrinking core.
			var core := PackedVector2Array()
			for pnt: Vector2 in hull:
				core.append(c + (pnt - c) * frac)
			draw_colored_polygon(core, col)
		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, Color(col.r, col.g, col.b, 0.85), 1.4, true)
		if alive and frac < 1.0:
			_draw_bar(c + Vector2(0, NEXUS_R + 7.0), frac, _hp_color(frac), true)
			_centered("%d%%" % int(round(frac * 100.0)), c + Vector2(0, NEXUS_R + 18.0),
				11, _hp_color(frac))
		if alive:
			_draw_siege_pulse(c, NEXUS_R + 3.0, float(siege.get("nexus_%s" % team, 0.0)))


## Towers, with health on the glyph itself. A turret drains like a battery — the
## coloured core shrinks with its HP — and adds a bar plus a red flash once it is
## really hurt. The thin bar alone was missed entirely in the 2026-07-25 playtest
## ("I do not see life of buildings"), even though it was on screen for 89% of a
## match: it is 3 px tall, sitting on top of a lane line.
func _draw_towers() -> void:
	var down: Dictionary = frame.get("towers_down", {})
	var hp: Dictionary = frame.get("tower_hp", {})
	var siege: Dictionary = frame.get("siege", {})
	for tw: Dictionary in geom.towers:
		var key: String = "%s_%s_%s" % [tw.team, tw.lane, tw.tier]
		var c := _w2s(tw.pos)
		if down.has(key):
			# Rubble: a dark stump where the turret was, so the hole in the map reads.
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0.13, 0.14, 0.17), true)
			draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color(0.34, 0.34, 0.36), 2.0)
			draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), Color(0.34, 0.34, 0.36), 2.0)
			continue
		var t: Dictionary = TEAM[tw.team]
		var r := TOWER_R if tw.tier != "base" else TOWER_R + 2.0
		var frac: float = clampf(float(hp.get(key, 1.0)), 0.0, 1.0)
		# Shell, then a core scaled to health, then the outline on top.
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)),
			Color(t.dark.r, t.dark.g, t.dark.b, 0.35), true)
		if frac > 0.0:
			var cr := r * frac
			draw_rect(Rect2(c - Vector2(cr, cr), Vector2(cr * 2, cr * 2)), t.dark, true)
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), t.ring, false, 1.5)
		_draw_siege_pulse(c, r + 3.0, float(siege.get(key, 0.0)))
		if frac >= 1.0:
			continue
		_draw_bar(c + Vector2(0, r + 6.0), frac, _hp_color(frac), true)
		# Under real pressure it also flashes, so the eye is pulled to the siege.
		if frac < 0.35:
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 110.0)
			draw_rect(Rect2(c - Vector2(r + 2, r + 2), Vector2((r + 2) * 2, (r + 2) * 2)),
				Color(1.0, 0.45, 0.35, 0.35 + 0.4 * pulse), false, 2.0)


## "This structure is losing health right now." `heat` is 1 at the moment of the
## hit and fades out, so a siege reads as ongoing work rather than a number that
## quietly changed.
func _draw_siege_pulse(c: Vector2, r: float, heat: float) -> void:
	if heat <= 0.0:
		return
	var grow := r + 7.0 * (1.0 - heat)
	draw_arc(c, grow, 0, TAU, 24, Color(1.0, 0.55, 0.25, 0.85 * heat), 2.4, true)
	for i in 4:
		var dir := Vector2.from_angle(TAU * float(i) / 4.0 + 0.4)
		draw_line(c + dir * (grow + 1.0), c + dir * (grow + 5.0),
			Color(1.0, 0.7, 0.4, 0.8 * heat), 2.0, true)


## Minion waves. Drawn under the champions so they read as background pressure:
## which lane is pushed, and by whom, at a glance.
func _draw_minions() -> void:
	var ms := float(Time.get_ticks_msec())
	var dots: Array = frame.get("minions", [])
	for i in dots.size():
		var mn: Dictionary = dots[i]
		var c := _w2s(mn.pos)
		var col: Color = TEAM[mn.team].fill
		draw_circle(c, MINION_R, Color(col.r, col.g, col.b, 0.75))
		if not mn.has("hit"):
			continue
		# This wave is chipping a structure right now, and in this sim the wave is
		# what takes a turret — and then the nexus. Left as walking dots, that read
		# as "the nexus fell on its own" (2026-07-26 designer note). Each minion
		# pokes at the structure on its own beat, so a clump reads as a crew at work.
		var dir := _w2s(mn.hit) - c
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var beat := 0.5 + 0.5 * sin(ms / 70.0 + float(i) * 1.7)
		draw_line(c + dir * MINION_R, c + dir * (MINION_R + 2.0 + 4.0 * beat),
			Color(1.0, 0.72, 0.38, 0.30 + 0.55 * beat), 1.6, true)


func _draw_wards() -> void:
	for wd: Dictionary in frame.get("wards", []):
		var c := _w2s(wd.pos)
		var col: Color = TEAM[wd.team].ring
		col.a = wd.alpha
		draw_arc(c, 4.0, 0, TAU, 12, col, 1.5, true)
		draw_circle(c, 1.5, col)


## One drawn beat per swing the sim fired. Ranged characters send a projectile
## across to the target, melee ones swing an arc at it; either way the last part
## of the beat lands as a spark on the victim, so an exchange reads as blows
## being traded rather than two dots resting next to each other.
func _draw_beats() -> void:
	var r := _champ_r()
	for b: Dictionary in frame.get("beats", []):
		var from := _w2s(b.from)
		var to := _w2s(b.to)
		var col: Color = TEAM[b.team].ring
		var f: float = b.frac
		var gap := to - from
		if gap.length() < 0.001:
			continue
		if b.ranged:
			var head := from.lerp(to, f)
			var tail := from.lerp(to, maxf(f - 0.28, 0.0))
			draw_line(tail, head, Color(col.r, col.g, col.b, 0.5), 1.6, true)
			draw_circle(head, 2.6, Color(col.r, col.g, col.b, 0.95))
		else:
			var ang := gap.angle()
			var centre := from + gap.normalized() * minf(gap.length(), r * 1.6) * 0.6
			var spread: float = 1.15 - 0.7 * f
			draw_arc(centre, r * 0.85, ang - spread, ang + spread, 12,
				Color(1.0, 0.95, 0.85, 0.9 * (1.0 - f)), 2.2, true)
		if f > 0.65:
			var s: float = (f - 0.65) / 0.35
			draw_circle(to, 1.5 + 3.0 * (1.0 - s), Color(1.0, 0.92, 0.72, 0.85 * (1.0 - s)))


## The CC link: victim tied back to whoever locked it, for as long as the lock
## runs. Dashed so it reads as a hold rather than an attack line.
func _draw_tethers() -> void:
	const DASHES := 9
	for th: Dictionary in frame.get("tethers", []):
		var from := _w2s(th.from)
		var to := _w2s(th.to)
		var col: Color = th.color
		col.a = th.alpha
		for i in DASHES:
			if i % 2 == 1:
				continue
			draw_line(from.lerp(to, float(i) / DASHES),
				from.lerp(to, float(i + 1) / DASHES), col, 1.8, true)


## The catch, on the victim. A slow is an icy ring with crystalline spurs (it
## drags you); a hard lock is an amber ring with stars orbiting the head (you are
## not going anywhere). Either way it lasts exactly as long as the sim's CC does.
func _draw_cc_mark(c: Vector2, r: float, stunned: bool) -> void:
	if stunned:
		draw_arc(c, r + 3.0, 0, TAU, 24, Color(1.0, 0.82, 0.30, 0.85), 2.2, true)
		var phase := float(Time.get_ticks_msec()) / 260.0
		for i in 3:
			var a := phase + TAU * float(i) / 3.0
			var orbit := Vector2(cos(a) * (r + 4.0), sin(a) * (r + 4.0) * 0.35)
			draw_circle(c + orbit - Vector2(0, r + 5.0), 2.0, Color(1.0, 0.95, 0.55, 0.95))
		return
	draw_arc(c, r + 3.0, 0, TAU, 24, Color(0.45, 0.85, 1.0, 0.85), 2.0, true)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.25
		var dir := Vector2.from_angle(a)
		draw_line(c + dir * (r + 1.0), c + dir * (r + 5.5),
			Color(0.60, 0.92, 1.0, 0.9), 1.6, true)


func _draw_champions() -> void:
	var textures: Dictionary = geom.get("textures", {})
	var r := _champ_r()
	var champs: Array = frame.get("champs", [])
	# Screen positions up front: the handle labels need to know who is crowded.
	var screen: Array = []
	for ch: Dictionary in champs:
		screen.append(_w2s(ch.pos))
	for i in champs.size():
		var ch: Dictionary = champs[i]
		var base: Vector2 = screen[i]
		var t: Dictionary = TEAM[ch.team]
		if not ch.alive:
			_draw_dead(base, ch, t, i)
			continue
		var c: Vector2 = base + ch.get("shake", Vector2.ZERO)

		# Fight / ult flares (drawn under the disc).
		if ch.get("casting", 0.0) > 0.0:
			var a: float = ch.casting
			draw_arc(c, r + 6 + (1.0 - a) * 16.0, 0, TAU, 24,
				Color(1.0, 0.95, 0.5, a * 0.8), 2.0, true)
		# Trading blows — a swing given or taken in the last second, not merely
		# "an enemy is nearby". Hot red so it never reads as the amber CC mark.
		if ch.get("exchanging", false):
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 90.0)
			draw_arc(c, r + 4, 0, TAU, 20, Color(1.0, 0.42, 0.24, 0.45 + 0.45 * pulse), 2.2, true)
		# Backing off: chevrons trailing behind, pointing the way out. A retreat is
		# a decision the sim makes constantly and the viewer used to draw as a fight.
		if ch.get("backing_off", false):
			_draw_retreat(c, r, ch.get("facing", Vector2.RIGHT), t)
		if ch.get("recalling", false):
			var rp := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 120.0)
			draw_arc(c, r + 8, 0, TAU, 24, Color(0.4, 0.9, 0.9, 0.35 + 0.3 * rp), 2.0, true)

		# Body: real sprite if the character's texture exists, else the placeholder
		# silhouette for its role.
		_draw_body(c, r, ch, t, textures.get(ch.char_id, null))

		# Just hit: a white flash on the body itself. HP bars move a couple of
		# pixels a swing, which is why a real exchange read as "nothing is
		# happening" (2026-07-25 playtest, remark 2).
		var flinch: float = ch.get("flinch", 0.0)
		if flinch > 0.0:
			draw_circle(c, r + 1.5, Color(1.0, 0.95, 0.92, 0.55 * flinch))
		# Caught: the lock/slow mark sits over the body so it can't be missed.
		if ch.get("stunned", false) or ch.get("slowed", false):
			_draw_cc_mark(c, r, ch.get("stunned", false))

		# Level badge (top-right of disc).
		var bp := c + Vector2(r * 0.9, -r * 0.9)
		draw_circle(bp, 6.5, Color(0.08, 0.09, 0.12, 0.9))
		_centered(str(ch.level), bp, 10, Color(0.95, 0.9, 0.7))

		# Health bar + handle. Colour shifts green -> amber -> red as it drops,
		# so a hurt player is readable without reading the bar length.
		var hp_frac: float = ch.get("hp_frac", 1.0)
		_draw_bar(c + Vector2(0, r + 4), hp_frac, _hp_color(hp_frac))
		# Handles in a grouped fight would print on top of each other, so each one
		# in a crowd drops to its own line instead of overlapping.
		_centered(ch.name, c + Vector2(0, r + 16 + 11.0 * _label_slot(screen, i)), 10,
			Color(0.85, 0.87, 0.92))


## Placeholder combat body: one silhouette per role, tinted by team, turned the
## way the player is facing, with the role letter still on it. Five shapes is
## enough that a fight reads as characters rather than dots (2026-07-25 playtest),
## while staying procedural — no art dependency.
##
## The placeholder contract from CLAUDE.md is unchanged: a character's `sprite`
## data field, when it points at a real texture, takes over here with no code
## change, and the same facing/tint applies to it.
func _draw_body(c: Vector2, r: float, ch: Dictionary, t: Dictionary, tex: Texture2D) -> void:
	# World Y is flipped on the way to the screen, so the look vector flips with it.
	var look: Vector2 = ch.get("facing", Vector2.RIGHT)
	var ang := Vector2(look.x, -look.y).angle()
	if tex != null:
		var ts := r * 2.2
		draw_texture_rect(tex, Rect2(c - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false, t.fill)
		draw_arc(c, r + 1.0, 0, TAU, 20, t.ring, 2.0, true)
	else:
		var pts := _role_shape(String(ch.role), c, r, ang)
		draw_colored_polygon(pts, t.fill)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, t.ring, 1.6, true)
		if ch.role == "support":
			# Octagon plus a cross: the helper reads at a glance.
			var f := Vector2.from_angle(ang)
			var s := f.orthogonal()
			draw_line(c - f * r * 0.55, c + f * r * 0.55, t.ring, 1.6, true)
			draw_line(c - s * r * 0.55, c + s * r * 0.55, t.ring, 1.6, true)
	# Facing pip: which way this player is pointed (at its target, or where it walks).
	var nose := Vector2.from_angle(ang)
	draw_line(c + nose * r * 0.7, c + nose * (r + 3.5), t.ring, 2.0, true)
	if ch.role != "support":
		_centered(ROLE_LETTER.get(ch.role, "?"), c, int(clampf(r * 1.25, 9.0, 13.0)),
			Color(1, 1, 1, 0.92))


## Role silhouettes: broad hexagon for the toplaner (it stands in front), an
## arrowhead for the jungler (it arrives), a star for the mid (it casts), a
## pentagon for the carry, an octagon for the support.
func _role_shape(role: String, c: Vector2, r: float, ang: float) -> PackedVector2Array:
	match role:
		"top":
			return _ngon(6, c, r * 1.1, ang)
		"jungle":
			var f := Vector2.from_angle(ang)
			var s := f.orthogonal()
			return PackedVector2Array([
				c + f * r * 1.45, c - f * r * 0.65 + s * r * 1.0,
				c - f * r * 0.2, c - f * r * 0.65 - s * r * 1.0])
		"mid":
			return _star(4, c, r * 1.25, r * 0.52, ang)
		"carry":
			return _ngon(5, c, r * 1.1, ang)
	return _ngon(8, c, r, ang)


func _ngon(sides: int, c: Vector2, radius: float, ang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(c + Vector2.from_angle(ang + TAU * float(i) / float(sides)) * radius)
	return pts


func _star(spikes: int, c: Vector2, outer: float, inner: float, ang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var radius := outer if i % 2 == 0 else inner
		pts.append(c + Vector2.from_angle(ang + TAU * float(i) / float(spikes * 2)) * radius)
	return pts


## How many lines down this champion's handle has to go to clear its neighbours.
func _label_slot(screen: Array, i: int) -> int:
	const CLEARANCE := 42.0
	var slot := 0
	for j in i:
		if screen[j].distance_to(screen[i]) < CLEARANCE:
			slot += 1
	return slot


## The dead sit in the fountain. The sim parks them all on the exact base point,
## so playback fans them around it by row index — five grey discs on one pixel
## tell you nothing about who is down and for how long.
func _draw_dead(base: Vector2, ch: Dictionary, t: Dictionary, row: int) -> void:
	var r := _champ_r()
	var c := base + Vector2.from_angle(TAU * float(row % 5) / 5.0 - PI * 0.5) * (r * 1.9)
	draw_circle(c, r, Color(0.24, 0.25, 0.28))
	draw_arc(c, r, 0, TAU, 20, Color(0.4, 0.4, 0.42), 1.5, true)
	# Skull-ish mark.
	draw_line(c + Vector2(-3, -2), c + Vector2(3, -2), Color(0.6, 0.6, 0.6), 1.5)
	draw_line(c + Vector2(0, -4), c + Vector2(0, 3), Color(0.6, 0.6, 0.6), 1.5)
	_draw_bar(c + Vector2(0, r + 4), ch.get("respawn_frac", 0.0), t.dark)
	_centered(ch.name, c + Vector2(0, r + 14), 9, Color(0.5, 0.52, 0.56))


func _hp_color(frac: float) -> Color:
	if frac > 0.5:
		return Color(0.40, 0.85, 0.45)
	if frac > 0.25:
		return Color(0.95, 0.75, 0.25)
	return Color(0.95, 0.35, 0.30)


## Backing off, drawn as motion: two chevrons behind the body pointing the way it
## is leaving. The sim breaks off fights constantly (hysteresis, on purpose), and
## before this a retreat looked exactly like a fight.
func _draw_retreat(c: Vector2, r: float, look: Vector2, t: Dictionary) -> void:
	var ang := Vector2(look.x, -look.y).angle()
	var back := Vector2.from_angle(ang + PI)
	var side := back.orthogonal()
	var col := Color(t.ring.r, t.ring.g, t.ring.b, 0.55)
	for i in 2:
		var base := c + back * (r + 3.0 + 4.0 * float(i))
		draw_line(base + side * 3.5, base - back * 3.0, col, 1.6, true)
		draw_line(base - side * 3.5, base - back * 3.0, col, 1.6, true)


## Floating damage numbers. The one unambiguous answer to "is the life actually
## moving?" — every number here is a real HP delta the sim produced, read off
## consecutive snapshots (MatchViewer._build_hits).
func _draw_pops() -> void:
	for h: Dictionary in frame.get("pops", []):
		var age: float = h.age
		var c := _w2s(h.pos) - Vector2(0, _champ_r() + 6.0 + 20.0 * age)
		var alpha := clampf(1.0 - age * age, 0.0, 1.0)
		var heal: bool = h.heal
		var col := Color(0.55, 1.0, 0.6, alpha) if heal else Color(1.0, 0.86, 0.45, alpha)
		var txt: String = ("+%d" if heal else "%d") % int(h.amount)
		var fsize := 11 if int(h.amount) < 120 else 14
		# Dark outline: numbers land on top of bodies, minions and lane lines.
		_centered(txt, c + Vector2(1, 1), fsize, Color(0.0, 0.0, 0.0, 0.7 * alpha))
		_centered(txt, c, fsize, col)


## `strong` is for structures: a wider, taller, outlined bar. The player-sized
## one is deliberately small — ten of them share the screen.
func _draw_bar(center: Vector2, frac: float, col: Color, strong := false) -> void:
	var w := 30.0 if strong else 22.0
	var h := 5.5 if strong else 3.5
	var tl := center - Vector2(w * 0.5, h * 0.5)
	draw_rect(Rect2(tl, Vector2(w, h)), Color(0.05, 0.06, 0.08, 0.9), true)
	if frac > 0.0:
		draw_rect(Rect2(tl, Vector2(w * clampf(frac, 0.0, 1.0), h)), col, true)
	if strong:
		draw_rect(Rect2(tl, Vector2(w, h)), Color(0.0, 0.0, 0.0, 0.55), false, 1.0)


## The transient layer: everything with a lifetime. `progress` (0 -> 1) is the
## effect's age, resolved by the viewer; nothing here keeps state of its own.
##
## The ability shapes carry `heavy` when they came from an ultimate — same shape
## family, bigger and louder — so a level-6 ult never reads like a basic ability.
func _draw_effects() -> void:
	for e: Dictionary in frame.get("effects", []):
		var c := _w2s(e.pos)
		var col: Color = e.color
		col.a = e.alpha
		var p: float = e.get("progress", 0.0)
		var heavy: bool = e.get("heavy", false)
		match e.kind:
			"ring":
				draw_arc(c, e.radius, 0, TAU, 28, col, 2.5, true)
			"text":
				var rise: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise), int(e.get("font", 13)), col)
			"banner":
				var rise2: float = e.get("rise", 0.0)
				_centered(e.text, c - Vector2(0, rise2), int(e.get("font", 18)), col)
			"tag":
				_draw_tag(c - Vector2(0, e.get("rise", 0.0) + 12.0), e.text,
					int(e.get("font", 12)), col, e.alpha)
			"shockwave":
				_draw_shockwave(c, float(e.get("world_radius", 6.0)) * _scale(), p, e.color, heavy)
			"beam":
				_draw_beam(c, _w2s(e.get("to", e.pos)), p, e.color, heavy,
					e.get("pierce", false), e.get("finisher", false))
			"bloom":
				var rb := _champ_r() + 4.0 + 12.0 * p
				draw_circle(c, rb * 0.92, Color(col.r, col.g, col.b, 0.16 * (1.0 - p)))
				draw_arc(c, rb, 0, TAU, 28, Color(col.r, col.g, col.b, 0.9 * (1.0 - p)),
					3.0 if heavy else 2.0, true)
			"cast_flash":
				# The caster flares white-hot for an instant, so an ultimate is visible
				# even when its impact lands on someone else across the fight.
				var cf := 1.0 - p
				draw_circle(c, (_champ_r() + 3.0) * (1.0 + 1.6 * p),
					Color(1.0, 1.0, 1.0, 0.30 * cf))
				draw_arc(c, (_champ_r() + 5.0) * (1.0 + 2.2 * p), 0, TAU, 28,
					Color(col.r, col.g, col.b, 0.9 * cf), 3.0 * cf + 1.0, true)
			"aura":
				var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 70.0)
				var ra := _champ_r() + 4.0 + 2.5 * pulse
				draw_arc(c, ra, 0, TAU, 24, Color(col.r, col.g, col.b, 0.75 * (1.0 - p)), 2.5, true)
				for i in 8:
					var ang := TAU * float(i) / 8.0 + pulse
					var dir := Vector2.from_angle(ang)
					draw_line(c + dir * ra, c + dir * (ra + 4.0),
						Color(col.r, col.g, col.b, 0.7 * (1.0 - p)), 1.6, true)


## An ability's area, at its real radius: a flash disc, a ring racing out to the
## edge of the effect, and — for an ultimate — the spikes that give it its punch.
func _draw_shockwave(c: Vector2, full_r: float, p: float, col: Color, heavy: bool) -> void:
	var grown := full_r * (0.28 + 0.72 * (1.0 - pow(1.0 - p, 3.0)))
	draw_circle(c, grown, Color(col.r, col.g, col.b, (0.28 if heavy else 0.14) * (1.0 - p)))
	draw_arc(c, grown, 0, TAU, 40, Color(col.r, col.g, col.b, 1.0 - p),
		(4.0 if heavy else 2.0) * (1.0 - 0.5 * p), true)
	if not heavy or p > 0.45:
		return
	var fade := 1.0 - p / 0.45
	for i in 8:
		var dir := Vector2.from_angle(TAU * float(i) / 8.0 + 0.2)
		draw_line(c + dir * grown * 0.55, c + dir * grown * 1.15,
			Color(1.0, 1.0, 1.0, 0.5 * fade), 2.0, true)


## A single-target ability: the line goes out, then bursts on the victim. A snipe
## carries through past its target; an execute stamps a cross where it finished.
func _draw_beam(from: Vector2, to: Vector2, p: float, col: Color, heavy: bool,
		pierce: bool, finisher: bool) -> void:
	var gap := to - from
	if gap.length() < 0.001:
		return
	var head := from.lerp(to, minf(p / 0.3, 1.0))
	var width: float = maxf((5.0 if heavy else 2.5) * (1.0 - 0.6 * p), 1.2)
	draw_line(from, head, Color(col.r, col.g, col.b, 0.95 * (1.0 - 0.7 * p)), width, true)
	if pierce and p >= 0.3:
		var beyond := gap.normalized() * 22.0 * (1.0 - p)
		draw_line(to, to + beyond, Color(col.r, col.g, col.b, 0.6 * (1.0 - p)), width * 0.7, true)
	if p < 0.3:
		return
	var burst := (p - 0.3) / 0.7
	draw_circle(to, 2.0 + (width + 6.0) * (1.0 - burst),
		Color(col.r, col.g, col.b, 0.8 * (1.0 - burst)))
	if finisher:
		var arm := (_champ_r() + 5.0) * (1.0 - burst * 0.4)
		var fc := Color(1.0, 0.9, 0.9, 0.9 * (1.0 - burst))
		draw_line(to + Vector2(-arm, -arm), to + Vector2(arm, arm), fc, 2.4, true)
		draw_line(to + Vector2(-arm, arm), to + Vector2(arm, -arm), fc, 2.4, true)


## Text on a dark pill. A bare string disappears over minions and rings; this
## keeps an ability name (or a CC tag) readable in the middle of a fight.
func _draw_tag(centre: Vector2, text: String, font_size: int, col: Color, alpha: float) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(5.0, 3.0)
	var rect := Rect2(centre - sz * 0.5 - pad, sz + pad * 2.0)
	draw_rect(rect, Color(0.04, 0.05, 0.08, 0.75 * alpha), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.85 * alpha), false, 1.0)
	_centered(text, centre, font_size, Color(col.r, col.g, col.b, alpha))


func _centered(text: String, center: Vector2, font_size: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := center - sz * 0.5 + Vector2(0, sz.y * 0.5 - _font.get_descent(font_size) * 0.3)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _enemy(team: String) -> String:
	return "red" if team == "blue" else "blue"
