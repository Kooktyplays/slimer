extends Node
## Permanent progression and settings, persisted to user://slimer_save.json.
##
## Writes go to a temp file and are then renamed over the real one, so a crash
## mid-write leaves the previous save intact rather than a truncated file.

const PATH := "user://slimer_save.json"
const TMP_PATH := "user://slimer_save.json.tmp"
## Version 3 added per-boss kill counters and the earned-achievement list. Both
## are additive - a version-2 save loads with the counters at zero and simply has
## not earned the achievements depending on them, which is the right answer for a
## save from before they were tracked.
const VERSION := 3

## Bumped when the *meaning* of an ability binding changes, not when a binding
## is added. Version 2 introduced the movement slot: it moved Space from
## ability_1 to ability_movement and split Shift and E across the two general
## slots. A version-1 save still binds ability_1 to Space, which would leave two
## actions on the same key and fire two slots at once - so those overrides are
## dropped on load and fall back to the new defaults.
const ABILITY_BIND_VERSION := 2
const _VERSIONED_ABILITY_ACTIONS: Array[String] = [
	"ability_movement", "ability_1", "ability_2",
]

var essence: int = 0
var unlocks: Array[String] = []
var loadout: Array[String] = ["dash", "grenade", "nova"]
var seen_hints: Array[String] = []
var stats := {
	"runs": 0,
	"best_wave": 0,
	"best_wave_nightmare": 0,
	"total_kills": 0,
	"total_money": 0,
	"minis_killed": 0,
	"majors_killed": 0,
	# one counter per boss, so "beat every boss" is answerable
	"boss_bramble": 0,
	"boss_toad": 0,
	"boss_wisp": 0,
	"boss_oak": 0,
	"boss_sovereign": 0,
}
## Achievement ids the player has earned. Never revoked once given.
var achievements: Array[String] = []
## action -> array of serialised bindings. Only actions the player actually
## rebound are stored; anything absent falls back to InputBinds.DEFAULTS.
var keybinds: Dictionary = {}
var settings := {
	"master_volume": 0.9,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"screen_shake": 1.0,
	"damage_numbers": true,
	"show_hints": true,
}

## Set by tests and the sim harness so they never touch the real save file.
var disable_writes: bool = false


func _ready() -> void:
	load_game()
	# Grant retroactively on load, so an achievement added in a later build goes
	# to a player who already met its condition instead of asking them to do it
	# again. Progress achievements read stats, which survive; feat achievements
	# need a run summary and simply stay unearned here.
	check_achievements()
	# Bindings have to reach the InputMap before anything reads input. Save is
	# the second autoload, so this runs before Main or any scene exists.
	InputBinds.apply(keybinds)


# --------------------------------------------------------------------------
# persistence
# --------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"essence": essence,
		"unlocks": unlocks,
		"loadout": loadout,
		"seen_hints": seen_hints,
		"stats": stats,
		"settings": settings,
		"keybinds": keybinds,
		"achievements": achievements,
	}


func from_dict(d: Dictionary) -> void:
	essence = int(d.get("essence", 0))
	unlocks = _to_string_array(d.get("unlocks", []))
	seen_hints = _to_string_array(d.get("seen_hints", []))
	achievements = _to_string_array(d.get("achievements", []))

	var lo := _to_string_array(d.get("loadout", ["dash", "grenade", "nova"]))
	loadout = _sanitise_loadout(lo)

	keybinds = _parse_keybinds(d.get("keybinds", {}))
	if int(d.get("version", 1)) < ABILITY_BIND_VERSION:
		for action: String in _VERSIONED_ABILITY_ACTIONS:
			keybinds.erase(action)

	for k: String in stats:
		if d.get("stats", {}).has(k):
			stats[k] = int(d["stats"][k])
	for k: String in settings:
		if d.get("settings", {}).has(k):
			var v: Variant = d["settings"][k]
			settings[k] = bool(v) if settings[k] is bool else float(v)


func load_game() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Slimer: could not open save file, starting fresh.")
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		push_warning("Slimer: save file is corrupt, starting fresh.")
		return false
	from_dict(parsed)
	return true


func save_game() -> bool:
	if disable_writes:
		return true
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Slimer: could not write save file.")
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	# rename over the target so the real file is never half-written
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TMP_PATH),
		ProjectSettings.globalize_path(PATH))
	if err != OK:
		push_warning("Slimer: save rename failed (%d)." % err)
		return false
	return true


func reset() -> void:
	essence = 0
	unlocks = []
	loadout = ["dash", "grenade", "nova"]
	seen_hints = []
	achievements = []
	keybinds.clear()
	InputBinds.apply(keybinds)
	for k: String in stats:
		stats[k] = 0
	save_game()


# --------------------------------------------------------------------------
# unlocks
# --------------------------------------------------------------------------
func is_unlocked(id: String) -> bool:
	return unlocks.has(id)


func can_afford(id: String) -> bool:
	return MetaDB.DEFS.has(id) and essence >= int(MetaDB.DEFS[id]["cost"])


func can_purchase(id: String) -> bool:
	return (MetaDB.DEFS.has(id)
		and not is_unlocked(id)
		and MetaDB.requirement_met(id, unlocks)
		and can_afford(id))


func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false
	essence -= int(MetaDB.DEFS[id]["cost"])
	unlocks.append(id)
	save_game()
	Events.unlock_granted.emit(MetaDB.DEFS[id]["kind"], id)
	Events.essence_changed.emit(essence, -int(MetaDB.DEFS[id]["cost"]))
	return true


func add_essence(amount: int) -> void:
	essence += amount
	Events.essence_changed.emit(essence, amount)


## Abilities the player is allowed to equip: the defaults plus anything unlocked
## with Essence.
func unlocked_abilities() -> Array[String]:
	var out: Array[String] = AbilitiesDB.default_unlocked()
	for id: String in unlocks:
		var def: Variant = MetaDB.DEFS.get(id)
		if def != null and def["kind"] == MetaDB.KIND_ABILITY:
			var ref: String = def["ref"]
			if not out.has(ref):
				out.append(ref)
	return out


## Abilities that may legally go in a given slot: unlocked, and of that slot's
## class. Slot 0 is the movement slot and will not take a general ability.
func unlocked_for_slot(slot: int) -> Array[String]:
	var owned := unlocked_abilities()
	var out: Array[String] = []
	# Walk the class list rather than the unlock list, so the picker's grid stays
	# in ORDER regardless of the sequence things were bought in.
	for id: String in AbilitiesDB.ids_of_class(AbilitiesDB.class_for_slot(slot)):
		if owned.has(id):
			out.append(id)
	return out


func set_loadout(slot: int, ability_id: String) -> void:
	if slot < 0 or slot >= AbilitiesDB.SLOT_COUNT:
		return
	if not unlocked_abilities().has(ability_id):
		return
	# A movement ability cannot be put in a general slot, or the reverse - the
	# classes are the whole point of having a separate movement slot.
	if not AbilitiesDB.fits_slot(ability_id, slot):
		return
	# Slots must hold different abilities. Swap with whichever slot already has
	# this one rather than duplicating it; only a same-class slot can be holding
	# it, so the swap is always legal.
	for other in range(loadout.size()):
		if other != slot and loadout[other] == ability_id:
			loadout[other] = loadout[slot]
			break
	loadout[slot] = ability_id
	save_game()
	Events.ability_equipped.emit(slot, ability_id)


# --------------------------------------------------------------------------
# run bookkeeping
# --------------------------------------------------------------------------
func record_run(summary: Dictionary, essence_gained: int) -> bool:
	stats["runs"] = int(stats["runs"]) + 1
	stats["total_kills"] = int(stats["total_kills"]) + int(summary.get("kills", 0))
	stats["total_money"] = int(stats["total_money"]) + int(summary.get("money_earned", 0))
	stats["minis_killed"] = int(stats["minis_killed"]) + int(summary.get("minis", 0))
	stats["majors_killed"] = int(stats["majors_killed"]) + int(summary.get("majors", 0))
	var wave := int(summary.get("wave", 0))
	var is_best := wave > int(stats["best_wave"])
	if is_best:
		stats["best_wave"] = wave
	if bool(summary.get("nightmare", false)) \
			and wave > int(stats["best_wave_nightmare"]):
		stats["best_wave_nightmare"] = wave
	add_essence(essence_gained)
	check_achievements(summary)
	save_game()
	return is_best


## Record that a particular boss was beaten, so "defeat every boss" is
## answerable. Called by the boss controller rather than inferred from the run
## summary, which only counts minis and majors in aggregate.
func record_boss_kill(boss_id: String) -> void:
	var key := "boss_%s" % boss_id
	if not stats.has(key):
		return
	stats[key] = int(stats[key]) + 1


## Grant anything newly earned, and announce it.
##
## Run on every run end and also on load, so an achievement added in a later
## build is granted retroactively to a player who already met its condition
## rather than requiring them to do it again.
func check_achievements(summary: Dictionary = {}) -> Array[String]:
	var granted: Array[String] = []
	for id: String in AchievementsDB.ORDER:
		if achievements.has(id):
			continue
		if not AchievementsDB.is_earned(id, stats, summary):
			continue
		achievements.append(id)
		granted.append(id)
		Events.achievement_unlocked.emit(id)
	return granted


func has_achievement(id: String) -> bool:
	return achievements.has(id)


func has_seen_hint(id: String) -> bool:
	return seen_hints.has(id)


func mark_hint_seen(id: String) -> void:
	if seen_hints.has(id):
		return
	seen_hints.append(id)
	save_game()


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
## Keep only entries that name a real action and deserialise to a real event.
## A save edited by hand, or written by an older build, must not be able to
## leave the player with an unusable control scheme.
func _parse_keybinds(v: Variant) -> Dictionary:
	var out := {}
	if v is not Dictionary:
		return out
	for action: Variant in (v as Dictionary):
		var name := str(action)
		if not InputBinds.DEFAULTS.has(name):
			continue
		var raw: Variant = (v as Dictionary)[action]
		if raw is not Array:
			continue
		var events: Array = []
		for entry: Variant in (raw as Array):
			if entry is Dictionary and InputBinds.deserialize(entry) != null:
				events.append(entry)
		if not events.is_empty():
			out[name] = events
	return out


## Rebind an action, then persist and apply immediately.
func set_keybind(action: String, events: Array) -> void:
	if not InputBinds.DEFAULTS.has(action):
		return
	if events.is_empty():
		keybinds.erase(action)
	else:
		keybinds[action] = events
	InputBinds.apply(keybinds)
	save_game()


func reset_keybinds() -> void:
	keybinds.clear()
	InputBinds.apply(keybinds)
	save_game()


func _to_string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in v:
			out.append(str(item))
	return out


## Guarantee one distinct, unlocked, class-correct ability per slot.
##
## Slot-by-slot rather than as a flat list, because a saved loadout from before
## the movement slot existed can be the right length but the wrong shape, and
## padding a general slot with Dash would hand the player two movement
## abilities.
func _sanitise_loadout(candidate: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for slot in range(AbilitiesDB.SLOT_COUNT):
		var allowed := unlocked_for_slot(slot)
		var pick := ""
		# Prefer what the save already had, wherever it sat, as long as it fits
		# this slot and is not already spoken for.
		for id: String in candidate:
			if allowed.has(id) and not out.has(id):
				pick = id
				break
		if pick == "":
			for id: String in allowed:
				if not out.has(id):
					pick = id
					break
		if pick == "":
			pick = AbilitiesDB.fallback_for_slot(slot)
		out.append(pick)
	return out
