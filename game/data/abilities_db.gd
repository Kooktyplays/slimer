class_name AbilitiesDB
extends RefCounted
## The eleven special abilities. The player equips exactly two, so these are
## written to pull in different directions - escape, burst, control, sustain -
## rather than being straight upgrades of one another.

const DEFS := {
	"dash": {
		"name": "Dash",
		"desc": "Blink through enemies and bullets. Brief invulnerability.",
		"icon": "icon_dash",
		"sound": "dash",
		"cooldown": 3.2,
		"charges": 2,
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
		"default": false,
		"essence": 150,
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
		"default": false,
		"essence": 280,
		"fraction": 0.18,
		"duration": 8.0,
	},
}

const ORDER: Array[String] = [
	"dash", "grenade", "nova", "shield", "heal", "lightning",
	"timeslow", "rapidfire", "orbital", "decoy", "lifesteal",
]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["dash"])


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
