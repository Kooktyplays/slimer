extends Node2D
## Bullet impact puff. Keeps the choreography from the asset pack's original
## impact.gd (pop out, fade fast) but parks itself in the pool instead of
## calling queue_free, so a firefight doesn't allocate.

@onready var _sprite: Sprite2D = $Sprite

var _tween: Tween


func play(at: Vector2, color: Color, size: float) -> void:
	global_position = at
	visible = true
	_sprite.modulate = color
	_sprite.rotation = randf() * TAU

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sprite, "scale", Vector2.ONE * 1.35 * size, 0.3) \
		.from(Vector2.ONE * 0.6 * size)
	_tween.tween_property(_sprite, "modulate:a", 0.0, 0.15).set_delay(0.15)
	_tween.chain().tween_callback(func() -> void: Pools.release(self))


func _pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
