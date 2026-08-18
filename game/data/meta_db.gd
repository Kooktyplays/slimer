class_name MetaDB
extends RefCounted
## Permanent unlocks, bought with Essence between runs.
##
## Deliberately weighted towards *variety* over *power*: most of the cost sits
## in new abilities and new shop entries, which widen what a run can become.
## The flat passives are small on purpose - repeated runs should make the
## player more capable, not make wave 20 trivial.

const KIND_ABILITY := "ability"
const KIND_UPGRADE := "upgrade"
const KIND_PASSIVE := "passive"

const DEFS := {
	# ---- new abilities (cost mirrors AbilitiesDB.essence) -------------------
	"ab_shield":    {"kind": KIND_ABILITY, "ref": "shield",    "cost": 120},
	"ab_nova":      {"kind": KIND_ABILITY, "ref": "nova",      "cost": 150},
	"ab_heal":      {"kind": KIND_ABILITY, "ref": "heal",      "cost": 180},
	"ab_decoy":     {"kind": KIND_ABILITY, "ref": "decoy",     "cost": 200},
	"ab_timeslow":  {"kind": KIND_ABILITY, "ref": "timeslow",  "cost": 200},
	"ab_lightning": {"kind": KIND_ABILITY, "ref": "lightning", "cost": 220},
	"ab_rapidfire": {"kind": KIND_ABILITY, "ref": "rapidfire", "cost": 240},
	"ab_orbital":   {"kind": KIND_ABILITY, "ref": "orbital",   "cost": 260},
	"ab_lifesteal": {"kind": KIND_ABILITY, "ref": "lifesteal", "cost": 280},

	# ---- new shop entries --------------------------------------------------
	"upg_heavy_slugs": {
		"kind": KIND_UPGRADE, "cost": 140,
		"name": "Heavy Slugs", "desc": "Adds a big-damage option to the shop pool.",
	},
	"upg_runaway_sear": {
		"kind": KIND_UPGRADE, "cost": 160,
		"name": "Runaway Sear", "desc": "Adds a large fire-rate option to the shop pool.",
	},
	"upg_split_barrel": {
		"kind": KIND_UPGRADE, "cost": 260,
		"name": "Split Barrel", "desc": "Adds the +1 projectile option to the shop pool.",
	},
	"upg_thirsting_grip": {
		"kind": KIND_UPGRADE, "cost": 220,
		"name": "Thirsting Grip", "desc": "Adds a lifesteal option to the shop pool.",
	},
	"upg_deep_reserves": {
		"kind": KIND_UPGRADE, "cost": 240,
		"name": "Deep Reserves", "desc": "Adds an extra-ability-charge option to the shop.",
	},

	# ---- starting passives (small, stacking tiers) -------------------------
	"pas_vigor_1": {
		"kind": KIND_PASSIVE, "cost": 130, "stat": "max_hp", "amount": 10.0,
		"name": "Vigor I", "desc": "Start each run with +10 maximum health.",
	},
	"pas_vigor_2": {
		"kind": KIND_PASSIVE, "cost": 300, "stat": "max_hp", "amount": 12.0,
		"name": "Vigor II", "desc": "Another +12 maximum health.", "needs": "pas_vigor_1",
	},
	"pas_purse_1": {
		"kind": KIND_PASSIVE, "cost": 170, "stat": "start_money", "amount": 160.0,
		"name": "Seed Money", "desc": "Start each run with 160 coins.",
	},
	"pas_edge_1": {
		"kind": KIND_PASSIVE, "cost": 240, "stat": "gun.damage", "amount": 2.0,
		"name": "Honed Edge", "desc": "Start each run with +2 bullet damage.",
	},
	"pas_edge_2": {
		"kind": KIND_PASSIVE, "cost": 480, "stat": "gun.damage", "amount": 2.0,
		"name": "Honed Edge II", "desc": "Another +2 starting damage.", "needs": "pas_edge_1",
	},
	"pas_reserve": {
		"kind": KIND_PASSIVE, "cost": 340, "stat": "ability_extra_charges", "amount": 1.0,
		"name": "Second Wind", "desc": "Both abilities start with +1 charge.",
	},
	"pas_attune": {
		"kind": KIND_PASSIVE, "cost": 280, "stat": "essence_mul", "amount": 0.25,
		"name": "Attunement", "desc": "+25% Essence earned from every run.",
	},
	"pas_haggle": {
		"kind": KIND_PASSIVE, "cost": 260, "stat": "free_rerolls", "amount": 1.0,
		"name": "Haggler", "desc": "One free shop reroll each visit.",
	},
}

const ORDER: Array[String] = [
	"ab_shield", "ab_nova", "ab_heal", "ab_decoy", "ab_timeslow",
	"ab_lightning", "ab_rapidfire", "ab_orbital", "ab_lifesteal",
	"upg_heavy_slugs", "upg_runaway_sear", "upg_split_barrel",
	"upg_thirsting_grip", "upg_deep_reserves",
	"pas_vigor_1", "pas_vigor_2", "pas_purse_1", "pas_edge_1", "pas_edge_2",
	"pas_reserve", "pas_attune", "pas_haggle",
]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


static func display_name(id: String) -> String:
	var def: Dictionary = DEFS[id]
	if def["kind"] == KIND_ABILITY:
		return AbilitiesDB.get_def(def["ref"])["name"]
	return def["name"]


static func description(id: String) -> String:
	var def: Dictionary = DEFS[id]
	if def["kind"] == KIND_ABILITY:
		return AbilitiesDB.get_def(def["ref"])["desc"]
	return def["desc"]


static func icon_path(id: String) -> String:
	var def: Dictionary = DEFS[id]
	if def["kind"] == KIND_ABILITY:
		return AbilitiesDB.icon_path(def["ref"])
	if def["kind"] == KIND_UPGRADE:
		return "res://assets/sprites/gen/icon_ammo.png"
	return "res://assets/sprites/gen/icon_heart.png"


## Prerequisite met? Tiered passives gate behind their earlier tier.
static func requirement_met(id: String, unlocked: Array) -> bool:
	var need: Variant = DEFS[id].get("needs")
	return need == null or unlocked.has(need)
