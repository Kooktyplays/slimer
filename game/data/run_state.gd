class_name RunState
extends RefCounted
## Everything that dies with the player.
##
## Nothing here is persisted. Permanent unlocks live in Save and are applied
## *into* a fresh RunState at the start of a run, which keeps the "death resets
## the run" rule impossible to get wrong: we simply throw this object away.

var seed_value: int = 0
var wave: int = 0
var money: int = 0

# gun stats, copied from Balance.GUN_BASE then mutated by upgrades
var gun: Dictionary = {}

# run-wide modifiers
var max_hp: float = Balance.PLAYER_MAX_HP
var hp: float = Balance.PLAYER_MAX_HP
var damage_reduction: float = 0.0
var move_speed_mul: float = 1.0
var pickup_range_mul: float = 1.0
var ability_cdr: float = 0.0
var ability_extra_charges: int = 0
var lifesteal: float = 0.0
var money_mul: float = 1.0
var free_rerolls: int = 0

# loadout
var abilities: Array[String] = ["dash", "grenade", "nova"]

# bookkeeping
var upgrades_bought: Dictionary = {}     # id -> count
var kills: int = 0
var minis_killed: int = 0
var majors_killed: int = 0
var damage_dealt: float = 0.0
var money_earned: int = 0
var rerolls_used: int = 0
var health_potion_guard: float = 0.0     # seconds left on the anti-farm guard
var started_at_ms: int = 0


func _init() -> void:
	gun = Balance.GUN_BASE.duplicate()
	started_at_ms = Time.get_ticks_msec()


## Build a run from the player's permanent unlocks.
static func create(seed_v: int, save_unlocks: Array, loadout: Array[String]) -> RunState:
	var rs := RunState.new()
	rs.seed_value = seed_v
	rs.abilities = loadout.duplicate()
	var essence_mul := 0.0
	for id: String in save_unlocks:
		if not MetaDB.DEFS.has(id):
			continue
		var def: Dictionary = MetaDB.DEFS[id]
		if def["kind"] != MetaDB.KIND_PASSIVE:
			continue
		var stat: String = def["stat"]
		var amount: float = float(def["amount"])
		match stat:
			"max_hp":
				rs.max_hp += amount
			"start_money":
				rs.money += int(amount)
			"gun.damage":
				rs.gun["damage"] = float(rs.gun["damage"]) + amount
			"ability_extra_charges":
				rs.ability_extra_charges += int(amount)
			"free_rerolls":
				rs.free_rerolls += int(amount)
			"essence_mul":
				essence_mul += amount
	rs.hp = rs.max_hp
	rs.set_meta("essence_mul", 1.0 + essence_mul)
	return rs


## Essence multiplier granted by permanent passives.
func essence_multiplier() -> float:
	return float(get_meta("essence_mul", 1.0))


func hp_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


func is_low_health() -> bool:
	return hp_fraction() <= Balance.LOW_HEALTH_FRACTION and hp > 0.0


func add_money(amount: int) -> void:
	var gained := int(round(amount * money_mul))
	money += gained
	money_earned += gained
	Events.money_changed.emit(money, gained)


func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	Events.money_changed.emit(money, -amount)
	return true


## Apply a shop upgrade. Returns false if the id is unknown.
func apply_upgrade(id: String) -> bool:
	if not UpgradesDB.DEFS.has(id):
		return false
	var def: Dictionary = UpgradesDB.get_def(id)
	_apply_effect(def["stat"], def["kind"], float(def["amount"]))
	var side: Variant = def.get("side")
	if side != null:
		_apply_effect(side["stat"], side["kind"], float(side["amount"]))
	upgrades_bought[id] = int(upgrades_bought.get(id, 0)) + 1
	Events.gun_upgraded.emit(def["stat"], stat_value(def["stat"]))
	return true


func _apply_effect(stat: String, kind: int, amount: float) -> void:
	if stat == "heal_full":
		hp = max_hp
		Events.player_healed.emit(max_hp)
		return

	if stat.begins_with("gun."):
		var key := stat.substr(4)
		var cur := float(gun.get(key, 0.0))
		gun[key] = _clamp_gun(key, _combine(cur, kind, amount))
		return

	var before := stat_value(stat)
	var after := _combine(before, kind, amount)
	match stat:
		"max_hp":
			var delta := after - max_hp
			max_hp = after
			hp = minf(hp + maxf(delta, 0.0), max_hp)
		"damage_reduction":
			damage_reduction = minf(after, 0.70)     # never fully immune
		"move_speed_mul":
			move_speed_mul = minf(after, 1.85)
		"pickup_range_mul":
			pickup_range_mul = minf(after, 4.0)
		"ability_cdr":
			ability_cdr = minf(after, 0.60)
		"ability_extra_charges":
			ability_extra_charges = int(after)
		"lifesteal":
			lifesteal = minf(after, 0.35)
		"money_mul":
			money_mul = after


func _combine(current: float, kind: int, amount: float) -> float:
	match kind:
		UpgradesDB.Kind.ADD:
			return current + amount
		UpgradesDB.Kind.MUL:
			return current * amount
		_:
			return amount


func _clamp_gun(key: String, value: float) -> float:
	if not Balance.GUN_CAPS.has(key):
		return maxf(value, 0.0)
	var cap := float(Balance.GUN_CAPS[key])
	# reload_time and spread are floors; everything else is a ceiling
	if key in ["reload_time", "spread"]:
		return maxf(value, cap)
	return minf(value, cap)


func stat_value(stat: String) -> float:
	if stat.begins_with("gun."):
		return float(gun.get(stat.substr(4), 0.0))
	match stat:
		"max_hp": return max_hp
		"damage_reduction": return damage_reduction
		"move_speed_mul": return move_speed_mul
		"pickup_range_mul": return pickup_range_mul
		"ability_cdr": return ability_cdr
		"ability_extra_charges": return float(ability_extra_charges)
		"lifesteal": return lifesteal
		"money_mul": return money_mul
		_: return 0.0


func times_bought(id: String) -> int:
	return int(upgrades_bought.get(id, 0))


## Damage per second at full uptime, used for the run-results screen.
func effective_dps() -> float:
	var mag := float(gun["magazine"])
	var rate := float(gun["fire_rate"])
	var cycle := mag / rate + float(gun["reload_time"])
	var per_shot := float(gun["damage"]) * float(gun["projectile_count"])
	var crit := 1.0 + float(gun["crit_chance"]) * (float(gun["crit_damage"]) - 1.0)
	return per_shot * crit * mag / cycle


func summary() -> Dictionary:
	return {
		"wave": wave,
		"kills": kills,
		"minis": minis_killed,
		"majors": majors_killed,
		"money_earned": money_earned,
		"damage_dealt": damage_dealt,
		"dps": effective_dps(),
		"seed": seed_value,
		"duration_ms": Time.get_ticks_msec() - started_at_ms,
		"abilities": abilities.duplicate(),
	}
