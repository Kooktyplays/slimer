extends Control
## Permanent upgrades, bought with Essence.
##
## Grouped by what they do to the game rather than by cost: new abilities,
## new shop entries, and small starting bonuses. Most of the Essence in the
## list buys variety, which is deliberate - the goal is that run twenty has
## more possible shapes than run one, not that it is easier.

var _scroll: VBoxContainer
var _essence_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := UITheme.label("PERMANENT UPGRADES", 44, UITheme.PURPLE, 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UITheme.icon("res://assets/sprites/gen/icon_essence.png", 34, UITheme.PURPLE))
	_essence_label = UITheme.label("", 34, UITheme.PURPLE)
	header.add_child(_essence_label)

	col.add_child(UITheme.label(
		"Essence is earned from every run and is never lost. "
		+ "These carry over; nothing else does.", 18, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(8))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_scroll = VBoxContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_theme_constant_override("separation", 8)
	scroll.add_child(_scroll)

	col.add_child(UITheme.spacer(8))
	var back := UITheme.button("BACK")
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func() -> void: Game.go_to_main_menu())
	col.add_child(back)

	_refresh()


func _refresh() -> void:
	_essence_label.text = str(Save.essence)
	for c in _scroll.get_children():
		c.queue_free()

	_add_section("NEW ABILITIES", MetaDB.KIND_ABILITY)
	_add_section("NEW SHOP UPGRADES", MetaDB.KIND_UPGRADE)
	_add_section("STARTING BONUSES", MetaDB.KIND_PASSIVE)


func _add_section(heading: String, kind: String) -> void:
	_scroll.add_child(UITheme.spacer(6))
	_scroll.add_child(UITheme.label(heading, 24, UITheme.GOLD, 5))
	for id: String in MetaDB.ORDER:
		if MetaDB.get_def(id)["kind"] == kind:
			_scroll.add_child(_row(id))


func _row(id: String) -> Control:
	var def := MetaDB.get_def(id)
	var owned := Save.is_unlocked(id)
	var available := MetaDB.requirement_met(id, Save.unlocks)
	var affordable := Save.can_afford(id)

	var border := UITheme.BORDER
	if owned:
		border = UITheme.GREEN
	elif not available:
		border = Color(0.22, 0.26, 0.22)
	elif affordable:
		border = UITheme.GOLD

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.PANEL if available else Color(0.10, 0.12, 0.10, 0.9), border, 2, 8))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	h.add_child(UITheme.icon(MetaDB.icon_path(id), 34,
		UITheme.GREEN if owned else (UITheme.TEXT if available else Color(0.35, 0.38, 0.35))))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	h.add_child(text)
	text.add_child(UITheme.label(MetaDB.display_name(id), 23,
		UITheme.TEXT if available else UITheme.TEXT_DIM, 5))
	var desc := MetaDB.description(id)
	if not available:
		desc += "     (needs %s first)" % MetaDB.display_name(String(def["needs"]))
	text.add_child(UITheme.label(desc, 16, UITheme.TEXT_DIM, 3))

	if owned:
		var owned_label := UITheme.label("OWNED", 22, UITheme.GREEN)
		owned_label.custom_minimum_size = Vector2(150, 0)
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(owned_label)
	else:
		var buy := UITheme.button("%d" % int(def["cost"]), 24)
		buy.custom_minimum_size = Vector2(150, 50)
		buy.disabled = not (available and affordable)
		buy.pressed.connect(_on_buy.bind(id))
		h.add_child(buy)

	return row


func _on_buy(id: String) -> void:
	if not Save.purchase(id):
		Audio.play_ui("ui_deny")
		return
	Audio.play("unlock", -2.0)
	_refresh()
