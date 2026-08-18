extends Node
## Object pooling for everything spawned in bulk.
##
## Bullets, enemies, particles, damage numbers and pickups all churn hard
## during a wave; instantiating and freeing them per-use is what makes big
## waves stutter. Pooled nodes are removed from the tree while idle so they
## cost nothing, and reused on demand.
##
## A pooled scene may implement:
##   _pool_activate()  - called right after it is added back to the tree
##   _pool_reset()     - called right before it is parked
## Neither is required.

const META_KEY := "_pool_key"
const META_ACTIVE := "_pool_active"

var _free: Dictionary = {}          # key -> Array[Node]   (parked, out of tree)
var _active: Dictionary = {}        # key -> Array[Node]   (handed out)
var _scenes: Dictionary = {}        # key -> PackedScene
var _created: Dictionary = {}       # key -> int (diagnostics)


func _exit_tree() -> void:
	for key: String in _free:
		for node: Node in _free[key]:
			if is_instance_valid(node):
				node.free()
	_free.clear()


func _key_for(scene: PackedScene) -> String:
	return scene.resource_path


func register(scene: PackedScene) -> void:
	var key := _key_for(scene)
	if not _scenes.has(key):
		_scenes[key] = scene
		_free[key] = []
		_active[key] = []
		_created[key] = 0


## Instantiate `count` copies up front so the first wave doesn't pay for them.
func prewarm(scene: PackedScene, count: int) -> void:
	register(scene)
	var key := _key_for(scene)
	var pool: Array = _free[key]
	while pool.size() < count:
		var node := scene.instantiate()
		node.set_meta(META_KEY, key)
		node.set_meta(META_ACTIVE, false)
		pool.append(node)
		_created[key] = int(_created[key]) + 1


## Take a node from the pool (or build one) and parent it to `parent`.
func acquire(scene: PackedScene, parent: Node) -> Node:
	register(scene)
	var key := _key_for(scene)
	var pool: Array = _free[key]
	var node: Node = null
	while not pool.is_empty() and node == null:
		var candidate: Node = pool.pop_back()
		if is_instance_valid(candidate):
			node = candidate
	if node == null:
		node = scene.instantiate()
		node.set_meta(META_KEY, key)
		_created[key] = int(_created[key]) + 1

	node.set_meta(META_ACTIVE, true)
	(_active[key] as Array).append(node)
	parent.add_child(node)
	if node.has_method("_pool_activate"):
		node.call("_pool_activate")
	return node


## Park a node back in its pool. Safe to call twice; safe on unpooled nodes
## (they're simply queue_freed instead).
##
## The node is marked inactive and hidden immediately, but actually leaving
## the tree is deferred. Most releases happen inside a physics callback - a
## bullet parking itself from `body_entered` - and Godot forbids reparenting a
## CollisionObject2D during one. Deferring the unparent is the difference
## between this working and a screenful of "Removing a CollisionObject node
## during a physics callback" errors.
## `immediate` skips the deferred unparent. Only safe outside physics - it is
## used at run teardown, where deferring would leave `_park` running against a
## world node that is already being freed.
func release(node: Node, immediate: bool = false) -> void:
	if not is_instance_valid(node):
		return
	if not node.has_meta(META_KEY):
		node.queue_free()
		return
	if not bool(node.get_meta(META_ACTIVE, false)):
		return                                  # already parked

	node.set_meta(META_ACTIVE, false)
	var key: String = node.get_meta(META_KEY)
	(_active[key] as Array).erase(node)

	if node.has_method("_pool_reset"):
		node.call("_pool_reset")
	if node is Node2D:
		(node as Node2D).visible = false
	node.set_process(false)
	node.set_physics_process(false)

	if immediate:
		_park(node, key)
	else:
		call_deferred("_park", node, key)


## Parameters are deliberately untyped: by the time the deferred call flushes,
## the node may already have been freed, and a typed `Node` parameter rejects
## a freed-object Variant with a conversion error instead of letting us check
## is_instance_valid ourselves.
func _park(node_variant: Variant, key_variant: Variant) -> void:
	if typeof(node_variant) != TYPE_OBJECT or not is_instance_valid(node_variant):
		return
	var node: Node = node_variant
	var key: String = str(key_variant)
	if bool(node.get_meta(META_ACTIVE, false)):
		return                                  # re-acquired before we parked it
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	var pool: Array = _free.get(key, [])
	if not pool.has(node):
		pool.append(node)
	_free[key] = pool


func is_pooled_active(node: Node) -> bool:
	return is_instance_valid(node) and bool(node.get_meta(META_ACTIVE, false))


func live_count(scene: PackedScene) -> int:
	return (_active.get(_key_for(scene), []) as Array).size()


func total_live() -> int:
	var n := 0
	for key: String in _active:
		n += (_active[key] as Array).size()
	return n


## Diagnostics for the perf test: how many nodes each pool ever had to build.
## `created` staying near `free + live` means the pool is sized correctly and
## we aren't quietly instantiating on the hot path.
func stats() -> Dictionary:
	var out := {}
	for key: String in _scenes:
		out[key.get_file()] = {
			"created": int(_created.get(key, 0)),
			"free": (_free.get(key, []) as Array).size(),
			"live": (_active.get(key, []) as Array).size(),
		}
	return out


## Park every handed-out node. Called when a run is torn down, so pooled
## objects go back on the free list instead of being freed along with the
## world node and silently shrinking every pool.
func release_all() -> void:
	for key: String in _active.keys():
		for node: Node in (_active[key] as Array).duplicate():
			release(node, true)
		_active[key] = []
