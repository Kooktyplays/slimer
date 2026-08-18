extends Node2D
## Satellites: orbs that circle the player and damage what they touch.
##
## Each orb keeps its own short per-enemy hit cooldown rather than a global
## one, so three orbs sweeping the same crowd deal three separate ticks
## instead of silently swallowing two of them.

const HIT_COOLDOWN := 0.45
const ORB_RADIUS := 34.0

var _player: Node2D = null
var _orbs: Array[Sprite2D] = []
var _damage := 26.0
var _orbit_radius := 150.0
var _angle := 0.0
var _life := 12.0
var _cooldowns: Dictionary = {}     # enemy instance id -> seconds remaining


func setup(player: Node2D, def: Dictionary) -> void:
	_player = player
	_damage = float(def["damage"])
	_orbit_radius = float(def["radius"])
	_life = float(def["duration"])
	var count := int(def["count"])
	var tex: Texture2D = preload("res://assets/sprites/gen/orb.png")

	for i in count:
		var s := Sprite2D.new()
		s.texture = tex
		s.modulate = Color(0.65, 0.85, 1.0)
		s.scale = Vector2.ONE * 1.5
		s.z_index = 48
		add_child(s)
		_orbs.append(s)
	_update_positions()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return

	_life -= delta
	if _life <= 0.0:
		_fade_out()
		return

	_angle += delta * 2.6
	global_position = _player.global_position
	_update_positions()

	for key: int in _cooldowns.keys():
		_cooldowns[key] = float(_cooldowns[key]) - delta
		if float(_cooldowns[key]) <= 0.0:
			_cooldowns.erase(key)

	_check_hits()


func _update_positions() -> void:
	var n := _orbs.size()
	for i in n:
		var a := _angle + TAU * i / n
		_orbs[i].position = Vector2(cos(a), sin(a) * 0.62) * _orbit_radius
		# orbs behind the player draw under them, in front draw over
		_orbs[i].z_index = 48 if sin(a) > 0.0 else 30


func _check_hits() -> void:
	var total := 0.0
	for orb: Sprite2D in _orbs:
		for e: Node2D in Combat.enemies_in_radius(orb.global_position, ORB_RADIUS + 26.0):
			var key := e.get_instance_id()
			if _cooldowns.has(key):
				continue
			_cooldowns[key] = HIT_COOLDOWN
			if e.has_method("take_damage"):
				e.call("take_damage", _damage, false, orb.global_position, 140.0)
				total += _damage
			FX.impact(orb.global_position, Color(0.7, 0.9, 1.0), 0.7)
	if total > 0.0 and _player.has_method("on_damage_dealt"):
		_player.call("on_damage_dealt", total)


func _fade_out() -> void:
	set_process(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)
