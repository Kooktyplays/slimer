class_name WaveController
extends Node
## Decides what spawns, when, and where.
##
## Difficulty is a *threat budget*, not an HP multiplier. Each wave gets a
## budget; each enemy type costs threat; the spawner buys enemies from the
## types unlocked so far until the budget is spent. That means a late wave is
## harder because it contains more and nastier things in worse combinations,
## which is a problem the player can out-play, rather than because a green
## slime now has 4000 HP, which is just a longer trigger pull.
##
## Elites are bought out of the same budget at a premium, so a wave that rolls
## elites automatically contains fewer bodies.

const ENEMY_SCENE := preload("res://actors/enemy.tscn")

signal wave_finished(wave: int)

var layout: ForestGenerator = null
var enemy_container: Node = null
var bullet_container: Node = null

var active := false
var wave := 0
var budget_remaining := 0.0
var spawn_accumulator := 0.0
var alive_count := 0

var _rng := RandomNumberGenerator.new()
var _weights: Dictionary = {}
var _finished_emitted := false


func _ready() -> void:
	add_to_group("wave_controller")
	Pools.prewarm(ENEMY_SCENE, 40)
	Events.enemy_died.connect(_on_enemy_died)


func setup(forest_layout: ForestGenerator, enemies_parent: Node, bullets_parent: Node) -> void:
	layout = forest_layout
	enemy_container = enemies_parent
	bullet_container = bullets_parent


# ---------------------------------------------------------------------------
# wave lifecycle
# ---------------------------------------------------------------------------
func start_wave(wave_number: int) -> void:
	wave = wave_number
	_rng.seed = (Game.run.seed_value if Game.run != null else 0) * 31 + wave * 7717
	budget_remaining = Balance.wave_budget(wave)
	_weights = EnemyTypes.weights_for_wave(wave)
	spawn_accumulator = 0.0
	alive_count = 0
	_finished_emitted = false
	active = true
	Combat.finisher_mode = false

	# Open with a visible cluster instead of a slow trickle, so a wave starts
	# as an event rather than an ambient drip.
	var opening := minf(budget_remaining * 0.35, 14.0)
	_spend(opening)


## Boss waves suppress the normal spawner; the boss controller drives them.
func stop() -> void:
	active = false


func clear_all_enemies() -> void:
	for e: Node2D in Combat.enemies():
		if e.has_method("die"):
			e.call("die", false)
	alive_count = 0


const FINISHER_THRESHOLD := 4


func _process(delta: float) -> void:
	if not active:
		return

	# once nothing more is coming and only a few are left, they all commit
	Combat.finisher_mode = (budget_remaining <= 0.0
		and Combat.enemy_count() <= FINISHER_THRESHOLD)

	if budget_remaining > 0.0:
		spawn_accumulator += delta * Balance.spawn_rate(wave)
		if spawn_accumulator >= 1.0:
			var chunk := minf(spawn_accumulator, budget_remaining)
			spawn_accumulator = 0.0
			_spend(chunk)
	elif alive_count <= 0 and not _finished_emitted:
		_finished_emitted = true
		active = false
		wave_finished.emit(wave)


# ---------------------------------------------------------------------------
# spending the budget
# ---------------------------------------------------------------------------
func _spend(amount: float) -> void:
	var spent := 0.0
	var guard := 0
	while spent < amount and budget_remaining > 0.0 and guard < 40:
		guard += 1
		if Combat.enemy_count() >= Balance.MAX_CONCURRENT_ENEMIES:
			return                                  # hold the rest back
		var id := _pick_type()
		var elite := _roll_elite()
		var cost := float(EnemyTypes.get_def(id)["threat"])
		if not elite.is_empty():
			cost *= Balance.ELITE_THREAT_MULTIPLIER
		if cost > budget_remaining and spent > 0.0:
			break
		if _spawn(id, elite):
			spent += cost
			budget_remaining -= cost
		else:
			break                                   # nowhere valid to put it


func _pick_type() -> String:
	var total := 0.0
	for k: String in _weights:
		total += float(_weights[k])
	var roll := _rng.randf() * total
	for k: String in _weights:
		roll -= float(_weights[k])
		if roll <= 0.0:
			return k
	return EnemyTypes.GREEN


func _roll_elite() -> String:
	if _rng.randf() >= Balance.elite_chance(wave):
		return ""
	return EnemyTypes.ELITE_MODS[_rng.randi() % EnemyTypes.ELITE_MODS.size()]


func _spawn(id: String, elite: String) -> bool:
	var pos := _find_spawn_position()
	if pos == Vector2.INF:
		return false
	_instantiate(id, pos, wave, elite)
	return true


## Spawn far enough away to be fair, close enough to be relevant, on open
## ground, and preferably off-screen. Never on top of the player.
func _find_spawn_position() -> Vector2:
	if layout == null or layout.spawn_zones.is_empty():
		return Vector2.INF
	var player_pos := Combat.player_position()
	var best := Vector2.INF
	var best_score := -INF

	for attempt in 22:
		var candidate: Vector2 = layout.spawn_zones[_rng.randi() % layout.spawn_zones.size()]
		var d := candidate.distance_to(player_pos)
		if d < Balance.SPAWN_MIN_DISTANCE or d > Balance.SPAWN_MAX_DISTANCE:
			continue
		if not layout.is_open(candidate):
			continue
		# prefer the near edge of the allowed band: enemies that spawn at the
		# far limit spend the first ten seconds walking, which is not a fight
		var score := -absf(d - Balance.SPAWN_MIN_DISTANCE * 1.25) + _rng.randf() * 90.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _instantiate(id: String, pos: Vector2, for_wave: int, elite: String) -> Enemy:
	var e := Pools.acquire(ENEMY_SCENE, enemy_container) as Enemy
	e.global_position = pos
	e.bullet_container = bullet_container
	e.layout = layout
	e.configure(id, for_wave, elite)
	alive_count += 1
	return e


## Used by splitter elites, which spawn children outside the budget.
func spawn_split(id: String, at: Vector2, for_wave: int) -> void:
	if Combat.enemy_count() >= Balance.MAX_CONCURRENT_ENEMIES:
		return
	var pos := layout.nearest_open(at) if layout != null else at
	var e := _instantiate(id, pos, maxi(1, for_wave - 2), "")
	# children are noticeably smaller and cheaper than what they came from
	e.max_hp *= 0.5
	e.hp = e.max_hp
	e.money_value = maxi(1, int(e.money_value * 0.35))


## Directly place an enemy - used by boss adds and by the sim harness.
func spawn_at(id: String, at: Vector2, for_wave: int, elite: String = "") -> Enemy:
	if Combat.enemy_count() >= Balance.MAX_CONCURRENT_ENEMIES:
		return null
	var pos := layout.nearest_open(at) if layout != null else at
	return _instantiate(id, pos, for_wave, elite)


func _on_enemy_died(_enemy: Node2D, _at: Vector2) -> void:
	alive_count = maxi(0, alive_count - 1)


# ---------------------------------------------------------------------------
# introspection (HUD + tests)
# ---------------------------------------------------------------------------
func remaining_estimate() -> int:
	var avg := 1.6
	return Combat.enemy_count() + int(budget_remaining / avg)


## What a wave would be made of, without spawning anything. Used by
## tests/test_waves.gd to check the composition curve.
static func preview_composition(wave_number: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + wave_number * 7717
	var weights := EnemyTypes.weights_for_wave(wave_number)
	var budget := Balance.wave_budget(wave_number)
	var counts := {}
	var elites := 0
	var guard := 0
	while budget > 0.0 and guard < 400:
		guard += 1
		var total := 0.0
		for k: String in weights:
			total += float(weights[k])
		var roll := rng.randf() * total
		var pick := EnemyTypes.GREEN
		for k: String in weights:
			roll -= float(weights[k])
			if roll <= 0.0:
				pick = k
				break
		var cost := float(EnemyTypes.get_def(pick)["threat"])
		var is_elite := rng.randf() < Balance.elite_chance(wave_number)
		if is_elite:
			cost *= Balance.ELITE_THREAT_MULTIPLIER
			elites += 1
		budget -= cost
		counts[pick] = int(counts.get(pick, 0)) + 1
	return {"counts": counts, "elites": elites, "budget": Balance.wave_budget(wave_number)}
