extends Control
## Run results and the Essence payout.
##
## This is the screen that has to make losing feel like progress, so the
## Essence total counts up rather than appearing, and a new personal best is
## called out explicitly.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var r := Game.last_results
	col.add_child(UITheme.title("RUN COMPLETE", 46, UITheme.GOLD))
	if Game.last_run_was_best:
		var best := UITheme.title("NEW BEST", 26, UITheme.GREEN)
		col.add_child(best)
		# gentle pulse, so the one line worth noticing is the one that moves
		var pulse := create_tween().set_loops()
		pulse.tween_property(best, "modulate:a", 0.45, 0.7)
		pulse.tween_property(best, "modulate:a", 1.0, 0.7)
	col.add_child(UITheme.spacer(18))

	_stat(col, "Wave reached", str(int(r.get("wave", 0))))
	_stat(col, "Enemies killed", str(int(r.get("kills", 0))))
	_stat(col, "Mini-bosses felled", str(int(r.get("minis", 0))))
	_stat(col, "Major bosses felled", str(int(r.get("majors", 0))))
	_stat(col, "Coins earned", str(int(r.get("money_earned", 0))))
	_stat(col, "Damage dealt", str(int(r.get("damage_dealt", 0))))
	_stat(col, "Final DPS", "%.0f" % float(r.get("dps", 0.0)))
	_stat(col, "Time survived", _format_time(int(r.get("duration_ms", 0))))
	_stat(col, "Seed", str(int(r.get("seed", 0))))

	col.add_child(UITheme.spacer(20))

	var essence_row := HBoxContainer.new()
	essence_row.alignment = BoxContainer.ALIGNMENT_CENTER
	essence_row.add_theme_constant_override("separation", 12)
	col.add_child(essence_row)
	essence_row.add_child(UITheme.icon(
		"res://assets/sprites/gen/icon_essence.png", 40, UITheme.PURPLE))
	var essence_label := UITheme.label("+0 ESSENCE", 38, UITheme.PURPLE)
	essence_row.add_child(essence_label)

	var count := create_tween()
	count.tween_method(func(v: float) -> void:
		essence_label.text = "+%d ESSENCE" % int(v),
		0.0, float(Game.last_essence_gained), 1.1).set_delay(0.3)
	count.tween_callback(func() -> void: Audio.play("essence", -6.0))

	col.add_child(UITheme.spacer(24))

	var again := UITheme.button("RUN AGAIN", 28)
	again.custom_minimum_size = Vector2(0, 54)
	again.pressed.connect(func() -> void: Game.go_to_loadout())
	col.add_child(again)

	var upgrades := UITheme.button("SPEND ESSENCE", 24)
	upgrades.pressed.connect(func() -> void: Game.go_to_meta())
	col.add_child(upgrades)

	var menu := UITheme.button("MAIN MENU", 22)
	menu.pressed.connect(func() -> void: Game.go_to_main_menu())
	col.add_child(menu)


func _stat(parent: Node, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UITheme.label(label, 21, UITheme.TEXT_DIM, 4)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(UITheme.label(value, 21, UITheme.TEXT, 4))


func _format_time(ms: int) -> String:
	var total := int(ms / 1000.0)
	return "%d:%02d" % [total / 60, total % 60]
