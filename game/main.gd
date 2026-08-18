class_name Main
extends Node
## Scene router.
##
## Game owns the state; this node owns the nodes. It listens for state changes
## and swaps whatever scene that state wants into the tree. Overlays (pause,
## settings) live on their own CanvasLayer above everything else.

const SCENES := {
	Game.State.MAIN_MENU: "res://ui/main_menu.tscn",
	Game.State.LOADOUT: "res://ui/loadout_screen.tscn",
	Game.State.META: "res://ui/meta_screen.tscn",
	Game.State.CREDITS: "res://ui/credits_screen.tscn",
	Game.State.RUN: "res://world/run.tscn",
	Game.State.DEATH: "res://ui/death_screen.tscn",
	Game.State.RESULTS: "res://ui/results_screen.tscn",
}
const PAUSE_MENU := "res://ui/pause_menu.tscn"
const SETTINGS_MENU := "res://ui/settings_menu.tscn"

@onready var _screen_holder: Node = $ScreenHolder
@onready var _overlay_layer: CanvasLayer = $OverlayLayer

var _current: Node = null
var _pause_menu: Control = null
var _settings_menu: Control = null


func _ready() -> void:
	# Main must keep running while paused so it can still read Escape.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ...but process_mode is INHERITED. Without the line below, ScreenHolder
	# and therefore the entire run scene under it - forest, player, every
	# enemy, the wave controller - also became PROCESS_MODE_ALWAYS and ignored
	# get_tree().paused completely. The pause menu appeared and the world
	# carried on behind it.
	_screen_holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Stated explicitly rather than inherited, so the overlays keep working
	# even if Main's own mode changes later.
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	Events.state_changed.connect(_on_state_changed)
	# DEATH keeps the world visible behind the overlay, so it is not a swap.
	Game.go_to_main_menu()


## _input rather than _unhandled_input: device detection has to see every
## event, including the ones the GUI consumes.
func _input(event: InputEvent) -> void:
	Game.note_device(event)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _settings_menu != null:
		_close_settings()
		get_viewport().set_input_as_handled()
		return
	if Game.can_pause() or Game.paused:
		Game.toggle_pause()
		_sync_pause_menu()
		get_viewport().set_input_as_handled()


func _on_state_changed(_from: int, to: int) -> void:
	_close_settings()
	_clear_pause_menu()
	if to == Game.State.DEATH:
		_show_overlay_scene(SCENES[to])
		return
	_swap_screen(SCENES.get(to, ""))


func _swap_screen(path: String) -> void:
	_clear_overlays()
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
		_current = null
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		push_warning("Slimer: scene not found: %s" % path)
		return
	var packed: PackedScene = load(path)
	_current = packed.instantiate()
	_screen_holder.add_child(_current)


## Death is drawn over the still-standing world rather than replacing it.
func _show_overlay_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("Slimer: scene not found: %s" % path)
		return
	var node: Control = (load(path) as PackedScene).instantiate()
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_layer.add_child(node)


func _clear_overlays() -> void:
	for child in _overlay_layer.get_children():
		child.queue_free()


# --------------------------------------------------------------------------
# pause / settings overlays
# --------------------------------------------------------------------------
func _sync_pause_menu() -> void:
	if Game.paused:
		if _pause_menu == null and ResourceLoader.exists(PAUSE_MENU):
			_pause_menu = (load(PAUSE_MENU) as PackedScene).instantiate()
			_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
			_overlay_layer.add_child(_pause_menu)
	else:
		_clear_pause_menu()


func _clear_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null


func open_settings() -> void:
	if _settings_menu != null or not ResourceLoader.exists(SETTINGS_MENU):
		return
	# Opening settings mid-run always pauses, whether or not it was reached via
	# the pause menu. Reading sliders while slimes close in is not a choice
	# anyone wants to be offered.
	if Game.can_pause() and not Game.paused:
		Game.set_paused(true)
		_sync_pause_menu()
	Game.settings_open = true
	_settings_menu = (load(SETTINGS_MENU) as PackedScene).instantiate()
	_settings_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_layer.add_child(_settings_menu)


func _close_settings() -> void:
	if _settings_menu == null:
		return
	if is_instance_valid(_settings_menu):
		_settings_menu.queue_free()
	_settings_menu = null
	Game.settings_open = false


## Convenience for menus: `Main.instance().open_settings()`.
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Main")
