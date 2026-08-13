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

## Smallest font size ever rendered, at any text scale. 11px effective text
## (13px label at the 0.85x scale) was below comfortable reading size.
const MIN_FONT_PX := 12

## WCAG AA minimum contrast ratio for normal text.
const MIN_CONTRAST := 4.5


static func fs(n: int) -> int:
	return maxi(int(round(float(n) * Game.text_scale)), MIN_FONT_PX)


## WCAG relative luminance of a color (0..1), per the contrast-ratio formula.
static func luminance(c: Color) -> float:
	var channels := [c.r, c.g, c.b]
	var linear: Array = []
	for v in channels:
		if v <= 0.03928:
			linear.append(v / 12.92)
		else:
			linear.append(pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


static func contrast_ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Text color that reads on `bg`: light TEXT on dark backgrounds, dark BG
## color on saturated/light ones. Picking by measured contrast instead of a
## hardcoded per-button color is what keeps white text off buttons like
## "Got it" (#3ecf8e), where it only reached ~1.8:1 (WCAG AA needs 4.5:1).
static func readable_text(bg: Color) -> Color:
	if contrast_ratio(bg, TEXT) >= contrast_ratio(bg, BG):
		return TEXT
	return BG


## Darken a button base just enough that both it and its hover variant meet
## MIN_CONTRAST against their auto-picked text color. Keeps vivid bases
## (green/gold stay vivid with dark text) and only darkens the few colors
## where neither text color would reach AA, so no caller can ship a
## low-contrast button by accident.
static func accessible_base(base: Color) -> Color:
	var c := base
	var steps := 0
	while steps < 16:
		var text := readable_text(c)
		var normal_ok := contrast_ratio(c, text) >= MIN_CONTRAST
		var hover_text := readable_text(c.lightened(0.12))
		var hover_ok := contrast_ratio(c.lightened(0.12), hover_text) >= MIN_CONTRAST
		if normal_ok and hover_ok:
			return c
		c = c.darkened(0.06)
		steps += 1
	return c


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


static func style_button(btn: Button, base: Color) -> void:
	var bg := accessible_base(base)
	var text_color := readable_text(bg)
	btn.add_theme_stylebox_override("normal", button_box(bg))
	btn.add_theme_stylebox_override("hover", button_box(bg.lightened(0.12)))
	btn.add_theme_stylebox_override("pressed", button_box(bg.darkened(0.15)))
	# Focus used to be a barely-visible lightened(0.06) fill; add an explicit
	# border so keyboard focus is obvious on every button (WCAG 2.4.7).
	var focus := button_box(bg.lightened(0.06))
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", button_box(bg.darkened(0.3)))
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	btn.add_theme_color_override("font_focus_color", text_color)
	btn.add_theme_color_override("font_disabled_color", text_color.darkened(0.25))


static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l
