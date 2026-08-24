class_name Combat
extends RefCounted
## Shared combat services: the live-enemy registry, area queries, and the
## global enemy time scale used by the Torpor ability.
##
## The registry exists because abilities, bosses and the wave controller all
## need "every live enemy" several times a frame, and repeatedly walking a
## SceneTree group for that is measurably worse than maintaining one array.
##
## Everything here is static, so it must be reset at the start of each run -
## `reset()` is called by run.gd.

static var enemy_time_scale: float = 1.0

## True once a wave has spawned everything it is going to and only a handful
## of enemies are left. In that state every survivor commits to the player -
## fleeing Hoarders stop fleeing, Spitters stop holding range.
##
## Without this the end of a wave becomes a hunt across a 4800x3700 forest for
## two enemies that are actively avoiding you, which is dead time in a game
## whose whole appeal is continuous pressure.
static var finisher_mode: bool = false

static var _enemies: Array[Node2D] = []
static var _player: Node2D = null


static func reset() -> void:
	enemy_time_scale = 1.0
	finisher_mode = false
	_enemies.clear()
	_player = null


# ---------------------------------------------------------------------------
# registry
# ---------------------------------------------------------------------------
static func register_enemy(e: Node2D) -> void:
	if not _enemies.has(e):
		_enemies.append(e)


static func unregister_enemy(e: Node2D) -> void:
	_enemies.erase(e)


static func set_player(p: Node2D) -> void:
	_player = p


static func player() -> Node2D:
	return _player if is_instance_valid(_player) else null


static func player_position() -> Vector2:
	var p := player()
	return p.global_position if p != null else Vector2.ZERO


## Live enemies, pruned of anything freed or returned to the pool.
static func enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var stale := false
	for e: Node2D in _enemies:
		if is_instance_valid(e) and e.is_inside_tree() and not bool(e.get("dying")):
			out.append(e)
		else:
			stale = true
	if stale:
		_enemies = out.duplicate()
	return out


static func enemy_count() -> int:
	return enemies().size()


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------
## Where an actor is actually drawn.
##
## Every actor's physics origin is at its feet, which is also where its shadow
## is drawn - the sprite sits well above it (32px for a slime, 78px for a boss).
## Measuring area damage from the origin meant abilities and bullets disagreed
## about where an enemy was, and both of them disagreed with the player's eyes.
## Falls back to the origin for anything that does not declare an offset.
static func hit_center(node: Node2D) -> Vector2:
	if node != null and node.has_method("hit_center"):
		return node.call("hit_center")
	return node.global_position if node != null else Vector2.ZERO


static func enemies_in_radius(center: Vector2, radius: float) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var r2 := radius * radius
	for e: Node2D in enemies():
		if hit_center(e).distance_squared_to(center) <= r2:
			out.append(e)
	return out


static func nearest_enemy(to: Vector2, max_distance: float = INF,
		exclude: Array = []) -> Node2D:
	var best: Node2D = null
	var best_d := max_distance * max_distance
	for e: Node2D in enemies():
		if exclude.has(e):
			continue
		var d := hit_center(e).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = e
	return best


## Damage everything in a circle, with optional falloff and knockback.
## Returns the number of enemies hit.
static func explode(center: Vector2, radius: float, damage: float,
		knockback: float = 0.0, falloff: bool = true) -> int:
	var hit := 0
	for e: Node2D in enemies_in_radius(center, radius):
		var dist := hit_center(e).distance_to(center)
		var scale := 1.0
		if falloff:
			scale = lerpf(1.0, 0.42, clampf(dist / maxf(radius, 1.0), 0.0, 1.0))
		if e.has_method("take_damage"):
			e.call("take_damage", damage * scale, false, center, knockback)
		hit += 1
	return hit


## Same, but hurts the player instead. Used by enemy and boss explosions.
static func explode_on_player(center: Vector2, radius: float, damage: float) -> bool:
	var p := player()
	if p == null or not p.has_method("take_damage"):
		return false
	var dist := hit_center(p).distance_to(center)
	if dist > radius:
		return false
	var scale := lerpf(1.0, 0.5, clampf(dist / maxf(radius, 1.0), 0.0, 1.0))
	p.call("take_damage", damage * scale, false, center, 0.0)
	return true


# ---------------------------------------------------------------------------
# time scale
# ---------------------------------------------------------------------------
## Slow every enemy and enemy bullet for `duration` seconds. Uses a tween on
## the caller so it survives the ability node going away.
static func apply_slow(host: Node, factor: float, duration: float) -> void:
	enemy_time_scale = factor
	var t := host.create_tween()
	t.tween_interval(duration)
	t.tween_callback(func() -> void: enemy_time_scale = 1.0)
