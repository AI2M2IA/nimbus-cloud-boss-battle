extends Control
## Boss battle: each question is a clash. Correct = damage the boss.
## Wrong = lose a heart and the question returns later in the queue.

const Rules := preload("res://scripts/battle_rules.gd")
const UITheme := preload("res://scripts/ui_theme.gd")
const QuizQuestionViewScript := preload("res://scripts/ui/quiz_question_view.gd")
const DialogView := preload("res://scripts/ui/dialog_view.gd")
const ScoreRowScript := preload("res://scripts/ui/score_row.gd")
const VICTORY_BONUS := 500

var battle: Dictionary
var queue: Array = []
var battle_pool_ids: Array = []
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
var dialog: Control = null
## Safe action for Esc while a dialog is open (STAY for the leave dialog,
## BACK TO MENU for the resume dialog) — Esc was inert while a dialog was
## up, which stranded keyboard-only players in the decision screen.
var dialog_cancel: Callable = func() -> void: pass
## Set by _end_battle so end-of-battle logic (record_result, overlay) runs
## exactly once -- the quiz view keeps answered == true under the overlay,
## so Enter/Space would otherwise re-emit continue_requested forever.
var _ended: bool = false
var _margin: MarginContainer


func _ready() -> void:
	Game.setup_scene_root(self)
	battle = Game.get_battle(Game.selected_battle_id)
	boss_color = Color(String(battle["color"]))
	max_hearts = int(battle["hearts"])
	hearts = max_hearts

	var checkpoint: Dictionary = Game.battle_checkpoint(String(battle["id"]))
	if checkpoint.is_empty():
		queue = Game.questions_for_battle(String(battle["id"]))
		for q in queue:
			battle_pool_ids.append(String(q.get("id", "")))
		total_unique = queue.size()
		if queue.is_empty():
			# Empty pool (e.g. questions.json failed to load): show an error
			# instead of falling into _next_question's free instant victory.
			_build_pool_error()
			return
		_build_ui()
		_update_hud()
		_next_question()
		return

	_restore_checkpoint(checkpoint)
	_build_ui()
	_update_hud()
	_show_resume_dialog(checkpoint)


# ---------------------------------------------------------------- UI building

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_margin.add_child(root)

	# --- header: boss on the left, player on the right
	var header := HFlowContainer.new()
	header.add_theme_constant_override("separation", 32)
	root.add_child(header)

	var boss_box := VBoxContainer.new()
	boss_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(boss_box)

	boss_name_label = UITheme.label(String(battle["boss"]), 26, boss_color)
	boss_box.add_child(boss_name_label)
	boss_box.add_child(UITheme.label(Game.t(String(battle["subtitle_key"])), 13, UITheme.TEXT_DIM))

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.show_percentage = false
	boss_hp_bar.custom_minimum_size = Vector2(0, 18)
	boss_hp_bar.max_value = total_unique
	boss_hp_bar.value = total_unique - correct_done
	boss_hp_bar.accessibility_name = Game.t("battle.boss_hp") % [total_unique, total_unique]
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
	quit.pressed.connect(_on_retreat_pressed)
	root.add_child(quit)

	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_margin):
		return
	var width := get_viewport_rect().size.x
	var side_margin := 16 if width < 600.0 else (32 if width < 900.0 else 48)
	_margin.add_theme_constant_override("margin_left", side_margin)
	_margin.add_theme_constant_override("margin_right", side_margin)
	_margin.add_theme_constant_override("margin_top", 16 if width < 600.0 else 24)
	_margin.add_theme_constant_override("margin_bottom", 16 if width < 600.0 else 24)


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
	_write_checkpoint()


func _on_continue_pressed() -> void:
	if _ended or dialog != null:
		return
	if hearts <= 0:
		_end_battle(false)
		return
	_next_question()


func _animate_boss_hit(damage_xp: int) -> void:
	if Game.reduced_motion:
		boss_hp_bar.value = float(total_unique - correct_done)
		return
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
	boss_hp_bar.accessibility_name = boss_hp_label.text
	# `current_q` is already present in queue immediately after a wrong answer,
	# so counting both briefly inflated the remaining-question indicator.
	progress_label.text = Game.t("battle.progress") % [questions_seen, remaining]
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


# ------------------------------------------------------- checkpoint + dialogs

## Restore a validated checkpoint (Game.battle_checkpoint) before _build_ui:
## queue order, hearts, streak and counters come back exactly as saved.
func _restore_checkpoint(checkpoint: Dictionary) -> void:
	var by_id := {}
	for q in Game.questions:
		by_id[String(q.get("id", ""))] = q
	queue = []
	for qid in checkpoint["queue"]:
		queue.append(by_id[qid])
	battle_pool_ids = checkpoint["pool"].duplicate()
	attempted = {}
	for qid in checkpoint["attempted"]:
		attempted[qid] = true
	first_try_correct = int(checkpoint["first_try_correct"])
	total_unique = int(checkpoint["total"])
	hearts = int(checkpoint["hearts"])
	correct_done = int(checkpoint["correct"])
	questions_seen = int(checkpoint["answered"])
	streak = int(checkpoint["streak"])
	best_streak = int(checkpoint.get("best_streak", streak))
	xp_earned = int(checkpoint["xp_earned"])


## Snapshot the run after every answered question and on "Leave & save".
## Called right after show_result(), so an answered current_q is already
## accounted for (cleared, or requeued on a miss); a current_q the player
## has not answered yet goes back at the front of the saved queue. Skipped
## once the queue is empty -- victory is one CONTINUE away then.
func _write_checkpoint() -> void:
	if _ended:
		return
	var ids: Array = []
	var answered := questions_seen
	if not current_q.is_empty() and not question_view.answered:
		ids.append(String(current_q.get("id", "")))
		# This question has only been displayed, not answered. It returns at
		# the front of the queue, so the restored _next_question() must advance
		# back to this same round instead of skipping one.
		answered = maxi(questions_seen - 1, 0)
	for q in queue:
		ids.append(String(q.get("id", "")))
	if ids.is_empty():
		return
	Game.save_battle_checkpoint(String(battle["id"]), Rules.make_checkpoint(
		ids, hearts, correct_done, answered, streak, best_streak, xp_earned,
		total_unique, attempted.keys(), first_try_correct, battle_pool_ids))


## Shown instead of the battle UI when the question pool came back empty
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
	panel.custom_minimum_size = Vector2(minf(520.0, maxf(get_viewport_rect().size.x - 32.0, 240.0)), 0)
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
	_show_leave_dialog()


## Offer the saved run: resume it, discard it for a fresh attempt, or bail
## back to the menu keeping the checkpoint for another day. Esc bails too.
func _show_resume_dialog(checkpoint: Dictionary) -> void:
	_show_dialog(
		Game.t("battle.resume_title"),
		Game.t("battle.resume_prompt") % [Rules.next_round(int(checkpoint["answered"])), int(checkpoint["queue"].size()), int(checkpoint["hearts"])],
		[
			{"text": Game.t("battle.resume"), "color": boss_color.darkened(0.4), "on_pressed": func() -> void:
				_close_dialog()
				_next_question()},
			{"text": Game.t("battle.start_over"), "color": UITheme.BAD.darkened(0.45), "on_pressed": func() -> void:
				Game.clear_battle_checkpoint(String(battle["id"]))
				get_tree().reload_current_scene()},
			{"text": Game.t("battle.back"), "color": UITheme.PANEL_LIGHT, "on_pressed": func() -> void:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")},
		],
		func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))


## Esc here means STAY — the destructive choice (leaving) is never the
## accidental default.
func _show_leave_dialog() -> void:
	_show_dialog(
		Game.t("battle.leave_title"),
		Game.t("battle.leave_prompt"),
		[
			{"text": Game.t("battle.leave_save"), "color": boss_color.darkened(0.4), "on_pressed": func() -> void:
				_write_checkpoint()
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")},
			{"text": Game.t("battle.stay"), "color": UITheme.PANEL_LIGHT, "on_pressed": _close_dialog},
		],
		_close_dialog)


func _show_dialog(title: String, body: String, actions: Array, cancel: Callable) -> void:
	if dialog != null:
		return
	dialog = DialogView.show(self, title, body, actions)
	dialog_cancel = cancel


func _close_dialog() -> void:
	if dialog != null:
		DialogView.close(dialog)
		dialog = null


# ---------------------------------------------------------------- end screens

func _end_battle(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	Game.clear_battle_checkpoint(String(battle["id"]))
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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 16, 28))
	panel.custom_minimum_size = Vector2(minf(520.0, maxf(get_viewport_rect().size.x - 32.0, 240.0)), 0)
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

	box.add_child(ScoreRowScript.build("boss", xp_earned))

	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var retry := Button.new()
	retry.text = Game.t("battle.retry")
	retry.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(retry, boss_color.darkened(0.4))
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(retry)

	var menu := Button.new()
	menu.text = Game.t("battle.back")
	menu.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(menu, UITheme.PANEL_LIGHT)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	buttons.add_child(menu)
