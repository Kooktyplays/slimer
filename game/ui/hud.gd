extends Control
## The in-run HUD.
##
## Layout follows where the player's attention already is: health bottom-left
## near the character, ammo bottom-right near the cursor hand, wave and money
## along the top out of the combat area, boss bar across the top where it
## can't hide anything. Nothing is drawn in the middle third of the screen
## except transient callouts.

const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")

var player: Player = null
var waves: WaveController = null

var _hp_fill: ColorRect
var _hp_label: Label
var _shield_fill: ColorRect
var _swift_holder: Control
var _swift_fill: ColorRect
var _poison_holder: Control
var _poison_fill: ColorRect
var _poison_label: Label

const POISON_COLOR := Color(0.62, 0.85, 0.25)
var _wave_label: Label
var _depth_label: Label
var _enemies_label: Label
var _money_label: Label
var _ammo_label: Label
var _reload_bar: ColorRect
var _reload_holder: Control
var _slots: Array = []
var _vignette: ColorRect
var _boss_panel: Control
var _boss_name: Label
var _boss_fill: ColorRect
var _boss_phase: Label
var _toast_holder: VBoxContainer
var _hint_label: Label

var _boss: Boss = null
var _boss_fade: Tween = null
var _damage_pulse := 0.0
var _hp_display := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect_events()


func bind(p: Player, w: WaveController) -> void:
	player = p
	waves = w
	if p != null:
		p.health_changed.connect(_on_health_changed)
		p.gun.ammo_changed.connect(_on_ammo_changed)
		p.abilities.slot_changed.connect(_on_slot_changed)
		_on_health_changed(Game.run.hp, Game.run.max_hp)
		_on_ammo_changed(p.gun.ammo, p.gun.magazine_size())
		for i in AbilitiesDB.SLOT_COUNT:
			_on_slot_changed(i)
	_on_money_changed(Game.run.money if Game.run != null else 0, 0)
	if Game.wave() >= 1:
		_on_wave_started(Game.wave(), Game.depth())
	else:
		# bound during the calm beat before wave 1 - "WAVE 0" is not a thing
		_wave_label.text = "GET READY"
		_depth_label.text = "FOREST DEPTH 1"


func _connect_events() -> void:
	Events.money_changed.connect(_on_money_changed)
	Events.wave_started.connect(_on_wave_started)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_phase_changed.connect(_on_boss_phase)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.player_damaged.connect(_on_player_damaged)
	Events.toast.connect(show_toast)
	Events.tutorial_hint.connect(_on_hint)
	# swap SPACE/SHIFT for A/B when the player picks up a controller
	Game.input_device_changed.connect(func(_d: String) -> void:
		for slot: AbilitySlot in _slots:
			slot.refresh_hotkey())


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------
func _build() -> void:
	_build_vignette()
	_build_health()
	_build_top_bar()
	_build_ammo()
	_build_abilities()
	_build_boss_bar()
	_build_toasts()


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE_SHADER
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("tint", Color(0.85, 0.10, 0.12))
	_vignette.material = mat
	add_child(_vignette)


func _build_health() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	root.position = Vector2(40, -104)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	root.add_child(UITheme.icon("res://assets/sprites/gen/icon_heart.png", 34, UITheme.RED))

	var back := ColorRect.new()
	back.color = Color(0.06, 0.09, 0.07, 0.85)
	back.position = Vector2(44, 4)
	back.size = Vector2(360, 28)
	root.add_child(back)

	_hp_fill = ColorRect.new()
	_hp_fill.color = UITheme.GREEN
	_hp_fill.position = Vector2(47, 7)
	_hp_fill.size = Vector2(354, 22)
	root.add_child(_hp_fill)

	# shield sits on top of health rather than beside it, so "how much can I
	# take right now" is one bar to read, not two
	_shield_fill = ColorRect.new()
	_shield_fill.color = Color(0.45, 0.78, 1.0, 0.85)
	_shield_fill.position = Vector2(47, 7)
	_shield_fill.size = Vector2(0, 22)
	root.add_child(_shield_fill)

	_hp_label = UITheme.label("100 / 100", 20)
	_hp_label.position = Vector2(52, 6)
	root.add_child(_hp_label)

	_build_status_bar(root)


## Timed buffs, shown under the health bar.
##
## The Swift potion had no readout at all: it changed how the player moved for
## nine seconds with nothing on screen saying so, and no way to tell whether it
## was about to run out. Sits under health because it is the same question -
## what is true about me right now - and the player is already looking there.
func _build_status_bar(root: Control) -> void:
	_swift_holder = Control.new()
	_swift_holder.position = Vector2(44, 38)
	_swift_holder.visible = false
	_swift_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_swift_holder)

	var back := ColorRect.new()
	back.color = Color(0.06, 0.09, 0.07, 0.85)
	back.size = Vector2(200, 14)
	_swift_holder.add_child(back)

	_swift_fill = ColorRect.new()
	_swift_fill.color = UITheme.BLUE
	_swift_fill.position = Vector2(2, 2)
	_swift_fill.size = Vector2(196, 10)
	_swift_holder.add_child(_swift_fill)

	var label := UITheme.label("SWIFT", 14, UITheme.BLUE)
	label.position = Vector2(206, -2)
	_swift_holder.add_child(label)

	# Poison sits on the same row. The player has to be able to tell the
	# difference between "I am hurt" and "I am still taking damage right now",
	# because the answer changes whether they should retreat or push.
	_poison_holder = Control.new()
	_poison_holder.position = Vector2(44, 56)
	_poison_holder.visible = false
	_poison_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_poison_holder)

	var pback := ColorRect.new()
	pback.color = Color(0.06, 0.09, 0.07, 0.85)
	pback.size = Vector2(200, 14)
	_poison_holder.add_child(pback)

	_poison_fill = ColorRect.new()
	_poison_fill.color = POISON_COLOR
	_poison_fill.position = Vector2(2, 2)
	_poison_fill.size = Vector2(196, 10)
	_poison_holder.add_child(_poison_fill)

	_poison_label = UITheme.label("POISON", 14, POISON_COLOR)
	_poison_label.position = Vector2(206, -2)
	_poison_holder.add_child(_poison_label)


func _build_top_bar() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_wave_label = UITheme.label("WAVE 1", 40, UITheme.TEXT, 8)
	_wave_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wave_label.position = Vector2(-140, 18)
	_wave_label.size = Vector2(280, 46)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_wave_label)

	_depth_label = UITheme.label("FOREST DEPTH 1", 19, UITheme.TEXT_DIM)
	_depth_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_depth_label.position = Vector2(-140, 64)
	_depth_label.size = Vector2(280, 24)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_depth_label)

	_enemies_label = UITheme.label("", 18, UITheme.TEXT_DIM)
	_enemies_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_enemies_label.position = Vector2(-140, 90)
	_enemies_label.size = Vector2(280, 22)
	_enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_enemies_label)

	var money_row := HBoxContainer.new()
	money_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_row.position = Vector2(-230, 24)
	money_row.size = Vector2(190, 40)
	money_row.alignment = BoxContainer.ALIGNMENT_END
	money_row.add_theme_constant_override("separation", 10)
	root.add_child(money_row)
	money_row.add_child(UITheme.icon("res://assets/sprites/gen/icon_coin.png", 30, UITheme.GOLD))
	_money_label = UITheme.label("0", 32, UITheme.GOLD)
	money_row.add_child(_money_label)


func _build_ammo() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	root.position = Vector2(-300, -120)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	row.add_child(UITheme.icon("res://assets/sprites/gen/icon_ammo.png", 32, UITheme.TEXT))
	_ammo_label = UITheme.label("12 / 12", 34)
	row.add_child(_ammo_label)

	_reload_holder = Control.new()
	_reload_holder.position = Vector2(0, 48)
	_reload_holder.visible = false
	root.add_child(_reload_holder)

	var back := ColorRect.new()
	back.color = Color(0.06, 0.09, 0.07, 0.85)
	back.size = Vector2(220, 12)
	_reload_holder.add_child(back)

	_reload_bar = ColorRect.new()
	_reload_bar.color = UITheme.GOLD
	_reload_bar.position = Vector2(2, 2)
	_reload_bar.size = Vector2(0, 8)
	_reload_holder.add_child(_reload_bar)

	var t := UITheme.label("RELOADING", 15, UITheme.GOLD)
	t.position = Vector2(0, 14)
	_reload_holder.add_child(t)


func _build_abilities() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	root.position = Vector2(40, -252)
	root.add_theme_constant_override("separation", 16)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Movement slot first, then the general pair - the same order as the picker
	# and the keybinds screen, so the icons match the keys left to right.
	const SLOT_ACTIONS := ["ability_movement", "ability_1", "ability_2"]
	for i in AbilitiesDB.SLOT_COUNT:
		var slot := AbilitySlot.new()
		slot.custom_minimum_size = Vector2(74, 74)
		slot.action = SLOT_ACTIONS[i] if i < SLOT_ACTIONS.size() else "ability_1"
		slot.is_movement = (AbilitiesDB.class_for_slot(i)
			== AbilitiesDB.CLASS_MOVEMENT)
		slot.refresh_hotkey()
		root.add_child(slot)
		_slots.append(slot)


func _build_boss_bar() -> void:
	_boss_panel = Control.new()
	_boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-460, 132)
	_boss_panel.size = Vector2(920, 76)
	_boss_panel.visible = false
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_panel)

	_boss_name = UITheme.label("BOSS", 30, UITheme.TEXT)
	_boss_name.size = Vector2(920, 34)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_panel.add_child(_boss_name)

	var back := ColorRect.new()
	back.color = Color(0.06, 0.09, 0.07, 0.9)
	back.position = Vector2(0, 40)
	back.size = Vector2(920, 26)
	_boss_panel.add_child(back)

	_boss_fill = ColorRect.new()
	_boss_fill.color = UITheme.RED
	_boss_fill.position = Vector2(3, 43)
	_boss_fill.size = Vector2(914, 20)
	_boss_panel.add_child(_boss_fill)

	_boss_phase = UITheme.label("", 16, UITheme.TEXT)
	_boss_phase.position = Vector2(0, 41)
	_boss_phase.size = Vector2(920, 22)
	_boss_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_panel.add_child(_boss_phase)


func _build_toasts() -> void:
	_toast_holder = VBoxContainer.new()
	_toast_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_holder.position = Vector2(-300, 250)
	_toast_holder.size = Vector2(600, 200)
	_toast_holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_holder)

	_hint_label = UITheme.label("", 24, UITheme.GOLD)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position = Vector2(-450, -290)
	_hint_label.size = Vector2(900, 40)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.modulate.a = 0.0
	add_child(_hint_label)


# ---------------------------------------------------------------------------
# updates
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if Game.run == null:
		return

	# health bar eases towards the true value so chip damage is visible
	var target := Game.run.hp_fraction()
	_hp_display = move_toward(_hp_display, target, delta * maxf(0.6, absf(_hp_display - target) * 6.0))
	_hp_fill.size.x = 354.0 * _hp_display
	_hp_fill.color = UITheme.GREEN.lerp(UITheme.RED, 1.0 - clampf(target / 0.6, 0.0, 1.0))

	if player != null and is_instance_valid(player):
		var shield_frac := clampf(player.shield_absorb / maxf(Game.run.max_hp, 1.0), 0.0, 1.0)
		_shield_fill.size.x = 354.0 * shield_frac
		_shield_fill.visible = shield_frac > 0.001

		_reload_holder.visible = player.gun.reloading
		if player.gun.reloading:
			_reload_bar.size.x = 216.0 * player.gun.reload_fraction()

		var swift := player.speed_boost_fraction()
		_swift_holder.visible = swift > 0.0
		if swift > 0.0:
			_swift_fill.size.x = 196.0 * swift
			# flash the last second so it is obvious the boost is about to end
			_swift_fill.color = (UITheme.BLUE if player.speed_boost_left > 1.0
				else UITheme.BLUE.lerp(UITheme.TEXT,
					0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0)))

		var poison := player.poison_fraction()
		_poison_holder.visible = poison > 0.0
		if poison > 0.0:
			_poison_fill.size.x = 196.0 * poison
			_poison_label.text = ("POISON x%d" % player.poison_stacks
				if player.poison_stacks > 1 else "POISON")

		for i in _slots.size():
			(_slots[i] as AbilitySlot).set_progress(player.abilities.charge_fraction(i))
			var s: Dictionary = player.abilities.slots[i]
			if not s.is_empty():
				(_slots[i] as AbilitySlot).set_charges(
					int(s["charges"]), int(s["max_charges"]))

	# low health and damage flash share the vignette
	var low := 0.0
	if Game.run.is_low_health():
		low = 0.26 + 0.12 * sin(Time.get_ticks_msec() / 220.0)
	_damage_pulse = maxf(0.0, _damage_pulse - delta * 2.4)
	var mat := _vignette.material as ShaderMaterial
	mat.set_shader_parameter("intensity", maxf(low, _damage_pulse))

	if waves != null and is_instance_valid(waves):
		var n := Combat.enemy_count()
		_enemies_label.text = ("%d remaining" % n) if n > 0 else ""

	if _boss != null and is_instance_valid(_boss) and not _boss.dying:
		_boss_fill.size.x = 914.0 * _boss.health_fraction()
	elif _boss_panel.visible and (_boss == null or not is_instance_valid(_boss)):
		_hide_boss()


func _on_health_changed(hp: float, max_hp: float) -> void:
	_hp_label.text = "%d / %d" % [ceil(hp), ceil(max_hp)]


func _on_ammo_changed(current: int, magazine: int) -> void:
	_ammo_label.text = "%d / %d" % [current, magazine]
	_ammo_label.modulate = UITheme.RED if current == 0 else UITheme.TEXT


func _on_slot_changed(slot: int) -> void:
	if player == null or slot >= _slots.size():
		return
	var s: Dictionary = player.abilities.slots[slot]
	if s.is_empty():
		return
	(_slots[slot] as AbilitySlot).set_ability(String(s["id"]))
	(_slots[slot] as AbilitySlot).set_charges(int(s["charges"]), int(s["max_charges"]))


func _on_money_changed(total: int, delta: int) -> void:
	_money_label.text = str(total)
	if delta > 0:
		# a quick pop, so money landing is felt and not just displayed
		var t := create_tween()
		t.tween_property(_money_label, "scale", Vector2.ONE * 1.22, 0.07)
		t.tween_property(_money_label, "scale", Vector2.ONE, 0.13)


func _on_wave_started(wave: int, depth: int) -> void:
	_wave_label.text = "WAVE %d" % wave
	_depth_label.text = "FOREST DEPTH %d" % depth
	var t := create_tween()
	t.tween_property(_wave_label, "scale", Vector2.ONE * 1.28, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_wave_label, "scale", Vector2.ONE, 0.22)
	show_toast("WAVE %d" % wave, UITheme.TEXT)


func _on_player_damaged(_amount: float, _from: Vector2) -> void:
	_damage_pulse = 0.42


func _on_boss_spawned(boss: Node2D, display_name: String, is_major: bool) -> void:
	# A boss can appear while the previous one's bar is still fading out. That
	# fade ends by setting the panel invisible, which would hide the new boss's
	# bar for the whole fight, so the old tween has to die here.
	if _boss_fade != null and _boss_fade.is_valid():
		_boss_fade.kill()
	_boss = boss as Boss
	_boss_panel.visible = true
	_boss_panel.modulate.a = 0.0
	_boss_name.text = display_name.to_upper()
	_boss_name.modulate = UITheme.GOLD if is_major else UITheme.TEXT
	_boss_fill.color = Color(0.86, 0.24, 0.30) if is_major else UITheme.RED
	_boss_fill.size.x = 914.0
	_boss_phase.text = "PHASE 1 / %d" % _boss.phase_count
	_boss_fade = create_tween()
	_boss_fade.tween_property(_boss_panel, "modulate:a", 1.0, 0.5)
	show_toast(("%s\n%s" % [display_name, BossDB.get_def(_boss.id)["title"]]),
		UITheme.GOLD if is_major else UITheme.RED)


func _on_boss_phase(boss: Node2D, phase: int) -> void:
	if boss != _boss:
		return
	_boss_phase.text = "PHASE %d / %d" % [phase, _boss.phase_count]
	var t := create_tween()
	t.tween_property(_boss_panel, "scale", Vector2(1.03, 1.15), 0.12)
	t.tween_property(_boss_panel, "scale", Vector2.ONE, 0.2)


func _on_boss_defeated(_boss: Node2D) -> void:
	_hide_boss()


func _hide_boss() -> void:
	_boss = null
	if not _boss_panel.visible:
		return
	if _boss_fade != null and _boss_fade.is_valid():
		_boss_fade.kill()
	_boss_fade = create_tween()
	_boss_fade.tween_property(_boss_panel, "modulate:a", 0.0, 0.4)
	_boss_fade.tween_callback(func() -> void: _boss_panel.visible = false)


# ---------------------------------------------------------------------------
# toasts and hints
# ---------------------------------------------------------------------------
func show_toast(text: String, color: Color) -> void:
	var l := UITheme.label(text, 30, color, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.add_child(l)
	var t := create_tween()
	t.tween_property(l, "modulate:a", 1.0, 0.15).from(0.0)
	t.tween_interval(1.9)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


func _on_hint(_id: String, text: String) -> void:
	_hint_label.text = text
	var t := create_tween()
	t.tween_property(_hint_label, "modulate:a", 1.0, 0.3)
	t.tween_interval(4.2)
	t.tween_property(_hint_label, "modulate:a", 0.0, 0.7)


# ---------------------------------------------------------------------------
# ability slot widget
# ---------------------------------------------------------------------------
class AbilitySlot extends Control:
	var action := "ability_1"
	## True for the dedicated movement slot, which gets its own marking.
	var is_movement := false
	var hotkey := ""
	var _progress := 1.0
	var _charges := 1
	var _max_charges := 1
	var _icon: Texture2D = null
	var _ready_pulse := 0.0

	## Re-read the caption from the live bindings, so it follows a rebind and
	## switches between "SPACE" and "A" with the active device.
	func refresh_hotkey() -> void:
		hotkey = InputBinds.label_for_action(
			Save.keybinds, action, Game.input_device).to_upper()
		queue_redraw()

	func set_ability(id: String) -> void:
		var path := AbilitiesDB.icon_path(id)
		_icon = load(path) if ResourceLoader.exists(path) else null
		queue_redraw()

	func set_progress(v: float) -> void:
		if not is_equal_approx(v, _progress):
			_progress = v
			queue_redraw()

	func set_charges(current: int, maximum: int) -> void:
		if current > _charges:
			_ready_pulse = 1.0
		if current != _charges or maximum != _max_charges:
			_charges = current
			_max_charges = maximum
			queue_redraw()

	func _process(delta: float) -> void:
		if _ready_pulse > 0.0:
			_ready_pulse = maxf(0.0, _ready_pulse - delta * 2.2)
			queue_redraw()

	func _draw() -> void:
		var r := size.x * 0.5
		var c := size * 0.5
		var usable := _charges > 0

		draw_circle(c, r, Color(0.07, 0.10, 0.08, 0.9))
		if _ready_pulse > 0.0:
			draw_arc(c, r + 5.0 * _ready_pulse, 0, TAU, 40,
				Color(1.0, 0.85, 0.4, _ready_pulse * 0.8), 3.0, true)

		if _icon != null:
			var s := r * 1.22
			draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false,
				Color(1, 1, 1, 1.0 if usable else 0.32))

		# cooldown sweep: unfilled arc shows what's left
		if _progress < 1.0:
			draw_arc(c, r - 4.0, -PI / 2 + TAU * _progress, -PI / 2 + TAU, 44,
				Color(0.05, 0.07, 0.05, 0.72), 9.0, true)
		draw_arc(c, r - 1.0, 0, TAU, 46,
			UITheme.GOLD if usable else Color(0.30, 0.35, 0.30), 3.0, true)

		# charge pips, only when the ability can hold more than one
		if _max_charges > 1:
			for i in _max_charges:
				var a := -PI / 2 + (i - (_max_charges - 1) * 0.5) * 0.42
				var p := c + Vector2(cos(a), sin(a)) * (r + 12.0)
				draw_circle(p, 4.5, UITheme.GOLD if i < _charges else Color(0.25, 0.30, 0.25))

		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(-r, r + 20.0), hotkey,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(0.62, 0.70, 0.62))

		# A second ring and a caption on the movement slot, so which key is the
		# dedicated movement one is readable at a glance. The picker and the shop
		# already label MOVEMENT vs GENERAL; in the run itself the three slots were
		# indistinguishable.
		if is_movement:
			draw_arc(c, r + 5.0, 0, TAU, 46, Color(0.45, 0.78, 1.0, 0.75), 2.0, true)
			draw_string(f, c + Vector2(-r, -r - 9.0), "MOVE",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.45, 0.78, 1.0, 0.9))
