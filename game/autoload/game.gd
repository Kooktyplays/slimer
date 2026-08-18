extends Node
## The game's state machine and the owner of the current run.
##
## This node decides *what* state the game is in and drives the music to match.
## It never instantiates scenes - main.tscn listens to `Events.state_changed`
## and swaps scenes itself. Keeping those apart is what makes the headless sim
## harness possible: it can drive real state transitions with no UI at all.

enum State { BOOT, MAIN_MENU, LOADOUT, META, RUN, DEATH, RESULTS, CREDITS }
enum Phase { NONE, INTERMISSION, WAVE, MINI_BOSS, MAJOR_BOSS, SHOP }

var state: int = State.BOOT
var phase: int = Phase.NONE
var run: RunState = null

var paused: bool = false
var settings_open: bool = false
var last_results: Dictionary = {}
var last_run_was_best: bool = false
var last_essence_gained: int = 0

var rng := RandomNumberGenerator.new()

## Set by the sim harness so a headless run doesn't wait on real-time timers.
var fast_mode: bool = false

var _was_low_health: bool = false


## Clock for the foliage and water shaders. They cannot use the built-in TIME
## because TIME keeps running while the SceneTree is paused, so a paused game
## still had every tree swaying and every pond rippling - which reads as the
## game not being paused at all, whatever the pause flag says.
var _anim_time := 0.0

## Which device the player last actually used. Drives aiming mode, the aim
## reticle, and whether on-screen prompts say "SPACE" or "A".
var input_device: String = InputBinds.DEVICE_KBM
signal input_device_changed(device: String)


## Called from Main._input for every event. Mouse *motion* is ignored on
## purpose: a controller player who nudges their desk should not flip the
## prompts back to keyboard glyphs.
func note_device(event: InputEvent) -> void:
	var device := input_device
	if event is InputEventJoypadButton:
		device = InputBinds.DEVICE_PAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > InputBinds.JOY_DEADZONE:
			device = InputBinds.DEVICE_PAD
	elif event is InputEventKey or event is InputEventMouseButton:
		device = InputBinds.DEVICE_KBM
	if device != input_device:
		input_device = device
		input_device_changed.emit(device)


func using_gamepad() -> bool:
	return input_device == InputBinds.DEVICE_PAD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	if paused:
		return
	_anim_time += delta
	RenderingServer.global_shader_parameter_set("anim_time", _anim_time)


# --------------------------------------------------------------------------
# top-level transitions
# --------------------------------------------------------------------------
func _set_state(next: int) -> void:
	if state == next:
		return
	var previous := state
	state = next
	Events.state_changed.emit(previous, next)
	_refresh_music()


func go_to_main_menu() -> void:
	run = null
	phase = Phase.NONE
	set_paused(false)
	_set_state(State.MAIN_MENU)


func go_to_loadout() -> void:
	_set_state(State.LOADOUT)


func go_to_meta() -> void:
	_set_state(State.META)


func go_to_credits() -> void:
	_set_state(State.CREDITS)


## Begin a fresh run. Everything temporary is discarded here - this single
## line is the whole of "death resets the run".
func start_run(seed_value: int = 0) -> void:
	var s := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000) ^ randi()
	rng.seed = s
	run = RunState.create(s, Save.unlocks, Save.loadout.duplicate())
	run.wave = 0
	_was_low_health = false
	set_paused(false)
	_set_state(State.RUN)
	phase = Phase.NONE
	Events.run_started.emit(s)


func abandon_run() -> void:
	run = null
	phase = Phase.NONE
	go_to_main_menu()


# --------------------------------------------------------------------------
# run flow
# --------------------------------------------------------------------------
func depth() -> int:
	if run == null:
		return 1
	return int(ceil(maxi(run.wave, 1) / float(Balance.WAVES_PER_DEPTH)))


static func is_mini_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % Balance.MINI_BOSS_EVERY == 0 \
		and wave % Balance.MAJOR_BOSS_EVERY != 0


static func is_major_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % Balance.MAJOR_BOSS_EVERY == 0


static func is_boss_wave(wave: int) -> bool:
	return is_mini_boss_wave(wave) or is_major_boss_wave(wave)


## Advance to the next wave and pick the phase it should run in.
func begin_next_wave() -> int:
	if run == null:
		return 0
	run.wave += 1
	if is_major_boss_wave(run.wave):
		_set_phase(Phase.MAJOR_BOSS)
	elif is_mini_boss_wave(run.wave):
		_set_phase(Phase.MINI_BOSS)
	else:
		_set_phase(Phase.WAVE)
	Events.wave_started.emit(run.wave, depth())
	return run.wave


func notify_wave_cleared() -> void:
	if run == null:
		return
	Events.wave_cleared.emit(run.wave)
	# A boss wave is always followed by the shop; ordinary waves get a short
	# breather instead.
	if is_boss_wave(run.wave):
		enter_shop()
	else:
		_set_phase(Phase.INTERMISSION)


func enter_shop() -> void:
	_set_phase(Phase.SHOP)
	Events.shop_opened.emit()


func leave_shop() -> void:
	# Phase first, then notify. Listeners react to shop_closed by queueing the
	# next wave, and that queue refuses to run while the phase still says SHOP
	# - emitting first left the run permanently parked after every shop.
	_set_phase(Phase.INTERMISSION)
	Events.shop_closed.emit()


func _set_phase(next: int) -> void:
	if phase == next:
		return
	phase = next
	_refresh_music()


# --------------------------------------------------------------------------
# death and results
# --------------------------------------------------------------------------
func _on_player_died() -> void:
	if state != State.RUN:
		return
	_set_state(State.DEATH)


## Called by the death screen once its animation is done.
func finish_run() -> void:
	if run == null:
		go_to_main_menu()
		return
	var summary := run.summary()
	var base := Balance.essence_for_run(
		int(summary["wave"]), int(summary["minis"]), int(summary["majors"]))
	last_essence_gained = int(round(base * run.essence_multiplier()))
	last_run_was_best = Save.record_run(summary, last_essence_gained)
	last_results = summary
	Events.run_ended.emit(summary)
	run = null
	phase = Phase.NONE
	_set_state(State.RESULTS)


# --------------------------------------------------------------------------
# pause
# --------------------------------------------------------------------------
func can_pause() -> bool:
	return state == State.RUN


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	get_tree().paused = value
	# GPU particles run on their own clock and ignore the tree's pause flag,
	# so drifting leaves and motes have to be stopped explicitly.
	_set_particles_paused(value)
	Audio.set_ducked(value or _should_duck())
	if value:
		Audio.play_ui("ui_click")


func _set_particles_paused(value: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("ambient_particles"):
		if node is GPUParticles2D:
			(node as GPUParticles2D).speed_scale = 0.0 if value else 1.0


func toggle_pause() -> void:
	if not can_pause() and not paused:
		return
	set_paused(not paused)


# --------------------------------------------------------------------------
# music
# --------------------------------------------------------------------------
## Re-evaluate the low-health cue. Called by the player when its HP changes.
func notify_health_changed() -> void:
	var low := run != null and run.is_low_health()
	if low == _was_low_health:
		return
	_was_low_health = low
	_refresh_music()
	Audio.set_ducked(paused or _should_duck())
	if low:
		Audio.play("low_health", -4.0, 0.0)


func _should_duck() -> bool:
	return false


func _refresh_music() -> void:
	match state:
		State.MAIN_MENU, State.LOADOUT, State.META, State.CREDITS, State.BOOT:
			Audio.play_cue(Audio.Cue.MENU)
		State.DEATH:
			Audio.play_cue(Audio.Cue.DEATH)
		State.RESULTS:
			Audio.play_cue(Audio.Cue.RESULTS)
		State.RUN:
			Audio.play_cue(_run_cue())


func _run_cue() -> int:
	if phase == Phase.SHOP:
		return Audio.Cue.SHOP
	if _was_low_health:
		return Audio.Cue.LOW_HEALTH
	match phase:
		Phase.MAJOR_BOSS:
			return Audio.Cue.MAJOR_BOSS
		Phase.MINI_BOSS:
			return Audio.Cue.MINI_BOSS
		_:
			# Waves get progressively more urgent music within each depth.
			if run != null and run.wave >= 8:
				return Audio.Cue.ESCALATION
			return Audio.Cue.COMBAT


# --------------------------------------------------------------------------
# helpers used across the game
# --------------------------------------------------------------------------
func has_run() -> bool:
	return run != null


func wave() -> int:
	return run.wave if run != null else 0


func shake(strength: float, duration: float = 0.25) -> void:
	var scaled := strength * float(Save.settings["screen_shake"])
	if scaled <= 0.01:
		return
	Events.screen_shake.emit(minf(scaled, Balance.SHAKE_MAX), duration)
