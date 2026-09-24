class_name RunState
extends RefCounted
## Everything that dies with the player.
##
## Nothing here is persisted. Permanent unlocks live in Save and are applied
## *into* a fresh RunState at the start of a run, which keeps the "death resets
## the run" rule impossible to get wrong: we simply throw this object away.

var seed_value: int = 0
var wave: int = 0
var money: int = 0
## Nightmare difficulty, chosen before the run and fixed for its lifetime.
var nightmare: bool = false
## Which character this run is. Sanitised on creation, so a save from before
## classes existed loads as the default rather than erroring.
var class_id: String = "warden"

## Ultimate charge, 0..1. Earned by doing what this class used to do - see the
## charge conditions in ClassesDB. Clamped at both ends: the HUD reads it as a
## fraction and an ultimate that could charge past full would show a meter
## that lies.
var ultimate_charge: float = 0.0
var ultimates_used: int = 0

# gun stats, copied from Balance.GUN_BASE then mutated by upgrades
var gun: Dictionary = {}

# run-wide modifiers
var max_hp: float = Balance.PLAYER_MAX_HP
var hp: float = Balance.PLAYER_MAX_HP
var damage_reduction: float = 0.0
var move_speed_mul: float = 1.0
var pickup_range_mul: float = 1.0
var ability_cdr: float = 0.0
var ability_extra_charges: int = 0
var lifesteal: float = 0.0
var money_mul: float = 1.0
var free_rerolls: int = 0
## Class-upgrade stats. `ultimate_rate` scales how fast charge accrues,
## `ultimate_power` how long an ultimate lasts. Both live here rather than on
## the class so a run can buy into them.
var ultimate_rate: float = 1.0
var ultimate_power: float = 1.0

## Per-ability upgrade counts: ability id -> {kind -> times bought}.
##
## This is what makes the locked loadout a commitment rather than a
## restriction. You can no longer fix a bad pick at the shop, so investing in a
## good one has to be possible.
var ability_levels: Dictionary = {}

## True once the finale has been beaten in this run. The ending shows once -
## a player who chose to continue and then reaches the Sovereign again on its
## own rotation slot should not be told they have won a second time.
var finale_cleared: bool = false

# loadout
var abilities: Array[String] = ["dash", "grenade", "nova"]

# bookkeeping
var upgrades_bought: Dictionary = {}     # id -> count
var kills: int = 0
var minis_killed: int = 0
var majors_killed: int = 0
var damage_dealt: float = 0.0
var money_earned: int = 0
var rerolls_used: int = 0
var health_potion_guard: float = 0.0     # seconds left on the anti-farm guard

## Combo: kills chained without being hit.
##
## The game had no reason to fight aggressively rather than kite - every kill
## was worth the same whenever it happened. A combo that rises on quick kills
## and dies the moment you are hit is the risk side of that, and it is the
## charge condition the Engineer's ultimate reads.
##
## It resets on damage on purpose, which pulls against the wider i-frames added
## in the same pass. That is the intended split: forgiveness comes from the
## i-frames, so a struggling player is not punished twice, and the combo is what
## a confident one is playing for.
var combo: int = 0
var combo_best: int = 0
var combo_timer: float = 0.0
const COMBO_WINDOW := 2.2
var started_at_ms: int = 0


func _init() -> void:
	gun = Balance.GUN_BASE.duplicate()
	started_at_ms = Time.get_ticks_msec()


## Build a run from the player's permanent unlocks.
static func create(seed_v: int, save_unlocks: Array, loadout: Array[String],
		nightmare_mode: bool = false, character: String = "") -> RunState:
	var rs := RunState.new()
	rs.seed_value = seed_v
	rs.nightmare = nightmare_mode
	rs.class_id = ClassesDB.sanitise(character)
	rs.abilities = loadout.duplicate()
	var essence_mul := 0.0
	for id: String in save_unlocks:
		if not MetaDB.DEFS.has(id):
			continue
		var def: Dictionary = MetaDB.DEFS[id]
		if def["kind"] != MetaDB.KIND_PASSIVE:
			continue
		var stat: String = def["stat"]
		var amount: float = float(def["amount"])
		match stat:
			"max_hp":
				rs.max_hp += amount
			"start_money":
				rs.money += int(amount)
			"gun.damage":
				rs.gun["damage"] = float(rs.gun["damage"]) + amount
			"ability_extra_charges":
				rs.ability_extra_charges += int(amount)
			"free_rerolls":
				rs.free_rerolls += int(amount)
			"essence_mul":
				essence_mul += amount
	# The class passive rides the same _apply_effect machinery every shop
	# upgrade uses, so it inherits every stat cap for free - a class can lift a
	# stat but never past the ceiling the game already enforces.
	var cls := ClassesDB.get_def(rs.class_id)
	var passive: Dictionary = cls.get("passive", {})
	if not passive.is_empty():
		rs._apply_effect(String(passive["stat"]), int(passive["kind"]),
			float(passive["amount"]))

	rs.hp = rs.max_hp
	rs.set_meta("essence_mul", 1.0 + essence_mul)
	return rs


## Essence multiplier granted by permanent passives.
func essence_multiplier() -> float:
	return float(get_meta("essence_mul", 1.0))


# ---------------------------------------------------------------------------
# ultimate charge
# ---------------------------------------------------------------------------
## Feed the ultimate. `source` is a ClassesDB.CHARGE_* id; anything that is not
## this class's own condition is ignored, which is what makes the five classes
## play differently rather than all filling from the same firehose.
##
## Every CHARGE_* constant must appear as a match arm here. The logic suite
## reads the arms out of this file, so a class naming a condition nothing
## implements fails the build rather than shipping an ultimate that never
## charges.
func add_ultimate_charge(source: String, magnitude: float) -> void:
	if ultimate_charge >= 1.0:
		return
	var want := String(ClassesDB.get_def(class_id)["charge"])
	if source != want:
		return

	var gain := 0.0
	match source:
		ClassesDB.CHARGE_ELITES:
			gain = magnitude * 0.16          # magnitude 1 per elite, 4 per boss
		ClassesDB.CHARGE_BRAWL:
			gain = magnitude / 900.0
		ClassesDB.CHARGE_DEALT:
			gain = magnitude / 5200.0
		ClassesDB.CHARGE_COMBO:
			gain = magnitude * 0.012         # magnitude is the combo count
		ClassesDB.CHARGE_PICKUPS:
			gain = magnitude * 0.014
	gain *= ultimate_rate
	if gain <= 0.0:
		return
	var before := ultimate_charge
	ultimate_charge = clampf(ultimate_charge + gain, 0.0, 1.0)
	if ultimate_charge != before:
		Events.ultimate_charge_changed.emit(ultimate_charge)


func ultimate_ready() -> bool:
	return ultimate_charge >= 1.0


## Spend it. Returns false if it was not full, so the caller cannot half-fire.
func spend_ultimate() -> bool:
	if not ultimate_ready():
		return false
	ultimate_charge = 0.0
	ultimates_used += 1
	Events.ultimate_charge_changed.emit(0.0)
	return true


## One more link in the chain. Returns the new combo count.
func add_combo() -> int:
	combo += 1
	combo_best = maxi(combo_best, combo)
	combo_timer = COMBO_WINDOW
	Events.combo_changed.emit(combo, combo_tier())
	return combo


func break_combo() -> void:
	if combo <= 0:
		return
	combo = 0
	combo_timer = 0.0
	Events.combo_changed.emit(0, 0)


## Ticks the window down. Called from run.gd, like health_potion_guard.
func tick_combo(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		break_combo()


## 0-5. Drives shake strength, hit stop, audio pitch, the coin multiplier and
## the HUD - one number so all of those can never disagree about how well you
## are doing.
##
## The top two tiers exist because the escalation used to go flat exactly when
## the player was doing best: the ceiling was 30 and the headless sim's best
## chain is 51, so a good run spent most of its time already maxed out with
## nothing further to earn. The thresholds below 30 are deliberately unchanged,
## so early and mid-wave pacing is exactly what it was.
const COMBO_TIER_THRESHOLDS: Array[int] = [0, 6, 15, 30, 50, 80]
const COMBO_TIER_MAX := 5


func combo_tier() -> int:
	# Walked from the top so the table is the single source of truth - a tier
	# added to COMBO_TIER_THRESHOLDS needs no second edit here.
	for tier: int in range(COMBO_TIER_MAX, 0, -1):
		if combo >= COMBO_TIER_THRESHOLDS[tier]:
			return tier
	return 0


func hp_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


func is_low_health() -> bool:
	return hp_fraction() <= Balance.LOW_HEALTH_FRACTION and hp > 0.0


func add_money(amount: int) -> void:
	var gained := int(round(amount * money_mul))
	money += gained
	money_earned += gained
	Events.money_changed.emit(money, gained)


func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	Events.money_changed.emit(money, -amount)
	return true


## Apply a shop upgrade. Returns false if the id is unknown.
## How much an ability upgrade of `kind` has been stacked, as a multiplier for
## the scaling kinds and a count for charges.
## Keyed by the STAT an upgrade affects ("power", "cooldown", "charges",
## "area"), not by the upgrade's display name. Those are different strings -
## "sharpened" raises "power" - and storing under one while reading the other
## is a silent no-op that looks like it worked.
func ability_bonus(ability: String, stat: String) -> float:
	var levels: Dictionary = ability_levels.get(ability, {})
	var count := int(levels.get(stat, 0))
	if count <= 0:
		return 0.0 if stat == "charges" else 1.0
	var amount := 1.0
	for kind: String in UpgradesDB.ABILITY_KINDS:
		var info: Dictionary = UpgradesDB.ABILITY_KINDS[kind]
		if String(info["stat"]) == stat:
			amount = float(info["amount"])
			break
	if stat == "charges":
		return amount * count
	return pow(amount, count)


func _buy_ability_upgrade(id: String) -> bool:
	var parsed := UpgradesDB.parse_ability_upgrade(id)
	if parsed.is_empty():
		return false
	var ability: String = parsed["ability"]
	# Only ever for something actually carried, so a stale offer cannot
	# quietly upgrade an ability that is not in the loadout.
	if not abilities.has(ability):
		return false
	var stat := String(UpgradesDB.ABILITY_KINDS[parsed["kind"]]["stat"])
	var levels: Dictionary = ability_levels.get(ability, {})
	levels[stat] = int(levels.get(stat, 0)) + 1
	ability_levels[ability] = levels
	# Recorded like any other purchase, so repeat pricing escalates. Without
	# this the same ability upgrade stays at its base price forever and the
	# opportunity cost that the whole shop is built on disappears for exactly
	# the upgrades that stack best.
	upgrades_bought[id] = int(upgrades_bought.get(id, 0)) + 1
	return true


func apply_upgrade(id: String) -> bool:
	if UpgradesDB.is_ability_upgrade(id):
		# The ability branch emitted nothing at all, so nothing downstream ever
		# learned a purchase had happened.
		if not _buy_ability_upgrade(id):
			return false
		Events.upgrade_purchased.emit(id)
		return true
	if not UpgradesDB.DEFS.has(id):
		return false
	var def: Dictionary = UpgradesDB.get_def(id)
	_apply_effect(def["stat"], def["kind"], float(def["amount"]))
	var side: Variant = def.get("side")
	if side != null:
		_apply_effect(side["stat"], side["kind"], float(side["amount"]))
	upgrades_bought[id] = int(upgrades_bought.get(id, 0)) + 1
	Events.gun_upgraded.emit(def["stat"], stat_value(def["stat"]))
	# Focused Mind and Deep Reserves are ordinary upgrades that happen to feed
	# the ability slots, so this path has to announce itself too.
	Events.upgrade_purchased.emit(id)
	return true


func _apply_effect(stat: String, kind: int, amount: float) -> void:
	if stat == "heal_full":
		hp = max_hp
		Events.player_healed.emit(max_hp)
		return

	if stat.begins_with("gun."):
		var key := stat.substr(4)
		var cur := float(gun.get(key, 0.0))
		gun[key] = _clamp_gun(key, _combine(cur, kind, amount))
		return

	var before := stat_value(stat)
	var after := _combine(before, kind, amount)
	match stat:
		"max_hp":
			var delta := after - max_hp
			max_hp = after
			hp = minf(hp + maxf(delta, 0.0), max_hp)
		"damage_reduction":
			damage_reduction = minf(after, 0.70)     # never fully immune
		"move_speed_mul":
			move_speed_mul = minf(after, 1.85)
		"pickup_range_mul":
			pickup_range_mul = minf(after, 4.0)
		"ability_cdr":
			ability_cdr = minf(after, 0.60)
		"ability_extra_charges":
			ability_extra_charges = int(after)
		"lifesteal":
			lifesteal = minf(after, 0.35)
		"money_mul":
			money_mul = after
		"ultimate_rate":
			ultimate_rate = minf(after, 2.5)
		"ultimate_power":
			ultimate_power = minf(after, 2.5)


func _combine(current: float, kind: int, amount: float) -> float:
	match kind:
		UpgradesDB.Kind.ADD:
			return current + amount
		UpgradesDB.Kind.MUL:
			return current * amount
		_:
			return amount


func _clamp_gun(key: String, value: float) -> float:
	if not Balance.GUN_CAPS.has(key):
		return maxf(value, 0.0)
	var cap := float(Balance.GUN_CAPS[key])
	# reload_time and spread are floors; everything else is a ceiling
	if key in ["reload_time", "spread"]:
		return maxf(value, cap)
	return minf(value, cap)


func stat_value(stat: String) -> float:
	if stat.begins_with("gun."):
		return float(gun.get(stat.substr(4), 0.0))
	match stat:
		"max_hp": return max_hp
		"damage_reduction": return damage_reduction
		"move_speed_mul": return move_speed_mul
		"pickup_range_mul": return pickup_range_mul
		"ability_cdr": return ability_cdr
		"ability_extra_charges": return float(ability_extra_charges)
		"lifesteal": return lifesteal
		"money_mul": return money_mul
		"ultimate_rate": return ultimate_rate
		"ultimate_power": return ultimate_power
		_: return 0.0


func _total_upgrades_bought() -> int:
	var n := 0
	for id: String in upgrades_bought:
		n += int(upgrades_bought[id])
	return n


func times_bought(id: String) -> int:
	return int(upgrades_bought.get(id, 0))


## Damage per second at full uptime, used for the run-results screen.
func effective_dps() -> float:
	var mag := float(gun["magazine"])
	var rate := float(gun["fire_rate"])
	var cycle := mag / rate + float(gun["reload_time"])
	var per_shot := float(gun["damage"]) * float(gun["projectile_count"])
	var crit := 1.0 + float(gun["crit_chance"]) * (float(gun["crit_damage"]) - 1.0)
	return per_shot * crit * mag / cycle


func summary() -> Dictionary:
	return {
		"wave": wave,
		"kills": kills,
		"combo_best": combo_best,
		"minis": minis_killed,
		"majors": majors_killed,
		"money_earned": money_earned,
		"damage_dealt": damage_dealt,
		"dps": effective_dps(),
		"seed": seed_value,
		"duration_ms": Time.get_ticks_msec() - started_at_ms,
		"abilities": abilities.duplicate(),
		"nightmare": nightmare,
		# Total purchases, not the per-id breakdown: achievements ask "did you
		# buy anything at all", and the breakdown is not worth serialising.
		"upgrades_bought": _total_upgrades_bought(),
	}
