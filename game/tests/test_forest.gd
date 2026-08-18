extends SceneTree
## Headless validation of the forest generator across many seeds.
##
## Run: Godot --headless --path game --script res://tests/test_forest.gd
##
## The generator promises the player can never be trapped, stranded, or
## dropped into a space too small to fight in. Those promises are cheap to
## break with a tuning tweak and impossible to confirm by eye, so they get
## checked here over a wide seed sweep.

const SEEDS := 200


func _initialize() -> void:
	var failures: Array[String] = []
	var t0 := Time.get_ticks_msec()

	var total_props := 0
	var total_zones := 0
	var total_attempts := 0
	var worst_clearing := 1 << 30
	var slowest := 0

	for i in SEEDS:
		var seed_v := 100_000 + i * 977
		var gen_start := Time.get_ticks_msec()
		var g := ForestGenerator.generate(seed_v)
		slowest = maxi(slowest, Time.get_ticks_msec() - gen_start)

		total_props += g.props.size()
		total_zones += g.spawn_zones.size()
		total_attempts += g.attempts_used

		if not g.failure.is_empty():
			failures.append("seed %d: %s" % [seed_v, g.failure])
			continue

		# 1. the player does not spawn inside an obstacle
		if not g.is_open(g.spawn_point):
			failures.append("seed %d: spawn point is blocked" % seed_v)

		# 2. everything important is reachable on foot from the spawn
		var reachable := g._flood_from(g.spawn_point)
		if not g._reached(reachable, g.shop_point):
			failures.append("seed %d: shop unreachable" % seed_v)
		for idx in g.clearings.size():
			if not g._reached(reachable, g.clearings[idx]["center"]):
				failures.append("seed %d: clearing %d unreachable" % [seed_v, idx])
		for idx in g.loot_points.size():
			if not g._reached(reachable, g.loot_points[idx]):
				failures.append("seed %d: loot point %d unreachable" % [seed_v, idx])

		# 3. no clearing is too cramped to fight in
		for idx in g.clearings.size():
			var open_cells := g.open_cells_in(
				g.clearings[idx]["center"], float(g.clearings[idx]["radius"]))
			worst_clearing = mini(worst_clearing, open_cells)
			if open_cells < ForestGenerator.MIN_CLEARING_OPEN_CELLS:
				failures.append("seed %d: clearing %d has only %d open cells"
					% [seed_v, idx, open_cells])

		# 4. spawn zones exist, are open, and are reachable
		if g.spawn_zones.size() < 60:
			failures.append("seed %d: only %d spawn zones" % [seed_v, g.spawn_zones.size()])
		for z: Vector2 in g.spawn_zones:
			if not g.is_open(z):
				failures.append("seed %d: spawn zone inside an obstacle" % seed_v)
				break
			if not g._reached(reachable, z):
				failures.append("seed %d: spawn zone unreachable" % seed_v)
				break

		# 5. the map is not mostly wall
		var summary := g.debug_summary()
		var open_ratio := float(summary["open_cells"]) / float(summary["total_cells"])
		if open_ratio < 0.25:
			failures.append("seed %d: only %.0f%% of the map is walkable"
				% [seed_v, open_ratio * 100.0])

	var elapsed := Time.get_ticks_msec() - t0
	print("\n=== forest generator ===")
	print("seeds:            %d" % SEEDS)
	print("total time:       %d ms (%.1f ms/seed, slowest %d ms)"
		% [elapsed, float(elapsed) / SEEDS, slowest])
	print("avg props:        %d" % (total_props / SEEDS))
	print("avg spawn zones:  %d" % (total_zones / SEEDS))
	print("avg attempts:     %.2f" % (float(total_attempts) / SEEDS))
	print("tightest clearing: %d open cells (min allowed %d)"
		% [worst_clearing, ForestGenerator.MIN_CLEARING_OPEN_CELLS])

	if failures.is_empty():
		print("RESULT: PASS - all %d seeds produced a playable forest\n" % SEEDS)
		quit(0)
	else:
		print("RESULT: FAIL - %d problems" % failures.size())
		for f: String in failures.slice(0, 25):
			print("  " + f)
		if failures.size() > 25:
			print("  ... and %d more" % (failures.size() - 25))
		print("")
		quit(1)
