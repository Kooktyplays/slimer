extends Control
## Settings overlay. Every change is applied and saved immediately - there is
## no Apply button to forget to press.

var _keybinds: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	add_child(UITheme.dim(0.85))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(UITheme.title("SETTINGS", 46, UITheme.TEXT))
	col.add_child(UITheme.spacer(12))

	_slider(col, "Master volume", "master_volume")
	_slider(col, "Music volume", "music_volume")
	_slider(col, "Sound volume", "sfx_volume")
	_slider(col, "Screen shake", "screen_shake")
	col.add_child(UITheme.spacer(8))
	_toggle(col, "Damage numbers", "damage_numbers")
	_toggle(col, "Tutorial hints", "show_hints")

	col.add_child(UITheme.spacer(14))
	var controls := UITheme.button("CONTROLS", 24)
	controls.custom_minimum_size = Vector2(0, 50)
	controls.pressed.connect(_open_keybinds)
	col.add_child(controls)

	col.add_child(UITheme.spacer(14))
	var close := UITheme.button("CLOSE", 26)
	close.pressed.connect(_close)
	col.add_child(close)

	var reset := UITheme.button("ERASE ALL PROGRESS", 18)
	reset.add_theme_color_override("font_hover_color", UITheme.RED)
	reset.pressed.connect(_confirm_reset)
	col.add_child(reset)


func _slider(parent: Node, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var l := UITheme.label(label, 21, UITheme.TEXT_DIM, 4)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)

	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Save.settings[key])
	s.custom_minimum_size = Vector2(250, 32)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)

	var value_label := UITheme.label("%d%%" % int(s.value * 100), 20, UITheme.TEXT, 4)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	s.value_changed.connect(func(v: float) -> void:
		Save.settings[key] = v
		value_label.text = "%d%%" % int(v * 100)
		Audio.apply_settings()
		Save.save_game())
	# a click of feedback when the audio sliders move, so they can be set by ear
	s.drag_ended.connect(func(_changed: bool) -> void:
		if key != "screen_shake":
			Audio.play_ui("ui_click", -8.0))


func _toggle(parent: Node, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UITheme.label(label, 21, UITheme.TEXT_DIM, 4)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var b := UITheme.button("ON" if bool(Save.settings[key]) else "OFF", 20)
	b.custom_minimum_size = Vector2(120, 42)
	b.pressed.connect(func() -> void:
		Save.settings[key] = not bool(Save.settings[key])
		b.text = "ON" if bool(Save.settings[key]) else "OFF"
		Save.save_game())
	row.add_child(b)


func _open_keybinds() -> void:
	if _keybinds != null:
		return
	_keybinds = preload("res://ui/keybinds_menu.gd").new()
	_keybinds.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_keybinds)
	_keybinds.connect("closed", func() -> void:
		if _keybinds != null:
			_keybinds.queue_free()
		_keybinds = null)


func _confirm_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Erase all Essence, unlocks and records?\nThis cannot be undone."
	dialog.title = "Erase progress"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Save.reset()
		Audio.play_ui("ui_deny")
		_close())
	dialog.popup_centered()


func _close() -> void:
	Audio.play_ui("ui_click")
	var main := Main.instance()
	if main != null:
		main.call("_close_settings")
