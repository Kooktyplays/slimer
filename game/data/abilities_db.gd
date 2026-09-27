class_name AbilitiesDB
extends RefCounted
## The fourteen special abilities, in two classes.
##
## A **movement** ability lives in its own slot and is always available. That
## separation exists because it had to: when Dash competed for a general slot it
## won every time, since it is the only source of invulnerability in the game and
## several boss attacks cannot be walked out of at all. Making it a tax on one of
## your two picks meant you really had one pick.
##
## The two **general** slots are where the interesting argument happens - burst,
## control, sustain - and those are written to pull against each other rather
## than being straight upgrades of one another.

const CLASS_MOVEMENT := "movement"
const CLASS_GENERAL := "general"

## Slot layout. Index 0 is movement, the rest are general.
const SLOT_CLASSES: Array[String] = [CLASS_MOVEMENT, CLASS_GENERAL, CLASS_GENERAL]
const SLOT_COUNT := 3

const DEFS := {
	"dash": {
		"name": "Dash",
		"desc": "Gone from where you were. For a moment nothing can reach you.",
		"icon": "icon_dash",
		"sound": "dash",
		"cooldown": 3.2,
		"charges": 2,
		"class": CLASS_MOVEMENT,
		"default": true,
		"essence": 0,
		"distance": 320.0,
		"duration": 0.16,
	},
	"grenade": {
		"name": "Grenade",
		"desc": "Throw it and stand back. 90 damage, 190 across.",
		"icon": "icon_grenade",
		"sound": "explosion",
		"cooldown": 7.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": true,
		"essence": 0,
		"damage": 90.0,
		"radius": 190.0,
		"fuse": 0.75,
	},
	"shield": {
		"name": "Bulwark",
		"desc": "Something between you and the next 120 damage. Six seconds.",
		"icon": "icon_shield",
		"sound": "shield",
		"cooldown": 14.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 120,
		"absorb": 120.0,
		"duration": 6.0,
	},
	"timeslow": {
		"name": "Torpor",
		"desc": "The forest drops to a third of itself for four seconds. Bullets too.",
		"icon": "icon_timeslow",
		"sound": "timeslow",
		"cooldown": 18.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 200,
		"factor": 0.35,
		"duration": 4.0,
	},
	"nova": {
		"name": "Nova",
		"desc": "Everything close leaves in a hurry, and hurt.",
		"icon": "icon_nova",
		"sound": "nova",
		"cooldown": 11.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": true,
		"essence": 0,
		"damage": 70.0,
		"radius": 300.0,
		"knockback": 640.0,
	},
	"heal": {
		"name": "Bloom",
		"desc": "A third of you, back, at once.",
		"icon": "icon_heal",
		"sound": "heal",
		"cooldown": 26.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 180,
		"fraction": 0.35,
	},
	"lightning": {
		"name": "Stormcall",
		"desc": "It jumps. Up to seven of them, if seven are standing close enough.",
		"icon": "icon_lightning",
		"sound": "lightning",
		"cooldown": 9.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 220,
		"damage": 55.0,
		"jumps": 7,
		"jump_range": 320.0,
	},
	"rapidfire": {
		"name": "Frenzy",
		"desc": "Three times the rate and nothing to reload, for five seconds.",
		"icon": "icon_rapidfire",
		"sound": "rapidfire",
		"cooldown": 20.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 240,
		"multiplier": 3.0,
		"duration": 5.0,
	},
	"orbital": {
		"name": "Satellites",
		"desc": "Three of them, circling, for twelve seconds. Walk through the crowd.",
		"icon": "icon_orbital",
		"sound": "orbital",
		"cooldown": 22.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 260,
		"count": 3,
		"damage": 26.0,
		"radius": 150.0,
		"duration": 12.0,
	},
	"decoy": {
		"name": "Effigy",
		"desc": "Something more interesting than you, for seven seconds. Then it goes off.",
		"icon": "icon_decoy",
		"sound": "decoy",
		"cooldown": 16.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 200,
		"duration": 7.0,
		"burst_damage": 60.0,
		"burst_radius": 200.0,
		"taunt_range": 620.0,
	},
	"surge": {
		"name": "Surge",
		"desc": "Nearly twice the speed for 3.5 seconds, and nothing to hide behind.",
		"icon": "icon_surge",
		"sound": "dash",
		"cooldown": 9.0,
		"charges": 1,
		"class": CLASS_MOVEMENT,
		"default": false,
		"essence": 170,
		"multiplier": 1.95,
		"duration": 3.5,
	},
	"vault": {
		"name": "Vault",
		"desc": "Leap to the cursor. Untouchable in the air, and the landing hurts.",
		"icon": "icon_vault",
		"sound": "dash",
		"cooldown": 7.0,
		"charges": 1,
		"class": CLASS_MOVEMENT,
		"default": false,
		"essence": 210,
		"distance": 380.0,
		"duration": 0.22,
		"damage": 45.0,
		"radius": 170.0,
		"knockback": 420.0,
	},
	"thornwall": {
		"name": "Thornwall",
		"desc": "Raise a barrier for 6 seconds. It stops slimes and their spit - and you.",
		"icon": "icon_thornwall",
		"sound": "shield",
		"cooldown": 15.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 190,
		"length": 260.0,
		"duration": 6.0,
	},
	"cinders": {
		"name": "Cinders",
		"desc": "The ground burns where you put it, and goes on burning.",
		"icon": "icon_cinders",
		"sound": "explosion",
		"cooldown": 13.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 230,
		"damage": 8.0,
		"interval": 0.25,
		"radius": 200.0,
		"duration": 5.0,
	},
}

## Movement first, then the general pool roughly by cost. This is the order the
## picker and the permanent-upgrade screen both display.
const ORDER: Array[String] = [
	"dash", "surge", "vault",
	"grenade", "nova", "shield", "heal", "lightning", "timeslow",
	"thornwall", "rapidfire", "cinders", "orbital", "decoy",
]


## Which def keys each ability upgrade kind scales.
##
## These live here, not in AbilityController, because two things need them and
## they must not disagree: the controller folds them into the numbers an
## ability uses, and the shop asks whether an upgrade would do anything at all
## before offering it. A "+30% damage" upgrade was on sale for Dash, which has
## no damage, because the producer and the consumer of that list were different
## code that never compared notes. One list, read by both.
const POWER_KEYS: Array[String] = ["damage", "burst_damage", "blast_damage"]
const AREA_KEYS: Array[String] = ["radius", "length", "jump_range",
	"orbit_radius", "burst_radius", "taunt_range"]


## AREA_KEYS plus the one that depends on what the ability does.
##
## `duration` means two different things in this table. On an ability that also
## has a `distance`, it is the TRAVEL TIME - Dash and Vault both fly at
## distance/duration - so stretching it covers the same ground more slowly
## while quietly handing out 25% more invulnerability, which is not what
## "+25% area" sells. Those scale their distance instead, so Widened actually
## makes the leap longer. Everywhere else, including Surge, `duration` is how
## long the effect lasts and is exactly the right thing to scale.
static func area_keys(id: String) -> Array[String]:
	var out := AREA_KEYS.duplicate()
	out.append("distance" if get_def(id).has("distance") else "duration")
	return out


## True if `id` has at least one of `keys` to scale. An upgrade that would
## multiply nothing is a dead purchase, and the shop uses this to stop
## selling one.
static func scales_any(id: String, keys: Array[String]) -> bool:
	var def := get_def(id)
	for key: String in keys:
		if def.has(key):
			return true
	return false


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["dash"])


## The class a slot index accepts.
static func class_for_slot(slot: int) -> String:
	if slot < 0 or slot >= SLOT_CLASSES.size():
		return CLASS_GENERAL
	return SLOT_CLASSES[slot]


static func ability_class(id: String) -> String:
	return String(get_def(id)["class"])


static func fits_slot(id: String, slot: int) -> bool:
	return DEFS.has(id) and ability_class(id) == class_for_slot(slot)


## Every id of one class, in ORDER. The picker uses this so a general slot is
## never offered a movement ability, or the other way round.
static func ids_of_class(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		if DEFS[id]["class"] == kind:
			out.append(id)
	return out


## What a slot falls back to when its saved id is missing or the wrong class.
## Deliberately class-correct: defaulting a general slot to Dash would quietly
## hand the player two movement abilities.
static func fallback_for_slot(slot: int) -> String:
	return "dash" if class_for_slot(slot) == CLASS_MOVEMENT else "grenade"


static func icon_path(id: String) -> String:
	return "res://assets/sprites/gen/%s.png" % get_def(id)["icon"]


static func default_unlocked() -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		if DEFS[id]["default"]:
			out.append(id)
	return out


static func locked_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		if not DEFS[id]["default"]:
			out.append(id)
	return out
