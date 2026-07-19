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

const CHARACTERS_PER_ROLE := 3
const TEAM_COUNT := 2

# Sanity ranges: catches typos (6200 hp), not balance opinions.
const STAT_RANGES := {
	"base/hp": [400, 800], "base/damage": [30, 90],
	"base/armor": [15, 50], "base/speed": [300, 400],
	"growth/hp": [50, 130], "growth/damage": [1, 6], "growth/armor": [1, 6],
	"ultimate/cooldown": [30, 300],
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

	_validate_characters(characters, errors)
	_validate_players(players, characters, errors)
	_validate_teams(teams, players, errors)
	_validate_comp_rules(comp_rules, errors)

	return {
		"characters": characters, "players": players, "teams": teams,
		"comp_rules": comp_rules, "errors": errors,
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
		for field in ["name", "role", "sprite", "curve", "base", "growth", "ultimate", "tags"]:
			if not c.has(field):
				errors.append("%s: missing field \"%s\"" % [where, field])
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


# --- helpers -----------------------------------------------------------------

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
