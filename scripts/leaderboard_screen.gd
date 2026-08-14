extends Control
## Local leaderboard screen: top runs per mode, read from the Game autoload.
## All UI is built in code, matching main_menu.gd.

const Leaderboard := preload("res://scripts/leaderboard.gd")
const UITheme := preload("res://scripts/ui_theme.gd")
const UILayout := preload("res://scripts/ui_layout.gd")

## Board colors follow the mode cards; "boss" uses the accent orange.
const BOARD_COLORS := {
	"survival": "#ff5d5d",
	"decay": "#4f9cf9",
	"pet": "#3ecf8e",
	"boss": "#ff9900",
}

var _margin: MarginContainer
var _grid: GridContainer


func _ready() -> void:
	Game.setup_scene_root(self)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.add_child(root)

	var title := UITheme.label(Game.t("lb.title"), 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := UITheme.label(Game.t("lb.subtitle"), 16, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_grid)

	for mode_key in Leaderboard.MODES:
		_grid.add_child(_make_board(String(mode_key)))

	var back := Button.new()
	back.text = Game.t("battle.back")
	back.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(back, UITheme.PANEL_LIGHT)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	root.add_child(back_row)

	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	var width := get_viewport_rect().size.x
	var side_margin := 20 if width < 600.0 else (32 if width < 900.0 else 48)
	for side in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(side, side_margin)
	_margin.add_theme_constant_override("margin_top", 24 if width < 600.0 else 32)
	_margin.add_theme_constant_override("margin_bottom", 24 if width < 600.0 else 32)
	_grid.columns = UILayout.responsive_columns(width, 360.0, 2, side_margin * 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			get_viewport().set_input_as_handled()


func _board_title(mode_key: String) -> String:
	if mode_key == "boss":
		return Game.t("lb.boss")
	return Game.t("mode.%s.name" % mode_key)


func _make_board(mode_key: String) -> PanelContainer:
	var color := Color(String(BOARD_COLORS.get(mode_key, "#ff9900")))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 220)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	box.add_child(UITheme.label(_board_title(mode_key), 22, color))

	var entries: Array = Game.leaderboard_top(mode_key)
	if entries.is_empty():
		var empty := UITheme.label(Game.t("lb.empty"), 14, UITheme.TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(empty)
		return card

	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank := UITheme.label("%2d." % (i + 1), 15, color if i == 0 else UITheme.TEXT_DIM)
		rank.custom_minimum_size = Vector2(34, 0)
		row.add_child(rank)
		var name_label := UITheme.label(String(e.get("name", "?")), 15, UITheme.TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UITheme.label(str(int(e.get("score", 0))), 15, color))
		# ISO date "YYYY-MM-DDTHH:MM:SS" — show the day only.
		row.add_child(UITheme.label(String(e.get("date", "")).substr(0, 10), 13, UITheme.TEXT_DIM))
		box.add_child(row)

	return card
