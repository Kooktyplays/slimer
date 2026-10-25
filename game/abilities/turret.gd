extends Node2D
## An Engineer turret: stationary, automatic, and yours.
##
## The one thing in the game that fights without you. It is the Engineer's
## whole identity - every other class is a set of numbers on the player, this
## one puts something on the map and leaves it there, which makes *where* you
## stand a decision rather than only *when* you move.
##
## **Turrets inherit your gun upgrades.** Damage, fire rate, crit and pierce are
## read live off `Game.run.gun`, so every shop purchase makes the turrets better
## too. That is the trick Risk of Rain 2's Engineer uses, and it is what stops
## the class being a parallel system bolted next to the shop instead of wired
## into it.
##
## Turret fire is tagged SOURCE_BULLET like any other bullet, which means Warded
## slimes shrug it off and a shelled Carapace does too. That interaction is free
## and worth keeping: a turret is not an answer to everything.

const PROJECTILE := preload("res://weapons/projectile.tscn")

## Turrets are deliberately weaker per shot than the player's own gun. They are
## uptime and positioning, not a second player.
const DAMAGE_SHARE := 0.55
const RATE_SHARE := 0.70
const RANGE := 620.0
const LIFETIME := 26.0

var _player: Node2D = null
var _life := LIFETIME
var _cooldown := 0.0
var _barrel: Sprite2D = null
var _base: Sprite2D = null
var _spin := 0.0

## Set by Overclock. While this is in the future the turret fires far faster,
## reaches further, and does not expire.
var overclocked_until := 0.0


func setup(player: Node2D, at: Vector2) -> void:
	_player = player
	global_position = at
	_life = LIFETIME
	add_to_group("turret")

	_base = Sprite2D.new()
	_base.texture = load("res://assets/sprites/gen/turret_base.png")
	add_child(_base)

	_barrel = Sprite2D.new()
	_barrel.texture = load("res://assets/sprites/gen/turret_barrel.png")
	_barrel.position = Vector2(0, -14)
	add_child(_barrel)

	# Deploy rather than appear, the same way Thornwall grows out of the ground.
	scale = Vector2(0.2, 0.2)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FX.ring(at, 80.0, Color(0.95, 0.8, 0.35), 0.35, 0.15)
	Audio.play("upgrade", -10.0)


func is_overclocked() -> bool:
	return Time.get_ticks_msec() / 1000.0 < overclocked_until


func _process(delta: float) -> void:
	var boosted := is_overclocked()

	# Overclock also suspends the clock: a turret should not expire mid-ultimate.
	if not boosted:
		_life -= delta
		if _life <= 0.0:
			_expire()
			return
		# blink out the last second, like Thornwall, so it is never a surprise
		if _life < 1.0:
			modulate.a = 0.35 + 0.65 * absf(sin(_life * 14.0))

	_spin += delta * (14.0 if boosted else 4.0)
	if _base != null:
		_base.rotation = sin(_spin * 0.4) * 0.06

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var reach := RANGE * (1.45 if boosted else 1.0)
	var target := Combat.nearest_enemy(global_position, reach)
	if target == null:
		return

	var dir := (Combat.hit_center(target) - global_position).normalized()
	if _barrel != null:
		_barrel.rotation = dir.angle() + PI * 0.5
	_fire(dir)
	_cooldown = _interval() * (0.32 if boosted else 1.0)


## Fire rate, read live off the player's gun so upgrades carry over.
func _interval() -> float:
	var rate := 3.0
	if Game.run != null:
		rate = maxf(float(Game.run.gun.get("fire_rate", 3.0)), 0.5)
	return 1.0 / (rate * RATE_SHARE)


func _fire(dir: Vector2) -> void:
	var damage := 8.0
	var crit_chance := 0.0
	var crit_mul := 1.5
	var pierce := 0
	if Game.run != null:
		damage = float(Game.run.gun.get("damage", 8.0)) * DAMAGE_SHARE
		crit_chance = float(Game.run.gun.get("crit_chance", 0.0))
		crit_mul = float(Game.run.gun.get("crit_damage", 1.5))
		pierce = int(Game.run.gun.get("pierce", 0))

	var crit := randf() < crit_chance
	if crit:
		damage *= crit_mul

	var b := Pools.acquire(PROJECTILE, get_parent()) as Node2D
	b.call("launch", global_position + dir * 22.0, dir, {
		"damage": damage,
		"crit": crit,
		"speed": 880.0,
		"range": RANGE * 1.2,
		"pierce": pierce,
		"from_player": true,
		"color": Color(1.0, 0.86, 0.45),
		"scale": 0.85,
	})
	Audio.play_throttled("shoot", 0.09, -20.0, 0.16)


func _expire() -> void:
	set_process(false)
	FX.burst(global_position, Color(0.95, 0.8, 0.35), 12, 1.1)
	remove_from_group("turret")
	queue_free()
