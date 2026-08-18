class_name ForestGenerator
extends RefCounted
## Builds a forest layout from a seed. Pure data - no nodes, no scene tree.
##
## Being node-free is the point: the whole thing can be run hundreds of times
## in a headless test to prove the guarantees below actually hold, which is not
## something you can check by looking at one screenshot.
##
## Guarantees (asserted by tests/test_forest.gd):
##   * the player never spawns inside an obstacle
##   * every clearing, the shop and every loot point is reachable on foot
##   * no clearing is smaller than MIN_CLEARING_OPEN_CELLS of open ground
##   * enemy spawn points are on open ground and off-screen from the player

const WORLD_SIZE := Vector2(4800.0, 3700.0)
const CELL := 64.0
const BORDER := 300.0                    ## impassable tree wall around the map

const CLEARING_MIN := 9
const CLEARING_MAX := 13
const CLEARING_RADIUS := Vector2(300.0, 470.0)
const CLEARING_SEPARATION := 720.0
const PATH_WIDTH := 170.0
const EXTRA_PATH_LOOPS := 3

const POND_MIN := 2
const POND_MAX := 4
const POND_RADIUS := Vector2(190.0, 330.0)

const TREE_SPACING := 168.0
const SCATTER_SPACING := 132.0
const DETAIL_SPACING := 108.0

const MIN_CLEARING_OPEN_CELLS := 26      ## ~106k px^2 of fightable space
const ACTOR_CLEARANCE := 46.0            ## widest actor half-width + margin
const MAX_ATTEMPTS := 6

# Cell flags
const OPEN := 0
const BLOCKED := 1

var rng := RandomNumberGenerator.new()

# --- output -----------------------------------------------------------------
var seed_value: int = 0
var bounds := Rect2(Vector2.ZERO, WORLD_SIZE)
var cols: int = 0
var rows: int = 0
var grid := PackedByteArray()
var props: Array[Dictionary] = []        # {id, pos, scale, flip, sway_phase}
var blockers: Array[Dictionary] = []     # {pos, radius}
var ponds: Array[Dictionary] = []        # {center, radius}
var clearings: Array[Dictionary] = []    # {center, radius}
var spawn_point := Vector2.ZERO
var shop_point := Vector2.ZERO
var loot_points: Array[Vector2] = []
var spawn_zones: Array[Vector2] = []
var attempts_used: int = 0
var failure: String = ""


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------
static func generate(seed_v: int) -> ForestGenerator:
	var g := ForestGenerator.new()
	g.seed_value = seed_v
	g._build()
	return g


func _build() -> void:
	cols = int(ceil(WORLD_SIZE.x / CELL))
	rows = int(ceil(WORLD_SIZE.y / CELL))

	# Reseed per attempt. If a layout can't be made connected we throw it away
	# and try a fresh one rather than shipping something the player can't walk.
	for attempt in MAX_ATTEMPTS:
		attempts_used = attempt + 1
		rng.seed = seed_value + attempt * 7919
		_reset()
		_place_clearings()
		_carve_paths()
		_place_ponds()
		_scatter_props()
		_rasterise()
		if _repair_and_validate():
			failure = ""
			_choose_spawn_zones()
			return
	# Every attempt failed: fall back to a bare arena, which is ugly but always
	# playable. Tests treat reaching this as a failure.
	failure = "fell back to bare arena after %d attempts" % MAX_ATTEMPTS
	_reset()
	_place_clearings()
	_carve_paths()
	_rasterise()
	_choose_spawn_zones()


func _reset() -> void:
	props.clear()
	blockers.clear()
	ponds.clear()
	clearings.clear()
	loot_points.clear()
	spawn_zones.clear()
	grid = PackedByteArray()
	grid.resize(cols * rows)
	grid.fill(OPEN)


# ---------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------
func _place_clearings() -> void:
	var want := rng.randi_range(CLEARING_MIN, CLEARING_MAX)
	var inset := BORDER + CLEARING_RADIUS.y
	var tries := 0
	while clearings.size() < want and tries < 900:
		tries += 1
		var p := Vector2(
			rng.randf_range(inset, WORLD_SIZE.x - inset),
			rng.randf_range(inset, WORLD_SIZE.y - inset))
		var ok := true
		for c: Dictionary in clearings:
			if p.distance_to(c["center"]) < CLEARING_SEPARATION:
				ok = false
				break
		if ok:
			clearings.append({
				"center": p,
				"radius": rng.randf_range(CLEARING_RADIUS.x, CLEARING_RADIUS.y),
			})

	# Spawn in the clearing nearest the middle, so the player starts with room
	# on every side instead of backed against the border.
	var mid := WORLD_SIZE * 0.5
	var best := 0
	for i in clearings.size():
		if clearings[i]["center"].distance_to(mid) < clearings[best]["center"].distance_to(mid):
			best = i
	spawn_point = clearings[best]["center"]

	# Shop goes in the clearing furthest from spawn - it's a destination.
	var far := 0
	for i in clearings.size():
		if clearings[i]["center"].distance_to(spawn_point) > clearings[far]["center"].distance_to(spawn_point):
			far = i
	shop_point = clearings[far]["center"]

	for i in clearings.size():
		if i != best:
			loot_points.append(_jitter_in_clearing(clearings[i]))


func _jitter_in_clearing(c: Dictionary) -> Vector2:
	var r: float = float(c["radius"]) * 0.55
	var a := rng.randf() * TAU
	return c["center"] + Vector2(cos(a), sin(a)) * rng.randf() * r


## Minimum spanning tree over the clearings, plus a few extra edges so the map
## has loops to circle-strafe around instead of dead ends.
var _path_segments: Array[Dictionary] = []


func _carve_paths() -> void:
	_path_segments.clear()
	if clearings.size() < 2:
		return
	var connected := [0]
	var remaining := range(1, clearings.size())
	while not remaining.is_empty():
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a: int in connected:
			for b: int in remaining:
				var d: float = clearings[a]["center"].distance_to(clearings[b]["center"])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		_path_segments.append({"a": best_a, "b": best_b})
		connected.append(best_b)
		remaining.erase(best_b)

	for i in EXTRA_PATH_LOOPS:
		var a := rng.randi_range(0, clearings.size() - 1)
		var b := rng.randi_range(0, clearings.size() - 1)
		if a != b:
			_path_segments.append({"a": a, "b": b})


func _place_ponds() -> void:
	var want := rng.randi_range(POND_MIN, POND_MAX)
	var inset := BORDER + POND_RADIUS.y
	var tries := 0
	while ponds.size() < want and tries < 400:
		tries += 1
		var p := Vector2(
			rng.randf_range(inset, WORLD_SIZE.x - inset),
			rng.randf_range(inset, WORLD_SIZE.y - inset))
		var r := rng.randf_range(POND_RADIUS.x, POND_RADIUS.y)
		# never drown a clearing or a path
		if _clearing_overlap(p, r + 140.0) or _on_path(p, r + 130.0):
			continue
		var clash := false
		for other: Dictionary in ponds:
			if p.distance_to(other["center"]) < r + float(other["radius"]) + 220.0:
				clash = true
				break
		if clash:
			continue
		ponds.append({"center": p, "radius": r})
		blockers.append({"pos": p, "radius": r * 0.92})
		_scatter_water_edge(p, r)


func _scatter_water_edge(center: Vector2, radius: float) -> void:
	var n := int(radius / 26.0)
	for i in n:
		var a := rng.randf() * TAU
		var d := radius * rng.randf_range(0.80, 1.14)
		var id := PropCatalog.pick(rng, PropCatalog.WATER_EDGE)
		# lily pads float, everything else sits on the bank
		if id == "lilypad":
			d = radius * rng.randf_range(0.15, 0.7)
		_add_prop(id, center + Vector2(cos(a), sin(a)) * d)


# ---------------------------------------------------------------------------
# scattering
# ---------------------------------------------------------------------------
func _scatter_props() -> void:
	_scatter_border()
	_scatter_layer(TREE_SPACING, PropCatalog.FOREST_TREES, "forest")
	_scatter_layer(SCATTER_SPACING, PropCatalog.FOREST_SCATTER, "forest")
	_scatter_layer(DETAIL_SPACING, PropCatalog.CLEARING_SCATTER, "clearing")
	_scatter_layer(DETAIL_SPACING * 1.35, PropCatalog.DETAIL_SCATTER, "path")
	_add_prop("shop_lantern", shop_point + Vector2(0, -150))
	_add_prop("campfire", shop_point)


## Dense unbroken tree wall so the arena has a hard edge without an invisible
## wall the player can see through.
func _scatter_border() -> void:
	var step := 96.0
	var depth := BORDER
	var x := 40.0
	while x < WORLD_SIZE.x:
		for band in range(0, int(depth / step)):
			var inset := band * step + rng.randf_range(-20.0, 20.0)
			_add_prop(PropCatalog.pick(rng, PropCatalog.FOREST_TREES),
				Vector2(x + rng.randf_range(-24, 24), inset))
			_add_prop(PropCatalog.pick(rng, PropCatalog.FOREST_TREES),
				Vector2(x + rng.randf_range(-24, 24), WORLD_SIZE.y - inset))
		x += step
	var y := 40.0
	while y < WORLD_SIZE.y:
		for band in range(0, int(depth / step)):
			var inset := band * step + rng.randf_range(-20.0, 20.0)
			_add_prop(PropCatalog.pick(rng, PropCatalog.FOREST_TREES),
				Vector2(inset, y + rng.randf_range(-24, 24)))
			_add_prop(PropCatalog.pick(rng, PropCatalog.FOREST_TREES),
				Vector2(WORLD_SIZE.x - inset, y + rng.randf_range(-24, 24)))
		y += step


## Jittered-grid sampling: cheap, deterministic, and gives blue-noise-ish
## spacing without the cost of real Poisson-disc rejection over a big map.
func _scatter_layer(spacing: float, table: Dictionary, region: String) -> void:
	var gx := int(WORLD_SIZE.x / spacing)
	var gy := int(WORLD_SIZE.y / spacing)
	for iy in range(1, gy):
		for ix in range(1, gx):
			var p := Vector2(
				ix * spacing + rng.randf_range(-spacing * 0.42, spacing * 0.42),
				iy * spacing + rng.randf_range(-spacing * 0.42, spacing * 0.42))
			if p.x < BORDER or p.y < BORDER \
					or p.x > WORLD_SIZE.x - BORDER or p.y > WORLD_SIZE.y - BORDER:
				continue
			if _in_pond(p, 30.0):
				continue

			var in_clearing := _clearing_overlap(p, 0.0)
			var on_path := _on_path(p, 0.0)
			match region:
				"forest":
					# keep solid things out of the arenas and the roads
					if in_clearing or on_path:
						continue
					if rng.randf() > 0.72:
						continue
				"clearing":
					if not in_clearing:
						continue
					if rng.randf() > 0.55:
						continue
				"path":
					if in_clearing or not on_path:
						continue
					if rng.randf() > 0.40:
						continue
			_add_prop(PropCatalog.pick(rng, table), p)


func _add_prop(id: String, pos: Vector2) -> void:
	props.append({
		"id": id,
		"pos": pos,
		"scale": rng.randf_range(0.88, 1.14),
		"flip": rng.randf() < 0.5,
		"sway_phase": rng.randf() * TAU,
	})
	if not PropCatalog.blocks(id):
		return
	var s: float = props[-1]["scale"]
	for b: Dictionary in PropCatalog.blockers(id):
		blockers.append({
			"pos": pos + (b["offset"] as Vector2) * s,
			"radius": float(b["radius"]) * s,
		})


# ---------------------------------------------------------------------------
# grid + connectivity
# ---------------------------------------------------------------------------
func _idx(cx: int, cy: int) -> int:
	return cy * cols + cx


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(p.x / CELL), 0, cols - 1),
		clampi(int(p.y / CELL), 0, rows - 1))


func cell_center(cx: int, cy: int) -> Vector2:
	return Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)


func is_open(p: Vector2) -> bool:
	if not bounds.has_point(p):
		return false
	var c := cell_of(p)
	return grid[_idx(c.x, c.y)] == OPEN


## Mark a cell blocked if any blocker circle comes within ACTOR_CLEARANCE of
## it. Inflating by the actor radius here means "open cell" already implies
## "an actor fits", so nothing downstream has to think about body size.
func _rasterise() -> void:
	grid.fill(OPEN)
	for b: Dictionary in blockers:
		var pos: Vector2 = b["pos"]
		var r: float = float(b["radius"]) + ACTOR_CLEARANCE
		var min_c := cell_of(pos - Vector2(r, r))
		var max_c := cell_of(pos + Vector2(r, r))
		for cy in range(min_c.y, max_c.y + 1):
			for cx in range(min_c.x, max_c.x + 1):
				if cell_center(cx, cy).distance_to(pos) <= r:
					grid[_idx(cx, cy)] = BLOCKED
	# the border band is always solid
	var bc := int(BORDER / CELL)
	for cy in rows:
		for cx in cols:
			if cx < bc or cy < bc or cx >= cols - bc or cy >= rows - bc:
				grid[_idx(cx, cy)] = BLOCKED


func _flood_from(start: Vector2) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	seen.fill(0)
	var c := cell_of(start)
	if grid[_idx(c.x, c.y)] == BLOCKED:
		return seen
	var queue: Array[Vector2i] = [c]
	seen[_idx(c.x, c.y)] = 1
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cur + d
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			var i := _idx(n.x, n.y)
			if seen[i] == 1 or grid[i] == BLOCKED:
				continue
			seen[i] = 1
			queue.append(n)
	return seen


## Force a walkable corridor between two points by deleting any blocker that
## intrudes on it. Used both to cut the paths and to repair a broken map.
func _clear_corridor(a: Vector2, b: Vector2, width: float) -> void:
	var kept: Array[Dictionary] = []
	for blocker: Dictionary in blockers:
		var d := _distance_to_segment(blocker["pos"], a, b)
		if d > width * 0.5 + float(blocker["radius"]):
			kept.append(blocker)
	blockers = kept
	var kept_props: Array[Dictionary] = []
	for prop: Dictionary in props:
		if not PropCatalog.blocks(prop["id"]):
			kept_props.append(prop)
			continue
		var d := _distance_to_segment(prop["pos"], a, b)
		if d > width * 0.5 + PropCatalog.block_radius(prop["id"]) * float(prop["scale"]):
			kept_props.append(prop)
	props = kept_props


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _clearing_overlap(p: Vector2, margin: float) -> bool:
	for c: Dictionary in clearings:
		if p.distance_to(c["center"]) < float(c["radius"]) + margin:
			return true
	return false


func _on_path(p: Vector2, margin: float) -> bool:
	for seg: Dictionary in _path_segments:
		var a: Vector2 = clearings[seg["a"]]["center"]
		var b: Vector2 = clearings[seg["b"]]["center"]
		if _distance_to_segment(p, a, b) < PATH_WIDTH * 0.5 + margin:
			return true
	return false


func _in_pond(p: Vector2, margin: float) -> bool:
	for pond: Dictionary in ponds:
		if p.distance_to(pond["center"]) < float(pond["radius"]) + margin:
			return true
	return false


## Cut clearings and roads clear, then check everything important is
## reachable, repairing once before giving up on the layout.
func _repair_and_validate() -> bool:
	for c: Dictionary in clearings:
		_clear_corridor(c["center"], c["center"], float(c["radius"]) * 2.0)
	for seg: Dictionary in _path_segments:
		_clear_corridor(clearings[seg["a"]]["center"], clearings[seg["b"]]["center"], PATH_WIDTH)
	_rasterise()

	for pass_index in 2:
		var reachable := _flood_from(spawn_point)
		var broken: Array[Vector2] = []
		for c: Dictionary in clearings:
			if not _reached(reachable, c["center"]):
				broken.append(c["center"])
		for p: Vector2 in loot_points:
			if not _reached(reachable, p):
				broken.append(p)
		if not _reached(reachable, shop_point):
			broken.append(shop_point)

		if broken.is_empty():
			return _clearings_are_roomy()
		if pass_index == 1:
			return false
		# punch straight corridors from spawn to whatever got cut off
		for p: Vector2 in broken:
			_clear_corridor(spawn_point, p, PATH_WIDTH)
		_rasterise()
	return false


func _reached(reachable: PackedByteArray, p: Vector2) -> bool:
	var c := cell_of(p)
	return reachable[_idx(c.x, c.y)] == 1


## A clearing that got choked with props isn't a combat space. Count the open
## cells inside each one and reject the layout if any is too cramped.
func _clearings_are_roomy() -> bool:
	for c: Dictionary in clearings:
		if open_cells_in(c["center"], float(c["radius"])) < MIN_CLEARING_OPEN_CELLS:
			return false
	return true


func open_cells_in(center: Vector2, radius: float) -> int:
	var min_c := cell_of(center - Vector2(radius, radius))
	var max_c := cell_of(center + Vector2(radius, radius))
	var n := 0
	for cy in range(min_c.y, max_c.y + 1):
		for cx in range(min_c.x, max_c.x + 1):
			if grid[_idx(cx, cy)] == OPEN and cell_center(cx, cy).distance_to(center) <= radius:
				n += 1
	return n


# ---------------------------------------------------------------------------
# spawn zones
# ---------------------------------------------------------------------------
## Candidate enemy spawn cells: open ground, reachable from the player's start.
## The spawner picks from these at run time with a live distance check, so an
## enemy can never appear on top of the player or inside a rock.
func _choose_spawn_zones() -> void:
	spawn_zones.clear()
	var reachable := _flood_from(spawn_point)
	var step := 3       # sample every 3rd cell; ~450 candidates is plenty
	for cy in range(0, rows, step):
		for cx in range(0, cols, step):
			var i := _idx(cx, cy)
			if grid[i] != OPEN or reachable[i] != 1:
				continue
			spawn_zones.append(cell_center(cx, cy))


## True if a body of `actor_radius` fits here, not just its centre point.
##
## The walkable grid is inflated by ACTOR_CLEARANCE, which is sized for a
## normal slime. A boss is several times wider, and dropping one into a gap
## that only fits a slime wedges it permanently - which, since the player
## cannot shoot through the trees pinning it, ends the run.
func has_clearance(p: Vector2, actor_radius: float) -> bool:
	if not is_open(p):
		return false
	var extra := maxf(0.0, actor_radius - ACTOR_CLEARANCE)
	if extra <= 0.0:
		return true
	var steps := maxi(1, int(ceil(extra / CELL)))
	for ring in range(1, steps + 1):
		var r := minf(ring * CELL, extra)
		var samples := 8 + ring * 4
		for i in samples:
			var a := TAU * i / samples
			if not is_open(p + Vector2(cos(a), sin(a)) * r):
				return false
	return true


## Nearest point with room for a body of `actor_radius`, searching outwards.
func nearest_open_for(p: Vector2, actor_radius: float,
		max_radius: float = 1600.0) -> Vector2:
	if has_clearance(p, actor_radius):
		return p
	var r := CELL
	while r <= max_radius:
		var samples := maxi(10, int(TAU * r / CELL))
		for i in samples:
			var a := TAU * i / samples
			var q := p + Vector2(cos(a), sin(a)) * r
			if has_clearance(q, actor_radius):
				return q
		r += CELL
	# nowhere fits: the clearings are the roomiest places we know of
	var best := spawn_point
	var best_open := -1
	for c: Dictionary in clearings:
		var open_cells := open_cells_in(c["center"], float(c["radius"]))
		if open_cells > best_open:
			best_open = open_cells
			best = c["center"]
	return best


## Nearest open point to `p`, searching outwards. Used to nudge anything that
## would otherwise be placed in a wall.
func nearest_open(p: Vector2, max_radius: float = 900.0) -> Vector2:
	if is_open(p):
		return p
	var step := CELL
	var r := step
	while r <= max_radius:
		var samples := maxi(8, int(TAU * r / step))
		for i in samples:
			var a := TAU * i / samples
			var q := p + Vector2(cos(a), sin(a)) * r
			if is_open(q):
				return q
		r += step
	return spawn_point


func debug_summary() -> Dictionary:
	var open_count := 0
	for v: int in grid:
		if v == OPEN:
			open_count += 1
	return {
		"seed": seed_value,
		"attempts": attempts_used,
		"failure": failure,
		"clearings": clearings.size(),
		"ponds": ponds.size(),
		"props": props.size(),
		"blockers": blockers.size(),
		"spawn_zones": spawn_zones.size(),
		"open_cells": open_count,
		"total_cells": cols * rows,
	}
