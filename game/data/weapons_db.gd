class_name WeaponsDB
extends RefCounted
## The weapons you can carry into a run: five guns and three melee weapons.
##
## A weapon is a LENS over RunState.gun, not a replacement for it. Every shop
## upgrade still edits the same numbers in RunState.gun; the weapon then scales
## and shifts them when a shot (or a swing) is made. That is what keeps the
## whole shop relevant whichever weapon you picked, and it is why caps hold: the
## lens is applied to the capped stats and clamped again by Balance.GUN_CAPS.
##
## Melee is not a gun with a short range. It has no ammo and no reload, it hits
## everything in an arc in front of you at once, and its damage is tagged
## Combat.SOURCE_MELEE - so a Carapace slime that shrugs off bullets does not
## shrug off a blade. That is the reason to carry one.

const KIND_GUN := "gun"
const KIND_MELEE := "melee"

const PISTOL := "pistol"
const DEFAULT := PISTOL

## Per-stat lens: {"stat": [multiplier, addend]}. Missing stats pass through.
## Read by apply(); the numbers in each entry are the whole design of a weapon.
const DEFS := {
	PISTOL: {
		"name": "Pistol",
		"kind": KIND_GUN,
		"desc": "Reliable. Twelve shots, a quick reload, and nothing to get used to.",
		"sprite": "pistol",
		# the gun scene's original numbers, so the pistol is unchanged
		"grip": Vector2(29, 25), "muzzle": Vector2(71, 19),
		"mods": {},
		"cost": 0,
	},
	"scattergun": {
		"name": "Scattergun",
		"kind": KIND_GUN,
		"desc": "Six pellets in a wide cone. Ruinous up close, a shrug at range.",
		"sprite": "weapon_scattergun",
		"grip": Vector2(12, 28), "muzzle": Vector2(68, 22),
		"mods": {
			"damage": [0.5, 0.0], "projectile_count": [1.0, 5.0], "spread": [3.2, 0.0],
			"fire_rate": [0.32, 0.0], "magazine": [0.5, 0.0], "reload_time": [1.2, 0.0],
			"range": [0.5, 0.0], "knockback": [1.4, 0.0],
		},
		"sound": "shoot_heavy",
		"cost": 180,
	},
	"repeater": {
		"name": "Repeater",
		"kind": KIND_GUN,
		"desc": "A drum of thirty-six and a trigger that will not let go. Wanders a little.",
		"sprite": "weapon_repeater",
		"grip": Vector2(16, 26), "muzzle": Vector2(74, 20),
		"mods": {
			"damage": [0.55, 0.0], "fire_rate": [2.1, 0.0], "spread": [2.0, 0.0],
			"magazine": [3.0, 0.0], "reload_time": [1.4, 0.0], "knockback": [0.6, 0.0],
		},
		"cost": 200,
	},
	"longshot": {
		"name": "Longshot",
		"kind": KIND_GUN,
		"desc": "Five heavy rounds that go through three slimes and keep going.",
		"sprite": "weapon_longshot",
		"grip": Vector2(16, 24), "muzzle": Vector2(86, 20),
		"mods": {
			"damage": [3.0, 0.0], "fire_rate": [0.3, 0.0], "penetration": [1.0, 3.0],
			"projectile_speed": [1.7, 0.0], "spread": [0.15, 0.0], "magazine": [0.42, 0.0],
			"range": [1.6, 0.0], "knockback": [1.6, 0.0],
		},
		"sound": "shoot_heavy",
		"cost": 240,
	},
	"launcher": {
		"name": "Ember Launcher",
		"kind": KIND_GUN,
		"desc": "Slow shells that burst where they land. Mind the reload.",
		"sprite": "weapon_launcher",
		"grip": Vector2(16, 32), "muzzle": Vector2(74, 20),
		"mods": {
			"damage": [2.4, 0.0], "fire_rate": [0.28, 0.0], "projectile_speed": [0.62, 0.0],
			"magazine": [0.34, 0.0], "reload_time": [1.3, 0.0], "spread": [0.6, 0.0],
		},
		"explode_radius": 120.0,
		"sound": "shoot_heavy",
		"cost": 280,
	},
	"blade": {
		"name": "Wildblade",
		"kind": KIND_MELEE,
		"desc": "A quick, wide cut. Never reloads, and bullet-proof hides do not stop it.",
		"sprite": "weapon_blade",
		"grip": Vector2(8, 14), "muzzle": Vector2(78, 14),
		"mods": {"damage": [1.7, 0.0], "fire_rate": [0.5, 0.0], "knockback": [1.3, 0.0]},
		"arc_deg": 130.0,
		"reach": 135.0,
		"cost": 0,
	},
	"maul": {
		"name": "Stonemaul",
		"kind": KIND_MELEE,
		"desc": "One enormous swing a second. Everything in front of you goes flying.",
		"sprite": "weapon_maul",
		"grip": Vector2(8, 24), "muzzle": Vector2(66, 24),
		"mods": {"damage": [3.6, 0.0], "fire_rate": [0.2, 0.0], "knockback": [3.2, 0.0]},
		"arc_deg": 200.0,
		"reach": 165.0,
		"heavy": true,
		"cost": 220,
	},
	"spear": {
		"name": "Thornspear",
		"kind": KIND_MELEE,
		"desc": "A long, narrow thrust. Hits everything in a line, from twice a blade's reach.",
		"sprite": "weapon_spear",
		"grip": Vector2(20, 12), "muzzle": Vector2(98, 12),
		"mods": {"damage": [2.2, 0.0], "fire_rate": [0.36, 0.0]},
		"arc_deg": 26.0,
		"reach": 250.0,
		"thrust": true,
		"cost": 200,
	},
}

## Guns first, then melee; free ones lead each group.
const ORDER: Array[String] = [
	PISTOL, "scattergun", "repeater", "longshot", "launcher",
	"blade", "spear", "maul",
]

## Gun stats that mean nothing to a melee weapon. The shop stops offering
## upgrades whose main stat is one of these while you carry one - an offer
## that does nothing is worse than no offer.
const MELEE_IGNORES: Array[String] = [
	"magazine", "reload_time", "projectile_speed", "spread", "penetration",
]


static func sanitise(id: String) -> String:
	return id if DEFS.has(id) else DEFAULT


static func get_def(id: String) -> Dictionary:
	return DEFS[sanitise(id)]


static func is_melee(id: String) -> bool:
	return String(get_def(id)["kind"]) == KIND_MELEE


static func sprite_path(id: String) -> String:
	return "res://assets/sprites/gen/%s.png" % String(get_def(id)["sprite"])


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


## The MetaDB unlock that grants `id`, or "" if it is free.
static func unlock_id(id: String) -> String:
	if is_free(id):
		return ""
	return "wpn_" + sanitise(id)


static func is_free(id: String) -> bool:
	return int(get_def(id)["cost"]) == 0


static func cost(id: String) -> int:
	return int(get_def(id)["cost"])


## RunState.gun as seen through weapon `id`: every lens applied, then clamped
## by the same caps the shop's upgrades are.
static func apply(gun: Dictionary, id: String) -> Dictionary:
	var out := gun.duplicate()
	var mods: Dictionary = get_def(id)["mods"]
	for stat: String in mods:
		if not out.has(stat):
			continue
		var m: Array = mods[stat]
		out[stat] = float(out[stat]) * float(m[0]) + float(m[1])
	for stat: String in Balance.GUN_CAPS:
		if not out.has(stat):
			continue
		var cap := float(Balance.GUN_CAPS[stat])
		# reload_time and spread are floors; everything else is a ceiling
		if stat == "reload_time" or stat == "spread":
			out[stat] = maxf(float(out[stat]), cap)
		else:
			out[stat] = minf(float(out[stat]), cap)
	return out


## Melee reach: the weapon's own, nudged by range upgrades so those still pay.
static func reach(id: String, stats: Dictionary) -> float:
	var base := float(get_def(id).get("reach", 0.0))
	var bonus := maxf(0.0, float(stats.get("range", 900.0)) - 900.0) * 0.12
	return base + bonus


## Melee arc in radians: extra "projectiles" from Split Barrel widen the cut.
static func arc(id: String, stats: Dictionary) -> float:
	var base := float(get_def(id).get("arc_deg", 0.0))
	var extra := maxf(0.0, float(stats.get("projectile_count", 1.0)) - 1.0)
	return deg_to_rad(minf(base * (1.0 + 0.18 * extra), 330.0))


## Whether a shop upgrade does anything for this weapon.
static func upgrade_applies(id: String, stat: String) -> bool:
	if not is_melee(id) or not stat.begins_with("gun."):
		return true
	return not MELEE_IGNORES.has(stat.substr(4))
