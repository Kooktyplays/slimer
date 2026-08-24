extends Node2D
## Thornwall: a temporary barrier that actually blocks.
##
## Everything else in the game that "controls" enemies steers them - this is the
## only thing that stops them. It works because of an existing quirk of the
## collision setup: enemies, the player and enemy bullets all mask
## `Layers.WORLD` and nothing else, so a StaticBody2D on the world layer is
## indistinguishable from a tree as far as the whole cast is concerned.
##
## It blocks the player too. That is the trade, not an oversight: a wall you can
## walk through is just a slow.

const THICKNESS := 34.0

var _life := 6.0
var _length := 260.0
var _body: StaticBody2D = null
var _fill: Polygon2D = null


func setup(at: Vector2, angle: float, def: Dictionary) -> void:
	global_position = at
	rotation = angle
	_life = float(def["duration"])
	_length = float(def["length"])

	_body = StaticBody2D.new()
	_body.collision_layer = Layers.WORLD
	_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_length, THICKNESS)
	shape.shape = rect
	_body.add_child(shape)
	add_child(_body)

	var half := Vector2(_length, THICKNESS) * 0.5
	_fill = Polygon2D.new()
	_fill.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	_fill.color = Color(0.35, 0.62, 0.30)
	add_child(_fill)

	# Thorns along the top edge, so it reads as growth rather than masonry.
	var spikes := Polygon2D.new()
	var pts := PackedVector2Array()
	var count := int(_length / 26.0)
	for i in count:
		var x := -half.x + (float(i) + 0.5) * (_length / float(count))
		pts.append(Vector2(x - 9.0, -half.y))
		pts.append(Vector2(x, -half.y - 17.0))
		pts.append(Vector2(x + 9.0, -half.y))
	spikes.polygon = pts
	spikes.color = Color(0.28, 0.5, 0.24)
	add_child(spikes)

	# Grow out of the ground rather than appearing, so the player can see the
	# footprint before it is solid.
	scale = Vector2(1.0, 0.1)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FX.ring(at, _length * 0.5, Color(0.5, 0.8, 0.4), 0.35, 0.15)


func _process(delta: float) -> void:
	_life -= delta
	# Fade the last second so nobody is surprised by the gap reopening.
	if _life < 1.0:
		modulate.a = 0.35 + 0.65 * absf(sin(_life * 14.0))
	if _life <= 0.0:
		set_process(false)
		FX.burst(global_position, Color(0.4, 0.7, 0.35), 12, 1.0)
		queue_free()
