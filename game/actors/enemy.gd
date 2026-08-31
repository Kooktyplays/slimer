class_name Enemy
extends CharacterBody2D
## Every non-boss enemy, configured by colour.
##
## One script rather than six, because the six variants differ in *numbers and
## one behaviour branch*, not in structure. Keeping them together is what
## guarantees the colour and the behaviour can't drift apart: `configure()`
## reads both out of the same EnemyTypes entry.
##
## Behaviours:
##   chase    (green)  - straight at you, in a pack
##   flank    (blue)   - fast, circles to your side before committing
##   tank     (red)    - slow, relentless, hits like a truck
##   ranged   (purple) - holds a preferred distance and shoots
##   skittish (yellow) - runs away, pays out big if you catch it
##   bomber   (orange) - closes and detonates
##   ward     (violet) - unflinching, immune to abilities: shoot it
##   turtle   (grey)   - hunkers behind a shell, immune to bullets: use a cooldown

const FLASH_SHADER := preload("res://assets/shaders/flash.gdshader")
const PROJECTILE := preload("res://weapons/projectile.tscn")
const FACE_NORMAL := preload("res://assets/sprites/gen/slime_face.png")
const FACE_ANGRY := preload("res://assets/sprites/gen/eyes_angry.png")

## Distant enemies think less often. At 55 enemies this is the difference
## between AI costing ~1 ms and ~4 ms a frame.
const LOD_NEAR := 900.0
const LOD_FAR_INTERVAL := 0.1

## The colour a deflected hit flashes. One colour for both immune types, so it
## reads as "that did nothing" rather than as a second thing to decode.
const DEFLECT_COLOR := Color(0.85, 0.88, 0.95)
const DEFLECT_TEXT_INTERVAL := 0.7

var _last_deflect_text := -1.0

@onready var _body: Sprite2D = $Visual/Body
@onready var _face: Sprite2D = $Visual/Body/Face
@onready var _crown: Sprite2D = $Visual/Body/Crown
@onready var _badge: Sprite2D = $Visual/Body/Badge
@onready var _visual: Node2D = $Visual
@onready var _shadow: Sprite2D = $Shadow
@onready var _shape: CollisionShape2D = $Shape
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/Shape

## Where Visual/Body sits inside Visual, before Visual's own scale is applied.
## Mirrors enemy.tscn. The drawn offset is this times the slime's visual scale,
## which is why hit_offset is computed per enemy rather than being a constant.
const BODY_LOCAL_Y := -32.0

## Offset from the physics origin - the feet, and where the shadow is drawn - to
## the middle of the drawn body, for this particular slime.
var hit_offset := Vector2.ZERO

# --- identity ---------------------------------------------------------------
var type_id: String = EnemyTypes.GREEN
var def: Dictionary = {}
var elite_mod: String = ""
var is_elite: bool = false

# --- stats ------------------------------------------------------------------
var max_hp := 30.0
var hp := 30.0
var speed := 110.0
var contact_damage := 8.0
var money_value := 5
var shield := 0.0
## A Combat.SOURCE_* tag this enemy takes no damage from, or "" for none.
var immune_to := ""
## Final collision radius in world pixels, matched to the drawn sprite.
var hit_radius := 30.0
## True for the Hoarder. Read by run.gd to drop the payout as a burst of coins
## rather than the usual handful.
var hoards := false

# --- state ------------------------------------------------------------------
var dying := false
var bullet_container: Node = null
var spawn_wave := 1

var _knockback := Vector2.ZERO
var _flash := 0.0
var _hop := 0.0
var _think_timer := 0.0
var _attack_timer := 0.0
var _contact_timer := 0.0
var _fuse_timer := -1.0
var _desired := Vector2.ZERO
var _flank_sign := 1.0
var _material: ShaderMaterial
var _spawn_anim := 0.0

## Carapace shell. Up = hunkered and bullet-proof, down = moving and open.
## The shell is what makes the type killable by a gun build at all - see the
## note on GREY in enemy_types.gd.
var _shell_up := false
var _shell_timer := 0.0
## Cached in configure(): _physics_process runs for every live enemy every
## frame, and at 68 concurrent that is 68 dictionary lookups and string
## compares a frame to ask a question whose answer cannot change.
var _is_turtle := false

## Phasing elites flicker out of reach on a cycle. Cycling rather than being a
## random dodge chance so the window is something the player can time, and so
## it can never be untargetable indefinitely.
var _phased := false
var _phase_timer := 0.0
const PHASE_OUT := 0.9
const PHASE_IN := 1.8

## Set each think by a nearby Warding elite, with an expiry rather than a flag
## the granter has to remember to clear - the granter usually dies, and a
## permanently warded pack would be a wave that a whole build cannot answer.
var _ward_until := 0.0
var _ward_tick := 0.0
## How often a Warding elite refreshes its aura. The grant lasts longer than
## the interval, so the aura is continuous while costing one area query every
## 0.15 s instead of one every frame - at 68 enemies that is the difference
## between a rounding error and a measurable cost.
const WARD_REFRESH := 0.15
const WARD_GRANT := 0.4

## Stuck handling. Enemies steer straight at their target with no pathfinding,
## which is fine in the open and fails in a pocket between two rocks: the
## slime grinds against geometry forever and the wave can never end.
##
## Two layers. A short nudge steers around most obstacles, and if an enemy is
## still pinned long after that, it is quietly relocated to a valid spawn
## point. The relocation is what makes "a wave can never hang on terrain" a
## guarantee rather than a hope.
const UNSTUCK_AFTER := 0.4
const UNSTUCK_DURATION := 0.75
const RELOCATE_AFTER := 9.0
const RELOCATE_MIN_DISTANCE := 700.0

var layout: ForestGenerator = null
var _stuck_time := 0.0
var _unstuck_timer := 0.0
var _unstuck_sign := 1.0
var _last_position := Vector2.ZERO


func _ready() -> void:
	# The body itself is no longer on the ENEMY layer - the Hurtbox is. The body
	# exists to collide with the forest at the slime's feet; the hurtbox is what
	# bullets and abilities look for, and it covers the drawn slime.
	collision_layer = 0
	collision_mask = Layers.WORLD
	_hurtbox.collision_layer = Layers.ENEMY
	_hurtbox.collision_mask = 0
	add_to_group("enemies")
	_material = ShaderMaterial.new()
	_material.shader = FLASH_SHADER
	_body.material = _material
	_shadow.modulate = Color(0, 0, 0, 0.26)


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
func configure(id: String, wave: int, elite: String = "") -> void:
	type_id = id
	def = EnemyTypes.get_def(id)
	spawn_wave = wave
	elite_mod = elite
	is_elite = not elite.is_empty()
	dying = false

	var hp_mul := Balance.hp_scale(wave)
	var dmg_mul := Balance.damage_scale(wave, Game.is_nightmare())
	var spd_mul := Balance.speed_scale(wave)

	max_hp = float(def["hp"]) * hp_mul
	speed = float(def["speed"]) * spd_mul
	contact_damage = float(def["contact_damage"]) * dmg_mul
	money_value = int(round(randi_range(def["money"].x, def["money"].y)
		* Balance.money_scale(wave)))
	hoards = bool(def.get("hoards", false))
	immune_to = String(def.get("immune_to", ""))
	# Start shelled, but stagger the cycle so a pack does not open and close in
	# unison - that would turn a group into one big binary window.
	_is_turtle = String(def["behavior"]) == "turtle"
	_shell_up = true
	_shell_timer = float(def.get("shell_up", 0.0)) * randf_range(0.35, 1.0)
	_phased = false
	_phase_timer = PHASE_IN * randf_range(0.3, 1.0)
	_ward_until = 0.0
	_ward_tick = 0.0
	# Both of these MUST be restored here, not just in _ready. Enemies are
	# pooled: a Phasing elite that died while phased would otherwise be handed
	# back out as an ordinary slime with its hurtbox layer still cleared and
	# its sprite still faded - permanently untargetable, and a wave that can
	# never end.
	_hurtbox.collision_layer = Layers.ENEMY
	_visual.modulate.a = 1.0

	var visual_scale := float(def["scale"])
	shield = 0.0

	if is_elite:
		max_hp *= Balance.ELITE_HP_MULTIPLIER
		contact_damage *= Balance.ELITE_DAMAGE_MULTIPLIER
		money_value = int(money_value * Balance.ELITE_MONEY_MULTIPLIER)
		visual_scale *= Balance.ELITE_SCALE
		match elite:
			"shielded":
				shield = max_hp * 0.45
			"enraged":
				speed *= 1.5
				contact_damage *= 1.25
			"splitter":
				max_hp *= 1.1
			"volatile":
				# Slightly frail: it is dangerous when it dies, not while alive,
				# and stacking both would just be a better Brute.
				max_hp *= 0.8
			"vampiric":
				contact_damage *= 1.15
			"phasing":
				# It is untargetable a third of the time, so it does not also
				# need the full elite health pool on top.
				max_hp *= 0.75
			"warding":
				# The aura is the threat. Left at elite baseline.
				pass

	hp = max_hp
	_body.texture = load(EnemyTypes.texture_path(id))
	_face.texture = FACE_ANGRY if is_elite else FACE_NORMAL
	_crown.visible = is_elite
	if is_elite:
		_crown.texture = load(EnemyTypes.crown_path(id))
	# The shape that says what this one does, for players who cannot read the
	# colour - and for everyone, on the two types where the colour is subtle.
	_badge.texture = load(EnemyTypes.badge_path(id))
	refresh_badge()
	_visual.scale = Vector2.ONE * visual_scale
	_shadow.scale = Vector2.ONE * visual_scale * 0.9
	hit_radius = float(def["radius"]) * (Balance.ELITE_SCALE if is_elite else 1.0)
	_apply_hit_shapes(visual_scale)

	_material.set_shader_parameter("flash", 0.0)
	_material.set_shader_parameter("flash_color", Color.WHITE)
	_knockback = Vector2.ZERO
	velocity = Vector2.ZERO
	_attack_timer = randf() * 1.5
	_contact_timer = 0.0
	_fuse_timer = -1.0
	_flank_sign = 1.0 if randf() < 0.5 else -1.0
	_think_timer = randf() * LOD_FAR_INTERVAL
	_spawn_anim = 1.0
	_stuck_time = 0.0
	_unstuck_timer = 0.0
	_last_position = global_position
	visible = true
	set_physics_process(true)
	Combat.register_enemy(self)
	Events.enemy_spawned.emit(self)


# ---------------------------------------------------------------------------
# per-frame
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if dying:
		return
	var scaled := delta * Combat.enemy_time_scale

	# Ranged attack cooldown, counted once per frame on real elapsed time so it
	# does not depend on how often _think() happens to run.
	_attack_timer = maxf(0.0, _attack_timer - scaled)
	if _is_turtle:
		_tick_shell(scaled)
	if is_elite:
		_tick_elite(scaled)

	_think_timer -= delta
	var target := _target_position()
	var near := global_position.distance_squared_to(Combat.player_position()) < LOD_NEAR * LOD_NEAR
	if near or _think_timer <= 0.0:
		_think(target)
		_think_timer = LOD_FAR_INTERVAL

	# steering: desired direction plus separation from neighbours, so a pack
	# spreads into a crescent instead of stacking into one fat slime
	var move := _desired
	if _unstuck_timer > 0.0:
		move = move.rotated(_unstuck_sign * 1.15)
	if near:
		move += _separation() * 0.85
	velocity = move.normalized() * _current_speed() * Combat.enemy_time_scale

	if _knockback.length_squared() > 4.0:
		velocity += _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)

	move_and_slide()
	_update_stuck(scaled)
	_tick_contact(scaled, target)
	_animate(delta)


func _update_stuck(delta: float) -> void:
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	_unstuck_timer = maxf(0.0, _unstuck_timer - delta)

	var wants_to_move := _desired.length_squared() > 0.01
	var expected := _current_speed() * delta * 0.35
	if wants_to_move and moved < expected:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 3.0)

	if _stuck_time > UNSTUCK_AFTER and _unstuck_timer <= 0.0:
		_unstuck_sign = 1.0 if randf() < 0.5 else -1.0
		_unstuck_timer = UNSTUCK_DURATION

	if _stuck_time > RELOCATE_AFTER:
		_relocate()


## Move a hopelessly pinned enemy to fresh ground. Only ever done well away
## from the player, so it can't be seen happening.
func _relocate() -> void:
	_stuck_time = 0.0
	var player_pos := Combat.player_position()
	if global_position.distance_to(player_pos) < RELOCATE_MIN_DISTANCE:
		return                                  # too close - would be visible
	var angle := randf() * TAU
	var dest := player_pos + Vector2.RIGHT.rotated(angle) * Balance.SPAWN_MIN_DISTANCE
	if layout != null:
		dest = layout.nearest_open(dest)
	global_position = dest
	_last_position = dest
	velocity = Vector2.ZERO


## Every enemy is slower than the player, which is correct in a fight and
## miserable at the end of a wave: one straggler on the far side of the map
## turns the last thirty seconds into a walk. Enemies that fall a long way
## behind hustle back into the fight.
##
## Skittish yellows are exempt - running away is their whole job.
const CATCHUP_DISTANCE := 1100.0
const CATCHUP_MULTIPLIER := 2.1


func _current_speed() -> float:
	if String(def["behavior"]) == "skittish":
		return speed
	var d := global_position.distance_to(Combat.player_position())
	if d <= CATCHUP_DISTANCE:
		return speed
	var over := clampf((d - CATCHUP_DISTANCE) / 900.0, 0.0, 1.0)
	return speed * lerpf(1.0, CATCHUP_MULTIPLIER, over)


## Enemies chase a decoy in preference to the player - that's the whole point
## of Effigy, and putting the check here means every behaviour respects it.
func _target_position() -> Vector2:
	var lure := preload("res://abilities/decoy.gd").find_for(global_position, get_tree())
	if lure != null:
		return lure.global_position
	return Combat.player_position()


func _think(target: Vector2) -> void:
	var to_target := target - global_position
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.001)

	# Mop-up: the wave is nearly over, so stop evading and come and finish it.
	# Spitters still shoot on the way in; they just stop kiting.
	if Combat.finisher_mode:
		_desired = dir
		if String(def["behavior"]) == "ranged":
			_try_shoot(dist, dir)
		return

	match String(def["behavior"]):
		"chase", "tank":
			_desired = dir

		"flank":
			# swing wide while far, commit straight in once close
			if dist > 260.0:
				_desired = (dir.rotated(_flank_sign * 0.85)).normalized()
			else:
				_desired = dir
			if randf() < 0.02:
				_flank_sign = -_flank_sign

		"ranged":
			var preferred := float(def["preferred_range"])
			var retreat := float(def["retreat_range"])
			if dist < retreat:
				_desired = -dir + dir.orthogonal() * 0.6 * _flank_sign
			elif dist > preferred * 1.15:
				_desired = dir
			else:
				# hold the line and strafe, so they're not static targets
				_desired = dir.orthogonal() * _flank_sign * 0.75
			_try_shoot(dist, dir)

		"skittish":
			var flee := float(def["flee_range"])
			if dist < flee:
				_desired = (-dir + dir.orthogonal() * 0.45 * _flank_sign).normalized()
			else:
				# drift lazily once safe, rather than fleeing to the map edge
				_desired = dir * 0.25

		"bomber":
			_desired = dir
			if dist < float(def["fuse_range"]) and _fuse_timer < 0.0:
				_start_fuse()

		"ward":
			# Straight at you and nothing else. No flanking, no spacing, no
			# flinching - the point is that it keeps coming while your
			# cooldowns do nothing to it.
			_desired = dir

		"turtle":
			# Shelled means planted. Standing still is the tell: you can read
			# whether bullets will work right now from across the screen,
			# without reading its colour.
			_desired = Vector2.ZERO if _shell_up else dir

		_:
			_desired = dir

	_desired = _desired.normalized()


## Size this slime's collision and hurt shapes.
##
## Both shapes are built fresh per enemy rather than edited in place. A shape
## declared in a .tscn is one resource shared by every instance of that scene,
## so the old `(_shape.shape as CircleShape2D).radius = hit_radius` did not
## resize this slime - it resized *every* slime, to whatever spawned most
## recently. A Brute and a Darter ended up with identical hitboxes, which is a
## large part of why shots that visibly connected did nothing.
##
## The body circle stays at the feet: that is what walks into trees, and moving
## it would change how the slime navigates the forest. The hurtbox is a separate
## capsule covering everything the player can see - from under the shadow up to
## the top of the drawn sprite - so aiming at the slime works, and so does
## aiming at the shadow, which is what players had learned to do.
func _apply_hit_shapes(visual_scale: float) -> void:
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	_shape.shape = circle

	hit_offset = Vector2(0, BODY_LOCAL_Y * visual_scale)

	# The sprite's real drawn extent, not a guess: the texture varies per colour
	# and the scale varies per type and with the elite bonus.
	var drawn_height := 0.0
	if _body.texture != null:
		drawn_height = _body.texture.get_height() * visual_scale
	var top := hit_offset.y - drawn_height * 0.5
	var bottom := hit_radius
	var capsule := CapsuleShape2D.new()
	capsule.radius = hit_radius
	capsule.height = maxf(bottom - top, hit_radius * 2.0)
	_hurtbox_shape.shape = capsule
	_hurtbox_shape.position = Vector2(0, (top + bottom) * 0.5)


## Re-read the enemy-marker setting. Called on every live enemy when the
## setting is toggled, so the change is visible immediately.
func refresh_badge() -> void:
	_badge.visible = bool(Save.settings.get("enemy_badges", true))


## Where the slime is actually drawn, relative to its physics origin. Abilities
## measure from here so area damage agrees with the bullets and with the player.
func hit_center() -> Vector2:
	return global_position + hit_offset


## Push apart from nearby enemies. Only samples enemies that are actually
## close, so this stays cheap even in a big wave.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	# Most types keep a loose personal space. Hoarders keep a much wider one, so
	# a pack of them spreads out instead of clumping into one convenient target -
	# hunting them down should mean chasing each one.
	var radius := hit_radius * float(def.get("separation_scale", 2.1))
	for other: Node2D in Combat.enemies_in_radius(global_position, radius):
		if other == self:
			continue
		var away := global_position - other.global_position
		var d := away.length()
		if d > 0.01:
			push += away / d * (1.0 - d / radius)
	return push.limit_length(1.0)


## Check and reset only. The countdown itself lives in _physics_process, on
## real elapsed time.
##
## This used to subtract a fixed LOD_FAR_INTERVAL here, which assumed the
## function ran at 10 Hz. It doesn't: _think() runs every physics frame while
## the enemy is within LOD_NEAR, which is exactly when it is shooting at you.
## The timer drained six times too fast and Spitters fired every ~0.35 s
## instead of every 2.1 s.
func _try_shoot(dist: float, dir: Vector2) -> void:
	if _attack_timer > 0.0 or dist > float(def["preferred_range"]) * 1.5:
		return
	_attack_timer = float(def["attack_cooldown"]) / Balance.speed_scale(spawn_wave)
	# Deferred: this runs inside _physics_process, and adding a CollisionObject
	# to the tree while the physics server is flushing queries is rejected.
	_spawn_bullet.call_deferred(dir)


func _spawn_bullet(dir: Vector2) -> void:
	if dying or not is_inside_tree():
		return
	var b := Pools.acquire(PROJECTILE, _container()) as Node2D
	b.call("launch", global_position + dir * 26.0, dir, {
		"damage": (float(def["projectile_damage"])
			* Balance.damage_scale(spawn_wave, Game.is_nightmare())),
		"speed": float(def["projectile_speed"]),
		"range": float(def["preferred_range"]) * 2.2,
		"from_player": false,
		"color": def["tint"],
		"scale": 1.15,
	})
	Audio.play_throttled("enemy_shoot", 0.07, -17.0, 0.2)
	Events.enemy_shot_fired.emit(self)
	_squash(1.25)


func _start_fuse() -> void:
	_fuse_timer = float(def["fuse_time"])
	FX.telegraph(global_position, float(def["blast_radius"]), _fuse_timer,
		Color(1.0, 0.45, 0.12))
	Audio.play("telegraph", -12.0)


func _tick_contact(delta: float, _target: Vector2) -> void:
	if _fuse_timer > 0.0:
		_fuse_timer -= delta
		# the telegraph is placed once, but the bomber keeps moving, so the
		# blast lands where it actually is
		if _fuse_timer <= 0.0:
			_detonate()
			return

	_contact_timer = maxf(0.0, _contact_timer - delta)
	if contact_damage <= 0.0 or _contact_timer > 0.0:
		return
	var p := Combat.player()
	if p == null:
		return
	var reach := hit_radius + Balance.PLAYER_RADIUS
	if global_position.distance_to(p.global_position) <= reach:
		p.call("take_damage", contact_damage, false, global_position, 0.0)
		# ...and leave poison behind. The instant hit is capped by
		# Balance.damage_scale; this is what keeps a wall of slimes dangerous
		# once the player's max HP has outgrown it. See CONTACT_POISON_FRACTION.
		if p.has_method("apply_poison"):
			p.call("apply_poison",
				contact_damage * Balance.CONTACT_POISON_FRACTION,
				Balance.CONTACT_POISON_DURATION)
		if elite_mod == "vampiric":
			# Off damage *dealt*, so it is answered by not being touched rather
			# than by out-damaging it. Capped at max_hp, so this can stall a
			# kill but never reverse one past full.
			hp = minf(max_hp, hp + contact_damage * 0.75)
			FX.floating_text(hit_center() + Vector2(0, -46), "+",
				Color(0.9, 0.35, 0.45))
		_contact_timer = 0.85
		_squash(1.35)


func _detonate() -> void:
	var radius := float(def["blast_radius"])
	var damage := (float(def["blast_damage"])
		* Balance.damage_scale(spawn_wave, Game.is_nightmare()))
	if is_elite:
		damage *= Balance.ELITE_DAMAGE_MULTIPLIER
	FX.explosion(global_position, radius)
	Audio.play("explosion", -6.0)
	Game.shake(Balance.SHAKE_EXPLOSION * 0.7, 0.3)
	Combat.explode_on_player(global_position, radius, damage)
	# bloaters also hurt each other, which is what makes a cluster of them
	# a genuine opportunity rather than only a threat
	for e: Node2D in Combat.enemies_in_radius(global_position, radius):
		if e != self and e.has_method("take_damage"):
			e.call("take_damage", damage * 0.5, false, global_position, 260.0)
	die(false)


# ---------------------------------------------------------------------------
# animation
# ---------------------------------------------------------------------------
func _animate(delta: float) -> void:
	var moving := velocity.length() > 12.0
	_hop += delta * (5.0 + (speed / 40.0 if moving else 0.0))
	var bounce := absf(sin(_hop))
	var base: float = float(def["scale"]) * (Balance.ELITE_SCALE if is_elite else 1.0)

	# the pack's slime squashes on landing and stretches at the top of its hop
	var squash := 1.0 + bounce * 0.10 - 0.05
	_visual.scale = Vector2(base * (2.0 - squash), base * squash)
	_visual.position.y = -bounce * (4.0 + (10.0 if moving else 0.0))
	_shadow.scale = Vector2.ONE * base * (0.95 - bounce * 0.12)
	_shadow.modulate.a = 0.26 - bounce * 0.06

	if velocity.x != 0.0:
		_body.flip_h = velocity.x < 0.0

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		_material.set_shader_parameter("flash", _flash)

	# a quick pop-in so spawns are visible rather than just appearing
	if _spawn_anim > 0.0:
		_spawn_anim = maxf(0.0, _spawn_anim - delta * 4.0)
		var t := 1.0 - _spawn_anim
		_visual.scale *= 0.3 + 0.7 * t
		_visual.rotation = _spawn_anim * 0.4 * _flank_sign


func _squash(amount: float) -> void:
	_visual.scale = Vector2(_visual.scale.x * amount, _visual.scale.y / amount)


# ---------------------------------------------------------------------------
# damage and death
# ---------------------------------------------------------------------------
func take_damage(amount: float, is_crit: bool = false, from: Vector2 = Vector2.ZERO,
		knockback: float = 0.0, source: String = Combat.SOURCE_OTHER) -> void:
	if dying:
		return

	# Warded shrugs off abilities, Carapace shrugs off bullets. The deflect has
	# to be as loud as a hit or the player reads "I missed" instead of "that
	# does not work on this one", and goes on missing.
	if _is_immune(source):
		_deflect(from)
		return

	var applied := amount
	if shield > 0.0:
		var absorbed := minf(shield, applied)
		shield -= absorbed
		applied -= absorbed
		_material.set_shader_parameter("flash_color", Color(0.6, 0.85, 1.0))
		if shield <= 0.0:
			FX.ring(global_position, 70.0, Color(0.5, 0.8, 1.0), 0.3, 0.4)
			_material.set_shader_parameter("flash_color", Color.WHITE)
	else:
		# clears the tint a deflect leaves behind, so a hit that lands looks
		# like a hit that lands
		_material.set_shader_parameter("flash_color", Color.WHITE)
	hp -= applied
	_flash = 1.0
	_material.set_shader_parameter("flash", 1.0)

	if knockback > 0.0 and from != Vector2.ZERO and not bool(def.get("unflinching", false)):
		var away := (global_position - from).normalized()
		# heavier enemies are harder to shove
		var resist: float = 1.0 / maxf(1.0, float(def["hp"]) / 40.0)
		_knockback += away * knockback * resist

	FX.damage_number(global_position + Vector2(0, -50), amount, is_crit)
	Events.enemy_damaged.emit(self, amount, is_crit, global_position)

	var p := Combat.player()
	if p != null and p.has_method("on_damage_dealt"):
		p.call("on_damage_dealt", minf(applied, maxf(hp, 0.0) + applied))

	# enraged elites speed up as they get hurt
	if elite_mod == "enraged" and hp < max_hp * 0.5:
		speed = float(def["speed"]) * Balance.speed_scale(spawn_wave) * 1.85

	if hp <= 0.0:
		die(true)


## Open and close the Carapace's shell. Both transitions are visible: it stops
## dead when it shells up and lurches forward when it opens, so the window a
## gun build has to shoot is legible from motion alone.
func _tick_shell(delta: float) -> void:
	_shell_timer -= delta
	if _shell_timer > 0.0:
		return
	_shell_up = not _shell_up
	_shell_timer = float(def.get("shell_up" if _shell_up else "shell_down", 1.5))
	_squash(1.22 if _shell_up else 0.82)
	if _shell_up:
		FX.ring(hit_center(), hit_radius * 1.5, DEFLECT_COLOR, 0.25, 0.35)


## Elite behaviour that runs on a clock rather than on an event.
func _tick_elite(delta: float) -> void:
	match elite_mod:
		"phasing":
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_phased = not _phased
				_phase_timer = PHASE_OUT if _phased else PHASE_IN
				# The hurtbox is what bullets look for, so dropping its layer
				# is what actually makes it untargetable rather than merely
				# invulnerable - shots pass through instead of pinging off.
				_hurtbox.collision_layer = 0 if _phased else Layers.ENEMY
				var t := create_tween()
				t.tween_property(_visual, "modulate:a", 0.25 if _phased else 1.0, 0.18)
				if not _phased:
					FX.ring(hit_center(), hit_radius * 1.4,
						Color(0.75, 0.7, 0.95), 0.25, 0.3)
		"warding":
			_ward_tick -= delta
			if _ward_tick <= 0.0:
				_ward_tick = WARD_REFRESH
				_ward_neighbours()


## Lend ability-immunity to everything nearby, on a short expiry.
##
## Pushed onto neighbours rather than read from them: the check in _is_immune
## runs on every single hit, and walking the enemy list there would put an
## area query in the hottest path in the game. Refreshing on the think tick
## costs one query per Warding elite instead.
func _ward_neighbours() -> void:
	var until := Time.get_ticks_msec() / 1000.0 + WARD_GRANT
	for e: Node2D in Combat.enemies_in_radius(hit_center(),
			EnemyTypes.WARD_AURA_RADIUS):
		if e == self or e.is_in_group("boss"):
			continue
		e.set("_ward_until", until)
	# Drawn every couple of seconds rather than every frame: the player has to
	# be able to see which slime is doing this, without a strobe.
	if _flash <= 0.0 and randf() < 0.02:
		FX.ring(hit_center(), EnemyTypes.WARD_AURA_RADIUS,
			Color(0.7, 0.6, 0.95, 0.5), 0.6, 0.25)


## Whether `source` bounces off this enemy right now.
##
## Warded's immunity is permanent; Carapace's holds only while the shell is up.
func _is_immune(source: String) -> bool:
	# Phasing is out of reach of everything while it is out - it is a window to
	# time, not a source to counter.
	if _phased:
		return true
	# A Warding elite lends its neighbours the Warded slime's trick. Bullets
	# still work, which is what stops an aura from being unanswerable: the
	# player always has a gun.
	if source == Combat.SOURCE_ABILITY \
			and Time.get_ticks_msec() / 1000.0 < _ward_until:
		return true
	if immune_to.is_empty() or source != immune_to:
		return false
	return _shell_up if _is_turtle else true


## What a hit looks like when it does nothing. Deliberately not silent: an
## unanswered hit that shows no feedback at all is indistinguishable from a
## bullet that missed.
func _deflect(from: Vector2) -> void:
	var at := hit_center()
	var edge := at
	if from != Vector2.ZERO:
		edge = at + (from - at).normalized() * hit_radius
	FX.impact(edge, DEFLECT_COLOR, 0.7)
	# The spark fires on every deflected hit, the word does not. A held trigger
	# on a Carapace is ~8 hits a second, and eight "IMMUNE" labels a second
	# stops being information and becomes a wall of text over the fight.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_deflect_text > DEFLECT_TEXT_INTERVAL:
		_last_deflect_text = now
		FX.floating_text(at + Vector2(0, -60), "IMMUNE", DEFLECT_COLOR)
	Audio.play_throttled("deflect", 0.08, -12.0, 0.15)
	_material.set_shader_parameter("flash_color", DEFLECT_COLOR)
	_flash = 0.6
	_material.set_shader_parameter("flash", 0.6)


func die(award: bool = true) -> void:
	if dying:
		return
	dying = true
	set_physics_process(false)
	Combat.unregister_enemy(self)
	remove_from_group("enemies")

	var at := global_position
	if award:
		FX.burst(at, def["tint"], 14 if not is_elite else 22, 1.0 if not is_elite else 1.5)
		Audio.play_throttled("enemy_death", 0.05, -11.0, 0.18)
		if elite_mod == "volatile":
			# Deferred for the same reason as _split: death usually arrives
			# from a bullet's body_entered, mid physics flush.
			_detonate_volatile.call_deferred(at, spawn_wave)
		if elite_mod == "splitter":
			# deferred for the same reason as _spawn_bullet: death usually
			# arrives from a bullet's body_entered, mid physics flush
			_split.call_deferred(at, type_id, spawn_wave)
	Events.enemy_died.emit(self, at)
	Pools.release(self)


## Volatile elites leave a blast behind them, which turns every kill into a
## question of where you were standing when you took it.
##
## Takes its arguments explicitly because it runs deferred, by which point this
## enemy has been recycled and its fields have moved on - the same reason
## _split does.
func _detonate_volatile(at: Vector2, for_wave: int) -> void:
	var radius := 200.0
	var damage := 22.0 * Balance.damage_scale(for_wave, Game.is_nightmare())
	FX.explosion(at, radius, Color(1.0, 0.55, 0.3))
	Audio.play("explosion", -7.0)
	Game.shake(Balance.SHAKE_EXPLOSION * 0.6, 0.25)
	Combat.explode_on_player(at, radius, damage)
	# It hurts the pack too, exactly like a Bloater, which is what makes a
	# volatile in a crowd an opportunity as well as a threat. Untagged, so it
	# lands on Warded and Carapace alike.
	Combat.explode(at, radius, damage * 0.5, 220.0, true, Combat.SOURCE_OTHER)


## Splitter elites break into two ordinary slimes of the same colour.
## Takes its arguments explicitly because it runs deferred, by which point
## this enemy has already been recycled and its own fields have moved on.
func _split(at: Vector2, id: String, for_wave: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var spawner := tree.get_first_node_in_group("wave_controller")
	if spawner == null or not spawner.has_method("spawn_split"):
		return
	for i in 2:
		var offset := Vector2.RIGHT.rotated(randf() * TAU) * 46.0
		spawner.call("spawn_split", id, at + offset, for_wave)


func _container() -> Node:
	if bullet_container != null and is_instance_valid(bullet_container):
		return bullet_container
	return get_parent()


func _pool_reset() -> void:
	dying = true
	set_physics_process(false)
	Combat.unregister_enemy(self)
	if is_in_group("enemies"):
		remove_from_group("enemies")
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_visual.rotation = 0.0
	_visual.modulate.a = 1.0
