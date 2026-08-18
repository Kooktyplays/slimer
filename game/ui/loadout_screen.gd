extends Control
## Pre-run loadout: pick your two abilities, then go.

var _picker: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_picker = preload("res://ui/ability_picker.gd").new()
	add_child(_picker)
	_picker.call("setup", "CHOOSE YOUR TWO",
		"You can swap them at any forest rest. You can never carry three.", false)
	_picker.connect("closed", _start)

	var back := UITheme.button("BACK", 22)
	back.custom_minimum_size = Vector2(160, 46)
	back.position = Vector2(40, 40)
	back.size = Vector2(160, 46)
	back.pressed.connect(func() -> void: Game.go_to_main_menu())
	add_child(back)


func _start() -> void:
	Audio.play_ui("ui_confirm")
	Game.start_run(0)
