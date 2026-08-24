class_name Pickup
extends Node2D
## Coins and potions.
##
## Collection is a distance check rather than an Area2D, because these need a
## magnet radius anyway - once you're measuring distance for the magnet, a
## physics area for the pickup itself is a second broadphase entry doing work
## the magnet already did.

const COIN := "coin"
const HEALTH := "potion_health"
const SPEED := "potion_speed"
const ABILITY := "potion_ability"

## Potions point at the sliced single-bottle versions, not the pack's raw
## files - those are 3x3 sheets and draw as a block of nine.
const TEXTURES := {
	COIN: "res://assets/sprites/gen/coin_strip.png",
	HEALTH: "res://assets/sprites/gen/potion_red.png",
	SPEED: "res://assets/sprites/gen/potion_blue.png",
	ABILITY: "res://assets/sprites/gen/potion_purple.png",
}
const TINTS := {
	COIN: Color(1.0, 0.85, 0.35),
	HEALTH: Color(1.0, 0.35, 0.40),
	SPEED: Color(0.35, 0.70, 1.0),
	ABILITY: Color(0.72, 0.45, 1.0),
}

## Draw scale for potions. Coins sit at 1.0; a potion is a rarer and more
## valuable thing and should read as one from across a clearing.
const POTION_SCALE := 1.35

const BASE_MAGNET := 165.0
const PICKUP_RADIUS := 34.0
const MAGNET_SPEED := 900.0
## Speed of the end-of-wave sweep, which ignores the magnet radius entirely.
const VACUUM_SPEED := 1500.0
const LIFETIME := 26.0
const GROUP := "pickup"

@onready var _sprite: Sprite2D = $Sprite
@onready var _glow: Sprite2D = $Glow

var kind := COIN
var value := 1
var collected := false

var _velocity := Vector2.ZERO
var _bob := 0.0
var _life := 0.0
var _settle := 0.0
var _vacuum := false


func configure(pickup_kind: String, at: Vector2, amount: int = 1) -> void:
	kind = pickup_kind
	value = amount
	collected = false
	global_position = at
	visible = true
	modulate.a = 1.0
	_life = LIFETIME
	_bob = randf() * TAU
	_settle = 0.45
	# pop out of the corpse rather than appearing under it
	_velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 240.0)

	_sprite.texture = load(TEXTURES[kind])
	_sprite.hframes = 6 if kind == COIN else 1
	_sprite.frame = 0
	# Potions are drawn larger than the coins, not smaller. They were at 0.85
	# against a coin's 1.0, which made the rarest and most valuable drop in the
	# game the least visible thing on the ground - play-testers walked past them.
	_sprite.scale = Vector2.ONE * (1.0 if kind == COIN else POTION_SCALE)
	_glow.modulate = Color(TINTS[kind].r, TINTS[kind].g, TINTS[kind].b, 0.35)
	_glow.scale = Vector2.ONE * (0.45 if kind == COIN else 1.05)
	_vacuum = false
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	set_process(true)


## Fly straight to the player from wherever this is, ignoring magnet range.
## Called on every coin when a wave clears, so finishing a fight collects the
## payout instead of leaving the player to sweep the clearing on foot.
func attract() -> void:
	if collected:
		return
	_vacuum = true
	_settle = 0.0            # cancel the scatter, redirect immediately
	_life = maxf(_life, 6.0) # don't let one expire mid-flight
	_velocity = Vector2.ZERO


## Bank this pickup where it lies, with no flight and no collection tween.
##
## The shop reads Game.run.money when it builds, and a boss payout is a shower
## of coins that takes about half a second to fly in - so the shop used to open
## showing the total from *before* the boss died. Coins the player has visibly
## earned have to be in the bank before anything can read the balance.
##
## Only the money moves here: no per-coin audio or floating text, because five
## coins banking on one frame is a burst of noise, not five rewards. The caller
## reports the total instead.
func collect_instantly() -> int:
	if collected or kind != COIN:
		return 0
	collected = true
	set_process(false)
	var banked := value
	if Game.run != null:
		Game.run.add_money(value)
	Events.pickup_collected.emit(kind, global_position)
	Pools.release(self)
	return banked


func _process(delta: float) -> void:
	if collected:
		return

	_bob += delta * 6.0
	_sprite.position.y = -14.0 + sin(_bob) * 4.0
	if kind == COIN:
		_sprite.frame = int(_bob * 1.6) % 6

	# initial scatter, then the magnet takes over
	if _settle > 0.0:
		_settle -= delta
		global_position += _velocity * delta
		_velocity = _velocity.move_toward(Vector2.ZERO, 900.0 * delta)

	var p := Combat.player()
	if p == null:
		return

	# A potion that cannot do anything right now is left where it lies rather
	# than being burned for a "FULL" message, and its expiry timer is paused
	# while it waits - so it is still there when you finally need it.
	var useful := _is_useful(p)
	if useful:
		_life -= delta
		if _life <= 0.0:
			_expire()
			return
	else:
		_sprite.modulate.a = 0.6 + 0.15 * sin(_bob * 0.6)   # dimmed: not usable
		return
	_sprite.modulate.a = 1.0

	var to_player := p.global_position - global_position
	var dist := to_player.length()
	var magnet := BASE_MAGNET * (Game.run.pickup_range_mul if Game.run != null else 1.0)

	if dist <= PICKUP_RADIUS:
		_collect(p)
	elif _vacuum:
		global_position = global_position.move_toward(
			p.global_position, VACUUM_SPEED * delta)
	elif dist <= magnet:
		# accelerate as it closes, so pickups snap in satisfyingly
		var pull := 1.0 - dist / magnet
		global_position += to_player / dist * MAGNET_SPEED * pull * delta

	# don't blink out a coin that is already on its way in
	if _life < 4.0 and not _vacuum:
		modulate.a = 0.35 + 0.65 * absf(sin(_life * 8.0))


## Would collecting this right now actually do something?
##
## Coins always count. A health potion at full health and an ability potion at
## full charges are pure waste - and since potions are meant to feel valuable,
## silently eating one is worse than leaving it on the ground.
func _is_useful(player: Node2D) -> bool:
	match kind:
		HEALTH:
			return Game.run == null or Game.run.hp < Game.run.max_hp - 0.5
		ABILITY:
			var controller: Variant = player.get("abilities")
			if controller == null:
				return false
			return controller.charges_missing() > 0
		_:
			return true


func _collect(player: Node2D) -> void:
	if collected:
		return
	collected = true
	set_process(false)

	match kind:
		COIN:
			if Game.run != null:
				Game.run.add_money(value)
			# One kill drops up to five coins and the magnet pulls them in
			# together, so this fires in bursts. Throttled to one blip per
			# burst rather than five stacked on top of each other.
			Audio.play_throttled("coin", 0.11, -15.0, 0.22)
			FX.floating_text(global_position + Vector2(0, -40),
				"+%d" % value, Color(1.0, 0.86, 0.35))
		HEALTH:
			if player.has_method("heal") and Game.run != null:
				player.call("heal", Game.run.max_hp * Balance.HEALTH_POTION_RESTORE)
				Game.run.health_potion_guard = Balance.HEALTH_POTION_COOLDOWN
			Audio.play("potion", -4.0)
			Events.potion_used.emit(HEALTH)
		SPEED:
			if player.has_method("apply_speed_boost"):
				player.call("apply_speed_boost",
					Balance.SPEED_POTION_MULTIPLIER, Balance.SPEED_POTION_DURATION)
			FX.floating_text(global_position + Vector2(0, -40), "SWIFT",
				Color(0.45, 0.8, 1.0))
			Audio.play("potion", -4.0, 0.10)
			Events.potion_used.emit(SPEED)
		ABILITY:
			var restored := 0
			if player.get("abilities") != null:
				restored = player.abilities.refill_all()
			FX.floating_text(global_position + Vector2(0, -40),
				"ABILITIES READY" if restored > 0 else "CHARGED",
				Color(0.78, 0.5, 1.0))
			FX.ring(global_position, 120.0, Color(0.78, 0.5, 1.0), 0.4, 0.25)
			Audio.play("potion", -4.0, -0.08)
			Events.potion_used.emit(ABILITY)

	FX.burst(global_position, TINTS[kind], 8, 0.6)
	Events.pickup_collected.emit(kind, global_position)

	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE * 1.6, 0.14)
	t.tween_property(self, "modulate:a", 0.0, 0.14)
	t.chain().tween_callback(func() -> void:
		scale = Vector2.ONE
		Pools.release(self))


func _expire() -> void:
	set_process(false)
	Pools.release(self)


func _pool_reset() -> void:
	collected = true
	_vacuum = false
	set_process(false)
	scale = Vector2.ONE
	modulate.a = 1.0
	if is_in_group(GROUP):
		remove_from_group(GROUP)
