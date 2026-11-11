extends Node
## Stages a short demo of one ability or ultimate in the real game, for the
## preview clips shown on the loadout, shop and character screens.
##
##   Godot --path . -- reel nova            # an ability
##   Godot --path . -- reel ult:vampire     # a class's ultimate, cutscene and all
##
## Recorded by tools/record_previews.py through Movie Maker; run without
## --write-movie it is just a scripted scene, handy for looking at one.
##
## It drives the same nodes the player does - the ability controller, the gun,
## the wave controller's spawner - so a clip cannot show an ability doing
## something the game does not.

const SEED := 777
const LEAD := 0.6             ## seconds of approach before the ability fires
const ABILITY_TAIL := 2.6
const ULT_TAIL := 2.6         ## after the cutscene

## Per-ability staging: where to aim, whether to keep shooting, and anything
## the scene needs first so the effect has something to show.
const STAGING := {
	"heal": {"hurt": 0.35},
	"shield": {"close": true, "hurts": true},
	"rapidfire": {"shoot": true},
	"lifesteal": {"shoot": true, "hurt": 0.45},
	"timeslow": {"shoot": true},
	"decoy": {"aim_far": true},
	# a speed buff is invisible on a player standing still
	"surge": {"walk": true},
}

var _id := ""
var _player: Node2D = null
var _keep_alive := true
var _shoot := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Save.disable_writes = true
	Save.settings["show_hints"] = false
	Save.settings["damage_numbers"] = true
	var args := OS.get_cmdline_user_args()
	var at := args.find("reel")
	_id = String(args[at + 1]) if at >= 0 and at + 1 < args.size() else "nova"
	call_deferred("_run")


func _process(_delta: float) -> void:
	if _keep_alive and Game.run != null and is_instance_valid(_player):
		Game.run.hp = maxf(Game.run.hp, Game.run.max_hp * 0.3)
	if _shoot and is_instance_valid(_player) and not get_tree().paused:
		_player.gun.try_fire(_player.aim_direction)


func _run() -> void:
	var ult := _id.begins_with("ult:")
	var cls := _id.substr(4) if ult else ClassesDB.DEFAULT
	Game.start_run(SEED, false, cls, WeaponsDB.DEFAULT)
	await _settle(1.0)
	var run := _run_node()
	if run == null:
		push_error("[reel] no run scene")
		get_tree().quit(1)
		return
	var waves: WaveController = run.waves
	waves.stop()
	waves.clear_all_enemies()
	# no first wave arriving mid-clip, and no banner announcing it
	run.set("_pending_wave", false)
	run.set("_intermission", 1.0e6)
	_player = run.player
	# an ability clip should not be interrupted by an ultimate charging
	if not ult:
		Game.run.ultimate_rate = 0.0

	var stage: Dictionary = STAGING.get(_id, {})
	if not ult:
		_equip(_id)
	_spawn_crowd(run, waves, bool(stage.get("close", false)) or _id == "ult:warrior")
	# Contact damage off unless being hit is the point (Bulwark absorbing it,
	# Last Stand throwing it back) - a red hurt-flash would be the loudest
	# thing in every other clip.
	if not (bool(stage.get("hurts", false)) or _id == "ult:warrior"):
		for e: Node2D in Combat.enemies():
			e.set("contact_damage", 0.0)
	await _settle(0.15)

	print("[reel] begin_frame=%d" % Engine.get_frames_drawn())
	_aim_at(_crowd_centre(bool(stage.get("aim_far", false))))
	await _settle(LEAD)

	if stage.has("hurt"):
		Game.run.hp = Game.run.max_hp * float(stage["hurt"])
	_shoot = bool(stage.get("shoot", false)) or _id == "ult:vampire"
	if ult:
		Game.run.ultimate_charge = 1.0
		_player.abilities.use_ultimate()
		# wait out the cutscene, then the ultimate itself
		await _settle(0.1)
		while get_tree().paused:
			await get_tree().process_frame
		await _settle(ULT_TAIL)
	else:
		var slot := 0 if _is_movement(_id) else 1
		_player.abilities.use(slot)
		if _id == "dash":
			await _settle(0.45)
			_player.abilities.use(slot)        # two charges: show both
		if bool(stage.get("walk", false)):
			await _walk(["move_down", "move_right", "move_up", "move_left"], 0.55)
			await _settle(ABILITY_TAIL - 2.2)
		else:
			await _settle(ABILITY_TAIL)
	print("[reel] end_frame=%d" % Engine.get_frames_drawn())
	get_tree().quit(0)


## Hold the real movement actions in turn, as a player would.
func _walk(actions: Array, each: float) -> void:
	for action: String in actions:
		Input.action_press(action)
		await _settle(each)
		Input.action_release(action)


func _equip(id: String) -> void:
	if _is_movement(id):
		_player.abilities.equip(0, id)
	else:
		_player.abilities.equip(0, "dash")
		_player.abilities.equip(1, id)


func _is_movement(id: String) -> bool:
	return String(AbilitiesDB.get_def(id).get("class", "")) == AbilitiesDB.CLASS_MOVEMENT


## A loose crowd ahead of the player, on open ground only.
func _spawn_crowd(run: Node, waves: WaveController, close: bool) -> void:
	var origin: Vector2 = _player.global_position
	# nothing that shoots or explodes - the clip is about the ability
	var types := [EnemyTypes.GREEN, EnemyTypes.GREEN, EnemyTypes.RED,
		EnemyTypes.BLUE, EnemyTypes.GREEN, EnemyTypes.RED]
	var n := 0
	for ring in 2:
		for k in 6:
			var a := deg_to_rad(-60.0 + 24.0 * k + 12.0 * ring)
			var r := (170.0 if close else 260.0) + 110.0 * ring
			var at := origin + Vector2.RIGHT.rotated(a) * r
			if run.layout != null and not run.layout.is_open(at):
				continue
			waves.spawn_at(types[n % types.size()], at, 6)
			n += 1


func _crowd_centre(far: bool) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for e: Node2D in Combat.enemies():
		total += e.global_position
		count += 1
	var c: Vector2 = total / count if count > 0 \
		else _player.global_position + Vector2(300, 0)
	if far:
		c = _player.global_position + (c - _player.global_position) * 1.35
	return c


## Point the real mouse at a world position, so everything that reads the
## cursor (grenades, cinders, the gun) aims exactly as a player would.
func _aim_at(world: Vector2) -> void:
	var screen := get_viewport().get_canvas_transform() * world
	get_viewport().warp_mouse(screen)


func _run_node() -> Node:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return null
	var holder := main.get_node_or_null("ScreenHolder")
	if holder == null or holder.get_child_count() == 0:
		return null
	var candidate := holder.get_child(0)
	return candidate if candidate.has_method("drop_reward") else null


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
