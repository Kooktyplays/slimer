extends Control
## Ability chooser, shared by the pre-run loadout screen and the shop.
##
## Three slots: one movement, two general. Selecting a slot filters the grid to
## abilities of that slot's class, so a general slot is never offered Dash and
## the movement slot is never offered Grenade. Picking one replaces whatever the
## selected slot held - the slot count is fixed, which is what keeps the general
## pair an actual choice rather than an accumulation.

signal closed()

var _selected_slot := 0
var _live := false            ## true when opened mid-run, so equip applies now
var _grid: GridContainer
var _slot_buttons: Array[Button] = []


func setup(title_text: String, subtitle: String, live: bool) -> void:
	_live = live
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build(title_text, subtitle)


func _build(title_text: String, subtitle: String) -> void:
	add_child(UITheme.dim(0.86))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(980, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(UITheme.title(title_text, 42, UITheme.GOLD))
	var sub := UITheme.label(subtitle, 19, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UITheme.spacer(6))

	# the equipped slots, click to choose which one you're changing
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 18)
	col.add_child(slots)
	_slot_buttons.clear()
	for i in AbilitiesDB.SLOT_COUNT:
		var b := UITheme.button("", 19)
		b.custom_minimum_size = Vector2(232, 84)
		b.pressed.connect(func() -> void:
			_selected_slot = i
			_refresh())
		slots.add_child(b)
		_slot_buttons.append(b)

	col.add_child(UITheme.spacer(10))

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(_grid)

	col.add_child(UITheme.spacer(12))
	var done := UITheme.button("DONE")
	done.custom_minimum_size = Vector2(0, 52)
	done.pressed.connect(func() -> void: closed.emit())
	col.add_child(done)

	_refresh()


func _refresh() -> void:
	for i in _slot_buttons.size():
		var id: String = Save.loadout[i] if i < Save.loadout.size() else ""
		var def := AbilitiesDB.get_def(id)
		var label := "MOVEMENT" if AbilitiesDB.class_for_slot(i) == \
			AbilitiesDB.CLASS_MOVEMENT else "ABILITY %d" % i
		_slot_buttons[i].text = "%s\n%s" % [label, def["name"]]
		_slot_buttons[i].add_theme_color_override("font_color",
			UITheme.GOLD if i == _selected_slot else UITheme.TEXT)

	for c in _grid.get_children():
		c.queue_free()

	# Only abilities the selected slot can actually hold. Showing the rest and
	# rejecting the click would be a worse way to teach the same rule.
	for id: String in Save.unlocked_for_slot(_selected_slot):
		_grid.add_child(_ability_card(id))


func _ability_card(id: String) -> Control:
	var def := AbilitiesDB.get_def(id)
	var equipped := Save.loadout.has(id)

	var b := Button.new()
	b.custom_minimum_size = Vector2(232, 164)
	b.add_theme_stylebox_override("normal", UITheme.panel_style(
		UITheme.PANEL_HI if equipped else UITheme.PANEL,
		UITheme.GOLD if equipped else UITheme.BORDER, 2, 8))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(
		UITheme.PANEL_HI, UITheme.GOLD, 2, 8))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(
		UITheme.BORDER, UITheme.GOLD, 2, 8))
	b.add_theme_stylebox_override("focus", UITheme.panel_style(
		Color(0, 0, 0, 0), UITheme.GOLD, 2, 8))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UITheme.wire_sounds(b)
	b.pressed.connect(_on_pick.bind(id))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(UITheme.icon(AbilitiesDB.icon_path(id), 30,
		UITheme.GOLD if equipped else UITheme.TEXT))
	head.add_child(UITheme.label(String(def["name"]), 22,
		UITheme.GOLD if equipped else UITheme.TEXT, 5))

	var desc := UITheme.label(String(def["desc"]), 15, UITheme.TEXT_DIM, 3)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(204, 78)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)

	var meta := UITheme.label(
		"%.0fs cooldown   %d charge%s" % [
			float(def["cooldown"]), int(def["charges"]),
			"" if int(def["charges"]) == 1 else "s"],
		14, UITheme.TEXT_DIM, 3)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(meta)

	return b


func _on_pick(id: String) -> void:
	Save.set_loadout(_selected_slot, id)
	if _live and Game.run != null:
		# Save.set_loadout may have swapped the other slot too, so push both
		var p := Combat.player()
		if p != null and p.get("abilities") != null:
			for i in Save.loadout.size():
				p.abilities.equip(i, Save.loadout[i])
		Game.run.abilities = Save.loadout.duplicate()
	Audio.play_ui("ui_confirm", -6.0)
	_refresh()
