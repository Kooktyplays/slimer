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
## Upgrades only offered to the class that can use them.
##
## Kept as a separate map rather than a field on each entry so the shop's
## existing pool logic does not change shape: an id absent from here is
## available to everyone, exactly as before.
const CLASS_LOCKED := {
	"ult_charge": ClassesDB.WARDEN,
	"ult_duration": ClassesDB.WARRIOR,
	"ult_bloodlust": ClassesDB.VAMPIRE,
	"ult_cadence": ClassesDB.ENGINEER,
	"ult_harvest": ClassesDB.HERBALIST,
}

## One per class. All five feed the ultimate rather than the gun, so picking a
## class changes what the shop is *for*, not only what it sells.
##
## Each of these is locked to one class, so each names THAT class's ultimate.
## They used to share three descriptions between five items - three of them read
## "Ultimate charges 25% faster" word for word - which told the player nothing
## about what they were buying and read as a table someone had filled in.
const CLASS_UPGRADES := {
	"ult_charge": {
		"name": "Old Instincts", "cat": CATEGORY_UTILITY,
		"stat": "ultimate_rate", "kind": Kind.MUL, "amount": 1.25,
		"desc": "Recall the Wood comes round 25% sooner", "cost": 210, "weight": 0.9,
	},
	"ult_duration": {
		"name": "Stubborn", "cat": CATEGORY_SURVIVAL,
		"stat": "ultimate_power", "kind": Kind.MUL, "amount": 1.35,
		"desc": "Last Stand holds for 35% longer", "cost": 230, "weight": 0.9,
	},
	"ult_bloodlust": {
		"name": "Thirst", "cat": CATEGORY_SURVIVAL,
		"stat": "ultimate_rate", "kind": Kind.MUL, "amount": 1.25,
		"desc": "Crimson Hour comes round 25% sooner", "cost": 240, "weight": 0.9,
	},
	"ult_cadence": {
		"name": "Tuned", "cat": CATEGORY_UTILITY,
		"stat": "ultimate_rate", "kind": Kind.MUL, "amount": 1.25,
		"desc": "Overclock comes round 25% sooner", "cost": 220, "weight": 0.9,
	},
	"ult_harvest": {
		"name": "Deep Roots", "cat": CATEGORY_UTILITY,
		"stat": "ultimate_power", "kind": Kind.MUL, "amount": 1.35,
		"desc": "Bloom keeps going 35% longer", "cost": 220, "weight": 0.9,
	},
}

# ---------------------------------------------------------------------------
# ability upgrades
# ---------------------------------------------------------------------------
## Upgrades that attach to an ability you are already carrying.
##
## These exist because in-run ability *swapping* was removed. A locked kit only
## works if you can invest in it - that is the Hades arrangement, where you
## cannot change your Attack but every boon makes it better - and it turns the
## pre-run pick from a guess you might regret into a commitment you build on.
##
## Offered as composite ids ("ability:grenade:sharpened") so they flow through
## the same pool, pricing and purchase path as every other upgrade rather than
## needing a second system beside it.
const ABILITY_PREFIX := "ability:"

const ABILITY_KINDS := {
	"sharpened": {
		"label": "Sharpened", "stat": "power", "amount": 1.30,
		"desc": "+30%% damage", "cost": 190, "weight": 1.0,
	},
	"quickened": {
		"label": "Quickened", "stat": "cooldown", "amount": 0.80,
		"desc": "-20%% cooldown", "cost": 210, "weight": 1.0,
	},
	"doubled": {
		"label": "Doubled", "stat": "charges", "amount": 1.0,
		"desc": "+1 charge", "cost": 320, "weight": 0.55,
	},
	"widened": {
		"label": "Widened", "stat": "area", "amount": 1.25,
		"desc": "+25%% area and duration", "cost": 200, "weight": 0.85,
	},
}


## Would buying `kind` for `ability` actually change anything?
##
## The shop used to offer all four kinds for every equipped ability without
## asking. "Sharpened Dash" - +30% damage, 190 coins - was on sale for an
## ability with no damage at all, and it was dead on seven of the fourteen.
## The player has no way to tell a dead row from a live one, so the shop has
## to not print it.
static func kind_applies(ability: String, kind: String) -> bool:
	if not AbilitiesDB.DEFS.has(ability) or not ABILITY_KINDS.has(kind):
		return false
	match String(ABILITY_KINDS[kind]["stat"]):
		"power":
			return AbilitiesDB.scales_any(ability, AbilitiesDB.POWER_KEYS)
		"area":
			return AbilitiesDB.scales_any(ability, AbilitiesDB.area_keys(ability))
	# cooldown and charges live on the slot rather than in the def, so every
	# ability has both - provided the controller actually re-reads them, which
	# is a separate bug and a separate fix.
	return true


static func ability_upgrade_id(ability: String, kind: String) -> String:
	return "%s%s:%s" % [ABILITY_PREFIX, ability, kind]


static func is_ability_upgrade(id: String) -> bool:
	return id.begins_with(ABILITY_PREFIX)


## -> {"ability": id, "kind": kind}, or empty for anything else.
static func parse_ability_upgrade(id: String) -> Dictionary:
	if not is_ability_upgrade(id):
		return {}
	var parts := id.substr(ABILITY_PREFIX.length()).split(":")
	if parts.size() != 2 or not ABILITY_KINDS.has(parts[1]):
		return {}
	return {"ability": parts[0], "kind": parts[1]}


## A def synthesised on demand, named after the ability it upgrades - so the
## shop shows "Quickened Grenade" rather than a generic row.
static func ability_upgrade_def(id: String) -> Dictionary:
	var parsed := parse_ability_upgrade(id)
	if parsed.is_empty() or not AbilitiesDB.DEFS.has(parsed["ability"]):
		return {}
	var kind: Dictionary = ABILITY_KINDS[parsed["kind"]]
	var ability: Dictionary = AbilitiesDB.DEFS[parsed["ability"]]
	return {
		"name": "%s %s" % [kind["label"], ability["name"]],
		"cat": CATEGORY_UTILITY,
		"stat": "ability_upgrade",
		"kind": Kind.SET,
		"amount": 0.0,
		"desc": "%s to %s" % [String(kind["desc"]).replace("%%", "%"),
			ability["name"]],
		"cost": int(kind["cost"]),
		"weight": float(kind["weight"]),
		"ability": parsed["ability"],
		"ability_kind": parsed["kind"],
	}


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


## DEFS plus the class-locked pool. They are declared separately so the shop's
## general offers stay readable as one list, but everything that looks an
## upgrade up has to see both.
static func any_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	if is_ability_upgrade(id):
		return ability_upgrade_def(id)
	return CLASS_UPGRADES.get(id, {})


static func get_def(id: String) -> Dictionary:
	return any_def(id)


static func price(id: String, times_bought: int) -> int:
	var def: Dictionary = any_def(id)
	var base: int = int(def["cost"])
	if def.get("repeatable_price", true):
		return int(round(base * (1.0 + REPEAT_PRICE_STEP * times_bought)))
	return base


## Ids that may appear in the shop given the player's permanent unlocks.
static func available_ids(unlocked: Array, class_id: String = "",
		equipped: Array = []) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = DEFS.keys()
	ids.append_array(CLASS_UPGRADES.keys())
	for id: String in ids:
		var need: Variant = META_LOCKED.get(id)
		if need != null and not unlocked.has(need):
			continue
		# Class upgrades are offered only to the class that can use them. An
		# empty class_id (tests, tooling) sees the unrestricted pool.
		var for_class: Variant = CLASS_LOCKED.get(id)
		if for_class != null and not class_id.is_empty() and for_class != class_id:
			continue
		out.append(id)

	# ...and one of each kind for every ability actually being carried. Only
	# the carried ones: an upgrade to something you did not bring would be a
	# dead offer, and the whole point is investing in what you committed to.
	for ability: String in equipped:
		if not AbilitiesDB.DEFS.has(ability):
			continue
		for kind: String in ABILITY_KINDS:
			# ...and only the kinds that would do something to it.
			if kind_applies(ability, kind):
				out.append(ability_upgrade_id(ability, kind))
	return out
