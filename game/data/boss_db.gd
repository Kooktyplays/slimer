class_name BossDB
extends RefCounted
## Boss definitions.
##
## Five archetypes with genuinely different mechanics - not one boss with five
## HP values. Three minis rotate on the every-5th-wave slot, two majors rotate
## on every-20th. Because the run is endless, each repeat of an archetype
## comes back with an extra phase rather than just more health.
##
## Two rules hold this together, and both were once broken:
##
## 1. **Every boss owns a signature attack nobody else has.** Without one, all
##    five drew from a single shared pool of nine moves and no boss had a move
##    that was *its*.
##
## 2. **Phases replace, they do not append.** Every phase list used to be the
##    previous phase plus more entries, which meant a phase change altered how
##    *often* you were attacked and never how you fought. A later phase now
##    drops moves as it gains them, so the thing you learned in phase 1 stops
##    being the answer in phase 2.
##
## Both rules are asserted in the logic suite; a phase list that is a superset
## of the one before it is a test failure, not a style note.

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
		# phase -> the attacks available in it. Later phases REPLACE the
		# earlier ones rather than adding to them - see the note above.
		"phases": [
			# learn the two tells...
			["charge", "radial"],
			# ...then it stops using either and starts fencing you in
			["snare", "summon", "rain"],
			# the charge comes back, now aimed at you inside a ring
			["snare", "charge", "spiral"],
		],
		# this boss's, and nobody else's
		"signature": "snare",
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
			# drops both openers: now it drags you in and pushes you out
			["tongue", "shockwave", "summon"],
			# pull, then slam where you land - the two halves finally meet
			["tongue", "slam", "rain"],
		],
		# this boss's, and nobody else's
		"signature": "tongue",
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
			# one wisp becomes several, and the spiral stops
			["chorus", "aimed_volley", "summon"],
			["chorus", "blink_radial", "rain"],
		],
		# this boss's, and nobody else's
		"signature": "chorus",
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
			# the ground itself takes over; the ranged game stops
			["rootquake", "shockwave", "slam"],
			["rootquake", "spiral", "radial", "summon"],
			["rootquake", "charge", "slam", "rain"],
		],
		# this boss's, and nobody else's
		"signature": "rootquake",
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
			# it starts eating its own court: from here, adds are the fight
			["devour", "summon", "rain", "radial"],
			["devour", "summon", "shockwave", "charge"],
			["devour", "summon", "blink_radial", "slam", "spiral"],
		],
		# this boss's, and nobody else's
		"signature": "devour",
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
	# The finale is always the Sovereign, whatever the rotation would have
	# said. It is the thing the story is built towards, and a run that reached
	# its ending and found the Ancient Oak there would be a different game.
	if Game.is_finale_wave(wave):
		return {"id": Balance.FINALE_BOSS, "repeat": 0, "major": true,
			"finale": true}
	if Game.is_major_boss_wave(wave):
		var index := (wave / Balance.MAJOR_BOSS_EVERY) - 1
		return {
			"id": MAJOR_ROTATION[index % MAJOR_ROTATION.size()],
			"repeat": index / MAJOR_ROTATION.size(),
			"major": true,
		}
	# Minis skip the wave numbers the majors take - including the finale, which
	# used to be a mini wave. Without that last subtraction every mini after
	# wave 25 shifts one place along the rotation and the sequence the player
	# has been learning silently skips a boss.
	var mini_index := (wave / Balance.MINI_BOSS_EVERY) - 1 - (wave / Balance.MAJOR_BOSS_EVERY)
	if wave > Balance.FINALE_WAVE and Balance.FINALE_WAVE % Balance.MINI_BOSS_EVERY == 0 \
			and Balance.FINALE_WAVE % Balance.MAJOR_BOSS_EVERY != 0:
		mini_index -= 1
	return {
		"id": MINI_ROTATION[maxi(mini_index, 0) % MINI_ROTATION.size()],
		"repeat": maxi(mini_index, 0) / MINI_ROTATION.size(),
		"major": false,
	}


## The most phases any archetype can reach. The HUD builds that many bar
## segments up front so a boss never allocates mid-fight, and derives it from
## here so adding a fifth phase to a boss cannot leave the bar a segment short.
static func max_phases() -> int:
	var most := 1
	for id: String in DEFS:
		most = maxi(most, (DEFS[id]["phases"] as Array).size())
	return most


## Phase count grows with repeats, capped by the archetype's phase list.
static func phase_count(id: String, repeat: int) -> int:
	var def: Dictionary = DEFS[id]
	var base: int = 3 if bool(def["major"]) else 2
	return mini(base + repeat, (def["phases"] as Array).size())
