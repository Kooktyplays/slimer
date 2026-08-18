extends Node2D
## Two jobs, one pooled node:
##
##   play()           - a ring that snaps outward and fades. Explosions, nova,
##                      boss slams: "this just happened, here".
##   play_telegraph() - a ground marker that fills from the centre outward over
##                      the wind-up time. "This is about to happen, here."
##
## Keeping them the same node keeps the visual language consistent: the
## telegraph's final size is exactly the ring the hit will draw.

@onready var _ring: Sprite2D = $Ring
@onready var _fill: Sprite2D = $Fill

var _tween: Tween
const RING_TEXTURE_RADIUS := 80.0     # ring.png is 160px across
const GLOW_TEXTURE_RADIUS := 64.0     # glow.png is 128px across


func play(at: Vector2, radius: float, color: Color, duration: float,
		expand_from: float) -> void:
	global_position = at
	visible = true
	_fill.visible = false
	_ring.visible = true
	_ring.modulate = color
	_ring.modulate.a = 0.95

	var target := radius / RING_TEXTURE_RADIUS
	_kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_ring, "scale", Vector2.ONE * target, duration) \
		.from(Vector2.ONE * target * expand_from) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_ring, "modulate:a", 0.0, duration) \
		.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void: Pools.release(self))


func play_telegraph(at: Vector2, radius: float, color: Color, duration: float) -> void:
	global_position = at
	visible = true
	_ring.visible = true
	_fill.visible = true

	var ring_scale := radius / RING_TEXTURE_RADIUS
	var fill_scale := radius / GLOW_TEXTURE_RADIUS
	_ring.scale = Vector2.ONE * ring_scale
	_ring.modulate = Color(color.r, color.g, color.b, 0.85)
	_fill.modulate = Color(color.r, color.g, color.b, 0.0)
	_fill.scale = Vector2.ZERO

	_kill()
	_tween = create_tween().set_parallel(true)
	# fill grows to meet the ring exactly as the attack lands
	_tween.tween_property(_fill, "scale", Vector2.ONE * fill_scale, duration)
	_tween.tween_property(_fill, "modulate:a", 0.42, duration * 0.7)
	_tween.tween_property(_ring, "modulate:a", 0.15, duration * 0.9) \
		.from(0.85).set_delay(duration * 0.1)
	_tween.chain().tween_callback(func() -> void: Pools.release(self))


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _pool_reset() -> void:
	_kill()
	_fill.visible = false
