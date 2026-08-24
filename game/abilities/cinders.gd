extends Node2D
## Cinders: burning ground that ticks damage while enemies stand in it.
##
## The only sustained damage source in the game - everything else is a burst.
## That makes it the ability that rewards funnelling a wave through somewhere
## rather than deleting the front of it, and it is the natural partner for
## Thornwall.

var _life := 5.0
var _radius := 200.0
var _damage := 8.0
var _interval := 0.25
var _tick := 0.0
var _age := 0.0
var _flames: Node2D = null


func setup(at: Vector2, def: Dictionary) -> void:
	global_position = at
	_life = float(def["duration"])
	_radius = float(def["radius"])
	_damage = float(def["damage"])
	_interval = float(def["interval"])
	_tick = _interval

	var ground := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		# A ragged edge, so it reads as a fire and not as a status circle.
		var r := _radius * (0.86 + 0.14 * sin(a * 3.0))
		pts.append(Vector2(cos(a), sin(a)) * r)
	ground.polygon = pts
	ground.color = Color(0.85, 0.35, 0.12, 0.28)
	add_child(ground)

	_flames = Node2D.new()
	add_child(_flames)

	FX.ring(at, _radius, Color(1.0, 0.55, 0.2), 0.4, 0.15)
	Game.shake(2.0, 0.2)


func _process(delta: float) -> void:
	_age += delta
	_life -= delta

	# A few embers licking upward, cheap and pooled through FX.
	if _flames != null and randf() < delta * 14.0:
		var a := randf() * TAU
		var d := sqrt(randf()) * _radius
		FX.impact(global_position + Vector2(cos(a), sin(a)) * d,
			Color(1.0, 0.6 + randf() * 0.3, 0.2, 0.7), 0.5)

	_tick -= delta
	if _tick <= 0.0:
		_tick = _interval
		# No knockback: shoving enemies out of the fire would fight the whole
		# point of a zone that punishes standing in it.
		var hit := Combat.explode(global_position, _radius, _damage, 0.0, false)
		if hit > 0:
			var p := Combat.player()
			if p != null and p.has_method("on_damage_dealt"):
				p.call("on_damage_dealt", _damage * hit)

	if _life <= 0.0:
		set_process(false)
		queue_free()
