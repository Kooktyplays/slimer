extends Control
## Control rebinding, keyboard/mouse and gamepad side by side.
##
## Each action gets one row with two slots. Clicking a slot listens for the
## next input of that kind and assigns it. Escape always cancels a capture and
## can never be bound to anything - losing the only way out of a menu to a
## mis-click is not a state a player should be able to reach.

signal closed()

const KIND_KBM := 0
const KIND_PAD := 1

var _rows: VBoxContainer
var _status: Label
var _capturing := false
var _capture_action := ""
var _capture_kind := KIND_KBM
var _capture_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	add_child(UITheme.dim(0.88))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(UITheme.title("CONTROLS", 44, UITheme.GOLD))
	_status = UITheme.label(
		"Click a binding to change it.  Escape cancels.", 18, UITheme.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	col.add_child(UITheme.spacer(6))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)
	var spacer := UITheme.label("", 17, UITheme.TEXT_DIM)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	for caption: String in ["Keyboard / Mouse", "Gamepad"]:
		var h := UITheme.label(caption, 17, UITheme.TEXT_DIM, 3)
		h.custom_minimum_size = Vector2(250, 0)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(h)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	_refresh()

	col.add_child(UITheme.spacer(8))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	var reset := UITheme.button("RESET TO DEFAULTS", 20)
	reset.custom_minimum_size = Vector2(320, 50)
	reset.pressed.connect(func() -> void:
		Save.reset_keybinds()
		_status.text = "Controls reset to defaults."
		_refresh())
	footer.add_child(reset)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)

	var done := UITheme.button("DONE", 22)
	done.custom_minimum_size = Vector2(220, 50)
	done.pressed.connect(func() -> void: closed.emit())
	footer.add_child(done)
	done.grab_focus()


func _refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var group := ""
	for entry: Dictionary in InputBinds.ACTIONS:
		if entry["group"] != group:
			group = entry["group"]
			_rows.add_child(UITheme.spacer(6))
			_rows.add_child(UITheme.label(group.to_upper(), 20, UITheme.GOLD, 4))
		_rows.add_child(_row(entry))


func _row(entry: Dictionary) -> Control:
	var action: String = entry["action"]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL, UITheme.BORDER, 2, 8))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var name_label := UITheme.label(String(entry["label"]), 21, UITheme.TEXT, 4)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_label)

	for kind in [KIND_KBM, KIND_PAD]:
		var data := InputBinds.first_of_kind(Save.keybinds, action, kind == KIND_PAD)
		var b := UITheme.button(
			InputBinds.describe(data) if not data.is_empty() else "—", 19)
		b.custom_minimum_size = Vector2(250, 46)
		b.pressed.connect(_begin_capture.bind(action, kind, b))
		h.add_child(b)

	return row


# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------
func _begin_capture(action: String, kind: int, button: Button) -> void:
	_capturing = true
	_capture_action = action
	_capture_kind = kind
	_capture_button = button
	button.text = "Press %s…" % ("a button" if kind == KIND_PAD else "a key")
	_status.text = "Listening for %s.  Escape cancels." % InputBinds.display_name(action)


func _cancel_capture(message: String) -> void:
	_capturing = false
	_capture_action = ""
	_capture_button = null
	_status.text = message
	_refresh()


## When not capturing, Escape closes this screen and nothing else - otherwise
## it would fall through and shut the settings menu behind it too.
func _unhandled_input(event: InputEvent) -> void:
	if _capturing:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _input(event: InputEvent) -> void:
	if not _capturing:
		return

	# Escape always means "stop", never "bind Escape".
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel_capture("Cancelled.")
		return

	var data := _event_to_binding(event)
	if data.is_empty():
		return
	get_viewport().set_input_as_handled()
	_assign(data)


## Only accept a *press* of the right kind of input; ignore releases, mouse
## motion and idle stick jitter.
func _event_to_binding(event: InputEvent) -> Dictionary:
	if _capture_kind == KIND_KBM:
		if event is InputEventKey and (event as InputEventKey).pressed \
				and not (event as InputEventKey).echo:
			return InputBinds.serialize(event)
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			return InputBinds.serialize(event)
		return {}

	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		return InputBinds.serialize(event)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) > 0.7:
			return InputBinds.serialize(motion)
	return {}


func _assign(data: Dictionary) -> void:
	var action := _capture_action
	var gamepad := _capture_kind == KIND_PAD

	# Taking a binding away from another action is fine, but it has to be said
	# out loud - silently unbinding something the player set earlier is how you
	# end up unable to shoot with no idea why.
	var clash := InputBinds.conflicting_action(Save.keybinds, data, action)
	var note := ""
	if clash != "":
		var kept: Array = []
		for existing: Variant in InputBinds.current(Save.keybinds, clash):
			if existing != data:
				kept.append(existing)
		Save.set_keybind(clash, kept)
		note = "  (taken from %s)" % InputBinds.display_name(clash)

	# replace this action's binding of the same kind, keep the other kind
	var updated: Array = []
	for existing: Variant in InputBinds.current(Save.keybinds, action):
		if InputBinds.is_gamepad(existing) != gamepad:
			updated.append(existing)
	updated.append(data)
	Save.set_keybind(action, updated)

	Audio.play_ui("ui_confirm", -6.0)
	_cancel_capture("%s bound to %s.%s"
		% [InputBinds.display_name(action), InputBinds.describe(data), note])
