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
const UITheme := preload("res://scripts/ui_theme.gd")
const QuizQuestionViewScript := preload("res://scripts/ui/quiz_question_view.gd")
const DialogView := preload("res://scripts/ui/dialog_view.gd")

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
## Rescue goal for this run's pool (scales down for small custom sets).
var pet_goal_count: int = ModeRules.PET_GOAL_CORRECT
## True when the run draws from a player-authored set instead of the
## built-in bank; such runs award no XP and no leaderboard entry, so a
## 1-question custom set can't be farmed for progress.
var custom_pool: bool = false

var current_q: Dictionary = {}

var status_label: Label
var streak_label: Label
var xp_label: Label
var question_view  # QuizQuestionViewScript instance; untyped like pet_avatar
# below, so calling show_question()/show_result() doesn't depend on a
# class_name being registered in the global script class cache.
var pet_avatar  # PetAvatarScript instance; untyped like final_avatar below,
# so calling set_pet()/set_progress()/react_*() doesn't depend on the
# PetAvatar class_name being registered in the global script class cache.
var dialog: Control = null
## Safe action for Esc while the abandon dialog is open (STAY) — Esc was
## inert while a dialog was up, which stranded keyboard-only players.
var dialog_cancel: Callable = func() -> void: pass
## Set by _end_run so end-of-run logic (record_mode_result, overlay) runs
## exactly once -- the quiz view keeps answered == true under the overlay,
## so Enter/Space would otherwise re-emit continue_requested forever.
var _ended: bool = false


func _ready() -> void:
	Game.setup_scene_root(self)
	mode_id = Game.selected_mode
	mode = Game.get_mode(mode_id)
	pet = Game.selected_pet if ModeRules.is_valid_pet(Game.selected_pet) else "cat"
	mode_color = Color(String(mode["color"]))
	custom_pool = Game.active_set_id() != ""
	queue = Game.mode_pool_shuffled()
	pet_goal_count = ModeRules.pet_goal(queue.size())

	if queue.is_empty():
		# Empty pool (e.g. questions.json failed to load): show an error
		# instead of falling into _next_question's free instant victory.
		_build_pool_error()
		return
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
	question_view = QuizQuestionViewScript.new()
	question_view.configure(mode_color)
	root.add_child(question_view)
	question_view.answer_submitted.connect(_on_answer_submitted)
	question_view.continue_requested.connect(_on_continue_pressed)

	# --- quit link
	var quit := Button.new()
	quit.text = Game.t("battle.retreat")
	quit.flat = true
	quit.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	quit.pressed.connect(_on_retreat_pressed)
	root.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			if dialog != null:
				var cancel := dialog_cancel
				_close_dialog()
				cancel.call()
			else:
				_on_retreat_pressed()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- run flow

func _next_question() -> void:
	if queue.is_empty():
		_end_run(true)
		return
	current_q = queue.pop_front()
	question_view.show_question(current_q)
	_update_hud()


func _on_answer_submitted(chosen: Array) -> void:
	var answers: Array = current_q.get("answers", [])
	var correct: bool = Rules.is_correct(chosen, answers)
	answered_count += 1

	var verdict_text: String
	var verdict_color: Color
	if correct:
		correct_count += 1
		streak += 1
		best_streak = max(best_streak, streak)
		var gained := Rules.xp_for_streak(streak)
		xp_earned += gained
		verdict_text = Game.t("battle.hit") % [gained, Rules.multiplier(streak)]
		verdict_color = UITheme.GOOD
		_update_pet_reaction(true)
	else:
		wrong_count += 1
		streak = 0
		if mode_id == "decay":
			verdict_text = Game.t("run.wrong_points") % ModeRules.DECAY_WRONG_PENALTY
		elif mode_id == "pet":
			verdict_text = Game.t("run.wrong_strikes") % [wrong_count, ModeRules.PET_MAX_WRONG]
		else:
			verdict_text = Game.t("run.wrong_strikes") % [wrong_count, ModeRules.SURVIVAL_MAX_WRONG]
		verdict_color = UITheme.BAD
		_update_pet_reaction(false)

	if mode_id == "decay":
		points = ModeRules.decay_points(points, correct)

	var explanation := String(current_q.get("explanation", Game.t("battle.no_explanation")))
	question_view.show_result(chosen, answers, verdict_text, verdict_color, explanation)
	_update_hud()


## "saved" (win), "capped" (Decay question cap reached — win), "lost" (game
## over) or "ongoing" — pure logic in mode_rules.gd.
func _run_outcome() -> String:
	match mode_id:
		"decay":
			if ModeRules.decay_is_over(points):
				return "lost"
			if answered_count >= ModeRules.DECAY_QUESTION_CAP:
				return "capped"
		"pet":
			return ModeRules.pet_outcome(correct_count, wrong_count, pet_goal_count)
		_:
			if ModeRules.survival_is_over(wrong_count):
				return "lost"
	return "ongoing"


func _on_continue_pressed() -> void:
	if _ended or dialog != null:
		return
	var outcome := _run_outcome()
	if outcome == "lost":
		_end_run(false)
		return
	if outcome == "saved" or outcome == "capped" or queue.is_empty():
		_end_run(true)
		return
	_next_question()


func _update_hud() -> void:
	status_label.text = _status_text()
	streak_label.text = Game.t("battle.combo") % [streak, best_streak]
	xp_label.text = Game.t("battle.xp") % xp_earned
	if pet_avatar != null:
		pet_avatar.set_progress(correct_count, pet_goal_count, wrong_count, ModeRules.PET_MAX_WRONG)


func _update_pet_reaction(correct: bool) -> void:
	if pet_avatar == null:
		return
	if correct:
		pet_avatar.react_correct(correct_count, pet_goal_count)
	else:
		pet_avatar.react_wrong(wrong_count, ModeRules.PET_MAX_WRONG)


func _status_text() -> String:
	match mode_id:
		"decay":
			return Game.t("run.points") % points
		"pet":
			var rescue: String = Game.t("run.pet_progress") % [Game.t("pet.%s" % pet), correct_count, pet_goal_count]
			return rescue + "\n" + Game.t("run.mistakes_left") % (ModeRules.PET_MAX_WRONG - wrong_count)
		_:
			return Game.t("run.mistakes_left") % (ModeRules.SURVIVAL_MAX_WRONG - wrong_count)


# --------------------------------------------------- error + abandon dialog

## Shown instead of the run UI when the question pool came back empty
## (e.g. questions.json failed to load): no free victory, just a way back.
func _build_pool_error() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 16, 28))
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var msg := UITheme.label(Game.t("battle.no_questions"), 16, UITheme.BAD)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(msg)

	var back := Button.new()
	back.text = Game.t("battle.back")
	back.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(back, UITheme.PANEL_LIGHT)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	box.add_child(back)


func _on_retreat_pressed() -> void:
	if _ended:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_show_abandon_dialog()


## Modes have no checkpoint (boss battles only), so leaving mid-run needs a
## confirmation -- the run is gone for good. Esc means STAY: the destructive
## choice is never the accidental default.
func _show_abandon_dialog() -> void:
	if dialog != null:
		return
	dialog = DialogView.show(
		self,
		Game.t("mode.abandon_title"),
		Game.t("mode.abandon_prompt"),
		[
			{"text": Game.t("mode.abandon"), "color": UITheme.BAD.darkened(0.45), "on_pressed": func() -> void:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")},
			{"text": Game.t("battle.stay"), "color": UITheme.PANEL_LIGHT, "on_pressed": _close_dialog},
		])
	dialog_cancel = _close_dialog


func _close_dialog() -> void:
	if dialog != null:
		DialogView.close(dialog)
		dialog = null


# ---------------------------------------------------------------- end screen

func _end_run(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	# Custom-set runs are practice, not progression: no XP, no leaderboard,
	# so a tiny hand-made pool can't be farmed for ranks.
	Game.record_mode_result(mode_id, correct_count, 0 if custom_pool else xp_earned)

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
	if custom_pool:
		box.add_child(UITheme.label(Game.t("run.custom_pool_note"), 14, UITheme.TEXT_DIM))
	else:
		box.add_child(UITheme.label(Game.t("battle.xp_earned") % xp_earned, 16, UITheme.ACCENT))
	box.add_child(UITheme.label(Game.t("battle.total_xp") % [Game.total_xp(), Game.player_rank()], 14, UITheme.TEXT_DIM))

	if not custom_pool:
		box.add_child(_make_score_row(_leaderboard_score()))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var retry := Button.new()
	retry.text = Game.t("run.retry")
	retry.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(retry, mode_color.darkened(0.4))
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
			return Game.t("run.pet_saved") % pet_name if victory else Game.t("run.pet_lost") % [pet_name, pet_goal_count]
		"decay":
			if not victory:
				return Game.t("run.decay_over")
			return Game.t("run.decay_cap") % ModeRules.DECAY_QUESTION_CAP \
					if answered_count >= ModeRules.DECAY_QUESTION_CAP else ""
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
	UITheme.style_button(save_btn, UITheme.ACCENT.darkened(0.4))
	var on_save := func() -> void:
		Game.record_score(name_edit.text, mode_id, score)
		save_btn.disabled = true
		name_edit.editable = false
		hint.text = Game.t("lb.saved")
		hint.add_theme_color_override("font_color", UITheme.GOOD)
	save_btn.pressed.connect(on_save)
	row.add_child(save_btn)
	return col
