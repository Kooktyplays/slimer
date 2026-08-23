class_name Forest
extends Node2D
## Turns a ForestGenerator layout into actual nodes.
##
## Node layout it creates:
##   Ground   - textured polygons for floor, clearings, paths and ponds
##   Sorted   - y-sorted; props live here and so do all the actors, because
##              they have to sort against each other for the player to walk
##              behind a tree
##   Ambience - falling leaves and drifting motes
##
## Collision is one StaticBody2D holding every blocker shape. Hundreds of
## separate bodies would be hundreds of physics objects for no benefit; a
## single body with many static circle shapes goes into the same broadphase
## and costs far less to set up.

const SWAY_SHADER := preload("res://assets/shaders/sway.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")

const TEX_GRASS := preload("res://assets/sprites/gen/ground_grass.png")
const TEX_CLEARING := preload("res://assets/sprites/gen/ground_clearing.png")
const TEX_PATH := preload("res://assets/sprites/gen/ground_path.png")
const TEX_WATER := preload("res://assets/sprites/gen/ground_water.png")
const TEX_LEAF := [
	preload("res://assets/sprites/gen/leaf_0.png"),
	preload("res://assets/sprites/gen/leaf_1.png"),
	preload("res://assets/sprites/gen/leaf_2.png"),
]

var layout: ForestGenerator = null
var sorted_layer: Node2D
var ground_layer: Node2D
var ambience_layer: Node2D

var _sway_materials: Dictionary = {}    # bucketed strength -> ShaderMaterial
var _texture_cache: Dictionary = {}


func _ready() -> void:
	y_sort_enabled = false


## Build the whole forest for `seed_value`. Returns the layout so the run
## controller can read spawn points out of it.
func build(seed_value: int) -> ForestGenerator:
	_clear()
	layout = ForestGenerator.generate(seed_value)
	if not layout.failure.is_empty():
		push_warning("Slimer: forest generation degraded - %s" % layout.failure)

	ground_layer = Node2D.new()
	ground_layer.name = "Ground"
	ground_layer.z_index = -50
	ground_layer.y_sort_enabled = false
	add_child(ground_layer)

	sorted_layer = Node2D.new()
	sorted_layer.name = "Sorted"
	sorted_layer.y_sort_enabled = true
	add_child(sorted_layer)

	ambience_layer = Node2D.new()
	ambience_layer.name = "Ambience"
	ambience_layer.z_index = 40
	add_child(ambience_layer)

	_build_ground()
	_build_props()
	_build_collision()
	_build_ambience()
	return layout


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_sway_materials.clear()


# ---------------------------------------------------------------------------
# ground
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	# Base floor - one repeating sprite stretched over the world, and then some.
	#
	# It used to stop exactly at WORLD_SIZE, so anything the camera showed past
	# the arena edge was unpainted viewport: the grey players reported falling
	# into. The wall now stops them well inside this, but the camera still looks
	# past the edge when you fight along it, and grass is what should be there.
	#
	# The region origin is offset to match, so the tiling stays aligned to world
	# coordinates and the extension does not seam against the rest of the ground.
	var over := ForestGenerator.OVERDRAW
	var base := Sprite2D.new()
	base.texture = TEX_GRASS
	base.centered = false
	base.position = Vector2(-over, -over)
	base.region_enabled = true
	base.region_rect = Rect2(Vector2(-over, -over),
		ForestGenerator.WORLD_SIZE + Vector2(over, over) * 2.0)
	base.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground_layer.add_child(base)

	# paths first, so clearings paint over where they meet
	for seg: Dictionary in layout._path_segments:
		var a: Vector2 = layout.clearings[seg["a"]]["center"]
		var b: Vector2 = layout.clearings[seg["b"]]["center"]
		ground_layer.add_child(_path_polygon(a, b, ForestGenerator.PATH_WIDTH))

	for c: Dictionary in layout.clearings:
		ground_layer.add_child(_blob_polygon(
			c["center"], float(c["radius"]), TEX_CLEARING, 0.10, 3))

	for pond: Dictionary in layout.ponds:
		var water := _blob_polygon(
			pond["center"], float(pond["radius"]), TEX_WATER, 0.13, 5)
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		water.material = mat
		ground_layer.add_child(water)


## An irregular disc. Perfect circles read as obviously procedural, and a
## little wobble is the difference between "a clearing" and "a stamp".
func _blob_polygon(center: Vector2, radius: float, tex: Texture2D,
		wobble: float, seed_offset: int) -> Polygon2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_value + int(center.x) * 31 + int(center.y) * 17 + seed_offset
	var pts := PackedVector2Array()
	var steps := 34
	var h1 := rng.randf() * TAU
	var h2 := rng.randf() * TAU
	for i in steps:
		var a := TAU * i / steps
		var r := radius * (1.0 + wobble * (sin(a * 3.0 + h1) * 0.6 + sin(a * 5.0 + h2) * 0.4))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.texture = tex
	# empty uv array makes Polygon2D use vertex positions as texture coords,
	# so every polygon tiles in world space and none of them seam against
	# the base floor
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return poly


func _path_polygon(a: Vector2, b: Vector2, width: float) -> Polygon2D:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * width * 0.5
	var pts := PackedVector2Array()
	var steps := 12
	# ragged edges on both sides so roads look worn rather than extruded
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_value + int(a.x + b.y)
	for i in range(steps + 1):
		var t := float(i) / steps
		var w := 1.0 + rng.randf_range(-0.16, 0.16)
		pts.append(a.lerp(b, t) + n * w)
	for i in range(steps, -1, -1):
		var t := float(i) / steps
		var w := 1.0 + rng.randf_range(-0.16, 0.16)
		pts.append(a.lerp(b, t) - n * w)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.texture = TEX_PATH
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return poly


# ---------------------------------------------------------------------------
# props
# ---------------------------------------------------------------------------
func _build_props() -> void:
	for prop: Dictionary in layout.props:
		var id: String = prop["id"]
		var def := PropCatalog.get_def(id)
		var sprite := Sprite2D.new()
		sprite.texture = _texture_for(id)
		sprite.position = prop["pos"]
		sprite.scale = Vector2.ONE * float(prop["scale"])
		sprite.flip_h = bool(prop["flip"])
		# anchor the sprite so its base sits on the ground point, which is also
		# what y-sorting compares
		sprite.offset = Vector2(0, -sprite.texture.get_height() * 0.5 + float(def["anchor"]))
		var sway := float(def.get("sway", 0.0))
		if sway > 0.01:
			sprite.material = _sway_material(sway)
		if def.get("layer", "") == "detail":
			sprite.z_index = -20      # under actors, never sorted against them
			sprite.y_sort_enabled = false
			ground_layer.add_child(sprite)
		else:
			sorted_layer.add_child(sprite)


func _texture_for(id: String) -> Texture2D:
	if not _texture_cache.has(id):
		_texture_cache[id] = load(PropCatalog.texture_path(id))
	return _texture_cache[id]


## One material per rounded sway strength, shared by every prop in that
## bucket. Phase comes from world position inside the shader, so sharing a
## material does not make them move in lockstep.
func _sway_material(strength: float) -> ShaderMaterial:
	var key := snappedf(strength, 0.1)
	if _sway_materials.has(key):
		return _sway_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	mat.set_shader_parameter("strength", key)
	mat.set_shader_parameter("speed", 1.05 + key * 0.35)
	mat.set_shader_parameter("amount", 4.5)
	_sway_materials[key] = mat
	return mat


# ---------------------------------------------------------------------------
# collision
# ---------------------------------------------------------------------------
func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Obstacles"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)
	for b: Dictionary in layout.blockers:
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = float(b["radius"])
		shape.shape = circle
		shape.position = b["pos"]
		body.add_child(shape)
	_build_boundary(body)


## Four slabs that close the arena.
##
## The tree band was the only thing holding the player in, and it is a random
## scatter - gaps through it exist by construction, and play-testers who found
## one walked into empty space and could not walk back, which ends the run with
## no way out but abandoning it.
##
## These go on the same StaticBody2D as every other blocker, so they cost four
## shapes rather than four bodies, and they sit on Layers.WORLD - the layer the
## player, enemies and bullets all already respect, so no ability gets a special
## case. Vault and Dash are stopped by this for free.
##
## Deliberately thick rather than thin: a slab a thousand pixels deep cannot be
## crossed by a teleport that overshoots, where a thin one could be stepped
## straight over.
func _build_boundary(body: StaticBody2D) -> void:
	const THICKNESS := 1000.0
	var size := ForestGenerator.WORLD_SIZE
	var inset := ForestGenerator.WALL_INSET
	var span := size.x - inset * 2.0

	# left, right, top, bottom - each centred just outside its own edge
	var slabs := [
		[Vector2(inset - THICKNESS * 0.5, size.y * 0.5), Vector2(THICKNESS, size.y + THICKNESS * 2.0)],
		[Vector2(size.x - inset + THICKNESS * 0.5, size.y * 0.5), Vector2(THICKNESS, size.y + THICKNESS * 2.0)],
		[Vector2(size.x * 0.5, inset - THICKNESS * 0.5), Vector2(span + THICKNESS * 2.0, THICKNESS)],
		[Vector2(size.x * 0.5, size.y - inset + THICKNESS * 0.5), Vector2(span + THICKNESS * 2.0, THICKNESS)],
	]
	for slab: Array in slabs:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = slab[1]
		shape.shape = rect
		shape.position = slab[0]
		body.add_child(shape)


# ---------------------------------------------------------------------------
# ambience
# ---------------------------------------------------------------------------
## Leaves and motes are emitted in a band that follows the camera, so the
## effect covers the screen without simulating particles across a 4800x3700
## world the player cannot see.
func _build_ambience() -> void:
	var leaves := GPUParticles2D.new()
	leaves.name = "Leaves"
	leaves.amount = 46
	leaves.lifetime = 9.0
	leaves.preprocess = 4.0
	leaves.texture = TEX_LEAF[0]
	leaves.local_coords = false
	# Faint and green. At full opacity a drifting leaf is the same size and
	# contrast as an enemy projectile, and the player should never have to
	# work out whether a moving object can hurt them.
	leaves.modulate = Color(0.72, 0.90, 0.62, 0.34)
	leaves.process_material = _leaf_material()
	leaves.add_to_group("ambient_particles")
	ambience_layer.add_child(leaves)

	var motes := GPUParticles2D.new()
	motes.name = "Motes"
	motes.amount = 30
	motes.lifetime = 7.0
	motes.preprocess = 3.0
	motes.texture = preload("res://assets/sprites/gen/glow.png")
	motes.local_coords = false
	motes.modulate = Color(1.0, 0.98, 0.82, 0.30)
	motes.process_material = _mote_material()
	motes.add_to_group("ambient_particles")
	ambience_layer.add_child(motes)


func _leaf_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(1100, 40, 1)
	m.direction = Vector3(0.25, 1, 0)
	m.spread = 22.0
	m.initial_velocity_min = 26.0
	m.initial_velocity_max = 62.0
	m.gravity = Vector3(6, 12, 0)
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	m.scale_min = 0.55
	m.scale_max = 1.15
	m.color = Color(1, 1, 1, 0.75)
	return m


func _mote_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(1000, 560, 1)
	m.direction = Vector3(0.4, -1, 0)
	m.spread = 45.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 16.0
	m.scale_min = 0.06
	m.scale_max = 0.20
	return m


## Keep the ambient emitters centred on the view.
func follow_camera(camera_pos: Vector2) -> void:
	if ambience_layer == null:
		return
	var leaves := ambience_layer.get_node_or_null("Leaves") as GPUParticles2D
	if leaves != null:
		leaves.position = camera_pos + Vector2(0, -640)
	var motes := ambience_layer.get_node_or_null("Motes") as GPUParticles2D
	if motes != null:
		motes.position = camera_pos
