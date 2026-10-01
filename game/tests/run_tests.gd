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
	_test_harness_scripts()
	_test_animation()
	_test_thief_and_mimic()
	_test_corpses()
	_test_straggler_escalation()
	_test_second_wave_enemies()
	_test_written_text()
	_test_deadfall()
	_test_boss_stats()
	_test_sfx_stability()
	_test_font()
	_test_boss_phases()
	_test_boss_phase_bar()
	_test_kill_feedback()
	_test_boss_curve()
	_test_finale()
	_test_classes()
	_test_combo()
	_test_ability_upgrades()
	_test_ultimates()
	_test_timed_effects()
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
		if wave % 20 == 0 or Game.is_finale_wave(wave):
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

	# 10 on the every-20 cadence plus the finale, which took a wave that used to
	# be a mini. Updated deliberately: this assertion existing is what made the
	# schedule change visible instead of silent.
	_check(majors == 11, "expected 11 major bosses in 200 waves, got %d" % majors)
	_check(minis == 29, "expected 29 mini-bosses in 200 waves, got %d" % minis)

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

	# --- the paywall --------------------------------------------------------
	#
	# The default has to be free. It is what every save falls back to, so a
	# locked default would start runs as a character the player cannot use.
	_check(ClassesDB.is_free(ClassesDB.DEFAULT),
		"the default class is not free - a save falling back to it would start "
		+ "a run as a character the player does not own")
	_check(ClassesDB.DEFAULT == ClassesDB.WARRIOR, "the Warrior should be the free one")
	_check(ClassesDB.cost(ClassesDB.DEFAULT) == 0, "the free class has a price")

	for id: String in ClassesDB.ORDER:
		if id == ClassesDB.DEFAULT:
			continue
		var key := ClassesDB.unlock_id(id)
		_check(not key.is_empty(), "%s has no unlock id" % id)
		_check(MetaDB.DEFS.has(key), "%s's unlock '%s' is not in MetaDB" % [id, key])
		_check(MetaDB.DEFS[key]["kind"] == MetaDB.KIND_CLASS,
			"%s's unlock is not a class unlock" % id)
		_check(String(MetaDB.DEFS[key]["ref"]) == id,
			"%s's unlock points at a different class" % id)
		_check(ClassesDB.cost(id) > 0, "%s is locked but free" % id)
		# it must be buyable and describable, or the meta screen shows a blank
		_check(not MetaDB.display_name(key).is_empty(), "%s has no unlock name" % id)
		_check(not MetaDB.description(key).is_empty(), "%s has no unlock text" % id)
		_check(MetaDB.ORDER.has(key), "%s's unlock is never shown on the screen" % id)

	# ownership: only the free one, on a fresh save
	var owned_before := Save.unlocks.duplicate()
	var char_before := Save.character
	Save.unlocks = []
	_check(Save.owns_class(ClassesDB.DEFAULT), "the free class is not owned")
	_check(Save.owned_classes().size() == 1,
		"a fresh save owns %d classes, expected only the free one"
			% Save.owned_classes().size())
	for id: String in ClassesDB.ORDER:
		if id != ClassesDB.DEFAULT:
			_check(not Save.owns_class(id), "%s is owned without being bought" % id)

	# a save naming a class you do not own comes back as the free one
	Save.from_dict({"version": 5, "essence": 0, "unlocks": [],
		"character": ClassesDB.HERBALIST, "loadout": ["dash", "grenade", "nova"],
		"stats": {}, "settings": {}, "keybinds": {}, "achievements": []})
	_check(Save.character == ClassesDB.DEFAULT,
		"a save naming an unowned class came back as '%s'" % Save.character)

	Save.unlocks = owned_before
	Save.character = char_before

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

		# every class needs a face, and so does every skin
		_check(ResourceLoader.exists(ClassesDB.sprite_path(id)),
			"class %s has no sprite at %s" % [id, ClassesDB.sprite_path(id)])
		for skin: String in ClassesDB.skins_for(id):
			var sdef: Dictionary = ClassesDB.skins_for(id)[skin]
			for key: String in ["name", "cost", "desc"]:
				_check(sdef.has(key), "skin %s/%s has no '%s'" % [id, skin, key])
			_check(int(sdef["cost"]) > 0, "skin %s/%s is free" % [id, skin])
			var spath := ClassesDB.sprite_path(id, skin)
			_check(ResourceLoader.exists(spath),
				"skin %s/%s has no sprite at %s" % [id, skin, spath])
			# ...and it must not silently be the default's sprite
			_check(spath != ClassesDB.sprite_path(id),
				"skin %s/%s resolves to the default sprite" % [id, skin])

		# an unknown skin falls back rather than erroring
		_check(ClassesDB.sanitise_skin(id, "nonesuch") == ClassesDB.SKIN_DEFAULT,
			"an unknown skin for %s did not fall back" % id)

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

	# --- buying a skin ------------------------------------------------------
	var saved_essence := Save.essence
	var saved_unlocked := Save.skins_unlocked.duplicate()
	# The Warrior, because it is the free one - buying a skin for a locked
	# class is refused at the source now, which is a different assertion.
	var cls := ClassesDB.WARRIOR
	var skin: String = ClassesDB.skins_for(cls).keys()[0]
	var price := int(ClassesDB.skins_for(cls)[skin]["cost"])

	Save.skins_unlocked = []
	Save.essence = price - 1
	_check(not Save.buy_skin(cls, skin), "a skin was bought without enough essence")
	_check(Save.essence == price - 1, "a failed skin purchase still charged")

	Save.essence = price + 10
	_check(Save.buy_skin(cls, skin), "an affordable skin could not be bought")
	_check(Save.essence == 10, "buying a skin charged the wrong amount")
	_check(Save.has_skin(cls, skin), "a bought skin is not owned")
	_check(not Save.buy_skin(cls, skin), "the same skin was bought twice")
	_check(Save.essence == 10, "re-buying an owned skin charged again")
	_check(Save.has_skin(cls, ClassesDB.SKIN_DEFAULT),
		"the default skin has to be owned by everyone")

	# ...and a locked class cannot be dressed at all
	Save.essence = 99999
	var locked := ClassesDB.VAMPIRE
	var had_vampire := Save.unlocks.has(ClassesDB.unlock_id(locked))
	Save.unlocks.erase(ClassesDB.unlock_id(locked))
	_check(not Save.owns_class(locked), "the Vampire should be locked by default")
	_check(not Save.buy_skin(locked, ClassesDB.skins_for(locked).keys()[0]),
		"a skin was bought for a class the player does not own")
	if had_vampire:
		Save.unlocks.append(ClassesDB.unlock_id(locked))

	Save.essence = saved_essence
	Save.skins_unlocked = saved_unlocked

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


## Ability upgrades, which are what replaced in-run swapping.
##
## This test used to assert only that ability_bonus() returned a bigger number
## after a purchase - the bookkeeping, never the effect. Every assertion in it
## would still have passed with _upgraded() deleted, and it sat green while
## eight purchasable upgrades did nothing at all. It now drives the real code
## paths the game uses.
func _test_ability_upgrades() -> void:
	var loadout: Array[String] = ["dash", "grenade", "nova"]
	var rs := RunState.create(1, [], loadout, false, ClassesDB.WARDEN)
	var pool := UpgradesDB.available_ids([], ClassesDB.WARDEN, loadout)

	# --- nothing is offered that could not do anything ---------------------
	#
	# "+30% damage" was on sale for Dash, which has no damage. The player
	# cannot tell a dead row from a live one, so the shop must not print it.
	for ability: String in AbilitiesDB.ORDER:
		for kind: String in UpgradesDB.ABILITY_KINDS:
			var id := UpgradesDB.ability_upgrade_id(ability, kind)
			var offered := pool.has(id)
			var possible := (loadout.has(ability)
				and UpgradesDB.kind_applies(ability, kind))
			_check(offered == possible,
				"%s is %s but kind_applies says %s"
					% [id, "offered" if offered else "not offered", possible])

	_check(not UpgradesDB.kind_applies("dash", "sharpened"),
		"Dash has no damage, so a damage upgrade for it must not be sellable")
	_check(not UpgradesDB.kind_applies("heal", "widened"),
		"Bloom has no area or duration to widen")
	for ability: String in AbilitiesDB.ORDER:
		for kind: String in ["quickened", "doubled"]:
			_check(UpgradesDB.kind_applies(ability, kind),
				"%s should be sellable for every ability - cooldown and "
					% kind + "charges are on the slot, not the def")

	# --- the key lists have exactly one owner ------------------------------
	#
	# The bug was a producer and a consumer disagreeing about which keys scale.
	# A second copy in the controller is how that comes back.
	var ctl_src := _read_source("res://abilities/ability_controller.gd")
	for key: String in AbilitiesDB.POWER_KEYS:
		_check(not ctl_src.contains('"%s", "' % key),
			"the controller has its own copy of the power key list")

	# --- power and area reach the numbers the ability actually uses --------
	var ac := AbilityController.new()
	var run_before := Game.run
	Game.run = rs

	var raw := AbilitiesDB.get_def("grenade")
	var base: Dictionary = ac.call("_upgraded", "grenade", raw)
	_check(is_equal_approx(float(base["damage"]), float(raw["damage"])),
		"an unbought upgrade already changed the grenade")
	_check(rs.apply_upgrade(UpgradesDB.ability_upgrade_id("grenade", "sharpened")),
		"buying a sharpened upgrade failed")
	var up: Dictionary = ac.call("_upgraded", "grenade", raw)
	_check(float(up["damage"]) > float(raw["damage"]),
		"Sharpened Grenade did not raise the damage the grenade is thrown with")
	_check(is_equal_approx(float(
		(ac.call("_upgraded", "nova", AbilitiesDB.get_def("nova")))["damage"]),
		float(AbilitiesDB.get_def("nova")["damage"])),
		"sharpening the grenade also sharpened Nova")

	# Widened means a longer reach on a movement ability, not a longer one.
	# Scaling `duration` there stretches the TRAVEL TIME - the dash flies at
	# distance/duration - so it covered the same ground more slowly while
	# quietly granting 25% more invulnerability.
	rs.apply_upgrade(UpgradesDB.ability_upgrade_id("dash", "widened"))
	var dash_raw := AbilitiesDB.get_def("dash")
	var dash_up: Dictionary = ac.call("_upgraded", "dash", dash_raw)
	_check(float(dash_up["distance"]) > float(dash_raw["distance"]),
		"Widened Dash did not make the dash go further")
	_check(is_equal_approx(float(dash_up["duration"]), float(dash_raw["duration"])),
		"Widened Dash stretched the travel time - that slows the dash down "
		+ "and hands out invulnerability nothing advertised")
	# ...but on an ability where duration IS the effect, it still scales.
	rs.apply_upgrade(UpgradesDB.ability_upgrade_id("nova", "widened"))
	var nova_up: Dictionary = ac.call("_upgraded", "nova", AbilitiesDB.get_def("nova"))
	_check(float(nova_up["radius"]) > float(AbilitiesDB.get_def("nova")["radius"]),
		"Widened Nova did not widen anything")

	# --- and they reach a LIVE slot, mid-run -------------------------------
	#
	# The one that mattered most. cooldown and max_charges were worked out in
	# equip(), which runs once at run start; nothing recomputed them after a
	# purchase, so Quickened and Doubled - and Focused Mind and Deep Reserves -
	# changed a stored number that was never read again.
	ac.equip(0, "dash")
	var cd_before := float(ac.slots[0]["cooldown"])
	var max_before := int(ac.slots[0]["max_charges"])

	rs.apply_upgrade(UpgradesDB.ability_upgrade_id("dash", "quickened"))
	ac.refresh_upgrades()
	_check(float(ac.slots[0]["cooldown"]) < cd_before,
		"Quickened Dash did not shorten the live slot's cooldown")

	rs.apply_upgrade(UpgradesDB.ability_upgrade_id("dash", "doubled"))
	ac.refresh_upgrades()
	_check(int(ac.slots[0]["max_charges"]) > max_before,
		"Doubled Dash did not raise the live slot's charge cap")
	_check(int(ac.slots[0]["charges"]) == int(ac.slots[0]["max_charges"]),
		"a charge that was just paid for was not handed over")

	# the two general shop upgrades that feed the same numbers
	var cd_now := float(ac.slots[0]["cooldown"])
	rs.apply_upgrade("ability_cdr")
	ac.refresh_upgrades()
	_check(float(ac.slots[0]["cooldown"]) < cd_now,
		"Focused Mind did not shorten a live cooldown")
	var max_now := int(ac.slots[0]["max_charges"])
	rs.apply_upgrade("ability_charge")
	ac.refresh_upgrades()
	_check(int(ac.slots[0]["max_charges"]) > max_now,
		"Deep Reserves did not raise a live charge cap")

	# a cooldown already in flight must not outlast the shortened one
	ac.slots[0]["cooldown_left"] = 999.0
	ac.refresh_upgrades()
	_check(float(ac.slots[0]["cooldown_left"]) <= float(ac.slots[0]["cooldown"]),
		"a cooldown in flight survived the upgrade that shortened it")

	ac.free()
	Game.run = run_before

	# --- bookkeeping, which was all this test used to check ----------------
	_check(rs.ability_bonus("grenade", "power") > 1.0, "the bonus is not stored")
	var once := rs.ability_bonus("grenade", "power")
	rs.apply_upgrade(UpgradesDB.ability_upgrade_id("grenade", "sharpened"))
	_check(rs.ability_bonus("grenade", "power") > once,
		"a second sharpened upgrade did not stack")

	var rep := UpgradesDB.ability_upgrade_id("grenade", "sharpened")
	_check(rs.times_bought(rep) >= 2,
		"ability upgrade purchases are not recorded, so pricing never escalates")
	_check(UpgradesDB.price(rep, rs.times_bought(rep)) > UpgradesDB.price(rep, 0),
		"buying an ability upgrade twice did not make the third cost more")
	_check(not rs.apply_upgrade(UpgradesDB.ability_upgrade_id("cinders", "sharpened")),
		"an upgrade applied to an ability the run is not carrying")

	for id: String in pool:
		if not UpgradesDB.is_ability_upgrade(id):
			continue
		var d := UpgradesDB.any_def(id)
		for key: String in ["name", "cat", "desc", "cost", "weight"]:
			_check(d.has(key), "ability upgrade '%s' has no '%s'" % [id, key])
		_check(UpgradesDB.price(id, 0) > 0, "ability upgrade '%s' is free" % id)

	var shop_src := _read_source("res://ui/shop.gd")
	_check(not shop_src.contains("ability_picker"),
		"the shop still opens the ability picker - swapping was meant to go")


## The five ultimates, and the upgrades sold against them.
func _test_ultimates() -> void:
	# Every class is sold exactly one upgrade, and that upgrade has to feed
	# something its own ultimate reads.
	#
	# It did not. "Stubborn" is the Warrior's only class-specific purchase, it
	# sells ultimate_power, and the single ultimate in the game that read
	# ultimate_power belonged to the Engineer - who is sold ultimate_rate
	# instead. The stat was reachable by two classes and worked for neither.
	var ctl_src := _read_source("res://abilities/ability_controller.gd")
	for id: String in UpgradesDB.CLASS_UPGRADES:
		var owner_class: Variant = UpgradesDB.CLASS_LOCKED.get(id)
		_check(owner_class != null, "class upgrade '%s' is locked to nobody" % id)
		if owner_class == null:
			continue
		var stat := String(UpgradesDB.CLASS_UPGRADES[id]["stat"])
		if stat != "ultimate_power":
			continue        # ultimate_rate is applied centrally, in add_ultimate_charge
		var ult := String(ClassesDB.get_def(String(owner_class))["ultimate"])
		var fn := "func _ult_%s()" % ult
		var at := ctl_src.find(fn)
		_check(at > 0, "no handler named %s for the %s" % [fn, owner_class])
		if at <= 0:
			continue
		var body_end := ctl_src.find("\nfunc ", at)
		var body := ctl_src.substr(at, (body_end - at) if body_end > at else 400)
		_check(body.contains("ultimate_power"),
			"%s is sold '%s' (%s) and its ultimate never reads that stat - "
				% [owner_class, id, stat]
				+ "the upgrade is a dead purchase")

	# Last Stand's output must not shrink as the player gets tankier. It was
	# computed from the damage that got THROUGH, after the 45% cushion the
	# ultimate itself grants, so its defensive half cut its offensive half by
	# nearly half and the tankier the build the less it did.
	# Asserted by hitting the player and measuring what an enemy standing next
	# to them loses - not by reading the source. The first version of this
	# check searched for "_retaliate(amount)" and could not fail: the poison
	# path takes a parameter of the same name, so it matched there no matter
	# what take_damage did.
	var scene: PackedScene = load("res://actors/enemy.tscn")
	var had_run := Game.run != null
	if not had_run:
		Game.start_run(9182)
	var p_scene: PackedScene = load("res://actors/player.tscn")
	var pl: Player = p_scene.instantiate()
	add_child(pl)
	Game.run.max_hp = 100000.0
	Game.run.hp = Game.run.max_hp

	var lost := []
	for reduction: float in [0.0, 0.45]:
		var foe: Enemy = scene.instantiate()
		add_child(foe)
		foe.configure(EnemyTypes.GREEN, 1)
		foe.max_hp = 100000.0
		foe.hp = foe.max_hp
		foe.global_position = pl.global_position + Vector2(60, 0)

		pl.begin_retaliation(6.0, reduction)
		pl.invulnerable_until = 0.0
		pl.set("_retaliate_ready_at", 0.0)
		var before := foe.hp
		pl.take_damage(100.0)
		lost.append(before - foe.hp)

		foe.die(false, false)
		foe.queue_free()

	_check(lost[0] > 0.0, "Last Stand threw nothing back at all")
	_check(is_equal_approx(float(lost[0]), float(lost[1])),
		"Last Stand hit for %.0f with no mitigation and %.0f with 45%% off - "
			% [lost[0], lost[1]]
			+ "its own damage reduction is shrinking its own damage")
	pl.queue_free()
	if not had_run:
		Game.abandon_run()

	var player_src := _read_source("res://actors/player.gd")
	# ...and poison has to count. It bypasses take_damage on purpose - routing
	# a DoT through there grants i-frames - and that made the damage which
	# actually kills you in a crowd the one thing Last Stand could not answer.
	var poison_at := player_src.find("func _take_poison_damage")
	_check(poison_at > 0, "the poison damage path is gone")
	if poison_at > 0:
		var body := player_src.substr(poison_at, 600)
		_check(body.contains("_retaliate("),
			"poison does not retaliate, so Last Stand ignores the damage that "
			+ "actually kills a Warrior in a crowd")


## Timed effects must refresh rather than cancel each other.
##
## Five of them set a variable and restored it to a hardcoded default on a
## tween of their own, with no check that they were still the owner. Casting
## one inside another switched the first one off. The Notion doc records this
## exact shape being found and fixed for the Swift Potion and never generalised.
func _test_timed_effects() -> void:
	var scene: PackedScene = load("res://actors/player.tscn")
	var had_run := Game.run != null
	if not had_run:
		Game.start_run(31337)
	var p: Player = scene.instantiate()
	add_child(p)

	# --- damage reduction: Surge and Last Stand share one owner ------------
	p.apply_damage_reduction(0.45, 6.0)
	_check(is_equal_approx(p.bonus_damage_reduction, 0.45),
		"Last Stand did not apply its damage reduction")
	p.apply_damage_reduction(0.35, 3.5)          # Surge, inside Last Stand
	_check(is_equal_approx(p.bonus_damage_reduction, 0.45),
		"Surging during Last Stand lowered the mitigation to Surge's")
	_check(p.damage_reduction_left > 3.5,
		"Surging during Last Stand cut Last Stand's timer down to Surge's")
	p.call("_tick_damage_reduction", 4.0)
	_check(is_equal_approx(p.bonus_damage_reduction, 0.45),
		"the shorter effect's expiry cancelled the longer one")
	p.call("_tick_damage_reduction", 3.0)
	_check(is_equal_approx(p.bonus_damage_reduction, 0.0),
		"the damage reduction never expired")

	# --- Bulwark ----------------------------------------------------------
	p.apply_shield(120.0, 6.0)
	p.call("_tick_shield", 5.0)
	p.apply_shield(120.0, 6.0)                   # recast just before it lapses
	p.call("_tick_shield", 2.0)
	_check(p.shield_absorb > 0.0,
		"recasting Bulwark left the first cast's expiry to end the second one")

	p.queue_free()
	if not had_run:
		Game.abandon_run()

	# --- Torpor -----------------------------------------------------------
	Combat.reset()
	Combat.apply_slow(self, 0.35, 4.0)
	Combat.tick_slow(3.5)
	Combat.apply_slow(self, 0.35, 4.0)           # a second Torpor
	Combat.tick_slow(1.0)
	_check(Combat.enemy_time_scale < 1.0,
		"a second Torpor was cancelled by the first one's expiry")
	Combat.tick_slow(4.0)
	_check(is_equal_approx(Combat.enemy_time_scale, 1.0),
		"the slow never wore off")
	Combat.reset()


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
	for n: int in RunState.COMBO_TIER_THRESHOLDS:
		rs.break_combo()
		for i in n:
			rs.add_combo()
		var tier := rs.combo_tier()
		_check(tier > last or n == 0, "combo tier did not rise at %d kills" % n)
		last = tier
	_check(last == RunState.COMBO_TIER_MAX,
		"the threshold table does not reach COMBO_TIER_MAX")

	# The escalation used to run out at 30 while the sim's best chain was 51,
	# so a good run spent most of its time already maxed with nothing left to
	# earn. Assert the top of the table is above where play actually reaches.
	rs.break_combo()
	for i in 60:
		rs.add_combo()
	_check(rs.combo_tier() >= 4,
		"a 60-kill chain did not reach tier 4 - the top of the curve is flat "
		+ "again over exactly the range a good run plays in")

	# One number drives shake, hit stop, audio, the HUD and the coins, so every
	# table keyed off it has to cover every tier it can be handed.
	_check(Balance.COMBO_MONEY_MUL.size() == RunState.COMBO_TIER_MAX + 1,
		"the combo payout table does not cover every tier")
	_check(is_equal_approx(Balance.combo_money_mul(0), 1.0),
		"a broken chain pays a bonus")
	var prev := 0.0
	for tier in range(0, RunState.COMBO_TIER_MAX + 1):
		var mul := Balance.combo_money_mul(tier)
		_check(mul > prev, "the combo payout did not rise at tier %d" % tier)
		prev = mul
	# Read through a clampi on purpose, so a tier added without a row here
	# pays the top rate rather than crashing a run.
	_check(is_equal_approx(Balance.combo_money_mul(99), prev),
		"an out-of-range tier did not clamp to the top payout")

	# Hit stop has to fire on reaching a tier, never on every kill at one.
	#
	# This is a guard on a mistake that was made and measured, not a style
	# note. On every kill it stuttered a dense wave from end to end, and
	# because hit stop restores on a real-time timer while the headless sim is
	# frame-deterministic, the same seed produced best combos of 34, 86 and 217
	# depending on how busy the machine was. A frame-deterministic test whose
	# result depends on wall-clock cannot fail honestly.
	var run_src := _read_source("res://world/run.gd")
	var stop_at := run_src.find("Events.hit_stop.emit(Balance.HIT_STOP_KILL)")
	_check(stop_at > 0, "nothing in run.gd fires the kill hit stop any more")
	if stop_at > 0:
		var guard := run_src.substr(maxi(0, stop_at - 200), 200)
		_check(guard.contains("tier_up"),
			"the kill hit stop is not guarded on reaching a new tier - it "
			+ "will fire on every kill at tier %d and above"
				% Balance.HIT_STOP_COMBO_TIER)

	# The HUD colours are indexed by the same tier, through the same clamp - a
	# short table does not crash, it just stops escalating at the top, which is
	# exactly where the escalation is supposed to be loudest.
	var hud_src := _read_source("res://ui/hud.gd")
	# Start the scan after the opening bracket, not at the declaration: the
	# type annotation Array[Color] carries a "]" of its own, and searching from
	# the start of the line finds that one and reads an empty table.
	var needle := "COMBO_TIER_COLOURS: Array[Color] = ["
	var from := hud_src.find(needle) + needle.length()
	var to := hud_src.find("]", from)
	var colours := (0 if from < needle.length() or to < 0
		else hud_src.substr(from, to - from).count("Color("))
	_check(colours == RunState.COMBO_TIER_MAX + 1,
		"the HUD has %d combo tier colours for %d tiers"
			% [colours, RunState.COMBO_TIER_MAX + 1])


## The ending, and the things that would quietly make it unreachable.
func _test_finale() -> void:
	var w := Balance.FINALE_WAVE
	_check(Game.is_finale_wave(w), "the finale wave is not the finale wave")
	_check(Game.is_major_boss_wave(w), "the finale is not a major boss wave")
	_check(not Game.is_mini_boss_wave(w),
		"wave %d is both the finale and a mini-boss" % w)
	_check(Game.is_boss_wave(w), "the finale is not a boss wave at all")

	# It has to be the Sovereign, not whatever the rotation would have put there
	var pick := BossDB.for_wave(w)
	_check(String(pick["id"]) == Balance.FINALE_BOSS,
		"the finale is %s, not the boss the ending is written about" % pick["id"])
	_check(bool(pick.get("finale", false)), "the finale is not flagged as one")

	# ...and it must be somewhere a player actually gets to. An ending past the
	# point anyone reaches is the problem this was built to fix.
	_check(w <= 30, "the finale at wave %d is too deep to be reached" % w)
	_check(BiomeDB.id_for_depth(Game.depth_for_wave(w)) == BiomeDB.ORDER[-1],
		"the finale should sit in the last biome, not partway down")

	# No other wave claims to be the finale.
	var count := 0
	for wave in range(1, 201):
		if Game.is_finale_wave(wave):
			count += 1
	_check(count == 1, "%d waves claim to be the finale" % count)

	# Taking a wave off the mini rotation must not shift the ones after it.
	var seen: Array[String] = []
	for wave in range(5, 60, 5):
		if Game.is_mini_boss_wave(wave):
			seen.append(String(BossDB.for_wave(wave)["id"]))
	for i in seen.size():
		_check(seen[i] == BossDB.MINI_ROTATION[i % BossDB.MINI_ROTATION.size()],
			"the mini rotation skipped a boss after the finale took wave %d" % w)

	# --- the finale has to be finishable -----------------------------------
	#
	# Sized off the major curve it was 20,150, and a run at wave 25 has roughly
	# 60 dps - a ten-minute fight. The sim caught it as a wedged wave; this
	# catches it as a number.
	var dps := 60.0            # measured from the headless sim at this depth
	var seconds := Balance.finale_boss_hp() / dps
	_check(seconds <= 180.0,
		"the finale is a %.0f second fight at %.0f dps - long enough that the "
			% [seconds, dps] + "run stalls on the wave it is meant to celebrate")
	_check(Balance.finale_boss_hp() > Balance.mini_boss_hp(w) * 0.5,
		"the finale is softer than half the mini-boss it replaced")

	# Devour must not out-heal the player.
	#
	# It healed 4.5% of MAX HP per enemy eaten, and the Sovereign summons its
	# own food - so the bigger the boss, the more each meal was worth. At the
	# finale that was ~720 a head and the sim spent four minutes taking it from
	# 100% to 99%. A flat per-enemy value cannot run away with the health pool.
	var per_meal := Boss.DEVOUR_HEAL_PER_ENEMY * Balance.hp_scale(w)
	var summons := int(BossDB.get_def(Balance.FINALE_BOSS)["summon_count"])
	var heal_per_cast := per_meal * summons
	_check(heal_per_cast < Balance.finale_boss_hp() * 0.12,
		"one Devour heals %.0f of the finale's %.0f health - it can out-heal "
			% [heal_per_cast, Balance.finale_boss_hp()]
			+ "anything the player does")
	# ...and it must not scale off the boss's own size, which is what made it
	# unbounded. A flat constant has the same value whatever the boss's health.
	_check(Boss.DEVOUR_HEAL_PER_ENEMY < 100.0,
		"Devour's per-enemy heal looks like a percentage again")

	# A run tracks the ending once, not once per Sovereign.
	var rs := RunState.create(1, [], ["dash", "grenade", "nova"], false)
	_check(not rs.finale_cleared, "a run started already finished")


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


## The boss health bar draws one segment per phase, so its boundaries have to
## be the phase thresholds and nothing else.
##
## A bar that promises the fight is about to change slightly before or after it
## actually does is worse than one continuous fill: it teaches a tell that is
## not true. phase_segment_fill and _check_phase therefore run off the same
## arithmetic, and this is what holds them together.
func _test_boss_phase_bar() -> void:
	for n in range(1, BossDB.max_phases() + 1):
		_check(is_equal_approx(Boss.phase_segment_fill(1.0, n, 0), 1.0),
			"a full boss did not fill the first segment of a %d-phase bar" % n)
		_check(is_equal_approx(Boss.phase_segment_fill(0.0, n, n - 1), 0.0),
			"a dead boss left the last segment of a %d-phase bar filled" % n)

		# Segments run left to right as phase n .. phase 1, because phase 1
		# sits at the top of the health pool and the bar drains from the right.
		for phase in range(1, n + 1):
			var index := n - phase
			# Just inside this phase's band: its own segment is partly full,
			# everything the player has already fought through is empty, and
			# everything still to come is untouched.
			var frac := (float(n - phase) + 0.5) / float(n)
			_check(Boss.phase_for_fraction(frac, n) == phase,
				"health %.3f is phase %d on a %d-phase boss, not %d"
					% [frac, Boss.phase_for_fraction(frac, n), n, phase])
			var here := Boss.phase_segment_fill(frac, n, index)
			_check(here > 0.0 and here < 1.0,
				"the segment for phase %d of %d is not the one draining at "
					% [phase, n] + "%.3f health" % frac)
			for spent in range(index + 1, n):
				_check(is_equal_approx(
					Boss.phase_segment_fill(frac, n, spent), 0.0),
					"segment %d still has health left after its phase ended"
						% spent)
			for ahead in range(0, index):
				_check(is_equal_approx(
					Boss.phase_segment_fill(frac, n, ahead), 1.0),
					"segment %d is already draining before its phase begins"
						% ahead)

		# Every segment boundary has to be a phase boundary. Sampling either
		# side of one proves the two agree rather than merely both existing.
		for b in range(1, n):
			var at := float(b) / float(n)
			_check(Boss.phase_for_fraction(at + 0.001, n)
				!= Boss.phase_for_fraction(at - 0.001, n),
				"the bar splits at %.3f health but the fight does not" % at)

		# Off the end of the bar rather than wrapping round to segment 0.
		_check(is_equal_approx(Boss.phase_segment_fill(1.0, n, n), 0.0),
			"a segment past the end of a %d-phase bar drew as full" % n)
		_check(is_equal_approx(Boss.phase_segment_fill(1.0, n, -1), 0.0),
			"a negative segment index drew as full")


## What a kill is worth, and the one way the combo multiplier could be farmed.
func _test_kill_feedback() -> void:
	# An ordinary corpse: the whole payout scales with the chain.
	_check(Balance.combo_payout(100, 0, 0) == 100,
		"a broken chain changed an ordinary payout")
	var top := Balance.combo_payout(100, 0, RunState.COMBO_TIER_MAX)
	_check(top > 100, "the top tier paid no more than a broken chain")

	# A Thief's haul is your own money coming back, so it must come back at
	# exactly face value. Otherwise "let it rob me, then kill it on a tier-5
	# chain" prints money, and the deeper the chain the better the exchange.
	for tier in range(0, RunState.COMBO_TIER_MAX + 1):
		_check(Balance.combo_payout(80, 80, tier) == 80,
			"a Thief carrying nothing but stolen coins paid %d for 80 taken, "
				% Balance.combo_payout(80, 80, tier)
				+ "at tier %d" % tier)
		# ...and the enemy's own worth still scales, so killing one is not a
		# worse deal than killing anything else.
		var mixed := Balance.combo_payout(120, 80, tier)
		_check(mixed == 80 + Balance.combo_payout(40, 0, tier),
			"a Thief's own payout did not scale like every other corpse")
		_check(mixed >= 80, "killing a Thief returned less than it stole")

	# The whole loop, in money: rob the player, kill it on the best chain the
	# game can produce, and they must not end up richer than they started.
	var purse := 500
	var stolen := 80
	var after := purse - stolen + Balance.combo_payout(
		stolen, stolen, RunState.COMBO_TIER_MAX)
	_check(after == purse,
		"robbing the player and killing the Thief on a full chain turned %d "
			% purse + "into %d" % after)

	# Clamps, so a malformed payout cannot pay out at all.
	_check(Balance.combo_payout(0, 40, 3) == 0,
		"an enemy worth nothing still paid a stolen haul it cannot have")
	_check(Balance.combo_payout(50, -10, 3) == Balance.combo_payout(50, 0, 3),
		"a negative haul was treated as a debt against the payout")


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
## A wave must always be able to end.
##
## finisher_mode already tells stragglers to stop kiting and commit, and that is
## enough whenever they can actually reach you. It is not enough when they
## cannot: a Spitter pressed against a trunk obeys it and still never arrives,
## and so does one knocked somewhere it cannot path back from. The headless sim
## wedged on exactly that - a full-health Spitter sitting at 389px for 14,400
## frames while the bot emptied magazine after magazine into the tree in front
## of it. The wave counter called that "stuck on wave 12" and nothing more.
##
## So the escalation is not a nicety. A wave that cannot end is unrecoverable
## for the player, and a slime that walks through a trunk for the last few
## seconds of a wave is a far smaller price than that.
## Every shipped sound is still the sound that shipped.
##
## tools/gen_sfx.py has one module-level `rng`, seeded once and shared by every
## generator, so a sound's identity is its POSITION in the file. Inserting one
## anywhere but the end re-draws the noise stream for everything after it:
## adding `deflect` to impacts() once silently rewrote 25 unrelated wavs, and
## nothing caught it because every file was still a valid, plausible sound.
##
## That rule was a comment. This makes it an assertion.
##
## When a change to an existing sound IS intended, run `gen_sfx.py --manifest`
## and say which sounds changed in the commit message. The manifest diff is the
## whole point: one added line reads very differently from twenty-six modified
## ones, so the reviewer sees the blast radius rather than being told about it.
## The game has its own typeface, and it is a real outline font.
##
## The second half of that sentence is the load-bearing part. ui_theme.gd sets
## outline_size on EVERY label - 6 px normally, 10 px on titles - and that
## outline is the only thing keeping white text legible over a green forest.
## Outlines come from the stroker, which needs real contour data. A bitmap font
## has none, so shipping one would turn every outline in the interface into a
## silent no-op: nothing would error, nothing would look obviously broken in a
## screenshot of a menu, and text over grass would just quietly stop reading.
func _test_font() -> void:
	var path := UITheme.FONT_PATH
	_check(ResourceLoader.exists(path),
		"the generated typeface is missing - run tools/gen_art.py")
	if not ResourceLoader.exists(path):
		return
	var font: FontFile = load(path)
	_check(font != null, "%s did not load as a FontFile" % path)
	if font == null:
		return

	# A bitmap FontFile carries a non-zero fixed_size. An outline font does not.
	_check(font.fixed_size == 0,
		("the typeface is a fixed-size bitmap font (%d px) - every label "
			% font.fixed_size)
		+ "outline in the game is now doing nothing")

	# ...and prove it positively rather than only by absence: ask the text
	# server for the actual outline of a glyph. Real contours here are what the
	# stroker will have to work with.
	var rids := font.get_rids()
	_check(not rids.is_empty(), "the typeface exposes no font RID")
	if rids.is_empty():
		return
	var rid: RID = rids[0]
	# TextServer is a class, not an autoload - the live one comes from
	# TextServerManager. Calling it statically is a parse error, and a parse
	# error in tests/ means the harness never loads and so never calls quit(),
	# which presents as check.sh hanging rather than as a failure.
	var ts := TextServerManager.get_primary_interface()
	for probe: String in ["A", "g", "0"]:
		var idx := ts.font_get_glyph_index(rid, 64, probe.unicode_at(0), 0)
		var contours: Dictionary = ts.font_get_glyph_contours(rid, 64, idx)
		var pts: PackedVector3Array = contours.get("points", PackedVector3Array())
		_check(pts.size() > 2,
			"glyph '%s' has %d outline points - the stroker has nothing to "
				% [probe, pts.size()] + "outline")

	# ...and that it is actually INSTALLED, not merely present on disk.
	#
	# The asset existing and the interface using it are two different claims,
	# and only the second one is the feature. Main._ready calls
	# UITheme.install_font() before it builds a screen, and the harness boots
	# through Main, so by the time this runs the fallback should already be
	# ours. Without this assertion the font could silently stop being applied -
	# a renamed constant, a reordered _ready - and every other check here would
	# still pass while the game rendered in the stock face.
	_check(ThemeDB.fallback_font == font,
		"the typeface loads but is not installed as ThemeDB.fallback_font - "
		+ "the interface is still rendering in Godot's stock face")

	# Coverage. 95 printable ASCII plus the nine non-ASCII the UI actually uses.
	var chars := font.get_supported_chars()
	_check(chars.length() >= 104,
		"the typeface covers %d characters, expected at least 104"
			% chars.length())
	for needed: String in ["\u00b7", "\u00d7", "\u2014", "\u2026", "\u2726"]:
		_check(chars.contains(needed),
			"the typeface has no glyph for U+%04X, which the UI renders"
				% needed.unicode_at(0))

	# Every glyph advances. A zero-advance glyph stacks the next one on top of
	# it, which reads as a missing character rather than as a broken one.
	for i in chars.length():
		var ch := chars[i]
		_check(font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x > 0.0,
			"glyph U+%04X has no advance" % ch.unicode_at(0))

	# Tabular figures. The HUD counts money, waves, kills and the combo upward
	# in real time; with proportional digits a 1 replacing a 0 makes the whole
	# number twitch sideways on the frame it changes.
	var zero := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	for d: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		_close(font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x, zero,
			"digit %s is not the same width as 0 - the HUD counters will jitter"
				% d, 0.01)

	# Every size the interface actually asks for, from the HUD's smallest label
	# to the main menu title, renders something.
	for size: int in [12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 28, 30,
			32, 34, 38, 40, 42, 44, 46, 54, 92, 104]:
		var w := font.get_string_size("Wave 12", HORIZONTAL_ALIGNMENT_LEFT, -1,
			size).x
		_check(w > 0.0, "the typeface renders nothing at %d px" % size)


func _test_sfx_stability() -> void:
	var raw := _read_source("res://tools/sfx_manifest.json")
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw)
	_check(parsed is Dictionary, "sfx_manifest.json is not a JSON object")
	if not (parsed is Dictionary):
		return
	var sounds: Dictionary = (parsed as Dictionary).get("sounds", {})
	_check(sounds.size() >= 47,
		"the sfx manifest covers only %d sounds - it has lost entries"
			% sounds.size())

	var changed: Array[String] = []
	for name: String in sounds:
		var path := "res://assets/sfx/%s.wav" % name
		if not FileAccess.file_exists(path):
			_check(false, "the manifest lists %s, which is not in assets/sfx" % name)
			continue
		if FileAccess.get_sha256(path) != String(sounds[name]):
			changed.append(name)
	# Reported as one failure naming all of them, not one per sound. The
	# diagnosis is the SHAPE of the list: a single name is a deliberate edit, a
	# run of twenty is the positional-rng bug and the fix is to move the new
	# generator to the end of main() rather than to re-record the manifest.
	_check(changed.is_empty(),
		"%d shipped sounds changed: %s - if this was not intended, a new sound "
			% [changed.size(), ", ".join(changed)]
		+ "was inserted before the end of gen_sfx.py's main()")

	# ...and every wav on disk is covered, so a new sound cannot slip in
	# unrecorded and quietly widen the blind spot.
	var dir := DirAccess.open("res://assets/sfx")
	_check(dir != null, "could not open assets/sfx")
	if dir == null:
		return
	for file: String in dir.get_files():
		if not file.ends_with(".wav"):
			continue
		_check(sounds.has(file.get_basename()),
			"%s is not in the sfx manifest - run gen_sfx.py --manifest" % file)


## The four behaviours added with the roster's second wave, and specifically the
## ways each of them could stop a wave from ending.
##
## Every one of these is the same class of bug: an enemy that is present and
## counted but cannot be killed. The game has shipped that bug twice already -
## the Phasing elite that came back from the pool with no hurtbox, and the
## Spitter that kited at exactly its preferred range - so a new behaviour that
## can hide, lie down or go untargetable gets its exits asserted rather than
## reasoned about.
## Player-facing text exists, and no two things say the same thing.
##
## The uniqueness half is the part that earns its place. Five class upgrades
## shipped sharing three descriptions between them - three of them read
## "Ultimate charges 25% faster" word for word - and nothing noticed, because
## every one of them was a valid non-empty string. Duplicate copy is the exact
## signature of a table that was filled in rather than written, and it is
## invisible to any check that only asks whether a field is present.
##
## Existence is checked too, because two of these are read with a bare subscript
## at runtime: tutor.gd indexes def["hint"] the moment an enemy first spawns, so
## a type without one crashes mid-wave and no test covered it.
## Deadfall stops bullets and not bodies, and never becomes terrain.
##
## The mechanism is that the player, every enemy, every boss and every enemy
## bullet mask WORLD and nothing else - so a body on its own layer is walked
## through by the entire cast with no edits to any of them. That is elegant and
## it is also completely invisible: nothing about "enemy.collision_mask ==
## Layers.WORLD" says "and this is what lets deadfall work". Asserted here so
## adding DEADFALL to an actor mask later fails loudly instead of quietly
## turning a lattice of branches into a wall.
##
## The other half is that a bullet blocker must never reach layout.blockers.
## That array feeds the navigation raster (inflated by ACTOR_CLEARANCE), the
## reachability flood, the corridor repair, the roominess check and the
## sealed-arena test. A circle in there marks ground unwalkable that bodies can
## actually cross, and every one of those guarantees would then be reasoning
## about geometry that does not exist.
## Every boss is wired into the save and the Clean Sweep achievement.
##
## Three lists have to agree - BossDB.DEFS, AchievementsDB.BOSS_STAT_KEYS and
## the stats in save_data - and nothing checked that they did.
## Save.record_boss_kill silently returns on a key it does not recognise, so a
## boss added without its stat makes Clean Sweep quietly unearnable forever, and
## a key listed without a stat behind it does the same thing from the other
## direction. Neither failure produces an error; the achievement simply never
## fires, which is not something a play-test finds.
func _test_boss_stats() -> void:
	for id: String in BossDB.DEFS:
		var key := "boss_" + id
		_check(AchievementsDB.BOSS_STAT_KEYS.has(key),
			"boss '%s' is not in BOSS_STAT_KEYS - Clean Sweep will never "
				% id + "require it, so it is not actually a clean sweep")
		_check(Save.stats.has(key),
			"boss '%s' has no save stat - Save.record_boss_kill returns "
				% id + "silently and the kill is never recorded")
	for key: String in AchievementsDB.BOSS_STAT_KEYS:
		_check(BossDB.DEFS.has(key.trim_prefix("boss_")),
			"BOSS_STAT_KEYS lists '%s', which is not a boss - Clean Sweep can "
				% key + "never be completed")


func _test_deadfall() -> void:
	_check(Layers.DEADFALL != Layers.WORLD and Layers.DEADFALL != Layers.ENEMY
		and Layers.DEADFALL != Layers.PLAYER and Layers.DEADFALL != Layers.PICKUP,
		"Layers.DEADFALL collides with another layer bit")

	# A bullet must see it...
	var proj: Node = load("res://weapons/projectile.tscn").instantiate()
	add_child(proj)
	proj.call("launch", Vector2.ZERO, Vector2.RIGHT,
		{"damage": 1.0, "speed": 100.0, "radius": 4.0})
	_check(int(proj.get("collision_mask")) & Layers.DEADFALL != 0,
		"a player bullet does not collide with deadfall - it shoots straight "
		+ "through the one prop that exists to stop it")
	proj.queue_free()

	# ...and nothing that walks may.
	var e: Enemy = load("res://actors/enemy.tscn").instantiate()
	add_child(e)
	e.configure(EnemyTypes.GREEN, 3)
	_check(e.collision_mask & Layers.DEADFALL == 0,
		"enemies collide with deadfall - it is a wall now, not cover")
	e.queue_free()

	_check(PropCatalog.stops_bullets("deadfall"), "deadfall does not stop bullets")
	_check(not PropCatalog.blocks("deadfall"),
		"deadfall is flagged as blocking - it will be rasterised into the "
		+ "navigation grid and bodies will path around thin air")
	_check(not PropCatalog.bullet_blockers("deadfall").is_empty(),
		"deadfall has no bullet blockers, so it stops nothing")
	_check(PropCatalog.blockers("deadfall").is_empty(),
		"deadfall declares body blockers")

	# ...and in a real forest, across every biome, it never lands in blockers.
	var total := 0
	for biome: String in BiomeDB.ORDER:
		# generate() is STATIC and returns the generator. Calling it on a fresh
		# instance and then reading that instance's props gives an empty list,
		# and every check inside the loop passes by never running - which is
		# exactly what the total below was added to catch, and did.
		var g := ForestGenerator.generate(4242, biome)
		# One assertion per biome, not one per deadfall-times-blocker pair: the
		# naive nested version emitted seventy-six thousand checks and told you
		# nothing more than this does.
		var coincident := 0
		for prop: Dictionary in g.props:
			if String(prop["id"]) != "deadfall":
				continue
			total += 1
			for b: Dictionary in g.blockers:
				if (b["pos"] as Vector2).distance_to(prop["pos"]) <= 1.0:
					coincident += 1
					break
		_check(coincident == 0,
			"%d deadfall props in %s put circles in layout.blockers - the "
				% [coincident, biome]
			+ "navigation grid now has walls where bodies can walk")
	# Without this the loop above is vacuous: a weight that stopped placing any
	# deadfall at all would make every check inside it pass by never running.
	_check(total > 0,
		"no deadfall was placed in any of the five biomes - it is in the "
		+ "catalogue but nothing scatters it, so none of the above was tested")


func _test_written_text() -> void:
	var hints := {}
	for id: String in EnemyTypes.ORDER:
		var def := EnemyTypes.get_def(id)
		var hint := String(def.get("hint", ""))
		_check(not hint.is_empty(),
			"%s has no hint - tutor.gd reads def[\"hint\"] directly and will "
				% id + "crash the first time one spawns")
		_check(not hints.has(hint),
			"%s and %s share a hint word for word" % [id, hints.get(hint, "")])
		hints[hint] = id

	var descs := {}
	for id: String in AbilitiesDB.ORDER:
		var d := String(AbilitiesDB.get_def(id).get("desc", ""))
		_check(not d.is_empty(), "ability '%s' has no description" % id)
		_check(not descs.has(d),
			"abilities '%s' and '%s' have the same description"
				% [id, descs.get(d, "")])
		descs[d] = id

	# The class-locked shop items. One per class, so each should be describing
	# a different ultimate by name.
	var class_descs := {}
	for id: String in UpgradesDB.CLASS_UPGRADES:
		var cd := String(UpgradesDB.CLASS_UPGRADES[id].get("desc", ""))
		_check(not cd.is_empty(), "class upgrade '%s' has no description" % id)
		_check(not class_descs.has(cd),
			"class upgrades '%s' and '%s' read identically - the player cannot "
				% [id, class_descs.get(cd, "")]
			+ "tell what they are buying")
		class_descs[cd] = id

	var meta_descs := {}
	for id: String in MetaDB.DEFS:
		var md := MetaDB.description(id)
		_check(not md.is_empty(), "meta unlock '%s' has no description" % id)
		_check(not meta_descs.has(md),
			"meta unlocks '%s' and '%s' read identically"
				% [id, meta_descs.get(md, "")])
		meta_descs[md] = id

	# The opening controls line lives in one place now. It was in two, and they
	# had already drifted apart by a word.
	_check(not InputBinds.OPENING_CONTROLS.is_empty(),
		"the opening controls line is empty")
	for path: String in ["res://ui/main_menu.gd", "res://world/tutor.gd"]:
		_check(not _read_source(path).contains("WASD to move"),
			"%s spells the controls line out again instead of reading "
				% path + "InputBinds.OPENING_CONTROLS")


func _test_second_wave_enemies() -> void:
	Combat.reset()
	var scene: PackedScene = load("res://actors/enemy.tscn")

	# --- Husk: goes down once, comes back up, and is shootable throughout ---
	var h: Enemy = scene.instantiate()
	add_child(h)
	h.configure(EnemyTypes.BONE, 12)
	var live := Combat.enemy_count()
	h.take_damage(10_000.0)
	_check(not h.dying, "a Husk died on its first knockdown instead of lying down")
	_check(Combat.enemy_count() == live,
		"a Husk stopped being counted while it was down - the wave can end "
		+ "with it still on the field")
	_check(h.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a downed Husk is not shootable, so it cannot be finished off")
	_check(bool(h.get("_husk_down")), "a Husk is not flagged as down")

	# it gets back up on its own clock, so it can never hold a wave open
	for _i in 200:
		h.call("_tick_husk", 0.05)
	_check(not bool(h.get("_husk_down")), "a Husk never got back up")
	_check(h.hp > 0.0, "a revived Husk came back with no health")

	# ...and the second knockdown is final.
	h.take_damage(10_000.0)
	_check(h.dying, "a Husk went down twice - it is unkillable")
	h.call("_pool_reset")
	_check(not bool(h.get("_husk_spent")),
		"a recycled Husk remembers it already revived, so it dies in one hit")

	# --- Burrower: untargetable underground, but mop-up always surfaces it ---
	var b: Enemy = scene.instantiate()
	add_child(b)
	b.configure(EnemyTypes.UMBER, 15)
	b.set("_burrow_timer", 0.0)
	b.call("_tick_burrow", 0.01)
	_check(bool(b.get("_burrowed")), "a Burrower never went under")
	_check(b.get_node("Hurtbox").collision_layer == 0,
		"a burrowed enemy is still shootable - the state means nothing")

	Combat.finisher_mode = true
	b.call("_think", Combat.player_position())
	_check(not bool(b.get("_burrowed")),
		"a Burrower stayed under during mop-up - the last one alive can ride "
		+ "its cycle and hold the wave open forever")
	_check(b.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a surfaced Burrower did not get its hurtbox back")
	Combat.finisher_mode = false

	# and the recycle, which is where the Phasing elite went wrong
	b.set("_burrowed", true)
	b.get_node("Hurtbox").collision_layer = 0
	b.call("_pool_reset")
	_check(b.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a parked Burrower keeps its cleared hurtbox - it comes back "
		+ "permanently unhittable")

	# --- Knot: pairs up, and never with itself ---
	var k1: Enemy = scene.instantiate()
	var k2: Enemy = scene.instantiate()
	add_child(k1)
	add_child(k2)
	k1.configure(EnemyTypes.INDIGO, 18)
	k2.configure(EnemyTypes.INDIGO, 18)
	k1.call("_find_knot_partner")
	_check(k1.get("_knot_partner") == k2, "a Knot did not find its pair")
	_check(k2.get("_knot_partner") == k1, "the pairing is not mutual")
	_check(k1.get("_knot_partner") != k1, "a Knot tethered itself")

	# --- Devourer: eats zoning, and only within reach ---
	var d: Enemy = scene.instantiate()
	add_child(d)
	d.configure(EnemyTypes.RUST, 20)
	var far := Node2D.new()
	far.add_to_group("zoning")
	add_child(far)
	far.global_position = d.global_position + Vector2(4000, 0)
	d.set("_eat_timer", 0.0)
	d.call("_tick_devour", 0.01)
	_check(is_instance_valid(far),
		"a Devourer ate a wall on the other side of the forest")
	far.queue_free()

	for e: Enemy in [h, b, k1, k2, d]:
		e.queue_free()
	Combat.reset()


func _test_straggler_escalation() -> void:
	Combat.reset()
	_check(not Combat.hunt_mode, "hunt mode is on before anything has stalled")

	# Not finishing: the clock must not run at all.
	Combat.tick_finisher(Balance.STRAGGLER_HUNT_AFTER * 2.0, false, 6)
	_check(not Combat.hunt_mode,
		"hunt mode engaged while the wave was still spawning")

	# Finishing, and the count is not moving. This is the wedge.
	#
	# The first finishing frame at a new count only starts the clock - it does
	# not credit its own delta, because the count having just changed is itself
	# progress. So reaching the grace period takes the frames after it.
	Combat.tick_finisher(Balance.STRAGGLER_HUNT_AFTER, true, 1)
	_check(not Combat.hunt_mode,
		"the frame a count first settles at already counted towards the "
		+ "grace period")
	Combat.tick_finisher(Balance.STRAGGLER_HUNT_AFTER * 0.5, true, 1)
	_check(not Combat.hunt_mode,
		"hunt mode engaged before the grace period was up")
	Combat.tick_finisher(Balance.STRAGGLER_HUNT_AFTER * 0.6, true, 1)
	_check(Combat.hunt_mode,
		"a wave stalled past the grace period never escalated - it can wedge "
		+ "forever")

	# A kill is progress, so the clock restarts rather than staying escalated.
	Combat.tick_finisher(0.1, true, 0)
	_check(not Combat.hunt_mode,
		"hunt mode stayed on after the count dropped - progress must reset it")

	var scene: PackedScene = load("res://actors/enemy.tscn")
	var e: Enemy = scene.instantiate()
	add_child(e)
	e.configure(EnemyTypes.PURPLE, 12)
	_check(e.collision_mask == Layers.WORLD,
		"a fresh enemy does not collide with the forest")
	var walking := float(e.call("_current_speed"))

	Combat.hunt_mode = true
	e.call("_sync_hunt_mask")
	_check(e.collision_mask == 0,
		"an escalated straggler still collides with the forest, so being stuck "
		+ "behind a trunk still wedges the wave")
	_check(float(e.call("_current_speed")) > walking,
		"an escalated straggler is no faster, so it closes no sooner")

	# ...and it goes back. Enemies are pooled, and one handed out still
	# ignoring the forest would walk through trunks for the rest of the run -
	# the same shape as the Phasing elite coming back unhittable.
	Combat.hunt_mode = false
	e.call("_sync_hunt_mask")
	_check(e.collision_mask == Layers.WORLD,
		"an enemy kept its forest-ignoring mask after the wave un-stalled")

	Combat.hunt_mode = true
	e.call("_sync_hunt_mask")
	e.call("_pool_reset")
	_check(e.collision_mask == Layers.WORLD,
		"a parked enemy has no forest collision - it comes back walking "
		+ "through trunks")

	# The recycle must also put it back in the enemy group. add_to_group runs
	# in _ready, once per node, and die() removes it - so before this every
	# enemy that had been through the pool was missing from the group while
	# still being counted by Combat.
	e.die(true)
	_check(not e.is_in_group("enemies"), "a corpse is still in the enemy group")
	e.call("_pool_reset")
	e.configure(EnemyTypes.GREEN, 3)
	_check(e.is_in_group("enemies"),
		"a recycled enemy is missing from the enemy group - Combat counts it "
		+ "but anything reading the group cannot see it")

	e.die(false, false)
	e.queue_free()
	Combat.reset()


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


## Every other test script has to compile.
##
## check.sh runs THIS harness, so a parse error here is caught - but the visual
## pass and the perf test are separate entry points it never loads, and a bad
## type inference in one of those is invisible until someone runs it by hand
## with a window open. Loading them from inside the suite closes that: it costs
## one assertion and it has already caught two.
func _test_harness_scripts() -> void:
	for path: String in ["res://tests/visual_pass.gd", "res://tests/perf_test.gd",
			"res://tests/sim_harness.gd", "res://tests/test_forest.gd"]:
		# load() returns a non-null GDScript even when compilation failed, so
		# a null check proves nothing. A script that did not compile has no
		# methods and cannot be instantiated - that is the discriminator.
		var script: Variant = ResourceLoader.load(path, "",
			ResourceLoader.CACHE_MODE_IGNORE)
		var gd := script as GDScript
		_check(gd != null and gd.get_script_method_list().size() > 0,
			"%s does not compile - it is never loaded by check.sh, so nothing "
				% path + "else would have told you")


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
		sheets[EnemyTypes.texture_path(id)] = Enemy.BODY_FRAMES
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
		_check(spr.hframes == Enemy.BODY_FRAMES,
			"a menu backdrop slime has hframes=%d - it will draw the whole "
				% spr.hframes + "strip instead of one frame")
		_check(spr.frame < Enemy.WALK_FRAMES,
			"a menu backdrop slime is paged to frame %d, which is a flinch or "
				% spr.frame + "a corpse - the menu should not be a morgue")
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

	# The flinch must not look like a wind-up. The wind-up sinks AND spreads;
	# a flinch that did the same would read as a telegraph, and the boss would
	# appear to announce an attack every time it took a bullet.
	_check(Boss.POSE_STRETCH[Boss.POSE_FLINCH] < 1.0,
		"the boss flinch spreads outward like the wind-up does - it will read "
		+ "as a telegraph and teach the player to dodge nothing")
	_check(Boss.POSE_SQUASH[Boss.POSE_FLINCH]
		> Boss.POSE_SQUASH[Boss.POSE_WINDUP],
		"the boss flinch crouches as deep as the wind-up, so the two poses "
		+ "cannot be told apart at a glance")

	# The walk indexes off WALK_FRAMES, never off hframes. Page the hop phase
	# across the whole strip and every slime plays its own death animation
	# each time it touches the ground.
	# The neutral slime frame fills its canvas edge to edge, and that is a
	# contract rather than an observation.
	#
	# Every offset measured against this sprite assumes it: the elite crown, the
	# face, the shape badge, and the hit radii in EnemyTypes - which are stated
	# in final pixels and deliberately NOT scaled. A silhouette that sat
	# differently inside the same canvas would leave crowns floating above their
	# slimes and hurtboxes that no longer match what is drawn, and neither
	# failure looks like an art change when you go looking for it.
	#
	# Shading is free to change; this only pins the outline. gen_art.py's rim,
	# speckle and dither passes are all alpha-preserving by construction for
	# exactly this reason, so a lighting pass cannot trip it - only a change to
	# the shape itself, which is the change that needs re-checking those offsets.
	var slime: Texture2D = load(EnemyTypes.texture_path(EnemyTypes.GREEN))
	if slime != null:
		var img := slime.get_image()
		var fw := img.get_width() / Enemy.BODY_FRAMES
		var frame0 := img.get_region(Rect2i(0, 0, fw, img.get_height()))
		frame0.convert(Image.FORMAT_RGBA8)
		var used := frame0.get_used_rect()
		_check(used == Rect2i(0, 0, fw, img.get_height()),
			("the neutral slime frame no longer fills its canvas (%s of %dx%d) "
				% [str(used), fw, img.get_height()])
			+ "- the crown, face, badge and hit radii are all offsets against it")

	var enemy_src := _read_source("res://actors/enemy.gd")
	_check(not enemy_src.contains("(1.0 - bounce) * float(_body.hframes)"),
		"the walk cycle indexes off hframes - it will page into the flinch "
		+ "and death frames every hop")
	_check(Enemy.BODY_FRAMES
		== Enemy.WALK_FRAMES + 1 + Enemy.DEATH_FRAMES.size(),
		"the enemy frame constants do not add up to the strip")
	for f: int in Enemy.DEATH_FRAMES:
		_check(f >= Enemy.WALK_FRAMES and f < Enemy.BODY_FRAMES,
			"death frame %d is not on the strip, or overlaps the walk" % f)


## A corpse is a pooled enemy that has not been recycled yet, which is the
## most dangerous thing in this file.
##
## The death animation holds an enemy in the tree for a fifth of a second after
## it dies. Everything downstream has to be finished with it by then - and when
## it comes back it has to come back clean. The Phasing elite bug was exactly
## this shape: an enemy that died with its hurtbox layer cleared returned from
## the pool as an ordinary slime nothing could shoot, and its wave could never
## end. Reverting either reset below reproduces that.
func _test_corpses() -> void:
	var scene: PackedScene = load("res://actors/enemy.tscn")
	var e: Enemy = scene.instantiate()
	add_child(e)
	e.configure(EnemyTypes.GREEN, 6)

	var live := Combat.enemy_count()
	e.die(true)

	# The wave's live count drops NOW, not when the animation ends. A corpse
	# that still counted would hold its wave open for the length of its own
	# death throes, and a screenful of them would hold it open much longer.
	_check(Combat.enemy_count() == live - 1,
		"a corpse is still counted among the living - it will hold the wave "
		+ "open until its animation finishes")
	_check(not e.is_in_group("enemies"), "a corpse is still in the enemy group")

	_check(int(e.get("_death_frame")) == 0, "a corpse is not playing its death")
	_check(e.get_node("Visual/Body").frame == Enemy.DEATH_FRAMES[0],
		"a corpse is showing frame %d instead of the first death frame"
			% e.get_node("Visual/Body").frame)
	_check(e.get_node("Hurtbox").collision_layer == 0,
		"a corpse is still shootable")

	# Dying twice must not fire enemy_died twice: the combo, the coins and the
	# wave count all hang off that one signal.
	var deaths := 0
	var counter := func(_n: Node2D, _at: Vector2) -> void: deaths += 1
	Events.enemy_died.connect(counter)
	e.die(true)
	Events.enemy_died.disconnect(counter)
	_check(deaths == 0, "a corpse died a second time and paid out twice")

	# ...and the recycle. _pool_reset runs on release, before configure() ever
	# sees the node again, so a parked enemy must already be safe.
	e.call("_pool_reset")
	_check(int(e.get("_death_frame")) == -1, "a parked enemy is mid-death")
	_check(e.get_node("Visual/Body").frame == 0,
		"a parked enemy kept a death frame and will spawn as a corpse")
	_check(e.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a parked enemy has no hurtbox - it comes back permanently unhittable")

	e.configure(EnemyTypes.BLUE, 6)
	_check(int(e.get("_death_frame")) == -1, "a recycled enemy is mid-death")
	_check(e.get_node("Hurtbox").collision_layer == Layers.ENEMY,
		"a recycled enemy came back unhittable")
	_check(e.get_node("Visual/Body").hframes == Enemy.BODY_FRAMES,
		"a recycled enemy has the wrong frame count")

	# A hit flinches; a deflect deliberately does not. "That hurt" and "that
	# does not work on this one" have to read as different events, or the
	# player keeps firing at a Carapace thinking they are missing.
	e.take_damage(1.0, false, Vector2.ZERO, 0.0, Combat.SOURCE_BULLET)
	_check(e.get_node("Visual/Body").frame == Enemy.FRAME_FLINCH,
		"a hit that landed did not flinch")

	e.die(false, false)
	_check(int(e.get("_death_frame")) == -1,
		"an enemy told to leave no corpse left one anyway - a Thief that got "
		+ "away would splat where it escaped")
	e.queue_free()


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
	_check(int(t2.get("stolen_value")) == 0, "a Thief claimed a haul it never took")
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
	_check(m.get_node("Visual/Body").hframes == Enemy.BODY_FRAMES,
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
	_check(int(round_trip["version"]) == 5, "to_dict did not write version 5")
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

	# --- v5: skins for classes you do not own are refunded ------------------
	var locked_cls := ClassesDB.VAMPIRE
	var locked_skin: String = ClassesDB.skins_for(locked_cls).keys()[0]
	var locked_price := int(ClassesDB.skins_for(locked_cls)[locked_skin]["cost"])
	var free_skin: String = ClassesDB.skins_for(ClassesDB.DEFAULT).keys()[0]

	var v4 := {
		"version": 4,
		"essence": 50,
		"unlocks": [],
		"loadout": ["dash", "grenade", "nova"],
		"character": locked_cls,
		"skins_unlocked": [
			Save.skin_key(locked_cls, locked_skin),
			Save.skin_key(ClassesDB.DEFAULT, free_skin),
		],
		"skin_for_class": {locked_cls: locked_skin},
		"stats": {}, "settings": {}, "keybinds": {}, "achievements": [],
	}
	Save.from_dict(v4)
	_check(Save.essence == 50 + locked_price,
		"the locked-class skin was not refunded - essence is %d, expected %d"
			% [Save.essence, 50 + locked_price])
	_check(not Save.skins_unlocked.has(Save.skin_key(locked_cls, locked_skin)),
		"a skin for a class the player does not own survived")
	_check(Save.skins_unlocked.has(Save.skin_key(ClassesDB.DEFAULT, free_skin)),
		"a skin for a class the player DOES own was refunded too")
	_check(Save.character == ClassesDB.DEFAULT,
		"a save wearing a locked class did not fall back")
	_check(not Save.skin_for_class.has(locked_cls),
		"a locked class kept its chosen skin")

	# once only, across a round-trip
	var after_skins := Save.essence
	var round2 := Save.to_dict()
	_check(bool(round2.get("refunded_locked_skins", false)),
		"the migrated save does not record the skin refund")
	Save.from_dict(round2)
	_check(Save.essence == after_skins,
		"the skin refund compounded - essence went %d to %d"
			% [after_skins, Save.essence])

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
