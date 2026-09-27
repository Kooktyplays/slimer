class_name MetaDB
extends RefCounted
## Permanent unlocks, bought with Essence between runs.
##
## Deliberately weighted towards *variety* over *power*: most of the cost sits
## in new abilities and new shop entries, which widen what a run can become.
## The flat passives are small on purpose - repeated runs should make the
## player more capable, not make wave 20 trivial.

const KIND_CLASS := "class"
const KIND_ABILITY := "ability"
const KIND_UPGRADE := "upgrade"
const KIND_PASSIVE := "passive"

const DEFS := {
	# ---- characters --------------------------------------------------------
	#
	# The Warrior is free and is not listed here - a game where the first
	# decision costs something you do not have yet is a game with no first
	# decision. The other four are the biggest thing Essence buys, which is
	# what the economy was missing: everything else it sold was small.
	#
	# `ref` is the ClassesDB id. Priced above the dearest ability (280) because
	# a character is a larger thing than an ability, and ascending so the
	# roster opens up over several runs rather than all at once.
	"cls_warden":    {"kind": KIND_CLASS, "ref": "warden",    "cost": 350},
	"cls_vampire":   {"kind": KIND_CLASS, "ref": "vampire",   "cost": 450},
	"cls_engineer":  {"kind": KIND_CLASS, "ref": "engineer",  "cost": 550},
	"cls_herbalist": {"kind": KIND_CLASS, "ref": "herbalist", "cost": 650},

	# ---- new abilities (cost mirrors AbilitiesDB.essence) -------------------
	"ab_surge":     {"kind": KIND_ABILITY, "ref": "surge",     "cost": 170},
	"ab_vault":     {"kind": KIND_ABILITY, "ref": "vault",     "cost": 210},
	"ab_shield":    {"kind": KIND_ABILITY, "ref": "shield",    "cost": 120},
	"ab_heal":      {"kind": KIND_ABILITY, "ref": "heal",      "cost": 180},
	"ab_decoy":     {"kind": KIND_ABILITY, "ref": "decoy",     "cost": 200},
	"ab_timeslow":  {"kind": KIND_ABILITY, "ref": "timeslow",  "cost": 200},
	"ab_lightning": {"kind": KIND_ABILITY, "ref": "lightning", "cost": 220},
	"ab_rapidfire": {"kind": KIND_ABILITY, "ref": "rapidfire", "cost": 240},
	"ab_orbital":   {"kind": KIND_ABILITY, "ref": "orbital",   "cost": 260},
	"ab_thornwall": {"kind": KIND_ABILITY, "ref": "thornwall", "cost": 190},
	"ab_cinders":   {"kind": KIND_ABILITY, "ref": "cinders",   "cost": 230},

	# ---- new shop entries --------------------------------------------------
	"upg_heavy_slugs": {
		"kind": KIND_UPGRADE, "cost": 140,
		"name": "Heavy Slugs", "desc": "The rest starts carrying slugs. Slower, and they go through things.",
	},
	"upg_runaway_sear": {
		"kind": KIND_UPGRADE, "cost": 160,
		"name": "Runaway Sear", "desc": "The rest starts carrying a barrel that will not stop. You will run dry.",
	},
	"upg_split_barrel": {
		"kind": KIND_UPGRADE, "cost": 260,
		"name": "Split Barrel", "desc": "The rest starts carrying a second barrel. Every shot is two.",
	},
	"upg_thirsting_grip": {
		"kind": KIND_UPGRADE, "cost": 220,
		"name": "Thirsting Grip", "desc": "The rest starts carrying a grip that takes something back from the kill.",
	},
	"upg_deep_reserves": {
		"kind": KIND_UPGRADE, "cost": 240,
		"name": "Deep Reserves", "desc": "The rest starts carrying one more use of whatever you brought.",
	},

	# ---- starting passives (small, stacking tiers) -------------------------
	"pas_vigor_1": {
		"kind": KIND_PASSIVE, "cost": 130, "stat": "max_hp", "amount": 10.0,
		"name": "Vigor I", "desc": "You arrive harder to finish. Ten more.",
	},
	"pas_vigor_2": {
		"kind": KIND_PASSIVE, "cost": 300, "stat": "max_hp", "amount": 12.0,
		"name": "Vigor II", "desc": "Harder again. Twelve more on top.", "needs": "pas_vigor_1",
	},
	"pas_purse_1": {
		"kind": KIND_PASSIVE, "cost": 170, "stat": "start_money", "amount": 160.0,
		"name": "Seed Money", "desc": "You arrive with 160 coins already in hand.",
	},
	"pas_edge_1": {
		"kind": KIND_PASSIVE, "cost": 240, "stat": "gun.damage", "amount": 2.0,
		"name": "Honed Edge", "desc": "Whatever you came in with is sharper. Two more.",
	},
	"pas_edge_2": {
		"kind": KIND_PASSIVE, "cost": 480, "stat": "gun.damage", "amount": 2.0,
		"name": "Honed Edge II", "desc": "Sharper still. Two more again.", "needs": "pas_edge_1",
	},
	"pas_reserve": {
		"kind": KIND_PASSIVE, "cost": 340, "stat": "ability_extra_charges", "amount": 1.0,
		"name": "Second Wind", "desc": "Everything you bring arrives with one more use in it.",
	},
	"pas_attune": {
		"kind": KIND_PASSIVE, "cost": 280, "stat": "essence_mul", "amount": 0.25,
		"name": "Attunement", "desc": "The forest gives up a quarter more of itself to you.",
	},
	"pas_haggle": {
		"kind": KIND_PASSIVE, "cost": 260, "stat": "free_rerolls", "amount": 1.0,
		"name": "Haggler", "desc": "One look at different stock, free, at every rest.",
	},
}

const ORDER: Array[String] = [
	"ab_surge", "ab_vault",
	"ab_shield", "ab_heal", "ab_thornwall", "ab_decoy",
	"ab_timeslow", "ab_lightning", "ab_cinders", "ab_rapidfire",
	"cls_warden", "cls_vampire", "cls_engineer", "cls_herbalist",
	"ab_orbital",
	"upg_heavy_slugs", "upg_runaway_sear", "upg_split_barrel",
	"upg_thirsting_grip", "upg_deep_reserves",
	"pas_vigor_1", "pas_vigor_2", "pas_purse_1", "pas_edge_1", "pas_edge_2",
	"pas_reserve", "pas_attune", "pas_haggle",
]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


## Names and descriptions for the ref-based kinds come from the table that owns
## the thing, so an ability or a character described in two places cannot drift
## into describing itself differently.
static func display_name(id: String) -> String:
	var def: Dictionary = DEFS[id]
	match def["kind"]:
		KIND_ABILITY:
			return AbilitiesDB.get_def(def["ref"])["name"]
		KIND_CLASS:
			return ClassesDB.display_name(def["ref"])
	return def["name"]


static func description(id: String) -> String:
	var def: Dictionary = DEFS[id]
	match def["kind"]:
		KIND_ABILITY:
			return AbilitiesDB.get_def(def["ref"])["desc"]
		KIND_CLASS:
			var cls := ClassesDB.get_def(def["ref"])
			return "%s  %s" % [cls["passive_text"], cls["charge_text"]]
	return def["desc"]


static func icon_path(id: String) -> String:
	var def: Dictionary = DEFS[id]
	if def["kind"] == KIND_ABILITY:
		return AbilitiesDB.icon_path(def["ref"])
	if def["kind"] == KIND_CLASS:
		# the character's own sprite, so the row shows who you are buying
		return ClassesDB.sprite_path(def["ref"])
	if def["kind"] == KIND_UPGRADE:
		return "res://assets/sprites/gen/icon_ammo.png"
	return "res://assets/sprites/gen/icon_heart.png"


## Prerequisite met? Tiered passives gate behind their earlier tier.
static func requirement_met(id: String, unlocked: Array) -> bool:
	var need: Variant = DEFS[id].get("needs")
	return need == null or unlocked.has(need)
