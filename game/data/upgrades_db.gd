class_name UpgradesDB
extends RefCounted
## The shop pool. Entries are grouped so a run can lean into a recognisable
## build - raw damage, rapid fire, or multi-projectile - without any single
## purchase being strictly correct.
##
## `stat` names starting with "gun." go to RunState.gun; the rest are run-wide
## modifiers on RunState itself.

enum Kind { ADD, MUL, SET }

const CATEGORY_DAMAGE := "damage"
const CATEGORY_RAPID := "rapid"
const CATEGORY_PROJECTILE := "projectile"
const CATEGORY_SURVIVAL := "survival"
const CATEGORY_UTILITY := "utility"

## `locked` entries need a meta unlock before they can appear in the pool.
const DEFS := {
	# ---- damage ------------------------------------------------------------
	"dmg_small": {
		"name": "Hollow Points", "cat": CATEGORY_DAMAGE,
		"stat": "gun.damage", "kind": Kind.ADD, "amount": 3.0,
		"desc": "+3 bullet damage", "cost": 140, "weight": 1.0,
	},
	"dmg_large": {
		"name": "Heavy Slugs", "cat": CATEGORY_DAMAGE,
		"stat": "gun.damage", "kind": Kind.ADD, "amount": 9.0,
		"desc": "+9 bullet damage, -8% fire rate", "cost": 340, "weight": 0.7,
		"side": {"stat": "gun.fire_rate", "kind": Kind.MUL, "amount": 0.92},
	},
	"crit_chance": {
		"name": "Weak Point Optics", "cat": CATEGORY_DAMAGE,
		"stat": "gun.crit_chance", "kind": Kind.ADD, "amount": 0.08,
		"desc": "+8% critical chance", "cost": 185, "weight": 0.9,
	},
	"crit_damage": {
		"name": "Fracture Rounds", "cat": CATEGORY_DAMAGE,
		"stat": "gun.crit_damage", "kind": Kind.ADD, "amount": 0.5,
		"desc": "+0.5x critical damage", "cost": 205, "weight": 0.8,
	},
	"penetration": {
		"name": "Piercing Core", "cat": CATEGORY_DAMAGE,
		"stat": "gun.penetration", "kind": Kind.ADD, "amount": 1.0,
		"desc": "Bullets pass through 1 more enemy", "cost": 265, "weight": 0.75,
	},

	# ---- rapid fire --------------------------------------------------------
	"fire_rate": {
		"name": "Tuned Action", "cat": CATEGORY_RAPID,
		"stat": "gun.fire_rate", "kind": Kind.ADD, "amount": 0.9,
		"desc": "+0.9 shots per second", "cost": 165, "weight": 1.0,
	},
	"fire_rate_big": {
		"name": "Runaway Sear", "cat": CATEGORY_RAPID,
		"stat": "gun.fire_rate", "kind": Kind.ADD, "amount": 2.4,
		"desc": "+2.4 shots/sec, -12% accuracy", "cost": 385, "weight": 0.65,
		"side": {"stat": "gun.spread", "kind": Kind.MUL, "amount": 1.12},
	},
	"magazine": {
		"name": "Extended Drum", "cat": CATEGORY_RAPID,
		"stat": "gun.magazine", "kind": Kind.ADD, "amount": 6.0,
		"desc": "+6 magazine capacity", "cost": 135, "weight": 1.0,
	},
	"reload": {
		"name": "Quick Hands", "cat": CATEGORY_RAPID,
		"stat": "gun.reload_time", "kind": Kind.MUL, "amount": 0.82,
		"desc": "-18% reload time", "cost": 155, "weight": 0.95,
	},

	# ---- projectile --------------------------------------------------------
	"proj_count": {
		"name": "Split Barrel", "cat": CATEGORY_PROJECTILE,
		"stat": "gun.projectile_count", "kind": Kind.ADD, "amount": 1.0,
		"desc": "+1 projectile per shot, -15% damage", "cost": 430, "weight": 0.55,
		"side": {"stat": "gun.damage", "kind": Kind.MUL, "amount": 0.85},
	},
	"proj_speed": {
		"name": "Hot Loads", "cat": CATEGORY_PROJECTILE,
		"stat": "gun.projectile_speed", "kind": Kind.ADD, "amount": 190.0,
		"desc": "+190 projectile speed", "cost": 115, "weight": 0.85,
	},
	"accuracy": {
		"name": "Rifled Bore", "cat": CATEGORY_PROJECTILE,
		"stat": "gun.spread", "kind": Kind.MUL, "amount": 0.74,
		"desc": "-26% bullet spread", "cost": 125, "weight": 0.8,
	},
	"knockback": {
		"name": "Impact Charge", "cat": CATEGORY_PROJECTILE,
		"stat": "gun.knockback", "kind": Kind.ADD, "amount": 80.0,
		"desc": "+80 knockback on hit", "cost": 105, "weight": 0.7,
	},
	"gun_range": {
		"name": "Long Barrel", "cat": CATEGORY_PROJECTILE,
		"stat": "gun.range", "kind": Kind.ADD, "amount": 220.0,
		"desc": "+220 bullet range", "cost": 100, "weight": 0.6,
	},

	# ---- survival ----------------------------------------------------------
	"max_hp": {
		"name": "Thick Hide", "cat": CATEGORY_SURVIVAL,
		"stat": "max_hp", "kind": Kind.ADD, "amount": 20.0,
		"desc": "+20 maximum health, heals 20", "cost": 210, "weight": 1.0,
	},
	"armor": {
		"name": "Bark Plating", "cat": CATEGORY_SURVIVAL,
		"stat": "damage_reduction", "kind": Kind.ADD, "amount": 0.06,
		"desc": "-6% damage taken", "cost": 270, "weight": 0.8,
	},
	"repair": {
		"name": "Field Poultice", "cat": CATEGORY_SURVIVAL,
		"stat": "heal_full", "kind": Kind.SET, "amount": 1.0,
		"desc": "Restore all health right now", "cost": 130, "weight": 0.9,
		"repeatable_price": false,
	},
	"lifesteal_run": {
		"name": "Thirsting Grip", "cat": CATEGORY_SURVIVAL,
		"stat": "lifesteal", "kind": Kind.ADD, "amount": 0.015,
		"desc": "+1.5% of damage dealt returns as health", "cost": 290, "weight": 0.6,
	},

	# ---- utility -----------------------------------------------------------
	"move_speed": {
		"name": "Light Step", "cat": CATEGORY_UTILITY,
		"stat": "move_speed_mul", "kind": Kind.MUL, "amount": 1.08,
		"desc": "+8% movement speed", "cost": 175, "weight": 0.9,
	},
	"ability_cdr": {
		"name": "Focused Mind", "cat": CATEGORY_UTILITY,
		"stat": "ability_cdr", "kind": Kind.ADD, "amount": 0.12,
		"desc": "-12% ability cooldown", "cost": 245, "weight": 0.85,
	},
	"ability_charge": {
		"name": "Deep Reserves", "cat": CATEGORY_UTILITY,
		"stat": "ability_extra_charges", "kind": Kind.ADD, "amount": 1.0,
		"desc": "+1 charge on every ability", "cost": 330, "weight": 0.5,
	},
	"money_bonus": {
		"name": "Keen Eye", "cat": CATEGORY_UTILITY,
		"stat": "money_mul", "kind": Kind.MUL, "amount": 1.14,
		"desc": "+14% money from kills", "cost": 205, "weight": 0.7,
	},
}

## Entries only available once the matching meta unlock is bought.
const META_LOCKED := {
	"proj_count": "upg_split_barrel",
	"lifesteal_run": "upg_thirsting_grip",
	"ability_charge": "upg_deep_reserves",
	"fire_rate_big": "upg_runaway_sear",
	"dmg_large": "upg_heavy_slugs",
}

## Repeat purchases of the same upgrade cost more, so stacking one stat has a
## real opportunity cost against branching out.
const REPEAT_PRICE_STEP := 0.55


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


static func price(id: String, times_bought: int) -> int:
	var def: Dictionary = DEFS[id]
	var base: int = int(def["cost"])
	if def.get("repeatable_price", true):
		return int(round(base * (1.0 + REPEAT_PRICE_STEP * times_bought)))
	return base


## Ids that may appear in the shop given the player's permanent unlocks.
static func available_ids(unlocked: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in DEFS:
		var need: Variant = META_LOCKED.get(id)
		if need == null or unlocked.has(need):
			out.append(id)
	return out
