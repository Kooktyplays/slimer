class_name PreviewClip
extends PanelContainer
## A looping, silent clip of an ability or ultimate, with its name underneath.
##
## The clips are the real game recorded by tools/record_previews.py, so what
## the menu shows is what the button does. Shared by the ability picker (loadout
## and shop) and the character screen.

const CLIP_SIZE := Vector2(400, 225)

var _title: Label = null
var _player: VideoStreamPlayer = null
var _missing: Label = null
var _caption: Label = null
var _path := ""


func _init() -> void:
	# The shop opens over a paused run; the clip must keep playing anyway.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.PANEL, UITheme.BORDER, 2, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	_title = UITheme.label("", 22, UITheme.GOLD, 4)
	col.add_child(_title)

	var frame := Control.new()
	frame.custom_minimum_size = CLIP_SIZE
	col.add_child(frame)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.loop = true
	_player.volume_db = -80.0
	_player.size = CLIP_SIZE
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_player)
	_missing = UITheme.label("no preview", 18, UITheme.TEXT_DIM, 3)
	_missing.size = CLIP_SIZE
	_missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(_missing)

	_caption = UITheme.label("", 16, UITheme.TEXT_DIM, 3)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(CLIP_SIZE.x, 0)
	col.add_child(_caption)


## Show `path` (a res:// .ogv) under `title`. Re-showing the clip already on
## screen does not restart it, so hovering back and forth does not stutter.
func show_clip(path: String, title: String, caption: String = "") -> void:
	_title.text = title
	_caption.text = caption
	_caption.visible = not caption.is_empty()
	if path == _path:
		return
	_path = path
	var stream: VideoStream = load(path) if ResourceLoader.exists(path) else null
	_missing.visible = stream == null
	_player.visible = stream != null
	_player.stop()
	_player.stream = stream
	if stream != null:
		_player.play()


func current_path() -> String:
	return _path


func is_playing() -> bool:
	return _player.is_playing()
