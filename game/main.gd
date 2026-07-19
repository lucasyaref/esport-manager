extends Control
## M2 placeholder main scene: validates data, runs the sim determinism
## self-test, and shows the scoreboard of a full simulated match so the
## economy is visible in-game. Replaced by the real match viewer in M4.

const SELF_TEST_SEED := 42
const SELF_TEST_MINUTES := 30


func _ready() -> void:
	var output := _build_ui()
	var data := DataLoader.load_all()
	if not data.errors.is_empty():
		var lines := ["[b]Game data[/b]: [color=red][b]%d ERRORS[/b][/color]" % data.errors.size()]
		for e in data.errors.slice(0, 10):
			lines.append("[color=red]  %s[/color]" % e)
		output.text = "\n".join(lines)
		return
	output.text = _run_self_test(data)


func _run_self_test(data: Dictionary) -> String:
	var setup := {
		"seed": SELF_TEST_SEED,
		"duration_ticks": SELF_TEST_MINUTES * 60 * SimMatch.TICKS_PER_SECOND,
		"snapshot_every": 10,
	}
	var a := SimMatch.new(setup, data).run()
	var b := SimMatch.new(setup, data).run()
	var ok: bool = a.checksum == b.checksum

	var lines := []
	lines.append("[b]Game data[/b]: %d characters, %d players, %d teams — [color=green][b]VALID[/b][/color]" % [
		data.characters.size(), data.players.size(), data.teams.size()])
	lines.append("[b]Determinism[/b]: %d-minute match simulated twice (seed %d) — %s" % [
		SELF_TEST_MINUTES, SELF_TEST_SEED,
		"[color=green][b]IDENTICAL — PASS[/b][/color]" if ok else "[color=red][b]DIFFERENT — FAIL[/b][/color]",
	])
	lines.append("")
	lines.append("[b]Scoreboard after %d minutes[/b] (%d events; farming economy only — combat lands in M3):" % [
		SELF_TEST_MINUTES, a.events.size()])
	lines.append("[code]%-10s %-6s %-9s %-10s %5s %5s %7s[/code]" % [
		"handle", "team", "role", "character", "level", "cs", "gold"])
	for row: Dictionary in a.summary:
		lines.append("[code]%-10s %-6s %-9s %-10s %5d %5d %7d[/code]" % [
			row.handle, row.team, row.role, row.character, row.level, row.cs, row.gold])
	return "\n".join(lines)


func _build_ui() -> RichTextLabel:
	var bg := ColorRect.new()
	bg.color = Color("1a1f2e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MOBA Manager — M2 sim core: map, minions, laning"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var output := RichTextLabel.new()
	output.bbcode_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(output)
	return output
