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

## Where a hit came from. Two enemy types are immune to one source each, so
## every damaging call has to say which it is.
##
## SOURCE_OTHER is the default on purpose: it always lands. A Bloater's blast
## is neither a bullet nor an ability, and if it inherited either tag a cluster
## of Bloaters would quietly become a universal answer to whichever type it was
## tagged as. Only the two real sources override it.
const SOURCE_OTHER := "other"
const SOURCE_BULLET := "bullet"
const SOURCE_ABILITY := "ability"

static var enemy_time_scale: float = 1.0
static var _slow_left: float = 0.0

## True once a wave has spawned everything it is going to and only a handful
## of enemies are left. In that state every survivor commits to the player -
## fleeing Hoarders stop fleeing, Spitters stop holding range.
##
## Without this the end of a wave becomes a hunt across a 4800x3700 forest for
## two enemies that are actively avoiding you, which is dead time in a game
## whose whole appeal is continuous pressure.
static var finisher_mode: bool = false

## Seconds finisher_mode has been on without the enemy count moving.
static var finisher_stall: float = 0.0
## True once a finishing wave has failed to end for long enough that something
## is wrong rather than slow.
##
## finisher_mode is only advice: it points a straggler at the player. It cannot
## help one that is obeying it and still cannot arrive - a Spitter pressed
## against a trunk, or anything knocked somewhere it cannot path back from. The
## sim wedged on exactly that, a full-health Spitter holding 389px for 14,400
## frames, and from the wave counter it was indistinguishable from a wave that
## never spawned.
##
## An escalated straggler ignores the forest and moves faster. That is a real
## cost - a slime briefly walking through a trunk - and it is the smaller one,
## because a wave that cannot end cannot be recovered from at all.
static var hunt_mode: bool = false
static var _finisher_count: int = -1

static var _enemies: Array[Node2D] = []
static var _player: Node2D = null


static func reset() -> void:
	enemy_time_scale = 1.0
	_slow_left = 0.0
	finisher_mode = false
	finisher_stall = 0.0
	hunt_mode = false
	_finisher_count = -1
	_enemies.clear()
	_player = null


## Advance the end-of-wave escalation clock. Called once per frame by the wave
## controller, which owns `finishing`; the arithmetic lives here so it can be
## asserted without standing up a whole wave.
##
## Any change in the count is progress and restarts the clock, so a wave that is
## being cleared slowly never escalates - only one that is not being cleared at
## all.
static func tick_finisher(delta: float, finishing: bool, count: int) -> void:
	finisher_mode = finishing
	if not finishing or count != _finisher_count:
		_finisher_count = count
		finisher_stall = 0.0
		hunt_mode = false
		return
	finisher_stall += delta
	hunt_mode = finisher_stall >= Balance.STRAGGLER_HUNT_AFTER


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
		knockback: float = 0.0, falloff: bool = true,
		source: String = SOURCE_OTHER) -> int:
	var hit := 0
	for e: Node2D in enemies_in_radius(center, radius):
		var dist := hit_center(e).distance_to(center)
		var scale := 1.0
		if falloff:
			scale = lerpf(1.0, 0.42, clampf(dist / maxf(radius, 1.0), 0.0, 1.0))
		if e.has_method("take_damage"):
			e.call("take_damage", damage * scale, false, center, knockback, source)
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
static func apply_slow(_host: Node, factor: float, duration: float) -> void:
	# Deepest slow wins, longest duration wins, and it expires on its own clock.
	# This used to be a tween that set enemy_time_scale back to 1.0 no matter
	# what: a second Torpor cast inside the first had the whole world snap back
	# to full speed the moment the first one's tween finished, with seconds
	# still showing on the second. The same shape as the Swift Potion bug.
	enemy_time_scale = minf(enemy_time_scale, factor)
	_slow_left = maxf(_slow_left, duration)


## Ticked from run.gd, beside the combo window, because this is a static and
## has no _process of its own.
static func tick_slow(delta: float) -> void:
	if _slow_left <= 0.0:
		return
	_slow_left = maxf(0.0, _slow_left - delta)
	if _slow_left <= 0.0:
		enemy_time_scale = 1.0
