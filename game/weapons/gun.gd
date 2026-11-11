class_name Gun
extends Node2D
## The player's weapon - a gun or a melee weapon, picked before the run.
##
## There is no weapon inventory mid-run: what you start with is what you
## finish with, and every shop purchase edits the numbers in RunState.gun that
## this node reads through the weapon's lens (WeaponsDB.apply). That's why
## nothing here caches stats: an upgrade takes effect on the very next shot.
##
## Melee weapons reuse the whole pipeline - fire rate is swing rate, damage,
## crit and knockback carry over - but swing instead of shooting: no ammo, no
## reload, and everything in the arc is hit at once.

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
## Frenzy's own clock. It used to live in a tween owned by the ability
## controller, which restored the defaults unconditionally - so a second Frenzy
## cast inside the first had its buff switched off by the first one's callback.
var _frenzy_left := 0.0


func begin_frenzy(multiplier: float, duration: float) -> void:
	fire_rate_multiplier = maxf(fire_rate_multiplier, multiplier)
	free_reloads = true
	_frenzy_left = maxf(_frenzy_left, duration)


func _tick_frenzy(delta: float) -> void:
	if _frenzy_left <= 0.0:
		return
	_frenzy_left = maxf(0.0, _frenzy_left - delta)
	if _frenzy_left <= 0.0:
		fire_rate_multiplier = 1.0
		free_reloads = false

var _cooldown: float = 0.0
var _recoil: float = 0.0

## Where the sprite and muzzle sit when aiming right; mirrored when aiming left.
var _base_offset := Vector2.ZERO
var _base_muzzle := Vector2.ZERO
var _base_sprite_pos := Vector2.ZERO
## Melee swing animation: seconds left, and how long the whole swing takes.
var _swing_left := 0.0
var _swing_time := 0.14
var _swing_arc := 0.0


func _ready() -> void:
	Pools.prewarm(PROJECTILE, 90)
	_base_sprite_pos = _sprite.position
	configure()
	refill()


## The weapon this gun is: the run's pick, or the default outside a run.
func weapon_id() -> String:
	if Game.run != null:
		return WeaponsDB.sanitise(String(Game.run.weapon))
	return WeaponsDB.DEFAULT


func is_melee() -> bool:
	return WeaponsDB.is_melee(weapon_id())


## Dress the node as the current weapon: sprite, grip point and muzzle.
func configure() -> void:
	var def := WeaponsDB.get_def(weapon_id())
	var tex := load(WeaponsDB.sprite_path(weapon_id())) as Texture2D
	if tex == null:
		return
	_sprite.texture = tex
	var grip: Vector2 = def["grip"]
	var muzzle: Vector2 = def["muzzle"]
	# grip pixel on the sprite's origin, so every weapon is held at the hand
	_base_offset = tex.get_size() * 0.5 - grip
	_base_muzzle = muzzle - grip
	_sprite.offset = _base_offset
	_muzzle.position = _base_muzzle


func _stats() -> Dictionary:
	var base: Dictionary = Game.run.gun if Game.run != null else Balance.GUN_BASE
	return WeaponsDB.apply(base, weapon_id())


func magazine_size() -> int:
	if is_melee():
		return 0
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
	# side when aiming left instead of the gun appearing upside down. The grip
	# and muzzle mirror with it, or the hand and the muzzle flash drift off the
	# weapon by the grip's distance from the sprite's centre line.
	var flip := absf(rotation) > PI * 0.5
	_sprite.flip_v = flip
	_sprite.offset.y = -_base_offset.y if flip else _base_offset.y
	_muzzle.position.y = -_base_muzzle.y if flip else _base_muzzle.y


func muzzle_position() -> Vector2:
	return _muzzle.global_position


# ---------------------------------------------------------------------------
# firing
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_tick_frenzy(delta)
	if _cooldown > 0.0:
		_cooldown -= delta
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta * 5.0)
		_sprite.position.x = _base_sprite_pos.x - _recoil * 12.0
	if _swing_left > 0.0:
		_animate_swing(delta)
	if reloading:
		reload_remaining -= delta
		if reload_remaining <= 0.0:
			refill()
			Audio.play("reload_end", -6.0)
			Events.reload_finished.emit()


func can_fire() -> bool:
	if is_melee():
		return _cooldown <= 0.0
	return not reloading and ammo > 0 and _cooldown <= 0.0


## Returns true if a shot (or a swing) actually went out.
func try_fire(direction: Vector2) -> bool:
	if is_melee():
		if _cooldown > 0.0:
			return false
		_swing(direction, _stats())
		return true
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
	var sound := String(WeaponsDB.get_def(weapon_id()).get("sound",
		"shoot_heavy" if heavy else "shoot"))
	Audio.play(sound, -13.0 if sound.begins_with("shoot") else -16.0, 0.18)
	Game.shake(Balance.SHAKE_SHOOT, 0.12)
	Events.shot_fired.emit(muzzle_position(), direction)

	if ammo <= 0:
		start_reload()
	return true


func _spawn_bullets(direction: Vector2, stats: Dictionary) -> void:
	var count := maxi(1, int(round(float(stats["projectile_count"]))))
	var spread_deg := float(stats["spread"])
	var base_angle := direction.angle()
	var shell := float(WeaponsDB.get_def(weapon_id()).get("explode_radius", 0.0))
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
			"color": (Color(1.0, 0.55, 0.25) if shell > 0.0 else Color(1.0, 0.92, 0.55))
				if not crit else Color(1.0, 0.66, 0.30),
			"scale": (1.6 if shell > 0.0 else 1.0) * (1.0 if not crit else 1.25),
			"explode_radius": shell,
		})


func _container() -> Node:
	if bullet_container != null and is_instance_valid(bullet_container):
		return bullet_container
	return get_tree().current_scene


func start_reload() -> void:
	if is_melee():
		return
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


# ---------------------------------------------------------------------------
# melee
# ---------------------------------------------------------------------------
## One swing: everything inside the arc and within reach is hit at once.
##
## Measured from the gun's pivot (the player's hand), against each enemy's
## drawn hit centre and hit radius, so a big slime is caught by the edge of a
## swing the way it looks like it should be.
func _swing(direction: Vector2, stats: Dictionary) -> void:
	var id := weapon_id()
	var def := WeaponsDB.get_def(id)
	var rate := float(stats["fire_rate"]) * fire_rate_multiplier
	_cooldown = 1.0 / maxf(rate, 0.1)
	var reach := WeaponsDB.reach(id, stats)
	var arc := WeaponsDB.arc(id, stats)
	var angle := direction.angle()
	var origin := global_position
	var thrust := bool(def.get("thrust", false))
	var heavy := bool(def.get("heavy", false))

	var hits := 0
	var any_crit := false
	for e: Node2D in Combat.enemies():
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var c := Combat.hit_center(e)
		var to := c - origin
		var r := float(e.get("hit_radius")) if e.get("hit_radius") != null else 24.0
		var dist := to.length()
		if dist > reach + r:
			continue
		# inside the arc, or so close the body overlaps the hand anyway
		if dist > r and absf(angle_difference(angle, to.angle())) > arc * 0.5 + asin(clampf(r / dist, 0.0, 1.0)):
			continue
		var crit := randf() < float(stats["crit_chance"])
		var dmg := float(stats["damage"]) * (float(stats["crit_damage"]) if crit else 1.0)
		e.call("take_damage", dmg, crit, c, float(stats["knockback"]), Combat.SOURCE_MELEE)
		FX.impact(c, Color(1, 1, 1) if not crit else Color(1.0, 0.85, 0.4), 1.0)
		any_crit = any_crit or crit
		hits += 1

	FX.slash(origin, angle, arc, reach,
		Color(1.0, 0.95, 0.8) if not heavy else Color(1.0, 0.8, 0.5), thrust)
	Audio.play("dash", -15.0 if not heavy else -11.0, 0.2)
	if hits > 0:
		if heavy:
			Audio.play_throttled("boss_move_slam", 0.1, -12.0, 0.15)
		elif any_crit:
			Audio.play_throttled("crit", 0.05, -10.0, 0.22)
		else:
			Audio.play_throttled("hit", 0.045, -11.0, 0.24)
	Game.shake(Balance.SHAKE_SHOOT * (3.5 if heavy else 1.4), 0.14 if heavy else 0.1)
	Events.shot_fired.emit(muzzle_position(), direction)

	_swing_time = clampf(_cooldown * 0.6, 0.08, 0.22)
	_swing_left = _swing_time
	_swing_arc = arc


## The weapon follows its own cut: a sweep through the arc, or a jab out and
## back for a thrust.
func _animate_swing(delta: float) -> void:
	_swing_left = maxf(0.0, _swing_left - delta)
	var p := 1.0 - _swing_left / maxf(_swing_time, 0.001)
	var def := WeaponsDB.get_def(weapon_id())
	if bool(def.get("thrust", false)):
		_sprite.rotation = 0.0
		_sprite.position.x = _base_sprite_pos.x + sin(p * PI) * 34.0
	else:
		var eased := 1.0 - pow(1.0 - p, 3.0)
		var half := minf(_swing_arc, PI * 1.2) * 0.5
		var dir := -1.0 if _sprite.flip_v else 1.0
		_sprite.rotation = dir * lerpf(-half, half, eased)
		if _swing_left <= 0.0:
			_sprite.rotation = 0.0
	if _swing_left <= 0.0:
		_sprite.position.x = _base_sprite_pos.x
