extends Node
## Stress test: fill the arena to the enemy cap, fire continuously, and
## measure frame time.
##
## Run windowed, because the point is to measure real rendering:
##   Godot --path game --resolution 1600x900 -- perf
##
## The budget is 16.6 ms for 60 fps. What matters is the 95th percentile, not
## the mean - an average of 9 ms with regular 40 ms spikes still reads as a
## stuttering game.

const WARMUP := 2.0
const MEASURE := 12.0
const TARGET_MS := 16.6

var _elapsed := 0.0
var _stage := "boot"
var _spawned := false


func _ready() -> void:
	Save.disable_writes = true
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Save.loadout = ["dash", "nova", "orbital"]
	Save.unlocks = ["ab_shield", "ab_orbital"]
	Game.start_run(2468)
	_stage = "warmup"


func _process(delta: float) -> void:
	if _stage == "boot":
		return
	_elapsed += delta

	var run := _run_node()
	if run == null:
		return
	var player: Player = run.player
	if player == null or not is_instance_valid(player):
		return

	if not _spawned and _elapsed > 1.0:
		_fill_arena(run, player)
		_spawned = true

	# keep the player alive and shooting, so the measurement includes bullets,
	# impacts, damage numbers and death effects rather than an idle scene
	Game.run.hp = Game.run.max_hp
	var target := Combat.nearest_enemy(player.global_position)
	if target != null:
		player.aim_override = target.global_position
		player.gun.try_fire((target.global_position - player.global_position).normalized())
	if int(_elapsed * 60) % 90 == 0:
		player.abilities.use(int(_elapsed) % AbilitiesDB.SLOT_COUNT)

	if _stage == "warmup" and _elapsed > WARMUP:
		_stage = "measuring"
		DebugCapture.begin_sampling()
	elif _stage == "measuring" and _elapsed > WARMUP + MEASURE:
		_finish(run)


## Fill to the cap with a realistic late-wave mix, including elites.
func _fill_arena(run: Node, player: Player) -> void:
	Game.run.wave = 30
	var waves: WaveController = run.waves
	waves.stop()
	var types := EnemyTypes.ORDER
	for i in Balance.MAX_CONCURRENT_ENEMIES:
		var angle := TAU * i / float(Balance.MAX_CONCURRENT_ENEMIES)
		var at: Vector2 = player.global_position \
			+ Vector2.RIGHT.rotated(angle) * randf_range(340.0, 900.0)
		var elite: String = "" if i % 4 != 0 else EnemyTypes.ELITE_MODS[i % 3]
		waves.spawn_at(types[i % types.size()], at, 30, elite)
	run.bosses.call("spawn_for_wave", 30, player.global_position)


func _finish(run: Node) -> void:
	set_process(false)
	var stats := DebugCapture.end_sampling()
	var pools := Pools.stats()

	print("\n=== performance ===")
	print("enemies on screen: %d (cap %d)"
		% [Combat.enemy_count(), Balance.MAX_CONCURRENT_ENEMIES])
	print("pooled objects live: %d" % Pools.total_live())
	print("props in the forest: %d" % run.layout.props.size())
	print("frame time: mean %.2f ms | median %.2f ms | p95 %.2f ms | max %.2f ms"
		% [stats.get("mean_ms", 0.0), stats.get("median_ms", 0.0),
			stats.get("p95_ms", 0.0), stats.get("max_ms", 0.0)])
	print("samples: %d" % int(stats.get("samples", 0)))
	print("pools:")
	for key: String in pools:
		var s: Dictionary = pools[key]
		print("  %-22s created %3d, live %3d, free %3d"
			% [key, s["created"], s["live"], s["free"]])

	var p95 := float(stats.get("p95_ms", 999.0))
	if p95 <= TARGET_MS:
		print("RESULT: PASS - p95 %.2f ms is inside the %.1f ms budget\n"
			% [p95, TARGET_MS])
		get_tree().quit(0)
	else:
		print("RESULT: FAIL - p95 %.2f ms exceeds the %.1f ms budget\n"
			% [p95, TARGET_MS])
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
