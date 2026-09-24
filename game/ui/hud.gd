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
## The Hollow's dark. A second vignette under the health one, because that one
## is already driven by low health and damage flashes and the two would fight
## over a single intensity. Pulled wider and kept off the middle of the screen:
## the shader's own note is that the centre is where the player is fighting and
## tinting it trades information for atmosphere, which is exactly the trade a
## "reduced sight" biome must not make.
var _gloom: ColorRect
var _boss_panel: Control
var _boss_name: Label
var _boss_phase: Label
## One pair per phase. Built to BossDB.max_phases() up front so arriving at a
## boss never allocates mid-fight, then shown to suit whatever phase count the
## boss actually reports.
var _boss_seg_back: Array[ColorRect] = []
var _boss_seg_fill: Array[ColorRect] = []
var _boss_seg_count := 0
var _boss_fill_colour := UITheme.RED
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
		_depth_label.text = "GREENWOOD  \u00b7  DEPTH 1"


func _connect_events() -> void:
	Events.money_changed.connect(_on_money_changed)
	Events.wave_started.connect(_on_wave_started)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_phase_changed.connect(_on_boss_phase)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.player_damaged.connect(_on_player_damaged)
	Events.toast.connect(show_toast)
	Events.tutorial_hint.connect(_on_hint)
	Events.achievement_unlocked.connect(func(id: String) -> void:
		var def := AchievementsDB.get_def(id)
		if not def.is_empty():
			show_toast("ACHIEVEMENT\n%s" % def["name"], UITheme.GOLD))
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
	_build_ultimate()
	_build_combo()
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

	_gloom = ColorRect.new()
	_gloom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gmat := ShaderMaterial.new()
	gmat.shader = VIGNETTE_SHADER
	gmat.set_shader_parameter("intensity", 0.0)
	gmat.set_shader_parameter("tint", Color(0.04, 0.05, 0.10))
	gmat.set_shader_parameter("inner", 0.45)
	gmat.set_shader_parameter("outer", 1.35)
	_gloom.material = gmat
	add_child(_gloom)          # under the health vignette, added next

	add_child(_vignette)
	Events.biome_changed.connect(func(id: String, display_name: String) -> void:
		set_gloom(String(BiomeDB.get_def(id)["hazard"]) == BiomeDB.HAZARD_GLOOM)
		var def := BiomeDB.get_def(id)
		show_toast("%s — %s" % [display_name.to_upper(),
			String(def.get("subtitle", ""))], Color(0.82, 0.88, 1.0)))


## Fade the dark in or out. Tweened rather than snapped: descending into The
## Hollow should feel like the light going, not like a setting changing.
func set_gloom(on: bool) -> void:
	if _gloom == null:
		return
	var mat := _gloom.material as ShaderMaterial
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("intensity", v),
		float(mat.get_shader_parameter("intensity")), 0.72 if on else 0.0, 1.1)


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

	_depth_label = UITheme.label("GREENWOOD  \u00b7  DEPTH 1", 19, UITheme.TEXT_DIM)
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


## The ultimate meter, sat to the right of the three ability slots.
##
## Deliberately a different shape from an ability slot - those are square and
## keyed, this is a bar that fills - because an ultimate is not a fourth
## ability. It is the thing you are working toward for the whole run.
var _ult_root: Control = null
var _ult_fill: ColorRect = null
var _ult_label: Label = null
var _ult_ready := false


func _build_ultimate() -> void:
	_ult_root = Control.new()
	_ult_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_ult_root.position = Vector2(320, -252)
	_ult_root.custom_minimum_size = Vector2(210, 74)
	_ult_root.size = Vector2(210, 74)
	_ult_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ult_root)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.42)
	back.position = Vector2(0, 44)
	back.size = Vector2(210, 18)
	_ult_root.add_child(back)

	_ult_fill = ColorRect.new()
	_ult_fill.position = Vector2(2, 46)
	_ult_fill.size = Vector2(0, 14)
	_ult_root.add_child(_ult_fill)

	_ult_label = UITheme.label("", 17, UITheme.TEXT_DIM, 4)
	_ult_label.position = Vector2(0, 20)
	_ult_label.size = Vector2(210, 22)
	_ult_root.add_child(_ult_label)

	Events.ultimate_charge_changed.connect(_on_ultimate_charge)
	_on_ultimate_charge(Game.run.ultimate_charge if Game.run != null else 0.0)


func _on_ultimate_charge(fraction: float) -> void:
	if _ult_fill == null or Game.run == null:
		return
	var def := ClassesDB.get_def(Game.run.class_id)
	var tint: Color = def["tint"]
	_ult_fill.size.x = 206.0 * clampf(fraction, 0.0, 1.0)
	var ready := fraction >= 1.0
	_ult_fill.color = tint if ready else Color(tint.r, tint.g, tint.b, 0.55)
	if ready and not _ult_ready:
		# Only on the transition, not every frame it stays full.
		Audio.play_ui("unlock", -6.0)
		FX.floating_text(player.global_position + Vector2(0, -130),
			"%s READY" % String(def["ultimate_name"]).to_upper(), tint) \
			if player != null and is_instance_valid(player) else null
	_ult_ready = ready
	_ult_label.text = ("%s  [%s]" % [String(def["ultimate_name"]).to_upper(),
		InputBinds.label_for_action(Save.keybinds, "ultimate", Game.input_device).to_upper()]) if ready \
		else String(def["ultimate_name"]).to_upper()
	_ult_label.add_theme_color_override("font_color",
		tint if ready else UITheme.TEXT_DIM)


## Combo counter. Only on screen while a chain is alive, so it is a reward for
## doing something rather than a permanent piece of furniture.
var _combo_label: Label = null


func _build_combo() -> void:
	_combo_label = UITheme.label("", 30, UITheme.TEXT, 6)
	_combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_combo_label.position = Vector2(-260, -40)
	_combo_label.size = Vector2(220, 44)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.visible = false
	add_child(_combo_label)
	Events.combo_changed.connect(_on_combo)


## One per combo tier, so this has to be RunState.COMBO_TIER_MAX + 1 long.
## It is read through a clampi, which means a short table does not crash - the
## counter just silently stops changing colour at the top, which is exactly
## where the escalation is supposed to be loudest.
const COMBO_TIER_COLOURS: Array[Color] = [
	Color(0.80, 0.85, 0.80), Color(0.75, 0.95, 0.70),
	Color(1.00, 0.85, 0.35), Color(1.00, 0.55, 0.35),
	Color(1.00, 0.36, 0.42), Color(1.00, 0.62, 1.00),
]


func _on_combo(count: int, tier: int) -> void:
	if _combo_label == null:
		return
	# Below the first tier there is nothing to celebrate yet, and a counter that
	# flickers on at every single kill is noise rather than feedback.
	if count < 4:
		_combo_label.visible = false
		return
	_combo_label.visible = true
	_combo_label.text = "%d×" % count
	_combo_label.add_theme_color_override("font_color",
		COMBO_TIER_COLOURS[clampi(tier, 0, COMBO_TIER_COLOURS.size() - 1)])
	var t := create_tween()
	t.tween_property(_combo_label, "scale", Vector2.ONE * (1.0 + 0.05 * tier), 0.06)
	t.tween_property(_combo_label, "scale", Vector2.ONE, 0.12)


## The boss bar: one segment per phase, across most of the screen.
##
## It was one continuous 920px fill with a "PHASE 2 / 3" caption, which asked
## the player to hold the phase count in their head and divide. The phases are
## already evenly spaced health thresholds, so a segment per phase is the same
## information drawn as what it is - how many more times this fight is going to
## change, and how far into the current one you are.
##
## Segment boundaries come from Boss.phase_segment_fill so they cannot drift
## from _check_phase. A bar that promises a change slightly early or late is
## worse than no bar.
const BOSS_BAR_W := 1440.0
const BOSS_BAR_H := 26.0
const BOSS_BAR_Y := 40.0
const BOSS_SEG_GAP := 6.0
const BOSS_SEG_INSET := 3.0
const BOSS_SEG_BACK := Color(0.06, 0.09, 0.07, 0.90)
## Phases already fought through. Dark enough to read as spent at a glance
## without going invisible - the shape of the whole bar is what says how long
## the fight is.
const BOSS_SEG_SPENT := Color(0.05, 0.06, 0.05, 0.82)


func _build_boss_bar() -> void:
	_boss_panel = Control.new()
	_boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-BOSS_BAR_W * 0.5, 132)
	_boss_panel.size = Vector2(BOSS_BAR_W, 76)
	_boss_panel.visible = false
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pivot centred so the phase-change pulse grows from the middle instead of
	# shoving a 1440px bar sideways off the screen.
	_boss_panel.pivot_offset = Vector2(BOSS_BAR_W * 0.5, 38)
	add_child(_boss_panel)

	_boss_name = UITheme.label("BOSS", 30, UITheme.TEXT)
	_boss_name.size = Vector2(BOSS_BAR_W, 34)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_panel.add_child(_boss_name)

	for _i in BossDB.max_phases():
		var back := ColorRect.new()
		back.color = BOSS_SEG_BACK
		back.position = Vector2(0, BOSS_BAR_Y)
		back.size = Vector2(0, BOSS_BAR_H)
		_boss_panel.add_child(back)
		_boss_seg_back.append(back)

		var fill := ColorRect.new()
		fill.color = UITheme.RED
		fill.position = Vector2(BOSS_SEG_INSET, BOSS_BAR_Y + BOSS_SEG_INSET)
		fill.size = Vector2(0, BOSS_BAR_H - BOSS_SEG_INSET * 2.0)
		_boss_panel.add_child(fill)
		_boss_seg_fill.append(fill)

	# Kept even though the segments now say the same thing: on a 4-phase repeat
	# boss the caption is what reads at a glance, and counting segments while
	# something is charging at you is not reading.
	_boss_phase = UITheme.label("", 16, UITheme.TEXT)
	_boss_phase.position = Vector2(0, BOSS_BAR_Y + 1.0)
	_boss_phase.size = Vector2(BOSS_BAR_W, 22)
	_boss_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_panel.add_child(_boss_phase)


## Lay the segments out for a boss with `count` phases and show that many.
func _layout_boss_segments(count: int) -> void:
	_boss_seg_count = clampi(count, 1, _boss_seg_back.size())
	var seg_w := (BOSS_BAR_W - BOSS_SEG_GAP * (_boss_seg_count - 1)) \
		/ float(_boss_seg_count)
	for i in _boss_seg_back.size():
		var shown := i < _boss_seg_count
		_boss_seg_back[i].visible = shown
		_boss_seg_fill[i].visible = shown
		if not shown:
			continue
		var x := i * (seg_w + BOSS_SEG_GAP)
		_boss_seg_back[i].position.x = x
		_boss_seg_back[i].size.x = seg_w
		_boss_seg_fill[i].position.x = x + BOSS_SEG_INSET
		_boss_seg_fill[i].size.x = seg_w - BOSS_SEG_INSET * 2.0


## Redraw the segments from the boss's health. Segments run left to right as
## the last phase down to phase 1, because phase 1 sits at the top of the
## health pool and the bar drains from the right.
func _update_boss_segments(frac: float, phase: int) -> void:
	var current := _boss_seg_count - phase
	for i in _boss_seg_count:
		var seg_frac := Boss.phase_segment_fill(frac, _boss_seg_count, i)
		var inner := _boss_seg_back[i].size.x - BOSS_SEG_INSET * 2.0
		_boss_seg_fill[i].size.x = inner * seg_frac
		_boss_seg_fill[i].visible = seg_frac > 0.001
		# The phase being fought right now is the bright one; the ones still to
		# come are dimmer, so "how much of this phase is left" reads separately
		# from "how much fight is left". Segments past the current one are
		# empty anyway, so only i < current needs dimming.
		_boss_seg_fill[i].color = (_boss_fill_colour if i == current
			else Color(_boss_fill_colour.r, _boss_fill_colour.g,
				_boss_fill_colour.b, 0.55))
		_boss_seg_back[i].color = (BOSS_SEG_SPENT if i > current
			else BOSS_SEG_BACK)


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
		_update_boss_segments(_boss.health_fraction(), _boss.phase)
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
	# The label has printed a bare depth number since launch, promising a
	# change that never arrived. Naming the biome is the promise being kept.
	_depth_label.text = "%s  \u00b7  DEPTH %d" % [
		String(BiomeDB.for_depth(depth)["name"]).to_upper(), depth]
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
	_boss_fill_colour = Color(0.86, 0.24, 0.30) if is_major else UITheme.RED
	_layout_boss_segments(_boss.phase_count)
	_update_boss_segments(1.0, 1)
	_boss_phase.text = "PHASE 1 / %d" % _boss.phase_count
	_boss_fade = create_tween()
	_boss_fade.tween_property(_boss_panel, "modulate:a", 1.0, 0.5)
	show_toast(("%s\n%s" % [display_name, BossDB.get_def(_boss.id)["title"]]),
		UITheme.GOLD if is_major else UITheme.RED)


func _on_boss_phase(boss: Node2D, phase: int) -> void:
	if boss != _boss:
		return
	_boss_phase.text = "PHASE %d / %d" % [phase, _boss.phase_count]
	# The segment just emptied goes dark here rather than waiting for the next
	# frame, so the bar and the phase callout land together.
	_update_boss_segments(_boss.health_fraction(), phase)
	var t := create_tween()
	t.tween_property(_boss_panel, "scale", Vector2(1.02, 1.15), 0.12)
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
