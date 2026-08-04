extends Control
## Boss battle: each question is a clash. Correct = damage the boss.
## Wrong = lose a heart and the question returns later in the queue.

const Rules := preload("res://scripts/battle_rules.gd")
const UITheme := preload("res://scripts/ui_theme.gd")
const QuizQuestionViewScript := preload("res://scripts/ui/quiz_question_view.gd")
const VICTORY_BONUS := 500

var battle: Dictionary
var queue: Array = []
var total_unique: int = 0
var correct_done: int = 0
var attempted: Dictionary = {}
var first_try_correct: int = 0

var hearts: int = 5
var max_hearts: int = 5
var streak: int = 0
var best_streak: int = 0
var xp_earned: int = 0
var questions_seen: int = 0

var current_q: Dictionary = {}

var boss_color: Color
var boss_name_label: Label
var boss_hp_bar: ProgressBar
var boss_hp_label: Label
var hearts_box: HBoxContainer
var streak_label: Label
var xp_label: Label
var progress_label: Label
var question_view  # QuizQuestionViewScript instance; untyped like pet_avatar
# in mode_battle.gd, so calling show_question()/show_result() doesn't depend
# on a class_name being registered in the global script class cache.
var overlay: Control


func _ready() -> void:
	battle = Game.get_battle(Game.selected_battle_id)
	boss_color = Color(String(battle["color"]))
	queue = Game.questions_for_battle(String(battle["id"]))
	total_unique = queue.size()
	max_hearts = int(battle["hearts"])
	hearts = max_hearts

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

	# --- header: boss on the left, player on the right
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 32)
	root.add_child(header)

	var boss_box := VBoxContainer.new()
	boss_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(boss_box)

	boss_name_label = UITheme.label(String(battle["boss"]), 26, boss_color)
	boss_box.add_child(boss_name_label)
	boss_box.add_child(UITheme.label(String(battle["subtitle"]), 13, UITheme.TEXT_DIM))

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.show_percentage = false
	boss_hp_bar.custom_minimum_size = Vector2(0, 18)
	boss_hp_bar.max_value = total_unique
	boss_hp_bar.value = total_unique
	boss_hp_bar.add_theme_stylebox_override("background", UITheme.panel_box(UITheme.PANEL_LIGHT, 6, 2))
	boss_hp_bar.add_theme_stylebox_override("fill", UITheme.panel_box(boss_color, 6, 2))
	boss_box.add_child(boss_hp_bar)

	boss_hp_label = UITheme.label("", 13, UITheme.TEXT_DIM)
	boss_box.add_child(boss_hp_label)

	var player_box := VBoxContainer.new()
	player_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_child(player_box)

	player_box.add_child(UITheme.label(Game.t("battle.you"), 16, UITheme.TEXT))
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 6)
	player_box.add_child(hearts_box)
	for i in range(max_hearts):
		var h := Panel.new()
		h.custom_minimum_size = Vector2(20, 20)
		hearts_box.add_child(h)

	streak_label = UITheme.label("", 14, UITheme.GOOD)
	player_box.add_child(streak_label)
	xp_label = UITheme.label("", 14, UITheme.ACCENT)
	player_box.add_child(xp_label)

	progress_label = UITheme.label("", 14, UITheme.TEXT_DIM)
	root.add_child(progress_label)

	# --- question card
	question_view = QuizQuestionViewScript.new()
	question_view.configure(boss_color)
	root.add_child(question_view)
	question_view.answer_submitted.connect(_on_answer_submitted)
	question_view.continue_requested.connect(_on_continue_pressed)

	# --- quit link
	var quit := Button.new()
	quit.text = Game.t("battle.retreat")
	quit.flat = true
	quit.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	quit.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	root.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- battle flow

func _next_question() -> void:
	if queue.is_empty():
		_end_battle(true)
		return
	current_q = queue.pop_front()
	questions_seen += 1

	var seen_before: bool = attempted.has(String(current_q.get("id", "")))
	var badge_suffix := Game.t("battle.rematch") if seen_before else ""
	question_view.show_question(current_q, badge_suffix)
	_update_hud()


func _on_answer_submitted(chosen: Array) -> void:
	var answers: Array = current_q.get("answers", [])
	var correct: bool = Rules.is_correct(chosen, answers)

	var qid := String(current_q.get("id", ""))
	var first_attempt: bool = not attempted.has(qid)
	attempted[qid] = true
	if first_attempt and correct:
		first_try_correct += 1

	var verdict_text: String
	var verdict_color: Color
	if correct:
		streak += 1
		best_streak = max(best_streak, streak)
		var mult := Rules.multiplier(streak)
		var gained := Rules.xp_for_streak(streak)
		xp_earned += gained
		correct_done += 1
		_animate_boss_hit(gained)
		if Rules.regen_heart(streak) and hearts < max_hearts:
			hearts += 1
			verdict_text = Game.t("battle.crit") % [gained, mult]
		else:
			verdict_text = Game.t("battle.hit") % [gained, mult]
		verdict_color = UITheme.GOOD
	else:
		hearts -= 1
		streak = 0
		var pos: int = Rules.requeue_position(queue.size())
		queue.insert(pos, current_q)
		verdict_text = Game.t("battle.miss")
		verdict_color = UITheme.BAD

	var explanation := String(current_q.get("explanation", Game.t("battle.no_explanation")))
	question_view.show_result(chosen, answers, verdict_text, verdict_color, explanation)
	_update_hud()


func _on_continue_pressed() -> void:
	if hearts <= 0:
		_end_battle(false)
		return
	_next_question()


func _animate_boss_hit(damage_xp: int) -> void:
	var tw := create_tween()
	tw.tween_property(boss_hp_bar, "value", float(total_unique - correct_done), 0.35)

	var pop := UITheme.label("-%d" % damage_xp, 24, UITheme.ACCENT)
	add_child(pop)
	pop.global_position = boss_hp_bar.global_position + Vector2(boss_hp_bar.size.x * 0.5, -10)
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(pop, "global_position:y", pop.global_position.y - 40.0, 0.7)
	tw2.tween_property(pop, "modulate:a", 0.0, 0.7)
	tw2.chain().tween_callback(pop.queue_free)

	var tw3 := create_tween()
	tw3.tween_property(boss_name_label, "modulate", Color(2, 2, 2), 0.08)
	tw3.tween_property(boss_name_label, "modulate", Color(1, 1, 1), 0.2)


func _update_hud() -> void:
	var remaining := total_unique - correct_done
	boss_hp_label.text = Game.t("battle.boss_hp") % [remaining, total_unique]
	progress_label.text = Game.t("battle.progress") % [questions_seen, queue.size() + (0 if current_q.is_empty() else 1)]
	streak_label.text = Game.t("battle.combo") % [streak, best_streak]
	xp_label.text = Game.t("battle.xp") % xp_earned
	var i := 0
	for h in hearts_box.get_children():
		var full: bool = i < hearts
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.BAD if full else UITheme.PANEL_LIGHT
		sb.set_corner_radius_all(5)
		h.add_theme_stylebox_override("panel", sb)
		i += 1


# ---------------------------------------------------------------- end screens

func _end_battle(victory: bool) -> void:
	var accuracy := 0.0
	if total_unique > 0:
		accuracy = float(first_try_correct) / float(total_unique)
	if victory:
		xp_earned += VICTORY_BONUS
	Game.record_result(String(battle["id"]), victory, accuracy, best_streak, xp_earned)

	overlay = Control.new()
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

	var title := UITheme.label(Game.t("battle.victory") if victory else Game.t("battle.defeat"), 32, UITheme.GOOD if victory else UITheme.BAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := UITheme.label(String(battle["boss"]), 18, boss_color)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(UITheme.label(Game.t("battle.accuracy") % [int(round(accuracy * 100.0)), first_try_correct, total_unique], 16))
	box.add_child(UITheme.label(Game.t("battle.best_combo") % best_streak, 16))
	var xp_line := Game.t("battle.xp_earned") % xp_earned
	if victory:
		xp_line += Game.t("battle.victory_bonus") % VICTORY_BONUS
	box.add_child(UITheme.label(xp_line, 16, UITheme.ACCENT))
	box.add_child(UITheme.label(Game.t("battle.total_xp") % [Game.total_xp(), Game.player_rank()], 14, UITheme.TEXT_DIM))

	if not victory:
		var tip := UITheme.label(Game.t("battle.tip"), 13, UITheme.TEXT_DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(tip)

	box.add_child(_make_score_row(xp_earned))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var retry := Button.new()
	retry.text = Game.t("battle.retry")
	retry.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(retry, boss_color.darkened(0.35))
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(retry)

	var menu := Button.new()
	menu.text = Game.t("battle.back")
	menu.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(menu, UITheme.PANEL_LIGHT)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	buttons.add_child(menu)


## Name prompt + save button — boss battles rank by XP earned ("boss" board).
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
		Game.record_score(name_edit.text, "boss", score)
		save_btn.disabled = true
		name_edit.editable = false
		hint.text = Game.t("lb.saved")
		hint.add_theme_color_override("font_color", UITheme.GOOD)
	save_btn.pressed.connect(on_save)
	row.add_child(save_btn)
	return col
