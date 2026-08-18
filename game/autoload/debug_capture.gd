extends Node
## Screenshot and diagnostics hooks used for verification.
##
## The point of this autoload is that the game can be checked without a human
## looking at it: a scripted pass drives the real game and calls `shot()` at
## chosen beats, and the resulting PNGs get inspected afterwards. F9 also takes
## a manual shot while playing.

const SHOT_DIR := "user://shots"

var enabled: bool = true
var _counter: int = 0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _sampling: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# `--  visual` (user args after a bare --) drives a scripted pass through
	# every game state, capturing a screenshot at each one. This is how the
	# game gets looked at without a human having to sit and play it.
	if OS.get_cmdline_user_args().has("visual"):
		_attach("res://tests/visual_pass.gd", "VisualPass")
	# `-- sim` plays the whole loop headless and asserts it holds together.
	if OS.get_cmdline_user_args().has("sim"):
		_attach("res://tests/sim_harness.gd", "SimHarness")
	# `-- tests` runs the logic suite with the autoloads live.
	if OS.get_cmdline_user_args().has("tests"):
		_attach("res://tests/run_tests.gd", "LogicTests")
	# `-- perf` stress-tests a full-size wave and reports frame timing.
	if OS.get_cmdline_user_args().has("perf"):
		_attach("res://tests/perf_test.gd", "PerfTest")


func _attach(script_path: String, node_name: String) -> void:
	var script: GDScript = load(script_path)
	var runner: Node = script.new()
	runner.name = node_name
	add_child(runner)


func _process(delta: float) -> void:
	if _sampling:
		_frame_times.append(delta * 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F9:
			shot("manual")


## Save the current viewport to user://shots/NN_name.png.
## Must be called after a frame has been drawn - await RenderingServer's
## frame_post_draw first if you're calling this right after a state change.
func shot(shot_name: String) -> String:
	if not enabled:
		return ""
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var image := viewport.get_texture().get_image()
	if image == null:
		return ""
	_counter += 1
	var path := "%s/%02d_%s.png" % [SHOT_DIR, _counter, shot_name]
	image.save_png(path)
	print("[shot] %s -> %s" % [shot_name, ProjectSettings.globalize_path(path)])
	return path


## Same as shot(), but waits for the next drawn frame first.
func shot_next_frame(shot_name: String) -> String:
	if not enabled:
		return ""
	await RenderingServer.frame_post_draw
	return shot(shot_name)


# --------------------------------------------------------------------------
# frame time sampling, for the performance check
# --------------------------------------------------------------------------
func begin_sampling() -> void:
	_frame_times = PackedFloat32Array()
	_sampling = true


func end_sampling() -> Dictionary:
	_sampling = false
	if _frame_times.is_empty():
		return {"samples": 0}
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for v: float in sorted:
		total += v
	return {
		"samples": n,
		"mean_ms": total / n,
		"median_ms": sorted[n / 2],
		"p95_ms": sorted[mini(n - 1, int(n * 0.95))],
		"max_ms": sorted[n - 1],
	}
