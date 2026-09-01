class_name AbilityController
extends Node
## Runs the player's three equipped abilities.
##
## Slot 0 is the movement slot and only takes a movement ability; slots 1 and 2
## are general. The split exists because Dash used to compete for a general slot
## and always won - it is the only source of invulnerability in the game, and
## several boss attacks cannot be walked out of at all - so "pick two" really
## meant "pick one, plus Dash". Separating the classes is what makes the general
## slots an actual argument between burst, control and sustain.
##
## Charges refill on a cooldown; potions can grant a charge directly.

const ORBITAL := preload("res://abilities/orbital_orbs.tscn")
const DECOY := preload("res://abilities/decoy.tscn")
const GRENADE := preload("res://abilities/grenade.tscn")
const THORNWALL := preload("res://abilities/thornwall.tscn")
const CINDERS := preload("res://abilities/cinders.tscn")

signal slot_changed(slot: int)

var player: Player = null
var effect_container: Node = null

## Per slot: {id, charges, max_charges, cooldown, cooldown_left}
## Sized from AbilitiesDB so it can never drift out of step with the loadout.
var slots: Array[Dictionary] = []


func _init() -> void:
	slots.resize(AbilitiesDB.SLOT_COUNT)
	for i in AbilitiesDB.SLOT_COUNT:
		slots[i] = {}


func _ready() -> void:
	Pools.prewarm(GRENADE, 4)


func setup(p: Player, container: Node) -> void:
	player = p
	effect_container = container
	var ids: Array[String] = Game.run.abilities if Game.run != null \
		else Save.loadout.duplicate()
	for i in AbilitiesDB.SLOT_COUNT:
		var id: String = ids[i] if i < ids.size() else ""
		# A saved loadout from before the movement slot existed can be short, or
		# hold the right ability in the wrong slot. Fall back per class rather
		# than to Dash, which would put a movement ability in a general slot.
		if not AbilitiesDB.fits_slot(id, i):
			id = AbilitiesDB.fallback_for_slot(i)
		equip(i, id)


func equip(slot: int, id: String) -> void:
	if slot < 0 or slot >= slots.size():
		return
	var def := AbilitiesDB.get_def(id)
	var extra := Game.run.ability_extra_charges if Game.run != null else 0
	var max_charges := int(def["charges"]) + extra
	slots[slot] = {
		"id": id,
		"charges": max_charges,
		"max_charges": max_charges,
		"cooldown": _cooldown_for(def),
		"cooldown_left": 0.0,
	}
	if Game.run != null and slot < Game.run.abilities.size():
		Game.run.abilities[slot] = id
	slot_changed.emit(slot)
	Events.ability_equipped.emit(slot, id)


func _cooldown_for(def: Dictionary) -> float:
	var cdr := Game.run.ability_cdr if Game.run != null else 0.0
	return float(def["cooldown"]) * (1.0 - cdr)


func _process(delta: float) -> void:
	for i in slots.size():
		var s := slots[i]
		if s.is_empty():
			continue
		if int(s["charges"]) >= int(s["max_charges"]):
			continue
		s["cooldown_left"] = float(s["cooldown_left"]) - delta
		if float(s["cooldown_left"]) <= 0.0:
			s["charges"] = int(s["charges"]) + 1
			s["cooldown_left"] = float(s["cooldown"]) if int(s["charges"]) < int(s["max_charges"]) else 0.0
			Audio.play("ui_hover", -18.0, 0.0)
			Events.ability_ready.emit(i, s["id"])
			slot_changed.emit(i)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.alive:
		return
	if event.is_action_pressed("ability_movement"):
		use(0)
	elif event.is_action_pressed("ability_1"):
		use(1)
	elif event.is_action_pressed("ability_2"):
		use(2)
	elif event.is_action_pressed("ultimate"):
		use_ultimate()


# ---------------------------------------------------------------------------
# ultimates
# ---------------------------------------------------------------------------
## Fire this run's class ultimate, if it is charged.
##
## Every ClassesDB ultimate id must appear as a match arm below. The logic suite
## reads the arms out of this file, so a class naming an ultimate nothing
## implements fails the build rather than shipping a button that does nothing.
func use_ultimate() -> bool:
	if Game.run == null or player == null or not player.alive:
		return false
	if not Game.run.ultimate_ready():
		Audio.play_ui("ui_deny", -10.0)
		return false
	if not Game.run.spend_ultimate():
		return false

	var class_id: String = Game.run.class_id
	var def := ClassesDB.get_def(class_id)
	var ult := String(def["ultimate"])

	_ultimate_flourish(def)
	match ult:
		"recall_the_wood": _ult_recall_the_wood()
		"last_stand": _ult_last_stand()
		"crimson_hour": _ult_crimson_hour()
		"overclock": _ult_overclock()
		"bloom": _ult_bloom()
	Events.ultimate_fired.emit(class_id, ult)
	return true


## Combat punctuation, not a cutscene.
##
## Deliberately short and made entirely of things that already exist - hit
## stop, shake, a ring, a name card. Players will see this hundreds of times in
## a game whose whole appeal is continuous pressure, so anything longer than
## about a second stops being a payoff and starts being an interruption.
func _ultimate_flourish(def: Dictionary) -> void:
	var tint: Color = def["tint"]
	Events.hit_stop.emit(0.18)
	Game.shake(9.0, 0.45)
	FX.ring(player.global_position, 520.0, tint, 0.55, 0.06)
	FX.burst(player.global_position, tint, 40, 2.4)
	FX.floating_text(player.global_position + Vector2(0, -120),
		String(def["ultimate_name"]).to_upper(), tint)
	Audio.play("boss_phase", 1.0)


## WARDEN. The forest remembers you - roots erupt in rings outward, the same
## shape the Ancient Oak's Rootquake uses, because you were one of them.
func _ult_recall_the_wood() -> void:
	var origin := player.global_position
	var damage := 46.0
	for step in 5:
		var t := create_tween()
		t.tween_interval(0.11 * step)
		t.tween_callback(func() -> void:
			if not is_instance_valid(player):
				return
			var radius := 150.0 + 165.0 * step
			for i in 10 + step * 3:
				var at := origin + Vector2.RIGHT.rotated(
					TAU * i / float(10 + step * 3)) * radius
				FX.explosion(at, 110.0, Color(0.45, 0.75, 0.4))
				Combat.explode(at, 110.0, damage, 240.0, true,
					Combat.SOURCE_ABILITY)
			Game.shake(4.0, 0.2))


## WARRIOR. What hits you comes back out. The one ultimate you want to be hit
## during, which is the class in one mechanic.
func _ult_last_stand() -> void:
	player.retaliating_until = Time.get_ticks_msec() / 1000.0 + 6.0
	player.bonus_damage_reduction = maxf(player.bonus_damage_reduction, 0.45)
	var t := create_tween()
	t.tween_interval(6.0)
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.bonus_damage_reduction = 0.0)


## VAMPIRE. Full lifesteal, and a kill spreads to whatever is beside it.
func _ult_crimson_hour() -> void:
	player.lifesteal_bonus += 0.85
	player.contagion_until = Time.get_ticks_msec() / 1000.0 + 8.0
	var t := create_tween()
	t.tween_interval(8.0)
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.lifesteal_bonus = maxf(0.0, player.lifesteal_bonus - 0.85))


## ENGINEER. Everything you carry goes off, three times over. Reuses the
## ability dispatch itself rather than reimplementing five effects.
func _ult_overclock() -> void:
	for burst in 3:
		var t := create_tween()
		t.tween_interval(0.34 * burst)
		t.tween_callback(func() -> void:
			if not is_instance_valid(player):
				return
			for slot in slots.size():
				var s := slots[slot]
				if s.is_empty():
					continue
				var id := String(s["id"])
				# movement abilities would fling the player around three times
				if AbilitiesDB.get_def(id).get("class", "") == AbilitiesDB.CLASS_MOVEMENT:
					continue
				_execute(id, AbilitiesDB.get_def(id))
			Game.shake(5.0, 0.25))


## HERBALIST. The ground turns on them - a wide, lasting burn centred on you.
func _ult_bloom() -> void:
	var at := player.global_position
	FX.ring(at, 620.0, Color(0.5, 0.9, 0.6), 0.8, 0.1)
	for tick in 12:
		var t := create_tween()
		t.tween_interval(0.28 * tick)
		t.tween_callback(func() -> void:
			if not is_instance_valid(player):
				return
			var hit := Combat.explode(at, 620.0, 22.0, 0.0, false,
				Combat.SOURCE_ABILITY)
			if hit > 0:
				FX.burst(at, Color(0.55, 0.9, 0.6), 8, 1.4)
				player.on_damage_dealt(22.0 * hit))


func use(slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or player == null or not player.alive:
		return false
	var s := slots[slot]
	if s.is_empty() or int(s["charges"]) <= 0:
		Audio.play_ui("ui_deny", -10.0)
		return false

	var id: String = s["id"]
	var def := AbilitiesDB.get_def(id)
	s["charges"] = int(s["charges"]) - 1
	if float(s["cooldown_left"]) <= 0.0:
		s["cooldown_left"] = float(s["cooldown"])
	slot_changed.emit(slot)

	Audio.play(def["sound"], -4.0)
	Events.ability_used.emit(slot, id)
	_execute(id, def)
	return true


## How many charges are missing across every slot. The potion uses this to
## decide whether it is worth being picked up at all.
func charges_missing() -> int:
	var missing := 0
	for i in slots.size():
		var s := slots[i]
		if s.is_empty():
			continue
		missing += maxi(0, int(s["max_charges"]) - int(s["charges"]))
	return missing


## Refill everything and clear every cooldown - what the purple potion does.
## Returns the number of charges restored.
##
## This used to be a single charge to the emptiest slot, which meant the potion
## was usually consumed for nothing: Dash refills in 3.2 s and Grenade in 7 s,
## so by the time you reach the drop you are already topped up. A full reset is
## worth going out of your way for.
func refill_all() -> int:
	var restored := 0
	for i in slots.size():
		var s := slots[i]
		if s.is_empty():
			continue
		var missing := maxi(0, int(s["max_charges"]) - int(s["charges"]))
		if missing <= 0:
			continue
		restored += missing
		s["charges"] = int(s["max_charges"])
		s["cooldown_left"] = 0.0
		slot_changed.emit(i)
		Events.ability_ready.emit(i, s["id"])
	return restored


## Grant a charge to whichever slot is emptiest.
func grant_charge(amount: int = 1) -> bool:
	var best := -1
	var best_missing := 0
	for i in slots.size():
		var s := slots[i]
		if s.is_empty():
			continue
		var missing := int(s["max_charges"]) - int(s["charges"])
		if missing > best_missing:
			best_missing = missing
			best = i
	if best < 0:
		return false
	var s := slots[best]
	s["charges"] = mini(int(s["max_charges"]), int(s["charges"]) + amount)
	if int(s["charges"]) >= int(s["max_charges"]):
		s["cooldown_left"] = 0.0
	slot_changed.emit(best)
	Events.ability_ready.emit(best, s["id"])
	return true


func charge_fraction(slot: int) -> float:
	var s := slots[slot]
	if s.is_empty():
		return 0.0
	if int(s["charges"]) >= int(s["max_charges"]):
		return 1.0
	var cd := float(s["cooldown"])
	return 1.0 - clampf(float(s["cooldown_left"]) / maxf(cd, 0.01), 0.0, 1.0)


# ---------------------------------------------------------------------------
# effects
# ---------------------------------------------------------------------------
func _execute(id: String, def: Dictionary) -> void:
	match id:
		"dash": _do_dash(def)
		"surge": _do_surge(def)
		"vault": _do_vault(def)
		"grenade": _do_grenade(def)
		"thornwall": _do_thornwall(def)
		"cinders": _do_cinders(def)
		"shield": _do_shield(def)
		"timeslow": _do_timeslow(def)
		"nova": _do_nova(def)
		"heal": _do_heal(def)
		"lightning": _do_lightning(def)
		"rapidfire": _do_rapidfire(def)
		"orbital": _do_orbital(def)
		"decoy": _do_decoy(def)
		"lifesteal": _do_lifesteal(def)


## The run's forest layout, for abilities that move the player across it.
##
## Read off the wave controller rather than the run node: it already carries the
## layout, it is already in a group, and it is already re-pointed at the new one
## when the forest regenerates at a biome boundary.
func _layout() -> ForestGenerator:
	if not is_inside_tree():
		return null
	var waves := get_tree().get_first_node_in_group("wave_controller")
	if waves == null:
		return null
	return waves.get("layout") as ForestGenerator


func _container() -> Node:
	if effect_container != null and is_instance_valid(effect_container):
		return effect_container
	return get_tree().current_scene


## Dash in the movement direction if there is one, otherwise towards the
## cursor - dashing backwards while strafing is the whole point of the ability.
func _do_dash(def: Dictionary) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := input.normalized() if input != Vector2.ZERO else player.aim_direction
	var distance := float(def["distance"])
	var duration := float(def["duration"])

	player.dashing = true
	player.velocity = dir * (distance / duration)
	FX.burst(player.global_position, Color(0.8, 0.95, 1.0), 10, 0.8)
	Game.shake(1.6, 0.12)

	# afterimages, spawned along the dash rather than all at once
	for i in 3:
		var delay := duration * (float(i) / 3.0)
		var t := create_tween()
		t.tween_interval(delay)
		t.tween_callback(func() -> void:
			if is_instance_valid(player):
				FX.impact(player.global_position, Color(0.7, 0.9, 1.0, 0.5), 0.8))

	var end := create_tween()
	end.tween_interval(duration)
	end.tween_callback(func() -> void:
		if not is_instance_valid(player):
			return
		player.dashing = false
		player.velocity = dir * player.max_speed() * 0.6
		# a grace window after the dash ends, so dashing through a crowd does
		# not immediately eat a contact hit on the far side
		player.grant_landing_grace())


## Surge trades Dash's invulnerability for duration. It is the answer to the
## attacks you are supposed to outrun rather than blink through - the expanding
## shockwave, the spiral - and the loadout that proves the bosses are beatable
## without a blink at all.
func _do_surge(def: Dictionary) -> void:
	var duration := float(def["duration"])
	player.apply_speed_boost(float(def["multiplier"]), duration)
	FX.ring(player.global_position, 90.0, Color(0.6, 1.0, 0.7), 0.35, 0.15)
	FX.burst(player.global_position, Color(0.7, 1.0, 0.75), 14, 1.2)

	# Flat damage reduction, NOT invulnerability. Dash and the Vault both got a
	# much wider landing grace this pass; without something in return Surge
	# becomes the strictly worse pick and the bug the movement slot exists to
	# prevent comes straight back. Reduction keeps "Surge has no i-frames"
	# literally true, so the sim's Dash-free guard still means something.
	player.bonus_damage_reduction = Balance.SURGE_DAMAGE_REDUCTION
	var guard := create_tween()
	guard.tween_interval(duration)
	guard.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.bonus_damage_reduction = 0.0)

	# A trail for as long as the boost lasts, so the state is readable.
	var left := float(def["duration"])
	var t := create_tween()
	t.set_loops(int(left / 0.09))
	t.tween_interval(0.09)
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			FX.impact(player.global_position, Color(0.65, 1.0, 0.7, 0.35), 0.6))


## Vault leaps to the cursor and lands hard. The escape doubles as the opener,
## which is what separates it from Dash - you aim it at something, not away.
func _do_vault(def: Dictionary) -> void:
	var to := player.get_global_mouse_position() - player.global_position
	var distance := minf(to.length(), float(def["distance"]))
	var dir := to.normalized() if to != Vector2.ZERO else player.aim_direction
	var duration := float(def["duration"])
	var radius := float(def["radius"])
	var damage := float(def["damage"])

	# A real leap, not a dash with a marker. begin_leap lifts the sprite off its
	# own shadow, shrinks the shadow toward the apex so the landing reads before
	# it lands, and drops the collision mask so the arc carries over trees.
	player.begin_leap(duration)
	player.velocity = dir * (distance / duration)
	FX.telegraph(player.global_position + dir * distance, radius, duration,
		Color(0.75, 0.95, 1.0))
	Audio.play("dash", -6.0)
	Game.shake(2.0, 0.12)

	var end := create_tween()
	end.tween_interval(duration)
	end.tween_callback(func() -> void:
		if not is_instance_valid(player):
			return
		player.end_leap()
		# Airborne means the arc passed over blockers, so the landing has to be
		# pushed to open ground or the player comes down inside a trunk.
		var layout := _layout()
		if layout != null and not layout.is_open(player.global_position):
			player.global_position = layout.nearest_open(player.global_position)
		player.velocity = dir * player.max_speed() * 0.5
		player.grant_landing_grace()
		var at := player.global_position
		FX.explosion(at, radius, Color(0.8, 0.95, 1.0))
		FX.ring(at, radius * 0.7, Color(0.85, 0.95, 1.0), 0.3, 0.15)
		Audio.play("explosion", -7.0)
		# A landing should land. Heavier than the take-off on purpose.
		Game.shake(Balance.SHAKE_EXPLOSION * 1.15, 0.32)
		var hit := Combat.explode(at, radius, damage, float(def["knockback"]),
			true, Combat.SOURCE_ABILITY)
		player.on_damage_dealt(damage * hit))


## A barrier at the cursor, laid across your line of sight to it - so it goes
## between you and whatever you are looking at, which is nearly always what you
## wanted.
func _do_thornwall(def: Dictionary) -> void:
	var target := player.get_global_mouse_position()
	var along := (target - player.global_position).angle() + PI * 0.5
	var w := THORNWALL.instantiate() as Node2D
	_container().add_child(w)
	w.call("setup", target, along, def)


func _do_cinders(def: Dictionary) -> void:
	var c := CINDERS.instantiate() as Node2D
	_container().add_child(c)
	c.call("setup", player.get_global_mouse_position(), def)


func _do_grenade(def: Dictionary) -> void:
	var target := player.get_global_mouse_position()
	var g := Pools.acquire(GRENADE, _container()) as Node2D
	g.call("throw_to", player.global_position, target, def)


func _do_shield(def: Dictionary) -> void:
	player.shield_absorb = float(def["absorb"])
	FX.ring(player.global_position, 120.0, Color(0.45, 0.8, 1.0), 0.5, 0.2)
	var t := create_tween()
	t.tween_interval(float(def["duration"]))
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.shield_absorb = 0.0)


func _do_timeslow(def: Dictionary) -> void:
	Combat.apply_slow(self, float(def["factor"]), float(def["duration"]))
	FX.ring(player.global_position, 900.0, Color(0.7, 0.75, 1.0), 0.8, 0.05)


func _do_nova(def: Dictionary) -> void:
	var radius := float(def["radius"])
	FX.ring(player.global_position, radius, Color(1.0, 0.85, 0.45), 0.45, 0.1)
	FX.burst(player.global_position, Color(1.0, 0.9, 0.6), 26, 1.8)
	var hit := Combat.explode(player.global_position, radius,
		float(def["damage"]), float(def["knockback"]), true, Combat.SOURCE_ABILITY)
	player.on_damage_dealt(float(def["damage"]) * hit)
	Game.shake(Balance.SHAKE_EXPLOSION, 0.35)


func _do_heal(def: Dictionary) -> void:
	player.heal(Game.run.max_hp * float(def["fraction"]))
	FX.ring(player.global_position, 140.0, Color(0.5, 1.0, 0.55), 0.5, 0.2)


## Chain lightning: hop from the nearest enemy outward, never repeating a
## target, drawing a bolt for each jump.
func _do_lightning(def: Dictionary) -> void:
	var damage := float(def["damage"])
	var jumps := int(def["jumps"])
	var jump_range := float(def["jump_range"])
	var hit: Array = []
	var from := player.global_position
	var total := 0.0

	for i in jumps:
		var target := Combat.nearest_enemy(from, jump_range, hit)
		if target == null:
			break
		hit.append(target)
		_draw_bolt(from, target.global_position)
		if target.has_method("take_damage"):
			target.call("take_damage", damage, false, from, 90.0, Combat.SOURCE_ABILITY)
			total += damage
		FX.burst(target.global_position, Color(0.75, 0.9, 1.0), 8, 0.9)
		from = target.global_position

	if hit.is_empty():
		FX.floating_text(player.global_position + Vector2(0, -70), "no target",
			Color(0.7, 0.7, 0.8))
	else:
		player.on_damage_dealt(total)
		Game.shake(2.6, 0.2)


func _draw_bolt(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 6.0
	line.default_color = Color(0.8, 0.92, 1.0)
	line.z_index = 80
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# jagged midpoints so it reads as lightning rather than a laser
	var steps := 6
	for i in range(steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t)
		if i > 0 and i < steps:
			var n := (b - a).normalized().orthogonal()
			p += n * randf_range(-22.0, 22.0)
		line.add_point(p)
	_container().add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "modulate:a", 0.0, 0.22)
	t.tween_callback(line.queue_free)


func _do_rapidfire(def: Dictionary) -> void:
	player.gun.fire_rate_multiplier = float(def["multiplier"])
	player.gun.free_reloads = true
	player.gun.refill()
	FX.ring(player.global_position, 110.0, Color(1.0, 0.7, 0.3), 0.4, 0.3)
	var t := create_tween()
	t.tween_interval(float(def["duration"]))
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.gun.fire_rate_multiplier = 1.0
			player.gun.free_reloads = false)


func _do_orbital(def: Dictionary) -> void:
	var orbs := ORBITAL.instantiate()
	_container().add_child(orbs)
	orbs.call("setup", player, def)


func _do_decoy(def: Dictionary) -> void:
	var d := DECOY.instantiate()
	_container().add_child(d)
	d.call("setup", player.global_position, def)


func _do_lifesteal(def: Dictionary) -> void:
	player.lifesteal_bonus = float(def["fraction"])
	FX.ring(player.global_position, 120.0, Color(0.85, 0.25, 0.35), 0.5, 0.25)
	var t := create_tween()
	t.tween_interval(float(def["duration"]))
	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.lifesteal_bonus = 0.0)
