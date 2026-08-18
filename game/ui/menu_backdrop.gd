extends Node2D
## Slimes bobbing across the menu background.
##
## Purely decorative, but it does one useful job: it shows the six enemy
## colours on the title screen, so the colour language is familiar before the
## first wave rather than something to decode mid-fight.

const SPEED := 26.0

var _slimes: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	# The background ColorRect is a sibling added before this node, so drawing
	# order alone puts these on top; a negative z_index would hide them behind
	# it entirely.
	z_index = 0
	var viewport := get_viewport_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260815
	for i in EnemyTypes.ORDER.size() * 2:
		var id: String = EnemyTypes.ORDER[i % EnemyTypes.ORDER.size()]
		var s := Sprite2D.new()
		s.texture = load(EnemyTypes.texture_path(id))
		s.modulate.a = 0.30
		var scale := rng.randf_range(0.5, 1.3)
		s.scale = Vector2.ONE * scale
		s.position = Vector2(
			rng.randf_range(-200.0, viewport.x + 200.0),
			rng.randf_range(60.0, viewport.y - 40.0))
		add_child(s)
		_slimes.append({
			"node": s,
			"speed": SPEED * rng.randf_range(0.4, 1.5) * (1.0 if i % 2 == 0 else -1.0),
			"phase": rng.randf() * TAU,
			"base_y": s.position.y,
			"scale": scale,
		})


func _process(delta: float) -> void:
	_time += delta
	var width := get_viewport_rect().size.x
	for s: Dictionary in _slimes:
		var node: Sprite2D = s["node"]
		node.position.x += float(s["speed"]) * delta
		if node.position.x < -240.0:
			node.position.x = width + 240.0
		elif node.position.x > width + 240.0:
			node.position.x = -240.0
		var bounce := absf(sin(_time * 2.2 + float(s["phase"])))
		node.position.y = float(s["base_y"]) - bounce * 16.0
		var sc: float = float(s["scale"])
		node.scale = Vector2(sc * (1.0 + bounce * 0.06), sc * (1.0 - bounce * 0.06))
