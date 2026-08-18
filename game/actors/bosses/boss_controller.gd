extends Node
## Picks the right boss for a wave, places it, and reports when it's down.
##
## Also handles the reward. Boss payouts are large and deliberately arrive as
## a shower of coins at the boss's feet, so the moment of winning and the
## moment of getting paid are the same moment.

const BOSS_SCENE := preload("res://actors/bosses/boss.tscn")

signal boss_cleared(boss: Node2D)

var layout: ForestGenerator = null
var actor_container: Node = null
var bullet_container: Node = null
var current: Boss = null


func setup(forest_layout: ForestGenerator, actors: Node, bullets: Node) -> void:
	layout = forest_layout
	actor_container = actors
	bullet_container = bullets


func spawn_for_wave(wave: int, near: Vector2) -> Boss:
	var pick := BossDB.for_wave(wave)
	var boss := BOSS_SCENE.instantiate() as Boss
	boss.layout = layout
	boss.bullet_container = bullet_container
	boss.spawner = get_tree().get_first_node_in_group("wave_controller") as WaveController
	actor_container.add_child(boss)
	boss.configure(pick["id"], wave, int(pick["repeat"]))

	# Place it in the open, at arm's length - close enough to be immediately
	# threatening, far enough that the entrance isn't a free hit. Clearance is
	# checked against the boss's own radius, not a slime's: a boss dropped into
	# a slime-sized gap wedges there, and the player cannot shoot through the
	# trees holding it.
	var angle := randf() * TAU
	var at := near + Vector2.RIGHT.rotated(angle) * 620.0
	if layout != null:
		at = layout.nearest_open_for(at, boss.hit_radius * 1.25)
	boss.enter(at)
	boss.defeated.connect(_on_boss_defeated)

	current = boss
	return boss


func _on_boss_defeated(boss: Boss) -> void:
	var reward := (Balance.major_boss_reward(boss.wave) if boss.is_major
		else Balance.mini_boss_reward(boss.wave))
	if Game.run != null:
		if boss.is_major:
			Game.run.majors_killed += 1
		else:
			Game.run.minis_killed += 1

	var run := get_parent()
	if run != null and run.has_method("drop_reward"):
		run.call("drop_reward", boss.global_position, reward)

	current = null
	boss_cleared.emit(boss)


func has_active_boss() -> bool:
	return current != null and is_instance_valid(current) and not current.dying
