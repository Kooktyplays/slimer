extends Control
## Shown over the still-standing world the moment the player dies.
##
## Deliberately slow: a beat of silence, the wave you reached, then the button.
## Snapping straight to a results table would rob the death of its weight.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var dim := UITheme.dim(0.0)
	add_child(dim)
	var fade := create_tween()
	fade.tween_property(dim, "color:a", 0.82, 1.4)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(520, 0)
	col.modulate.a = 0.0
	center.add_child(col)

	col.add_child(UITheme.title("YOU GOT SLIMED", 92, UITheme.RED))
	col.add_child(UITheme.title(
		"the forest closes over wave %d" % Game.wave(), 24, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(46))

	var cont := UITheme.button("CONTINUE", 28)
	cont.pressed.connect(_continue)
	col.add_child(cont)

	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_property(col, "modulate:a", 1.0, 0.7)
	t.tween_callback(func() -> void: cont.grab_focus())


func _continue() -> void:
	Audio.play_ui("ui_confirm")
	Game.finish_run()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("shoot"):
		_continue()
		get_viewport().set_input_as_handled()
