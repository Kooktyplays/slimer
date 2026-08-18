class_name GameCamera
extends Camera2D
## Follow camera with trauma-based shake and a small aim lead.
##
## Shake uses a trauma value that decays and is applied as trauma-squared, so
## small hits barely register and big ones land hard - a linear shake either
## feels mushy on impacts or unreadable on chip damage. Offsets are also
## clamped, because the brief for this game explicitly asks that screen shake
## never make combat hard to read.

const MAX_OFFSET := Vector2(26.0, 22.0)
const MAX_ROLL := 0.035
const DECAY := 1.9
const LOOK_AHEAD := 0.16
const LOOK_AHEAD_MAX := 190.0

var trauma := 0.0
var enabled_look_ahead := true

var _noise_seed := 0.0
var _look := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	ignore_rotation = false
	_noise_seed = randf() * 1000.0
	Events.screen_shake.connect(add_trauma)


func _process(delta: float) -> void:
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - DECAY * delta)

	# lead the camera towards where the player is aiming, so more of the
	# screen ahead of the cursor is visible
	var target_look := Vector2.ZERO
	if enabled_look_ahead:
		var to_mouse := get_global_mouse_position() - global_position
		target_look = to_mouse * LOOK_AHEAD
		if target_look.length() > LOOK_AHEAD_MAX:
			target_look = target_look.normalized() * LOOK_AHEAD_MAX
	_look = _look.lerp(target_look, 1.0 - pow(0.001, delta))

	var shake := trauma * trauma
	_noise_seed += delta * 34.0
	var shake_offset := Vector2(
		sin(_noise_seed * 1.37) * MAX_OFFSET.x,
		cos(_noise_seed * 1.71) * MAX_OFFSET.y) * shake
	offset = _look + shake_offset
	rotation = sin(_noise_seed * 0.93) * MAX_ROLL * shake


## `strength` is in the same units as the Balance.SHAKE_* constants.
func add_trauma(strength: float, _duration: float = 0.25) -> void:
	trauma = minf(1.0, trauma + strength / Balance.SHAKE_MAX)


## Frame the camera on a boss entrance, then hand control back.
func focus_on(target: Vector2, duration: float) -> void:
	enabled_look_ahead = false
	var original := position_smoothing_speed
	position_smoothing_speed = 2.5
	var holder := get_parent() as Node2D
	if holder == null:
		return
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		offset = _look.lerp(target - global_position, v), 0.0, 1.0, duration * 0.35)
	t.tween_interval(duration * 0.3)
	t.tween_method(func(v: float) -> void:
		offset = (target - global_position).lerp(Vector2.ZERO, v), 0.0, 1.0, duration * 0.35)
	t.tween_callback(func() -> void:
		enabled_look_ahead = true
		position_smoothing_speed = original)
