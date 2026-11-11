extends Control
## Choosing what you carry in: five guns and three melee weapons.
##
## All eight on one screen rather than cycled one at a time like characters -
## weapons are compared on numbers, and numbers are compared side by side.
## Clicking an owned weapon picks it; clicking a locked one buys it if you can
## afford the price shown on it.

signal closed

const CARD_SIZE := Vector2(268, 252)

var _grid: GridContainer = null
var _essence_label: Label = null
var _entry_weapon := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_entry_weapon = WeaponsDB.sanitise(String(Save.weapon))
	_build()
	_refresh()


func _build() -> void:
	add_child(UITheme.dim(0.9))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	col.add_child(UITheme.title("CHOOSE YOUR WEAPON", 42, UITheme.TEXT))
	var sub := UITheme.label(
		"Shop upgrades apply to whichever you carry. Melee never reloads, and "
		+ "hides that turn bullets do not turn a blade.", 18, UITheme.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UITheme.spacer(6))

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	col.add_child(_grid)

	col.add_child(UITheme.spacer(6))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	_essence_label = UITheme.label("", 20, UITheme.PURPLE, 4)
	_essence_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_essence_label)
	var done := UITheme.button("DONE", 26)
	done.custom_minimum_size = Vector2(220, 52)
	done.pressed.connect(_done)
	footer.add_child(done)

	var back := UITheme.button("←  BACK", 22)
	back.custom_minimum_size = Vector2(160, 46)
	back.position = Vector2(40, 40)
	back.size = Vector2(160, 46)
	back.tooltip_text = "Leave without changing weapon (Esc)"
	back.pressed.connect(_back)
	add_child(back)


func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for id: String in WeaponsDB.ORDER:
		_grid.add_child(_card(id))
	_essence_label.text = "%d ✦ essence" % Save.essence


## The numbers a player compares weapons on, at base stats - what the weapon
## is before any shop upgrade.
static func stat_line(id: String) -> String:
	var s := WeaponsDB.apply(Balance.GUN_BASE, id)
	if WeaponsDB.is_melee(id):
		return "%d dmg  ·  %.1f swings/s\nreach %d  ·  %d° arc" % [
			roundi(float(s["damage"])), float(s["fire_rate"]),
			roundi(WeaponsDB.reach(id, s)), roundi(rad_to_deg(WeaponsDB.arc(id, s)))]
	var pellets := roundi(float(s["projectile_count"]))
	var dmg := "%d" % roundi(float(s["damage"]))
	if pellets > 1:
		dmg += " ×%d" % pellets
	var extra := ""
	if float(WeaponsDB.get_def(id).get("explode_radius", 0.0)) > 0.0:
		extra = "  ·  bursts"
	elif float(s["penetration"]) >= 1.0:
		extra = "  ·  pierces %d" % roundi(float(s["penetration"]))
	return "%s dmg  ·  %.1f/s\n%d rounds%s" % [
		dmg, float(s["fire_rate"]), roundi(float(s["magazine"])), extra]


func _card(id: String) -> Control:
	var def := WeaponsDB.get_def(id)
	var owned := Save.owns_weapon(id)
	var chosen := WeaponsDB.sanitise(String(Save.weapon)) == id
	var melee := WeaponsDB.is_melee(id)

	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	var border := UITheme.GOLD if chosen else UITheme.BORDER
	b.add_theme_stylebox_override("normal", UITheme.panel_style(
		UITheme.PANEL_HI if chosen else UITheme.PANEL, border, 2, 8))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(
		UITheme.PANEL_HI, UITheme.GOLD, 2, 8))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(
		UITheme.BORDER, UITheme.GOLD, 2, 8))
	b.add_theme_stylebox_override("focus", UITheme.panel_style(
		Color(0, 0, 0, 0), UITheme.GOLD, 2, 8))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.modulate = Color(1, 1, 1) if owned else Color(0.72, 0.74, 0.78)
	UITheme.wire_sounds(b)
	b.pressed.connect(_pick.bind(id))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)

	var art := TextureRect.new()
	art.texture = load(WeaponsDB.sprite_path(id))
	art.custom_minimum_size = Vector2(0, 58)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var name_label := UITheme.label(String(def["name"]), 22,
		UITheme.GOLD if chosen else UITheme.TEXT, 4)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_label)
	var tag := UITheme.label("MELEE" if melee else "GUN", 14,
		UITheme.RED if melee else UITheme.BLUE, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tag)

	var desc := UITheme.label(String(def["desc"]), 14, UITheme.TEXT_DIM, 3)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 54)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)

	var stats := UITheme.label(stat_line(id), 14, UITheme.TEXT, 3)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stats)

	var foot := ""
	var foot_col := UITheme.TEXT_DIM
	if chosen:
		foot = "CARRYING"
		foot_col = UITheme.GOLD
	elif not owned:
		foot = "UNLOCK  %d ✦" % WeaponsDB.cost(id)
		foot_col = UITheme.PURPLE if Save.essence >= WeaponsDB.cost(id) else UITheme.TEXT_DIM
	var foot_label := UITheme.label(foot, 16, foot_col, 3)
	foot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot_label)
	return b


func _pick(id: String) -> void:
	if not Save.owns_weapon(id):
		var price := WeaponsDB.cost(id)
		if Save.essence < price:
			Audio.play_ui("ui_deny", -8.0)
			return
		Save.essence -= price
		Save.unlocks.append(WeaponsDB.unlock_id(id))
		Audio.play_ui("unlock", -4.0)
	else:
		Audio.play_ui("ui_confirm", -8.0)
	Save.weapon = id
	Save.save_game()
	_refresh()


func _done() -> void:
	Audio.play_ui("ui_confirm", -6.0)
	closed.emit()


## Leave with the weapon you came in with. A purchase made here stays bought.
func _back() -> void:
	if Save.weapon != _entry_weapon:
		Save.weapon = _entry_weapon
		Save.save_game()
	Audio.play_ui("ui_click", -8.0)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
