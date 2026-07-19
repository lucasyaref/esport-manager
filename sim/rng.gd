class_name SimRNG
extends RefCounted
## Seeded RNG for the simulation core.
##
## Determinism contract: every random draw inside sim/ MUST go through the
## single SimRNG instance owned by the match. Never call the global
## randf()/randi() utilities, never create ad-hoc RandomNumberGenerator
## instances, never use Array.shuffle()/pick_random() (they use the global
## RNG), and never let draw order depend on anything but sim state.
## tools/check.sh lints sim/ for violations.
##
## GOTCHA that already bit us once (M0): inside this class, an UNQUALIFIED
## call like `randf()` binds to the global @GlobalScope utility function,
## NOT to the method below — GDScript utility functions shadow same-named
## methods. Internal calls must be written `self.randf()`.

var _rng := RandomNumberGenerator.new()
var draw_count: int = 0  # draws so far; events record it to pinpoint desyncs


func _init(match_seed: int) -> void:
	_rng.seed = match_seed


func randf() -> float:
	draw_count += 1
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	draw_count += 1
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	draw_count += 1
	return _rng.randi_range(from, to)


## True with probability p (0..1).
func chance(p: float) -> bool:
	return self.randf() < p


## Uniform pick from a non-empty array.
func pick(options: Array) -> Variant:
	assert(not options.is_empty())
	return options[self.randi_range(0, options.size() - 1)]


## Index into weights proportional to weight value. Weights must be >= 0
## and sum to > 0.
func weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	assert(total > 0.0)
	var roll := self.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if roll < acc:
			return i
	return weights.size() - 1


## In-place Fisher-Yates shuffle.
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := self.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
