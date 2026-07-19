extends Control
## M0 placeholder main scene: runs the sim determinism self-test on startup and
## shows the result, so "open the project and press Play" proves the skeleton
## works. Replaced by the real match viewer in M4.

const SELF_TEST_SEED := 42
const SELF_TEST_TICKS := 600


func _ready() -> void:
	var output := _build_ui()
	output.text = _run_self_test()


func _run_self_test() -> String:
	var setup := {"seed": SELF_TEST_SEED, "duration_ticks": SELF_TEST_TICKS}
	var a := SimMatch.new(setup).run()
	var b := SimMatch.new(setup).run()
	var ok: bool = a.checksum == b.checksum

	var lines := []
	lines.append("[b]Sim determinism self-test[/b]  (seed %d, %d ticks, run twice)" % [
		SELF_TEST_SEED, SELF_TEST_TICKS,
	])
	lines.append("run 1 checksum: [code]%s[/code]" % a.checksum)
	lines.append("run 2 checksum: [code]%s[/code]" % b.checksum)
	lines.append("[color=%s][b]%s[/b][/color]" % [
		"green" if ok else "red", "IDENTICAL — PASS" if ok else "DIFFERENT — FAIL",
	])
	lines.append("")
	lines.append("[b]Stub event log[/b] (placeholder skirmishes, real sim arrives in M2–M3):")
	for ev in a.events:
		var secs: float = ev.t / float(SimMatch.TICKS_PER_SECOND)
		match ev.type:
			"skirmish_stub":
				lines.append("  %5.1fs  %s killed %s" % [secs, ev.data.winner, ev.data.loser])
			_:
				lines.append("  %5.1fs  %s" % [secs, ev.type])
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
	title.text = "MOBA Manager — M0 project skeleton"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var output := RichTextLabel.new()
	output.bbcode_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(output)
	return output
