extends Control
## The between-waves shop.
##
## Six offers, priced so the player can typically afford two. That ratio is
## the design: the shop is a place to make a choice, not a place to collect a
## reward. Repeat purchases of the same upgrade get more expensive, so leaning
## hard into one stat costs real breadth.
##
## Ability swapping lives here too, which is the only in-run moment the
## loadout can change.

const REROLL_LABEL := "REROLL"

var _offers: Array[String] = []
var _rows: VBoxContainer
var _money_label: Label
var _reroll_button: Button
var _rng := RandomNumberGenerator.new()
var _swap_panel: Control = null


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The shop used to read money exactly once, as it built itself, and only
	# redraw it on a purchase or a reroll. Anything that credited money while the
	# shop was already open - a coin still in flight, a late payout - left the
	# header showing a stale balance the player had no way to refresh. The HUD
	# has always tracked this signal; the shop should too.
	Events.money_changed.connect(_on_money_changed)
	_rng.seed = (Game.run.seed_value if Game.run != null else 0) * 977 + Game.wave() * 13
	_roll_offers()
	_build()
	Audio.play("shop_enter", -4.0)
	# fade in rather than snapping, so leaving a fight feels like arriving
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.35)


# ---------------------------------------------------------------------------
# offers
# ---------------------------------------------------------------------------
func _roll_offers() -> void:
	var pool := UpgradesDB.available_ids(Save.unlocks)
	var weighted: Array[String] = []
	for id: String in pool:
		var def := UpgradesDB.get_def(id)
		var weight := float(def["weight"])
		# nudge away from things already bought several times, so the shop
		# keeps offering the player new directions
		weight /= 1.0 + 0.6 * Game.run.times_bought(id)
		# a full heal is worthless at full health, and precious when hurt
		if id == "repair":
			weight *= lerpf(0.15, 3.0, 1.0 - Game.run.hp_fraction())
		var slots := maxi(1, int(round(weight * 10.0)))
		for i in slots:
			weighted.append(id)

	_offers.clear()
	var guard := 0
	while _offers.size() < Balance.SHOP_OFFER_COUNT and guard < 400:
		guard += 1
		if weighted.is_empty():
			break
		var pick: String = weighted[_rng.randi() % weighted.size()]
		if not _offers.has(pick):
			_offers.append(pick)
	# if the pool is smaller than the offer count, show what there is
	for id: String in pool:
		if _offers.size() >= Balance.SHOP_OFFER_COUNT:
			break
		if not _offers.has(id):
			_offers.append(id)


func _price(id: String) -> int:
	return UpgradesDB.price(id, Game.run.times_bought(id))


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------
func _build() -> void:
	for c in get_children():
		c.queue_free()

	add_child(UITheme.dim(0.78))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UITheme.panel()
	panel.custom_minimum_size = Vector2(940, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := UITheme.label("FOREST REST", 42, UITheme.GOLD, 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_money_label = UITheme.label("", 34, UITheme.GOLD)
	header.add_child(_money_label)

	var sub := UITheme.label(
		"Wave %d cleared. Spend what you earned - you cannot buy everything."
			% Game.wave(), 19, UITheme.TEXT_DIM)
	col.add_child(sub)
	col.add_child(UITheme.spacer(8))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	col.add_child(_rows)
	_refresh_rows()

	col.add_child(UITheme.spacer(10))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	_reroll_button = UITheme.button("")
	_reroll_button.custom_minimum_size = Vector2(240, 52)
	_reroll_button.pressed.connect(_on_reroll)
	footer.add_child(_reroll_button)

	var swap := UITheme.button("SWAP ABILITIES")
	swap.custom_minimum_size = Vector2(280, 52)
	swap.pressed.connect(_open_swap)
	footer.add_child(swap)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var leave := UITheme.button("CONTINUE  [F]")
	leave.custom_minimum_size = Vector2(260, 52)
	leave.pressed.connect(_on_continue)
	footer.add_child(leave)

	_refresh_money()


func _refresh_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for id: String in _offers:
		_rows.add_child(_build_row(id))


## One offer: icon, name, what it does, what it costs. Nothing else - the
## brief asks for Item -> Effect -> Cost and that is genuinely all a shop row
## needs to support a decision.
func _build_row(id: String) -> Control:
	var def := UpgradesDB.get_def(id)
	var cost := _price(id)
	var affordable := Game.run.money >= cost

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.PANEL_HI if affordable else Color(0.10, 0.12, 0.10, 0.9),
		_category_color(def["cat"]) if affordable else Color(0.24, 0.28, 0.24),
		2, 8))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	h.add_child(UITheme.icon(_category_icon(def["cat"]), 38,
		_category_color(def["cat"]) if affordable else Color(0.35, 0.38, 0.35)))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	h.add_child(text)

	var name_label := UITheme.label(String(def["name"]), 24,
		UITheme.TEXT if affordable else UITheme.TEXT_DIM, 5)
	text.add_child(name_label)

	var owned := Game.run.times_bought(id)
	var effect := String(def["desc"])
	if owned > 0:
		effect += "     (owned x%d)" % owned
	text.add_child(UITheme.label(effect, 17, UITheme.TEXT_DIM, 4))

	var buy := UITheme.button("%d" % cost, 26)
	buy.custom_minimum_size = Vector2(140, 54)
	buy.disabled = not affordable
	buy.pressed.connect(_on_buy.bind(id))
	h.add_child(buy)

	return row


func _category_color(cat: String) -> Color:
	match cat:
		UpgradesDB.CATEGORY_DAMAGE: return UITheme.RED
		UpgradesDB.CATEGORY_RAPID: return UITheme.GOLD
		UpgradesDB.CATEGORY_PROJECTILE: return UITheme.PURPLE
		UpgradesDB.CATEGORY_SURVIVAL: return UITheme.GREEN
		_: return UITheme.BLUE


func _category_icon(cat: String) -> String:
	match cat:
		UpgradesDB.CATEGORY_DAMAGE: return "res://assets/sprites/gen/icon_nova.png"
		UpgradesDB.CATEGORY_RAPID: return "res://assets/sprites/gen/icon_rapidfire.png"
		UpgradesDB.CATEGORY_PROJECTILE: return "res://assets/sprites/gen/icon_ammo.png"
		UpgradesDB.CATEGORY_SURVIVAL: return "res://assets/sprites/gen/icon_heart.png"
		_: return "res://assets/sprites/gen/icon_dash.png"


## Money moved while the shop is open. Offer affordability is part of the money
## display, so the rows have to be rebuilt, not just the header - a row that
## became affordable must stop being greyed out and its button must enable.
func _on_money_changed(_total: int, _delta: int) -> void:
	if _rows != null and is_instance_valid(_rows):
		_refresh_rows()
	_refresh_money()


func _refresh_money() -> void:
	if _money_label != null:
		_money_label.text = "%d coins" % Game.run.money
	if _reroll_button != null:
		var cost := _reroll_cost()
		_reroll_button.text = "%s (%s)" % [REROLL_LABEL, "free" if cost == 0 else str(cost)]
		_reroll_button.disabled = cost > Game.run.money


func _reroll_cost() -> int:
	if Game.run.rerolls_used < Game.run.free_rerolls:
		return 0
	var paid := Game.run.rerolls_used - Game.run.free_rerolls
	return Balance.SHOP_REROLL_BASE_COST + Balance.SHOP_REROLL_STEP * paid


# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------
func _on_buy(id: String) -> void:
	var cost := _price(id)
	if not Game.run.spend_money(cost):
		Audio.play_ui("ui_deny")
		return
	Game.run.apply_upgrade(id)
	Audio.play("purchase", -3.0)
	Events.toast.emit("%s acquired" % UpgradesDB.get_def(id)["name"], UITheme.GOLD)
	# the row stays, but its price has gone up and money has gone down
	_refresh_rows()
	_refresh_money()


func _on_reroll() -> void:
	var cost := _reroll_cost()
	if cost > 0 and not Game.run.spend_money(cost):
		Audio.play_ui("ui_deny")
		return
	Game.run.rerolls_used += 1
	_rng.seed = _rng.randi()
	_roll_offers()
	_refresh_rows()
	_refresh_money()
	Audio.play("ui_confirm", -8.0)


func _on_continue() -> void:
	Audio.play_ui("ui_confirm")
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void: Game.leave_shop())


func _unhandled_input(event: InputEvent) -> void:
	if _swap_panel != null:
		return
	if event.is_action_pressed("interact"):
		_on_continue()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# ability swapping
# ---------------------------------------------------------------------------
func _open_swap() -> void:
	if _swap_panel != null:
		return
	_swap_panel = preload("res://ui/ability_picker.gd").new()
	add_child(_swap_panel)
	_swap_panel.call("setup", "Swap Abilities",
		"One movement ability and two others. Choose all three.", true)
	_swap_panel.connect("closed", func() -> void:
		if _swap_panel != null:
			_swap_panel.queue_free()
		_swap_panel = null)
