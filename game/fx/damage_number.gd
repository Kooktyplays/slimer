extends Node2D
## Floating damage number / pickup text.
##
## Crits are bigger, warmer and pop harder, so the player reads them without
## having to look directly at the number.

@onready var _label: Label = $Label

var _tween: Tween


func play(at: Vector2, amount: float, is_crit: bool) -> void:
	var text := str(int(round(amount)))
	var color := Color(1.0, 0.86, 0.36) if is_crit else Color(1, 1, 1)
	_start(at, text, color, 1.5 if is_crit else 1.0)


func play_text(at: Vector2, text: String, color: Color) -> void:
	_start(at, text, color, 1.15)


func _start(at: Vector2, text: String, color: Color, size: float) -> void:
	global_position = at + Vector2(randf_range(-14, 14), randf_range(-8, 8))
	visible = true
	_label.text = text
	_label.modulate = color
	scale = Vector2.ONE * size
	_label.position = Vector2(-60, -20)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - 62.0, 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	_tween.tween_property(self, "scale", Vector2.ONE * size, 0.18) \
		.from(Vector2.ONE * size * 1.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.34).set_delay(0.41)
	_tween.chain().tween_callback(func() -> void: Pools.release(self))


func _pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
