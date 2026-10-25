class_name ClassesDB
extends RefCounted
## The five characters, and the ultimates they have to earn.
##
## A class is layered ON TOP of the ability loadout, not instead of it: you pick
## a class and your three abilities. Nothing the Essence economy already sells
## is invalidated by this.
##
## Everything that varies together is declared together, for the same reason
## EnemyTypes declares colour and behaviour in one entry - a class that could
## half-exist (new passive, old ultimate) would read as a bug rather than as a
## character.
##
## The framing, from the story draft: **a class is who you were before you
## died.** That is why the ultimate has to be re-earned every run rather than
## owned - you have to remember yourself before you can be that person again -
## and it is why each one charges from doing what that person used to do.

# --- charge conditions -------------------------------------------------------
## Every one of these needs a match arm in RunState.add_ultimate_charge. The
## logic suite reads the arms out of the source and fails if a class names one
## that nothing implements, because a class whose ultimate never charges is a
## class that quietly does not work.
const CHARGE_ELITES := "elites"      ## elite and boss kills
## Damage dealt while surrounded.
##
## NOT damage taken, which is what this used to be and which rewards playing
## badly - the more you are hit, the sooner your reward. Overwatch charges
## ultimates from doing your job (damage dealt, healing done) and specifically
## refuses to charge tanks for blocking, for exactly this reason. The Warrior's
## job is to be in the middle of it and keep swinging, so that is what pays.
const CHARGE_BRAWL := "brawl"
const CHARGE_DEALT := "dealt"        ## damage dealt
const CHARGE_COMBO := "combo"        ## kills chained without being hit
const CHARGE_PICKUPS := "pickups"    ## things collected off the ground

const WARDEN := "warden"
const WARRIOR := "warrior"
const VAMPIRE := "vampire"
const ENGINEER := "engineer"
const HERBALIST := "herbalist"

## The Warrior leads because it is the one you start with. The rest are bought
## with Essence - see MetaDB - and the order is the order they are priced in, so
## the screen reads left to right as the roster opens up.
##
## DEFAULT must always be a class every player owns. It is what a save falls
## back to, and falling back to something locked would start a run as a
## character the player cannot use.
const ORDER: Array[String] = [WARRIOR, WARDEN, VAMPIRE, ENGINEER, HERBALIST]
const DEFAULT := WARRIOR


## The MetaDB unlock that grants `id`, or "" if it is free.
static func unlock_id(id: String) -> String:
	if id == DEFAULT:
		return ""
	return "cls_" + sanitise(id)


static func is_free(id: String) -> bool:
	return sanitise(id) == DEFAULT


## Essence price, or 0 for the free one.
static func cost(id: String) -> int:
	var key := unlock_id(id)
	if key.is_empty() or not MetaDB.DEFS.has(key):
		return 0
	return int(MetaDB.DEFS[key]["cost"])

const DEFS := {
	WARDEN: {
		"name": "The Warden",
		"title": "what the forest kept",
		"blurb": "You were one of them. The bosses are what you would have become.",
		"tint": Color(0.62, 0.86, 0.66),
		# Tougher and slower to anger. A warden outlasts things.
		"passive": {"stat": "max_hp", "kind": UpgradesDB.Kind.ADD, "amount": 25.0},
		"passive_text": "+25 max health.",
		"charge": CHARGE_ELITES,
		"charge_text": "Charges by killing elites and bosses.",
		"ultimate": "recall_the_wood",
		"ultimate_name": "Recall the Wood",
		"ultimate_text": "The forest remembers you. Roots erupt across the arena.",
	},
	WARRIOR: {
		"name": "The Warrior",
		"title": "died on their feet",
		"blurb": "Whatever killed you, it took a while. Get in the middle of it.",
		"tint": Color(0.92, 0.55, 0.42),
		"passive": {"stat": "damage_reduction", "kind": UpgradesDB.Kind.ADD,
			"amount": 0.10},
		"passive_text": "10% less damage taken.",
		"charge": CHARGE_BRAWL,
		"charge_text": "Charges by dealing damage while surrounded.",
		"ultimate": "last_stand",
		"ultimate_name": "Last Stand",
		"ultimate_text": "For a few seconds, what hits you comes back out.",
	},
	VAMPIRE: {
		"name": "The Vampire",
		"title": "was never alive here",
		"blurb": "The only thing in this forest that did not have to die to stay.",
		"tint": Color(0.85, 0.38, 0.52),
		"passive": {"stat": "lifesteal", "kind": UpgradesDB.Kind.ADD, "amount": 0.06},
		"passive_text": "6% of damage dealt comes back as health.",
		"charge": CHARGE_DEALT,
		"charge_text": "Charges by dealing damage.",
		"ultimate": "crimson_hour",
		"ultimate_name": "Crimson Hour",
		"ultimate_text": "Every hit heals, and every kill spreads to its neighbours.",
	},
	ENGINEER: {
		"name": "The Engineer",
		"title": "built something that outlasted them",
		"blurb": "The campfire at every rest was probably yours.",
		"tint": Color(0.95, 0.80, 0.35),
		# A real identity rather than a stat line. The Engineer is the only
		# class that puts something on the map and leaves it there.
		"passive": {"stat": "ability_cdr", "kind": UpgradesDB.Kind.ADD, "amount": 0.06},
		"passive_text": "Deploys automatic turrets. They inherit your gun upgrades.",
		"deploys_turrets": true,
		# The only class that reads the combo counter, which is what makes the
		# combo system worth having rather than decorative.
		"charge": CHARGE_COMBO,
		"charge_text": "Charges by chaining kills without being hit.",
		"ultimate": "overclock",
		"ultimate_name": "Overclock",
		"ultimate_text": "Your turrets fire far faster, reach further, and cannot be broken.",
	},
	HERBALIST: {
		"name": "The Herbalist",
		"title": "knew the forest before it turned",
		"blurb": "You used to come here on purpose.",
		"tint": Color(0.60, 0.82, 0.95),
		"passive": {"stat": "pickup_range_mul", "kind": UpgradesDB.Kind.MUL,
			"amount": 1.6},
		"passive_text": "Much wider pickup range.",
		"charge": CHARGE_PICKUPS,
		"charge_text": "Charges by collecting what the forest drops.",
		"ultimate": "bloom",
		"ultimate_name": "Bloom",
		"ultimate_text": "The ground itself turns on them.",
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT])


static func is_valid(id: String) -> bool:
	return DEFS.has(id)


## Sanitised: an unknown or empty id falls back to the default rather than
## erroring, so a save written before classes existed still loads.
static func sanitise(id: String) -> String:
	return id if DEFS.has(id) else DEFAULT


static func display_name(id: String) -> String:
	return String(get_def(id)["name"])


static func ultimate_id(id: String) -> String:
	return String(get_def(id)["ultimate"])


## Cosmetic variants. Two per class beyond the default.
##
## Skins exist because the Essence economy runs out of things to sell: once the
## abilities and passives are unlocked there is nothing left to want. Cosmetics
## extend that without adding power, which is the usual fix - and they cost
## almost nothing here, because the art is generated, so a skin is a tint and a
## mark rather than a drawing.
const SKIN_DEFAULT := "default"

const SKINS := {
	WARDEN: {
		"deeproot": {"name": "Deep Root", "cost": 260,
			"desc": "What was left after the forest finished with you."},
		"firstwatch": {"name": "First Watch", "cost": 380,
			"desc": "From before the wardens had anything to guard against."},
	},
	WARRIOR: {
		"ironclad": {"name": "Ironclad", "cost": 260,
			"desc": "You did not go quietly, and it shows."},
		"lastbreath": {"name": "Last Breath", "cost": 380,
			"desc": "The version of you that was still standing at the end."},
	},
	VAMPIRE: {
		"sated": {"name": "Sated", "cost": 260,
			"desc": "You have fed. It suits you."},
		"ashen": {"name": "Ashen", "cost": 380,
			"desc": "Too long without. Something is going out."},
	},
	ENGINEER: {
		"brassworks": {"name": "Brassworks", "cost": 260,
			"desc": "The good tools, the ones you kept for yourself."},
		"scrapheap": {"name": "Scrapheap", "cost": 380,
			"desc": "Everything since has been made of what was to hand."},
	},
	HERBALIST: {
		"bloomtide": {"name": "Bloomtide", "cost": 260,
			"desc": "The forest still recognises you, some days."},
		"nightshade": {"name": "Nightshade", "cost": 380,
			"desc": "You learned the other half of what grows here."},
	},
}


static func skins_for(class_id: String) -> Dictionary:
	return SKINS.get(sanitise(class_id), {})


static func skin_name(class_id: String, skin: String) -> String:
	if skin == SKIN_DEFAULT:
		return "Default"
	var d: Dictionary = skins_for(class_id).get(skin, {})
	return String(d.get("name", "Default"))


## An unknown skin falls back to the default rather than erroring, so a save
## naming a skin that was later renamed still loads.
static func sanitise_skin(class_id: String, skin: String) -> String:
	return skin if skins_for(class_id).has(skin) else SKIN_DEFAULT


static func sprite_path(id: String, skin: String = SKIN_DEFAULT) -> String:
	var cls := sanitise(id)
	var s := sanitise_skin(cls, skin)
	if s == SKIN_DEFAULT:
		return "res://assets/sprites/gen/player_%s.png" % cls
	return "res://assets/sprites/gen/player_%s_%s.png" % [cls, s]
