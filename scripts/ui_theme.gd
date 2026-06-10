class_name UITheme
## Shared UI helpers (styleboxes, colors) built in code — no art assets needed.

const BG := Color("#101627")
const PANEL := Color("#1b2238")
const PANEL_LIGHT := Color("#242d4a")
const TEXT := Color("#e8ecf8")
const TEXT_DIM := Color("#9aa4c4")
const GOOD := Color("#3ecf8e")
const BAD := Color("#ff5d5d")
const ACCENT := Color("#ff9900")


static func panel_box(color: Color = PANEL, radius: int = 12, margin: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func button_box(color: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func style_button(btn: Button, base: Color, text_color: Color = TEXT) -> void:
	btn.add_theme_stylebox_override("normal", button_box(base))
	btn.add_theme_stylebox_override("hover", button_box(base.lightened(0.12)))
	btn.add_theme_stylebox_override("pressed", button_box(base.darkened(0.15)))
	btn.add_theme_stylebox_override("focus", button_box(base.lightened(0.06)))
	btn.add_theme_stylebox_override("disabled", button_box(base.darkened(0.3)))
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	btn.add_theme_color_override("font_disabled_color", text_color.darkened(0.25))


static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
