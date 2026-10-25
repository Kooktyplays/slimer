extends Control
## Pre-run loadout: pick a movement ability and two others, choose a difficulty,
## then go.

var _picker: Control = null
var _nightmare := false
var _nightmare_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_picker = preload("res://ui/ability_picker.gd").new()
	add_child(_picker)
	_picker.call("setup", "CHOOSE YOUR THREE",
		"Movement, then two more. These are locked for the run - the shop "
		+ "upgrades what you bring, it does not replace it.", false)
	_picker.connect("closed", _start)

	_build_class_picker()
	_build_difficulty()

	var back := UITheme.button("BACK", 22)
	back.custom_minimum_size = Vector2(160, 46)
	back.position = Vector2(40, 40)
	back.size = Vector2(160, 46)
	back.pressed.connect(func() -> void: Game.go_to_main_menu())
	add_child(back)


## Difficulty toggle.
##
## Deliberately a toggle on this screen rather than a separate menu entry: the
## choice belongs next to the loadout, because the two are the same decision -
## what you are taking in, and what you are taking it into.
## Who you were. Sits beside the difficulty toggle rather than replacing the
## ability grid - the class is layered on top of the loadout, not instead of it.
var _class_button: Button = null


func _build_class_picker() -> void:
	_class_button = UITheme.button("", 22)
	_class_button.custom_minimum_size = Vector2(360, 52)
	_class_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_class_button.position = Vector2(-180, -170)
	_class_button.size = Vector2(360, 52)
	# Opens the real screen. Cycling through five characters on one button was
	# always a placeholder - a class is the biggest decision in a run and
	# cannot be read off a label that changes when you press it.
	_class_button.pressed.connect(_open_class_select)
	add_child(_class_button)
	_refresh_class()


var _class_panel: Control = null


func _open_class_select() -> void:
	if _class_panel != null:
		return
	Audio.play_ui("ui_click", -8.0)
	_class_panel = preload("res://ui/class_select.gd").new()
	add_child(_class_panel)
	_class_panel.connect("closed", func() -> void:
		if _class_panel != null:
			_class_panel.queue_free()
		_class_panel = null
		_refresh_class())


func _refresh_class() -> void:
	if _class_button == null:
		return
	var id := ClassesDB.sanitise(String(Save.character))
	var def := ClassesDB.get_def(id)
	_class_button.text = String(def["name"]).to_upper()
	_class_button.add_theme_color_override("font_color", def["tint"])
	_class_button.text = "%s  \u25b8" % String(def["name"]).to_upper()
	_class_button.tooltip_text = "%s\n\n%s\n%s\n\nULTIMATE - %s\n%s" % [
		String(def["blurb"]),
		String(def["passive_text"]),
		String(def["charge_text"]),
		String(def["ultimate_name"]),
		String(def["ultimate_text"]),
	]


func _build_difficulty() -> void:
	_nightmare_button = UITheme.button("", 22)
	_nightmare_button.custom_minimum_size = Vector2(360, 52)
	_nightmare_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_nightmare_button.position = Vector2(-180, -110)
	_nightmare_button.size = Vector2(360, 52)
	_nightmare_button.pressed.connect(func() -> void:
		_nightmare = not _nightmare
		Audio.play_ui("ui_confirm")
		_refresh_difficulty())
	add_child(_nightmare_button)
	_refresh_difficulty()


func _refresh_difficulty() -> void:
	if _nightmare_button == null:
		return
	_nightmare_button.text = ("DIFFICULTY:  NIGHTMARE" if _nightmare
		else "DIFFICULTY:  NORMAL")
	_nightmare_button.add_theme_color_override("font_color",
		UITheme.RED if _nightmare else UITheme.TEXT)
	_nightmare_button.tooltip_text = ("Every slime from wave 1, far bigger waves"
		+ " and much harder hits. Pays %.1fx Essence."
			% Balance.NIGHTMARE_ESSENCE_MULTIPLIER) if _nightmare else \
		"The standard run. Enemy types unlock as you go."


func _start() -> void:
	Audio.play_ui("ui_confirm")
	Game.start_run(0, _nightmare, ClassesDB.sanitise(String(Save.character)))
