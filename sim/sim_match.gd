class_name SimMatch
extends RefCounted
## Deterministic tick-based match simulation.
##
## M0 stub: no real MOBA logic yet. Ten placeholder entities random-walk on a
## logical map and resolve "skirmishes" when they meet. The point of this stub
## is to lock in the architecture every later milestone builds on:
##   input  = setup dictionary (seed + params)
##   output = ordered event stream + per-tick snapshots + checksum
## and to prove the determinism rule: same setup ⇒ identical output.
##
## Pure GDScript — no Node/scene dependencies. Must run headless.

const TICKS_PER_SECOND := 10

const MAP_SIZE := 100.0          # logical units, square map
const WALK_SPEED := 1.5          # units per tick, stub value
const SKIRMISH_RANGE := 6.0
const SKIRMISH_COOLDOWN_TICKS := 30

var _setup: Dictionary
var _rng: SimRNG

var _entities: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _snapshots: Array[Array] = []
var _skirmish_cooldown := 0


func _init(setup: Dictionary) -> void:
	_setup = setup
	_rng = SimRNG.new(int(setup.get("seed", 0)))


## Runs the full match and returns:
## { "events": Array, "snapshots": Array, "ticks": int, "checksum": String }
func run() -> Dictionary:
	var duration_ticks := int(_setup.get("duration_ticks", 60 * TICKS_PER_SECOND))
	_spawn_entities()
	_emit(0, "match_start", {"seed": int(_setup.get("seed", 0))})
	for t in range(duration_ticks):
		_tick(t)
		_snapshots.append(_capture_snapshot())
	_emit(duration_ticks - 1, "match_end", {})
	return {
		"events": _events,
		"snapshots": _snapshots,
		"ticks": duration_ticks,
		"checksum": _checksum(),
	}


func _spawn_entities() -> void:
	for i in range(5):
		_entities.append(_make_entity("B%d" % (i + 1), Vector2(5, 5)))
	for i in range(5):
		_entities.append(_make_entity("R%d" % (i + 1), Vector2(MAP_SIZE - 5, MAP_SIZE - 5)))


func _make_entity(id: String, home: Vector2) -> Dictionary:
	return {"id": id, "home": home, "pos": home, "kills": 0}


func _tick(t: int) -> void:
	# Movement: seeded random walk with a drift toward map center so the two
	# teams actually meet and skirmish. Iteration order over _entities is
	# fixed (array order), which keeps RNG draw order stable.
	var center := Vector2(MAP_SIZE / 2, MAP_SIZE / 2)
	for e in _entities:
		var noise := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		var drift: Vector2 = (center - e.pos).normalized() * 0.4 if e.pos.distance_to(center) > 1.0 else Vector2.ZERO
		var dir := noise + drift
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
		e.pos = (e.pos + dir * WALK_SPEED).clamp(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE))

	# Skirmish stub: first cross-team pair in range fights, coin-flip winner,
	# loser goes back to their home corner.
	if _skirmish_cooldown > 0:
		_skirmish_cooldown -= 1
		return
	for i in range(_entities.size()):
		for j in range(i + 1, _entities.size()):
			var a: Dictionary = _entities[i]
			var b: Dictionary = _entities[j]
			if a.id[0] == b.id[0]:
				continue
			if a.pos.distance_to(b.pos) > SKIRMISH_RANGE:
				continue
			var a_wins := _rng.chance(0.5)
			var winner: Dictionary = a if a_wins else b
			var loser: Dictionary = b if a_wins else a
			winner.kills += 1
			loser.pos = loser.home
			_emit(t, "skirmish_stub", {"winner": winner.id, "loser": loser.id})
			_skirmish_cooldown = SKIRMISH_COOLDOWN_TICKS
			return


func _emit(t: int, type: String, data: Dictionary) -> void:
	# "draws" = RNG draw count when the event fired. Two runs of the same seed
	# must match on this; it pinpoints desyncs instantly when they don't.
	_events.append({"t": t, "type": type, "draws": _rng.draw_count, "data": data})


func _capture_snapshot() -> Array:
	var snap := []
	for e in _entities:
		snap.append([e.id, e.pos.x, e.pos.y, e.kills])
	return snap


## MD5 over byte-exact serialized events + snapshots. var_to_bytes keeps full
## float precision — JSON.stringify rounds, which can hide tiny divergences.
## Insertion order of all dictionaries is deterministic, so this is canonical.
func _checksum() -> String:
	var payload := var_to_bytes({"events": _events, "snapshots": _snapshots})
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(payload)
	return ctx.finish().hex_encode()
