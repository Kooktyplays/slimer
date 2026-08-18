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
	_test_gun_upgrades()
	_test_upgrade_pricing()
	_test_economy()
	_test_potions()
	_test_save_roundtrip()
	_test_loadout()
	_test_meta_progression()
	_test_forest_smoke()
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
	_check(Balance.spawn_rate(500) <= 7.5001, "spawn rate exceeded its cap")

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
	_check(behaviours.size() == 6, "expected six distinct enemy behaviours")

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
	Save.unlocks = ["ab_nova", "pas_vigor_1"]
	Save.seen_hints = ["hint_move"]
	Save.stats["best_wave"] = 42
	Save.settings["music_volume"] = 0.42
	Save.settings["damage_numbers"] = false
	Save.loadout = ["nova", "dash"]

	var snapshot := Save.to_dict().duplicate(true)
	Save.from_dict(snapshot)

	_check(Save.essence == 1234, "essence did not survive the round trip")
	_check(Save.unlocks.has("ab_nova"), "unlocks did not survive the round trip")
	_check(Save.seen_hints.has("hint_move"), "hints did not survive the round trip")
	_check(int(Save.stats["best_wave"]) == 42, "stats did not survive the round trip")
	_close(float(Save.settings["music_volume"]), 0.42, "settings float lost")
	_check(bool(Save.settings["damage_numbers"]) == false, "settings bool lost")

	# corrupt input must not throw
	Save.from_dict({})
	Save.from_dict({"unlocks": "not an array", "stats": {"best_wave": "x"}})
	_check(Save.loadout.size() == 2, "loadout survived corrupt input at wrong size")

	Save.from_dict(original)


## The two-slot rule is load-bearing for build variety, so it is enforced
## rather than assumed.
func _test_loadout() -> void:
	var original_unlocks := Save.unlocks.duplicate()
	var original_loadout := Save.loadout.duplicate()

	Save.unlocks = []
	_check(Save.unlocked_abilities() == AbilitiesDB.default_unlocked(),
		"a fresh save should only have the default abilities")

	# asking for a locked ability must be refused
	Save.loadout = ["dash", "grenade"]
	Save.set_loadout(0, "orbital")
	_check(not Save.loadout.has("orbital"), "equipped a locked ability")

	# unlocking makes it available, and equipping it swaps rather than adds
	Save.unlocks = ["ab_orbital"]
	Save.set_loadout(0, "orbital")
	_check(Save.loadout.size() == 2, "loadout is not exactly two abilities")
	_check(Save.loadout[0] == "orbital", "the chosen ability was not equipped")
	_check(Save.loadout[1] == "grenade", "the other slot was disturbed")

	# picking the ability already in the other slot swaps them, never duplicates
	Save.set_loadout(1, "orbital")
	_check(Save.loadout[0] != Save.loadout[1],
		"the same ability ended up in both slots")
	_check(Save.loadout.size() == 2, "loadout grew beyond two")

	# sanitising junk still yields two distinct unlocked abilities
	Save.from_dict({"unlocks": [], "loadout": ["orbital", "orbital", "nova"]})
	_check(Save.loadout.size() == 2, "sanitised loadout is not two entries")
	_check(Save.loadout[0] != Save.loadout[1], "sanitised loadout has duplicates")
	for id: String in Save.loadout:
		_check(Save.unlocked_abilities().has(id),
			"sanitised loadout contains locked ability '%s'" % id)

	# every ability must be reachable and distinct
	_check(AbilitiesDB.ORDER.size() == 11, "expected eleven abilities")
	for id: String in AbilitiesDB.ORDER:
		var def := AbilitiesDB.get_def(id)
		_check(float(def["cooldown"]) > 0.0, "ability '%s' has no cooldown" % id)
		_check(int(def["charges"]) >= 1, "ability '%s' has no charges" % id)
		_check(ResourceLoader.exists(AbilitiesDB.icon_path(id)),
			"ability '%s' has no icon" % id)

	Save.unlocks = original_unlocks
	Save.loadout = original_loadout


func _test_meta_progression() -> void:
	var original_essence := Save.essence
	var original_unlocks := Save.unlocks.duplicate()

	Save.essence = 0
	Save.unlocks = []
	_check(not Save.can_purchase("ab_nova"), "bought an unlock with no essence")

	Save.essence = 100_000
	_check(Save.can_purchase("ab_nova"), "a affordable unlock was refused")
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
func _test_forest_smoke() -> void:
	for i in 12:
		var g := ForestGenerator.generate(5000 + i * 313)
		_check(g.failure.is_empty(), "seed %d degraded: %s" % [g.seed_value, g.failure])
		_check(g.is_open(g.spawn_point), "seed %d spawns inside an obstacle" % g.seed_value)
		_check(g.spawn_zones.size() > 50, "seed %d has too few spawn zones" % g.seed_value)
		_check(g.clearings.size() >= ForestGenerator.CLEARING_MIN,
			"seed %d generated too few clearings" % g.seed_value)
		# a boss must fit somewhere near the player
		var boss_spot := g.nearest_open_for(g.spawn_point + Vector2(620, 0), 240.0)
		_check(g.has_clearance(boss_spot, 240.0),
			"seed %d has nowhere for a boss to stand" % g.seed_value)


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
