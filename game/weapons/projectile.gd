extends Area2D
## Pooled bullet, used by both the player and by enemies.
##
## Collision is a swept shape query done by hand, not Area2D's body_entered
## signal. The signal only fires when a body *enters* the area, which misses
## two cases that happen constantly:
##
##   * point blank - a bullet spawned already overlapping an enemy never
##     "enters" it, so the shot visibly passes through something touching you
##   * fast bullets - with projectile-speed upgrades a bullet can move further
##     in one physics step than an enemy is wide, and step straight over it
##
## Sampling the bullet's circle along the segment it travels each frame fixes
## both, and also removes the deferred-monitoring dance that signal-time
## despawning needed.

## Distance between samples along the swept path. A target is only missed if
## it fits entirely between two samples without touching either, which needs a
## gap above 2 * (bullet radius + target radius); the smallest enemy radius is
## 25, so 28 leaves a wide margin.
const SAMPLE_STEP := 28.0
const MAX_SAMPLES := 12

@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionShape2D = $Shape

var velocity := Vector2.ZERO
var damage := 10.0
var is_crit := false
var pierce := 0
var knockback := 0.0
var max_range := 900.0
var from_player := true
## Torpor's slow. Enemy bullets read Combat.enemy_time_scale live each frame -
## this used to be a plain field that nothing ever wrote, so Torpor slowed enemy
## *bodies* while their bullets kept full speed, and the ability's own
## description ("slow every enemy and enemy bullet") was simply false.
var slow_factor := 1.0

var _travelled := 0.0
var _hit: Array[RID] = []
var _alive := false
var _radius := 7.0
var _query := PhysicsShapeQueryParameters2D.new()
var _query_shape := CircleShape2D.new()


func _ready() -> void:
	# The area itself never monitors; the sweep below does all the work.
	monitoring = false
	monitorable = false
	_query.shape = _query_shape
	# Actors are hit through a Hurtbox Area2D that covers the drawn sprite, not
	# through their CharacterBody2D - the body's shape sits at the feet, where
	# the shadow is, which is why shots aimed at a slime used to sail through it.
	# Bodies still matter for the forest's static geometry.
	_query.collide_with_areas = true
	_query.collide_with_bodies = true


func launch(at: Vector2, dir: Vector2, cfg: Dictionary) -> void:
	global_position = at
	damage = float(cfg.get("damage", 10.0))
	is_crit = bool(cfg.get("crit", false))
	pierce = int(cfg.get("pierce", 0))
	knockback = float(cfg.get("knockback", 0.0))
	max_range = float(cfg.get("range", 900.0))
	from_player = bool(cfg.get("from_player", true))
	velocity = dir.normalized() * float(cfg.get("speed", 900.0))
	slow_factor = 1.0

	rotation = velocity.angle()
	_travelled = 0.0
	_hit.clear()
	_alive = true
	visible = true
	set_physics_process(true)

	var scale_factor := float(cfg.get("scale", 1.0))
	var tint: Color = cfg.get("color", Color.WHITE)
	_sprite.modulate = tint
	_sprite.scale = Vector2.ONE * scale_factor
	_radius = 7.0 * scale_factor
	(_shape.shape as CircleShape2D).radius = _radius
	_query_shape.radius = _radius

	if from_player:
		collision_layer = Layers.PLAYER_BULLET
		_query.collision_mask = Layers.ENEMY | Layers.WORLD
	else:
		collision_layer = Layers.ENEMY_BULLET
		_query.collision_mask = Layers.PLAYER | Layers.WORLD
	collision_mask = _query.collision_mask

	# Check the spawn point itself before moving. This is the point-blank fix:
	# an enemy already touching the muzzle gets hit by the first shot rather
	# than by nothing at all.
	_sweep(global_position, global_position)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	# Your own bullets are never slowed - Torpor is a debuff on the forest, not
	# a global time scale.
	slow_factor = 1.0 if from_player else Combat.enemy_time_scale
	var step := velocity * delta * slow_factor
	var to := global_position + step
	_sweep(global_position, to)
	if not _alive:
		return
	global_position = to
	_travelled += step.length()
	if _travelled >= max_range:
		_expire()


## Walk the bullet's circle along `from` -> `to`, resolving the first thing it
## touches at each sample.
func _sweep(from: Vector2, to: Vector2) -> void:
	var world := get_world_2d()
	if world == null:
		return
	var space := world.direct_space_state
	var distance := from.distance_to(to)
	var samples := clampi(int(ceil(distance / SAMPLE_STEP)), 0, MAX_SAMPLES)

	for i in range(samples + 1):
		var t := 0.0 if samples == 0 else float(i) / samples
		_query.transform = Transform2D(0.0, from.lerp(to, t))
		_query.exclude = _hit
		var results := space.intersect_shape(_query, 8)
		for result: Dictionary in results:
			var body: Object = result.get("collider")
			if body == null:
				continue
			if _resolve(body, result.get("rid"), _query.transform.origin):
				return          # bullet died on this hit


## Returns true if the bullet should stop here.
func _resolve(collider: Object, rid: RID, at: Vector2) -> bool:
	# A hurtbox is an Area2D whose owner is the actor that takes the damage.
	var body: Object = collider
	if collider is Area2D:
		body = (collider as Area2D).get_parent()
		if body == null:
			return false
	if body is StaticBody2D:
		FX.impact(at, Color(0.85, 0.85, 0.8, 0.8), 0.7)
		Audio.play_throttled("hit", 0.05, -16.0, 0.12)
		_expire()
		return true

	if not body.has_method("take_damage"):
		return false
	_hit.append(rid)

	body.call("take_damage", damage, is_crit, at, knockback)
	FX.impact(at, Color(1, 1, 1) if not is_crit else Color(1.0, 0.85, 0.4), 0.85)
	if is_crit:
		Audio.play_throttled("crit", 0.05, -10.0, 0.12)
	else:
		Audio.play_throttled("hit", 0.045, -13.0, 0.14)

	if _hit.size() > pierce:
		_expire()
		return true
	return false


func _expire() -> void:
	if not _alive:
		return
	_alive = false
	set_physics_process(false)
	Pools.release(self)


func _pool_reset() -> void:
	_alive = false
	velocity = Vector2.ZERO
	_hit.clear()
	set_physics_process(false)
