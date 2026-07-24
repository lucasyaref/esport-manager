extends SceneTree
## Validates all game data; with --report also prints the M1 stat-spread report
## (markdown). Exits 0 when data is valid, 1 otherwise.
##
## Usage:
##   godot --headless --path . --script res://tools/data_check.gd [-- --report]


func _initialize() -> void:
	var data := DataLoader.load_all()
	var errors: Array[String] = data.errors
	if not errors.is_empty():
		for e in errors:
			print("DATA ERROR: %s" % e)
		print("DATA VALIDATION: FAIL (%d errors)" % errors.size())
		quit(1)
		return
	print("DATA VALIDATION: OK (%d characters, %d players, %d teams)" % [
		data.characters.size(), data.players.size(), data.teams.size(),
	])
	if "--report" in OS.get_cmdline_user_args():
		_print_report(data)
	quit(0)


func _print_report(data: Dictionary) -> void:
	print("\n## Characters by role (level 1 → level %d)\n" % DataLoader.MAX_LEVEL)
	for role in DataLoader.ROLES:
		print("**%s**\n" % role.capitalize())
		print("| Character | Curve | Tags | HP | Damage | Armor | Speed | Basic | Ultimate |")
		print("|---|---|---|---|---|---|---|---|---|")
		for c: Dictionary in _characters_of_role(data, role):
			print("| %s | %s | %s | %d → %d | %d → %d | %d → %d | %d | %s | %s (%s) |" % [
				c.name, c.curve, ", ".join(c.tags),
				_lvl(c, "hp", 1), _lvl(c, "hp", DataLoader.MAX_LEVEL),
				_lvl(c, "damage", 1), _lvl(c, "damage", DataLoader.MAX_LEVEL),
				_lvl(c, "armor", 1), _lvl(c, "armor", DataLoader.MAX_LEVEL),
				int(c.base.speed), _basic_desc(c.basic_ability), c.ultimate.name, c.ultimate.effect,
			])
		print("")

	print("## Role stat spreads (min / avg / max)\n")
	for stat in ["hp", "damage", "armor"]:
		print("**%s at level %d**\n" % [stat.capitalize(), DataLoader.MAX_LEVEL])
		print("| Role | Min | Avg | Max |")
		print("|---|---|---|---|")
		for role in DataLoader.ROLES:
			var values: Array[float] = []
			for c: Dictionary in _characters_of_role(data, role):
				values.append(DataLoader.stat_at_level(c, stat, DataLoader.MAX_LEVEL))
			print("| %s | %d | %d | %d |" % [role, _amin(values), _avg(values), _amax(values)])
		print("")

	print("## Players\n")
	for team_id: String in data.teams:
		var team: Dictionary = data.teams[team_id]
		print("**%s (%s)** — %s\n" % [team.name, team.tag, team.identity])
		print("| Player | Role | Mechanics | Macro | Laning | Compliance | Pool |")
		print("|---|---|---|---|---|---|---|")
		var totals := {"mechanics": 0.0, "macro": 0.0, "laning": 0.0, "coach_compliance": 0.0}
		for role in DataLoader.ROLES:
			var p: Dictionary = data.players[team.roster[role]]
			var a: Dictionary = p.attributes
			for k: String in totals:
				totals[k] += a[k]
			var pool_bits := []
			for char_id: String in p.champion_pool:
				pool_bits.append("%s %d" % [data.characters[char_id].name, int(p.champion_pool[char_id])])
			print("| %s | %s | %d | %d | %d | %d | %s |" % [
				p.handle, role, a.mechanics, a.macro, a.laning, a.coach_compliance,
				", ".join(pool_bits),
			])
		print("| *team avg* | | *%.0f* | *%.0f* | *%.0f* | *%.0f* | |" % [
			totals.mechanics / 5, totals.macro / 5, totals.laning / 5,
			totals.coach_compliance / 5,
		])
		print("")


func _characters_of_role(data: Dictionary, role: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in data.characters:
		if data.characters[id].role == role:
			out.append(data.characters[id])
	return out


func _lvl(c: Dictionary, stat: String, level: int) -> int:
	return int(DataLoader.stat_at_level(c, stat, level))


## One-line summary of the basic-ability slot (§3 three-action model).
func _basic_desc(slot: Dictionary) -> String:
	var effect: String = slot.effect
	if effect in DataLoader.PASSIVE_EFFECTS:
		return "%s (%s +%d%%)" % [slot.name, effect.trim_prefix("passive_"),
			int(round(float(slot.params.pct) * 100.0))]
	if effect in ["single_cc", "aoe_cc"]:
		return "%s (%s %ss, u%d)" % [slot.name, slot.params.cc, slot.params.duration, int(slot.unlock)]
	return "%s (%s, u%d)" % [slot.name, effect, int(slot.unlock)]


func _amin(values: Array[float]) -> float:
	return values.reduce(func(a: float, b: float) -> float: return minf(a, b))


func _amax(values: Array[float]) -> float:
	return values.reduce(func(a: float, b: float) -> float: return maxf(a, b))


func _avg(values: Array[float]) -> float:
	return values.reduce(func(a: float, b: float) -> float: return a + b) / values.size()
