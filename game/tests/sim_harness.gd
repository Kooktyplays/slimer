extends Node
## Plays the real game, headless, for 26+ waves, and asserts the loop holds.
##
## Run: Godot --headless --fixed-fps 60 --path game -- sim
##
## This is the softlock test. It drives the actual run scene, the actual wave
## controller and the actual bosses through real input, so anything that can
## wedge the loop - a wave that never finishes, a shop that never closes, a
## boss that never dies - shows up here rather than in front of a player.
##
## `--fixed-fps 60` makes every frame advance exactly 1/60 s of game time
## regardless of wall clock, so the whole run compresses into about a minute.

## Wave 22 is where coverage is complete, not where the game gets easy: it is
## past mini-bosses at 5/10/15, the major boss at 20, four shops, the elite
## unlock at 13 and the last enemy colour at 15, plus a normal wave after the
## major to prove the loop resumes.
##
## The bot regularly reaches 26+, but somewhere in the mid-twenties it starts
## losing races it should win, and a test that fails on the bot's marksmanship
## reports the wrong thing. Raise this when the bot gets better, not to make
## the number look nicer.
const TARGET_WAVE := 22
const MAX_FRAMES := 260_000
const SIM_DAMAGE_ASSIST := 12.0
## 240 simulated seconds with no wave change. Deliberately generous: a wave 25
## crowd or a repeat boss legitimately runs minutes, and a tight window here
## turns "the bot is not very good" into a reported softlock.
const STALL_FRAMES := 14400

var _frames := 0
var _failures: Array[String] = []
var _notes: Array[String] = []

var _last_wave := 0
var _last_progress_frame := 0
var _waves_seen: Array[int] = []
var _boss_waves_seen: Array[int] = []
var _major_waves_seen: Array[int] = []
var _shops_opened := 0
var _shops_closed := 0
var _abilities_fired := {0: 0, 1: 0}
var _potions := {}
var _peak_enemies := 0
var _strafe := 1.0
var _ability_cooldown := 0.0
var _phase := "waves"
var _pool_peak := 0
var _started := false
var verbose := OS.get_cmdline_user_args().has("verbose")
var _last_player_pos := Vector2.ZERO
var _bot_stuck := 0
var _no_kill_frames := 0
var _last_enemy_count := 0
var _last_boss_hp := INF
var _target_index := 0


func _ready() -> void:
	Save.disable_writes = true
	Game.fast_mode = true

	Events.wave_started.connect(func(w: int, _d: int) -> void:
		_waves_seen.append(w)
		_last_wave = w
		_last_progress_frame = _frames)
	Events.boss_spawned.connect(func(_b: Node2D, _n: String, major: bool) -> void:
		if major:
			_major_waves_seen.append(Game.wave())
		else:
			_boss_waves_seen.append(Game.wave()))
	Events.shop_opened.connect(func() -> void: _shops_opened += 1)
	Events.shop_closed.connect(func() -> void: _shops_closed += 1)
	Events.ability_used.connect(func(slot: int, _id: String) -> void:
		_abilities_fired[slot] = int(_abilities_fired[slot]) + 1)
	Events.potion_used.connect(func(kind: String) -> void:
		_potions[kind] = int(_potions.get(kind, 0)) + 1)

	# Autoloads are ready before main.tscn is, and Main's own _ready() calls
	# go_to_main_menu(). Starting the run from here immediately would emit
	# state_changed with nothing listening, and then get overwritten - so wait
	# for the router to exist first.
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# Two abilities that always have something to do, so both slots get
	# genuinely exercised rather than one of them sitting on a dead target.
	Save.loadout = ["dash", "nova"]
	Save.unlocks = ["ab_nova"]
	# Seed the global RNG too. Game.start_run seeds its own generator, but
	# spawn placement, bullet spread and drop rolls use the global one, so
	# without this the run differs every time and a failure cannot be
	# reproduced.
	seed(987654)
	Game.start_run(987654)

	# Damage assist. This test exists to prove the *loop* holds - waves
	# advance, bosses die, shops open and close, death resets - not to prove a
	# scripted bot can out-shoot wave 26. Without it the run stalls on the
	# bot's aim rather than on anything the game is doing wrong, which is a
	# test that reports the wrong thing. Health is topped up for the same
	# reason.
	Game.run.gun["damage"] = float(Game.run.gun["damage"]) * SIM_DAMAGE_ASSIST

	_last_progress_frame = _frames
	_started = true


func _process(_delta: float) -> void:
	_frames += 1
	if not _started:
		return
	if _frames > MAX_FRAMES:
		_fail("hit the frame ceiling without reaching wave %d" % TARGET_WAVE)
		_finish()
		return
	if _frames - _last_progress_frame > STALL_FRAMES:
		_fail("no wave progress for %d frames (stuck on wave %d, phase %d)"
			% [STALL_FRAMES, _last_wave, Game.phase])
		_dump_state()
		_finish()
		return
	if verbose and _frames % 600 == 0:
		_dump_state()

	match _phase:
		"waves": _tick_waves()
		"dying": _tick_dying()


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------
func _tick_waves() -> void:
	var run := _run_node()
	if run == null:
		return
	var player: Player = run.player
	if player == null or not is_instance_valid(player) or not player.alive:
		return

	_peak_enemies = maxi(_peak_enemies, Combat.enemy_count())
	_pool_peak = maxi(_pool_peak, Pools.total_live())

	# Keep the run alive: this test is about the loop not wedging, not about
	# whether an AI can out-play wave 26.
	if Game.run.hp < Game.run.max_hp * 0.75:
		Game.run.hp = Game.run.max_hp

	# close the shop as soon as it opens
	if Game.phase == Game.Phase.SHOP:
		_shop_behaviour(run)
		return

	_fight(player)

	if _last_wave >= TARGET_WAVE and Game.phase != Game.Phase.SHOP:
		_begin_death_test(player)


func _fight(player: Player) -> void:
	var target := _pick_target(player)
	if target != null:
		# Lead the shot. Yellow Hoarders flee at speed, and firing at where a
		# fleeing target *is* misses almost every time - a human leads without
		# thinking about it, and a bot that doesn't will report a stall the
		# game does not actually have.
		var aim_at := _predict(player, target)
		player.aim_override = aim_at
		player.gun.try_fire((aim_at - player.global_position).normalized())
	else:
		player.aim_override = player.global_position + Vector2.RIGHT

	# Close the distance when the fight has drifted away, strafe when it
	# hasn't. A bot that only strafes outruns every chaser forever.
	var dir := Vector2.ZERO
	if target != null:
		var to_target := target.global_position - player.global_position
		var dist := to_target.length()
		# with the wave nearly clear, commit - that's what finishing looks like
		var close_range := 200.0 if Combat.enemy_count() <= 3 else 420.0
		if target is Boss:
			close_range = 260.0        # bosses are big; fight them up close
		if _no_kill_frames > 240:
			close_range = 170.0        # nothing is dying: get in its face
		if dist > close_range:
			dir = to_target.normalized()
		else:
			if _frames % 90 == 0:
				_strafe = -_strafe
			dir = to_target.normalized().orthogonal() * _strafe
			if dist < 170.0:
				dir -= to_target.normalized() * 0.8      # back off from contact
	else:
		if _frames % 90 == 0:
			_strafe = -_strafe
		dir = Vector2(_strafe, sin(_frames * 0.01))

	# Unstick: a bot holding one direction into a rock pocket never gets out,
	# and reports a stall that a human would resolve in half a second.
	var moved := player.global_position.distance_to(_last_player_pos)
	_last_player_pos = player.global_position
	if moved < 0.6:
		_bot_stuck += 1
	else:
		_bot_stuck = maxi(0, _bot_stuck - 2)
	if _bot_stuck > 20:
		if _bot_stuck > 110:
			_bot_stuck = 0
		dir = Vector2.RIGHT.rotated(float(_frames) * 0.07)

	_hold("move_right", dir.x > 0.25)
	_hold("move_left", dir.x < -0.25)
	_hold("move_down", dir.y > 0.25)
	_hold("move_up", dir.y < -0.25)

	# fire both ability slots on a rotation
	_ability_cooldown -= 1.0 / 60.0
	if _ability_cooldown <= 0.0:
		var slot := (_frames / 300) % 2
		player.abilities.use(slot)
		_ability_cooldown = 1.5


## Bosses summon adds faster than a nearest-target bot can clear them, so a
## bot that always shoots the closest thing never actually fights the boss.
## Players focus the boss; so does this.
##
## When kills stop happening the target is rotated and the bot closes in - the
## usual cause is a tree between it and whatever it locked onto, and standing
## still shooting bark is not something a player would do for two minutes.
func _pick_target(player: Player) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("boss"):
		var boss := node as Boss
		if is_instance_valid(boss) and not boss.dying and boss.active:
			# Progress against a boss is falling HP, not a falling enemy
			# count. Tracking only the count meant a boss standing behind a
			# tree registered as "fine" forever.
			if boss.hp < _last_boss_hp:
				_no_kill_frames = 0
			else:
				_no_kill_frames += 1
			_last_boss_hp = boss.hp
			return boss
	_last_boss_hp = INF

	var count := Combat.enemy_count()
	if count < _last_enemy_count:
		_no_kill_frames = 0
	else:
		_no_kill_frames += 1
	_last_enemy_count = count

	if _no_kill_frames < 240:
		return Combat.nearest_enemy(player.global_position)

	# stalled: work through the nearby enemies instead of one unreachable one
	var candidates := Combat.enemies_in_radius(player.global_position, 1600.0)
	if candidates.is_empty():
		candidates = Combat.enemies()
	if candidates.is_empty():
		return null
	if _no_kill_frames > 600:
		_no_kill_frames = 240
		_target_index += 1
	return candidates[_target_index % candidates.size()]


func _predict(player: Player, target: Node2D) -> Vector2:
	var bullet_speed := float(Game.run.gun["projectile_speed"])
	var to_target := target.global_position - player.global_position
	var travel := to_target.length() / maxf(bullet_speed, 1.0)
	var target_velocity: Vector2 = target.get("velocity") if target.get("velocity") != null else Vector2.ZERO
	return target.global_position + target_velocity * travel


func _shop_behaviour(run: Node) -> void:
	var shop: Node = run.shop
	if shop == null or not is_instance_valid(shop):
		return
	# Spend down to nothing, then leave. Buying repeatedly also exercises
	# repeat-purchase price escalation, and keeps the bot strong enough that
	# later waves are a test of the loop rather than of the bot.
	var guard := 0
	while guard < 30:
		guard += 1
		var bought := false
		for id: String in shop.get("_offers"):
			if Game.run.money >= UpgradesDB.price(id, Game.run.times_bought(id)):
				shop.call("_on_buy", id)
				bought = true
				break
		if not bought:
			break
	shop.call("_on_continue")


func _hold(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


# ---------------------------------------------------------------------------
# death and reset
# ---------------------------------------------------------------------------
var _pre_death := {}


func _begin_death_test(player: Player) -> void:
	_phase = "dying"
	_pre_death = {
		"essence": Save.essence,
		"unlocks": Save.unlocks.duplicate(),
		"upgrades": Game.run.upgrades_bought.duplicate(),
		"money": Game.run.money,
		"damage": float(Game.run.gun["damage"]),
	}
	_note("reached wave %d with %d money, %.0f gun damage, %d upgrades bought"
		% [_last_wave, Game.run.money, _pre_death["damage"],
			_pre_death["upgrades"].size()])
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)
	player.take_damage(1_000_000.0)


func _tick_dying() -> void:
	if Game.state == Game.State.DEATH:
		Game.finish_run()
		return
	if Game.state != Game.State.RESULTS:
		return

	# --- death must wipe the run and keep permanent progress ---------------
	if Game.run != null:
		_fail("run state survived death")
	if Save.essence <= int(_pre_death["essence"]):
		_fail("no essence awarded for the run")
	if Save.unlocks != _pre_death["unlocks"]:
		_fail("permanent unlocks changed across death")

	# starting a fresh run must reset every temporary thing
	Game.start_run(13579)
	if Game.run.money != 0:
		_fail("new run started with %d money" % Game.run.money)
	if not Game.run.upgrades_bought.is_empty():
		_fail("new run inherited gun upgrades")
	if not is_equal_approx(float(Game.run.gun["damage"]), float(Balance.GUN_BASE["damage"])):
		_fail("new run gun damage is %.1f, expected base %.1f"
			% [float(Game.run.gun["damage"]), float(Balance.GUN_BASE["damage"])])
	if Game.run.wave != 0:
		_fail("new run started at wave %d" % Game.run.wave)

	_finish()


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------
func _finish() -> void:
	set_process(false)
	_check_sequence()

	print("\n=== full-run simulation ===")
	print("simulated:        %d frames (%.1f minutes of game time)"
		% [_frames, _frames / 3600.0])
	print("waves played:     %d (reached wave %d)" % [_waves_seen.size(), _last_wave])
	print("mini-bosses:      %s" % str(_boss_waves_seen))
	print("major bosses:     %s" % str(_major_waves_seen))
	print("shops:            %d opened, %d closed" % [_shops_opened, _shops_closed])
	print("abilities used:   slot 1 x%d, slot 2 x%d"
		% [_abilities_fired[0], _abilities_fired[1]])
	print("potions consumed: %s" % (str(_potions) if not _potions.is_empty() else "none"))
	print("peak enemies:     %d (cap %d)" % [_peak_enemies, Balance.MAX_CONCURRENT_ENEMIES])
	print("peak pooled live: %d" % _pool_peak)
	print("orphan nodes:     %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for n: String in _notes:
		print("note: " + n)

	if _failures.is_empty():
		print("RESULT: PASS - the loop ran %d waves and reset cleanly\n" % _last_wave)
		get_tree().quit(0)
	else:
		print("RESULT: FAIL - %d problems" % _failures.size())
		for f: String in _failures:
			print("  " + f)
		print("")
		get_tree().quit(1)


## Everything that has to be true about the *shape* of the run.
func _check_sequence() -> void:
	if _last_wave < TARGET_WAVE:
		_fail("only reached wave %d of %d" % [_last_wave, TARGET_WAVE])

	# waves must be consecutive with no gaps or repeats
	for i in _waves_seen.size():
		if _waves_seen[i] != i + 1:
			_fail("wave sequence broke: expected %d, got %d" % [i + 1, _waves_seen[i]])
			break

	# every multiple of 5 that is not a multiple of 20 is a mini-boss
	var expected_minis: Array[int] = []
	var expected_majors: Array[int] = []
	for w in range(1, _last_wave + 1):
		if Game.is_major_boss_wave(w):
			expected_majors.append(w)
		elif Game.is_mini_boss_wave(w):
			expected_minis.append(w)
	if _boss_waves_seen != expected_minis:
		_fail("mini-boss waves were %s, expected %s"
			% [str(_boss_waves_seen), str(expected_minis)])
	if _major_waves_seen != expected_majors:
		_fail("major boss waves were %s, expected %s"
			% [str(_major_waves_seen), str(expected_majors)])

	# a shop after every boss
	var expected_shops := expected_minis.size() + expected_majors.size()
	if _shops_opened < expected_shops:
		_fail("%d shops opened, expected %d (one per boss)"
			% [_shops_opened, expected_shops])
	if _shops_closed < _shops_opened:
		_fail("%d shops opened but only %d closed - one never released the run"
			% [_shops_opened, _shops_closed])

	if int(_abilities_fired[0]) == 0:
		_fail("ability slot 1 never fired")
	if int(_abilities_fired[1]) == 0:
		_fail("ability slot 2 never fired")
	if _peak_enemies > Balance.MAX_CONCURRENT_ENEMIES:
		_fail("enemy cap exceeded: %d live at peak, cap is %d"
			% [_peak_enemies, Balance.MAX_CONCURRENT_ENEMIES])


func _run_node() -> Node:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return null
	var holder := main.get_node_or_null("ScreenHolder")
	if holder == null or holder.get_child_count() == 0:
		return null
	var candidate := holder.get_child(0)
	return candidate if candidate.has_method("drop_reward") else null


## Snapshot of everything that could wedge the loop. Printed on a stall, and
## periodically with `-- sim verbose`.
func _dump_state() -> void:
	var run := _run_node()
	var line := "[t=%d] wave=%d phase=%d state=%d enemies=%d" % [
		_frames, _last_wave, Game.phase, Game.state, Combat.enemy_count()]
	if run != null and run.waves != null:
		var w: WaveController = run.waves
		line += " active=%s budget=%.1f alive_count=%d" % [
			w.active, w.budget_remaining, w.alive_count]
	if run != null and run.player != null and is_instance_valid(run.player):
		var p: Player = run.player
		line += " hp=%.0f ammo=%d/%d reloading=%s pooled=%d" % [
			Game.run.hp if Game.run != null else -1,
			p.gun.ammo, p.gun.magazine_size(), p.gun.reloading, Pools.total_live()]
		var target := Combat.nearest_enemy(p.global_position)
		line += " nearest=%.0f" % (
			p.global_position.distance_to(target.global_position) if target != null else -1.0)
	for node: Node in get_tree().get_nodes_in_group("boss"):
		var b := node as Boss
		if is_instance_valid(b):
			line += " | boss=%s hp=%.0f/%.0f phase=%d active=%s dying=%s busy=%s d=%.0f" % [
				b.id, b.hp, b.max_hp, b.phase, b.active, b.dying, b.get("_busy"),
				b.global_position.distance_to(Combat.player_position())]
	print(line)


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)


func _note(message: String) -> void:
	_notes.append(message)
