extends Node2D
## Thrown grenade. Arcs to the cursor, telegraphs its blast radius while the
## fuse burns, then detonates.
##
## The telegraph is not decoration: the blast is big enough to matter and the
## player needs to know whether they are standing in it.

@onready var _sprite: Sprite2D = $Sprite

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _fuse := 0.75
var _elapsed := 0.0
var _damage := 90.0
var _radius := 190.0
var _armed := false


func throw_to(from: Vector2, to: Vector2, def: Dictionary) -> void:
	_from = from
	_to = to
	_fuse = float(def["fuse"])
	_damage = float(def["damage"])
	_radius = float(def["radius"])
	_elapsed = 0.0
	_armed = true
	global_position = from
	visible = true
	set_process(true)
	_sprite.rotation = 0.0
	FX.telegraph(to, _radius, _fuse, Color(1.0, 0.55, 0.2))


func _process(delta: float) -> void:
	if not _armed:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _fuse, 0.0, 1.0)
	# parabolic arc: linear across the ground, sine hop in height
	global_position = _from.lerp(_to, t) - Vector2(0, sin(t * PI) * 130.0)
	_sprite.rotation += delta * 12.0
	# flash faster as the fuse runs out
	var blink := sin(_elapsed * lerpf(14.0, 46.0, t))
	_sprite.modulate = Color(1, 1, 1) if blink < 0.0 else Color(2.0, 0.6, 0.4)

	if t >= 1.0:
		_detonate()


func _detonate() -> void:
	_armed = false
	set_process(false)
	FX.explosion(_to, _radius)
	Audio.play("explosion", -2.0)
	Game.shake(Balance.SHAKE_EXPLOSION, 0.4)
	var hit := Combat.explode(_to, _radius, _damage, 380.0)
	var p := Combat.player()
	if p != null and p.has_method("on_damage_dealt"):
		p.call("on_damage_dealt", _damage * hit)
	Pools.release(self)


func _pool_reset() -> void:
	_armed = false
	set_process(false)
