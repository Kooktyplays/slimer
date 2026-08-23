class_name EnemyTypes
extends RefCounted
## The six enemy colours. Colour, behaviour and stats are declared together so
## they can never drift apart - the colour is a promise about what the thing
## does, and the player learns to read it in one glance.

const GREEN := "green"
const RED := "red"
const BLUE := "blue"
const YELLOW := "yellow"
const PURPLE := "purple"
const ORANGE := "orange"

const ORDER: Array[String] = [GREEN, BLUE, RED, PURPLE, YELLOW, ORANGE]

const DEFS := {
	GREEN: {
		"name": "Slime",
		"behavior": "chase",
		"tint": Color(0.36, 0.80, 0.15),
		"hp": 30.0,
		"speed": 110.0,
		"contact_damage": 8.0,
		"threat": 1.0,
		"money": Vector2i(4, 7),
		"scale": 0.62,
		"radius": 30.0,
		"unlock_wave": 1,
		"weight": 1.0,
		"hint": "Green slimes chase you down. Keep moving.",
	},
	BLUE: {
		"name": "Darter",
		"behavior": "flank",
		"tint": Color(0.16, 0.60, 0.92),
		"hp": 20.0,
		"speed": 215.0,
		"contact_damage": 6.0,
		"threat": 1.2,
		"money": Vector2i(6, 10),
		"scale": 0.54,
		"radius": 25.0,
		"unlock_wave": 4,
		"weight": 0.95,
		"hint": "Blue darters are fast and try to get behind you.",
	},
	RED: {
		"name": "Brute",
		"behavior": "tank",
		"tint": Color(0.86, 0.16, 0.24),
		"hp": 110.0,
		"speed": 62.0,
		"contact_damage": 20.0,
		"threat": 3.0,
		"money": Vector2i(12, 18),
		"scale": 0.92,
		"radius": 44.0,
		"unlock_wave": 6,
		"weight": 0.7,
		"hint": "Red brutes soak damage and hit hard. Don't get cornered.",
	},
	PURPLE: {
		"name": "Spitter",
		"behavior": "ranged",
		"tint": Color(0.60, 0.24, 0.85),
		"hp": 38.0,
		"speed": 95.0,
		"contact_damage": 5.0,
		"threat": 2.2,
		"money": Vector2i(10, 16),
		"scale": 0.64,
		"radius": 30.0,
		"unlock_wave": 9,
		"weight": 0.8,
		"hint": "Purple spitters keep their distance. Close in or break line of sight.",
		# ranged-specific
		"projectile_damage": 9.0,
		"projectile_speed": 430.0,
		"attack_cooldown": 2.1,
		"preferred_range": 420.0,
		"retreat_range": 260.0,
	},
	YELLOW: {
		"name": "Hoarder",
		"behavior": "skittish",
		"tint": Color(0.95, 0.75, 0.12),
		"hp": 45.0,
		"speed": 145.0,
		"contact_damage": 7.0,
		"threat": 1.8,
		# Hoarders are the reason to break off what you are doing and commit to a
		# chase, so the payout has to be worth abandoning position for. At 34-52
		# they paid about three times a Green, which is not enough to change what
		# the player does.
		"money": Vector2i(70, 105),
		"scale": 0.66,
		"radius": 32.0,
		"unlock_wave": 11,
		"weight": 0.55,
		"hint": "Yellow hoarders hoard the gold and run. Hunt them down first.",
		# They break away sooner and keep more distance, so catching one is a
		# decision with a cost rather than something that happens incidentally.
		"flee_range": 520.0,
		"separation_scale": 3.4,
		# Marks the payout as a hoard: it drops as a bigger, brighter shower.
		"hoards": true,
	},
	ORANGE: {
		"name": "Bloater",
		"behavior": "bomber",
		"tint": Color(0.95, 0.45, 0.10),
		"hp": 34.0,
		"speed": 130.0,
		"contact_damage": 0.0,      # all its damage is in the blast
		"threat": 2.4,
		"money": Vector2i(11, 17),
		"scale": 0.70,
		"radius": 34.0,
		"unlock_wave": 15,
		"weight": 0.7,
		"hint": "Orange bloaters detonate. Kill them early, at range.",
		"blast_damage": 26.0,
		"blast_radius": 165.0,
		"fuse_range": 95.0,
		"fuse_time": 0.75,
	},
}

## NOTE: "radius" is the hit radius in world pixels, already final - it is
## deliberately NOT scaled by "scale". Sizing the hitbox off the visual
## scale produced collision circles roughly half the drawn slime, so shots
## that visibly connected passed straight through.

## Elite modifiers layered on top of a base type once elites unlock.
const ELITE_MODS := ["shielded", "enraged", "splitter"]

const ELITE_MOD_INFO := {
	"shielded": {
		"name": "Shielded",
		"desc": "absorbs a burst of damage before taking any",
	},
	"enraged": {
		"name": "Enraged",
		"desc": "is much faster and hits harder",
	},
	"splitter": {
		"name": "Splitter",
		"desc": "breaks into smaller slimes when killed",
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[GREEN])


static func texture_path(id: String) -> String:
	return "res://assets/sprites/gen/enemy_%s_body.png" % id


static func crown_path(id: String) -> String:
	return "res://assets/sprites/gen/elite_crown_%s.png" % id


## Types legal for a given wave, respecting unlock gates.
static func unlocked_for_wave(wave: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		if wave >= int(DEFS[id]["unlock_wave"]):
			out.append(id)
	return out


## Spawn weights for a wave. Newly unlocked types get a temporary boost so the
## player meets them clearly instead of losing one in a crowd, and the basic
## green fades back as the roster fills out.
static func weights_for_wave(wave: int) -> Dictionary:
	var out := {}
	for id: String in unlocked_for_wave(wave):
		var def: Dictionary = DEFS[id]
		var w: float = float(def["weight"])
		var since: int = wave - int(def["unlock_wave"])
		if since <= 2:
			w *= 2.2 - 0.4 * since       # spotlight the new arrival
		if id == GREEN:
			w *= maxf(0.35, 1.0 - 0.035 * wave)
		out[id] = maxf(w, 0.05)
	return out
