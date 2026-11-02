extends PanelContainer
## Shared quiz-question card: the scrollable stem + options, single vs.
## select_two answering, the "more below" overflow hint, and the post-answer
## explanation panel. Used by both battle.gd (boss battles) and
## mode_battle.gd (Survival / Points Decay / Save the Pet) -- the two screens
## were building nearly identical UI and wiring the same option/confirm/
## continue interactions independently. Scoring, hearts, streak, requeue, XP
## and pet reactions are all game-mode-specific and stay in the caller; this
## view only renders a question and reports what the player did.
##
## Usage:
##   question_view = QuizQuestionViewScript.new()
##   question_view.configure(accent_color)   # builds the internal UI now
##   root.add_child(question_view)
##   question_view.answer_submitted.connect(_on_answer_submitted)
##   question_view.continue_requested.connect(_on_continue_pressed)
##   ...
##   question_view.show_question(current_q, optional_badge_suffix)
##   # caller scores the answer once answer_submitted fires, then:
##   question_view.show_result(chosen, answers, verdict_text, verdict_color, explanation)

const UITheme := preload("res://scripts/ui_theme.gd")

signal answer_submitted(chosen: Array)
signal continue_requested

const OVERFLOW_LAYOUT_MIN_FRAMES := 6
const OVERFLOW_LAYOUT_MAX_FRAMES := 12
const OVERFLOW_LAYOUT_STABLE_FRAMES := 2

var current_q: Dictionary = {}
var selected_keys: Array = []
var answered: bool = false
var option_buttons: Dictionary = {}
var option_order: Array = []
var _overflow_refresh_generation := 0

var scroll: ScrollContainer
var badge_label: Label
var stem_text: RichTextLabel
var overflow_hint: Label
var options_box: VBoxContainer
var confirm_btn: Button
var explain_panel: PanelContainer
var verdict_label: Label
var explain_text: RichTextLabel
var continue_btn: Button


## Builds the internal UI. Call once, right after .new(), before adding this
## to the tree -- building children on a not-yet-parented Control is fine in
## Godot and keeps construction explicit instead of depending on _ready()
## timing relative to when the caller sets configuration like accent_color.
func configure(accent_color: Color) -> void:
	add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 20))
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 12)
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_box)

	badge_label = UITheme.label("", 13, accent_color)
	badge_label.accessibility_name = Game.t("battle.pick_one")
	card_box.add_child(badge_label)

	stem_text = RichTextLabel.new()
	stem_text.fit_content = true
	stem_text.scroll_active = false
	stem_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stem_text.add_theme_font_size_override("normal_font_size", UITheme.fs(18))
	stem_text.add_theme_color_override("default_color", UITheme.TEXT)
	stem_text.accessibility_name = Game.t("custom.stem")
	card_box.add_child(stem_text)

	# Long, multi-part scenario questions can overflow the card on the
	# default 720p window; the scrollbar alone is easy to miss, so surface
	# an explicit cue near the top whenever there's more to scroll to.
	overflow_hint = UITheme.label("▼", 16, UITheme.ACCENT)
	overflow_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overflow_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overflow_hint.visible = false
	card_box.add_child(overflow_hint)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.add_child(options_box)

	confirm_btn = Button.new()
	confirm_btn.text = Game.t("battle.confirm")
	confirm_btn.visible = false
	confirm_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(confirm_btn, UITheme.ACCENT.darkened(0.4))
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
	explain_text.accessibility_name = Game.t("custom.explanation")
	ex_box.add_child(explain_text)

	continue_btn = Button.new()
	continue_btn.text = Game.t("battle.continue")
	continue_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(continue_btn, UITheme.GOOD.darkened(0.4))
	continue_btn.pressed.connect(_on_continue_pressed)
	ex_box.add_child(continue_btn)


## Displays a new question. badge_suffix (e.g. "Rematch") is appended after
## a " | " separator, matching battle.gd's existing rematch-badge format;
## leave it empty for modes that don't have that concept (mode_battle.gd).
func show_question(question: Dictionary, badge_suffix: String = "") -> void:
	current_q = question
	selected_keys = []
	answered = false
	option_buttons = {}
	option_order = []

	var is_two: bool = String(question.get("type", "single")) == "select_two"
	var badge := Game.t("battle.select_two") if is_two else Game.t("battle.pick_one")
	if badge_suffix != "":
		badge += "   |   " + badge_suffix
	badge_label.text = badge
	badge_label.accessibility_name = badge

	stem_text.text = String(question.get("stem", ""))

	for child in options_box.get_children():
		child.queue_free()

	for opt in question.get("options", []):
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
		option_order.append(key)

	confirm_btn.visible = is_two
	confirm_btn.disabled = true
	explain_panel.visible = false
	scroll.scroll_vertical = 0
	_refresh_overflow_hint()


## Shows/hides the "more below" cue once layout settles on the new content.
## Not awaited by normal callers -- it updates overflow_hint whenever it
## resolves. Godot recalculates RichTextLabel minimum sizes and container
## scroll ranges over several deferred layout passes, especially while the
## fallback-font chain is first shaped. A bounded stability check avoids
## reading a stale range after an arbitrary fixed number of frames. The
## generation guard prevents an older refresh from overwriting a newer one.
func _refresh_overflow_hint() -> void:
	if not is_instance_valid(scroll):
		return
	_overflow_refresh_generation += 1
	var generation := _overflow_refresh_generation
	var bar := scroll.get_v_scroll_bar()
	var initial_metrics := Vector2(bar.max_value, bar.page)
	var previous_metrics := initial_metrics
	var observed_change := false
	var stable_frames := 0

	for frame_index in range(OVERFLOW_LAYOUT_MAX_FRAMES):
		await get_tree().process_frame
		if generation != _overflow_refresh_generation or not is_instance_valid(scroll):
			return
		bar = scroll.get_v_scroll_bar()
		var metrics := Vector2(bar.max_value, bar.page)
		observed_change = observed_change or not metrics.is_equal_approx(initial_metrics)
		if metrics.is_equal_approx(previous_metrics):
			stable_frames += 1
		else:
			previous_metrics = metrics
			stable_frames = 0
		if frame_index + 1 >= OVERFLOW_LAYOUT_MIN_FRAMES \
				and observed_change and stable_frames >= OVERFLOW_LAYOUT_STABLE_FRAMES:
			break

	overflow_hint.visible = bar.max_value > bar.page


func _on_option_pressed(key: String) -> void:
	if answered:
		return
	answer_submitted.emit([key])


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
	answer_submitted.emit(selected_keys.duplicate())


## Called by the caller once it has scored the answer (is it correct? what
## does that mean for hearts/streak/points/pet?). Renders the shared part of
## the post-answer state: colors the option buttons, shows the verdict text
## and explanation, and scrolls down to reveal them.
func show_result(chosen: Array, answers: Array, verdict_text: String, verdict_color: Color, explanation: String) -> void:
	answered = true
	for key in option_buttons.keys():
		var btn: Button = option_buttons[key]
		btn.disabled = true
		if answers.has(key):
			UITheme.style_button(btn, UITheme.GOOD.darkened(0.25))
			# Shape marker, not just color, for color-blind players.
			btn.text = "✓  " + btn.text
		elif chosen.has(key):
			UITheme.style_button(btn, UITheme.BAD.darkened(0.25))
			btn.text = "✗  " + btn.text
	confirm_btn.visible = false

	verdict_label.text = verdict_text
	verdict_label.accessibility_name = verdict_text
	verdict_label.add_theme_color_override("font_color", verdict_color)
	var full_explanation := explanation
	var why_nots = current_q.get("whyNots", {})
	if typeof(why_nots) == TYPE_DICTIONARY:
		for key in chosen:
			if not answers.has(key) and why_nots.has(key):
				full_explanation += "\n\n" + Game.t("battle.why_not") % [String(key), String(why_nots[key])]
	explain_text.text = full_explanation
	explain_text.accessibility_description = full_explanation
	explain_panel.visible = true
	_scroll_to_explanation()


func _scroll_to_explanation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _on_continue_pressed() -> void:
	continue_requested.emit()


# ------------------------------------------------------------- keyboard input

## A-L pick a matching canonical option; 1-9 pick by displayed position.
## Enter/Space confirms (select_two) or continues
## (once answered). Routed through the real Button objects rather than
## calling the internal handlers directly, so toggle-mode visuals for
## select_two questions stay in sync with the logical selection -- calling
## _on_option_toggled() directly would update selected_keys without the
## button itself ever looking pressed.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var keycode: int = (event as InputEventKey).keycode

	if not answered:
		var option_key := _option_key_for_keycode(keycode)
		if option_key != "" and option_buttons.has(option_key):
			_activate_option(option_key)
			get_viewport().set_input_as_handled()
			return

	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER or keycode == KEY_SPACE:
		if answered:
			continue_requested.emit()
			get_viewport().set_input_as_handled()
		elif confirm_btn.visible and not confirm_btn.disabled:
			_on_confirm_pressed()
			get_viewport().set_input_as_handled()


func _option_key_for_keycode(keycode: int) -> String:
	match keycode:
		KEY_A:
			return "A"
		KEY_B:
			return "B"
		KEY_C:
			return "C"
		KEY_D:
			return "D"
		KEY_E:
			return "E"
		KEY_F:
			return "F"
		KEY_G:
			return "G"
		KEY_H:
			return "H"
		KEY_I:
			return "I"
		KEY_J:
			return "J"
		KEY_K:
			return "K"
		KEY_L:
			return "L"
	var index := -1
	match keycode:
		KEY_1: index = 0
		KEY_2: index = 1
		KEY_3: index = 2
		KEY_4: index = 3
		KEY_5: index = 4
		KEY_6: index = 5
		KEY_7: index = 6
		KEY_8: index = 7
		KEY_9: index = 8
	if index >= 0 and index < option_order.size():
		return String(option_order[index])
	return ""


func _activate_option(key: String) -> void:
	var btn: Button = option_buttons[key]
	if btn.disabled:
		return
	if btn.toggle_mode:
		btn.set_pressed(not btn.button_pressed)
	else:
		btn.pressed.emit()
