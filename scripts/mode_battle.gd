extends Control
## Run loop for the extra game modes: Survival, Points Decay, Save the Pet.
## Question/answer handling mirrors the boss battle, but the win/lose
## conditions are the pure functions in mode_rules.gd. The classic boss
## battle (battle.gd) is intentionally untouched by this scene.
## Unlike boss battles, wrong answers do not requeue here — each question
## is asked at most once per run.

const Rules := preload("res://scripts/battle_rules.gd")
const ModeRules := preload("res://scripts/mode_rules.gd")
const PetAvatarScript := preload("res://scripts/pet_avatar.gd")

var mode: Dictionary
var mode_id: String = "survival"
var pet: String = "cat"
var mode_color: Color

var queue: Array = []
var correct_count: int = 0
var wrong_count: int = 0
var answered_count: int = 0
var points: int = ModeRules.DECAY_START_POINTS
var streak: int = 0
var best_streak: int = 0
var xp_earned: int = 0

var current_q: Dictionary = {}
var selected_keys: Array = []
var answered: bool = false
var option_buttons: Dictionary = {}

var status_label: Label
var streak_label: Label
var xp_label: Label
var scroll: ScrollContainer
var badge_label: Label
var stem_text: RichTextLabel
var options_box: VBoxContainer
var confirm_btn: Button
var explain_panel: PanelContainer
var verdict_label: Label
var explain_text: RichTextLabel
var continue_btn: Button
var pet_avatar: PetAvatar


func _ready() -> void:
	mode_id = Game.selected_mode
	mode = Game.get_mode(mode_id)
	pet = Game.selected_pet if ModeRules.is_valid_pet(Game.selected_pet) else "cat"
	mode_color = Color(String(mode["color"]))
	queue = Game.mode_pool_shuffled()

	_build_ui()
	_update_hud()
	_next_question()


# ---------------------------------------------------------------- UI building

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# --- header: mode on the left, run status on the right
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 32)
	root.add_child(header)

	var mode_box := VBoxContainer.new()
	mode_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(mode_box)

	mode_box.add_child(UITheme.label(Game.t(String(mode["name_key"])), 26, mode_color))
	var desc := UITheme.label(Game.t(String(mode["desc_key"])), 13, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_box.add_child(desc)

	var status_box := VBoxContainer.new()
	status_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_child(status_box)

	status_box.add_child(UITheme.label(Game.t("battle.you"), 16, UITheme.TEXT))
	status_label = UITheme.label("", 16, mode_color)
	status_box.add_child(status_label)
	streak_label = UITheme.label("", 14, UITheme.GOOD)
	status_box.add_child(streak_label)
	xp_label = UITheme.label("", 14, UITheme.ACCENT)
	status_box.add_child(xp_label)

	if mode_id == "pet":
		var pet_stage := CenterContainer.new()
		pet_stage.custom_minimum_size = Vector2(0, 154)
		pet_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(pet_stage)

		pet_avatar = PetAvatarScript.new()
		pet_avatar.custom_minimum_size = Vector2(260, 150)
		pet_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pet_avatar.set_pet(pet)
		pet_stage.add_child(pet_avatar)

	# --- question card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 20))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(card)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 12)
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_box)

	badge_label = UITheme.label("", 13, mode_color)
	card_box.add_child(badge_label)

	stem_text = RichTextLabel.new()
	stem_text.fit_content = true
	stem_text.scroll_active = false
	stem_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stem_text.add_theme_font_size_override("normal_font_size", UITheme.fs(18))
	stem_text.add_theme_color_override("default_color", UITheme.TEXT)
	card_box.add_child(stem_text)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.add_child(options_box)

	confirm_btn = Button.new()
	confirm_btn.text = Game.t("battle.confirm")
	confirm_btn.visible = false
	confirm_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(confirm_btn, UITheme.ACCENT.darkened(0.3))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	card_box.add_child(confirm_btn)

	explain_panel = PanelContainer.new()
	explain_panel.visible = false
	explain_panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL_LIGHT, 10, 14))
	card_box.add_child(explain_panel)

	var ex_box := VBoxContainer.new()
	ex_box.add_theme_constant_override("separation", 8)
	explain_panel.add_child(ex_box)

	verdict_label = UITheme.label("", 20, UITheme.GOOD)
	ex_box.add_child(verdict_label)

	explain_text = RichTextLabel.new()
	explain_text.fit_content = true
	explain_text.scroll_active = false
	explain_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explain_text.add_theme_font_size_override("normal_font_size", UITheme.fs(15))
	explain_text.add_theme_color_override("default_color", UITheme.TEXT)
	ex_box.add_child(explain_text)

	continue_btn = Button.new()
	continue_btn.text = Game.t("battle.continue")
	continue_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(continue_btn, UITheme.GOOD.darkened(0.4))
	continue_btn.pressed.connect(_on_continue_pressed)
	ex_box.add_child(continue_btn)

	# --- quit link
	var quit := Button.new()
	quit.text = Game.t("battle.retreat")
	quit.flat = true
	quit.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	quit.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	root.add_child(quit)


# ---------------------------------------------------------------- run flow

func _next_question() -> void:
	if queue.is_empty():
		_end_run(true)
		return
	current_q = queue.pop_front()
	selected_keys = []
	answered = false
	option_buttons = {}

	var is_two: bool = String(current_q.get("type", "single")) == "select_two"
	badge_label.text = Game.t("battle.select_two") if is_two else Game.t("battle.pick_one")

	stem_text.text = String(current_q.get("stem", ""))

	for child in options_box.get_children():
		child.queue_free()

	for opt in current_q.get("options", []):
		var key := String(opt.get("key", ""))
		var btn := Button.new()
		btn.text = "%s)  %s" % [key, String(opt.get("text", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", UITheme.fs(16))
		btn.set("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(btn, UITheme.PANEL_LIGHT)
		if is_two:
			btn.toggle_mode = true
			btn.toggled.connect(_on_option_toggled.bind(key))
		else:
			btn.pressed.connect(_on_option_pressed.bind(key))
		options_box.add_child(btn)
		option_buttons[key] = btn

	confirm_btn.visible = is_two
	confirm_btn.disabled = true
	explain_panel.visible = false
	scroll.scroll_vertical = 0
	_update_hud()


func _on_option_pressed(key: String) -> void:
	if answered:
		return
	_evaluate([key])


func _on_option_toggled(pressed: bool, key: String) -> void:
	if answered:
		return
	if pressed:
		if not selected_keys.has(key):
			selected_keys.append(key)
	else:
		selected_keys.erase(key)
	confirm_btn.disabled = selected_keys.size() != 2
	if selected_keys.size() > 2:
		var oldest: String = selected_keys.pop_front()
		if option_buttons.has(oldest):
			option_buttons[oldest].set_pressed_no_signal(false)
		confirm_btn.disabled = selected_keys.size() != 2


func _on_confirm_pressed() -> void:
	if answered or selected_keys.size() != 2:
		return
	_evaluate(selected_keys.duplicate())


func _evaluate(chosen: Array) -> void:
	answered = true
	var answers: Array = current_q.get("answers", [])
	var correct: bool = Rules.is_correct(chosen, answers)
	answered_count += 1

	for key in option_buttons.keys():
		var btn: Button = option_buttons[key]
		btn.disabled = true
		if answers.has(key):
			UITheme.style_button(btn, UITheme.GOOD.darkened(0.25))
		elif chosen.has(key):
			UITheme.style_button(btn, UITheme.BAD.darkened(0.25))
	confirm_btn.visible = false

	if correct:
		correct_count += 1
		streak += 1
		best_streak = max(best_streak, streak)
		var gained := Rules.xp_for_streak(streak)
		xp_earned += gained
		verdict_label.text = Game.t("battle.hit") % [gained, Rules.multiplier(streak)]
		verdict_label.add_theme_color_override("font_color", UITheme.GOOD)
		_update_pet_reaction(true)
	else:
		wrong_count += 1
		streak = 0
		if mode_id == "decay":
			verdict_label.text = Game.t("run.wrong_points") % ModeRules.DECAY_WRONG_PENALTY
		elif mode_id == "pet":
			verdict_label.text = Game.t("run.wrong_strikes") % [wrong_count, ModeRules.PET_MAX_WRONG]
		else:
			verdict_label.text = Game.t("run.wrong_strikes") % [wrong_count, ModeRules.SURVIVAL_MAX_WRONG]
		verdict_label.add_theme_color_override("font_color", UITheme.BAD)
		_update_pet_reaction(false)

	if mode_id == "decay":
		points = ModeRules.decay_points(points, correct)

	explain_text.text = String(current_q.get("explanation", Game.t("battle.no_explanation")))
	explain_panel.visible = true
	_update_hud()
	_scroll_to_explanation()


func _scroll_to_explanation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## "saved" (win), "lost" (game over) or "ongoing" — pure logic in mode_rules.gd.
func _run_outcome() -> String:
	match mode_id:
		"decay":
			if ModeRules.decay_is_over(points):
				return "lost"
		"pet":
			return ModeRules.pet_outcome(correct_count, wrong_count)
		_:
			if ModeRules.survival_is_over(wrong_count):
				return "lost"
	return "ongoing"


func _on_continue_pressed() -> void:
	var outcome := _run_outcome()
	if outcome == "lost":
		_end_run(false)
		return
	if outcome == "saved" or queue.is_empty():
		_end_run(true)
		return
	_next_question()


func _update_hud() -> void:
	status_label.text = _status_text()
	streak_label.text = Game.t("battle.combo") % [streak, best_streak]
	xp_label.text = Game.t("battle.xp") % xp_earned
	if pet_avatar != null:
		pet_avatar.set_progress(correct_count, ModeRules.PET_GOAL_CORRECT, wrong_count, ModeRules.PET_MAX_WRONG)


func _update_pet_reaction(correct: bool) -> void:
	if pet_avatar == null:
		return
	if correct:
		pet_avatar.react_correct(correct_count, ModeRules.PET_GOAL_CORRECT)
	else:
		pet_avatar.react_wrong(wrong_count, ModeRules.PET_MAX_WRONG)


func _status_text() -> String:
	match mode_id:
		"decay":
			return Game.t("run.points") % points
		"pet":
			var rescue: String = Game.t("run.pet_progress") % [Game.t("pet.%s" % pet), correct_count, ModeRules.PET_GOAL_CORRECT]
			return rescue + "\n" + Game.t("run.mistakes_left") % (ModeRules.PET_MAX_WRONG - wrong_count)
		_:
			return Game.t("run.mistakes_left") % (ModeRules.SURVIVAL_MAX_WRONG - wrong_count)


# ---------------------------------------------------------------- end screen

func _end_run(victory: bool) -> void:
	Game.record_mode_result(mode_id, correct_count, xp_earned)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 16, 28))
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title_text: String
	if mode_id == "pet":
		title_text = Game.t("run.pet_saved_title") if victory else Game.t("run.pet_lost_title")
	else:
		title_text = Game.t("run.cleared_title") if victory else Game.t("run.over_title")
	var title := UITheme.label(title_text, 32, UITheme.GOOD if victory else UITheme.BAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var reason := _reason_text(victory)
	if reason != "":
		var sub := UITheme.label(reason, 15, UITheme.TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(sub)

	if mode_id == "pet":
		var final_avatar = PetAvatarScript.new()
		final_avatar.custom_minimum_size = Vector2(210, 152)
		final_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		final_avatar.set_pet(pet)
		final_avatar.set_progress(correct_count, ModeRules.PET_GOAL_CORRECT, wrong_count, ModeRules.PET_MAX_WRONG)
		final_avatar.set_final_state(victory)
		box.add_child(final_avatar)

	box.add_child(UITheme.label(Game.t("run.final_score") % [correct_count, answered_count], 16))
	box.add_child(UITheme.label(Game.t("battle.best_combo") % best_streak, 16))
	box.add_child(UITheme.label(Game.t("battle.xp_earned") % xp_earned, 16, UITheme.ACCENT))
	box.add_child(UITheme.label(Game.t("battle.total_xp") % [Game.total_xp(), Game.player_rank()], 14, UITheme.TEXT_DIM))

	box.add_child(_make_score_row(_leaderboard_score()))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var retry := Button.new()
	retry.text = Game.t("run.retry")
	retry.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(retry, mode_color.darkened(0.35))
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(retry)

	var menu := Button.new()
	menu.text = Game.t("battle.back")
	menu.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(menu, UITheme.PANEL_LIGHT)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	buttons.add_child(menu)


func _reason_text(victory: bool) -> String:
	match mode_id:
		"pet":
			var pet_name: String = Game.t("pet.%s" % pet)
			return Game.t("run.pet_saved") % pet_name if victory else Game.t("run.pet_lost") % pet_name
		"decay":
			return "" if victory else Game.t("run.decay_over")
		_:
			return "" if victory else Game.t("run.survival_over")


## What the leaderboard ranks per mode (see scripts/leaderboard.gd).
func _leaderboard_score() -> int:
	match mode_id:
		"decay":
			return points
		"pet":
			return best_streak
		_:
			return correct_count


## Name prompt + save button so the run can be recorded on the leaderboard.
func _make_score_row(score: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var hint := UITheme.label(Game.t("lb.record_score") % score, 14, UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = Game.t("lb.your_name")
	name_edit.text = Game.last_player_name()
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(180, 0)
	row.add_child(name_edit)

	var save_btn := Button.new()
	save_btn.text = Game.t("lb.save_score")
	save_btn.add_theme_font_size_override("font_size", UITheme.fs(14))
	UITheme.style_button(save_btn, UITheme.ACCENT.darkened(0.3))
	var on_save := func() -> void:
		Game.record_score(name_edit.text, mode_id, score)
		save_btn.disabled = true
		name_edit.editable = false
		hint.text = Game.t("lb.saved")
		hint.add_theme_color_override("font_color", UITheme.GOOD)
	save_btn.pressed.connect(on_save)
	row.add_child(save_btn)
	return col
