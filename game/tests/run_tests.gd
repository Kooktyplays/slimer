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
	_test_arena_is_sealed()
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
	_check(AbilitiesDB.ORDER.size() == 15, "expected fifteen abilities")
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
