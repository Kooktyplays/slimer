extends Node2D
## Effigy: a lure that enemies attack instead of the player, then bursts.
##
## Enemies read `Combat.player()` for their target, so the decoy works by
## registering itself in the `decoy` group; enemy AI checks that group first
## and prefers a decoy inside its taunt range. That keeps the redirection in
## one place instead of teaching every behaviour about lures.

@onready var _sprite: Sprite2D = $Sprite

var taunt_range := 620.0
var _life := 7.0
var _burst_damage := 60.0
var _burst_radius := 200.0
var _bob := 0.0


func setup(at: Vector2, def: Dictionary) -> void:
	global_position = at
	_life = float(def["duration"])
	_burst_damage = float(def["burst_damage"])
	_burst_radius = float(def["burst_radius"])
	taunt_range = float(def["taunt_range"])
	add_to_group("decoy")
	FX.ring(at, 140.0, Color(0.8, 0.8, 1.0), 0.4, 0.2)


func _process(delta: float) -> void:
	_life -= delta
	_bob += delta * 5.0
	_sprite.position.y = sin(_bob) * 5.0
	_sprite.scale = Vector2(1.0 - sin(_bob) * 0.05, 1.0 + sin(_bob) * 0.05) * 0.9
	# flash out as it expires so the burst isn't a surprise
	if _life < 1.2:
		_sprite.modulate.a = 0.4 + 0.6 * absf(sin(_life * 16.0))
	if _life <= 0.0:
		_burst()


func _burst() -> void:
	set_process(false)
	remove_from_group("decoy")
	FX.explosion(global_position, _burst_radius, Color(0.75, 0.8, 1.0))
	Audio.play("explosion", -6.0)
	Game.shake(4.0, 0.3)
	var hit := Combat.explode(global_position, _burst_radius, _burst_damage, 300.0)
	var p := Combat.player()
	if p != null and p.has_method("on_damage_dealt"):
		p.call("on_damage_dealt", _burst_damage * hit)
	queue_free()


## Nearest decoy to `from` that is within its own taunt range.
static func find_for(from: Vector2, tree: SceneTree) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for node: Node in tree.get_nodes_in_group("decoy"):
		var d2 := (node as Node2D).global_position
		var dist := d2.distance_to(from)
		if dist <= float(node.get("taunt_range")) and dist < best_d:
			best_d = dist
			best = node as Node2D
	return best
