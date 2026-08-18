extends Node
## Contextual onboarding.
##
## No tutorial level and no wall of text. Each hint fires the first time the
## thing it describes actually happens, shows for a few seconds, and is then
## recorded in the save so it never appears again - across runs, not just
## within one.
##
## Enemy hints are the important ones: the colour system only works if the
## player learns what each colour does, and the cheapest way to teach that is
## one line the first time a new colour walks on screen.

const FIRST_HINT_DELAY := 1.2

var _shown_this_run: Dictionary = {}
var _timer := 0.0
var _ability_prompt_at := 22.0


func _ready() -> void:
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.pickup_collected.connect(_on_pickup)
	Events.reload_started.connect(_on_reload)
	Events.shop_opened.connect(func() -> void: _hint("shop",
		"Spend your coins. You cannot buy everything - that is the point."))
	Events.boss_spawned.connect(func(_b: Node2D, name_text: String, major: bool) -> void:
		if major:
			_hint("major_boss", "%s. Watch the ground: every heavy attack is telegraphed."
				% name_text)
		else:
			_hint("mini_boss", "A mini-boss. Keep moving and read the wind-ups."))
	Events.wave_started.connect(_on_wave_started)
	Events.gun_upgraded.connect(func(_stat: String, _v: float) -> void:
		_hint("upgrade", "Your gun keeps the upgrade for the rest of this run."))

	_timer = -FIRST_HINT_DELAY


func _process(delta: float) -> void:
	_timer += delta
	if _timer > 0.0 and not _shown_this_run.has("move"):
		_hint("move", "WASD to move.  Mouse to aim.  Left click to shoot.")
	if _timer > _ability_prompt_at:
		_hint("ability", "SPACE and SHIFT use your two abilities. You only ever carry two.")


## Show a hint once ever. `id` is namespaced in the save so a later hint added
## to the game does not collide with an old one.
func _hint(id: String, text: String) -> void:
	if _shown_this_run.has(id):
		return
	_shown_this_run[id] = true
	if not bool(Save.settings.get("show_hints", true)):
		return
	var key := "hint_" + id
	if Save.has_seen_hint(key):
		return
	Save.mark_hint_seen(key)
	Events.tutorial_hint.emit(key, text)


func _on_wave_started(wave: int, _depth: int) -> void:
	if wave == 2:
		_hint("waves", "Waves get bigger and mix in new colours. Every fifth wave brings a boss.")


func _on_enemy_spawned(enemy: Node2D) -> void:
	if bool(enemy.get("is_elite")):
		var mod := String(enemy.get("elite_mod"))
		var info: Variant = EnemyTypes.ELITE_MOD_INFO.get(mod)
		if info != null:
			_hint("elite_" + mod, "Crowned enemies are elites. This one %s."
				% info["desc"])
		return
	var id := String(enemy.get("type_id"))
	if id.is_empty():
		return
	var def := EnemyTypes.get_def(id)
	_hint("enemy_" + id, String(def["hint"]))


func _on_pickup(kind: String, _at: Vector2) -> void:
	match kind:
		"coin":
			_hint("money", "Coins buy gun upgrades at the rest after each boss.")
		"potion_health":
			_hint("potion_health", "Red restores health.")
		"potion_speed":
			_hint("potion_speed", "Blue makes you faster for a while.")
		"potion_ability":
			_hint("potion_ability", "Purple refills an ability charge.")


func _on_reload(_duration: float) -> void:
	_hint("reload", "Out of ammo - you reload automatically, or press R early.")
