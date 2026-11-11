extends CanvasLayer
## The cutscene an ultimate plays before it goes off.
##
## The world freezes on the frame the button was pressed, the camera pushes in
## on it, letterbox bars close, and the character steps in front of their own
## motif - roots for the Warden, a blood moon for the Vampire - with the
## ultimate's name. A white flash, the bars open, the world resumes and the
## ultimate lands on the frame it was called on.
##
## Two rules keep it from becoming an interruption in a game about pressure:
## it is short (DURATION), and any key skips straight to the flash. It can also
## be switched off in Settings ("ultimate_cinematics"), which falls back to the
## old under-a-second flourish.
##
## The freeze frame is a screenshot of the world rather than a live camera move:
## the tree is paused, and a paused Camera2D does not update its transform, so
## animating the real camera would do nothing until the cutscene was over.

signal finished

const DURATION := 2.35
const FLASH_AT := 1.95
const SKIP_AFTER := 0.2
const PIXEL := 4.0            ## motif shapes snap to this screen-pixel grid

var class_id := ""
var _def: Dictionary = {}
var _tint := Color.WHITE
var _t := 0.0
var _focus := Vector2.ZERO    ## the player's position on screen
var _done := false

var _frame: TextureRect = null
var _frame_mat: ShaderMaterial = null
var _motif: Control = null
var _portrait: TextureRect = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
var _class_label: Label = null
var _name_label: Label = null
var _desc_label: Label = null
var _flash: ColorRect = null


## Play the cutscene for `cls`, frozen on `snapshot`, pushing in on `focus`.
func setup(cls: String, snapshot: Texture2D, focus: Vector2) -> void:
	class_id = ClassesDB.sanitise(cls)
	_def = ClassesDB.get_def(class_id)
	_tint = _def["tint"]
	_focus = focus
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build(snapshot)
	_apply(0.0)


func _build(snapshot: Texture2D) -> void:
	var size := _screen()

	_frame = TextureRect.new()
	_frame.texture = snapshot
	_frame.size = size
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.pivot_offset = _focus
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = preload("res://assets/shaders/freeze_frame.gdshader")
	_frame_mat.set_shader_parameter("tint", _tint)
	_frame.material = _frame_mat
	add_child(_frame)

	_motif = Control.new()
	_motif.size = size
	_motif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motif.draw.connect(_draw_motif)
	add_child(_motif)

	_portrait = TextureRect.new()
	var path := ClassesDB.sprite_path(class_id, Save.skin_of(class_id))
	_portrait.texture = load(path) if ResourceLoader.exists(path) else null
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size = Vector2(84, 73) * 4.0
	add_child(_portrait)

	_bar_top = ColorRect.new()
	_bar_bottom = ColorRect.new()
	for bar: ColorRect in [_bar_top, _bar_bottom]:
		bar.color = Color(0.02, 0.03, 0.02)
		bar.size = Vector2(size.x, size.y * 0.13)
		add_child(bar)

	_class_label = UITheme.label(String(_def["name"]).to_upper(), 30, _tint, 5)
	_name_label = UITheme.label(String(_def["ultimate_name"]).to_upper(), 92,
		Color(1, 1, 1), 10)
	_desc_label = UITheme.label(String(_def["ultimate_text"]), 24,
		Color(0.92, 0.94, 0.9), 5)
	for l: Label in [_class_label, _name_label, _desc_label]:
		l.size = Vector2(size.x * 0.56, 0)
		add_child(l)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.size = size
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	if _done:
		return
	# Frame time with the hit-stop divided back out: Engine.time_scale may be
	# mid hit-stop when the button is pressed, and the cutscene must not play
	# at a quarter speed. Not the wall clock - Movie Maker renders slower than
	# real time, and a wall-clock cutscene would be over in a few frames of
	# the recorded preview.
	_t += delta / maxf(Engine.time_scale, 0.0001)
	if _t >= DURATION:
		_finish()
		return
	_apply(_t)


func _input(event: InputEvent) -> void:
	# Swallow everything while it plays - Esc must not open the pause menu
	# underneath a cutscene - and let any press skip to the flash.
	get_viewport().set_input_as_handled()
	if _done or _t < SKIP_AFTER:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed and _t < FLASH_AT:
		_t = FLASH_AT


func _apply(t: float) -> void:
	var size := _screen()
	var into := _ease_out(clampf(t / 0.28, 0.0, 1.0))
	var out := clampf((t - FLASH_AT) / (DURATION - FLASH_AT), 0.0, 1.0)

	# slow push-in on the player, faster over the last beat
	var push := 1.0 + 0.16 * _ease_in_out(clampf(t / FLASH_AT, 0.0, 1.0)) + 0.1 * out
	_frame.scale = Vector2(push, push)
	_frame_mat.set_shader_parameter("desaturate", 0.75 * into)
	_frame_mat.set_shader_parameter("tint_amount", 0.45 * into)
	_frame_mat.set_shader_parameter("vignette", 0.9 * into)
	_frame_mat.set_shader_parameter("darken", 0.35 * into)

	# letterbox
	var bar_h := size.y * 0.13 * (into * (1.0 - _ease_in_out(out)))
	_bar_top.position = Vector2(0, bar_h - size.y * 0.13)
	_bar_bottom.position = Vector2(0, size.y - bar_h)

	# the character steps in from the left and breathes
	var p_in := _ease_back(clampf((t - 0.15) / 0.45, 0.0, 1.0))
	var px := lerpf(-_portrait.size.x, size.x * 0.12, p_in)
	_portrait.position = Vector2(px, size.y * 0.5 - _portrait.size.y * 0.55
		+ sin(t * 5.0) * 6.0)
	_portrait.modulate.a = 1.0 - out

	# the name slams in from the right, with a little overshoot in scale
	var text_x := size.x * 0.40
	var c_in := _ease_out(clampf((t - 0.30) / 0.30, 0.0, 1.0))
	_class_label.position = Vector2(lerpf(size.x, text_x, c_in), size.y * 0.30)
	_class_label.modulate.a = c_in * (1.0 - out)
	var n_in := clampf((t - 0.42) / 0.26, 0.0, 1.0)
	_name_label.position = Vector2(lerpf(size.x * 1.1, text_x, _ease_out(n_in)),
		size.y * 0.36)
	var punch := 1.0 + 0.25 * (1.0 - _ease_out(clampf((t - 0.62) / 0.25, 0.0, 1.0))) \
		* float(n_in >= 1.0)
	_name_label.pivot_offset = Vector2(0, 50)
	_name_label.scale = Vector2(punch, punch)
	_name_label.modulate.a = n_in * (1.0 - out)
	var d_in := clampf((t - 0.75) / 0.35, 0.0, 1.0)
	_desc_label.position = Vector2(text_x, size.y * 0.52 + (1.0 - d_in) * 16.0)
	_desc_label.modulate.a = d_in * (1.0 - out)

	# the hit: white flash that holds a beat, then lets the world back in
	var f := 0.0
	if t >= FLASH_AT - 0.06:
		f = clampf((t - (FLASH_AT - 0.06)) / 0.06, 0.0, 1.0) * (1.0 - out)
	_flash.color.a = f
	_frame_mat.set_shader_parameter("flash", f * 0.5)
	_motif.modulate.a = 1.0 - out
	_frame.modulate.a = 1.0 - _ease_in_out(clampf((t - FLASH_AT - 0.1) / 0.3, 0.0, 1.0))
	_motif.queue_redraw()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	# freed by a scene change mid-cutscene: never leave the world paused
	if not _done:
		_done = true
		finished.emit()


# ---------------------------------------------------------------------------
# motifs - one per class, drawn behind the character
# ---------------------------------------------------------------------------
func _draw_motif() -> void:
	match String(_def.get("ultimate", "")):
		"recall_the_wood": _motif_roots()
		"last_stand": _motif_last_stand()
		"crimson_hour": _motif_blood_moon()
		"overclock": _motif_gears()
		"bloom": _motif_petals()


## WARDEN: roots claw in from every edge toward you.
func _motif_roots() -> void:
	var size := _screen()
	var grow := _ease_out(clampf((_t - 0.05) / 0.9, 0.0, 1.0))
	var bark := Color(0.36, 0.24, 0.14)
	var leaf := _tint.lightened(0.1)
	for i in 16:
		var rng := RandomNumberGenerator.new()
		rng.seed = 911 + i
		var side := i % 4
		var along := rng.randf_range(0.08, 0.92)
		var start: Vector2 = [Vector2(along * size.x, size.y + 10), Vector2(-10, along * size.y),
			Vector2(size.x + 10, along * size.y), Vector2(along * size.x, -10)][side]
		var target := _focus.lerp(start, rng.randf_range(0.25, 0.5))
		var pts := PackedVector2Array()
		var steps := 14
		for s in steps + 1:
			var k := float(s) / steps
			if k > grow:
				break
			var p := start.lerp(target, k)
			var normal := (target - start).orthogonal().normalized()
			p += normal * sin(k * 9.0 + i) * 26.0 * (1.0 - k)
			pts.append(_snap(p))
		if pts.size() < 2:
			continue
		for s in pts.size() - 1:
			var w := lerpf(36.0, 10.0, float(s) / steps)
			draw_line_on_motif(pts[s], pts[s + 1], bark, w)
			draw_line_on_motif(pts[s], pts[s + 1], bark.lightened(0.18), w * 0.35)
			if s % 3 == 2:
				_motif.draw_rect(Rect2(_snap(pts[s] + Vector2(8, -14)),
					Vector2(PIXEL * 4, PIXEL * 3)), leaf)
				_motif.draw_rect(Rect2(_snap(pts[s] + Vector2(-20, 4)),
					Vector2(PIXEL * 3, PIXEL * 2)), leaf.darkened(0.2))


## WARRIOR: the world rushes at you, and a cut splits the screen.
func _motif_last_stand() -> void:
	var size := _screen()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var col := _tint.lightened(0.35)
	for i in 64:
		var a := rng.randf() * TAU
		var speed := rng.randf_range(0.6, 1.4)
		var r0 := fmod(_t * 900.0 * speed + rng.randf() * 600.0, 900.0) + 120.0
		var r1 := r0 + rng.randf_range(60.0, 220.0)
		var c := col
		c.a = 0.55 * clampf(_t / 0.2, 0.0, 1.0)
		draw_line_on_motif(_snap(_focus + Vector2.RIGHT.rotated(a) * r0),
			_snap(_focus + Vector2.RIGHT.rotated(a) * r1), c, PIXEL)
	# the slash: a bright wedge that tears across once
	var k := clampf((_t - 0.55) / 0.22, 0.0, 1.0)
	if k > 0.0 and k < 1.0 or (_t > 0.77 and _t < 1.4):
		var fade := 1.0 - clampf((_t - 0.77) / 0.6, 0.0, 1.0)
		var from := Vector2(size.x * 0.05, size.y * 0.95)
		var to := from.lerp(Vector2(size.x * 0.95, size.y * 0.05), minf(k, 1.0))
		var n := (to - from).orthogonal().normalized() * 14.0
		var white := Color(1, 1, 1, 0.9 * fade)
		_motif.draw_colored_polygon(PackedVector2Array([
			_snap(from), _snap(to + n), _snap(to - n)]), white)


## VAMPIRE: a blood moon rises behind you and the sky bleeds.
func _motif_blood_moon() -> void:
	var size := _screen()
	var rise := _ease_out(clampf(_t / 0.8, 0.0, 1.0))
	var centre := Vector2(size.x * 0.25, size.y * (0.75 - 0.3 * rise))
	var r := 260.0 * rise
	_motif.draw_circle(centre, r + 40.0, Color(0.5, 0.02, 0.08, 0.35))
	_motif.draw_circle(centre, r, Color(0.62, 0.05, 0.12))
	_motif.draw_circle(centre + Vector2(-r * 0.25, -r * 0.2), r * 0.55,
		Color(0.75, 0.12, 0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 46:
		var x := rng.randf() * size.x
		var speed := rng.randf_range(500.0, 1100.0)
		var y := fmod(_t * speed + rng.randf() * size.y, size.y + 200.0) - 100.0
		var drop := Color(0.8, 0.06, 0.14, 0.85)
		_motif.draw_rect(Rect2(_snap(Vector2(x, y)), Vector2(PIXEL, PIXEL * 6)), drop)
		_motif.draw_rect(Rect2(_snap(Vector2(x - PIXEL * 0.5, y + PIXEL * 6)),
			Vector2(PIXEL * 2, PIXEL * 2)), drop)


## ENGINEER: the machinery wakes up and spins past redline.
func _motif_gears() -> void:
	var size := _screen()
	var spin := _t * (2.0 + _t * 4.0)
	var brass := Color(0.86, 0.66, 0.24)
	var dark := Color(0.45, 0.32, 0.12)
	var gears := [
		[Vector2(size.x * 0.24, size.y * 0.52), 230.0, 14, 1.0],
		[Vector2(size.x * 0.08, size.y * 0.22), 130.0, 10, -1.7],
		[Vector2(size.x * 0.42, size.y * 0.86), 150.0, 11, -1.5],
		[Vector2(size.x * 0.88, size.y * 0.78), 110.0, 9, 2.0],
	]
	var appear := _ease_out(clampf(_t / 0.5, 0.0, 1.0))
	for g: Array in gears:
		_gear(g[0], float(g[1]) * appear, int(g[2]), spin * float(g[3]), brass, dark)
	# circuit traces lighting up toward the centre
	var lit := clampf(_t / 1.2, 0.0, 1.0)
	for i in 8:
		var y := size.y * (0.15 + 0.1 * i)
		var x1 := size.x * lit
		_motif.draw_line(_snap(Vector2(size.x, y)), _snap(Vector2(size.x - x1 * 0.5, y)),
			Color(1.0, 0.85, 0.35, 0.5), PIXEL)


func _gear(c: Vector2, r: float, teeth: int, angle: float, col: Color, hole: Color) -> void:
	if r < 4.0:
		return
	var pts := PackedVector2Array()
	for i in teeth * 4:
		var a := angle + TAU * i / float(teeth * 4)
		var tooth := (i % 4) < 2
		pts.append(_snap(c + Vector2.RIGHT.rotated(a) * (r if tooth else r * 0.82)))
	_motif.draw_colored_polygon(pts, col)
	_motif.draw_circle(c, r * 0.55, col.darkened(0.15))
	_motif.draw_circle(c, r * 0.22, hole)


## HERBALIST: petals spiral out of you and the ground blooms.
func _motif_petals() -> void:
	var size := _screen()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 70:
		var a0 := rng.randf() * TAU
		var speed := rng.randf_range(260.0, 620.0)
		var r := fmod(_t * speed + rng.randf() * 500.0, size.x * 0.75)
		var a := a0 + r * 0.004
		var p := _focus + Vector2.RIGHT.rotated(a) * r
		var c: Color = [Color(0.98, 0.72, 0.82), Color(0.62, 0.9, 0.7),
			Color(1.0, 0.95, 0.75)][i % 3]
		var s := PIXEL * (2.0 + float(i % 3))
		_motif.draw_rect(Rect2(_snap(p), Vector2(s, s * 0.6)), c)
	var bloom := _ease_back(clampf((_t - 0.2) / 0.6, 0.0, 1.0))
	for j in 5:
		var centre := Vector2(size.x * (0.1 + 0.2 * j), size.y * (0.8 - 0.12 * (j % 2)))
		for k in 6:
			var off := Vector2.RIGHT.rotated(TAU * k / 6.0 + _t) * 34.0 * bloom
			_motif.draw_circle(centre + off, 22.0 * bloom, Color(0.95, 0.6, 0.78, 0.9))
		_motif.draw_circle(centre, 16.0 * bloom, Color(1.0, 0.9, 0.5))


func draw_line_on_motif(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	_motif.draw_line(a, b, col, width)


func _snap(p: Vector2) -> Vector2:
	return (p / PIXEL).round() * PIXEL


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _ease_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
