extends Control
## The ending.
##
## Shown once per run, the first time the finale boss is cleared. The game had
## no win state at all before this: the loop was endless, bosses repeated with
## scaled HP, and there was nothing to reach. A paid game that cannot be
## completed is a hard sell, and a roguelike whose whole theme is persistence
## without progress needs one moment where the persistence pays.
##
## It does not end the run. CONTINUE puts you straight back into the loop,
## because everything the late game is built on - the boss repeat system, the
## deepest biome holding forever, the whole endless curve - would become dead
## content if beating the Sovereign stopped play.

signal continued
signal ended

const LINES: Array[String] = [
	"The Sovereign comes apart, and the forest lets go of what it was holding.",
	"For the first time since you arrived, nothing is coming.",
	"You could stop here.",
]

var _line_index := 0
var _lines_box: VBoxContainer = null
var _buttons: HBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_reveal()


func _build() -> void:
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.04, 0.06, 0.05, 0.0)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	# fade the world out rather than cutting to a screen, so the ending reads
	# as the run quietening down instead of a scene change
	var fade := create_tween()
	fade.tween_property(back, "color:a", 0.93, 1.2)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := UITheme.title("THE FOREST IS QUIET", 52, UITheme.GOLD)
	title.modulate.a = 0.0
	col.add_child(title)
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_property(title, "modulate:a", 1.0, 0.9)

	col.add_child(UITheme.spacer(10))
	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 10)
	col.add_child(_lines_box)

	col.add_child(UITheme.spacer(24))
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 16)
	_buttons.modulate.a = 0.0
	col.add_child(_buttons)

	var go_on := UITheme.button("CONTINUE", 26)
	go_on.custom_minimum_size = Vector2(280, 56)
	go_on.pressed.connect(func() -> void:
		Audio.play_ui("ui_confirm", -6.0)
		continued.emit())
	_buttons.add_child(go_on)

	var stop := UITheme.button("END THE RUN", 26)
	stop.custom_minimum_size = Vector2(280, 56)
	stop.pressed.connect(func() -> void:
		Audio.play_ui("ui_click", -8.0)
		ended.emit())
	_buttons.add_child(stop)


## One line at a time. The pacing is the point - this is the only moment in the
## game that is allowed to be slow.
func _reveal() -> void:
	if _line_index >= LINES.size():
		var t := create_tween()
		t.tween_interval(0.5)
		t.tween_property(_buttons, "modulate:a", 1.0, 0.6)
		return

	var l := UITheme.label(LINES[_line_index], 22, UITheme.TEXT, 6)
	l.custom_minimum_size = Vector2(720, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	_lines_box.add_child(l)
	_line_index += 1

	var t := create_tween()
	t.tween_interval(1.4 if _line_index == 1 else 0.5)
	t.tween_property(l, "modulate:a", 1.0, 0.8)
	t.tween_callback(_reveal)
