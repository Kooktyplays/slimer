class_name FX
extends Node
## Spawns the short-lived visual effects: impacts, muzzle flashes, damage
## numbers, death bursts, explosions and telegraphs.
##
## Everything here is pooled. During a wave these spawn dozens of times a
## second, and instantiating/freeing them is exactly the churn that makes big
## waves stutter.
##
## `FX.setup(container)` must be called once per run with the node the effects
## should be parented to.

static var _container: Node = null

const IMPACT := preload("res://fx/impact.tscn")
const MUZZLE := preload("res://fx/muzzle_flash.tscn")
const DAMAGE_NUMBER := preload("res://fx/damage_number.tscn")
const BURST := preload("res://fx/burst.tscn")
const RING := preload("res://fx/ring_pulse.tscn")


static func setup(container: Node) -> void:
	_container = container
	Pools.prewarm(IMPACT, 32)
	Pools.prewarm(MUZZLE, 12)
	Pools.prewarm(DAMAGE_NUMBER, 40)
	Pools.prewarm(BURST, 24)
	Pools.prewarm(RING, 12)


static func teardown() -> void:
	_container = null


static func _ok() -> bool:
	return _container != null and is_instance_valid(_container)


static func impact(at: Vector2, color: Color = Color.WHITE, scale: float = 1.0) -> void:
	if not _ok():
		return
	var n := Pools.acquire(IMPACT, _container) as Node2D
	n.call("play", at, color, scale)


static func muzzle_flash(at: Vector2, angle: float) -> void:
	if not _ok():
		return
	var n := Pools.acquire(MUZZLE, _container) as Node2D
	n.call("play", at, angle)


static func damage_number(at: Vector2, amount: float, is_crit: bool) -> void:
	if not _ok() or not bool(Save.settings["damage_numbers"]):
		return
	var n := Pools.acquire(DAMAGE_NUMBER, _container) as Node2D
	n.call("play", at, amount, is_crit)


static func floating_text(at: Vector2, text: String, color: Color) -> void:
	if not _ok():
		return
	var n := Pools.acquire(DAMAGE_NUMBER, _container) as Node2D
	n.call("play_text", at, text, color)


static func burst(at: Vector2, color: Color, count: int = 12, power: float = 1.0) -> void:
	if not _ok():
		return
	var n := Pools.acquire(BURST, _container) as Node2D
	n.call("play", at, color, count, power)


## Expanding ring - used for explosions, nova, boss slams and telegraphs.
static func ring(at: Vector2, radius: float, color: Color, duration: float = 0.4,
		expand_from: float = 0.15) -> void:
	if not _ok():
		return
	var n := Pools.acquire(RING, _container) as Node2D
	n.call("play", at, radius, color, duration, expand_from)


## Ground marker that fills up before a boss attack lands.
static func telegraph(at: Vector2, radius: float, duration: float,
		color: Color = Color(1.0, 0.35, 0.25)) -> void:
	if not _ok():
		return
	var n := Pools.acquire(RING, _container) as Node2D
	n.call("play_telegraph", at, radius, color, duration)


static func explosion(at: Vector2, radius: float, color: Color = Color(1.0, 0.62, 0.22)) -> void:
	ring(at, radius, color, 0.45, 0.10)
	burst(at, color, 18, 1.6)
	impact(at, Color(1, 1, 1, 0.9), radius / 70.0)
