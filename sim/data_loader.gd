class_name DataLoader
extends RefCounted
## Loads and validates all game data (characters, players, teams, comp rules).
## Pure GDScript — usable headless and from the game. All balance/content
## lives in data/*.json; the sim never hardcodes content.

const ROLES: Array[String] = ["top", "jungle", "mid", "carry", "support"]
const TAGS: Array[String] = ["engage", "poke", "scaling", "early", "protect"]
const CURVES: Array[String] = ["early", "balanced", "late"]
const ULT_EFFECTS: Array[String] = [
	"aoe_cc", "single_cc", "aoe_damage", "single_burst", "snipe", "team_shield",
	"team_heal", "self_steroid", "global_teleport", "zone_denial", "execute",
]
## Basic-ability passives: persistent combat modifiers, never fired (M5-C).
## Each carries a params.pct. See PlayerAgent._init_passive / Combat.
const PASSIVE_EFFECTS: Array[String] = [
	"passive_power", "passive_bulwark", "passive_sustain",
]
## The three-action model (§3): a basic ability is an active spell (a subset of
## the ultimate effects, minus global_teleport which is a rotation tool) OR a
## passive. Both slots share this data shape; the ultimate slot uses ULT_EFFECTS.
const BASIC_EFFECTS: Array[String] = [
	"single_cc", "aoe_cc", "single_burst", "snipe", "aoe_damage", "self_steroid",
	"team_shield", "team_heal", "zone_denial", "execute",
	"passive_power", "passive_bulwark", "passive_sustain",
]
const CC_KINDS: Array[String] = ["slow", "stun", "root", "knockup", "fear"]

## Where a character wants to stand in a fight. Drives target selection and
## the steering forces in the combat engine.
const FIGHT_ROLES: Array[String] = ["frontline", "backline", "flank", "peel"]

const CHARACTERS_PER_ROLE := 3
const TEAM_COUNT := 2

# Sanity ranges: catches typos (6200 hp), not balance opinions.
# Combat ranges are in map units — the map is 100x100 and 1 unit ≈ 125 LoL
# units (from PlayerAgent.SPEED_SCALE), so melee ≈ 1.2 and artillery ≈ 5.
const STAT_RANGES := {
	"base/hp": [400, 800], "base/damage": [30, 90],
	"base/armor": [15, 50], "base/speed": [300, 400],
	"growth/hp": [50, 130], "growth/damage": [1, 6], "growth/armor": [1, 6],
	"ultimate/cooldown": [30, 300],
	"combat/attack_range": [1.0, 6.0], "combat/preferred_range": [1.0, 6.0],
	"combat/attack_speed": [0.5, 1.2],
}
const MAX_LEVEL := 18


## Loads everything. Returns:
## { "characters": {id: dict}, "players": {id: dict}, "teams": {id: dict},
##   "comp_rules": dict, "errors": Array[String] }
## Data is only trustworthy when errors is empty.
static func load_all(base_dir := "res://data") -> Dictionary:
	var errors: Array[String] = []
	var characters := _index_by_id(
		_parse_file(base_dir + "/characters.json", "characters", errors), "characters", errors)
	var players := _index_by_id(
		_parse_file(base_dir + "/players.json", "players", errors), "players", errors)
	var teams := _index_by_id(
		_parse_file(base_dir + "/teams.json", "teams", errors), "teams", errors)
	var comp_rules := _parse_raw(base_dir + "/comp_rules.json", errors)
	var map := _parse_raw(base_dir + "/map.json", errors)
	var balance := _parse_raw(base_dir + "/balance.json", errors)

	_validate_characters(characters, errors)
	_validate_players(players, characters, errors)
	_validate_teams(teams, players, errors)
	_validate_comp_rules(comp_rules, errors)
	_validate_map(map, errors)
	_validate_balance(balance, errors)

	# Terrain (M6-T2) needs a clean map to validate against and a SimMap to
	# read lane/camp/pit geometry from when it builds the navigation, so it
	# only loads once everything above is already sound.
	var terrain: Terrain = null
	var nav: NavGrid = null
	if errors.is_empty():
		terrain = Terrain.load_from(base_dir + "/terrain.txt", float(map.get("size", 100.0)), errors)
		if errors.is_empty():
			var geom := SimMap.new(map)
			errors.append_array(terrain.validate(geom))
			if errors.is_empty():
				nav = geom.build_nav(terrain)

	return {
		"characters": characters, "players": players, "teams": teams,
		"comp_rules": comp_rules, "map": map, "balance": balance,
		"terrain": terrain, "nav": nav, "errors": errors,
	}


## Stat value at a level (1..MAX_LEVEL), linear growth.
static func stat_at_level(character: Dictionary, stat: String, level: int) -> float:
	var value := float(character.base[stat])
	if character.growth.has(stat):
		value += float(character.growth[stat]) * (level - 1)
	return value


# --- parsing -----------------------------------------------------------------

static func _parse_raw(path: String, errors: Array[String]) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: missing or empty file" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		errors.append("%s: invalid JSON" % path)
		return {}
	return parsed


static func _parse_file(path: String, list_key: String, errors: Array[String]) -> Array:
	var parsed := _parse_raw(path, errors)
	if parsed.is_empty():
		return []
	if not parsed.get(list_key) is Array:
		errors.append("%s: expected top-level \"%s\" array" % [path, list_key])
		return []
	return parsed[list_key]


static func _index_by_id(list: Array, what: String, errors: Array[String]) -> Dictionary:
	var by_id := {}
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty():
			errors.append("%s: entry without a valid \"id\": %s" % [what, str(entry).left(80)])
			continue
		if by_id.has(entry.id):
			errors.append("%s: duplicate id \"%s\"" % [what, entry.id])
			continue
		by_id[entry.id] = entry
	return by_id


# --- validation --------------------------------------------------------------

static func _validate_characters(characters: Dictionary, errors: Array[String]) -> void:
	var role_counts := {}
	for id: String in characters:
		var c: Dictionary = characters[id]
		var where := "characters/%s" % id
		for field in ["name", "role", "sprite", "curve", "base", "growth", "combat",
				"basic_ability", "ultimate", "tags"]:
			if not c.has(field):
				errors.append("%s: missing field \"%s\"" % [where, field])
		var fight_role: Variant = c.get("combat", {}).get("fight_role")
		if not fight_role in FIGHT_ROLES:
			errors.append("%s: unknown combat.fight_role \"%s\"" % [where, str(fight_role)])
		var pref: Variant = c.get("combat", {}).get("preferred_range")
		var reach: Variant = c.get("combat", {}).get("attack_range")
		if _is_number(pref) and _is_number(reach) and pref > reach:
			errors.append("%s: combat.preferred_range (%s) exceeds attack_range (%s)" % [
				where, str(pref), str(reach)])
		if not c.get("role", "") in ROLES:
			errors.append("%s: unknown role \"%s\"" % [where, c.get("role")])
		else:
			role_counts[c.role] = role_counts.get(c.role, 0) + 1
		if not c.get("curve", "") in CURVES:
			errors.append("%s: unknown curve \"%s\"" % [where, c.get("curve")])
		for key: String in STAT_RANGES:
			_check_range(c, key, where, errors)
		var ult: Dictionary = c.get("ultimate", {})
		if not ult.get("effect", "") in ULT_EFFECTS:
			errors.append("%s: unknown ultimate effect \"%s\"" % [where, ult.get("effect")])
		if not ult.get("name") is String or not ult.get("params") is Dictionary:
			errors.append("%s: ultimate needs \"name\" and \"params\"" % where)
		_validate_basic_ability(c.get("basic_ability", {}), where, errors)
		var tags: Array = c.get("tags", [])
		if tags.is_empty():
			errors.append("%s: needs at least one tag" % where)
		for tag in tags:
			if not tag in TAGS:
				errors.append("%s: unknown tag \"%s\"" % [where, tag])
	for role in ROLES:
		if role_counts.get(role, 0) != CHARACTERS_PER_ROLE:
			errors.append("characters: role \"%s\" has %d characters, expected %d" % [
				role, role_counts.get(role, 0), CHARACTERS_PER_ROLE])


static func _validate_players(players: Dictionary, characters: Dictionary, errors: Array[String]) -> void:
	for id: String in players:
		var p: Dictionary = players[id]
		var where := "players/%s" % id
		if not p.get("handle") is String or p.get("handle", "").is_empty():
			errors.append("%s: missing handle" % where)
		if not p.get("role", "") in ROLES:
			errors.append("%s: unknown role \"%s\"" % [where, p.get("role")])
		var attrs: Dictionary = p.get("attributes", {})
		for attr in ["mechanics", "macro", "laning", "coach_compliance"]:
			if not _is_number(attrs.get(attr)) or attrs[attr] < 0 or attrs[attr] > 100:
				errors.append("%s: attribute \"%s\" must be a number 0-100" % [where, attr])
		var pool: Dictionary = p.get("champion_pool", {})
		if pool.is_empty():
			errors.append("%s: empty champion_pool" % where)
		var playable := false
		for char_id: String in pool:
			var prof: Variant = pool[char_id]
			if not characters.has(char_id):
				errors.append("%s: pool references unknown character \"%s\"" % [where, char_id])
			elif characters[char_id].get("role") != p.get("role"):
				errors.append("%s: pool character \"%s\" is not a %s" % [where, char_id, p.get("role")])
			if not _is_int(prof) or prof < 0 or prof > 3:
				errors.append("%s: proficiency for \"%s\" must be an integer 0-3" % [where, char_id])
			elif prof >= 1:
				playable = true
		if not pool.is_empty() and not playable:
			errors.append("%s: no playable character (all proficiencies 0)" % where)
	if players.size() != TEAM_COUNT * ROLES.size():
		errors.append("players: expected %d players, found %d" % [TEAM_COUNT * ROLES.size(), players.size()])


static func _validate_teams(teams: Dictionary, players: Dictionary, errors: Array[String]) -> void:
	var used_players := {}
	for id: String in teams:
		var t: Dictionary = teams[id]
		var where := "teams/%s" % id
		for field in ["name", "tag", "color", "roster"]:
			if not t.has(field):
				errors.append("%s: missing field \"%s\"" % [where, field])
		if not Color.html_is_valid(t.get("color", "")):
			errors.append("%s: invalid color \"%s\" (expected #rrggbb)" % [where, t.get("color")])
		var roster: Dictionary = t.get("roster", {})
		for role in ROLES:
			var pid: Variant = roster.get(role)
			if not pid is String or not players.has(pid):
				errors.append("%s: roster.%s references unknown player \"%s\"" % [where, role, str(pid)])
				continue
			if players[pid].get("role") != role:
				errors.append("%s: player \"%s\" is a %s, listed as %s" % [
					where, pid, players[pid].get("role"), role])
			if used_players.has(pid):
				errors.append("%s: player \"%s\" already on team \"%s\"" % [where, pid, used_players[pid]])
			used_players[pid] = id
	if teams.size() != TEAM_COUNT:
		errors.append("teams: expected %d teams, found %d" % [TEAM_COUNT, teams.size()])


static func _validate_comp_rules(rules: Dictionary, errors: Array[String]) -> void:
	var phases: Dictionary = rules.get("phases", {})
	if not _is_number(phases.get("mid_start_min")) or not _is_number(phases.get("late_start_min")) \
			or phases.mid_start_min >= phases.late_start_min:
		errors.append("comp_rules/phases: needs mid_start_min < late_start_min")
	var curves: Dictionary = rules.get("curves", {})
	for curve in CURVES:
		var mult: Dictionary = curves.get(curve, {})
		for phase in ["early", "mid", "late"]:
			if not _is_number(mult.get(phase)) or mult[phase] <= 0:
				errors.append("comp_rules/curves/%s: missing positive \"%s\" multiplier" % [curve, phase])
	for entry: Dictionary in rules.get("synergies", []):
		var tags: Array = entry.get("tags", [])
		if tags.size() != 2 or not (tags[0] in TAGS and tags[1] in TAGS):
			errors.append("comp_rules/synergies: invalid tag pair %s" % str(tags))
		_check_bonus(entry, "synergies", errors)
	for entry: Dictionary in rules.get("counters", []):
		if not (entry.get("strong", "") in TAGS and entry.get("weak", "") in TAGS):
			errors.append("comp_rules/counters: invalid tags in %s" % str(entry).left(80))
		_check_bonus(entry, "counters", errors)


static func _validate_map(map: Dictionary, errors: Array[String]) -> void:
	for base in ["blue", "red"]:
		if not _is_point(map.get("bases", {}).get(base)):
			errors.append("map/bases: missing [x, y] for \"%s\"" % base)
	var lanes: Dictionary = map.get("lanes", {})
	for lane in ["top", "mid", "bot"]:
		var path: Array = lanes.get(lane, {}).get("path", [])
		if path.size() < 2:
			errors.append("map/lanes/%s: path needs at least 2 points" % lane)
		for pt in path:
			if not _is_point(pt):
				errors.append("map/lanes/%s: bad point %s" % [lane, str(pt)])
	# Tower tiers are whatever map.json says they are — the count per lane is a
	# design lever (it went 3 -> 2 on 2026-08-09), so nothing here hardcodes a list.
	# What is *not* optional is that both sides get the same tiers in mirrored
	# places: blue-side win rate is a tracked balance metric, so an uneven tower
	# layout would poison it exactly the way an asymmetric terrain grid would. Same
	# rule as the terrain gate, applied to the structures.
	var blue_towers: Dictionary = map.get("towers", {}).get("blue", {})
	var red_towers: Dictionary = map.get("towers", {}).get("red", {})
	for team in ["blue", "red"]:
		var towers: Dictionary = map.get("towers", {}).get(team, {})
		if towers.is_empty():
			errors.append("map/towers/%s: needs at least one tier" % team)
		if not towers.has("outer"):
			# `outer` is named in the sim: SimMap clamps the lane front to it, and
			# Objectives.outer_down cues the bot-lane rotation off it.
			errors.append("map/towers/%s: needs an \"outer\" tier" % team)
		for tier: String in towers:
			var t: Variant = towers[tier]
			if not _is_number(t) or t <= 0.0 or t >= 1.0:
				errors.append("map/towers/%s/%s: needs lane param in (0, 1)" % [team, tier])
	for tier: String in blue_towers:
		if not red_towers.has(tier):
			errors.append("map/towers: \"%s\" exists for blue but not red" % tier)
		elif _is_number(blue_towers[tier]) and _is_number(red_towers[tier]):
			# Mirrored about the lane midpoint: blue at t sits where red sits at 1 - t.
			var mirror: float = float(blue_towers[tier]) + float(red_towers[tier])
			if absf(mirror - 1.0) > 0.001:
				errors.append("map/towers/%s: blue %s + red %s = %s, must sum to 1.0 (mirrored)"
					% [tier, blue_towers[tier], red_towers[tier], mirror])
	for tier: String in red_towers:
		if not blue_towers.has(tier):
			errors.append("map/towers: \"%s\" exists for red but not blue" % tier)
	for pit in ["dragon", "baron"]:
		if not _is_point(map.get("pits", {}).get(pit)):
			errors.append("map/pits: missing [x, y] for \"%s\"" % pit)
	var camp_ids := {}
	var side_counts := {"blue": 0, "red": 0}
	for camp: Dictionary in map.get("camps", []):
		var id: String = camp.get("id", "?")
		if camp_ids.has(id):
			errors.append("map/camps: duplicate id \"%s\"" % id)
		camp_ids[id] = true
		if not camp.get("side", "") in ["blue", "red"]:
			errors.append("map/camps/%s: side must be blue or red" % id)
		else:
			side_counts[camp.side] += 1
		if not _is_point(camp.get("pos")):
			errors.append("map/camps/%s: bad pos" % id)
		for field in ["gold", "xp", "clear_s"]:
			if not _is_number(camp.get(field)) or camp.get(field, 0) <= 0:
				errors.append("map/camps/%s: \"%s\" must be a positive number" % [id, field])
	if side_counts.blue == 0 or side_counts.blue != side_counts.red:
		errors.append("map/camps: blue and red need the same non-zero camp count (got %d/%d)" % [
			side_counts.blue, side_counts.red])


static func _validate_balance(balance: Dictionary, errors: Array[String]) -> void:
	# Every listed key must exist as a positive number; formulas read them blind.
	var required := {
		"minions": ["first_wave_s", "wave_interval_s", "melee_per_wave", "caster_per_wave",
			"cannon_every_n_waves", "gold_melee", "gold_caster", "gold_cannon",
			"xp_per_minion", "speed", "combat_kill_rate", "presence_pressure",
			"presence_radius", "tower_kill_rate", "defend_pressure_mult"],
		"economy": ["starting_gold", "passive_gold_per_s", "support_income_per_s",
			"buy_threshold_base", "buy_threshold_per_level", "recall_channel_s"],
		"xp": ["level_up_base", "level_up_step", "duo_share"],
		"health": ["regen_pct_per_s", "base_regen_pct_per_s", "recall_hp_threshold",
			"regen_lockout_s"],
		"laning": ["poke_interval_s", "poke_base", "poke_damage_norm", "poke_laning_div",
			"poke_variance", "poke_floor_hp", "poke_level_ramp_start", "allin_enemy_hp",
			"allin_self_hp", "allin_lead", "allin_overext", "allin_min_level", "trade_lead", "trade_offset",
			"allin_offset", "back_offset", "push_pressure_mult", "back_pressure_mult"],
		"cs": ["base_chance", "laning_divisor", "support_assist_bonus", "max_chance"],
		"jungle": ["camp_first_spawn_s", "camp_respawn_s", "clear_jitter_s"],
		"combat": ["kill_gold", "assist_gold_total", "shutdown_per_streak", "shutdown_max",
			"min_kill_worth", "kill_xp_base", "kill_xp_per_victim_level",
			"power_item_divisor", "mechanics_power_base", "mechanics_power_divisor", "ehp_norm",
			"respawn_base_s", "respawn_per_level_s"],
		"fight": ["awareness_radius", "danger_radius", "damage_scale", "damage_variance",
			"threat_norm", "max_reach", "melee_damage_bonus", "engage_speed_bonus",
			"contest_margin", "contest_macro_divisor", "commit_margin", "lane_commit_margin", "disengage_hp",
			"lane_disengage_hp", "hold_when_winning_edge", "disengage_lock_s",
			"reach_falloff", "stand_inset", "low_hp_focus",
			"flank_backline_bias",
			"peel_target_bias", "backline_kite", "frontline_screen", "frontline_screen_lerp",
			"peel_standoff", "retreat_home_bias", "retreat_step", "assist_window_s",
			"fight_group_radius", "fight_end_grace_s", "pit_context_radius",
			"ult_default_radius", "ult_aoe_min_targets", "ult_execute_hp", "ult_heal_ally_hp",
			"ult_damage_scale", "basic_damage_scale", "ult_single_mult", "ult_execute_mult",
			"ult_cc_damage_mult",
			"ult_heal_mult", "stun_duration_s", "cc_catch_range", "steroid_duration_s",
			"steroid_damage_mult",
			"chase_patience_s", "leash_radius", "dive_hp", "dive_target_hp", "dive_margin", "focus_penalty",
			"no_vision_caution", "vision_radius", "brush_reveal_radius", "squishy_bias", "squishy_ehp_ref"],
		"ganks": ["check_interval_s", "min_interval_s", "base_chance_early_tag",
			"base_chance_other", "overextend_weight", "commit_timeout_s", "react_macro_norm",
			"connect_low_hp", "connect_overext", "bot_focus_weight",
				"answer_interval_s", "answer_min_interval_s", "answer_min_hp", "answer_ally_hp",
				"answer_radius", "answer_base", "answer_lift", "answer_react_bonus"],
		"defense": ["deep_threat_bound", "defend_men", "punish_deep", "punish_isolation_radius",
			"punish_collapse_radius", "punish_min_collapsers", "punish_base", "punish_lift",
			"play_interval_s", "play_window_s", "play_radius", "play_min_men", "play_max_men",
			"play_join_base", "play_join_lift"],
		"wards": ["support_ward_interval_s", "ward_duration_s"],
		"towers": ["hp", "minion_dps", "plating_until_s", "plating_reduction", "player_base_dps", "gold_per_player", "nexus_hp",
			"range", "player_dps", "aggro_window_s", "credit_radius"],
		"objectives": ["dragon_first_spawn_s", "dragon_respawn_s", "dragon_gold_per_player",
			"dragon_buff_per_stack", "baron_first_spawn_s", "baron_respawn_s",
			"baron_gold_per_player", "baron_buff_power", "baron_siege_mult",
			"baron_duration_s", "decision_interval_s", "take_channel_s",
			"dragon_xp_per_player", "baron_xp_per_player",
			"dragon_soul_stacks", "dragon_soul_power"],
	}
	for section: String in required:
		var sec: Dictionary = balance.get(section, {})
		for key: String in required[section]:
			if not _is_number(sec.get(key)) or sec.get(key, -1) < 0:
				errors.append("balance/%s: \"%s\" must be a non-negative number" % [section, key])
	var ult_impact: Dictionary = balance.get("combat", {}).get("ult_impact", {})
	for effect in ULT_EFFECTS:
		if not _is_number(ult_impact.get(effect)):
			errors.append("balance/combat/ult_impact: missing coefficient for \"%s\"" % effect)
	# basic_impact only needs coefficients for the active basic effects actually
	# authored (single_cc today); it grows as active basics are added.
	var basic_impact: Dictionary = balance.get("combat", {}).get("basic_impact", {})
	if not _is_number(basic_impact.get("single_cc")):
		errors.append("balance/combat/basic_impact: missing coefficient for \"single_cc\"")


# --- helpers -----------------------------------------------------------------


static func _is_point(v: Variant) -> bool:
	return v is Array and v.size() == 2 and _is_number(v[0]) and _is_number(v[1])

static func _is_number(v: Variant) -> bool:
	return v is float or v is int


static func _is_int(v: Variant) -> bool:
	return _is_number(v) and is_equal_approx(float(v), roundf(float(v)))


static func _check_range(c: Dictionary, slash_path: String, where: String, errors: Array[String]) -> void:
	var parts := slash_path.split("/")
	var value: Variant = c.get(parts[0], {}).get(parts[1])
	var lo: float = STAT_RANGES[slash_path][0]
	var hi: float = STAT_RANGES[slash_path][1]
	if not _is_number(value) or value < lo or value > hi:
		errors.append("%s: %s = %s outside sane range [%s, %s]" % [
			where, slash_path, str(value), lo, hi])


static func _check_bonus(entry: Dictionary, what: String, errors: Array[String]) -> void:
	var bonus: Variant = entry.get("bonus")
	if not _is_number(bonus) or bonus < 0 or bonus > 0.5:
		errors.append("comp_rules/%s: bonus must be 0..0.5, got %s" % [what, str(bonus)])


## The basic-ability slot (§3 three-action model). Same shape as the ultimate —
## effect + params + cooldown + unlock — but its effect may be a persistent
## passive (no activation) or an active spell that fires like a mini-ultimate.
static func _validate_basic_ability(slot: Dictionary, where: String, errors: Array[String]) -> void:
	if slot.is_empty():
		return  # the missing-field check above already reported it
	var effect: String = str(slot.get("effect", ""))
	if not effect in BASIC_EFFECTS:
		errors.append("%s: unknown basic_ability effect \"%s\"" % [where, effect])
		return
	if not slot.get("name") is String or not slot.get("params") is Dictionary:
		errors.append("%s: basic_ability needs \"name\" and \"params\"" % where)
		return
	var unlock: Variant = slot.get("unlock")
	if not _is_int(unlock) or unlock < 1 or unlock > MAX_LEVEL:
		errors.append("%s: basic_ability.unlock must be an integer 1..%d" % [where, MAX_LEVEL])
	var params: Dictionary = slot.params
	if effect in PASSIVE_EFFECTS:
		# A passive is a persistent modifier: it needs a strength, not a cooldown.
		var pct: Variant = params.get("pct")
		if not _is_number(pct) or pct <= 0.0 or pct > 0.5:
			errors.append("%s: basic_ability passive needs params.pct in (0, 0.5]" % where)
	else:
		# An active fires on a cooldown like the ultimate.
		var cd: Variant = slot.get("cooldown")
		if not _is_number(cd) or cd <= 0.0 or cd > 300.0:
			errors.append("%s: basic_ability active needs cooldown in (0, 300]" % where)
		if effect in ["single_cc", "aoe_cc"]:
			if not params.get("cc", "") in CC_KINDS:
				errors.append("%s: basic_ability cc must be one of %s" % [where, str(CC_KINDS)])
			elif params.cc == "slow":
				var sm: Variant = params.get("slow_mult")
				if not _is_number(sm) or sm <= 0.0 or sm >= 1.0:
					errors.append("%s: slow basic_ability needs params.slow_mult in (0, 1)" % where)
				if not _is_number(params.get("duration")) or params.get("duration", 0) <= 0.0:
					errors.append("%s: slow basic_ability needs positive params.duration" % where)
