extends Control
## Boss-select screen, plus the extra game modes and language picker.
## All UI is built in code.

const ModeRules := preload("res://scripts/mode_rules.gd")
const PetAvatarScript := preload("res://scripts/pet_avatar.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var title := UITheme.label(Game.t("menu.title"), 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := UITheme.label(Game.t("menu.subtitle"), 18, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	var xp := UITheme.label(Game.t("menu.xp_rank") % [Game.total_xp(), Game.player_rank()], 20, UITheme.GOOD)
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(xp)

	root.add_child(_make_language_row())
	root.add_child(_make_extras_row())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	for battle in Game.BATTLES:
		grid.add_child(_make_card(battle))

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

	var modes_grid := GridContainer.new()
	modes_grid.columns = 3
	modes_grid.add_theme_constant_override("h_separation", 18)
	modes_grid.add_theme_constant_override("v_separation", 18)
	modes_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(modes_grid)

	for mode in Game.MODES:
		modes_grid.add_child(_make_mode_card(mode))


func _make_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.label(Game.t("menu.language"), 14, UITheme.TEXT_DIM))

	var picker := OptionButton.new()
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
	minus.add_theme_font_size_override("font_size", UITheme.fs(15))
	UITheme.style_button(minus, UITheme.PANEL_LIGHT)
	minus.pressed.connect(func() -> void:
		Game.adjust_text_scale(-Game.TEXT_SCALE_STEP)
		get_tree().reload_current_scene())
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "A+"
	plus.tooltip_text = Game.t("menu.text_larger")
	plus.add_theme_font_size_override("font_size", UITheme.fs(18))
	UITheme.style_button(plus, UITheme.PANEL_LIGHT)
	plus.pressed.connect(func() -> void:
		Game.adjust_text_scale(Game.TEXT_SCALE_STEP)
		get_tree().reload_current_scene())
	row.add_child(plus)
	return row


## Custom Quiz and Leaderboard entries, between the language picker and bosses.
func _make_extras_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
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
	fc_btn.text = Game.t("menu.flashcards")
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
	card.custom_minimum_size = Vector2(340, 200)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var name_label := UITheme.label(String(battle["boss"]), 22, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var sub := UITheme.label(String(battle["subtitle"]), 14, UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)

	var count := Game.questions_for_battle(String(battle["id"])).size()
	box.add_child(UITheme.label(Game.t("menu.card_stats") % [count, int(battle["hearts"])], 14, UITheme.TEXT))

	var rec := Game.battle_record(String(battle["id"]))
	var status := Game.t("menu.not_fought")
	var status_color := UITheme.TEXT_DIM
	if not rec.is_empty():
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
	UITheme.style_button(fight, color.darkened(0.35))
	fight.pressed.connect(_on_fight_pressed.bind(String(battle["id"])))
	box.add_child(fight)

	return card


func _make_mode_card(mode: Dictionary) -> PanelContainer:
	var id := String(mode["id"])
	var color := Color(String(mode["color"]))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(340, 290 if id == "pet" else 190)

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
		var pets := HBoxContainer.new()
		pets.add_theme_constant_override("separation", 8)
		for p in ModeRules.PETS:
			var choice := VBoxContainer.new()
			choice.add_theme_constant_override("separation", 4)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var avatar = PetAvatarScript.new()
			avatar.custom_minimum_size = Vector2(72, 64)
			avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			avatar.set_pet(String(p))
			choice.add_child(avatar)

			var pet_btn := Button.new()
			pet_btn.text = Game.t("pet.%s" % p)
			pet_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pet_btn.add_theme_font_size_override("font_size", UITheme.fs(14))
			UITheme.style_button(pet_btn, color.darkened(0.35))
			pet_btn.pressed.connect(_on_mode_pressed.bind(id, String(p)))
			choice.add_child(pet_btn)
			pets.add_child(choice)
		box.add_child(pets)
	else:
		var start := Button.new()
		start.text = Game.t("mode.start")
		start.add_theme_font_size_override("font_size", UITheme.fs(18))
		UITheme.style_button(start, color.darkened(0.35))
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
