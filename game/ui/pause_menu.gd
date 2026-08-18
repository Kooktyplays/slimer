extends Control
## Pause overlay. Runs with PROCESS_MODE_ALWAYS so it still works while the
## tree is paused.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Audio.set_ducked(true)
	_build()


func _exit_tree() -> void:
	Audio.set_ducked(false)


func _build() -> void:
	add_child(UITheme.dim(0.7))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(UITheme.title("PAUSED", 54, UITheme.TEXT))
	col.add_child(UITheme.spacer(10))
	col.add_child(_controls_block())
	col.add_child(UITheme.spacer(16))

	var resume := UITheme.button("RESUME", 26)
	resume.pressed.connect(_resume)
	col.add_child(resume)

	var settings := UITheme.button("SETTINGS", 22)
	settings.pressed.connect(func() -> void:
		var main := Main.instance()
		if main != null:
			main.call("open_settings"))
	col.add_child(settings)

	var quit := UITheme.button("ABANDON RUN", 22)
	quit.add_theme_color_override("font_hover_color", UITheme.RED)
	quit.pressed.connect(func() -> void:
		Game.set_paused(false)
		Game.finish_run())
	col.add_child(quit)


## The control list lives on the pause screen rather than in a tutorial wall,
## so it's available exactly when someone goes looking for it.
func _controls_block() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	# Read from the live bindings rather than a hardcoded list, so this stays
	# correct after a rebind and shows controller glyphs on a controller.
	v.add_child(_control_row("Move",
		"%s %s %s %s" % [
			InputBinds.label_for_action(Save.keybinds, "move_up", Game.input_device),
			InputBinds.label_for_action(Save.keybinds, "move_left", Game.input_device),
			InputBinds.label_for_action(Save.keybinds, "move_down", Game.input_device),
			InputBinds.label_for_action(Save.keybinds, "move_right", Game.input_device)]))
	v.add_child(_control_row("Aim",
		"Right Stick" if Game.using_gamepad() else "Mouse"))
	for entry: Dictionary in InputBinds.ACTIONS:
		var action: String = entry["action"]
		if action.begins_with("move_"):
			continue
		v.add_child(_control_row(String(entry["label"]),
			InputBinds.label_for_action(Save.keybinds, action, Game.input_device)))
	return v


func _control_row(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var l := UITheme.label(label, 18, UITheme.TEXT_DIM, 3)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UITheme.label(value, 18, UITheme.TEXT, 3))
	return row


func _resume() -> void:
	Game.set_paused(false)
	var main := Main.instance()
	if main != null:
		main.call("_sync_pause_menu")
