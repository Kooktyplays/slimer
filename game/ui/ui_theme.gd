class_name UITheme
extends RefCounted
## Shared UI construction helpers.
##
## The interface is built in code rather than laid out in .tscn files: almost
## every panel here is a list of rows generated from data (shop offers, meta
## unlocks, ability choices), so a scene file would be a handful of nodes plus
## a lot of duplication. These helpers keep the look consistent across all of
## them.

const BG := Color(0.09, 0.12, 0.10, 0.94)
const PANEL := Color(0.13, 0.17, 0.14, 0.96)
const PANEL_HI := Color(0.19, 0.25, 0.20, 0.98)
const BORDER := Color(0.36, 0.52, 0.34)
const TEXT := Color(0.92, 0.96, 0.90)
const TEXT_DIM := Color(0.62, 0.70, 0.62)
const GOLD := Color(1.0, 0.82, 0.32)
const RED := Color(0.92, 0.32, 0.34)
const GREEN := Color(0.48, 0.86, 0.42)
const BLUE := Color(0.42, 0.72, 1.0)
const PURPLE := Color(0.70, 0.48, 0.96)


static func label(text: String, size: int = 22, color: Color = TEXT,
		outline: int = 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = outline
	ls.outline_color = Color(0.03, 0.05, 0.03, 0.9)
	l.label_settings = ls
	l.modulate = color
	return l


static func title(text: String, size: int = 54, color: Color = TEXT) -> Label:
	var l := label(text, size, color, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func panel_style(bg: Color = PANEL, border: Color = BORDER,
		width: int = 3, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func panel(bg: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p


static func button(text: String, size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_stylebox_override("normal", panel_style(PANEL, BORDER, 2, 8))
	b.add_theme_stylebox_override("hover", panel_style(PANEL_HI, GOLD, 2, 8))
	b.add_theme_stylebox_override("pressed", panel_style(BORDER, GOLD, 2, 8))
	b.add_theme_stylebox_override("disabled", panel_style(
		Color(0.11, 0.13, 0.11, 0.9), Color(0.24, 0.28, 0.24), 2, 8))
	b.add_theme_stylebox_override("focus", panel_style(
		Color(0, 0, 0, 0), GOLD, 2, 8))
	b.custom_minimum_size = Vector2(0, 46)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wire_sounds(b)
	return b


static func wire_sounds(b: BaseButton) -> void:
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play_ui("ui_hover", -20.0))
	b.pressed.connect(func() -> void: Audio.play_ui("ui_click", -8.0))


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func icon(path: String, size: float, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	return t


## Full-screen dimmer, so menus never sit directly on top of gameplay.
static func dim(alpha: float = 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.06, 0.05, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func money_text(amount: int) -> String:
	return "%s" % amount
