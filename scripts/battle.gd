extends Control
## Boss battle: each question is a clash. Correct = damage the boss.
## Wrong = lose a heart and the question returns later in the queue.

const Rules := preload("res://scripts/battle_rules.gd")
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
var selected_keys: Array = []
var answered: bool = false
var option_buttons: Dictionary = {}

var boss_color: Color
var boss_name_label: Label
var boss_hp_bar: ProgressBar
var boss_hp_label: Label
var hearts_box: HBoxContainer
var streak_label: Label
var xp_label: Label
var progress_label: Label
var scroll: ScrollContainer
var badge_label: Label
var stem_text: RichTextLabel
var options_box: VBoxContainer
var confirm_btn: Button
var explain_panel: PanelContainer
var verdict_label: Label
var explain_text: RichTextLabel
var continue_btn: Button
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

	badge_label = UITheme.label("", 13, boss_color)
	card_box.add_child(badge_label)

	stem_text = RichTextLabel.new()
	stem_text.fit_content = true
	stem_text.scroll_active = false
	stem_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stem_text.add_theme_font_size_override("normal_font_size", 18)
	stem_text.add_theme_color_override("default_color", UITheme.TEXT)
	card_box.add_child(stem_text)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.add_child(options_box)

	confirm_btn = Button.new()
	confirm_btn.text = Game.t("battle.confirm")
	confirm_btn.visible = false
	confirm_btn.add_theme_font_size_override("font_size", 16)
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
	explain_text.add_theme_font_size_override("normal_font_size", 15)
	explain_text.add_theme_color_override("default_color", UITheme.TEXT)
	ex_box.add_child(explain_text)

	continue_btn = Button.new()
	continue_btn.text = Game.t("battle.continue")
	continue_btn.add_theme_font_size_override("font_size", 16)
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


# ---------------------------------------------------------------- battle flow

func _next_question() -> void:
	if queue.is_empty():
		_end_battle(true)
		return
	current_q = queue.pop_front()
	selected_keys = []
	answered = false
	option_buttons = {}
	questions_seen += 1

	var is_two: bool = String(current_q.get("type", "single")) == "select_two"
	var seen_before: bool = attempted.has(String(current_q.get("id", "")))
	var badge := Game.t("battle.select_two") if is_two else Game.t("battle.pick_one")
	if seen_before:
		badge += "   |   " + Game.t("battle.rematch")
	badge_label.text = badge

	stem_text.text = String(current_q.get("stem", ""))

	for child in options_box.get_children():
		child.queue_free()

	for opt in current_q.get("options", []):
		var key := String(opt.get("key", ""))
		var btn := Button.new()
		btn.text = "%s)  %s" % [key, String(opt.get("text", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
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

	var qid := String(current_q.get("id", ""))
	var first_attempt: bool = not attempted.has(qid)
	attempted[qid] = true
	if first_attempt and correct:
		first_try_correct += 1

	for key in option_buttons.keys():
		var btn: Button = option_buttons[key]
		btn.disabled = true
		if answers.has(key):
			UITheme.style_button(btn, UITheme.GOOD.darkened(0.25))
		elif chosen.has(key):
			UITheme.style_button(btn, UITheme.BAD.darkened(0.25))
	confirm_btn.visible = false

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
			verdict_label.text = Game.t("battle.crit") % [gained, mult]
		else:
			verdict_label.text = Game.t("battle.hit") % [gained, mult]
		verdict_label.add_theme_color_override("font_color", UITheme.GOOD)
	else:
		hearts -= 1
		streak = 0
		var pos: int = Rules.requeue_position(queue.size())
		queue.insert(pos, current_q)
		verdict_label.text = Game.t("battle.miss")
		verdict_label.add_theme_color_override("font_color", UITheme.BAD)

	explain_text.text = String(current_q.get("explanation", Game.t("battle.no_explanation")))
	explain_panel.visible = true
	_update_hud()
	_scroll_to_explanation()


func _scroll_to_explanation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


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

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var retry := Button.new()
	retry.text = Game.t("battle.retry")
	retry.add_theme_font_size_override("font_size", 16)
	UITheme.style_button(retry, boss_color.darkened(0.35))
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(retry)

	var menu := Button.new()
	menu.text = Game.t("battle.back")
	menu.add_theme_font_size_override("font_size", 16)
	UITheme.style_button(menu, UITheme.PANEL_LIGHT)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	buttons.add_child(menu)
