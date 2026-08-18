class_name BossDB
extends RefCounted
## Boss definitions.
##
## Five archetypes with genuinely different mechanics - not one boss with five
## HP values. Three minis rotate on the every-5th-wave slot, two majors rotate
## on every-20th. Because the run is endless, each repeat of an archetype
## comes back with an extra phase and a wider attack list rather than just
## more health.

const MINI_ROTATION: Array[String] = ["bramble", "toad", "wisp"]
const MAJOR_ROTATION: Array[String] = ["oak", "sovereign"]

## "radius" is the final hit radius in world pixels, not scaled by "scale".
const DEFS := {
	"bramble": {
		"name": "Bramble Warden",
		"title": "Warden of the Thicket",
		"body": "res://assets/sprites/gen/boss_bramble_body.png",
		"eyes": "res://assets/sprites/gen/boss_bramble_eyes.png",
		"eye_offset": Vector2(0, -22),
		"major": false,
		"scale": 1.75,
		"radius": 110.0,
		"speed": 92.0,
		"contact_damage": 22.0,
		"tint": Color(0.60, 0.44, 0.28),
		# phase -> attacks available. Later phases keep the earlier ones.
		"phases": [
			["charge", "radial"],
			["charge", "radial", "summon", "rain"],
			["charge", "radial", "summon", "rain", "spiral"],
		],
		"summon_types": ["green", "green", "blue"],
		"summon_count": 3,
		"projectile": "res://assets/sprites/gen/thorn.png",
		"attack_interval": Vector2(2.1, 3.2),
	},
	"toad": {
		"name": "The Toadfather",
		"title": "Glutton of the Mire",
		"body": "res://assets/sprites/gen/boss_toad_body.png",
		"eyes": "res://assets/sprites/gen/boss_toad_eyes.png",
		"eye_offset": Vector2(0, -46),
		"major": false,
		"scale": 1.7,
		"radius": 130.0,
		"speed": 64.0,
		"contact_damage": 26.0,
		"tint": Color(0.30, 0.62, 0.28),
		"phases": [
			["slam", "aimed_volley"],
			["slam", "aimed_volley", "summon", "shockwave"],
			["slam", "aimed_volley", "summon", "shockwave", "rain"],
		],
		"summon_types": ["green", "orange"],
		"summon_count": 4,
		"projectile": "res://assets/sprites/gen/orb.png",
		"attack_interval": Vector2(2.4, 3.4),
	},
	"wisp": {
		"name": "The Wisp Choir",
		"title": "Voices in the Dark",
		"body": "res://assets/sprites/gen/boss_wisp_body.png",
		"eyes": "res://assets/sprites/gen/boss_wisp_eyes.png",
		"eye_offset": Vector2(0, -8),
		"major": false,
		"scale": 1.8,
		"radius": 95.0,
		"speed": 128.0,
		"contact_damage": 16.0,
		"tint": Color(0.57, 0.40, 0.92),
		"phases": [
			["spiral", "blink_radial"],
			["spiral", "blink_radial", "aimed_volley", "summon"],
			["spiral", "blink_radial", "aimed_volley", "summon", "rain"],
		],
		"summon_types": ["purple", "blue"],
		"summon_count": 3,
		"projectile": "res://assets/sprites/gen/orb.png",
		"attack_interval": Vector2(1.9, 2.8),
		"floats": true,
	},
	"oak": {
		"name": "The Ancient Oak",
		"title": "First Root of the Deep Wood",
		"body": "res://assets/sprites/gen/boss_oak_body.png",
		"eyes": "res://assets/sprites/gen/boss_oak_eyes.png",
		"eye_offset": Vector2(0, -74),
		"major": true,
		"scale": 2.15,
		"radius": 150.0,
		"speed": 52.0,
		"contact_damage": 34.0,
		"tint": Color(0.42, 0.34, 0.22),
		"phases": [
			["rain", "radial", "summon"],
			["rain", "radial", "summon", "shockwave", "slam"],
			["rain", "radial", "summon", "shockwave", "slam", "spiral"],
			["rain", "radial", "summon", "shockwave", "slam", "spiral", "charge"],
		],
		"summon_types": ["green", "red", "purple"],
		"summon_count": 5,
		"projectile": "res://assets/sprites/gen/thorn.png",
		"attack_interval": Vector2(1.7, 2.6),
	},
	"sovereign": {
		"name": "The Slime Sovereign",
		"title": "Crowned Devourer",
		"body": "res://assets/sprites/gen/boss_sovereign_body.png",
		"eyes": "res://assets/sprites/gen/boss_sovereign_eyes.png",
		"eye_offset": Vector2(0, -62),
		"major": true,
		"scale": 2.2,
		"radius": 190.0,
		"speed": 76.0,
		"contact_damage": 36.0,
		"tint": Color(0.57, 0.40, 0.92),
		"phases": [
			["slam", "spiral", "summon"],
			["slam", "spiral", "summon", "rain", "radial"],
			["slam", "spiral", "summon", "rain", "radial", "shockwave", "charge"],
			["slam", "spiral", "summon", "rain", "radial", "shockwave", "charge", "blink_radial"],
		],
		"summon_types": ["green", "blue", "red", "yellow"],
		"summon_count": 6,
		"summon_elite": true,
		"projectile": "res://assets/sprites/gen/boss_orb.png",
		"attack_interval": Vector2(1.5, 2.3),
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


## Which boss shows up on `wave`, and how many times it has appeared before.
## The repeat count drives the extra phase on later encounters.
static func for_wave(wave: int) -> Dictionary:
	if Game.is_major_boss_wave(wave):
		var index := (wave / Balance.MAJOR_BOSS_EVERY) - 1
		return {
			"id": MAJOR_ROTATION[index % MAJOR_ROTATION.size()],
			"repeat": index / MAJOR_ROTATION.size(),
			"major": true,
		}
	# minis skip the wave numbers the majors take
	var mini_index := (wave / Balance.MINI_BOSS_EVERY) - 1 - (wave / Balance.MAJOR_BOSS_EVERY)
	return {
		"id": MINI_ROTATION[maxi(mini_index, 0) % MINI_ROTATION.size()],
		"repeat": maxi(mini_index, 0) / MINI_ROTATION.size(),
		"major": false,
	}


## Phase count grows with repeats, capped by the archetype's phase list.
static func phase_count(id: String, repeat: int) -> int:
	var def: Dictionary = DEFS[id]
	var base: int = 3 if bool(def["major"]) else 2
	return mini(base + repeat, (def["phases"] as Array).size())
