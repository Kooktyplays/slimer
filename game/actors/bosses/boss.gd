class_name Boss
extends CharacterBody2D
## Boss actor: entrance, phases, telegraphed attack patterns, defeat.
##
## Attack damage is deliberately heavy - roughly 55% above where it started -
## and that is paired with the forgiveness pass rather than stacked on top of
## it. Post-hit invulnerability went 0.55s to 0.78s, so boss hits land less
## often; making each one hurt much more trades frequency for weight, which is
## the readable version. Raising both would just be unfair.
##
## The floor on that trade is that no single attack may kill a full-health
## player outright, at any wave. A telegraph is a promise that reacting to it
## is worth something, and a one-shot breaks that promise. There is a test.
##
## Every attack follows the same contract - wind up with a visible telegraph
## and a distinct sound, *then* hit. A boss that can damage you without
## warning is a boss you can only survive by luck, and the whole point of
## these fights is that they can be learned.
##
## Nine of the attacks below are shared across archetypes; which ones a boss
## can use, and in which phase, comes from BossDB. Each boss also owns exactly
## one **signature** attack that nobody else has - without those, five bosses
## drawing from one pool were five HP bars with the same moveset.
##
## Phases *replace* rather than append. A phase that was the previous phase
## plus two more entries only changed how often you were attacked; a phase that
## drops what you learned and brings something else changes how you fight.

const PROJECTILE := preload("res://weapons/projectile.tscn")

## Health the Sovereign gains per enemy consumed by Devour, before wave
## scaling. Flat on purpose - see _ult... see _atk_devour.
const DEVOUR_HEAL_PER_ENEMY := 22.0
## Bramble's Snare grows real barriers. Same scene the Thornwall ability uses,
## so a boss wall and a player wall obey exactly the same rules.
const THORNWALL := preload("res://abilities/thornwall.tscn")

signal defeated(boss: Boss)

@onready var _body: Sprite2D = $Visual/Body
@onready var _eyes: Sprite2D = $Visual/Body/Eyes
@onready var _visual: Node2D = $Visual
@onready var _shadow: Sprite2D = $Shadow
@onready var _shape: CollisionShape2D = $Shape
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/Shape

## Where Visual/Body sits inside Visual, before Visual's own scale. Mirrors
## boss.tscn. Bosses are drawn a long way above their feet, so aiming at one and
## hitting nothing was at its worst here.
const BODY_LOCAL_Y := -78.0

## Offset from the physics origin to the middle of the drawn boss, for this
## boss's scale.
var hit_offset := Vector2.ZERO

var id := "bramble"
var def: Dictionary = {}
var display_name := "Boss"
var is_major := false
## True for the run's ending. Read by run.gd, which shows the ending the first
## time one of these is cleared.
var is_finale := false
var wave := 5
var repeat := 0

var max_hp := 1000.0
var hp := 1000.0
var phase := 1
var phase_count := 2
var dying := false
var active := false

var bullet_container: Node = null
var spawner: WaveController = null
var layout: ForestGenerator = null

var _damage_scale := 1.0
var _attack_timer := 2.0
var _flash := 0.0
var _hop := 0.0
var _material: ShaderMaterial
var _busy := false
var _contact_timer := 0.0
var _charge_velocity := Vector2.ZERO
var _charging := false
var _projectile_texture: Texture2D
var _rng := RandomNumberGenerator.new()

## Pose frames on the body strip: idle, the wind-up crouch, the strike.
##
## These are the two moments the fight already stops for. Every attack calls
## _wind_up() and then lands on a tween callback, and until now both of those
## were carried by a scale tween on a single static sprite - which is most of
## why Notion's read on the bosses was "rigid".
const POSE_IDLE := 0
const POSE_WINDUP := 1
const POSE_STRIKE := 2
const POSE_COUNT := 3
## Must mirror BOSS_POSES in tools/gen_art.py. The eyes are a child of the body
## sprite, so hframes does not move them - they have to be transformed to match
## the pose or the Ancient Oak ends up looking at its own shoulder.
const POSE_SQUASH: Array[float] = [1.00, 0.88, 1.00]
const POSE_STRETCH: Array[float] = [1.00, 1.08, 0.90]

var _eye_home := Vector2.ZERO
## Final collision radius in world pixels, matched to the drawn sprite.
var hit_radius := 110.0


func _ready() -> void:
	# The hurtbox carries the ENEMY layer; the body only collides with the
	# forest. See Enemy._apply_hit_shapes for why.
	collision_layer = 0
	_hurtbox.collision_layer = Layers.ENEMY
	_hurtbox.collision_mask = 0
	collision_mask = Layers.WORLD
	add_to_group("enemies")
	add_to_group("boss")
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/shaders/flash.gdshader")
	_body.material = _material


# ---------------------------------------------------------------------------
# setup and entrance
# ---------------------------------------------------------------------------
func configure(boss_id: String, for_wave: int, repeat_index: int) -> void:
	id = boss_id
	def = BossDB.get_def(boss_id)
	wave = for_wave
	repeat = repeat_index
	is_major = bool(def["major"])
	is_finale = Game.is_finale_wave(for_wave)
	display_name = String(def["name"])
	phase_count = BossDB.phase_count(boss_id, repeat_index)
	phase = 1
	dying = false
	_rng.seed = for_wave * 104729 + repeat_index

	if is_finale:
		# Its own number: the major curve at wave 25 is shaped for wave 40 and
		# produces a boss the run cannot finish.
		max_hp = Balance.finale_boss_hp()
	else:
		max_hp = (Balance.major_boss_hp(for_wave) if is_major
			else Balance.mini_boss_hp(for_wave))
		max_hp *= 1.0 + 0.18 * repeat_index
	hp = max_hp
	_damage_scale = Balance.boss_damage_scale(for_wave)

	_body.texture = load(def["body"])
	_body.hframes = POSE_COUNT
	_eyes.texture = load(def["eyes"])
	_eyes.position = def["eye_offset"]
	_eye_home = def["eye_offset"]
	set_pose(POSE_IDLE)
	_projectile_texture = load(def["projectile"])

	var s := float(def["scale"]) * (1.0 + 0.06 * repeat_index)
	_visual.scale = Vector2.ONE * s
	_shadow.scale = Vector2.ONE * s * 2.4
	_shadow.modulate = Color(0, 0, 0, 0.30)
	hit_radius = float(def["radius"])
	# Fresh shapes per boss: a shape declared in a .tscn is shared by every
	# instance of that scene, so editing it in place resized every boss at once.
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	_shape.shape = circle
	# Hurtbox covers the drawn boss, from under the shadow to the top of the
	# sprite; the body circle stays at the feet for navigation. See
	# Enemy._apply_hit_shapes for the reasoning.
	hit_offset = Vector2(0, BODY_LOCAL_Y * s)
	var drawn_height := 0.0
	if _body.texture != null:
		drawn_height = _body.texture.get_height() * s
	var top := hit_offset.y - drawn_height * 0.5
	var capsule := CapsuleShape2D.new()
	capsule.radius = hit_radius
	capsule.height = maxf(hit_radius - top, hit_radius * 2.0)
	_hurtbox_shape.shape = capsule
	_hurtbox_shape.position = Vector2(0, (top + hit_radius) * 0.5)
	_material.set_shader_parameter("flash", 0.0)
	_stuck_time = 0.0
	_unstuck_timer = 0.0
	_last_position = global_position
	Combat.register_enemy(self)


## Drop in with a slam, a shout and a camera punch, then start fighting.
func enter(at: Vector2) -> void:
	global_position = at
	visible = true
	active = false
	_busy = true
	_visual.scale *= 0.1
	_visual.modulate.a = 0.0

	Audio.play("boss_spawn", 2.0, 0.0)
	Events.boss_spawned.emit(self, display_name, is_major)

	var target_scale: float = float(def["scale"]) * (1.0 + 0.06 * repeat)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_visual, "modulate:a", 1.0, 0.35)
	t.tween_property(_visual, "scale", Vector2.ONE * target_scale, 0.75) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func() -> void:
		FX.ring(global_position, float(def["radius"]) * 3.2, def["tint"], 0.6, 0.05)
		FX.burst(global_position, def["tint"], 30, 2.0)
		Game.shake(Balance.SHAKE_BOSS_SLAM, 0.5))
	t.tween_interval(0.5)
	t.tween_callback(func() -> void:
		active = true
		_busy = false
		_attack_timer = 1.2)

	set_physics_process(true)


# ---------------------------------------------------------------------------
# per-frame
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if dying:
		return
	var scaled := delta * Combat.enemy_time_scale
	_animate(delta)

	if not active:
		return

	if _charging:
		velocity = _charge_velocity * Combat.enemy_time_scale
		move_and_slide()
		_tick_contact(scaled, true)
		return

	if not _busy:
		_move(scaled)
		_attack_timer -= scaled
		if _attack_timer <= 0.0:
			_choose_attack()

	_tick_contact(scaled, false)


func _move(delta: float) -> void:
	var target := Combat.player_position()
	var to_player := target - global_position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)
	var speed := float(def["speed"]) * (1.0 + 0.12 * (phase - 1))
	# Bosses are slow on purpose, which becomes dead time if the fight drifts
	# apart - a 64 px/s toad two screens away is half a minute of walking.
	if dist > 1200.0:
		speed *= lerpf(1.0, 2.6, clampf((dist - 1200.0) / 1200.0, 0.0, 1.0))

	# Bosses circle rather than beeline. Walking straight at the player is
	# both easy to kite and dull to fight.
	var orbit := 300.0 + hit_radius
	var want: Vector2
	if dist > orbit * 1.25:
		want = dir
	elif dist < orbit * 0.7:
		want = -dir
	else:
		want = dir.orthogonal() * (1.0 if (wave + phase) % 2 == 0 else -1.0)
	if _unstuck_timer > 0.0:
		want = want.rotated(_unstuck_sign * 1.2)
	velocity = want * speed
	move_and_slide()
	_update_stuck(delta)


## Bosses are wide enough to jam between two trees, and a jammed boss is an
## unwinnable run: it cannot reach the player and the player cannot shoot
## through the geometry pinning it. Nudge first, then force a reposition.
const UNSTUCK_AFTER := 0.5
const UNSTUCK_DURATION := 0.9
const RELOCATE_AFTER := 6.0

var _stuck_time := 0.0
var _unstuck_timer := 0.0
var _unstuck_sign := 1.0
var _last_position := Vector2.ZERO


func _update_stuck(delta: float) -> void:
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	_unstuck_timer = maxf(0.0, _unstuck_timer - delta)

	if moved < velocity.length() * delta * 0.3:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 3.0)

	if _stuck_time > UNSTUCK_AFTER and _unstuck_timer <= 0.0:
		_unstuck_sign = -_unstuck_sign
		_unstuck_timer = UNSTUCK_DURATION

	if _stuck_time > RELOCATE_AFTER:
		_reposition()


## Unlike an enemy's silent relocation, a boss moves in full view - so it is
## dressed as a deliberate blink rather than hidden.
func _reposition() -> void:
	_stuck_time = 0.0
	_unstuck_timer = 0.0
	var dest := Combat.player_position() \
		+ Vector2.RIGHT.rotated(randf() * TAU) * (420.0 + hit_radius)
	if layout != null:
		dest = layout.nearest_open_for(dest, hit_radius * 1.25)
	FX.burst(global_position, def["tint"], 18, 1.2)
	global_position = dest
	_last_position = dest
	velocity = Vector2.ZERO
	FX.ring(dest, hit_radius * 2.0, def["tint"], 0.4, 0.15)
	Audio.play("ability", -10.0)


func _tick_contact(delta: float, heavy: bool) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if _contact_timer > 0.0:
		return
	var p := Combat.player()
	if p == null:
		return
	var reach := hit_radius + Balance.PLAYER_RADIUS
	if global_position.distance_to(p.global_position) <= reach:
		var dmg := float(def["contact_damage"]) * _damage_scale * (1.6 if heavy else 1.0)
		p.call("take_damage", dmg, false, global_position, 0.0)
		_contact_timer = 0.9


func _animate(delta: float) -> void:
	_hop += delta * 2.6
	var bounce := absf(sin(_hop))
	var base: float = float(def["scale"]) * (1.0 + 0.06 * repeat)
	if not _busy and active:
		_visual.scale = Vector2(base * (1.0 + bounce * 0.035), base * (1.0 - bounce * 0.035))
	if bool(def.get("floats", false)):
		_visual.position.y = -30.0 - bounce * 14.0
		_shadow.modulate.a = 0.18
	else:
		_visual.position.y = -bounce * 5.0

	if velocity.x != 0.0:
		_body.flip_h = velocity.x < 0.0

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		_material.set_shader_parameter("flash", _flash)


# ---------------------------------------------------------------------------
# attack selection
# ---------------------------------------------------------------------------
func _available_attacks() -> Array:
	var phases: Array = def["phases"]
	var index := clampi(phase - 1, 0, phases.size() - 1)
	return phases[index]


func _choose_attack() -> void:
	var options := _available_attacks()
	if options.is_empty():
		_attack_timer = 2.0
		return
	var pick: String = options[_rng.randi() % options.size()]
	var interval: Vector2 = def["attack_interval"]
	# Later phases attack more often. Steepened from 0.13 to 0.19 per phase,
	# and floored: at 0.13 a phase-4 boss was still only 39% faster than its
	# phase 1, which is not enough to read as a different fight. The floor is
	# what stops the pace from collapsing to nothing on a deep repeat.
	var pace := maxf(1.0 - 0.19 * (phase - 1), 0.34)
	_attack_timer = _rng.randf_range(interval.x, interval.y) * pace

	match pick:
		"slam": _atk_slam()
		"radial": _atk_radial()
		"aimed_volley": _atk_aimed_volley()
		"charge": _atk_charge()
		"summon": _atk_summon()
		"spiral": _atk_spiral()
		"rain": _atk_rain()
		"shockwave": _atk_shockwave()
		"blink_radial": _atk_blink_radial()
		# signatures - one boss each
		"snare": _atk_snare()
		"tongue": _atk_tongue()
		"chorus": _atk_chorus()
		"rootquake": _atk_rootquake()
		"devour": _atk_devour()


func _telegraph_time() -> float:
	# tighter windows in later phases, but never so short it can't be reacted to
	return maxf(0.42, 0.85 - 0.11 * (phase - 1))


## Wind-up for a telegraphed attack. Callers chain the hit onto the returned
## tween, so this must run for exactly `duration` - the ground marker drawn by
## FX.telegraph fills over that same duration, and the two are a promise to the
## player that the hit lands when the fill meets the ring.
##
## The squash still eases over the first 70%; it used to be the *whole* tween,
## which meant every attack in the game landed 30% early. At phase 1 that turned
## a 0.85 s window into 0.595 s - and a slam you could not walk out of either
## way. The interval is what keeps the visual and the hitbox honest.
func _wind_up(duration: float) -> Tween:
	_busy = true
	velocity = Vector2.ZERO
	Audio.play("telegraph", -6.0)
	set_pose(POSE_WINDUP)
	var t := create_tween()
	# The scale tween is kept but softened from 0.85/1.18 to 0.94/1.07. It was
	# standing in for an anticipation pose the sprite did not have; now the
	# sprite has one, and running both at full strength deforms twice.
	t.tween_property(_visual, "scale", _visual.scale * Vector2(0.94, 1.07), duration * 0.7) \
		.set_ease(Tween.EASE_IN)
	t.tween_interval(duration * 0.3)
	t.tween_callback(func() -> void: set_pose(POSE_STRIKE))
	return t


## Switch pose, carrying the eyes with it.
##
## The body squashes about its feet, so the drawn face moves down by half of
## whatever height the pose lost. The eyes are offset by exactly that and
## scaled to match, which is what keeps them on the face instead of floating
## where the face used to be.
func set_pose(index: int) -> void:
	var i := clampi(index, 0, POSE_COUNT - 1)
	_body.frame = i
	var sq := POSE_SQUASH[i]
	var xs := POSE_STRETCH[i]
	var h := 0.0
	if _body.texture != null:
		h = float(_body.texture.get_height())
	_eyes.position = Vector2(_eye_home.x * xs,
		_eye_home.y * sq + (1.0 - sq) * h * 0.5)
	_eyes.scale = Vector2(xs, sq)


func _recover() -> void:
	_busy = false
	set_pose(POSE_IDLE)


# ---------------------------------------------------------------------------
# attacks
# ---------------------------------------------------------------------------
## Ground slam at the player's current position. Rewards moving on the tell.
func _atk_slam() -> void:
	var target := Combat.player_position()
	var radius := 250.0 + 30.0 * phase
	var lead := _telegraph_time()
	FX.telegraph(target, radius, lead, Color(1.0, 0.4, 0.2))

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		FX.explosion(target, radius, def["tint"])
		Audio.play("boss_attack", -1.0)
		Game.shake(Balance.SHAKE_BOSS_SLAM, 0.45)
		Combat.explode_on_player(target, radius, 38.0 * _damage_scale)
		_visual.scale = Vector2.ONE * float(def["scale"]) * (1.0 + 0.06 * repeat))
	t.tween_interval(0.25)
	t.tween_callback(_recover)


## Ring of projectiles. Leave a gap so it can be walked through - a perfect
## ring is a damage tax, a ring with a seam is a decision.
func _atk_radial() -> void:
	var count := 12 + 4 * phase
	var lead := _telegraph_time()
	FX.telegraph(global_position, 200.0, lead, Color(1.0, 0.7, 0.2))

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		var gap := _rng.randf() * TAU
		for i in count:
			var a := TAU * i / count
			if absf(angle_difference(a, gap)) < 0.42:
				continue
			_fire(Vector2.RIGHT.rotated(a), 330.0, 12.0)
		Audio.play("boss_attack", -6.0)
		FX.ring(global_position, 180.0, def["tint"], 0.35, 0.2))
	t.tween_interval(0.2)
	t.tween_callback(_recover)


func _atk_aimed_volley() -> void:
	var shots := 3 + phase
	var lead := _telegraph_time() * 0.8
	var t := _wind_up(lead)
	for i in shots:
		t.tween_callback(func() -> void:
			var dir := (Combat.player_position() - global_position).normalized()
			var spread := deg_to_rad(_rng.randf_range(-9.0, 9.0))
			_fire(dir.rotated(spread), 470.0, 14.0)
			Audio.play("enemy_shoot", -8.0, 0.12))
		t.tween_interval(0.14)
	t.tween_callback(_recover)


## Telegraphed line charge. The line is drawn before the boss moves, so the
## safe ground is unambiguous.
func _atk_charge() -> void:
	var target := Combat.player_position()
	var dir := (target - global_position).normalized()
	var distance := 620.0
	var lead := _telegraph_time() * 1.15

	var line := Line2D.new()
	# Line2D width is the full thickness, so this has to be twice the real reach.
	# It used to be radius * 1.8, drawing a half-width of 0.9 * radius while the
	# charge actually hits at radius + PLAYER_RADIUS - under-reporting its own
	# hitbox by 33-41 px, which is how the Sovereign one-shot players who
	# correctly stood just outside the line they were shown.
	line.width = (float(def["radius"]) + Balance.PLAYER_RADIUS) * 2.0
	line.default_color = Color(1.0, 0.35, 0.25, 0.28)
	line.z_index = 12
	line.add_point(global_position)
	line.add_point(global_position + dir * distance)
	get_parent().add_child(line)

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		line.queue_free()
		_charging = true
		_charge_velocity = dir * 1150.0
		Audio.play("boss_attack", 0.0)
		Game.shake(5.0, 0.3))
	t.tween_interval(distance / 1150.0)
	t.tween_callback(func() -> void:
		_charging = false
		_charge_velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		FX.ring(global_position, 220.0, def["tint"], 0.4, 0.2)
		Game.shake(6.0, 0.3))
	t.tween_interval(0.45)          # punished if you dodge: long recovery
	t.tween_callback(_recover)


func _atk_summon() -> void:
	if spawner == null:
		_recover()
		return
	var types: Array = def["summon_types"]
	var count := int(def["summon_count"]) + phase - 1
	var lead := _telegraph_time()

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		Audio.play("boss_phase", -8.0)
		for i in count:
			var a := TAU * i / count + _rng.randf()
			var at := global_position + Vector2.RIGHT.rotated(a) * _rng.randf_range(180.0, 330.0)
			var kind: String = types[_rng.randi() % types.size()]
			var elite := ""
			if bool(def.get("summon_elite", false)) and _rng.randf() < 0.25:
				elite = EnemyTypes.ELITE_MODS[_rng.randi() % EnemyTypes.ELITE_MODS.size()]
			spawner.spawn_at(kind, at, wave, elite)
			FX.ring(at, 70.0, def["tint"], 0.35, 0.2))
	t.tween_interval(0.3)
	t.tween_callback(_recover)


## Rotating stream. Forces continuous movement rather than one dodge.
func _atk_spiral() -> void:
	var arms := 2 + (1 if phase >= 3 else 0)
	var shots := 14 + 3 * phase
	var lead := _telegraph_time() * 0.7
	var spin := 0.28 * (1.0 if _rng.randf() < 0.5 else -1.0)

	var t := _wind_up(lead)
	var base := _rng.randf() * TAU
	for i in shots:
		t.tween_callback(func() -> void:
			for arm in arms:
				var a := base + i * spin + TAU * arm / arms
				_fire(Vector2.RIGHT.rotated(a), 300.0, 10.0))
		t.tween_interval(0.075)
	t.tween_callback(func() -> void:
		Audio.play("boss_attack", -8.0)
		_recover())


## Several telegraphed circles around the player, staggered so the safe spot
## keeps moving.
func _atk_rain() -> void:
	var drops := 4 + phase
	var radius := 165.0
	var lead := _telegraph_time()

	var t := _wind_up(lead * 0.6)
	for i in drops:
		t.tween_callback(func() -> void:
			var at := Combat.player_position() + Vector2.RIGHT.rotated(_rng.randf() * TAU) \
				* _rng.randf_range(0.0, 320.0)
			FX.telegraph(at, radius, lead, Color(0.95, 0.5, 0.9))
			var inner := create_tween()
			inner.tween_interval(lead)
			inner.tween_callback(func() -> void:
				FX.explosion(at, radius, def["tint"])
				Audio.play("explosion", -12.0)
				Combat.explode_on_player(at, radius, 25.0 * _damage_scale)))
		t.tween_interval(0.22)
	t.tween_interval(lead)
	t.tween_callback(_recover)


## Expanding ring centred on the boss. Outrun it or get clipped.
##
## This one needs a tell of its own, and specifically one that does not look like
## a slam: slam says "leave the spot you are standing on", shockwave says "get
## further away from me", and they were sharing the same squash and the same
## sound. Getting that backwards is a free hit either direction. So the ground
## marker here grows *outward from the boss* to the full radius, rather than
## filling a circle centred on the player.
func _atk_shockwave() -> void:
	var lead := _telegraph_time()
	var max_radius := 620.0

	# A ring at the final radius, and a fill that races out to meet it - the
	# opposite reading to slam's marker, and in the boss's own colour rather
	# than slam's warning orange.
	FX.telegraph(global_position, max_radius, lead, Color(0.45, 0.75, 1.0))

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		Audio.play("boss_phase", -3.0)
		Game.shake(7.0, 0.4)
		FX.ring(global_position, max_radius, def["tint"], 0.55, 0.08)
		var origin := global_position
		# damage is applied on a delay matched to the visual ring's travel, so
		# what hits you is what you can see
		for step in 5:
			var inner := create_tween()
			inner.tween_interval(0.55 * (float(step) / 5.0))
			inner.tween_callback(func() -> void:
				var r := max_radius * (float(step + 1) / 5.0)
				var p := Combat.player()
				if p == null:
					return
				var d := p.global_position.distance_to(origin)
				if d <= r and d > r - 130.0:
					p.call("take_damage", 31.0 * _damage_scale, false, origin, 0.0)))
	t.tween_interval(0.7)
	t.tween_callback(_recover)


## Vanish, reappear beside the player, immediately burst outward.
func _atk_blink_radial() -> void:
	var lead := _telegraph_time() * 0.8
	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		FX.burst(global_position, def["tint"], 18, 1.2)
		var dest := Combat.player_position() + Vector2.RIGHT.rotated(_rng.randf() * TAU) * 260.0
		if layout != null:
			dest = layout.nearest_open(dest)
		global_position = dest
		FX.ring(dest, 200.0, def["tint"], 0.4, 0.1)
		Audio.play("ability", -6.0)
		for i in 14:
			_fire(Vector2.RIGHT.rotated(TAU * i / 14.0), 350.0, 11.0))
	t.tween_interval(0.35)
	t.tween_callback(_recover)


# ---------------------------------------------------------------------------
# signature attacks - exactly one per boss
# ---------------------------------------------------------------------------
## BRAMBLE. Grows a ring of thorn walls around the player with a single gap.
## The gap is shown before the walls are solid, so this is a "move now, and
## know where to" - the opposite question to the boss's charge, which is "get
## off this line".
func _atk_snare() -> void:
	var center := Combat.player_position()
	var radius := 300.0
	var segments := 8
	var gap := _rng.randi() % segments
	var lead := _telegraph_time() * 1.2
	FX.telegraph(center, radius, lead, Color(0.45, 0.75, 0.35))

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		Audio.play("ability", -4.0)
		for i in segments:
			if i == gap:
				continue
			var a := TAU * i / segments
			var at := center + Vector2.RIGHT.rotated(a) * radius
			if layout != null and not layout.is_open(at):
				continue
			var wall: Node2D = THORNWALL.instantiate()
			get_parent().add_child(wall)
			# tangent to the ring, so the segments form a wall not a starburst
			wall.call("setup", at, a + PI * 0.5, {
				"duration": 4.5, "length": TAU * radius / float(segments) * 1.05,
			})
		FX.ring(center, radius, def["tint"], 0.5, 0.12))
	t.tween_interval(0.3)
	t.tween_callback(_recover)


## TOAD. A tongue lashes out along a drawn line and drags you back down it.
## Being pulled is the point: it does modest damage and puts you exactly where
## the Toadfather's slam wants you, which is why phase 3 pairs the two.
func _atk_tongue() -> void:
	var dir := (Combat.player_position() - global_position).normalized()
	var reach := 700.0
	var lead := _telegraph_time()

	var line := Line2D.new()
	line.width = 46.0
	line.default_color = Color(0.85, 0.35, 0.45, 0.30)
	line.z_index = 12
	line.add_point(global_position)
	line.add_point(global_position + dir * reach)
	get_parent().add_child(line)

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		line.default_color = Color(0.95, 0.45, 0.5, 0.85)
		Audio.play("boss_attack", -3.0)
		Game.shake(4.5, 0.25)
		var p := Combat.player()
		if p != null:
			# on the line, and within reach of it
			var to_p := p.global_position - global_position
			var along := to_p.dot(dir)
			var off := (to_p - dir * along).length()
			if along > 0.0 and along < reach and off < line.width * 0.5:
				p.call("take_damage", 22.0 * _damage_scale, false,
					global_position, 0.0)
				# Reeled in as a velocity impulse, not a position tween.
				# The player's _move() overwrites velocity every frame but
				# decays it *toward* the input target at PLAYER_ACCEL, so an
				# impulse survives several frames and - crucially - is resolved
				# by move_and_slide, which respects the forest. Setting the
				# position directly would drag the player through trees.
				p.velocity += -dir * 1450.0
				FX.ring(p.global_position, 90.0, Color(0.95, 0.45, 0.5), 0.3, 0.2))
	t.tween_interval(0.3)
	t.tween_callback(func() -> void:
		line.queue_free()
		_recover())


## WISP. Splits into a choir of echoes that all fire at once. Only the real one
## can be hurt - the echoes are pure visual - so the question this asks is
## "where is it actually", not "which one do I shoot".
func _atk_chorus() -> void:
	var echoes := 2 + phase
	var lead := _telegraph_time() * 0.9
	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		Audio.play("ability", -4.0)
		var spots: Array[Vector2] = []
		for i in echoes:
			var a := TAU * i / echoes + _rng.randf()
			var at := global_position + Vector2.RIGHT.rotated(a) * _rng.randf_range(200.0, 340.0)
			if layout != null:
				at = layout.nearest_open(at)
			spots.append(at)
			var ghost := Sprite2D.new()
			ghost.texture = _body.texture
			ghost.modulate = Color(def["tint"].r, def["tint"].g, def["tint"].b, 0.55)
			ghost.scale = _visual.scale
			ghost.z_index = 10
			# parented first: global_position on a node outside the tree is
			# just position, and would land the echoes wherever the parent is
			get_parent().add_child(ghost)
			ghost.global_position = at + Vector2(0, BODY_LOCAL_Y * float(def["scale"]))
			var fade := ghost.create_tween()
			fade.tween_interval(0.55)
			fade.tween_property(ghost, "modulate:a", 0.0, 0.3)
			fade.tween_callback(ghost.queue_free)
		# every voice sings, including the real one
		for at: Vector2 in spots:
			var to_player := (Combat.player_position() - at).normalized()
			for k in 3:
				_fire_from(at, to_player.rotated(deg_to_rad(-14.0 + 14.0 * k)), 340.0, 10.0)
		for k in 3:
			var d := (Combat.player_position() - global_position).normalized()
			_fire(d.rotated(deg_to_rad(-14.0 + 14.0 * k)), 340.0, 10.0))
	t.tween_interval(0.45)
	t.tween_callback(_recover)


## OAK. Roots tear along spokes radiating from the trunk. The safe ground is
## the wedge *between* two spokes, so this is the one attack that rewards
## standing still in the right place rather than running.
func _atk_rootquake() -> void:
	var spokes := 5 + phase
	var steps := 6
	var step_len := 150.0
	var radius := 120.0
	var lead := _telegraph_time()
	var base := _rng.randf() * TAU
	var origin := global_position

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		Audio.play("boss_attack", -2.0)
		Game.shake(6.0, 0.5)
		for step in steps:
			var inner := create_tween()
			inner.tween_interval(0.10 * step)
			inner.tween_callback(func() -> void:
				var d := (float(step) + 1.0) * step_len
				for i in spokes:
					var at := origin + Vector2.RIGHT.rotated(base + TAU * i / spokes) * d
					FX.explosion(at, radius, def["tint"])
					Combat.explode_on_player(at, radius, 23.0 * _damage_scale)))
	t.tween_interval(0.10 * steps + 0.3)
	t.tween_callback(_recover)


## SOVEREIGN. Eats its own summons and heals off them. This is the only reason
## in the game to prioritise a boss's adds over the boss - leave them alive and
## the health bar goes backwards.
func _atk_devour() -> void:
	var lead := _telegraph_time()
	var radius := 520.0
	FX.telegraph(global_position, radius, lead, Color(0.75, 0.4, 0.95))

	var t := _wind_up(lead)
	t.tween_callback(func() -> void:
		var eaten := 0
		for e: Node2D in Combat.enemies_in_radius(global_position, radius):
			# never itself, and never another boss
			if e == self or e.is_in_group("boss"):
				continue
			var at := e.global_position
			FX.burst(at, def["tint"], 10, 1.0)
			var streak := create_tween()
			streak.tween_callback(func() -> void:
				FX.ring(at, 60.0, def["tint"], 0.3, 0.25))
			# die(false) suppresses the death FX but NOT the payout: run.gd
			# drops coins off the enemy_died signal and reads money_value,
			# which it would still see. Zero it first, or the Sovereign
			# healing off its own court would pay you for the privilege.
			e.set("money_value", 0)
			if e.has_method("die"):
				e.call("die", false)
			eaten += 1
		if eaten > 0:
			# Heals for what it ATE, not for a share of its own size.
			#
			# This was 4.5% of max_hp per add, which is a runaway: the boss
			# summons its own food, so the bigger the boss the more each meal
			# is worth. At the finale's 16,000 HP that was 720 a head and about
			# 4,300 a cast, and the headless sim spent four minutes taking the
			# Sovereign from 100% to 99%. A boss that out-heals you is not a
			# hard fight, it is an unwinnable one.
			#
			# A flat per-add value scaled the way enemy health is scales
			# sanely and cannot run away with the boss's own health pool.
			hp = minf(max_hp, hp + DEVOUR_HEAL_PER_ENEMY
				* Balance.hp_scale(wave) * eaten)
			Audio.play("boss_phase", -2.0)
			FX.floating_text(global_position + Vector2(0, -160),
				"DEVOURED %d" % eaten, Color(0.8, 0.5, 1.0))
			Game.shake(5.0, 0.3)
		else:
			FX.floating_text(global_position + Vector2(0, -160), "hungry",
				Color(0.7, 0.6, 0.8)))
	t.tween_interval(0.35)
	t.tween_callback(_recover)


func _fire(dir: Vector2, speed: float, damage: float) -> void:
	_fire_from(global_position, dir, speed, damage)


func _fire_from(origin: Vector2, dir: Vector2, speed: float, damage: float) -> void:
	var container := bullet_container if bullet_container != null else get_parent()
	var b := Pools.acquire(PROJECTILE, container) as Node2D
	b.call("launch", origin + dir * (hit_radius * 0.8), dir, {
		"damage": damage * _damage_scale,
		"speed": speed,
		"range": 1500.0,
		"from_player": false,
		"color": def["tint"],
		"scale": 1.5 if is_major else 1.25,
	})


# ---------------------------------------------------------------------------
# damage, phases, death
# ---------------------------------------------------------------------------
func take_damage(amount: float, is_crit: bool = false, _from: Vector2 = Vector2.ZERO,
		_knockback: float = 0.0, _source: String = Combat.SOURCE_OTHER) -> void:
	if dying or not active:
		return
	hp -= amount
	_flash = 1.0
	_material.set_shader_parameter("flash", 1.0)
	FX.damage_number(global_position + Vector2(0, -110), amount, is_crit)
	Audio.play_throttled("boss_hit", 0.05, -17.0, 0.16)
	Events.enemy_damaged.emit(self, amount, is_crit, global_position)

	var p := Combat.player()
	if p != null and p.has_method("on_damage_dealt"):
		p.call("on_damage_dealt", amount)

	_check_phase()
	if hp <= 0.0:
		_die()


## Where the boss is actually drawn, relative to its physics origin.
func hit_center() -> Vector2:
	return global_position + hit_offset


func health_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


## Phases are evenly spaced health thresholds. Crossing one interrupts the
## current attack, so a phase change is a visible reset rather than something
## the player has to infer from the health bar.
func _check_phase() -> void:
	var target := phase_count - int(floor(health_fraction() * phase_count))
	target = clampi(target, 1, phase_count)
	if target <= phase:
		return
	phase = target
	Audio.play("boss_phase", 0.0)
	Events.hit_stop.emit(Balance.HIT_STOP_BOSS_PHASE)
	Events.boss_phase_changed.emit(self, phase)
	Game.shake(9.0, 0.5)
	FX.ring(global_position, 420.0, Color(1.0, 0.85, 0.4), 0.7, 0.05)
	FX.burst(global_position, def["tint"], 30, 2.0)
	FX.floating_text(global_position + Vector2(0, -160),
		"PHASE %d" % phase, Color(1.0, 0.8, 0.35))
	# brief invulnerable pause so the transition is readable
	_busy = true
	_charging = false
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_callback(_recover)


func _die() -> void:
	if dying:
		return
	dying = true
	active = false
	set_physics_process(false)
	Combat.unregister_enemy(self)
	remove_from_group("enemies")

	Audio.play("boss_death", 2.0, 0.0)
	Game.shake(Balance.SHAKE_BOSS_SLAM, 1.0)

	# a run of small pops before the big one
	for i in 7:
		var t := create_tween()
		t.tween_interval(0.11 * i)
		t.tween_callback(func() -> void:
			if not is_instance_valid(self):
				return
			var at := global_position + Vector2.RIGHT.rotated(randf() * TAU) \
				* randf_range(30.0, float(def["radius"]) * 1.4)
			FX.explosion(at, 120.0, def["tint"])
			Game.shake(3.0, 0.15))

	var t := create_tween()
	t.tween_interval(0.85)
	t.tween_callback(func() -> void:
		FX.explosion(global_position, float(def["radius"]) * 3.4, def["tint"])
		FX.burst(global_position, Color(1, 1, 1), 44, 2.6))
	t.tween_property(_visual, "scale", Vector2.ZERO, 0.3).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		Events.boss_defeated.emit(self)
		defeated.emit(self)
		queue_free())
