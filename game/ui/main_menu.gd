extends Control
## Title screen.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# a few slimes drifting behind the title, so the menu isn't a dead screen
	var deco := Node2D.new()
	deco.set_script(preload("res://ui/menu_backdrop.gd"))
	add_child(deco)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(440, 0)
	center.add_child(col)

	col.add_child(UITheme.title("SLIMER", 104, UITheme.GREEN))
	col.add_child(UITheme.spacer(40))

	var start := UITheme.button("NEW RUN", 30)
	start.pressed.connect(func() -> void: Game.go_to_loadout())
	col.add_child(start)

	var meta := UITheme.button("UPGRADES", 26)
	meta.pressed.connect(func() -> void: Game.go_to_meta())
	col.add_child(meta)

	var credits := UITheme.button("CREDITS", 26)
	credits.pressed.connect(func() -> void: Game.go_to_credits())
	col.add_child(credits)

	var settings := UITheme.button("SETTINGS", 26)
	settings.pressed.connect(func() -> void:
		var main := Main.instance()
		if main != null:
			main.call("open_settings"))
	col.add_child(settings)

	if not OS.has_feature("web"):
		var quit := UITheme.button("QUIT", 26)
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)

	col.add_child(UITheme.spacer(28))
	col.add_child(_stats_line())
	# give the controller somewhere to start
	start.grab_focus()


func _stats_line() -> Control:
	var runs := int(Save.stats["runs"])
	if runs == 0:
		var first := UITheme.label(
			"WASD to move.  Mouse to aim.  Click to shoot.", 18, UITheme.TEXT_DIM)
		first.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return first
	var l := UITheme.label(
		"%d runs    best: wave %d    %d essence" % [
			runs, int(Save.stats["best_wave"]), Save.essence],
		18, UITheme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
