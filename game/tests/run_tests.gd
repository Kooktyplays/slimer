extends Node
## Logic tests: everything checkable without playing the game.
##
## Run: Godot --headless --path game -- tests
##
## Attached as a node rather than run via --script so the autoloads exist -
## Save and Game are singletons, and testing them through a fake would be
## testing the fake.

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	Save.disable_writes = true
	call_deferred("_run")


func _run() -> void:
	_test_boss_cadence()
	_test_wave_curve()
	_test_enemy_unlocks()
	_test_elites()
	_test_adaptation_pair()
	_test_animation()
	_test_thief_and_mimic()
	_test_boss_phases()
	_test_boss_curve()
	_test_classes()
	_test_combo()
	_test_leap()
	_test_gun_upgrades()
	_test_upgrade_pricing()
	_test_economy()
	_test_potions()
	_test_save_roundtrip()
	_test_loadout()
	_test_meta_progression()
	_test_forest_smoke()
	_test_biomes()
	_test_arena_is_sealed()
	_test_nightmare()
	_test_achievements()
	_report()


# ---------------------------------------------------------------------------
# assertions
# ---------------------------------------------------------------------------
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(a: float, b: float, message: String, epsilon: float = 0.001) -> void:
	_check(absf(a - b) <= epsilon, "%s (got %.4f, expected %.4f)" % [message, a, b])


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------
## The brief is explicit: mini-boss every 5 waves, major every 20, and the
## major replaces the mini rather than stacking with it.
func _test_boss_cadence() -> void:
	var minis := 0
	var majors := 0
	for wave in range(1, 201):
		var is_mini := Game.is_mini_boss_wave(wave)
		var is_major := Game.is_major_boss_wave(wave)
		_check(not (is_mini and is_major),
			"wave %d is both a mini-boss and a major boss" % wave)
		if wave % 20 == 0:
			_check(is_major, "wave %d should be a major boss" % wave)
		elif wave % 5 == 0:
			_check(is_mini, "wave %d should be a mini-boss" % wave)
		else:
			_check(not is_mini and not is_major,
				"wave %d should not be a boss wave" % wave)
		if is_mini:
			minis += 1
		if is_major:
			majors += 1

	_check(majors == 10, "expected 10 major bosses in 200 waves, got %d" % majors)
	_check(minis == 30, "expected 30 mini-bosses in 200 waves, got %d" % minis)

	# every boss wave must resolve to a real archetype, and repeats must add
	# phases rather than only health
	var seen_minis := {}
	var seen_majors := {}
	for wave in range(1, 201):
		if not Game.is_boss_wave(wave):
			continue
		var pick := BossDB.for_wave(wave)
		_check(BossDB.DEFS.has(pick["id"]),
			"wave %d picked unknown boss '%s'" % [wave, pick["id"]])
		_check(bool(pick["major"]) == Game.is_major_boss_wave(wave),
			"wave %d boss major flag disagrees with the cadence" % wave)
		var phases := BossDB.phase_count(pick["id"], int(pick["repeat"]))
		_check(phases >= 2, "wave %d boss has only %d phases" % [wave, phases])
		_check(phases <= (BossDB.DEFS[pick["id"]]["phases"] as Array).size(),
			"wave %d boss wants more phases than it defines" % wave)
		if bool(pick["major"]):
			seen_majors[pick["id"]] = true
		else:
			seen_minis[pick["id"]] = true

	_check(seen_minis.size() == BossDB.MINI_ROTATION.size(),
		"only %d of %d mini-boss archetypes ever appear"
			% [seen_minis.size(), BossDB.MINI_ROTATION.size()])
	_check(seen_majors.size() == BossDB.MAJOR_ROTATION.size(),
		"only %d of %d major boss archetypes ever appear"
			% [seen_majors.size(), BossDB.MAJOR_ROTATION.size()])

	# rewards must scale with the wave, and majors must beat minis
	_check(Balance.major_boss_reward(20) > Balance.mini_boss_reward(20) * 2,
		"a major boss should pay out far more than a mini")
	_check(Balance.mini_boss_hp(25) > Balance.mini_boss_hp(5),
		"later mini-bosses should be tougher")


## Difficulty must rise, but not by inflating HP forever - the caps are the
## whole point of the design.
func _test_wave_curve() -> void:
	var previous := 0.0
	for wave in range(1, 201):
		var budget := Balance.wave_budget(wave)
		_check(budget > previous, "wave %d budget did not increase" % wave)
		previous = budget

	_check(Balance.wave_budget(20) > Balance.wave_budget(10) * 1.8,
		"the budget curve is too flat to feel like escalation")

	# stat scaling is capped so late waves are wider, not spongier
	_close(Balance.hp_scale(1), 1.0, "wave 1 hp scale should be 1.0")
	_check(Balance.hp_scale(500) <= 3.2001, "hp scale exceeded its cap")
	_check(Balance.damage_scale(500) <= 2.4001, "damage scale exceeded its cap")
	_check(Balance.speed_scale(500) <= 1.4501, "speed scale exceeded its cap")
	_check(Balance.spawn_rate(500) <= 9.5001, "spawn rate exceeded its cap")

	# an enemy at wave 200 should be a few times tougher, not a thousand times
	_check(Balance.hp_scale(200) < 4.0,
		"late enemies are HP sponges, which the design explicitly rejects")


## The composition table has to produce the progression the brief describes:
## early waves are simple, later ones combine types.
func _test_enemy_unlocks() -> void:
	_check(EnemyTypes.unlocked_for_wave(1) == [EnemyTypes.GREEN],
		"wave 1 should only contain green slimes")
	_check(EnemyTypes.unlocked_for_wave(3) == [EnemyTypes.GREEN],
		"wave 3 should still only be green")

	var w7 := EnemyTypes.unlocked_for_wave(7)
	for id: String in [EnemyTypes.GREEN, EnemyTypes.BLUE, EnemyTypes.RED]:
		_check(w7.has(id), "wave 7 should include %s" % id)
	_check(not w7.has(EnemyTypes.ORANGE), "wave 7 should not include orange yet")

	var w12 := EnemyTypes.unlocked_for_wave(12)
	for id: String in [EnemyTypes.GREEN, EnemyTypes.BLUE, EnemyTypes.RED,
			EnemyTypes.PURPLE, EnemyTypes.YELLOW]:
		_check(w12.has(id), "wave 12 should include %s" % id)

	_check(EnemyTypes.unlocked_for_wave(17).has(EnemyTypes.ORANGE),
		"wave 17 should include orange bloaters")
	_check(EnemyTypes.unlocked_for_wave(30).size() == EnemyTypes.ORDER.size(),
		"every enemy type should be available by wave 30")

	# unlocks only ever add
	var previous := 0
	for wave in range(1, 60):
		var n := EnemyTypes.unlocked_for_wave(wave).size()
		_check(n >= previous, "the roster shrank at wave %d" % wave)
		previous = n

	# every type must declare a colour, a behaviour and a distinct role
	var behaviours := {}
	for id: String in EnemyTypes.ORDER:
		var def := EnemyTypes.get_def(id)
		_check(def.has("tint"), "%s has no colour" % id)
		_check(def.has("behavior"), "%s has no behaviour" % id)
		_check(float(def["threat"]) > 0.0, "%s has no threat cost" % id)
		_check(not behaviours.has(def["behavior"]),
			"%s reuses the '%s' behaviour - colours must mean different things"
				% [id, def["behavior"]])
		behaviours[def["behavior"]] = id
	_check(behaviours.size() == EnemyTypes.ORDER.size(),
		"expected one distinct behaviour per enemy type")

	# green must fade as the roster fills, or later waves feel the same
	var early: float = EnemyTypes.weights_for_wave(2)[EnemyTypes.GREEN]
	var late: float = EnemyTypes.weights_for_wave(40)[EnemyTypes.GREEN]
	_check(late < early, "green slimes do not thin out in later waves")


func _test_elites() -> void:
	for wave in range(1, Balance.ELITE_UNLOCK_WAVE):
		_close(Balance.elite_chance(wave), 0.0,
			"elites appeared before wave %d" % Balance.ELITE_UNLOCK_WAVE)
	_check(Balance.elite_chance(Balance.ELITE_UNLOCK_WAVE) > 0.0,
		"elites never unlock")
	_check(Balance.elite_chance(500) <= 0.3001, "elite chance exceeded its cap")
	_check(Balance.ELITE_THREAT_MULTIPLIER > 1.0,
		"elites must cost extra threat, or a wave gets strictly harder for free")
	_check(EnemyTypes.ELITE_MODS.size() >= 3, "expected at least three elite modifiers")

	# every modifier must be described, or the tutor hint for it is blank
	for mod: String in EnemyTypes.ELITE_MODS:
		_check(EnemyTypes.ELITE_MOD_INFO.has(mod),
			"elite modifier '%s' has no ELITE_MOD_INFO entry" % mod)
		var info: Dictionary = EnemyTypes.ELITE_MOD_INFO.get(mod, {})
		_check(not String(info.get("name", "")).is_empty(), "%s has no name" % mod)
		_check(not String(info.get("desc", "")).is_empty(), "%s has no description" % mod)
	_check(EnemyTypes.ELITE_MOD_INFO.size() == EnemyTypes.ELITE_MODS.size(),
		"ELITE_MOD_INFO describes a modifier that is never rolled")

	# A pooled enemy has to come back clean. A Phasing elite clears its hurtbox
	# layer to become untargetable; if configure() did not restore it, the next
	# slime out of the pool would be permanently unhittable and the wave could
	# never end. This is the guard on that.
	var scene: PackedScene = load("res://actors/enemy.tscn")
	var e: Enemy = scene.instantiate()
	add_child(e)
	e.configure(EnemyTypes.GREEN, 20, "phasing")
	# force it out of phase, the way the elite tick would
	e.call("_tick_elite", 999.0)
	var phased_layer: int = e.get_node("Hurtbox").collision_layer
	_check(phased_layer == 0, "a phasing elite should be untargetable while out")
	# ...and now recycled as an ordinary slime
	e.configure(EnemyTypes.GREEN, 20, "")
	_check(e.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a recycled enemy kept a phasing elite's disabled hurtbox - it would be "
		+ "permanently untargetable")
	_check(is_equal_approx(e.get_node("Visual").modulate.a, 1.0),
		"a recycled enemy kept a phasing elite's faded sprite")
	e.die(false)
	e.queue_free()


## The five characters, and the two ways a class can silently not work.
func _test_classes() -> void:
	_check(ClassesDB.ORDER.size() == 5, "expected five classes")
	_check(ClassesDB.DEFS.size() == ClassesDB.ORDER.size(),
		"a class is declared but not in ORDER, or the other way round")
	_check(ClassesDB.is_valid(ClassesDB.DEFAULT), "the default class does not exist")

	# An unknown id must fall back, not error - a save written before classes
	# existed carries no class at all.
	_check(ClassesDB.sanitise("") == ClassesDB.DEFAULT, "empty class id did not fall back")
	_check(ClassesDB.sanitise("nonesuch") == ClassesDB.DEFAULT,
		"an unknown class id did not fall back")

	var charges := _charge_arms()
	var ultimates := _ultimate_arms()
	var seen_charge := {}
	var seen_ult := {}

	for id: String in ClassesDB.ORDER:
		var def := ClassesDB.get_def(id)
		for key: String in ["name", "title", "blurb", "tint", "passive",
				"passive_text", "charge", "charge_text", "ultimate",
				"ultimate_name", "ultimate_text"]:
			_check(def.has(key), "class %s declares no '%s'" % [id, key])

		# A charge condition nothing implements is an ultimate that never fills.
		var charge := String(def["charge"])
		_check(charges.has(charge),
			"class %s charges from '%s', which RunState.add_ultimate_charge "
				% [id, charge] + "has no arm for - its ultimate would never fill")
		_check(not seen_charge.has(charge),
			"%s and %s share the charge condition '%s'"
				% [id, seen_charge.get(charge, "?"), charge])
		seen_charge[charge] = id

		# An ultimate nothing dispatches is a button that does nothing.
		var ult := String(def["ultimate"])
		_check(ultimates.has(ult),
			"class %s names ultimate '%s', which nothing dispatches" % [id, ult])
		_check(not seen_ult.has(ult),
			"%s and %s share an ultimate" % [id, seen_ult.get(ult, "?")])
		seen_ult[ult] = id

		# The passive has to be a stat the run actually understands.
		var passive: Dictionary = def["passive"]
		var stat := String(passive["stat"])
		var rs := RunState.create(1, [], ["dash", "grenade", "nova"], false, id)
		_check(rs.class_id == id, "RunState did not keep the class it was given")
		_check(rs.stat_value(stat) != 0.0 or stat == "damage_reduction",
			"class %s's passive stat '%s' reads as nothing" % [id, stat])

		# ...and it must not blow through the caps every upgrade respects.
		_check(rs.damage_reduction <= 0.70, "%s pushed damage reduction past its cap" % id)
		_check(rs.move_speed_mul <= 1.85, "%s pushed move speed past its cap" % id)
		_check(rs.lifesteal <= 0.35, "%s pushed lifesteal past its cap" % id)
		_check(rs.ability_cdr <= 0.60, "%s pushed cooldown reduction past its cap" % id)

		# every class needs a face
		_check(ResourceLoader.exists(ClassesDB.sprite_path(id)),
			"class %s has no sprite at %s" % [id, ClassesDB.sprite_path(id)])

	# --- charge is bounded, and cannot be spent twice ----------------------
	var rs2 := RunState.create(1, [], ["dash", "grenade", "nova"], false,
		ClassesDB.WARRIOR)
	_check(not rs2.ultimate_ready(), "a run started with a full ultimate")
	_check(not rs2.spend_ultimate(), "an empty ultimate could be spent")
	for i in 400:
		rs2.add_ultimate_charge(ClassesDB.CHARGE_BRAWL, 50.0)
	_check(rs2.ultimate_charge <= 1.0,
		"ultimate charge ran past full to %.2f" % rs2.ultimate_charge)
	_check(rs2.ultimate_ready(), "the ultimate never filled")
	_check(rs2.spend_ultimate(), "a full ultimate could not be spent")
	_check(rs2.ultimate_charge == 0.0, "spending did not empty the meter")
	_check(not rs2.spend_ultimate(), "an ultimate was spent twice")

	# ...and only from its own condition, or all five classes play the same
	var rs3 := RunState.create(1, [], ["dash", "grenade", "nova"], false,
		ClassesDB.WARRIOR)
	rs3.add_ultimate_charge(ClassesDB.CHARGE_DEALT, 100000.0)
	_check(rs3.ultimate_charge == 0.0,
		"the Warrior charged from damage dealt, which is the Vampire's condition")

	# Every id the shop can offer must carry every field the shop reads. The
	# class upgrades shipped with "price"/"category" instead of "cost"/"cat"
	# and no "weight" at all, which made _roll_offers error and quietly sold
	# nothing for a whole run - the suite passed the entire time.
	for cls: String in ClassesDB.ORDER:
		for id: String in UpgradesDB.available_ids([], cls):
			var def := UpgradesDB.any_def(id)
			for key: String in ["name", "cat", "stat", "kind", "amount",
					"desc", "cost", "weight"]:
				_check(def.has(key),
					"shop upgrade '%s' has no '%s' - the shop reads it" % [id, key])
			_check(UpgradesDB.price(id, 0) > 0, "upgrade '%s' is free" % id)
			_check(float(def["weight"]) > 0.0, "upgrade '%s' can never be rolled" % id)

	# every class upgrade must be reachable by exactly the class it is for
	for id: String in UpgradesDB.CLASS_LOCKED:
		var owner := String(UpgradesDB.CLASS_LOCKED[id])
		_check(ClassesDB.is_valid(owner),
			"class upgrade %s is locked to unknown class %s" % [id, owner])
		_check(not UpgradesDB.any_def(id).is_empty(),
			"class upgrade %s is locked but never defined" % id)
		_check(UpgradesDB.available_ids([], owner).has(id),
			"%s is never offered to %s, the only class that can use it" % [id, owner])
		for other: String in ClassesDB.ORDER:
			if other == owner:
				continue
			_check(not UpgradesDB.available_ids([], other).has(id),
				"%s is offered to %s as well as %s" % [id, other, owner])


## Charge conditions RunState can actually act on, read out of the match arms
## rather than restated here - the same shape as the boss-attack and biome
## hazard guards, and for the same reason: a guard that cannot fail is worse
## than no guard.
func _charge_arms() -> Dictionary:
	return _match_arms("res://data/run_state.gd", "ClassesDB.CHARGE_")


## Ultimates the ability controller can dispatch.
func _ultimate_arms() -> Dictionary:
	var out := {}
	var src := _read_source("res://abilities/ability_controller.gd")
	var re := RegEx.new()
	re.compile('"(?<name>[a-z_]+)":\\s*_ult_')
	for m: RegExMatch in re.search_all(src):
		out[m.get_string("name")] = true
	return out


## Constants named on the left of a `match` arm in `path`. Only arms count -
## a mention anywhere else in the file is not a dispatch.
func _match_arms(path: String, prefix: String) -> Dictionary:
	var out := {}
	for line: String in _read_source(path).split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.ends_with(":") or not trimmed.begins_with(prefix):
			continue
		# "ClassesDB.CHARGE_ELITES:" -> the constant's value
		var name := trimmed.trim_suffix(":").split(".")[-1]
		for c: String in [ClassesDB.CHARGE_ELITES, ClassesDB.CHARGE_BRAWL,
				ClassesDB.CHARGE_DEALT, ClassesDB.CHARGE_COMBO,
				ClassesDB.CHARGE_PICKUPS]:
			if name.to_lower().ends_with(c.to_lower()):
				out[c] = true
	return out


## The leap has to put everything back.
##
## begin_leap drops the collision mask so the arc carries over trees and lifts
## the sprite off its own shadow. If end_leap fails to restore either, the
## player is left walking through the forest permanently, floating.
func _test_leap() -> void:
	var scene: PackedScene = load("res://actors/player.tscn")
	var pl: Player = scene.instantiate()
	add_child(pl)

	var mask := pl.collision_mask
	_check(mask != 0, "the player starts with no collision mask at all")

	pl.begin_leap(0.2)
	_check(pl.airborne, "begin_leap did not mark the player airborne")
	_check(pl.dashing, "an airborne player should also be dashing (i-frames)")
	_check(pl.collision_mask == 0,
		"a leap did not drop the collision mask - it would stop at the first tree")

	pl.end_leap()
	_check(not pl.airborne, "end_leap did not clear airborne")
	_check(not pl.dashing, "end_leap did not clear dashing")
	_check(pl.collision_mask == mask,
		"end_leap did not restore the collision mask - the player would walk "
		+ "through the forest for the rest of the run")
	_check(is_equal_approx(pl.get_node("Visual").position.y, 0.0),
		"end_leap left the player floating above their own shadow")
	_check(is_equal_approx(pl.get_node("Shadow").scale.x, 1.0),
		"end_leap left the shadow shrunk")
	pl.queue_free()


## Combos: the risk half of the pass that made damage more forgiving.
func _test_combo() -> void:
	var rs := RunState.create(1, [], ["dash", "grenade", "nova"], false)
	_check(rs.combo == 0, "a run started mid-combo")
	for i in 8:
		rs.add_combo()
	_check(rs.combo == 8, "the combo did not count to 8")
	_check(rs.combo_best == 8, "the best combo was not recorded")
	_check(rs.combo_tier() >= 1, "eight kills did not reach the first tier")

	# it dies on damage - that is the whole risk side of it
	rs.break_combo()
	_check(rs.combo == 0, "the combo survived a break")
	_check(rs.combo_best == 8, "breaking the combo erased the best, which is a record")

	# ...and it dies on its own if you stop
	for i in 5:
		rs.add_combo()
	rs.tick_combo(RunState.COMBO_WINDOW + 0.1)
	_check(rs.combo == 0, "the combo did not expire when the window ran out")

	# tiers have to actually rise, or the shake and the HUD read one number
	var last := -1
	for n in [0, 6, 15, 30]:
		rs.break_combo()
		for i in n:
			rs.add_combo()
		var tier := rs.combo_tier()
		_check(tier > last or n == 0, "combo tier did not rise at %d kills" % n)
		last = tier


## Bosses must not fall behind the waves.
##
## This is the guard on a measured, structural bug rather than a matter of
## taste. Boss health was linear (520 + 95w) while a wave's total health pool
## is quadratic - wave_budget is already w-squared before hp_scale multiplies
## it again - so the two diverged permanently: a mini-boss was 1.14x a whole
## wave's health at wave 5, 0.48x by wave 15 and 0.22x by wave 30.
##
## The floor is deliberately below 1.0. A boss does not need more health than a
## wave to be harder than one: a wave is thirty-odd bodies from every direction
## with stacking poison, a boss is one target with walkable telegraphs. But it
## must not fall to a fifth of one.
const BOSS_HP_FLOOR := 0.70


func _test_boss_curve() -> void:
	var worst := INF
	var worst_wave := 0
	for wave in range(1, 101):
		if not (Game.is_mini_boss_wave(wave) or Game.is_major_boss_wave(wave)):
			continue
		var boss_hp := (Balance.major_boss_hp(wave) if Game.is_major_boss_wave(wave)
			else Balance.mini_boss_hp(wave))
		var ratio := boss_hp / Balance.wave_hp_pool(wave)
		if ratio < worst:
			worst = ratio
			worst_wave = wave
	_check(worst >= BOSS_HP_FLOOR,
		("boss health falls to %.2fx a wave's pool at wave %d - the boss curve "
		+ "has drifted back below the wave curve") % [worst, worst_wave])

	# ...and a major must always be the bigger event of the two.
	for wave in range(20, 101, 20):
		_check(Balance.major_boss_hp(wave) > Balance.mini_boss_hp(wave) * 1.5,
			"the major boss at wave %d is not meaningfully bigger than a mini" % wave)

	# Both curves have to actually curve. A straight line is what caused this.
	# Second difference of a quadratic is positive and constant; of a line, zero.
	# Second difference of a quadratic is positive; of a straight line, zero.
	var mini_second: float = (Balance.mini_boss_hp(30)
		- 2.0 * Balance.mini_boss_hp(20) + Balance.mini_boss_hp(10))
	var major_second: float = (Balance.major_boss_hp(30)
		- 2.0 * Balance.major_boss_hp(20) + Balance.major_boss_hp(10))
	_check(mini_second > 1.0,
		"the mini-boss health curve is linear again - it has to grow with the "
		+ "wave budget, which is quadratic")
	_check(major_second > 1.0,
		"the major-boss health curve is linear again")

	# Boss damage must keep pace with the player's growing health pool too.
	_check(Balance.boss_damage_scale(40) > Balance.boss_damage_scale(20) * 1.6,
		"boss damage barely grows between wave 20 and wave 40")


## The two rules that keep five bosses from being one boss.
##
## Both of these were broken until the adaptation pass: every phase list was
## the previous phase plus more entries, and every attack came from one shared
## pool, so no boss had a move of its own and no phase changed how you fought.
func _test_boss_phases() -> void:
	# every attack a boss can name has to actually dispatch, or a typo makes a
	# boss silently do nothing for a whole phase
	var handled := _boss_attack_names()
	var signatures := {}

	for id: String in BossDB.DEFS:
		var def := BossDB.get_def(id)
		var phases: Array = def["phases"]

		_check(def.has("signature"), "%s has no signature attack" % id)
		var sig := String(def.get("signature", ""))
		_check(not signatures.has(sig),
			"%s and %s share the signature '%s' - it is not a signature then"
				% [id, signatures.get(sig, "?"), sig])
		signatures[sig] = id

		# the signature has to be used, and only by its owner
		var used := false
		for phase: Array in phases:
			if phase.has(sig):
				used = true
		_check(used, "%s declares the signature '%s' and never uses it" % [id, sig])

		for other: String in BossDB.DEFS:
			if other == id:
				continue
			for phase: Array in BossDB.get_def(other)["phases"]:
				_check(not phase.has(sig),
					"%s uses %s's signature '%s'" % [other, id, sig])

		for i in phases.size():
			var phase: Array = phases[i]
			_check(not phase.is_empty(), "%s phase %d has no attacks" % [id, i + 1])
			for attack: String in phase:
				_check(handled.has(attack),
					"%s phase %d names '%s', which _choose_attack cannot dispatch"
						% [id, i + 1, attack])

			# THE regression guard: a phase may not be its predecessor plus
			# more. If it is, the phase change only altered the attack rate.
			if i > 0:
				var previous: Array = phases[i - 1]
				var kept := 0
				for attack: String in previous:
					if phase.has(attack):
						kept += 1
				_check(kept < previous.size(),
					("%s phase %d keeps every attack from phase %d - a phase has "
					+ "to replace, not append") % [id, i + 1, i])

		# enough phases to cover the repeats the endless run will ask for
		_check(phases.size() >= BossDB.phase_count(id, 0),
			"%s declares fewer phases than its first encounter uses" % id)

	_check(signatures.size() == BossDB.DEFS.size(),
		"expected one distinct signature attack per boss")


## Attack ids boss.gd's dispatch actually understands, read out of the source
## so the test cannot drift away from the match statement it is guarding.
func _boss_attack_names() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://actors/bosses/boss.gd", FileAccess.READ)
	if f == null:
		_check(false, "could not read boss.gd to check the attack dispatch")
		return out
	var text := f.get_as_text()
	f.close()
	var re := RegEx.new()
	re.compile('"(?<name>[a-z_]+)":\\s*_atk_')
	for m: RegExMatch in re.search_all(text):
		out[m.get_string("name")] = true
	_check(out.size() >= 14, "found only %d boss attacks in the dispatch" % out.size())
	return out


## Frame animation, and the one mistake that would break every hurtbox.
##
## Enemy._apply_hit_shapes and Boss._apply_hit_shapes both size their hurtbox
## from texture.get_height(). Every animated sheet in the game is therefore a
## HORIZONTAL strip: laid out vertically, get_height() would return the height
## of the whole column and silently inflate - or, on a re-tuned sheet, shrink -
## every hit shape in the game. Nothing else in the codebase would notice.
func _test_animation() -> void:
	var sheets := {}
	# one slime, hue-rotated into the whole roster - so all of them must agree
	for id: String in EnemyTypes.ORDER:
		sheets[EnemyTypes.texture_path(id)] = 4
	for id: String in BossDB.DEFS:
		sheets[String(BossDB.get_def(id)["body"])] = Boss.POSE_COUNT

	for path: String in sheets:
		var tex: Texture2D = load(path)
		_check(tex != null, "missing animated sheet %s" % path)
		if tex == null:
			continue
		var frames: int = sheets[path]
		_check(tex.get_width() > tex.get_height(),
			"%s is not a horizontal strip - a vertical one silently resizes "
				% path + "every hit shape in the game")
		_check(tex.get_width() % frames == 0,
			"%s is %d wide, which does not divide into %d frames"
				% [path, tex.get_width(), frames])

	# Anything that DRAWS an enemy body has to page the strip, not stretch it.
	# The menu backdrop is the one place outside the actors that does, and it
	# rendered every slime four frames wide until this was caught by looking at
	# the running game - no assertion in the suite would have noticed.
	var deco := Node2D.new()
	deco.set_script(load("res://ui/menu_backdrop.gd"))
	add_child(deco)
	var checked := 0
	for child: Node in deco.get_children():
		var spr := child as Sprite2D
		if spr == null or spr.texture == null:
			continue
		if not String(spr.texture.resource_path).contains("enemy_"):
			continue
		checked += 1
		_check(spr.hframes == 4,
			"a menu backdrop slime has hframes=%d - it will draw the whole "
				% spr.hframes + "walk strip instead of one frame")
	_check(checked > 0, "found no enemy sprites in the menu backdrop to check")
	deco.queue_free()

	# the boss pose tables have to agree with the strip the art tool emits
	_check(Boss.POSE_SQUASH.size() == Boss.POSE_COUNT,
		"boss pose squash table does not cover every frame")
	_check(Boss.POSE_STRETCH.size() == Boss.POSE_COUNT,
		"boss pose stretch table does not cover every frame")
	for v: float in Boss.POSE_SQUASH:
		_check(v <= 1.0,
			"a boss pose stretches past full height - the strip is anchored at "
			+ "the feet, so anything over 1.0 crops the top of the sprite")


## Thief and Mimic: the two that go after something other than your health.
func _test_thief_and_mimic() -> void:
	var thief := EnemyTypes.get_def(EnemyTypes.TEAL)
	var mimic := EnemyTypes.get_def(EnemyTypes.PALE)
	_check(thief.has("steal"), "the Thief has nothing to steal with")
	_check(mimic.has("disguise_range"), "the Mimic has no reveal range")

	var scene: PackedScene = load("res://actors/enemy.tscn")

	# --- theft is bounded by what the player actually has -------------------
	#
	# The run has to exist first. Without it Game.run is null, the assignment
	# below errors, _steal() returns early on its own null guard, and this whole
	# block asserts nothing while still reporting a pass - which is exactly what
	# it did until this was caught.
	var had_run := Game.run != null
	if not had_run:
		Game.start_run(4242)
	_check(Game.run != null, "could not start a run to test theft against")

	var t: Enemy = scene.instantiate()
	add_child(t)
	t.configure(EnemyTypes.TEAL, 20)
	var before := t.money_value
	Game.run.money = 12                      # less than the steal range
	t.call("_steal")
	_check(Game.run.money == 0,
		"a Thief left %d behind - theft should be capped at what you have"
			% Game.run.money)
	_check(t.money_value == before + 12,
		"a Thief's haul did not go onto its payout, so killing it loses the money")

	# ...and it cannot take from an empty purse, or the balance goes negative
	Game.run.money = 0
	var t2: Enemy = scene.instantiate()
	add_child(t2)
	t2.configure(EnemyTypes.TEAL, 20)
	t2.call("_steal")
	_check(Game.run.money == 0, "a Thief pushed the balance to %d" % Game.run.money)
	_check(int(t2.get("_stolen")) == 0, "a Thief claimed a haul it never took")
	t2.die(false)
	t2.queue_free()

	t.die(false)
	t.queue_free()
	if not had_run:
		Game.abandon_run()

	# --- a Mimic must come back from the pool undisguised -------------------
	var m: Enemy = scene.instantiate()
	add_child(m)
	m.configure(EnemyTypes.PALE, 20)
	_check(bool(m.get("_disguised")), "a Mimic did not spawn disguised")
	_check(not m.get_node("Visual/Body/Face").visible,
		"a disguised Mimic is showing its face")
	_check(not m.get_node("Visual/Body/Badge").visible,
		"a disguised Mimic is showing its marker, which gives the trap away")

	# reveal, then recycle as an ordinary slime
	m.call("_reveal")
	_check(not bool(m.get("_disguised")), "a Mimic did not reveal")
	_check(m.get_node("Visual/Body/Face").visible,
		"a revealed Mimic has no face - it is a threat now and must read as one")
	m.configure(EnemyTypes.GREEN, 20)
	_check(not bool(m.get("_disguised")),
		"a recycled Mimic came back still disguised")
	_check(m.get_node("Visual/Body").hframes == 4,
		"a recycled Mimic kept a pickup's frame count instead of the walk cycle")
	_check(m.get_node("Visual/Body/Face").visible,
		"a recycled Mimic came back faceless")
	m.die(false)
	m.queue_free()


## The Warded/Carapace pair: the first enemies that refuse a whole damage
## source, so the first that can make a wave unclearable if they are wrong.
func _test_adaptation_pair() -> void:
	var warded := EnemyTypes.get_def(EnemyTypes.VIOLET)
	var carapace := EnemyTypes.get_def(EnemyTypes.GREY)

	# they only work as a pair - one of each source, or a single build is
	# punished and the other never has to adapt at all
	_check(String(warded["immune_to"]) == Combat.SOURCE_ABILITY,
		"Warded must be the ability-immune half of the pair")
	_check(String(carapace["immune_to"]) == Combat.SOURCE_BULLET,
		"Carapace must be the bullet-immune half of the pair")

	# no type may be immune to SOURCE_OTHER: that is the untagged default, and
	# a type immune to it would shrug off Bloater splash and anything added
	# later that forgets to declare a source
	for id: String in EnemyTypes.ORDER:
		var imm := String(EnemyTypes.get_def(id).get("immune_to", ""))
		_check(imm != Combat.SOURCE_OTHER,
			"%s is immune to the untagged default source" % id)

	# The anti-softlock guarantee. A Surge/Barrier/Heal loadout deals no
	# ability damage at all, so a permanently bullet-proof enemy in that run
	# could never be killed and the wave could never end. Carapace's shell must
	# cycle; Warded needs no such escape hatch because the player always has a
	# gun.
	_check(float(carapace.get("shell_up", 0.0)) > 0.0
			and float(carapace.get("shell_down", 0.0)) > 0.0,
		"the bullet-immune type must open its shell, or a no-ability run hangs")
	_check(not warded.has("shell_up"),
		"Warded should not shell - its immunity is meant to be constant")

	# and the behaviour itself, on a real enemy rather than the table
	var scene: PackedScene = load("res://actors/enemy.tscn")
	_check_immunity(scene, EnemyTypes.VIOLET)
	_check_immunity(scene, EnemyTypes.GREY)


## Spawn one and shoot it, with each source in turn.
func _check_immunity(scene: PackedScene, id: String) -> void:
	var e: Enemy = scene.instantiate()
	add_child(e)
	e.configure(id, 20)
	var name_of := String(EnemyTypes.get_def(id)["name"])

	# the source it is immune to does nothing at all
	var before := e.hp
	e.take_damage(25.0, false, Vector2.ZERO, 0.0, String(e.immune_to))
	_check(e.hp == before,
		"%s took damage from %s, which it is immune to" % [name_of, e.immune_to])

	# the other source, and the untagged default, both land
	var other := (Combat.SOURCE_BULLET if e.immune_to == Combat.SOURCE_ABILITY
		else Combat.SOURCE_ABILITY)
	e.take_damage(25.0, false, Vector2.ZERO, 0.0, other)
	_check(e.hp < before, "%s shrugged off %s, which should hurt it"
		% [name_of, other])

	before = e.hp
	e.take_damage(25.0, false, Vector2.ZERO, 0.0, Combat.SOURCE_OTHER)
	_check(e.hp < before,
		"%s shrugged off untagged damage - Bloater splash must always land"
			% name_of)

	e.die(false)
	e.queue_free()


## Every shop entry must apply cleanly, and no run may exceed the stat caps.
func _test_gun_upgrades() -> void:
	for id: String in UpgradesDB.DEFS:
		var rs := RunState.new()
		var before := rs.stat_value(UpgradesDB.get_def(id)["stat"])
		var ok := rs.apply_upgrade(id)
		_check(ok, "upgrade '%s' failed to apply" % id)
		var after := rs.stat_value(UpgradesDB.get_def(id)["stat"])
		if UpgradesDB.get_def(id)["stat"] != "heal_full":
			_check(not is_equal_approx(before, after),
				"upgrade '%s' changed nothing" % id)

	# stacking one upgrade 50 times must respect the caps
	var stacked := RunState.new()
	for i in 50:
		stacked.apply_upgrade("fire_rate")
		stacked.apply_upgrade("crit_chance")
		stacked.apply_upgrade("proj_count")
		stacked.apply_upgrade("penetration")
		stacked.apply_upgrade("reload")
		stacked.apply_upgrade("accuracy")
		stacked.apply_upgrade("armor")
		stacked.apply_upgrade("move_speed")
	_check(float(stacked.gun["fire_rate"]) <= float(Balance.GUN_CAPS["fire_rate"]) + 0.001,
		"fire rate broke its cap")
	_check(float(stacked.gun["crit_chance"]) <= float(Balance.GUN_CAPS["crit_chance"]) + 0.001,
		"crit chance broke its cap")
	_check(float(stacked.gun["projectile_count"]) <= float(Balance.GUN_CAPS["projectile_count"]) + 0.001,
		"projectile count broke its cap")
	_check(float(stacked.gun["reload_time"]) >= float(Balance.GUN_CAPS["reload_time"]) - 0.001,
		"reload time dropped below its floor")
	_check(float(stacked.gun["spread"]) >= float(Balance.GUN_CAPS["spread"]) - 0.001,
		"spread dropped below its floor")
	_check(stacked.damage_reduction <= 0.7001,
		"damage reduction reached total immunity")

	# an upgraded gun must actually feel stronger
	var fresh := RunState.new()
	var built := RunState.new()
	for i in 8:
		built.apply_upgrade("dmg_small")
		built.apply_upgrade("fire_rate")
	_check(built.effective_dps() > fresh.effective_dps() * 2.5,
		"eight damage and eight fire-rate upgrades barely moved DPS")


func _test_upgrade_pricing() -> void:
	for id: String in UpgradesDB.DEFS:
		var first := UpgradesDB.price(id, 0)
		var fourth := UpgradesDB.price(id, 3)
		_check(first > 0, "upgrade '%s' is free" % id)
		if UpgradesDB.get_def(id).get("repeatable_price", true):
			_check(fourth > first,
				"stacking '%s' does not get more expensive" % id)

	# the shop pool must offer real breadth
	var categories := {}
	for id: String in UpgradesDB.DEFS:
		categories[UpgradesDB.get_def(id)["cat"]] = true
	_check(categories.size() >= 5,
		"only %d upgrade categories - builds will not diverge" % categories.size())
	_check(UpgradesDB.DEFS.size() >= 20,
		"the shop pool is too small for varied runs")

	# locked entries must stay out of the pool until unlocked
	var locked_id := "proj_count"
	_check(not UpgradesDB.available_ids([]).has(locked_id),
		"'%s' is available without its meta unlock" % locked_id)
	_check(UpgradesDB.available_ids([UpgradesDB.META_LOCKED[locked_id]]).has(locked_id),
		"'%s' stays locked after buying its unlock" % locked_id)


func _test_economy() -> void:
	# every enemy pays something, and the colours pay differently
	var payouts := {}
	for id: String in EnemyTypes.ORDER:
		var money: Vector2i = EnemyTypes.get_def(id)["money"]
		_check(money.x > 0 and money.y >= money.x, "%s has a broken payout" % id)
		payouts[id] = money.x
	_check(int(payouts[EnemyTypes.YELLOW]) > int(payouts[EnemyTypes.GREEN]) * 3,
		"yellow Hoarders should be worth chasing")
	_check(int(payouts[EnemyTypes.RED]) > int(payouts[EnemyTypes.GREEN]),
		"red brutes should pay more than green slimes")

	var rs := RunState.new()
	rs.add_money(100)
	_check(rs.money == 100, "money was not credited")
	_check(rs.spend_money(40), "a valid purchase was refused")
	_check(rs.money == 60, "money was not debited correctly")
	_check(not rs.spend_money(1000), "an unaffordable purchase went through")
	_check(rs.money == 60, "a refused purchase still took money")

	# money grows more slowly than costs, so choices stay tight
	_check(Balance.money_scale(20) < 3.0,
		"payouts inflate too fast for the shop to stay meaningful")


func _test_potions() -> void:
	for wave in range(1, 60):
		for hp in [0.05, 0.3, 0.5, 1.0]:
			var chance := Balance.potion_chance(wave, hp, false)
			_check(chance >= 0.0 and chance <= Balance.POTION_MAX_CHANCE + 0.0001,
				"potion chance out of bounds at wave %d hp %.2f" % [wave, hp])

	# hurt players see more health potions - but the guard must shut that off,
	# or low HP becomes a farm
	var hurt := Balance.potion_chance(10, 0.2, false)
	var healthy := Balance.potion_chance(10, 1.0, false)
	var guarded := Balance.potion_chance(10, 0.2, true)
	_check(hurt > healthy, "being hurt does not improve potion odds")
	_check(guarded < hurt, "the anti-farm guard does not reduce the bonus")
	_check(is_equal_approx(guarded, healthy),
		"the guard should remove the low-HP bonus entirely")
	_check(Balance.POTION_MAX_CHANCE < 0.35,
		"potions drop too often to feel valuable")


func _test_save_roundtrip() -> void:
	var original := Save.to_dict()

	Save.essence = 1234
	Save.unlocks = ["ab_shield", "pas_vigor_1"]
	Save.seen_hints = ["hint_move"]
	Save.stats["best_wave"] = 42
	Save.settings["music_volume"] = 0.42
	Save.settings["damage_numbers"] = false
	Save.loadout = ["dash", "nova", "grenade"]

	var snapshot := Save.to_dict().duplicate(true)
	Save.from_dict(snapshot)

	_check(Save.essence == 1234, "essence did not survive the round trip")
	_check(Save.unlocks.has("ab_shield"), "unlocks did not survive the round trip")
	_check(Save.seen_hints.has("hint_move"), "hints did not survive the round trip")
	_check(int(Save.stats["best_wave"]) == 42, "stats did not survive the round trip")
	_close(float(Save.settings["music_volume"]), 0.42, "settings float lost")
	_check(bool(Save.settings["damage_numbers"]) == false, "settings bool lost")

	# corrupt input must not throw
	Save.from_dict({})
	Save.from_dict({"unlocks": "not an array", "stats": {"best_wave": "x"}})
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT,
		"loadout survived corrupt input at wrong size")

	# A version-1 save binds ability_1 to Space, which is now the movement slot's
	# key. Carrying that override forward would leave two actions on one key and
	# fire two slots per press, so loading an old save must drop it.
	Save.from_dict({
		"version": 1,
		"keybinds": {
			"ability_1": [{"type": "key", "physical": 32}],
			"ability_2": [{"type": "key", "physical": 4194325}],
			"shoot": [{"type": "mouse", "button": 1}],
		},
	})
	_check(not Save.keybinds.has("ability_1"),
		"a version-1 ability binding survived the migration and now collides "
		+ "with the movement key")
	_check(not Save.keybinds.has("ability_2"),
		"a version-1 ability binding survived the migration")
	_check(Save.keybinds.has("shoot"),
		"the migration threw away bindings it had no business touching")

	# A current save keeps its bindings.
	Save.from_dict({
		"version": Save.VERSION,
		"keybinds": {"ability_1": [{"type": "key", "physical": 81}]},
	})
	_check(Save.keybinds.has("ability_1"),
		"a current-version ability binding was wrongly discarded")

	Save.from_dict(original)


## The slot rules are load-bearing for build variety, so they are enforced
## rather than assumed. In particular a movement ability must never reach a
## general slot: that is the whole reason the classes exist.
func _test_loadout() -> void:
	var original_unlocks := Save.unlocks.duplicate()
	var original_loadout := Save.loadout.duplicate()

	Save.unlocks = []
	_check(Save.unlocked_abilities() == AbilitiesDB.default_unlocked(),
		"a fresh save should only have the default abilities")
	_check(AbilitiesDB.default_unlocked().size() == AbilitiesDB.SLOT_COUNT,
		"a fresh save must have one free ability per slot, or a slot starts empty")

	# one free ability of the right class for every slot
	for slot in AbilitiesDB.SLOT_COUNT:
		_check(not Save.unlocked_for_slot(slot).is_empty(),
			"slot %d has nothing legal to put in it on a fresh save" % slot)

	# asking for a locked ability must be refused
	Save.loadout = ["dash", "grenade", "nova"]
	Save.set_loadout(1, "orbital")
	_check(not Save.loadout.has("orbital"), "equipped a locked ability")

	# unlocking makes it available
	Save.unlocks = ["ab_orbital"]
	Save.set_loadout(1, "orbital")
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT,
		"loadout is not exactly one ability per slot")
	_check(Save.loadout[1] == "orbital", "the chosen ability was not equipped")
	_check(Save.loadout[0] == "dash", "the movement slot was disturbed")

	# picking the ability already in another slot swaps, never duplicates
	Save.set_loadout(2, "orbital")
	_check(Save.loadout[1] != Save.loadout[2],
		"the same ability ended up in two slots")
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT, "loadout grew a slot")

	# the class rule, from both directions
	Save.loadout = ["dash", "grenade", "nova"]
	Save.set_loadout(1, "dash")
	_check(Save.loadout[1] != "dash", "a movement ability reached a general slot")
	Save.set_loadout(0, "grenade")
	_check(Save.loadout[0] == "dash", "a general ability reached the movement slot")

	# a pre-movement-slot save is the right length but the wrong shape
	Save.from_dict({"unlocks": [], "loadout": ["dash", "grenade"]})
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT,
		"an old two-entry loadout was not padded to the slot count")
	for slot in AbilitiesDB.SLOT_COUNT:
		_check(AbilitiesDB.fits_slot(Save.loadout[slot], slot),
			"slot %d holds the wrong class after migration" % slot)

	# sanitising junk still yields one distinct unlocked ability per slot
	Save.from_dict({"unlocks": [], "loadout": ["orbital", "orbital", "dash", "dash"]})
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT,
		"sanitised loadout is the wrong size")
	var seen: Array[String] = []
	for slot in AbilitiesDB.SLOT_COUNT:
		var id: String = Save.loadout[slot]
		_check(not seen.has(id), "sanitised loadout duplicated '%s'" % id)
		seen.append(id)
		_check(AbilitiesDB.fits_slot(id, slot),
			"sanitised loadout put '%s' in the wrong class of slot" % id)
		_check(Save.unlocked_abilities().has(id),
			"sanitised loadout contains locked ability '%s'" % id)

	# every ability must be reachable, well formed and correctly classed
	_check(AbilitiesDB.ORDER.size() == 14, "expected fourteen abilities")
	var movement := 0
	for id: String in AbilitiesDB.ORDER:
		var def := AbilitiesDB.get_def(id)
		_check(float(def["cooldown"]) > 0.0, "ability '%s' has no cooldown" % id)
		_check(int(def["charges"]) >= 1, "ability '%s' has no charges" % id)
		_check(ResourceLoader.exists(AbilitiesDB.icon_path(id)),
			"ability '%s' has no icon" % id)
		var kind: String = def["class"]
		_check(kind == AbilitiesDB.CLASS_MOVEMENT or kind == AbilitiesDB.CLASS_GENERAL,
			"ability '%s' has no valid class" % id)
		if kind == AbilitiesDB.CLASS_MOVEMENT:
			movement += 1
	_check(movement >= 2,
		"one movement ability is not a choice - the slot needs alternatives")

	Save.unlocks = original_unlocks
	Save.loadout = original_loadout


func _test_meta_progression() -> void:
	var original_essence := Save.essence
	var original_unlocks := Save.unlocks.duplicate()

	Save.essence = 0
	Save.unlocks = []
	_check(not Save.can_purchase("ab_shield"), "bought an unlock with no essence")

	Save.essence = 100_000
	_check(Save.can_purchase("ab_shield"), "a affordable unlock was refused")
	_check(not Save.can_purchase("pas_vigor_2"),
		"a tiered passive ignored its prerequisite")
	Save.purchase("pas_vigor_1")
	_check(Save.can_purchase("pas_vigor_2"),
		"the prerequisite did not unlock the next tier")
	_check(not Save.can_purchase("pas_vigor_1"), "an owned unlock can be rebought")

	# passives must feed into a fresh run
	Save.unlocks = ["pas_vigor_1", "pas_purse_1", "pas_edge_1", "pas_attune"]
	var rs := RunState.create(1, Save.unlocks, ["dash", "grenade"])
	_check(rs.max_hp > Balance.PLAYER_MAX_HP, "the Vigor passive did nothing")
	_check(rs.money > 0, "the starting-money passive did nothing")
	_check(float(rs.gun["damage"]) > float(Balance.GUN_BASE["damage"]),
		"the starting-damage passive did nothing")
	_check(rs.essence_multiplier() > 1.0, "the Essence passive did nothing")
	_check(rs.hp == rs.max_hp, "a run did not start at full health")

	# ...and must be modest, so unlocks widen the game rather than trivialise it
	_check(rs.max_hp < Balance.PLAYER_MAX_HP * 1.6,
		"starting health bonuses are large enough to remove the challenge")

	# every unlock must be buyable and describable
	for id: String in MetaDB.ORDER:
		_check(MetaDB.DEFS.has(id), "MetaDB.ORDER lists unknown id '%s'" % id)
		_check(int(MetaDB.DEFS[id]["cost"]) > 0, "unlock '%s' is free" % id)
		_check(not MetaDB.display_name(id).is_empty(), "unlock '%s' has no name" % id)
		_check(not MetaDB.description(id).is_empty(), "unlock '%s' has no description" % id)
	_check(MetaDB.ORDER.size() == MetaDB.DEFS.size(),
		"some unlocks are defined but never shown in the upgrade screen")

	# essence must be earned for any run, and more for a longer one
	var short_run := Balance.essence_for_run(3, 0, 0)
	var long_run := Balance.essence_for_run(25, 4, 1)
	_check(short_run > 0, "a short run earns nothing at all")
	_check(long_run > short_run * 4, "a long run barely out-earns a short one")

	Save.essence = original_essence
	Save.unlocks = original_unlocks


## A small sweep here; tests/test_forest.gd runs the full 200-seed version.
##
## Run for EVERY biome, not just the default. Each biome swaps the prop tables
## the generator scatters from, so each is a fresh chance to author a table
## that produces a map the player cannot walk - and the whole point of these
## assertions is that a generated forest is always playable.
func _test_forest_smoke() -> void:
	for biome: String in BiomeDB.ORDER:
		for i in 12:
			var g := ForestGenerator.generate(5000 + i * 313, biome)
			var tag := "%s seed %d" % [biome, g.seed_value]
			_check(g.failure.is_empty(), "%s degraded: %s" % [tag, g.failure])
			_check(g.is_open(g.spawn_point), "%s spawns inside an obstacle" % tag)
			_check(g.spawn_zones.size() > 50, "%s has too few spawn zones" % tag)
			_check(g.clearings.size() >= ForestGenerator.CLEARING_MIN,
				"%s generated too few clearings" % tag)
			# a boss must fit somewhere near the player
			var boss_spot := g.nearest_open_for(g.spawn_point + Vector2(620, 0), 240.0)
			_check(g.has_clearance(boss_spot, 240.0),
				"%s has nowhere for a boss to stand" % tag)


## The five biomes, and the promise the HUD has been making since launch.
func _test_biomes() -> void:
	_check(BiomeDB.ORDER.size() == 5, "expected five biomes")
	_check(BiomeDB.DEFS.size() == BiomeDB.ORDER.size(),
		"a biome is declared but not in ORDER, or the other way round")

	# Depth is 1-based and the run never ends, so both ends must be safe.
	_check(BiomeDB.id_for_depth(0) == BiomeDB.ORDER[0],
		"depth 0 should clamp to the first biome")
	_check(BiomeDB.id_for_depth(1) == BiomeDB.GREENWOOD, "depth 1 is not Greenwood")
	_check(BiomeDB.id_for_depth(999) == BiomeDB.ORDER[-1],
		"the deepest biome must hold forever - the run has no last wave")

	# Never goes backwards, and every biome is actually reachable by play.
	var seen := {}
	var previous := -1
	for depth in range(1, 40):
		var idx := BiomeDB.ORDER.find(BiomeDB.id_for_depth(depth))
		_check(idx >= previous, "the biome went backwards at depth %d" % depth)
		previous = idx
		seen[BiomeDB.id_for_depth(depth)] = true
	_check(seen.size() == BiomeDB.ORDER.size(),
		"only %d of %d biomes are reachable" % [seen.size(), BiomeDB.ORDER.size()])

	# All five are met by wave 21, so dying at wave 15 still shows three of
	# them. A biome nobody reaches is content that does not exist.
	_check(BiomeDB.id_for_depth(Game.depth_for_wave(21)) == BiomeDB.ORDER[-1],
		"the last biome should be reached by wave 21")

	# Greenwood teaches; it does not also test.
	_check(String(BiomeDB.get_def(BiomeDB.GREENWOOD)["hazard"]) == BiomeDB.HAZARD_NONE,
		"the first biome must have no hazard - it is where the game is taught")

	var hazards := {}
	var implemented := _terrain_hazard_names()
	for id: String in BiomeDB.ORDER:
		var def := BiomeDB.get_def(id)
		for key: String in ["name", "ground", "trees", "scatter", "clearing",
				"detail", "hazard", "ponds", "prop_tint"]:
			_check(def.has(key), "%s declares no '%s'" % [id, key])

		# four ground slots, always, and each pointing at a real texture
		var ground: Dictionary = def["ground"]
		for slot: String in ["grass", "clearing", "path", "water"]:
			_check(ground.has(slot), "%s has no '%s' ground" % [id, slot])
			_check(ResourceLoader.exists(BiomeDB.ground_path(id, slot)),
				"%s '%s' ground texture is missing: %s"
					% [id, slot, BiomeDB.ground_path(id, slot)])

		# every prop a biome scatters has to exist in the catalogue
		for table: String in ["trees", "scatter", "clearing", "detail"]:
			var weights: Dictionary = def[table]
			_check(not weights.is_empty(), "%s has an empty '%s' table" % [id, table])
			for prop: String in weights:
				_check(PropCatalog.DEFS.has(prop),
					"%s '%s' names an unknown prop '%s'" % [id, table, prop])

		var hazard := String(def["hazard"])
		if hazard != BiomeDB.HAZARD_NONE:
			_check(not hazards.has(hazard),
				"%s and %s share the hazard '%s'" % [id, hazards.get(hazard, "?"), hazard])
			hazards[hazard] = id
			# A hazard nothing implements is a biome that quietly does nothing.
			_check(implemented.has(hazard),
				"%s names hazard '%s', which nothing applies" % [id, hazard])
			# ...and it needs somewhere to happen
			var ponds: Vector2i = def["ponds"]
			if hazard != BiomeDB.HAZARD_GLOOM:
				_check(ponds.x >= 1,
					"%s can generate zero hazard zones, so its hazard may never fire" % id)


## Hazard ids the game can actually act on, read out of the source rather than
## restated here, so the test cannot drift away from what it guards.
##
## Only *dispatch* counts. An earlier version of this searched each file for
## the constant anywhere, which meant deleting a hazard's match arm still
## passed - the id was still mentioned on a line that merely picked its damage
## number. A guard that cannot fail is worse than no guard, because it is
## trusted. So: match arms in Run._tick_terrain, and an explicit comparison in
## the HUD for gloom, which is a screen effect rather than a place to stand.
func _terrain_hazard_names() -> Dictionary:
	var out := {}
	var ids: Array[String] = [BiomeDB.HAZARD_WATER, BiomeDB.HAZARD_FIRE,
		BiomeDB.HAZARD_GLOOM, BiomeDB.HAZARD_BRAMBLE]

	var run_src := _read_source("res://world/run.gd")
	for line: String in run_src.split("\n"):
		var trimmed := line.strip_edges()
		# a match arm: "BiomeDB.HAZARD_X:" or "BiomeDB.HAZARD_X, BiomeDB.HAZARD_Y:"
		if not trimmed.ends_with(":") or not trimmed.begins_with("BiomeDB.HAZARD_"):
			continue
		for id: String in ids:
			if trimmed.contains(_hazard_const(id)):
				out[id] = true

	var hud_src := _read_source("res://ui/hud.gd")
	if hud_src.contains("== BiomeDB." + _hazard_const(BiomeDB.HAZARD_GLOOM)):
		out[BiomeDB.HAZARD_GLOOM] = true
	return out


## "water_slow" -> "HAZARD_WATER"; the constant name the code refers to it by.
func _hazard_const(id: String) -> String:
	return "HAZARD_" + id.to_upper().split("_")[0]


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_check(false, "could not read %s" % path)
		return ""
	var text := f.get_as_text()
	f.close()
	return text


## The navigation grid and the physics wall must agree about where the arena
## ends.
##
## This is the grid half only. The grid already sealed the border band before
## the wall existed - _rasterise() force-blocks it - which is exactly why the
## escape bug was so easy to miss: spawning and steering behaved, while the
## player, who moves by physics rather than by the grid, walked straight out
## through a gap in the tree scatter. The physics half is covered in the visual
## pass, which can query real collision shapes.
##
## What this guards is the two staying consistent. If WALL_INSET ever grows past
## BORDER, the grid would call cells walkable that sit outside the physics wall,
## and enemies would spawn in a pocket the player can never reach.
func _test_arena_is_sealed() -> void:
	var size := ForestGenerator.WORLD_SIZE
	var inset := ForestGenerator.WALL_INSET
	for i in 24:
		var g := ForestGenerator.generate(9000 + i * 577)
		var leaks := 0
		# sample densely enough that a one-cell gap cannot hide between samples
		var step := ForestGenerator.CELL * 0.5
		var x := 0.0
		while x <= size.x:
			if g.is_open(Vector2(x, inset * 0.5)) \
					or g.is_open(Vector2(x, size.y - inset * 0.5)):
				leaks += 1
			x += step
		var y := 0.0
		while y <= size.y:
			if g.is_open(Vector2(inset * 0.5, y)) \
					or g.is_open(Vector2(size.x - inset * 0.5, y)):
				leaks += 1
			y += step
		_check(leaks == 0,
			"seed %d has %d walkable points outside the wall" % [g.seed_value, leaks])
		# and the spawn point must be comfortably inside it, not tucked in the band
		_check(g.spawn_point.x > inset and g.spawn_point.y > inset
				and g.spawn_point.x < size.x - inset
				and g.spawn_point.y < size.y - inset,
			"seed %d spawns the player outside the wall" % g.seed_value)


## Nightmare is one flag, threaded through three curves. Each has to actually
## move, and normal play has to be left exactly as it was.
func _test_nightmare() -> void:
	for wave in [1, 7, 20, 45]:
		_check(Balance.wave_budget(wave, true) > Balance.wave_budget(wave) * 1.3,
			"nightmare budget is not meaningfully higher at wave %d" % wave)
		_check(Balance.damage_scale(wave, true) > Balance.damage_scale(wave) * 1.3,
			"nightmare damage is not meaningfully higher at wave %d" % wave)
		_check(Balance.spawn_rate(wave, true) > Balance.spawn_rate(wave),
			"nightmare spawn rate is not higher at wave %d" % wave)
		# normal must be untouched by the parameter existing
		_close(Balance.wave_budget(wave, false), Balance.wave_budget(wave),
			"normal budget changed at wave %d" % wave)
		_close(Balance.damage_scale(wave, false), Balance.damage_scale(wave),
			"normal damage changed at wave %d" % wave)

	# the whole roster from wave 1, which is most of what makes the mode
	var night_one := EnemyTypes.unlocked_for_wave(1, true)
	_check(night_one.size() == EnemyTypes.ORDER.size(),
		"nightmare wave 1 offers %d of %d enemy types"
			% [night_one.size(), EnemyTypes.ORDER.size()])
	_check(night_one.has(EnemyTypes.ORANGE),
		"nightmare wave 1 is missing the Bloater, which normally unlocks at 15")
	_check(EnemyTypes.unlocked_for_wave(1) == [EnemyTypes.GREEN],
		"normal wave 1 stopped being green-only")
	_check(EnemyTypes.weights_for_wave(1, true).size() == EnemyTypes.ORDER.size(),
		"nightmare wave 1 weights do not cover the full roster")

	# end to end: a nightmare wave 1 really is built from the whole roster and
	# is materially bigger than the normal one
	var normal_one := WaveController.preview_composition(1, 4242, false)
	var night_comp := WaveController.preview_composition(1, 4242, true)
	_check(float(night_comp["budget"]) > float(normal_one["budget"]) * 1.3,
		"nightmare wave 1 is not built from a bigger budget")
	_check((night_comp["counts"] as Dictionary).size()
			>= (normal_one["counts"] as Dictionary).size(),
		"nightmare wave 1 draws from no more enemy types than normal")

	# and it has to pay, or nobody would choose it
	_check(Balance.essence_for_run(20, 3, 1, true)
			> Balance.essence_for_run(20, 3, 1), "nightmare pays no more essence")

	# the flag has to survive onto the run and into its summary
	var rs := RunState.create(1, [], ["dash", "grenade", "nova"], true)
	_check(rs.nightmare, "RunState dropped the nightmare flag")
	rs.wave = 12
	_check(bool(rs.summary()["nightmare"]),
		"the run summary dropped the nightmare flag")
	var normal := RunState.create(1, [], ["dash", "grenade", "nova"])
	_check(not normal.nightmare, "a normal run came back marked nightmare")


## Achievements resolve off permanent stats plus the run that just ended, and a
## save written before they existed has to load without losing anything.
func _test_achievements() -> void:
	for id: String in AchievementsDB.ORDER:
		var def := AchievementsDB.get_def(id)
		_check(not def.is_empty(), "achievement %s has no definition" % id)
		_check(not String(def["name"]).is_empty(), "achievement %s has no name" % id)
		_check(ResourceLoader.exists(AchievementsDB.icon_path(id)),
			"achievement %s points at a missing icon" % id)
	_check(AchievementsDB.ORDER.size() == AchievementsDB.DEFS.size(),
		"AchievementsDB.ORDER and DEFS disagree on how many there are")

	var blank := {}
	for key: String in Save.stats:
		blank[key] = 0

	# nothing is earned from nothing
	for id: String in AchievementsDB.ORDER:
		_check(not AchievementsDB.is_earned(id, blank, {}),
			"achievement %s is earned on a fresh save" % id)

	# feats need the run that just ended, and respect difficulty
	_check(AchievementsDB.is_earned("no_gods", blank,
			{"wave": 40, "nightmare": true}),
		"reaching wave 40 on nightmare did not earn No Gods")
	_check(not AchievementsDB.is_earned("no_gods", blank,
			{"wave": 40, "nightmare": false}),
		"reaching wave 40 on normal wrongly earned a nightmare achievement")
	_check(not AchievementsDB.is_earned("unmaker", blank,
			{"wave": 99, "nightmare": true}),
		"Unmaker was earned one wave early")

	# "every boss" needs every counter, not just a total
	var most := blank.duplicate()
	for key: String in AchievementsDB.BOSS_STAT_KEYS:
		most[key] = 1
	_check(AchievementsDB.is_earned("clean_sweep", most, {}),
		"beating every boss did not earn Clean Sweep")
	most["boss_sovereign"] = 0
	_check(not AchievementsDB.is_earned("clean_sweep", most, {}),
		"Clean Sweep was earned with a boss still unbeaten")

	# a version-2 save has to load into version 3 with its stats intact
	var v2 := {
		"version": 2,
		"essence": 410,
		"unlocks": ["ab_surge"],
		"loadout": ["dash", "grenade", "nova"],
		"stats": {"runs": 9, "best_wave": 24, "total_kills": 1200,
			"total_money": 700, "minis_killed": 4, "majors_killed": 1},
		"settings": {},
		"keybinds": {},
	}
	var essence_before := Save.essence
	var stats_before := Save.stats.duplicate()
	var achievements_before := Save.achievements.duplicate()
	Save.from_dict(v2)
	_check(Save.essence == 410, "a version-2 save lost its essence")
	_check(int(Save.stats["best_wave"]) == 24, "a version-2 save lost best_wave")
	_check(int(Save.stats["total_kills"]) == 1200, "a version-2 save lost kills")
	_check(int(Save.stats["boss_bramble"]) == 0,
		"a version-2 save did not default the new per-boss counters to zero")
	_check(Save.achievements.is_empty(),
		"a version-2 save came back with achievements it never earned")
	# and the new fields round-trip
	Save.achievements = ["first_blood"]
	Save.stats["boss_toad"] = 2
	var round_trip := Save.to_dict()
	_check(int(round_trip["version"]) == 4, "to_dict did not write version 4")
	Save.from_dict(round_trip)
	_check(Save.achievements.has("first_blood"), "achievements did not round-trip")
	_check(int(Save.stats["boss_toad"]) == 2, "per-boss counters did not round-trip")

	# --- v4: Leech removed, its Essence refunded --------------------------
	#
	# A player who spent 280 Essence on Leech must get it back, exactly once,
	# and a loadout still holding it must come back playable rather than with
	# an empty slot.
	var v3 := {
		"version": 3,
		"essence": 100,
		"unlocks": ["ab_lifesteal", "ab_surge"],
		"loadout": ["dash", "lifesteal", "nova"],
		"stats": {}, "settings": {}, "keybinds": {}, "achievements": [],
	}
	Save.from_dict(v3)
	_check(Save.essence == 100 + Save.REMOVED_ABILITY_REFUND,
		"the Leech refund did not land - essence is %d, expected %d"
			% [Save.essence, 100 + Save.REMOVED_ABILITY_REFUND])
	_check(not Save.unlocks.has(Save.REMOVED_ABILITY_UNLOCK),
		"the removed ability's unlock survived the migration")
	_check(not Save.loadout.has(Save.REMOVED_ABILITY),
		"a loadout came back still holding the removed ability")
	_check(Save.loadout.size() == AbilitiesDB.SLOT_COUNT,
		"the loadout lost a slot instead of being repaired")
	for id: String in Save.loadout:
		_check(AbilitiesDB.DEFS.has(id),
			"the repaired loadout holds '%s', which is not an ability" % id)

	# The refund does not compound across a save/load round-trip.
	#
	# Note what this can and cannot prove. from_dict resets essence from the
	# dictionary before anything else, so re-loading the SAME old file lands on
	# the same number whether or not the refund is gated - that case is
	# idempotent by construction and no assertion can distinguish it. What is
	# worth guarding is the round-trip: save after migrating, load that, and
	# the refund must not be granted a second time on top of the new balance.
	var after_first := Save.essence
	var migrated := Save.to_dict()
	_check(bool(migrated.get("refunded_removed_ability", false)),
		"the migrated save does not record that the refund was paid")
	Save.from_dict(migrated)
	_check(Save.essence == after_first,
		"the refund compounded across a save/load - essence went %d to %d"
			% [after_first, Save.essence])
	_check(not Save.unlocks.has(Save.REMOVED_ABILITY_UNLOCK),
		"the removed unlock came back after a round-trip")

	Save.essence = essence_before
	Save.stats = stats_before
	Save.achievements = achievements_before


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------
func _report() -> void:
	print("\n=== logic tests ===")
	print("checks run: %d" % _checks)
	if _failures.is_empty():
		print("RESULT: PASS - all %d checks passed\n" % _checks)
		get_tree().quit(0)
	else:
		print("RESULT: FAIL - %d of %d checks failed" % [_failures.size(), _checks])
		for f: String in _failures:
			print("  " + f)
		print("")
		get_tree().quit(1)
