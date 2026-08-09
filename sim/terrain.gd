class_name Terrain
extends RefCounted
## Runtime view of data/terrain.txt: the map's walkable space as a square grid of
## cells, one character per cell in the source file. Pure GDScript, no Node deps.
##
## The source file is a picture you can read and edit in any text editor — that is
## the whole point of it (REPORTS/M6-terrain-scoping.md §1). This class turns those
## characters into something the sim and the renderer can ask questions of, and
## enforces the guard rails that keep a hand edit from quietly breaking the game.
##
## Coordinates: row 0 is the TOP of the map (high y), column 0 is x = 0. A grid of
## N cells covers a world of `world_size` units, so one cell is world_size / N units.

# --- cell kinds ---------------------------------------------------------------
# Stored one byte per cell. WALL is the only non-walkable kind; keep it 0 so an
# empty/short row reads as solid rock rather than as accidentally-open floor.
enum {WALL, OPEN, BRUSH, RIVER, PIT, LANE, CAMP, BASE_BLUE, BASE_RED}

const CHAR_TO_KIND := {
	"#": WALL, ".": OPEN, ",": BRUSH, "~": RIVER, "o": PIT,
	"=": LANE, "c": CAMP, "B": BASE_BLUE, "R": BASE_RED,
}
const KIND_TO_CHAR := {
	WALL: "#", OPEN: ".", BRUSH: ",", RIVER: "~", PIT: "o",
	LANE: "=", CAMP: "c", BASE_BLUE: "B", BASE_RED: "R",
}
const KIND_NAME := {
	WALL: "wall", OPEN: "open", BRUSH: "brush", RIVER: "river", PIT: "pit",
	LANE: "lane", CAMP: "camp", BASE_BLUE: "blue base", BASE_RED: "red base",
}

const COMMENT_PREFIX := ";"
## How many of the same complaint we print before saying "and N more". A broken
## edit tends to break a whole row at once; 2500 identical errors help nobody.
const MAX_REPORTED := 8

var n: int = 0                  ## cells per side
var world_size: float = 100.0
var cell_size: float = 2.0      ## world units per cell
var cells: PackedByteArray = PackedByteArray()
## Lazily built by _build_void(); empty until the first is_void_cell().
var _void: PackedByteArray = PackedByteArray()


## Parses the grid text. Structural problems (wrong size, unknown characters) are
## appended to `errors`; the object is still usable so the renderer can show you
## what it *did* read — seeing the broken map is how you fix it.
func _init(text: String, size := 100.0, errors: Array[String] = []) -> void:
	world_size = size
	var rows: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)  # keep leading, drop trailing
		if line.is_empty() or line.begins_with(COMMENT_PREFIX):
			continue
		rows.append(line)
	if rows.is_empty():
		errors.append("terrain: file has no grid rows")
		return

	n = rows.size()
	var width_errors := 0
	for r in rows.size():
		if rows[r].length() != n:
			width_errors += 1
			if width_errors <= MAX_REPORTED:
				errors.append("terrain: row %d is %d chars, expected %d (the grid must be square)"
					% [r, rows[r].length(), n])
	if width_errors > MAX_REPORTED:
		errors.append("terrain: ... and %d more rows of the wrong width" % (width_errors - MAX_REPORTED))

	cell_size = world_size / float(n)
	cells.resize(n * n)
	cells.fill(WALL)
	var unknown := {}
	for r in n:
		var line: String = rows[r]
		for c in mini(n, line.length()):
			var ch := line[c]
			if CHAR_TO_KIND.has(ch):
				cells[r * n + c] = CHAR_TO_KIND[ch]
			else:
				unknown[ch] = unknown.get(ch, 0) + 1
	for ch: String in unknown:
		errors.append("terrain: unknown character \"%s\" (%d times) — see the legend at the top of the file"
			% [ch, unknown[ch]])


## Loads from a file path. Never returns null; on a missing file you get an empty
## grid and an error, which the caller reports rather than crashing on.
static func load_from(path: String, size := 100.0, errors: Array[String] = []) -> Terrain:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: missing or empty file" % path)
	return Terrain.new(text, size, errors)


# --- lookups ------------------------------------------------------------------

func kind_at_cell(col: int, row: int) -> int:
	if col < 0 or row < 0 or col >= n or row >= n:
		return WALL  # outside the grid is rock, not void
	return cells[row * n + col]


func kind_at(world_pos: Vector2) -> int:
	var cell := cell_of(world_pos)
	return kind_at_cell(cell.x, cell.y)


func walkable_at(world_pos: Vector2) -> bool:
	return kind_at(world_pos) != WALL


func walkable_cell(col: int, row: int) -> bool:
	return kind_at_cell(col, row) != WALL


## Blocks line of sight (M6-T3). Split from walkability on purpose: brush is
## walkable and hides you, a wall is neither.
func blocks_sight_cell(col: int, row: int) -> bool:
	return kind_at_cell(col, row) == WALL


## How deep into the border wall the arena's rampart reaches. Beyond this the
## map has simply ended.
const RAMPART_DEPTH := 2

## The three kinds of unwalkable cell. Identical to the sim, which only ever asks
## "can I walk here"; quite different to the eye, which needs to tell a boulder
## it can walk around from the wall at the end of the world.
enum {ROCK, RAMPART, VOID}

## Which of the three a wall cell is. Rock stands inside the arena; rampart is
## the arena's own wall, the part of the outside within RAMPART_DEPTH of walkable
## ground; void is everything beyond that.
##
## The middle case earns its keep. A plain outside/inside split was the first
## version and it failed the moment the outer lanes were pulled inward: a thicker
## border is still entirely border-connected, so the whole new margin went black
## and the road went straight back to abutting the void — reinstating the very
## finding the inset was meant to close.
func wall_class(col: int, row: int) -> int:
	if _void.is_empty():
		_build_void()
	if col < 0 or row < 0 or col >= n or row >= n:
		return VOID
	return _void[row * n + col]


## Drop the cached wall classification, so the next query rebuilds it.
##
## Nothing in the sim or the viewer needs this: a Terrain loaded from disk is
## immutable for its whole life, which is why the cache has no invalidation of its
## own. The editing tools in `tools/` are the exception — they mutate `cells` in
## place and then keep asking questions about the result — and an eroding pass in
## particular *must* see the boundary it moved on the previous pass, or it re-derives
## the rampart from a grid that no longer exists.
func invalidate_wall_classes() -> void:
	_void = PackedByteArray()


## Built lazily, on the first query. A Terrain's cells are fixed at construction
## for every reader in the game; the tools that do edit them call
## `invalidate_wall_classes()` afterwards.
func _build_void() -> void:
	_void.resize(n * n)
	# Pass 1: wall reachable from the map border through wall. Everything outside
	# the arena, including its own wall.
	var outside := PackedByteArray()
	outside.resize(n * n)
	var queue: Array[Vector2i] = []
	for i in n:
		for cell in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			var idx: int = cell.y * n + cell.x
			if cells[idx] == WALL and outside[idx] == 0:
				outside[idx] = 1
				queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cell + d
			if nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
				continue
			var idx: int = nb.y * n + nb.x
			if outside[idx] == 1 or cells[idx] != WALL:
				continue
			outside[idx] = 1
			queue.append(nb)

	# Pass 2: how far each wall cell sits from walkable ground, capped at
	# RAMPART_DEPTH. Anything within that is the arena's wall, not the void.
	var near := PackedByteArray()
	near.resize(n * n)
	var front: Array[Vector2i] = []
	for r in n:
		for c in n:
			if cells[r * n + c] != WALL:
				near[r * n + c] = 1
				front.append(Vector2i(c, r))
	for _step in RAMPART_DEPTH:
		var next_front: Array[Vector2i] = []
		for cell in front:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cell + d
				if nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
					continue
				var idx: int = nb.y * n + nb.x
				if near[idx] == 1:
					continue
				near[idx] = 1
				next_front.append(nb)
		front = next_front

	for i in n * n:
		if outside[i] == 0:
			_void[i] = ROCK
		else:
			_void[i] = RAMPART if near[i] == 1 else VOID


## World position -> cell. Row 0 is the top of the map, so y is flipped.
func cell_of(world_pos: Vector2) -> Vector2i:
	var col := int(floorf(world_pos.x / cell_size))
	var row := n - 1 - int(floorf(world_pos.y / cell_size))
	return Vector2i(clampi(col, 0, n - 1), clampi(row, 0, n - 1))


## Centre of a cell in world coordinates.
func center_of(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * cell_size, (n - row - 0.5) * cell_size)


## The world-space rectangle a cell covers. The renderer draws these.
func rect_of(col: int, row: int) -> Rect2:
	return Rect2(col * cell_size, (n - row - 1) * cell_size, cell_size, cell_size)


func walkable_count() -> int:
	var total := 0
	for i in cells.size():
		if cells[i] != WALL:
			total += 1
	return total


func walkable_fraction() -> float:
	return float(walkable_count()) / float(maxi(1, cells.size()))


## The grid rendered back to text (without the comment header). Used by the
## symmetry repair tooling and by tests that need to diff a generated map.
func to_text() -> String:
	var out := PackedStringArray()
	for r in n:
		var line := ""
		for c in n:
			line += KIND_TO_CHAR[cells[r * n + c]]
		out.append(line)
	return "\n".join(out)


# --- guard rails --------------------------------------------------------------

## Every check the designer's edits have to survive, in one call. Returns the
## list of complaints; empty means the map is sound.
##
## `map` is the SimMap built from data/map.json — the anchors (bases, pits, camps,
## towers) must all stand on walkable ground, or the sim will spawn things inside
## rock.
func validate(map: SimMap = null) -> Array[String]:
	var errors: Array[String] = []
	if n == 0:
		errors.append("terrain: empty grid")
		return errors
	if not is_equal_approx(world_size, map.size if map != null else world_size):
		errors.append("terrain: grid covers %.0f world units, map.json says %.0f"
			% [world_size, map.size])
	_check_symmetry(errors)
	if map != null:
		_check_anchors(map, errors)
		_check_anchor_symmetry(map, errors)
	_check_reachability(map, errors)
	return errors


## 180-degree rotational symmetry about the centre. Blue-side win rate is a
## tracked balance metric, so an asymmetric map would poison every number we
## have — this check is not cosmetic.
func _check_symmetry(errors: Array[String]) -> void:
	var bad := 0
	var first := ""
	for r in n:
		for c in n:
			var here: int = cells[r * n + c]
			var there: int = cells[(n - 1 - r) * n + (n - 1 - c)]
			if _mirror_kind(here) != there:
				bad += 1
				if first.is_empty():
					first = "cell (col %d, row %d) is %s but its opposite (col %d, row %d) is %s" % [
						c, r, KIND_NAME[here], n - 1 - c, n - 1 - r, KIND_NAME[there]]
	if bad > 0:
		# Every mismatch is counted twice (once from each end of the pair).
		errors.append("terrain: not 180-degree symmetric — %d cells disagree; first: %s"
			% [bad / 2, first])


static func _mirror_kind(kind: int) -> int:
	if kind == BASE_BLUE:
		return BASE_RED
	if kind == BASE_RED:
		return BASE_BLUE
	return kind


## Everything the sim places on the map must stand on walkable ground.
func _check_anchors(map: SimMap, errors: Array[String]) -> void:
	var anchors: Array = []
	for team: String in map.bases:
		anchors.append(["%s base" % team, map.bases[team]])
	for pit: String in map.pits:
		anchors.append(["%s pit" % pit, map.pits[pit]])
	for camp: Dictionary in map.camps:
		anchors.append(["camp %s" % camp.get("id", "?"), camp.pos])
	for team: String in map.towers:
		for tier: String in map.towers[team]:
			for lane in SimMap.LANES:
				var t := float(map.towers[team][tier])
				anchors.append(["%s %s tower (%s)" % [team, tier, lane], map.pos_on_lane(lane, t)])
	var reported := 0
	for entry: Array in anchors:
		var pos: Vector2 = entry[1]
		if walkable_at(pos):
			continue
		reported += 1
		if reported <= MAX_REPORTED:
			var cell := cell_of(pos)
			errors.append("terrain: %s at (%.0f, %.0f) sits in rock — cell col %d, row %d"
				% [entry[0], pos.x, pos.y, cell.x, cell.y])
	if reported > MAX_REPORTED:
		errors.append("terrain: ... and %d more anchors in rock" % (reported - MAX_REPORTED))


## The *positions* in map.json must be 180-degree symmetric too, not just the grid.
##
## `_check_symmetry` proves the drawn map is fair and `_check_anchors` proves every
## anchor stands on walkable ground, and between them they look like they cover it.
## They do not: an anchor can sit on perfectly good ground, in a perfectly
## symmetric grid, at a position whose opposite number is somewhere else entirely.
## Found exactly that in the shipped data — four camps whose map.json positions had
## drifted 3.6 world units from the symmetric clusters the grid actually draws, so
## blue's jungle route was measurably shorter than red's while every rail passed.
## Blue-side win rate is a tracked balance metric; this is the half of it the grid
## check could never see.
func _check_anchor_symmetry(map: SimMap, errors: Array[String]) -> void:
	var pairs: Array = [
		["base", map.bases.get("blue", Vector2.ZERO), map.bases.get("red", Vector2.ZERO)],
	]
	if map.pits.has("dragon") and map.pits.has("baron"):
		pairs.append(["pit", map.pits["dragon"], map.pits["baron"]])
	# Camps pair by position rather than by id: nothing in the data says which camp
	# is which one's opposite, so the check is "every camp has an opposite number",
	# which is the property that actually matters.
	var unmatched: Array[String] = []
	for camp: Dictionary in map.camps:
		var want := Vector2(world_size, world_size) - (camp.pos as Vector2)
		var found := false
		for other: Dictionary in map.camps:
			if (other.pos as Vector2).distance_to(want) <= cell_size * 0.5:
				found = true
				break
		if not found:
			unmatched.append("%s at (%.0f, %.0f) — nothing sits at its opposite (%.0f, %.0f)"
				% [camp.get("id", "?"), camp.pos.x, camp.pos.y, want.x, want.y])
	for entry: Array in pairs:
		var a: Vector2 = entry[1]
		var b: Vector2 = entry[2]
		var want := Vector2(world_size, world_size) - a
		if want.distance_to(b) > cell_size * 0.5:
			errors.append("terrain: %s pair is not symmetric — (%.0f, %.0f) implies "
				% [entry[0], a.x, a.y]
				+ "(%.0f, %.0f), but the other is at (%.0f, %.0f)" % [want.x, want.y, b.x, b.y])
	for u in unmatched.slice(0, MAX_REPORTED):
		errors.append("terrain: camp %s" % u)
	if unmatched.size() > MAX_REPORTED:
		errors.append("terrain: ... and %d more asymmetric camps"
			% (unmatched.size() - MAX_REPORTED))


## Every walkable cell must be reachable from both bases. Catches the classic
## hand-edit bug: a wall typed across a corridor that seals off a pocket of
## jungle, which the sim would then send a jungler to and strand it there.
func _check_reachability(map: SimMap, errors: Array[String]) -> void:
	var total := walkable_count()
	if total == 0:
		errors.append("terrain: no walkable cells at all")
		return
	var starts := {}
	if map != null:
		for team: String in map.bases:
			starts[team] = cell_of(map.bases[team])
	else:
		starts["grid"] = _first_walkable()
	for who: String in starts:
		var start: Vector2i = starts[who]
		if not walkable_cell(start.x, start.y):
			continue  # already reported by the anchor check
		var reached := _flood(start)
		if reached < total:
			errors.append("terrain: %d of %d walkable cells are cut off from the %s — "
				% [total - reached, total, who]
				+ "a wall is sealing a pocket of the map")


func _first_walkable() -> Vector2i:
	for r in n:
		for c in n:
			if cells[r * n + c] != WALL:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


## 4-connected flood fill. 4 and not 8 on purpose: a diagonal gap between two
## wall corners is not a gap a body should be able to squeeze through, and T2's
## navigation will use the same connectivity this check does.
func _flood(start: Vector2i) -> int:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var queue: Array[Vector2i] = [start]
	seen[start.y * n + start.x] = 1
	var count := 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		count += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cell + d
			if nb.x < 0 or nb.y < 0 or nb.x >= n or nb.y >= n:
				continue
			var idx: int = nb.y * n + nb.x
			if seen[idx] == 1 or cells[idx] == WALL:
				continue
			seen[idx] = 1
			queue.append(nb)
	return count
