extends Control
## Boss-select screen, plus the extra game modes and language picker.
## All UI is built in code.

const ModeRules := preload("res://scripts/mode_rules.gd")
const PetAvatarScript := preload("res://scripts/pet_avatar.gd")
const UITheme := preload("res://scripts/ui_theme.gd")
const ReviewSchedulerScript := preload("res://scripts/review_scheduler.gd")
const UILayout := preload("res://scripts/ui_layout.gd")

var _margin: MarginContainer
var _boss_grid: GridContainer
var _modes_grid: GridContainer


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

	var title := UITheme.label(Game.t("menu.title"), 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := UITheme.label(Game.t("menu.subtitle"), 18, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	var xp := UITheme.label(Game.t("menu.xp_rank") % [Game.total_xp(), Game.player_rank()], 20, UITheme.GOOD)
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(xp)

	var next_rank := Game.next_rank_info()
	var xp_next_text: String
	if next_rank.is_empty():
		xp_next_text = Game.t("menu.xp_max")
	else:
		xp_next_text = Game.t("menu.xp_next") % [int(next_rank["remaining"]), Game.t(String(next_rank["key"]))]
	var xp_next := UITheme.label(xp_next_text, 14, UITheme.TEXT_DIM)
	xp_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(xp_next)

	root.add_child(_make_language_row())
	root.add_child(_make_extras_row())

	_boss_grid = GridContainer.new()
	_boss_grid.add_theme_constant_override("h_separation", 18)
	_boss_grid.add_theme_constant_override("v_separation", 18)
	_boss_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_boss_grid)

	for battle in Game.BATTLES:
		_boss_grid.add_child(_make_card(battle))

	var hint := UITheme.label(Game.t("menu.hint"), 14, UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	# --- extra game modes (Survival, Points Decay, Save the Pet)
	var modes_title := UITheme.label(Game.t("menu.modes_title"), 28, UITheme.ACCENT)
	modes_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(modes_title)

	var modes_hint := UITheme.label(Game.t("menu.modes_hint"), 14, UITheme.TEXT_DIM)
	modes_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(modes_hint)

	# Active question pool the game modes draw from (built-in or custom set).
	var active_set := Game.get_custom_set(Game.active_set_id())
	var pool_name: String = Game.t("custom.builtin") if active_set.is_empty() else String(active_set["name"])
	var pool_label := UITheme.label(Game.t("menu.active_set") % pool_name, 13, UITheme.GOOD if not active_set.is_empty() else UITheme.TEXT_DIM)
	pool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pool_label)

	_modes_grid = GridContainer.new()
	_modes_grid.add_theme_constant_override("h_separation", 18)
	_modes_grid.add_theme_constant_override("v_separation", 18)
	_modes_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_modes_grid)

	for mode in Game.MODES:
		_modes_grid.add_child(_make_mode_card(mode))

	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	var width := get_viewport_rect().size.x
	var display_scale := DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	var side_margin := 20 if width < 600.0 else (32 if width < 900.0 else 48)
	_margin.add_theme_constant_override("margin_left", side_margin)
	_margin.add_theme_constant_override("margin_right", side_margin)
	_margin.add_theme_constant_override("margin_top", 24 if width < 600.0 else 32)
	_margin.add_theme_constant_override("margin_bottom", 24 if width < 600.0 else 32)
	_boss_grid.columns = UILayout.responsive_columns(width, 280.0, 3, side_margin * 2.0, 18.0, display_scale)
	_modes_grid.columns = UILayout.responsive_columns(width, 280.0, 3, side_margin * 2.0, 18.0, display_scale)


func _make_language_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.label(Game.t("menu.language"), 14, UITheme.TEXT_DIM))

	var picker := OptionButton.new()
	picker.accessibility_name = Game.t("menu.language")
	picker.custom_minimum_size = Vector2(150, 44)
	var langs: Array = Game.available_languages()
	for i in range(langs.size()):
		picker.add_item(String(langs[i]["name"]), i)
		if String(langs[i]["code"]) == Game.lang:
			picker.select(i)
	var on_language_picked := func(idx: int) -> void:
		Game.set_language(String(langs[idx]["code"]))
		get_tree().reload_current_scene()
	picker.item_selected.connect(on_language_picked)
	row.add_child(picker)

	var minus := Button.new()
	minus.text = "A\u2212"
	minus.tooltip_text = Game.t("menu.text_smaller")
	minus.accessibility_name = Game.t("menu.text_smaller")
	minus.add_theme_font_size_override("font_size", UITheme.fs(15))
	UITheme.style_button(minus, UITheme.PANEL_LIGHT)
	var on_smaller := func() -> void:
		Game.adjust_text_scale(-Game.TEXT_SCALE_STEP)
		get_tree().reload_current_scene()
	minus.pressed.connect(on_smaller)
	row.add_child(minus)

	var reset := Button.new()
	reset.text = "A"
	reset.tooltip_text = Game.t("menu.text_default")
	reset.accessibility_name = Game.t("menu.text_default")
	reset.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(reset, UITheme.PANEL_LIGHT)
	var on_reset := func() -> void:
		Game.reset_text_scale()
		get_tree().reload_current_scene()
	reset.pressed.connect(on_reset)
	row.add_child(reset)

	var plus := Button.new()
	plus.text = "A+"
	plus.tooltip_text = Game.t("menu.text_larger")
	plus.accessibility_name = Game.t("menu.text_larger")
	plus.add_theme_font_size_override("font_size", UITheme.fs(18))
	UITheme.style_button(plus, UITheme.PANEL_LIGHT)
	var on_larger := func() -> void:
		Game.adjust_text_scale(Game.TEXT_SCALE_STEP)
		get_tree().reload_current_scene()
	plus.pressed.connect(on_larger)
	row.add_child(plus)

	var motion := CheckButton.new()
	motion.text = Game.t("menu.reduce_motion")
	motion.accessibility_name = Game.t("menu.reduce_motion")
	motion.button_pressed = Game.reduced_motion
	motion.toggled.connect(Game.set_reduced_motion)
	row.add_child(motion)
	return row


## Custom Quiz and Leaderboard entries, between the language picker and bosses.
func _make_extras_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var custom_btn := Button.new()
	custom_btn.text = Game.t("menu.custom")
	custom_btn.add_theme_font_size_override("font_size", UITheme.fs(15))
	UITheme.style_button(custom_btn, UITheme.PANEL_LIGHT)
	custom_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/custom_quiz.tscn"))
	row.add_child(custom_btn)

	var lb_btn := Button.new()
	lb_btn.text = Game.t("menu.leaderboard")
	lb_btn.add_theme_font_size_override("font_size", UITheme.fs(15))
	UITheme.style_button(lb_btn, UITheme.PANEL_LIGHT)
	lb_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/leaderboard.tscn"))
	row.add_child(lb_btn)

	var fc_btn := Button.new()
	# Due-card count on the button itself: it's the game's only daily hook,
	# and it used to live hidden one screen away inside the flashcards view.
	var scheduler = ReviewSchedulerScript.new()
	var all_cards: Array = scheduler.ensure_cards_for_questions(Game.review_cards(), Game.flashcards)
	var due_count: int = scheduler.due_cards(all_cards, Game.today_day()).size()
	fc_btn.text = Game.t("menu.flashcards_due") % due_count if due_count > 0 else Game.t("menu.flashcards")
	fc_btn.add_theme_font_size_override("font_size", UITheme.fs(15))
	UITheme.style_button(fc_btn, UITheme.PANEL_LIGHT)
	fc_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/flashcards.tscn"))
	row.add_child(fc_btn)
	return row


func _make_card(battle: Dictionary) -> PanelContainer:
	var color := Color(String(battle["color"]))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 200)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var name_label := UITheme.label(String(battle["boss"]), 22, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var sub := UITheme.label(Game.t(String(battle["subtitle_key"])), 14, UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)

	var count := Game.questions_for_battle(String(battle["id"])).size()
	box.add_child(UITheme.label(Game.t("menu.card_stats") % [count, int(battle["hearts"])], 14, UITheme.TEXT))

	var rec := Game.battle_record(String(battle["id"]))
	var in_progress: Dictionary = Game.battle_checkpoint(String(battle["id"]))
	var status := Game.t("menu.not_fought")
	var status_color := UITheme.TEXT_DIM
	if not in_progress.is_empty():
		status = Game.t("menu.in_progress") % [int(in_progress["answered"]), int(in_progress["queue"].size())]
		status_color = UITheme.ACCENT
	elif not rec.is_empty():
		if rec.get("defeated", false):
			status = Game.t("menu.defeated") % [int(round(float(rec.get("best_accuracy", 0.0)) * 100.0)), int(rec.get("best_streak", 0))]
			status_color = UITheme.GOOD
		else:
			status = Game.t("menu.attempts") % [int(rec.get("attempts", 0)), int(round(float(rec.get("best_accuracy", 0.0)) * 100.0))]
			status_color = UITheme.BAD
	box.add_child(UITheme.label(status, 13, status_color))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var fight := Button.new()
	fight.text = Game.t("menu.fight")
	fight.add_theme_font_size_override("font_size", UITheme.fs(18))
	UITheme.style_button(fight, color.darkened(0.4))
	fight.pressed.connect(_on_fight_pressed.bind(String(battle["id"])))
	box.add_child(fight)

	return card


func _make_mode_card(mode: Dictionary) -> PanelContainer:
	var id := String(mode["id"])
	var color := Color(String(mode["color"]))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 290 if id == "pet" else 190)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var name_label := UITheme.label(Game.t(String(mode["name_key"])), 22, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var desc := UITheme.label(Game.t(String(mode["desc_key"])), 14, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	var rec := Game.mode_record(id)
	var status := Game.t("menu.not_fought")
	var status_color := UITheme.TEXT_DIM
	if not rec.is_empty():
		status = Game.t("menu.mode_record") % [int(rec.get("best_score", 0)), int(rec.get("attempts", 0))]
		status_color = UITheme.GOOD
	box.add_child(UITheme.label(status, 13, status_color))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	if id == "pet":
		box.add_child(UITheme.label(Game.t("mode.pet.pick"), 13, UITheme.TEXT_DIM))
		var pets := HFlowContainer.new()
		pets.add_theme_constant_override("separation", 8)
		for p in ModeRules.PETS:
			var choice := VBoxContainer.new()
			choice.add_theme_constant_override("separation", 4)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var avatar = PetAvatarScript.new()
			avatar.set_reduced_motion(Game.reduced_motion)
			avatar.custom_minimum_size = Vector2(72, 64)
			avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			avatar.set_pet(String(p))
			choice.add_child(avatar)

			var pet_btn := Button.new()
			pet_btn.text = Game.t("pet.%s" % p)
			pet_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pet_btn.add_theme_font_size_override("font_size", UITheme.fs(14))
			UITheme.style_button(pet_btn, color.darkened(0.4))
			pet_btn.pressed.connect(_on_mode_pressed.bind(id, String(p)))
			choice.add_child(pet_btn)
			pets.add_child(choice)
		box.add_child(pets)
	else:
		var start := Button.new()
		start.text = Game.t("mode.start")
		start.add_theme_font_size_override("font_size", UITheme.fs(18))
		UITheme.style_button(start, color.darkened(0.4))
		start.pressed.connect(_on_mode_pressed.bind(id, Game.selected_pet))
		box.add_child(start)

	return card


func _on_fight_pressed(id: String) -> void:
	Game.selected_battle_id = id
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _on_mode_pressed(id: String, pet: String) -> void:
	Game.selected_mode = id
	Game.selected_pet = pet
	get_tree().change_scene_to_file("res://scenes/mode_battle.tscn")
