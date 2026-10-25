extends Control
## Choosing who you were.
##
## This replaces a cycling button on the loadout screen, which was a
## placeholder: five characters with distinct passives, charge conditions and
## ultimates cannot be chosen from a label that changes when you press it. A
## class is the biggest decision in a run and it deserves the space to be read.
##
## The card animates on every change rather than only on open - the switch is
## the moment worth punctuating, because that is when you are comparing.

signal closed

const CARD_SIZE := Vector2(560, 470)

var _index := 0
var _card: PanelContainer = null
var _sprite: TextureRect = null
var _name_label: Label = null
var _title_label: Label = null
var _passive_label: Label = null
var _charge_label: Label = null
var _ult_label: Label = null
var _ult_desc: Label = null
var _blurb: Label = null
var _skin_button: Button = null
var _skin_label: Label = null
var _essence_label: Label = null
var _confirm_button: Button = null
var _bob := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_index = maxi(0, ClassesDB.ORDER.find(ClassesDB.sanitise(String(Save.character))))
	_build()
	_refresh(false)


func _build() -> void:
	add_child(UITheme.dim(0.88))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	col.add_child(UITheme.title("CHOOSE WHO YOU WERE", 42, UITheme.TEXT))
	var sub := UITheme.label(
		"Every class carries the same three abilities you pick. What differs is "
		+ "what you are, and what you have to do to remember it.",
		18, UITheme.TEXT_DIM, 4)
	sub.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UITheme.spacer(8))

	# --- the card, flanked by arrows ---------------------------------------
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)

	var prev := UITheme.button("<", 34)
	prev.custom_minimum_size = Vector2(60, CARD_SIZE.y)
	prev.pressed.connect(func() -> void: _step(-1))
	row.add_child(prev)

	_card = UITheme.panel()
	_card.custom_minimum_size = CARD_SIZE
	row.add_child(_card)

	var next := UITheme.button(">", 34)
	next.custom_minimum_size = Vector2(60, CARD_SIZE.y)
	next.pressed.connect(func() -> void: _step(1))
	row.add_child(next)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	_card.add_child(inner)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(0, 150)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(_sprite)
	inner.add_child(UITheme.spacer(10))

	_name_label = UITheme.label("", 34, UITheme.TEXT, 4)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_name_label)

	_title_label = UITheme.label("", 18, UITheme.TEXT_DIM, 4)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_title_label)

	_blurb = _wrapped(inner, 18, UITheme.TEXT_DIM)
	inner.add_child(UITheme.spacer(6))
	_passive_label = _wrapped(inner, 20, UITheme.GREEN)
	_charge_label = _wrapped(inner, 20, UITheme.BLUE)
	inner.add_child(UITheme.spacer(6))
	_ult_label = _wrapped(inner, 22, UITheme.GOLD)
	_ult_desc = _wrapped(inner, 18, UITheme.TEXT_DIM)

	# --- skins --------------------------------------------------------------
	inner.add_child(UITheme.spacer(8))
	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 10)
	inner.add_child(skin_row)

	_skin_label = UITheme.label("", 18, UITheme.TEXT_DIM, 4)
	_skin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_row.add_child(_skin_label)

	_skin_button = UITheme.button("", 18)
	_skin_button.custom_minimum_size = Vector2(230, 42)
	_skin_button.pressed.connect(_cycle_skin)
	skin_row.add_child(_skin_button)

	# --- footer -------------------------------------------------------------
	col.add_child(UITheme.spacer(8))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	_essence_label = UITheme.label("", 20, UITheme.PURPLE, 4)
	_essence_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_essence_label)

	_confirm_button = UITheme.button("CHOOSE", 26)
	_confirm_button.custom_minimum_size = Vector2(260, 52)
	_confirm_button.pressed.connect(_confirm)
	footer.add_child(_confirm_button)


func _wrapped(parent: Node, size: int, colour: Color) -> Label:
	var l := UITheme.label("", size, colour, 4)
	l.custom_minimum_size = Vector2(CARD_SIZE.x - 40, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _current() -> String:
	return ClassesDB.ORDER[posmod(_index, ClassesDB.ORDER.size())]


func _step(by: int) -> void:
	_index = posmod(_index + by, ClassesDB.ORDER.size())
	Audio.play_ui("ui_click", -8.0)
	_refresh(true)


## Cycle through this class's skins: default, then each variant. An unowned one
## is bought here if it can be afforded, and refused with a sound if not - the
## price is on the button, so nothing is a surprise.
func _cycle_skin() -> void:
	var cls := _current()
	var order: Array[String] = [ClassesDB.SKIN_DEFAULT]
	order.append_array(ClassesDB.skins_for(cls).keys())
	var at := order.find(Save.skin_of(cls))
	var want: String = order[posmod(at + 1, order.size())]

	if not Save.has_skin(cls, want):
		if not Save.buy_skin(cls, want):
			Audio.play_ui("ui_deny", -8.0)
			_refresh(false)
			return
		Audio.play_ui("unlock", -6.0)
	else:
		Audio.play_ui("ui_click", -10.0)
	Save.skin_for_class[cls] = want
	Save.save_game()
	_refresh(true)


## Choose this character, or buy it if it is not owned yet.
##
## One button rather than two: the label says which it is, and a player who
## cannot afford it is told the price rather than shown a dead control.
func _confirm() -> void:
	var cls := _current()
	if not Save.owns_class(cls):
		var cost := ClassesDB.cost(cls)
		if Save.essence < cost:
			Audio.play_ui("ui_deny", -8.0)
			return
		Save.essence -= cost
		Save.unlocks.append(ClassesDB.unlock_id(cls))
		Save.save_game()
		Audio.play_ui("unlock", -4.0)
		_refresh(true)
		return
	Save.character = cls
	Save.save_game()
	Audio.play_ui("ui_confirm", -6.0)
	closed.emit()


func _refresh(animate: bool) -> void:
	var cls := _current()
	var def := ClassesDB.get_def(cls)
	var tint: Color = def["tint"]

	var path := ClassesDB.sprite_path(cls, Save.skin_of(cls))
	_sprite.texture = load(path) if ResourceLoader.exists(path) else null
	_name_label.text = String(def["name"]).to_upper()
	_name_label.add_theme_color_override("font_color", tint)
	_title_label.text = String(def["title"])
	_blurb.text = String(def["blurb"])
	_passive_label.text = String(def["passive_text"])
	_charge_label.text = String(def["charge_text"])
	_ult_label.text = "ULTIMATE — %s" % String(def["ultimate_name"]).to_upper()
	_ult_desc.text = String(def["ultimate_text"])

	var owned := Save.owns_class(cls)

	# The card dims and the button becomes a price when the class is locked, so
	# the state is readable without a separate padlock to decode.
	_card.modulate = Color(1, 1, 1) if owned else Color(0.72, 0.74, 0.78)
	if owned:
		_confirm_button.text = "CHOOSE"
		_confirm_button.add_theme_color_override("font_color", UITheme.TEXT)
	else:
		var cost := ClassesDB.cost(cls)
		_confirm_button.text = "UNLOCK  %d \u2726" % cost
		_confirm_button.add_theme_color_override("font_color",
			UITheme.PURPLE if Save.essence >= cost else UITheme.TEXT_DIM)

	# skin row
	var skin := Save.skin_of(cls)
	_skin_label.text = "Skin:  %s" % ClassesDB.skin_name(cls, skin)
	var order: Array[String] = [ClassesDB.SKIN_DEFAULT]
	order.append_array(ClassesDB.skins_for(cls).keys())
	var nxt: String = order[posmod(order.find(skin) + 1, order.size())]
	# no dressing a character you do not have
	_skin_button.disabled = not owned
	_skin_label.visible = owned
	if not owned:
		_skin_button.text = "LOCKED"
		_skin_button.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	elif Save.has_skin(cls, nxt):
		_skin_button.text = "NEXT SKIN"
		_skin_button.add_theme_color_override("font_color", UITheme.TEXT)
	else:
		var cost := int(ClassesDB.skins_for(cls)[nxt]["cost"])
		_skin_button.text = "UNLOCK  %d ✦" % cost
		_skin_button.add_theme_color_override("font_color",
			UITheme.PURPLE if Save.essence >= cost else UITheme.TEXT_DIM)
	_essence_label.text = "%d ✦ essence" % Save.essence

	if animate:
		# Slide-and-settle on every change, not only on open: switching is when
		# you are comparing, so that is the moment worth punctuating.
		_card.modulate.a = 0.0
		_card.position.x = 26.0
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(_card, "modulate:a", 1.0, 0.16)
		t.tween_property(_card, "position:x", 0.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	# The same idle bob the player has in the world, so the card shows the
	# character rather than a portrait of one.
	_bob += delta * 2.4
	if _sprite != null:
		_sprite.position.y = sin(_bob) * 5.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()
