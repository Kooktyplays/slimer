extends Control
## Credits.
##
## The GDQuest attribution here is not decoration - the art pack is
## CC BY-NC-SA 4.0, which requires the asset name, a link to the original,
## attribution to GDQuest, a link to GDQuest, a link to the licence, and a
## statement that the assets were modified, all visible to the audience. For a
## game the licence names the credits screen as the right place. Do not trim
## this block down. See LICENSE-ASSETS.md and RIGHTS.md.

## Edit this one line to change the name shown throughout the screen.
const AUTHOR := "Tanav Yedlapalli"

const GDQUEST_URL := "https://gdquest.com"
const ASSET_URL := "https://github.com/gdquest-demos/getting-started-with-godot-4"
const LICENSE_URL := "https://creativecommons.org/licenses/by-nc-sa/4.0/deed.en"

const ENTRIES: Array[Dictionary] = [
	{"role": "Design and development", "name": AUTHOR},
	{"role": "Music", "name": AUTHOR},
	{"role": "Sprites and sound effects", "name": "Procedurally generated"},
	{"role": "Engine", "name": "Godot 4.4.1"},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# the same drifting slimes as the title screen, so this reads as part of
	# the game rather than a text dump
	var deco := Node2D.new()
	deco.set_script(preload("res://ui/menu_backdrop.gd"))
	add_child(deco)

	# a panel behind the text: the licence block is dense and has to stay
	# legible over the drifting slimes
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(940, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	col.add_child(UITheme.title("SLIMER", 54, UITheme.GREEN))
	col.add_child(UITheme.title("a forest that does not end", 18, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(16))

	for entry: Dictionary in ENTRIES:
		var row := HBoxContainer.new()
		col.add_child(row)
		var role := UITheme.label(String(entry["role"]), 19, UITheme.TEXT_DIM, 4)
		role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(role)
		row.add_child(UITheme.label(String(entry["name"]), 19, UITheme.TEXT, 4))

	col.add_child(UITheme.spacer(18))
	col.add_child(UITheme.label("ART ASSETS", 20, UITheme.GOLD, 4))

	# Built by concatenation on purpose. Writing this as "a" + "b" % [...] binds
	# the format to the last fragment only, and the earlier URLs render as a
	# literal "%s" - which in a licence notice is worse than no notice at all.
	var attribution_text := (
		"This game contains a modified derivative of \"Your First 2D Game With "
		+ "Godot 4 — 2D project assets\" by GDQuest (" + GDQUEST_URL + "), used "
		+ "and re-released under CC BY-NC-SA 4.0 (" + LICENSE_URL + "). "
		+ "The original can be found at " + ASSET_URL + ". Changes were made: "
		+ "the slime was recoloured into six enemy types, the player was "
		+ "recoloured and outlined, and the potion sheets were sliced into "
		+ "single bottles.")
	var attribution := UITheme.label(attribution_text, 15, UITheme.TEXT_DIM, 3)
	attribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(attribution)

	col.add_child(UITheme.spacer(10))
	var noncommercial := UITheme.label(
		"That licence is NonCommercial: this game may be shared freely, but not sold.",
		15, UITheme.GOLD, 3)
	noncommercial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(noncommercial)

	col.add_child(UITheme.spacer(14))
	var stats := UITheme.label(
		"%d runs    best: wave %d    %d enemies felled" % [
			int(Save.stats["runs"]), int(Save.stats["best_wave"]),
			int(Save.stats["total_kills"])],
		16, UITheme.TEXT_DIM, 3)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stats)

	col.add_child(UITheme.spacer(14))
	var back := UITheme.button("BACK", 22)
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(func() -> void: Game.go_to_main_menu())
	col.add_child(back)
	back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.go_to_main_menu()
