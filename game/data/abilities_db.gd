class_name AbilitiesDB
extends RefCounted
## The fifteen special abilities, in two classes.
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
		"desc": "Blink through enemies and bullets. Brief invulnerability.",
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
		"desc": "Lob an explosive at the cursor. Heavy area damage.",
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
		"desc": "A barrier absorbs the next 120 damage for 6 seconds.",
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
		"desc": "Slow every enemy and enemy bullet to 35% for 4 seconds.",
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
		"desc": "Detonate around yourself, damaging and flinging back everything near.",
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
		"desc": "Restore 35% of maximum health instantly.",
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
		"desc": "Chain lightning arcs between up to 7 nearby enemies.",
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
		"desc": "Triple fire rate and free reloads for 5 seconds.",
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
		"desc": "Three orbs circle you for 12 seconds, damaging what they touch.",
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
		"desc": "Drop a lure that pulls enemies for 7 seconds, then bursts.",
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
	"lifesteal": {
		"name": "Leech",
		"desc": "For 8 seconds, 18% of the damage you deal comes back as health.",
		"icon": "icon_lifesteal",
		"sound": "lifesteal",
		"cooldown": 24.0,
		"charges": 1,
		"class": CLASS_GENERAL,
		"default": false,
		"essence": 280,
		"fraction": 0.18,
		"duration": 8.0,
	},
	"surge": {
		"name": "Surge",
		"desc": "Sprint at nearly double speed for 3.5 seconds. No invulnerability.",
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
		"desc": "Set the ground alight at the cursor. Burns whatever stands in it.",
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
	"thornwall", "rapidfire", "cinders", "orbital", "decoy", "lifesteal",
]


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
