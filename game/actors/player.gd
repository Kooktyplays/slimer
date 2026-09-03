class_name Player
extends CharacterBody2D
## The player character.
##
## Feel notes, because these are the numbers that decide whether the game is
## fun rather than merely correct:
##  * acceleration is high and friction higher, so input-to-motion is near
##    instant but the character still has weight when you let go
##  * aim is read every frame from the raw mouse position, never smoothed -
##    smoothing aim always feels like input lag
##  * the body squashes and stretches with speed, which sells motion without
##    needing walk-cycle art

const SHADOW_TEXTURE := preload("res://assets/sprites/gen/ground_shadow.png")
## Base size of the character. The squash-and-stretch below multiplies this,
## so it must be applied there too - setting it only in the scene would be
## overwritten on the first animated frame.
const VISUAL_SCALE := 1.18

signal health_changed(hp: float, max_hp: float)
signal died()

@onready var _body: Sprite2D = $Visual/Body
@onready var _outline: Sprite2D = $Visual/Outline
@onready var _face: Sprite2D = $Visual/Body/Face
@onready var _visual: Node2D = $Visual
@onready var _shadow: Sprite2D = $Shadow
@onready var gun: Gun = $Gun
@onready var abilities: AbilityController = $Abilities
@onready var camera: GameCamera = $Camera
@onready var _reticle: Sprite2D = $Reticle

var alive := true
var aim_direction := Vector2.RIGHT
var invulnerable_until := 0.0

## Set by abilities / potions.
var speed_multiplier := 1.0
## Seconds left on the Swift potion / Surge speed boost, and the duration it
## started from. Tracked as plain state rather than hidden inside a tween so the
## HUD can draw how long is left - and so a second pickup mid-boost refreshes it
## instead of the first one's callback cutting the second one short.
var speed_boost_left := 0.0
var speed_boost_total := 0.0

## Lingering slime poison. Stacks with each slime that reaches you, ticks
## through healing, and expires on its own.
var poison_stacks := 0
var poison_left := 0.0
var poison_dps := 0.0
var _poison_tick := 0.0
var shield_absorb := 0.0
var lifesteal_bonus := 0.0

## Warrior's Last Stand: while this is in the future, damage taken is thrown
## back out around you. Stored as a timestamp rather than a bool so it expires
## on its own and cannot be left stuck on by a tween that outlived the run.
## What counts as "surrounded" for the Warrior's charge.
const BRAWL_RADIUS := 290.0
const BRAWL_ENEMIES := 3

var retaliating_until := 0.0
## Vampire's Crimson Hour: while this is in the future, a kill near you spreads
## to whatever is beside it.
var contagion_until := 0.0


func is_retaliating() -> bool:
	return Time.get_ticks_msec() / 1000.0 < retaliating_until


func is_contagious() -> bool:
	return Time.get_ticks_msec() / 1000.0 < contagion_until
var dashing := false

var _bob := 0.0
var _hurt_flash := 0.0
var _shoot_held := false


func _ready() -> void:
	# The hurtbox carries the PLAYER layer so enemy bullets hit the drawn
	# character rather than the shadow under it; the body only collides with the
	# forest. See Enemy._apply_hit_shapes for the full reasoning.
	collision_layer = 0
	var hurtbox := $Hurtbox as Area2D
	hurtbox.collision_layer = Layers.PLAYER
	hurtbox.collision_mask = 0
	collision_mask = Layers.WORLD
	_shadow.texture = SHADOW_TEXTURE
	# Who you were before you died. Falls back to the scene's own texture if
	# there is no run, so the player still draws in the editor and in tests.
	if Game.run != null:
		var path := ClassesDB.sprite_path(Game.run.class_id)
		if ResourceLoader.exists(path):
			_body.texture = load(path)
	_shadow.modulate = Color(0, 0, 0, 0.28)
	# pure white: the player is the only white thing in a green forest full of
	# saturated slimes, and that is the whole readability strategy
	_body.modulate = Color(1, 1, 1)
	add_to_group("player")
	_emit_health()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_speed_boost(delta)
	_tick_poison(delta)
	_tick_terrain_damage(delta)
	_move(delta)
	_aim()
	_handle_shooting()
	_animate(delta)


# ---------------------------------------------------------------------------
# movement
# ---------------------------------------------------------------------------
func _move(delta: float) -> void:
	if dashing:
		move_and_slide()
		_hold_in_bounds()
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var target := input * max_speed()
	if input == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, Balance.PLAYER_FRICTION * delta)
	else:
		velocity = velocity.move_toward(target, Balance.PLAYER_ACCEL * delta)
	move_and_slide()
	_hold_in_bounds()


## Lift the drawn character off its own shadow for the length of a leap.
##
## This is the whole difference between a jump and a dash, and it is cheap
## because Shadow and Visual are siblings in player.tscn: raising one and not
## the other IS the jump. The shadow shrinks and fades toward the apex, which
## is what makes the landing point readable before the landing happens.
##
## The collision mask is dropped for the flight so the leap passes over trees.
## A leap that stops at a trunk is not a leap - but it does mean the landing has
## to be pushed to open ground, or you come down inside one.
const LEAP_HEIGHT := 78.0


func begin_leap(duration: float) -> void:
	airborne = true
	dashing = true
	collision_mask = 0
	var t := create_tween()
	t.set_parallel(true)
	# a parabola, not a slide: up fast, hang, down fast
	t.tween_method(func(v: float) -> void:
		if is_instance_valid(_visual):
			_visual.position.y = -LEAP_HEIGHT * sin(v * PI),
		0.0, 1.0, duration)
	t.tween_method(func(v: float) -> void:
		if is_instance_valid(_shadow):
			var shrink := 1.0 - 0.45 * sin(v * PI)
			_shadow.scale = Vector2.ONE * shrink
			_shadow.modulate.a = 0.28 * shrink,
		0.0, 1.0, duration)


func end_leap() -> void:
	airborne = false
	dashing = false
	collision_mask = Layers.WORLD
	if is_instance_valid(_visual):
		_visual.position.y = 0.0
	if is_instance_valid(_shadow):
		_shadow.scale = Vector2.ONE
		_shadow.modulate.a = 0.28


## Offset from the physics origin - the feet, where the shadow is drawn - to the
## middle of the drawn character. Visual/Body sits at y=-28 inside Visual, which
## player.tscn scales by 1.18.
const HIT_OFFSET := Vector2(0, -28.0 * 1.18)


## Where the player is actually drawn, relative to their physics origin.
func hit_center() -> Vector2:
	return global_position + HIT_OFFSET


## Backstop behind the forest's boundary wall.
##
## The wall does the real work and stops ordinary movement, dashes and vaults,
## because they all move through the physics engine and respect Layers.WORLD.
## This exists for anything that sets a position directly instead - a teleport,
## a knockback resolved outside move_and_slide, a future ability - because being
## outside the arena is unrecoverable for the player and the cost of preventing
## it is two comparisons a frame.
func _hold_in_bounds() -> void:
	var limit := ForestGenerator.WALL_INSET + Balance.PLAYER_RADIUS
	var size := ForestGenerator.WORLD_SIZE
	global_position = Vector2(
		clampf(global_position.x, limit, size.x - limit),
		clampf(global_position.y, limit, size.y - limit))


## Set by the run each frame from whatever the player is standing in. Kept
## separate from speed_multiplier so terrain and a Swift potion can both apply
## without either one clobbering the other's bookkeeping.
## True while a leap is in the air. Distinct from `dashing`, which only means
## "moving under an ability's own velocity": airborne additionally means the
## player is ABOVE the forest and passes over blockers.
var airborne := false

var terrain_speed_mul := 1.0

## Damage per second from whatever the player is standing in, set by the run
## each frame. Flat, and deliberately NOT routed through apply_poison: that
## adds a stack per call and multiplies dps by the stack count, which is right
## for contact poison - where the pressure is meant to scale with how many
## slimes reached you - and badly wrong for standing in a pool, where six
## re-applications turned a 7 dps hazard into 42 and killed the player in
## about two seconds. Standing in fire should be a steady, readable rate.
var terrain_dps := 0.0
var _terrain_damage_tick := 0.0


func max_speed() -> float:
	var run_mul := Game.run.move_speed_mul if Game.run != null else 1.0
	return Balance.PLAYER_SPEED * run_mul * speed_multiplier * terrain_speed_mul


# ---------------------------------------------------------------------------
# aiming and shooting
# ---------------------------------------------------------------------------
## Set by the headless sim harness, which has no mouse. Vector2.INF means
## "use the real cursor".
var aim_override := Vector2.INF

## How far in front of the player the gamepad reticle sits.
const AIM_RETICLE_DISTANCE := 320.0
var _gamepad_aim := Vector2.ZERO


## Aim target for this frame.
##
## Right stick wins when it is actually deflected; otherwise the mouse. Falling
## back rather than locking to a mode means a player can switch mid-fight
## without the aim snapping somewhere unexpected, and a controller that is
## plugged in but idle never fights the mouse for control.
func _aim_target() -> Vector2:
	if aim_override != Vector2.INF:
		return aim_override
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > InputBinds.JOY_DEADZONE:
		_gamepad_aim = stick.normalized()
		return global_position + _gamepad_aim * AIM_RETICLE_DISTANCE
	if Game.using_gamepad() and _gamepad_aim != Vector2.ZERO:
		# stick released but still on a controller: hold the last heading
		return global_position + _gamepad_aim * AIM_RETICLE_DISTANCE
	return get_global_mouse_position()


func _aim() -> void:
	var mouse := _aim_target()
	var dir := mouse - global_position
	if dir.length_squared() > 4.0:
		aim_direction = dir.normalized()
	gun.aim_at(mouse)
	# face and gun follow the aim, so the character always reads as pointed at
	# what the cursor is on
	_face.position.x = clampf(aim_direction.x * 6.0, -6.0, 6.0)
	_body.flip_h = aim_direction.x < 0.0
	_outline.flip_h = _body.flip_h

	# On a controller there is no cursor, so the aim direction needs to be
	# drawn or you are shooting blind. `top_level` keeps it in world space
	# rather than inheriting the player's squash-and-stretch.
	var pad := Game.using_gamepad()
	_reticle.visible = pad
	if pad:
		_reticle.global_position = global_position + aim_direction * AIM_RETICLE_DISTANCE
		_reticle.rotation += get_physics_process_delta_time() * 1.2


func _handle_shooting() -> void:
	_shoot_held = Input.is_action_pressed("shoot")
	if _shoot_held:
		gun.try_fire(aim_direction)
	if Input.is_action_just_pressed("reload"):
		gun.start_reload()


# ---------------------------------------------------------------------------
# animation
# ---------------------------------------------------------------------------
func _animate(delta: float) -> void:
	var speed_frac := clampf(velocity.length() / maxf(max_speed(), 1.0), 0.0, 1.0)
	_bob += delta * (7.0 + speed_frac * 10.0)

	# squash and stretch: taller and narrower while moving fast
	var squash := 1.0 + sin(_bob) * (0.035 + speed_frac * 0.055)
	_visual.scale = Vector2(2.0 - squash, squash) * VISUAL_SCALE
	_visual.position.y = -sin(_bob) * (2.0 + speed_frac * 5.0)
	_shadow.scale = Vector2.ONE * VISUAL_SCALE * (1.0 - speed_frac * 0.08)

	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)
		_body.modulate = Color(1, 1, 1).lerp(Color(1.6, 0.4, 0.4), _hurt_flash)

	# I-frames blink the outline rather than fading the whole character.
	# Fading was clearer in isolation but made the player genuinely hard to
	# find in a crowd, which is the worst possible moment to lose track of it.
	var invuln := is_invulnerable() and not dashing
	if invuln:
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 45.0)
		_outline.modulate = Color(0.07, 0.11, 0.09).lerp(Color(1.0, 0.95, 0.6), blink)
	else:
		_outline.modulate = Color(0.07, 0.11, 0.09)
	_visual.modulate.a = 1.0


# ---------------------------------------------------------------------------
# damage
# ---------------------------------------------------------------------------
## Brief mercy after an ability puts you down somewhere new. Shared by Dash and
## the Vault so the two can never drift apart.
func grant_landing_grace() -> void:
	invulnerable_until = maxf(invulnerable_until,
		Time.get_ticks_msec() / 1000.0 + Balance.LANDING_GRACE)


## Extra damage reduction from a temporary source - currently Surge, which
## trades invulnerability for a smaller, constant cushion.
var bonus_damage_reduction := 0.0


func is_invulnerable() -> bool:
	return dashing or Time.get_ticks_msec() / 1000.0 < invulnerable_until


func take_damage(amount: float, _crit: bool = false, from: Vector2 = Vector2.ZERO,
		_knockback: float = 0.0, _source: String = Combat.SOURCE_OTHER) -> void:
	if not alive or is_invulnerable() or Game.run == null:
		return

	var incoming := amount * (1.0 - Game.run.damage_reduction) \
		* (1.0 - bonus_damage_reduction)

	# a shield eats damage before health does, and reports what it absorbed
	if shield_absorb > 0.0:
		var absorbed := minf(shield_absorb, incoming)
		shield_absorb -= absorbed
		incoming -= absorbed
		FX.floating_text(global_position + Vector2(0, -60),
			"-%d" % int(absorbed), Color(0.55, 0.85, 1.0))
		if shield_absorb <= 0.0:
			FX.ring(global_position, 90.0, Color(0.5, 0.8, 1.0), 0.3, 0.6)
		if incoming <= 0.01:
			return

	Game.run.hp = maxf(0.0, Game.run.hp - incoming)
	invulnerable_until = Time.get_ticks_msec() / 1000.0 + Balance.PLAYER_IFRAMES
	_hurt_flash = 1.0
	Game.run.break_combo()

	# Last Stand. What hits you comes back out - which is why the Warrior is
	# the one class that wants to be hit, and why its ultimate is the only one
	# that gets better the worse things are going.
	if is_retaliating():
		var out := incoming * 3.0
		FX.ring(global_position, 300.0, Color(0.95, 0.55, 0.4), 0.35, 0.2)
		Combat.explode(global_position, 300.0, out, 280.0, false,
			Combat.SOURCE_ABILITY)
		on_damage_dealt(out)

	Audio.play("player_hurt", -3.0)
	Game.shake(Balance.SHAKE_HIT, 0.22)
	Events.player_damaged.emit(incoming, from)
	Events.hit_stop.emit(0.05)
	_emit_health()
	Game.notify_health_changed()

	if Game.run.hp <= 0.0:
		_die()


## Add a stack of slime poison, or refresh the ones already running.
##
## Deliberately not routed through take_damage: that grants i-frames, so a DoT
## ticking through it would either do nothing at all (blocked by the i-frames it
## just granted) or leave the player permanently invulnerable between ticks.
func apply_poison(dps_per_stack: float, duration: float) -> void:
	if not alive:
		return
	poison_dps = maxf(poison_dps, dps_per_stack)
	poison_stacks = mini(poison_stacks + 1, Balance.CONTACT_POISON_MAX_STACKS)
	poison_left = maxf(poison_left, duration)


## Fraction of the current poison left, 0..1, for the HUD.
func poison_fraction() -> float:
	if poison_left <= 0.0:
		return 0.0
	return clampf(poison_left / Balance.CONTACT_POISON_DURATION, 0.0, 1.0)


func _tick_poison(delta: float) -> void:
	if poison_left <= 0.0:
		# Clear any residue. poison_left can reach zero without this function
		# being the one that took it there, and leaving stacks behind would make
		# the next single stack hit for the strength of the last full pile.
		if poison_stacks > 0:
			poison_stacks = 0
			poison_dps = 0.0
		return
	if Game.run == null:
		return
	poison_left -= delta
	_poison_tick -= delta
	if _poison_tick <= 0.0:
		_poison_tick = Balance.CONTACT_POISON_INTERVAL
		_take_poison_damage(poison_dps * poison_stacks
			* Balance.CONTACT_POISON_INTERVAL)
	if poison_left <= 0.0:
		poison_stacks = 0
		poison_dps = 0.0


## Terrain damage, on the same cadence as poison and through the same
## application - it must not grant i-frames either, or wading through an ember
## pool would make the player briefly invulnerable to everything else.
func _tick_terrain_damage(delta: float) -> void:
	if terrain_dps <= 0.0 or not alive:
		_terrain_damage_tick = 0.0
		return
	_terrain_damage_tick -= delta
	if _terrain_damage_tick <= 0.0:
		_terrain_damage_tick = Balance.CONTACT_POISON_INTERVAL
		_take_poison_damage(terrain_dps * Balance.CONTACT_POISON_INTERVAL)


## Poison damage. Reduced by armour and eaten by a shield like anything else,
## but it grants no i-frames, does not shake the camera and does not hit-stop -
## four of these a second doing any of that would read as the game stuttering.
func _take_poison_damage(amount: float) -> void:
	if not alive or Game.run == null or amount <= 0.0:
		return
	var incoming := amount * (1.0 - Game.run.damage_reduction)
	if shield_absorb > 0.0:
		var absorbed := minf(shield_absorb, incoming)
		shield_absorb -= absorbed
		incoming -= absorbed
		if incoming <= 0.01:
			return
	Game.run.hp = maxf(0.0, Game.run.hp - incoming)
	Events.player_damaged.emit(incoming, global_position)
	_emit_health()
	Game.notify_health_changed()
	if Game.run.hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if not alive or Game.run == null:
		return
	var before := Game.run.hp
	Game.run.hp = minf(Game.run.max_hp, Game.run.hp + amount)
	var gained := Game.run.hp - before
	if gained > 0.0:
		FX.floating_text(global_position + Vector2(0, -70),
			"+%d" % int(round(gained)), Color(0.45, 0.95, 0.5))
		Events.player_healed.emit(gained)
	_emit_health()
	Game.notify_health_changed()


## Called whenever the player deals damage, so lifesteal can pay out.
func on_damage_dealt(amount: float) -> void:
	if Game.run == null:
		return
	Game.run.damage_dealt += amount
	Game.run.add_ultimate_charge(ClassesDB.CHARGE_DEALT, amount)

	# The Warrior charges from swinging while surrounded - doing the job, not
	# surviving a beating. Only counted when the crowd is real, so kiting one
	# straggler does not fill the meter.
	if Combat.enemies_in_radius(global_position, BRAWL_RADIUS).size() >= BRAWL_ENEMIES:
		Game.run.add_ultimate_charge(ClassesDB.CHARGE_BRAWL, amount)
	var fraction := Game.run.lifesteal + lifesteal_bonus
	if fraction > 0.0:
		heal(amount * fraction)


func _die() -> void:
	if not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	_shoot_held = false
	Audio.play("death", 0.0, 0.0)
	FX.burst(global_position, Color(1, 1, 1), 26, 1.8)
	Game.shake(Balance.SHAKE_EXPLOSION, 0.6)
	var t := create_tween()
	t.tween_property(_visual, "scale", Vector2(1.6, 0.2), 0.35).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_visual, "modulate:a", 0.0, 0.45)
	died.emit()
	Events.player_died.emit()


func _emit_health() -> void:
	if Game.run != null:
		health_changed.emit(Game.run.hp, Game.run.max_hp)


# ---------------------------------------------------------------------------
# used by abilities
# ---------------------------------------------------------------------------
## Apply or refresh the speed boost.
##
## This used to set speed_multiplier and start a tween that reset it to 1.0 when
## it finished. Drinking a second Swift potion part-way through the first left
## two tweens running, and the *first* one's callback would fire mid-way through
## the second boost and end it early - the potion visibly did nothing.
##
## Refresh, never stack: the stronger multiplier and the longer of the two
## remaining times win, so a second potion always extends and never shortens.
func apply_speed_boost(multiplier: float, duration: float) -> void:
	if speed_boost_left <= 0.0:
		speed_multiplier = multiplier
	else:
		speed_multiplier = maxf(speed_multiplier, multiplier)
	speed_boost_left = maxf(speed_boost_left, duration)
	speed_boost_total = speed_boost_left


## How much of the current speed boost is left, 0..1. Zero when none is running.
func speed_boost_fraction() -> float:
	if speed_boost_left <= 0.0 or speed_boost_total <= 0.0:
		return 0.0
	return clampf(speed_boost_left / speed_boost_total, 0.0, 1.0)


func _tick_speed_boost(delta: float) -> void:
	if speed_boost_left <= 0.0:
		return
	speed_boost_left = maxf(0.0, speed_boost_left - delta)
	if speed_boost_left <= 0.0:
		speed_multiplier = 1.0
		speed_boost_total = 0.0
