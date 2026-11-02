extends Control
## Leitner flashcard review screen. Cards come from the book (data/flashcards.json);
## box state persists in the player save via the Game autoload.

const ReviewSchedulerScript := preload("res://scripts/review_scheduler.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

var _rs
var _cards: Array = []
var _by_id: Dictionary = {}
var _queue: Array = []
var _pos: int = 0
var _flipped: bool = false
var _animating: bool = false
var _revealed: bool = false

var _card_btn: Button
var _hint: Label
var _progress: Label
var _action_row: HBoxContainer
var _got_btn: Button
var _again_btn: Button
var _margin: MarginContainer


func _ready() -> void:
	Game.setup_scene_root(self)
	_rs = ReviewSchedulerScript.new()
	for fc in Game.flashcards:
		_by_id[String(fc.get("id", ""))] = fc
	_cards = _rs.ensure_cards_for_questions(Game.review_cards(), Game.flashcards)
	Game.save_review_cards(_cards)
	for c in _rs.due_cards(_cards, Game.today_day()):
		_queue.append(String(c.get("question_id", "")))
	_queue.shuffle()
	_build_ui()
	_show_current()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	_margin.add_child(col)

	col.add_child(UITheme.label(Game.t("flashcards.title"), 26, UITheme.ACCENT))

	_progress = UITheme.label("", 14, UITheme.TEXT_DIM)
	col.add_child(_progress)

	_card_btn = Button.new()
	_card_btn.custom_minimum_size = Vector2(0, 220)
	_card_btn.accessibility_description = Game.t("flashcards.flip_hint")
	_card_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_btn.clip_text = false
	_card_btn.add_theme_font_size_override("font_size", UITheme.fs(20))
	UITheme.style_button(_card_btn, UITheme.PANEL_LIGHT)
	_card_btn.pressed.connect(_on_card_pressed)
	col.add_child(_card_btn)

	_hint = UITheme.label(Game.t("flashcards.flip_hint"), 13, UITheme.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 12)
	col.add_child(_action_row)

	_again_btn = Button.new()
	_again_btn.text = Game.t("flashcards.again")
	_again_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(_again_btn, UITheme.BAD)
	_again_btn.pressed.connect(_on_grade.bind(false))
	_action_row.add_child(_again_btn)

	_got_btn = Button.new()
	_got_btn.text = Game.t("flashcards.got_it")
	_got_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(_got_btn, UITheme.GOOD)
	_got_btn.pressed.connect(_on_grade.bind(true))
	_action_row.add_child(_got_btn)

	var back := Button.new()
	back.text = Game.t("flashcards.back")
	back.add_theme_font_size_override("font_size", UITheme.fs(14))
	UITheme.style_button(back, UITheme.PANEL_LIGHT)
	back.pressed.connect(_on_back)
	col.add_child(back)

	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	var width := get_viewport_rect().size.x
	var side_margin := 20 if width < 600.0 else (64 if width < 900.0 else 220)
	for side in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(side, side_margin)
	_margin.add_theme_constant_override("margin_top", 32)
	_margin.add_theme_constant_override("margin_bottom", 32)


func _show_current(animate: bool = false) -> void:
	if _pos >= _queue.size():
		_card_btn.text = Game.t("flashcards.complete")
		_hint.text = ""
		_action_row.visible = false
		_progress.text = "%s: %d" % [Game.t("flashcards.cards"), _queue.size()]
		return
	var fc: Dictionary = _by_id.get(String(_queue[_pos]), {})
	_flipped = false
	_revealed = false
	_hint.text = Game.t("flashcards.flip_hint")
	_again_btn.disabled = true
	_got_btn.disabled = true
	_progress.text = "%s  %d / %d" % [Game.t("flashcards.cards"), _pos + 1, _queue.size()]
	var term := String(fc.get("term", String(_queue[_pos])))
	if animate:
		_flip_card(term)
	else:
		_card_btn.text = term


func _on_card_pressed() -> void:
	if _animating or _pos >= _queue.size():
		return
	var fc: Dictionary = _by_id.get(String(_queue[_pos]), {})
	_flipped = not _flipped
	if _flipped:
		_revealed = true
		_again_btn.disabled = false
		_got_btn.disabled = false
		_hint.text = Game.t("flashcards.grade_hint")
		_flip_card(String(fc.get("definition", "")))
	else:
		_hint.text = Game.t("flashcards.flip_hint")
		_flip_card(String(fc.get("term", String(_queue[_pos]))))


func _flip_card(new_text: String) -> void:
	if Game.reduced_motion:
		_card_btn.text = new_text
		_card_btn.scale = Vector2.ONE
		_animating = false
		return
	_animating = true
	_card_btn.pivot_offset = _card_btn.size * 0.5
	var tw := create_tween()
	tw.tween_property(_card_btn, "scale:x", 0.0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _card_btn.text = new_text)
	tw.tween_property(_card_btn, "scale:x", 1.0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _animating = false)


func _on_grade(success: bool) -> void:
	if _animating or not _revealed or _pos >= _queue.size():
		return
	var fc_id := String(_queue[_pos])
	for i in range(_cards.size()):
		if String(_cards[i].get("question_id", "")) == fc_id:
			_cards[i] = _rs.mark(_cards[i], success, Game.today_day())
			break
	Game.save_review_cards(_cards)
	_pos += 1
	_show_current(true)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_on_back()
			get_viewport().set_input_as_handled()
