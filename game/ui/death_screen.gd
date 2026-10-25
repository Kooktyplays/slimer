extends Control
## Shown over the still-standing world the moment the player dies.
##
## Deliberately slow: a beat of silence, the wave you reached, then the button.
## Snapping straight to a results table would rob the death of its weight.

## One of these under the wave number, picked at random.
##
## There used to be exactly one death message, and it was "YOU GOT SLIMED" in
## ninety-two point red - which is a joke from a different game than the one the
## victory screen and the class blurbs are written for. Dying is the thing the
## player will see most often in a roguelike; it was the only screen in the game
## with nothing to say.
const LINES: Array[String] = [
	"it closes over the place where you were",
	"nothing here was ever going to let you leave",
	"the trees do not move aside for this",
	"you were already dead. this is only the rest of it",
	"something further in has stopped paying attention",
	"the ground takes it back",
	"you get up from this. you always get up from this",
]


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

	col.add_child(UITheme.title("THE FOREST KEEPS YOU", 92, UITheme.RED))
	col.add_child(UITheme.title(
		"wave %d" % Game.wave(), 24, UITheme.TEXT_DIM))
	col.add_child(UITheme.title(LINES[randi() % LINES.size()], 22,
		UITheme.TEXT_DIM))
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
