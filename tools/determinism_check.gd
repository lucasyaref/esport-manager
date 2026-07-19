extends SceneTree
## Determinism check: same setup + seed must produce an identical event log,
## identical snapshots, and identical checksum. Different seeds must diverge.
##
## Usage:
##   godot --headless --path . --script res://tools/determinism_check.gd
##
## Exits 0 on PASS, 1 on FAIL. Run via tools/check.sh.

const SEEDS := [1, 42, 987654321]
const TICKS := 600  # 60 sim-seconds is plenty to accumulate RNG draws


func _initialize() -> void:
	var failed := false
	var checksums := []

	for s in SEEDS:
		var setup := {"seed": s, "duration_ticks": TICKS}
		var a := SimMatch.new(setup).run()
		var b := SimMatch.new(setup).run()
		if a.checksum != b.checksum:
			failed = true
			print("FAIL seed=%d: checksums differ (%s vs %s)" % [s, a.checksum, b.checksum])
			_print_first_divergence(a, b)
		elif JSON.stringify(a.events) != JSON.stringify(b.events):
			failed = true
			print("FAIL seed=%d: same checksum but different events (checksum bug?)" % s)
		else:
			print("ok   seed=%d: two runs identical, %d events, checksum=%s" % [
				s, a.events.size(), a.checksum,
			])
		checksums.append(a.checksum)

	# Sanity: different seeds should not collide (if they do, the seed is
	# probably being ignored somewhere).
	for i in range(checksums.size()):
		for j in range(i + 1, checksums.size()):
			if checksums[i] == checksums[j]:
				failed = true
				print("FAIL: seeds %s and %s produced identical output" % [SEEDS[i], SEEDS[j]])

	if failed:
		print("DETERMINISM CHECK: FAIL")
		quit(1)
	else:
		print("DETERMINISM CHECK: PASS")
		quit(0)


func _print_first_divergence(a: Dictionary, b: Dictionary) -> void:
	var n: int = min(a.events.size(), b.events.size())
	for i in range(n):
		if JSON.stringify(a.events[i]) != JSON.stringify(b.events[i]):
			print("  first differing event at index %d:" % i)
			print("    run A: %s" % JSON.stringify(a.events[i]))
			print("    run B: %s" % JSON.stringify(b.events[i]))
			return
	print("  event logs are a prefix of each other (sizes %d vs %d)" % [
		a.events.size(), b.events.size(),
	])
