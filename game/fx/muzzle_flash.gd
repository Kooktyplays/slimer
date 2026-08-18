extends Node2D
## Muzzle flash, reusing the pack's original tween (kick forward, scale up,
## fade) with pooling instead of queue_free.

@onready var _sprite: Sprite2D = $Sprite

var _tween: Tween


func play(at: Vector2, angle: float) -> void:
	global_position = at
	rotation = angle
	visible = true
	_sprite.position = Vector2.ZERO
	_sprite.modulate.a = 1.0

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_sprite, "position:x", 16.0, 0.25)
	_tween.tween_property(_sprite, "scale", Vector2.ONE * 1.25, 0.25).from(Vector2.ONE * 0.7)
	_tween.tween_property(_sprite, "modulate:a", 0.0, 0.25).set_delay(0.1)
	_tween.chain().tween_callback(func() -> void: Pools.release(self))


func _pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
