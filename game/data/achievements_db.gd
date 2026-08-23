class_name AchievementsDB
extends RefCounted
## Every achievement, declared in one table.
##
## Each entry owns its own unlock rule as a plain condition over the permanent
## stats in Save and the summary of the run that just ended. Keeping the rule
## beside the name is the same reasoning as EnemyTypes: a description and the
## thing it describes cannot drift apart if they are the same declaration.
##
## Ids are stable strings and are also what the Steam achievement config will
## key off, so renaming one silently revokes it for everyone who has it.

const KIND_PROGRESS := "progress"   ## accumulates over many runs
const KIND_FEAT := "feat"           ## done in a single run

## stat keys these read from Save.stats, beyond the ones that already existed
const BOSS_STAT_KEYS: Array[String] = [
	"boss_bramble", "boss_toad", "boss_wisp", "boss_oak", "boss_sovereign",
]

const DEFS := {
	# --- bosses -------------------------------------------------------------
	"first_blood": {
		"name": "First Blood",
		"desc": "Defeat any boss.",
		"icon": "icon_nova",
		"kind": KIND_PROGRESS,
	},
	"grove_tyrant": {
		"name": "Grove Tyrant",
		"desc": "Defeat a major boss.",
		"icon": "icon_heart",
		"kind": KIND_PROGRESS,
	},
	"clean_sweep": {
		"name": "Clean Sweep",
		"desc": "Defeat every boss in the forest at least once.",
		"icon": "icon_shield",
		"kind": KIND_PROGRESS,
	},

	# --- survival, normal ---------------------------------------------------
	"deep_woods": {
		"name": "Deep Woods",
		"desc": "Reach wave 20.",
		"icon": "icon_dash",
		"kind": KIND_FEAT,
	},
	"the_long_dark": {
		"name": "The Long Dark",
		"desc": "Survive 100 waves.",
		"icon": "icon_timeslow",
		"kind": KIND_FEAT,
	},

	# --- survival, nightmare ------------------------------------------------
	"no_gods": {
		"name": "No Gods, No Slimes",
		"desc": "Reach wave 40 on Nightmare.",
		"icon": "icon_rapidfire",
		"kind": KIND_FEAT,
	},
	"unmaker": {
		"name": "Unmaker",
		"desc": "Survive 100 waves on Nightmare.",
		"icon": "icon_lightning",
		"kind": KIND_FEAT,
	},

	# --- mastery ------------------------------------------------------------
	"pacifist_run": {
		"name": "Light Touch",
		"desc": "Reach wave 10 without buying a single upgrade.",
		"icon": "icon_ammo",
		"kind": KIND_FEAT,
	},
	"hoarder": {
		"name": "Hoarder Hoarder",
		"desc": "Earn 50,000 coins in total.",
		"icon": "icon_coin",
		"kind": KIND_PROGRESS,
	},
	"exterminator": {
		"name": "Exterminator",
		"desc": "Kill 10,000 slimes in total.",
		"icon": "icon_grenade",
		"kind": KIND_PROGRESS,
	},
}

## Declaration order, so the UI is stable regardless of Dictionary ordering.
const ORDER: Array[String] = [
	"first_blood", "grove_tyrant", "clean_sweep",
	"deep_woods", "the_long_dark", "no_gods", "unmaker",
	"pacifist_run", "hoarder", "exterminator",
]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func icon_path(id: String) -> String:
	var def := get_def(id)
	if def.is_empty():
		return ""
	return "res://assets/sprites/gen/%s.png" % def["icon"]


## Is `id` earned, given the permanent stats and the run that just ended?
##
## `summary` is RunState.summary() for a run that has just finished, or an empty
## dictionary when re-checking outside a run (loading a save, opening the menu).
## Progress achievements read stats and so resolve either way; feat achievements
## need the summary and simply stay unearned without one.
static func is_earned(id: String, stats: Dictionary, summary: Dictionary) -> bool:
	var wave := int(summary.get("wave", 0))
	var nightmare := bool(summary.get("nightmare", false))
	match id:
		"first_blood":
			return int(stats.get("minis_killed", 0)) + int(stats.get("majors_killed", 0)) > 0
		"grove_tyrant":
			return int(stats.get("majors_killed", 0)) > 0
		"clean_sweep":
			for key: String in BOSS_STAT_KEYS:
				if int(stats.get(key, 0)) <= 0:
					return false
			return true
		"deep_woods":
			return wave >= 20 or int(stats.get("best_wave", 0)) >= 20
		"the_long_dark":
			return wave >= 100 or int(stats.get("best_wave", 0)) >= 100
		"no_gods":
			return nightmare and wave >= 40
		"unmaker":
			return nightmare and wave >= 100
		"pacifist_run":
			return wave >= 10 and int(summary.get("upgrades_bought", -1)) == 0
		"hoarder":
			return int(stats.get("total_money", 0)) >= 50000
		"exterminator":
			return int(stats.get("total_kills", 0)) >= 10000
		_:
			return false
