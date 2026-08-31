extends Node2D
## One run, from spawning in the forest to dying in it.
##
## Owns the world nodes and sequences the wave -> boss -> shop loop. Game holds
## the authoritative state; this node reacts to it and drives the timing.

const PLAYER_SCENE := preload("res://actors/player.tscn")
const PICKUP_SCENE := preload("res://actors/pickup.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
const SHOP_SCENE := preload("res://ui/shop.tscn")
const BOSS_CONTROLLER := preload("res://actors/bosses/boss_controller.gd")

@onready var forest: Forest = $Forest
@onready var effects: Node2D = $Effects
@onready var hud_layer: CanvasLayer = $HUDLayer

var player: Player = null
var waves: WaveController = null
var bosses: Node = null
var hud: Control = null
var shop: Control = null
var layout: ForestGenerator = null

var _intermission := 0.0
var _pending_wave := false
var _hit_stop_until := 0.0


func _ready() -> void:
	Combat.reset()
	FX.setup(effects)

	if Game.run == null:
		# entering the run scene directly (editor / harness) - make one
		Game.start_run(0)

	layout = forest.build(Game.run.seed_value,
		BiomeDB.id_for_depth(Game.depth_for_wave(Game.run.wave + 1)))

	waves = WaveController.new()
	waves.name = "Waves"
	add_child(waves)
	waves.setup(layout, forest.sorted_layer, effects)
	waves.wave_finished.connect(_on_wave_finished)

	bosses = Node.new()
	bosses.name = "Bosses"
	bosses.set_script(BOSS_CONTROLLER)
	add_child(bosses)
	bosses.call("setup", layout, forest.sorted_layer, effects)
	bosses.connect("boss_cleared", _on_boss_cleared)

	_spawn_player()
	_build_hud()

	var tutor := Node.new()
	tutor.name = "Tutor"
	tutor.set_script(preload("res://world/tutor.gd"))
	add_child(tutor)

	Pools.prewarm(PICKUP_SCENE, 60)
	Events.enemy_died.connect(_on_enemy_died)
	Events.hit_stop.connect(_apply_hit_stop)
	Events.shop_closed.connect(_on_shop_closed)
	Events.wave_cleared.connect(_on_wave_cleared)

	# a beat of calm before the first wave, so the player can look around
	_intermission = 2.4
	_pending_wave = true


func _exit_tree() -> void:
	Pools.release_all()
	FX.teardown()
	Combat.reset()
	# Hit stop restores the time scale from a tween owned by this node. Dying
	# during hit stop frees the node with that tween still pending, which used
	# to leave the entire game running at quarter speed forever.
	Engine.time_scale = 1.0


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.global_position = layout.nearest_open(layout.spawn_point)
	forest.sorted_layer.add_child(player)
	player.gun.bullet_container = effects
	player.abilities.setup(player, effects)
	Combat.set_player(player)


func _build_hud() -> void:
	hud = HUD_SCENE.instantiate()
	hud_layer.add_child(hud)
	hud.call("bind", player, waves)


# ---------------------------------------------------------------------------
# per-frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if player != null and is_instance_valid(player):
		forest.follow_camera(player.global_position)
		if Game.run != null:
			Game.run.health_potion_guard = maxf(
				0.0, Game.run.health_potion_guard - delta)

	_tick_terrain(delta)

	if _pending_wave:
		_intermission -= delta
		if _intermission <= 0.0:
			_pending_wave = false
			_begin_wave()


func _begin_wave() -> void:
	if Game.run == null or Game.state != Game.State.RUN:
		return
	var wave := Game.begin_next_wave()
	Audio.play("wave_start", -4.0)

	if Game.is_boss_wave(wave):
		waves.stop()
		bosses.call("spawn_for_wave", wave, player.global_position)
	else:
		waves.start_wave(wave)


func _on_wave_finished(wave: int) -> void:
	if Game.state != Game.State.RUN:
		return
	Audio.play("wave_clear", -6.0)
	FX.floating_text(player.global_position + Vector2(0, -110),
		"WAVE %d CLEAR" % wave, Color(0.7, 1.0, 0.75))
	Game.notify_wave_cleared()
	_queue_next_wave()


func _on_boss_cleared(_boss: Node2D) -> void:
	if Game.state != Game.State.RUN:
		return
	# sweep up any adds the boss left behind before the shop opens
	waves.clear_all_enemies()
	# ...and bank the payout before anything can read the balance. This has to
	# happen before notify_wave_cleared(), because for a boss wave that call
	# opens the shop itself - see Game.notify_wave_cleared.
	_bank_loose_coins()
	Game.notify_wave_cleared()
	_open_shop()


## Instantly credit every coin still lying in the forest.
##
## A boss drops its reward as a shower of coins that fly to the player over
## about half a second. The shop opens on the same frame the boss dies and reads
## Game.run.money as it builds, so it showed the balance from *before* the kill:
## beat a boss for 300 with 400 in hand and the shop offered you 400, not 700.
## The coins did arrive a moment later, but by then the number was already
## drawn, and it stayed wrong until a purchase happened to redraw it.
##
## Banking is instant rather than accelerated because any flight time at all
## re-opens the same race.
func _bank_loose_coins() -> void:
	var total := 0
	var at := player.global_position if is_instance_valid(player) else Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group(Pickup.GROUP):
		var pickup := node as Pickup
		if pickup != null and pickup.kind == Pickup.COIN and not pickup.collected:
			total += pickup.collect_instantly()
	if total <= 0:
		return
	# One report for the whole payout - five separate "+14" numbers stacked on
	# the same pixel is noise, not feedback.
	Audio.play("coin", -10.0)
	FX.floating_text(at + Vector2(0, -140), "+%d" % total, Color(1.0, 0.86, 0.35))


func _queue_next_wave() -> void:
	if Game.phase == Game.Phase.SHOP:
		return
	_intermission = Balance.WAVE_INTERMISSION if not Game.fast_mode else 0.2
	_pending_wave = true


# ---------------------------------------------------------------------------
# shop
# ---------------------------------------------------------------------------
func _open_shop() -> void:
	if shop != null and is_instance_valid(shop):
		return
	shop = SHOP_SCENE.instantiate()
	hud_layer.add_child(shop)
	shop.call("open")


func _on_shop_closed() -> void:
	if shop != null and is_instance_valid(shop):
		shop.queue_free()
	shop = null
	_maybe_descend()
	_queue_next_wave()


# ---------------------------------------------------------------------------
# terrain hazards
# ---------------------------------------------------------------------------
## What the biome's standing water does to whoever walks into it.
##
## Every hazard is a different *meaning* for geometry the generator already
## produces, rather than a new system: `layout.ponds` is the same list of
## {center, radius} in all five biomes, and the biome decides whether that is
## water to wade through, embers to avoid, or sap that poisons. Which is also
## why each one is legible - the pools are painted in the biome's own water
## texture, so the hazard is visible well before it is felt.
##
## The Hollow is the exception: its hazard is the dark itself, which is a
## screen effect rather than a place you can stand.
const TERRAIN_SLOW := 0.62
## Damage per second while standing in a hazard pool. Sized so a pool can be
## crossed but not camped in: at 9 dps a run through Ashfall's embers costs a
## few health, and standing in one is a steady drain you can watch happen.
const TERRAIN_DPS_FIRE := 9.0
const TERRAIN_DPS_BRAMBLE := 6.0


func _tick_terrain(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or layout == null:
		return
	var hazard := String(forest.biome_def.get("hazard", BiomeDB.HAZARD_NONE))
	# Cleared every frame and re-set only while actually standing in something,
	# so walking out of a pool stops the effect on the same frame.
	player.terrain_speed_mul = 1.0
	player.terrain_dps = 0.0
	if hazard == BiomeDB.HAZARD_NONE or hazard == BiomeDB.HAZARD_GLOOM:
		return

	var at := player.global_position
	var inside := false
	for pond: Dictionary in layout.ponds:
		if at.distance_to(pond["center"]) <= float(pond["radius"]):
			inside = true
			break
	if not inside:
		return

	match hazard:
		BiomeDB.HAZARD_WATER:
			player.terrain_speed_mul = TERRAIN_SLOW
		BiomeDB.HAZARD_FIRE:
			player.terrain_dps = TERRAIN_DPS_FIRE
		BiomeDB.HAZARD_BRAMBLE:
			player.terrain_dps = TERRAIN_DPS_BRAMBLE


# ---------------------------------------------------------------------------
# descending
# ---------------------------------------------------------------------------
## Regenerate the forest when the next wave belongs to a deeper biome.
##
## The timing is not a coincidence: Balance.WAVES_PER_DEPTH and MINI_BOSS_EVERY
## are both 5, so every depth boundary is a boss wave followed by a shop. By
## the time the shop closes the arena is empty by construction - the boss is
## dead, _on_boss_cleared swept its adds and banked every coin - so the whole
## rebuild happens behind a screen the player was already reading.
##
## Regenerating rather than recolouring is the point. The forest is supposed to
## be a place that rearranges itself so it cannot be learned; a new palette over
## identical geometry would say the opposite.
func _maybe_descend() -> void:
	if Game.run == null or Game.state != Game.State.RUN:
		return
	var next_biome := BiomeDB.id_for_depth(Game.depth_for_wave(Game.run.wave + 1))
	if next_biome == forest.biome:
		return

	# Park every pooled node first. Pickups still lying in the forest are
	# children of the layer about to be freed, and a pool holding a freed node
	# hands that node out again on the next acquire. release_all() exists for
	# exactly this - a world teardown that the pools have to survive.
	Pools.release_all()

	# The player is a child of forest.sorted_layer, which the rebuild frees.
	# Reparenting rather than respawning keeps the run: health, abilities,
	# cooldowns and every upgrade bought so far all live on this node.
	var keep_player := is_instance_valid(player) and player.get_parent() != null
	if keep_player:
		player.get_parent().remove_child(player)

	# Seeded from the run seed *and* the depth, so a run is still reproducible
	# from the one number the results screen shows.
	layout = forest.build(Game.run.seed_value + Game.depth_for_wave(
		Game.run.wave + 1) * 104729, next_biome)

	if keep_player:
		forest.sorted_layer.add_child(player)
		player.global_position = layout.nearest_open(layout.spawn_point)
		player.velocity = Vector2.ZERO

	# Re-point everything that cached the old layout or the old parent node.
	# Both setups are pure reference assignment - they reset no wave state.
	waves.setup(layout, forest.sorted_layer, effects)
	bosses.call("setup", layout, forest.sorted_layer, effects)

	var def := BiomeDB.get_def(next_biome)
	Events.biome_changed.emit(next_biome, String(def["name"]))
	if keep_player:
		FX.floating_text(player.global_position + Vector2(0, -140),
			String(def["name"]).to_upper(), Color(0.85, 0.9, 1.0))
	Audio.play("boss_phase", -4.0)


# ---------------------------------------------------------------------------
# drops
# ---------------------------------------------------------------------------
func _on_enemy_died(enemy: Node2D, at: Vector2) -> void:
	if Game.run == null:
		return
	Game.run.kills += 1

	var money := int(enemy.get("money_value"))
	if money > 0:
		_drop_coins(at, money, bool(enemy.get("hoards")))
	_maybe_drop_potion(at, enemy)


## Split a payout into a few coins so a big reward reads as a shower rather
## than a single sprite worth 90.
##
## A hoarder bursts into far more coins than its payout alone would justify.
## Killing one is meant to feel like cracking something open, and the reward has
## to be legible at the moment it happens or the chase never seems worth it.
func _drop_coins(at: Vector2, total: int, hoard: bool = false) -> void:
	var cap := 12 if hoard else 5
	var per_coin := 9.0 if hoard else 14.0
	var count := clampi(int(ceil(total / per_coin)), 1, cap)
	var per := maxi(1, int(round(float(total) / count)))
	for i in count:
		var p := Pools.acquire(PICKUP_SCENE, forest.sorted_layer) as Pickup
		p.configure(Pickup.COIN, at, per)
	if hoard:
		FX.burst(at, Color(1.0, 0.86, 0.35), 22, 1.1)
		Audio.play("coin", -4.0)


func _maybe_drop_potion(at: Vector2, enemy: Node2D) -> void:
	var guarded := Game.run.health_potion_guard > 0.0
	var chance := Balance.potion_chance(Game.run.wave, Game.run.hp_fraction(), guarded)
	if bool(enemy.get("is_elite")):
		chance *= 2.4
	if randf() > chance:
		return

	# Weight the roll towards what the player actually lacks, but only inside
	# the already-capped drop chance, so this can't be farmed for sustain.
	var kinds: Array[String] = [Pickup.HEALTH, Pickup.SPEED, Pickup.ABILITY]
	var weights: Array[float] = [1.0, 1.0, 1.0]
	if Game.run.hp_fraction() > 0.85 or guarded:
		weights[0] = 0.15
	elif Game.run.hp_fraction() < 0.45:
		weights[0] = 2.4

	var total: float = weights[0] + weights[1] + weights[2]
	var roll := randf() * total
	var kind: String = kinds[2]
	for i in 3:
		roll -= weights[i]
		if roll <= 0.0:
			kind = kinds[i]
			break

	var p := Pools.acquire(PICKUP_SCENE, forest.sorted_layer) as Pickup
	p.configure(kind, at)


func drop_reward(at: Vector2, money: int) -> void:
	_drop_coins(at, money)


## Clearing a wave collects every coin still on the ground. A fight can scatter
## payouts across a whole clearing, and walking the arena picking them up
## afterwards is dead time between waves - the reward should arrive when you
## win, not when you finish tidying up.
##
## Coins only. Potions stay where they fell, so taking one is still a decision.
func _on_wave_cleared(_wave: int) -> void:
	for node: Node in get_tree().get_nodes_in_group(Pickup.GROUP):
		var pickup := node as Pickup
		if pickup != null and pickup.kind == Pickup.COIN and not pickup.collected:
			pickup.attract()


# ---------------------------------------------------------------------------
# hit stop
# ---------------------------------------------------------------------------
## A few frames of slowed time on heavy impacts. Very short - long hit stop in
## a game with this much simultaneous action reads as a frame drop.
func _apply_hit_stop(duration: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _hit_stop_until or Game.fast_mode:
		return
	# The cooldown is deliberately much longer than the effect. Surrounded by a
	# dozen enemies the player is hit constantly, and re-triggering hit stop on
	# every one of those keeps the game in slow motion - which reads as the
	# game lagging, not as impact.
	_hit_stop_until = now + maxf(duration, 0.45)
	Engine.time_scale = 0.25
	# ignore_time_scale so the restore fires on a real-time schedule; a scaled
	# timer would take four times as long to undo its own slowdown
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void: Engine.time_scale = 1.0)
