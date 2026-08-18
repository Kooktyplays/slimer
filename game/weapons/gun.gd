class_name Gun
extends Node2D
## The player's one gun.
##
## There is no weapon inventory in this game - the gun the player starts with
## is the gun they finish with, and every shop purchase edits the numbers in
## RunState.gun that this node reads. That's why nothing here caches stats:
## an upgrade takes effect on the very next shot.

const PROJECTILE := preload("res://weapons/projectile.tscn")

signal ammo_changed(current: int, magazine: int)

@onready var _sprite: Sprite2D = $Sprite
@onready var _muzzle: Marker2D = $Sprite/Muzzle

var bullet_container: Node = null

var ammo: int = 0
var reloading: bool = false
var reload_remaining: float = 0.0

## Set by the Frenzy ability.
var fire_rate_multiplier: float = 1.0
var free_reloads: bool = false

var _cooldown: float = 0.0
var _recoil: float = 0.0


func _ready() -> void:
	Pools.prewarm(PROJECTILE, 90)
	refill()


func _stats() -> Dictionary:
	return Game.run.gun if Game.run != null else Balance.GUN_BASE


func magazine_size() -> int:
	return maxi(1, int(round(float(_stats()["magazine"]))))


func refill() -> void:
	ammo = magazine_size()
	reloading = false
	reload_remaining = 0.0
	ammo_changed.emit(ammo, magazine_size())


# ---------------------------------------------------------------------------
# aiming
# ---------------------------------------------------------------------------
func aim_at(target: Vector2) -> void:
	var dir := (target - global_position)
	if dir.length_squared() < 1.0:
		return
	rotation = dir.angle()
	# flip the sprite rather than the node, so the barrel stays on the correct
	# side when aiming left instead of the gun appearing upside down
	_sprite.flip_v = absf(rotation) > PI * 0.5


func muzzle_position() -> Vector2:
	return _muzzle.global_position


# ---------------------------------------------------------------------------
# firing
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta * 5.0)
		_sprite.position.x = -_recoil * 12.0
	if reloading:
		reload_remaining -= delta
		if reload_remaining <= 0.0:
			refill()
			Audio.play("reload_end", -6.0)
			Events.reload_finished.emit()


func can_fire() -> bool:
	return not reloading and ammo > 0 and _cooldown <= 0.0


## Returns true if a shot actually went out.
func try_fire(direction: Vector2) -> bool:
	if reloading:
		return false
	if ammo <= 0:
		start_reload()
		return false
	if _cooldown > 0.0:
		return false

	var stats := _stats()
	var rate := float(stats["fire_rate"]) * fire_rate_multiplier
	_cooldown = 1.0 / maxf(rate, 0.1)
	ammo -= 1
	ammo_changed.emit(ammo, magazine_size())

	_spawn_bullets(direction, stats)

	_recoil = 1.0
	FX.muzzle_flash(muzzle_position(), rotation)
	# Quiet, with wide pitch variance. This sample plays up to eighteen times a
	# second on a fully upgraded gun, and at the original level and jitter it
	# became a drone within one wave.
	var heavy := float(stats["damage"]) >= 30.0
	Audio.play("shoot_heavy" if heavy else "shoot", -13.0, 0.18)
	Game.shake(Balance.SHAKE_SHOOT, 0.12)
	Events.shot_fired.emit(muzzle_position(), direction)

	if ammo <= 0:
		start_reload()
	return true


func _spawn_bullets(direction: Vector2, stats: Dictionary) -> void:
	var count := maxi(1, int(round(float(stats["projectile_count"]))))
	var spread_deg := float(stats["spread"])
	var base_angle := direction.angle()
	# Multi-shot fans out over a widened arc, so extra projectiles are real
	# coverage rather than three bullets stacked on one pixel.
	var arc := deg_to_rad(spread_deg * 2.0 + (count - 1) * 5.5)

	for i in count:
		var t := 0.0 if count == 1 else (float(i) / (count - 1)) - 0.5
		var angle := base_angle + t * arc + deg_to_rad(randf_range(-spread_deg, spread_deg)) * 0.5
		var crit := randf() < float(stats["crit_chance"])
		var dmg := float(stats["damage"])
		if crit:
			dmg *= float(stats["crit_damage"])

		var b := Pools.acquire(PROJECTILE, _container()) as Node2D
		b.call("launch", muzzle_position(), Vector2.RIGHT.rotated(angle), {
			"damage": dmg,
			"crit": crit,
			"pierce": int(round(float(stats["penetration"]))),
			"knockback": float(stats["knockback"]),
			"range": float(stats["range"]),
			"speed": float(stats["projectile_speed"]),
			"from_player": true,
			"color": Color(1.0, 0.92, 0.55) if not crit else Color(1.0, 0.66, 0.30),
			"scale": 1.0 if not crit else 1.25,
		})


func _container() -> Node:
	if bullet_container != null and is_instance_valid(bullet_container):
		return bullet_container
	return get_tree().current_scene


func start_reload() -> void:
	if reloading or ammo == magazine_size():
		return
	if free_reloads:
		refill()
		return
	reloading = true
	reload_remaining = float(_stats()["reload_time"])
	Audio.play("reload_start", -8.0)
	Events.reload_started.emit(reload_remaining)


func reload_fraction() -> float:
	if not reloading:
		return 1.0
	var total := float(_stats()["reload_time"])
	return 1.0 - clampf(reload_remaining / maxf(total, 0.01), 0.0, 1.0)
