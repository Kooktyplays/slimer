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
const VIOLET := "violet"
const GREY := "grey"
const TEAL := "teal"
const PALE := "pale"
const BONE := "bone"
const RUST := "rust"
const UMBER := "umber"
const INDIGO := "indigo"

## Teaching order, and the array everything else iterates. A type missing from
## here is invisible to the spawner, the tutor and every count in the suite.
##
## Re-spaced when the roster went from ten to fourteen: the run ENDS at wave 25
## now, so four types appended above wave 20 would have been content almost
## nobody saw. All fourteen are unlocked by wave 20.
const ORDER: Array[String] = [GREEN, BLUE, RED, PURPLE, YELLOW, BONE, VIOLET,
	UMBER, ORANGE, TEAL, INDIGO, GREY, RUST, PALE]

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
		"hint": "They come straight at you, and that is all they do. Keep moving.",
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
		"hint": "Fast, and it wants your back. Do not let one get round you.",
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
		"hint": "It takes a lot and it gives a lot. Never let one corner you.",
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
		"unlock_wave": 8,
		"weight": 0.8,
		"hint": "It will not come to you. Close the gap, or put a tree between you.",
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
		"unlock_wave": 10,
		"weight": 0.55,
		"hint": "It is carrying more than the rest and it knows it. Hunt it first.",
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
		"hint": "It is going to go off. Make sure you are somewhere else when it does.",
		"blast_damage": 26.0,
		"blast_radius": 165.0,
		"fuse_range": 95.0,
		"fuse_time": 0.75,
	},
	# ---------------------------------------------------------------------
	# The adaptation pair. Everything above is chase-with-variations: whatever
	# you brought, you use it. These two are the first enemies that ask what
	# you brought and refuse half the answers.
	#
	# They only work as a pair. Either one alone punishes a single build; both
	# of them mean no loadout is safe, and a gun build and an ability build
	# each get a visible weakness they have to answer.
	# ---------------------------------------------------------------------
	VIOLET: {
		"name": "Warded",
		"behavior": "ward",
		"tint": Color(0.72, 0.60, 0.92),
		"hp": 64.0,
		"speed": 86.0,
		"contact_damage": 15.0,
		"threat": 2.8,
		"money": Vector2i(13, 20),
		"scale": 0.74,
		"radius": 34.0,
		"unlock_wave": 13,
		"weight": 0.6,
		"hint": "Abilities slide straight off this one. Shoot it.",
		# Permanent, and safe to make permanent: the player always has a gun.
		"immune_to": Combat.SOURCE_ABILITY,
		# It walks through your zoning in a straight line and does not flinch,
		# which is the behaviour half of "your cooldowns do not work here".
		"unflinching": true,
		# Tighter personal space than the pack default of 2.1, so a line of
		# them reads as a line rather than as one wide slime - but not zero,
		# which let them stack into a single sprite.
		"separation_scale": 1.3,
	},
	GREY: {
		"name": "Carapace",
		"behavior": "turtle",
		"tint": Color(0.55, 0.62, 0.55),
		"hp": 58.0,
		"speed": 78.0,
		"contact_damage": 17.0,
		"threat": 2.6,
		"money": Vector2i(13, 20),
		"scale": 0.78,
		"radius": 36.0,
		"unlock_wave": 18,
		"weight": 0.55,
		"hint": "While it is shelled, bullets go nowhere. Open it with an ability.",
		"immune_to": Combat.SOURCE_BULLET,
		# The shell CYCLES rather than being permanent, and that is a
		# deliberate departure from "bullets only".
		#
		# Ability damage is not guaranteed: a Surge/Barrier/Heal loadout deals
		# none at all, and a permanently bullet-proof enemy in that run can
		# never be killed - so the wave can never end. A cycling shell keeps
		# the intent (an ability deletes it, ignoring the shell entirely)
		# without the hang: a gun build can still kill it by shooting the open
		# window - which is exactly the adapting the pair exists to ask for.
		"shell_up": 2.2,
		"shell_down": 1.3,
	},
	# ---------------------------------------------------------------------
	# The two that go after something other than your health.
	# ---------------------------------------------------------------------
	TEAL: {
		"name": "Thief",
		"behavior": "thief",
		"tint": Color(0.20, 0.75, 0.70),
		"hp": 42.0,
		"speed": 190.0,
		"contact_damage": 3.0,       # it is not here to hurt you
		"threat": 2.0,
		"money": Vector2i(8, 13),
		"scale": 0.58,
		"radius": 27.0,
		"unlock_wave": 16,
		"weight": 0.6,
		"hint": "It takes what you have and runs. Catch it and you get it all back.",
		# The counterpart to the Hoarder: one hoards gold, one takes yours.
		"steal": Vector2i(28, 55),
		# Once it has your money it wants distance, so it reuses the skittish
		# flee steering rather than a second implementation of running away.
		"flee_range": 620.0,
		"separation_scale": 2.6,
		"hoards": true,              # drops its haul as a burst, like a Hoarder
	},
	PALE: {
		"name": "Mimic",
		"behavior": "mimic",
		"tint": Color(0.85, 0.80, 0.55),
		"hp": 70.0,
		"speed": 150.0,
		"contact_damage": 22.0,
		"threat": 2.5,
		"money": Vector2i(16, 24),
		"scale": 0.66,
		"radius": 30.0,
		"unlock_wave": 20,
		"weight": 0.5,
		"hint": "That was not a coin. Mimics wait on the ground - read what you pick up.",
		# Sits still wearing a pickup's sprite until you get close. Makes the
		# player read the ground, which is a whole layer of attention the game
		# did not previously use.
		"disguise_range": 150.0,
	},
	BONE: {
		"name": "Husk",
		"behavior": "husk",
		"tint": Color(0.86, 0.80, 0.70),
		"hp": 46.0, "speed": 102.0, "contact_damage": 7.0, "threat": 2.0,
		"money": Vector2i(9, 14), "scale": 0.62, "radius": 29.0,
		"unlock_wave": 11, "weight": 0.8,
		"hint": "Husks lie down when they run out. They get back up.",
		# husk-specific. It stays registered, visible and shootable while down -
		# finishing one off is the counterplay, and an untargetable corpse would
		# be a way for a wave never to end.
		"revive_delay": 2.6,
		"revive_fraction": 0.5,
	},
	UMBER: {
		"name": "Burrower",
		"behavior": "burrow",
		"tint": Color(0.55, 0.40, 0.22),
		"hp": 78.0, "speed": 124.0, "contact_damage": 9.0, "threat": 2.6,
		"money": Vector2i(12, 18), "scale": 0.66, "radius": 31.0,
		"unlock_wave": 14, "weight": 0.7,
		"hint": "Burrowers go under. Hold your shot until one surfaces.",
		# Cycles, like the Carapace's shell, and for the same reason: a
		# permanently untargetable enemy is a wave that can never end.
		"burrow_down": 1.9,
		"burrow_up": 2.4,
	},
	INDIGO: {
		"name": "Knot",
		"behavior": "knot",
		"tint": Color(0.32, 0.38, 0.86),
		"hp": 64.0, "speed": 96.0, "contact_damage": 8.0, "threat": 2.4,
		"money": Vector2i(11, 16), "scale": 0.64, "radius": 30.0,
		"unlock_wave": 17, "weight": 0.7,
		"hint": "Knots pair up. The line strung between them hurts to cross.",
		"tether_damage": 16.0,
		"tether_range": 620.0,
	},
	RUST: {
		"name": "Devourer",
		"behavior": "devour",
		"tint": Color(0.72, 0.26, 0.14),
		"hp": 120.0, "speed": 88.0, "contact_damage": 11.0, "threat": 3.0,
		"money": Vector2i(14, 20), "scale": 0.78, "radius": 37.0,
		"unlock_wave": 19, "weight": 0.6,
		"hint": "Devourers eat Thornwall and Cinders. Stop treating the ground "
			+ "as cover.",
		"eat_range": 130.0,
	},
}

## NOTE: "radius" is the hit radius in world pixels, already final - it is
## deliberately NOT scaled by "scale". Sizing the hitbox off the visual
## scale produced collision circles roughly half the drawn slime, so shots
## that visibly connected passed straight through.

## Elite modifiers layered on top of a base type once elites unlock.
## Three of these existed for the whole life of the game, which meant an elite
## at wave 40 was one of the same three things it was at wave 13. Elite mods are
## the cheapest variety in the codebase - a match arm and a table entry - so
## there is no good reason for the list to be short.
const ELITE_MODS := ["shielded", "enraged", "splitter",
	"volatile", "vampiric", "phasing", "warding"]

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
	"volatile": {
		"name": "Volatile",
		"desc": "detonates when it dies - kill it at range",
	},
	"vampiric": {
		"name": "Vampiric",
		"desc": "heals itself with every hit it lands on you",
	},
	"phasing": {
		"name": "Phasing",
		"desc": "flickers out of reach - time your shots",
	},
	"warding": {
		"name": "Warding",
		"desc": "shields nearby slimes from your abilities",
	},
}

## How far a Warding elite's aura reaches.
const WARD_AURA_RADIUS := 300.0


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[GREEN])


static func texture_path(id: String) -> String:
	return "res://assets/sprites/gen/enemy_%s_body.png" % id


static func badge_path(id: String) -> String:
	return "res://assets/sprites/gen/enemy_%s_badge.png" % id


static func crown_path(id: String) -> String:
	return "res://assets/sprites/gen/elite_crown_%s.png" % id


## Types legal for a given wave, respecting unlock gates.
##
## Nightmare ignores the gates entirely: Bloaters normally arrive at wave 15,
## and meeting one on wave 1 alongside everything else is most of what makes the
## mode different. The staggered roster is a teaching tool, and nightmare is for
## players who have already been taught.
static func unlocked_for_wave(wave: int, nightmare: bool = false) -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		if nightmare or wave >= int(DEFS[id]["unlock_wave"]):
			out.append(id)
	return out


## Spawn weights for a wave. Newly unlocked types get a temporary boost so the
## player meets them clearly instead of losing one in a crowd, and the basic
## green fades back as the roster fills out.
static func weights_for_wave(wave: int, nightmare: bool = false) -> Dictionary:
	var out := {}
	for id: String in unlocked_for_wave(wave, nightmare):
		var def: Dictionary = DEFS[id]
		var w: float = float(def["weight"])
		var since: int = wave - int(def["unlock_wave"])
		if since <= 2:
			w *= 2.2 - 0.4 * since       # spotlight the new arrival
		if id == GREEN:
			w *= maxf(0.35, 1.0 - 0.035 * wave)
		out[id] = maxf(w, 0.05)
	return out
