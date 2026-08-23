extends Node
## Scripted walk through every game state, capturing a screenshot at each.
##
## Run: Godot --path game --resolution 1600x900 -- visual
##
## This is the verification step for anything you can only judge by looking:
## whether the HUD overlaps itself, whether enemy colours read against the
## forest, whether a boss is framed sensibly. It drives the real game - the
## same scenes, the same state machine - rather than a mock.

const SEED := 424242

var _failures: Array[String] = []
var _keep_alive := true


func _process(_delta: float) -> void:
	if _keep_alive and Game.run != null:
		Game.run.hp = Game.run.max_hp


func _ready() -> void:
	# never let a verification run touch the player's real save
	Save.disable_writes = true
	call_deferred("_run")


func _run() -> void:
	await _settle(1.0)

	# --- 1. main menu -------------------------------------------------------
	await _shot("main_menu")

	# --- 2. loadout ---------------------------------------------------------
	Game.go_to_loadout()
	await _settle(0.5)
	await _shot("loadout")

	# --- 3. meta / permanent upgrades --------------------------------------
	Save.essence = 900
	Game.go_to_meta()
	await _settle(0.5)
	await _shot("meta_upgrades")

	# --- 3b. credits (CC BY-NC-SA attribution must be legible here) ---------
	Game.go_to_credits()
	await _settle(0.6)
	_expect(Game.state == Game.State.CREDITS, "credits screen did not open")
	await _shot("credits")

	# --- 4. the forest ------------------------------------------------------
	Game.start_run(SEED)
	await _settle(1.6)
	await _shot("forest_spawn")

	var run := _run_node()
	if run == null:
		print("[visual] run scene missing, aborting")
		get_tree().quit(1)
		return

	# --- 5. an ordinary wave, with every colour on screen at once ----------
	# Forced rather than waited for, so the shot is guaranteed to contain one
	# of each and the colour language can actually be checked.
	Game.run.wave = 16
	var waves: WaveController = run.waves
	var player: Node2D = run.player
	var i := 0
	for id: String in EnemyTypes.ORDER:
		for n in 3:
			var a := TAU * (i / 18.0)
			var at: Vector2 = player.global_position + Vector2.RIGHT.rotated(a) \
				* randf_range(230.0, 470.0)
			waves.spawn_at(id, at, 16, "shielded" if n == 2 else "")
			i += 1
	await _settle(1.4)
	await _shot("wave_all_colours")

	# --- 6. combat: shoot for a bit ----------------------------------------
	for frame in 40:
		player.gun.try_fire(Vector2.RIGHT.rotated(sin(frame * 0.3) * 0.9))
		await get_tree().process_frame
	await _shot("combat")

	# --- 7. abilities -------------------------------------------------------
	# Slot 0 is the movement slot, so it takes a movement ability - equipping a
	# general one here would put Nova on the dash key.
	player.abilities.equip(0, "vault")
	player.abilities.equip(1, "nova")
	player.abilities.equip(2, "orbital")
	player.abilities.use(0)
	player.abilities.use(1)
	await _settle(0.35)
	await _shot("ability_nova")

	# --- 7b. pause, then settings on top of it -----------------------------
	# These check that the world actually STOPS, not that a flag flipped.
	# An earlier version asserted get_tree().paused and passed happily while
	# every enemy kept walking, because Main was PROCESS_MODE_ALWAYS and the
	# whole run scene inherited it. Sampling positions is the assertion that
	# catches that.
	_press("pause")
	await _settle(0.4)
	_expect(get_tree().paused, "pressing pause did not pause the tree")

	var enemy_before := _sample_enemy()
	var player_before: Vector2 = player.global_position
	await _settle(0.7)
	_expect(_sample_enemy().is_equal_approx(enemy_before),
		"enemies kept moving while paused")
	_expect(player.global_position.is_equal_approx(player_before),
		"the player kept moving while paused")
	await _shot("pause_menu")

	var main := get_tree().root.get_node_or_null("Main")
	main.call("open_settings")
	await _settle(0.5)
	_expect(get_tree().paused, "opening settings unpaused the game")
	enemy_before = _sample_enemy()
	await _settle(0.6)
	_expect(_sample_enemy().is_equal_approx(enemy_before),
		"enemies kept moving while the settings menu was open")
	await _shot("settings")

	_press("pause")                       # closes settings, stays paused
	await _settle(0.3)
	_expect(get_tree().paused, "closing settings unpaused the game")
	_press("pause")                       # closes the pause menu
	await _settle(0.4)
	_expect(not get_tree().paused, "the game stayed paused after resuming")
	# ...and the world has to start again afterwards
	enemy_before = _sample_enemy()
	await _settle(0.6)
	_expect(not _sample_enemy().is_equal_approx(enemy_before),
		"enemies stayed frozen after resuming")

	# --- 7b2. the arena is physically closed --------------------------------
	# The grid has always claimed the border is solid; the player moves by
	# physics, not by the grid, and that is the gap play-testers escaped
	# through. This asserts the real collision geometry, then actually drives
	# the player into it.
	# One ray per side proves nothing: it would hit a border tree and pass. The
	# tree band is a scatter with gaps everywhere, so the only honest question is
	# whether ANY line out of the arena is unobstructed. Sweep the whole
	# perimeter and count the ones that escape.
	var space := player.get_world_2d().direct_space_state
	var wsize := ForestGenerator.WORLD_SIZE
	var inset := ForestGenerator.WALL_INSET
	var escapes := 0
	var first_escape := Vector2.ZERO
	var probe_step := 40.0

	var py := inset + 30.0
	while py <= wsize.y - inset - 30.0:
		for pair: Array in [
			[Vector2(inset + 30.0, py), Vector2(-800.0, py)],
			[Vector2(wsize.x - inset - 30.0, py), Vector2(wsize.x + 800.0, py)],
		]:
			var q := PhysicsRayQueryParameters2D.create(pair[0], pair[1])
			q.collision_mask = Layers.WORLD
			q.collide_with_areas = false
			if space.intersect_ray(q).is_empty():
				if escapes == 0:
					first_escape = pair[0]
				escapes += 1
		py += probe_step

	var px := inset + 30.0
	while px <= wsize.x - inset - 30.0:
		for pair: Array in [
			[Vector2(px, inset + 30.0), Vector2(px, -800.0)],
			[Vector2(px, wsize.y - inset - 30.0), Vector2(px, wsize.y + 800.0)],
		]:
			var q := PhysicsRayQueryParameters2D.create(pair[0], pair[1])
			q.collision_mask = Layers.WORLD
			q.collide_with_areas = false
			if space.intersect_ray(q).is_empty():
				if escapes == 0:
					first_escape = pair[0]
				escapes += 1
		px += probe_step

	_expect(escapes == 0,
		"%d unobstructed lines out of the arena, first at %s" % [escapes, first_escape])

	# and walking hard into a corner has to leave the player inside it
	player.global_position = Vector2(
		ForestGenerator.WALL_INSET + 90.0, ForestGenerator.WALL_INSET + 90.0)
	await _settle(0.2)
	for _push in 30:
		player.velocity = Vector2(-4000.0, -4000.0)
		player.move_and_slide()
		await get_tree().physics_frame
	_expect(player.global_position.x >= ForestGenerator.WALL_INSET - 1.0
			and player.global_position.y >= ForestGenerator.WALL_INSET - 1.0,
		"the player was pushed out of the arena to %s" % player.global_position)
	player.velocity = Vector2.ZERO
	player.global_position = run.layout.nearest_open(run.layout.spawn_point)
	await _settle(0.3)

	# --- 7b3. shots land on the slime, not on its shadow --------------------
	# Every actor's physics origin is at its feet, which is exactly where the
	# shadow is drawn; the sprite sits 32px above it. Aiming at the slime you can
	# see used to miss it entirely, which play-testers reported as bullets
	# passing through enemies.
	waves.clear_all_enemies()
	await _settle(0.3)
	var mark := waves.spawn_at(EnemyTypes.GREEN,
		player.global_position + Vector2(300, 0), 1)
	_expect(mark != null, "could not spawn a slime for the hitbox check")
	if mark != null:
		await _settle(0.2)
		var hit_space := player.get_world_2d().direct_space_state
		var probe := PhysicsShapeQueryParameters2D.new()
		var probe_shape := CircleShape2D.new()
		probe_shape.radius = 7.0            # a bullet
		probe.shape = probe_shape
		probe.collision_mask = Layers.ENEMY
		probe.collide_with_areas = true
		probe.collide_with_bodies = true

		# The upper body of the drawn slime. Its *centre* sits only marginally
		# outside the old feet circle, so probing there proves nothing; the dead
		# zone was the top of the sprite, which is most of what you aim at when a
		# slime is coming towards you.
		#
		# Scale comes from the type definition, not from Visual.scale - the
		# squash-and-stretch animation drives that live, and reading it made this
		# probe land in a different place every run.
		var body_sprite := mark.get_node("Visual/Body") as Sprite2D
		var base_scale: float = float(EnemyTypes.get_def(EnemyTypes.GREEN)["scale"])
		var drawn_h: float = body_sprite.texture.get_height() * base_scale
		var upper := mark.hit_center() - Vector2(0, drawn_h * 0.42)
		probe.transform = Transform2D(0.0, upper)
		_expect(not hit_space.intersect_shape(probe, 4).is_empty(),
			"a shot at the top of the slime's sprite hits nothing (probe %s, feet %s)"
				% [upper, mark.global_position])

		# and the feet, so players who learned to aim low are not punished
		probe.transform = Transform2D(0.0, mark.global_position)
		_expect(not hit_space.intersect_shape(probe, 4).is_empty(),
			"a shot at the slime's feet hits nothing")

		# a Brute and a Darter must not share one hitbox: the shape lives in the
		# .tscn and used to be edited in place, so the last spawn resized them all
		var brute := waves.spawn_at(EnemyTypes.RED,
			player.global_position + Vector2(-300, 0), 1)
		await _settle(0.2)
		if brute != null:
			_expect(not is_equal_approx(brute.hit_radius, mark.hit_radius),
				"Brute and Slime report the same hit radius (%.1f)" % mark.hit_radius)
			probe_shape.radius = 2.0
			# a point just outside the small slime but inside the big brute
			probe.transform = Transform2D(0.0,
				brute.hit_center() + Vector2(mark.hit_radius + 6.0, 0))
			_expect(not hit_space.intersect_shape(probe, 4).is_empty(),
				"the Brute's hitbox is no bigger than the Slime's")
	waves.clear_all_enemies()
	await _settle(0.3)

	# --- 7c. clearing a wave vacuums the coins in ---------------------------
	var coin_scene: PackedScene = preload("res://actors/pickup.tscn")
	var far: Array[Pickup] = []
	for c in 6:
		var coin := Pools.acquire(coin_scene, run.forest.sorted_layer) as Pickup
		coin.configure(Pickup.COIN,
			player.global_position + Vector2.RIGHT.rotated(TAU * c / 6.0) * 700.0, 5)
		far.append(coin)
	await _settle(0.6)
	var distance_before := 0.0
	for coin: Pickup in far:
		distance_before += coin.global_position.distance_to(player.global_position)
	_expect(distance_before > 3000.0, "test coins were not placed far away")

	Events.wave_cleared.emit(Game.wave())
	await _settle(0.5)
	var distance_after := 0.0
	for coin: Pickup in far:
		if is_instance_valid(coin) and not coin.collected:
			distance_after += coin.global_position.distance_to(player.global_position)
	_expect(distance_after < distance_before * 0.6,
		"coins did not fly in when the wave cleared (%.0f -> %.0f)"
			% [distance_before, distance_after])
	await _settle(1.2)
	var still_out := 0
	for coin: Pickup in far:
		if is_instance_valid(coin) and not coin.collected:
			still_out += 1
	_expect(still_out == 0, "%d coins never reached the player" % still_out)

	# and the pickup-range upgrade must be gone from the shop pool
	_expect(not UpgradesDB.available_ids(Save.unlocks).has("pickup_range"),
		"the pickup range upgrade is still offered in the shop")

	# --- 7d. a Spitter fires at its configured rate, not six times faster ---
	waves.clear_all_enemies()
	await _settle(0.4)
	var spitter := waves.spawn_at(EnemyTypes.PURPLE,
		player.global_position + Vector2(330, 0), 10)
	_expect(spitter != null, "could not spawn a spitter for the fire-rate check")
	if spitter != null:
		var fired: Array[int] = [0]
		var tally := func(e: Node2D) -> void:
			if e == spitter:
				fired[0] += 1
		Events.enemy_shot_fired.connect(tally)
		await _settle(6.0)
		Events.enemy_shot_fired.disconnect(tally)

		var cooldown: float = float(
			EnemyTypes.get_def(EnemyTypes.PURPLE)["attack_cooldown"])
		var expected := 6.0 / (cooldown / Balance.speed_scale(10))
		# The bug drained the cooldown once per physics frame instead of once
		# per second, so this fired about six times too often. Allow generous
		# slack for the random start offset; anything near 6x is the bug back.
		_expect(fired[0] <= expected * 2.0 + 1,
			"spitter fired %d shots in 6s, expected about %.0f"
				% [fired[0], expected])
		_expect(fired[0] >= 1, "spitter never fired at all")

	# --- 7e. purple potion is not wasted at full charges --------------------
	waves.clear_all_enemies()
	player.abilities.equip(0, "dash")
	player.abilities.equip(1, "grenade")
	player.abilities.equip(2, "nova")
	await _settle(0.3)
	var potion_scene: PackedScene = preload("res://actors/pickup.tscn")
	var potion := Pools.acquire(potion_scene, run.forest.sorted_layer) as Pickup
	potion.configure(Pickup.ABILITY, player.global_position + Vector2(30, 0))
	await _settle(0.9)
	_expect(not potion.collected,
		"an ability potion was consumed while every ability was full")

	# Pin the potion inside the pickup radius before the real assertion below.
	# configure() scatters a drop with an unseeded randf(), so it comes to rest a
	# different distance away every run - measured at 36.4 px against a
	# PICKUP_RADIUS of 34, i.e. either side of the threshold depending on the
	# roll and the frame timing. That made the collection check a coin flip that
	# failed for reasons having nothing to do with what it is testing. The
	# scatter is incidental here; the charge state is the subject.
	potion.global_position = player.global_position + Vector2(20, 0)

	# grenade, not dash: dashing moves the player 320px away and the potion
	# can never catch up, which looks like the potion being broken
	player.abilities.use(1)

	await _settle(1.0)
	_expect(potion.collected, "the ability potion was not collected once needed")
	_expect(player.abilities.charges_missing() == 0,
		"the ability potion did not refill every charge")

	# --- 7f. rebinding round-trips through the save ------------------------
	var original_binds := Save.keybinds.duplicate(true)
	Save.set_keybind("reload", [{"type": "key", "physical": 84}])   # T
	_expect(InputMap.action_has_event("reload", InputBinds.deserialize(
		{"type": "key", "physical": 84})),
		"rebinding did not reach the InputMap")
	var snapshot := Save.to_dict().duplicate(true)
	Save.from_dict(snapshot)
	_expect(Save.keybinds.has("reload"), "keybinds did not survive a save round trip")
	Save.keybinds = original_binds
	InputBinds.apply(Save.keybinds)
	_expect(InputBinds.label_for_action(Save.keybinds, "reload",
		InputBinds.DEVICE_KBM) == "R", "resetting keybinds did not restore R")

	# --- 8. mini-boss -------------------------------------------------------
	waves.clear_all_enemies()
	run.bosses.call("spawn_for_wave", 5, player.global_position)
	await _settle(2.2)
	await _shot("mini_boss")

	# --- 9. major boss ------------------------------------------------------
	if run.bosses.current != null:
		run.bosses.current.queue_free()
	await _settle(0.3)
	Game.run.wave = 20
	run.bosses.call("spawn_for_wave", 20, player.global_position)
	await _settle(2.4)
	await _shot("major_boss")

	# --- 10. shop -----------------------------------------------------------
	Game.run.money = 1400
	if run.bosses.current != null:
		run.bosses.current.queue_free()
	await _settle(0.3)
	run.call("_open_shop")
	await _settle(0.8)
	await _shot("shop")

	Game.leave_shop()
	await _settle(0.4)

	# --- 11. low health -----------------------------------------------------
	_keep_alive = false
	Game.run.hp = Game.run.max_hp * 0.18
	Game.notify_health_changed()
	waves.spawn_at(EnemyTypes.RED, player.global_position + Vector2(300, 0), 16)
	await _settle(1.0)
	await _shot("low_health")

	# --- 12. death ----------------------------------------------------------
	_keep_alive = false
	player.take_damage(9999.0)
	await _settle(2.4)
	await _shot("death")

	# --- 13. results --------------------------------------------------------
	Game.finish_run()
	await _settle(1.6)
	await _shot("results")

	if _failures.is_empty():
		print("[visual] pass complete - all behaviour checks passed")
		get_tree().quit(0)
	else:
		print("[visual] pass complete with %d FAILURES:" % _failures.size())
		for f: String in _failures:
			print("  " + f)
		get_tree().quit(1)


func _run_node() -> Node:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return null
	var holder := main.get_node_or_null("ScreenHolder")
	if holder == null or holder.get_child_count() == 0:
		return null
	var candidate := holder.get_child(0)
	return candidate if candidate.has_method("drop_reward") else null


## Feed a real action press through the input system, so the pass exercises
## the same path a keyboard does rather than calling handlers directly.
##
## parse_input_event, not action_press: action_press only sets the state that
## Input.is_action_pressed() polls, and never delivers an event to _input or
## _unhandled_input. Pause is event-driven, so it would never see it.
## Sends a real InputEventKey, not an InputEventAction. An action event is
## matched by name and skips the input map entirely, so it can pass while the
## actual key binding is broken - which is exactly the bug this is meant to
## catch.
func _press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _press(action: String) -> void:
	if action == "pause":
		_press_key(KEY_ESCAPE)
		return
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## Summed enemy positions - one number that changes if anything is moving.
func _sample_enemy() -> Vector2:
	var total := Vector2.ZERO
	for e: Node2D in Combat.enemies():
		total += e.global_position
	return total


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	print("[visual] FAIL: %s" % message)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	print("[visual] -> %s" % shot_name)
	await RenderingServer.frame_post_draw
	DebugCapture.shot(shot_name)
	await get_tree().process_frame
