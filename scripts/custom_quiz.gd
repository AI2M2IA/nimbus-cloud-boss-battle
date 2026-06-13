extends Control
## Custom quiz screen: pick the active question pool, bulk-import a JSON set
## (file or paste — including the book site's exported questions.json), or
## add questions one by one. Validation is the pure scripts/quiz_import.gd;
## persistence lives in the Game autoload (user://custom_sets.json).
## All UI is built in code, matching main_menu.gd.

const QuizImport := preload("res://scripts/quiz_import.gd")

var pool_box: VBoxContainer
var import_name_edit: LineEdit
var import_text: TextEdit
var import_status: Label
var file_dialog: FileDialog

var add_name_edit: LineEdit
var stem_edit: TextEdit
var option_edits: Array = []
var answers_edit: LineEdit
var explanation_edit: TextEdit
var domain_spin: SpinBox
var add_status: Label


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

	var title := UITheme.label(Game.t("custom.title"), 42, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := UITheme.label(Game.t("custom.subtitle"), 16, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	root.add_child(_make_pool_panel())
	root.add_child(_make_import_panel())
	root.add_child(_make_add_panel())

	var back := Button.new()
	back.text = Game.t("battle.back")
	back.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(back, UITheme.PANEL_LIGHT)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	root.add_child(back_row)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	_refresh_pool_list()


# ------------------------------------------------------------- question pool

func _make_pool_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UITheme.label(Game.t("custom.active_pool"), 22, UITheme.ACCENT))

	pool_box = VBoxContainer.new()
	pool_box.add_theme_constant_override("separation", 6)
	box.add_child(pool_box)
	return panel


func _refresh_pool_list() -> void:
	for child in pool_box.get_children():
		child.queue_free()
	pool_box.add_child(_make_pool_row("", Game.t("custom.builtin"), Game.questions.size()))
	for s in Game.list_custom_sets():
		var qs: Array = s.get("questions", [])
		pool_box.add_child(_make_pool_row(String(s["id"]), String(s["name"]), qs.size()))


func _make_pool_row(set_id: String, set_name: String, count: int) -> HBoxContainer:
	var active: bool = Game.active_set_id() == set_id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := UITheme.label(set_name, 16, UITheme.GOOD if active else UITheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(UITheme.label(Game.t("custom.set_stats") % count, 14, UITheme.TEXT_DIM))

	var use_btn := Button.new()
	use_btn.text = Game.t("custom.in_use") if active else Game.t("custom.use")
	use_btn.disabled = active
	use_btn.add_theme_font_size_override("font_size", UITheme.fs(13))
	UITheme.style_button(use_btn, UITheme.GOOD.darkened(0.4) if active else UITheme.PANEL_LIGHT)
	var on_use := func() -> void:
		Game.set_active_set(set_id)
		_refresh_pool_list()
	use_btn.pressed.connect(on_use)
	row.add_child(use_btn)

	if set_id != "":
		var remove_btn := Button.new()
		remove_btn.text = Game.t("custom.remove")
		remove_btn.add_theme_font_size_override("font_size", UITheme.fs(13))
		UITheme.style_button(remove_btn, UITheme.BAD.darkened(0.45))
		var on_remove := func() -> void:
			Game.remove_custom_set(set_id)
			_refresh_pool_list()
		remove_btn.pressed.connect(on_remove)
		row.add_child(remove_btn)

	return row


# -------------------------------------------------------------- bulk import

func _make_import_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UITheme.label(Game.t("custom.import_title"), 22, UITheme.ACCENT))
	var hint := UITheme.label(Game.t("custom.import_hint"), 14, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)

	import_name_edit = LineEdit.new()
	import_name_edit.placeholder_text = Game.t("custom.set_name")
	import_name_edit.custom_minimum_size = Vector2(260, 0)
	name_row.add_child(import_name_edit)

	var load_btn := Button.new()
	load_btn.text = Game.t("custom.load_file")
	load_btn.add_theme_font_size_override("font_size", UITheme.fs(14))
	UITheme.style_button(load_btn, UITheme.PANEL_LIGHT)
	load_btn.pressed.connect(func() -> void: file_dialog.popup_centered_ratio(0.7))
	name_row.add_child(load_btn)

	import_text = TextEdit.new()
	import_text.placeholder_text = '{"questions": [ ... ]}'
	import_text.custom_minimum_size = Vector2(0, 160)
	import_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(import_text)

	var import_btn := Button.new()
	import_btn.text = Game.t("custom.import_btn")
	import_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(import_btn, UITheme.ACCENT.darkened(0.3))
	import_btn.pressed.connect(_on_import_pressed)
	box.add_child(import_btn)

	import_status = UITheme.label("", 14, UITheme.TEXT_DIM)
	import_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(import_status)
	return panel


func _on_file_selected(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_set_status(import_status, Game.t("custom.invalid_json"), false)
		return
	var raw := f.get_as_text()
	if raw.length() > QuizImport.MAX_IMPORT_BYTES:
		_set_status(import_status, Game.t("custom.invalid_json"), false)
		return
	import_text.text = raw
	if import_name_edit.text.strip_edges() == "":
		import_name_edit.text = path.get_file().get_basename()


func _on_import_pressed() -> void:
	var set_name := import_name_edit.text.strip_edges()
	if set_name == "":
		_set_status(import_status, Game.t("custom.name_required"), false)
		return
	if import_text.text.length() > QuizImport.MAX_IMPORT_BYTES:
		_set_status(import_status, Game.t("custom.invalid_json"), false)
		return
	var data = JSON.parse_string(import_text.text)
	if data == null:
		_set_status(import_status, Game.t("custom.invalid_json"), false)
		return
	var bank: Dictionary = QuizImport.normalize(data)
	var verdict: Dictionary = QuizImport.validate_bank(bank)
	if not verdict["ok"]:
		_set_status(import_status, "\n".join(verdict["errors"]), false)
		return
	Game.save_custom_set(set_name, bank["questions"])
	_set_status(import_status, Game.t("custom.import_ok") % [int(verdict["count"]), set_name], true)
	_refresh_pool_list()


# ---------------------------------------------------------- add one question

func _make_add_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 14, 18))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UITheme.label(Game.t("custom.add_title"), 22, UITheme.ACCENT))

	add_name_edit = LineEdit.new()
	add_name_edit.placeholder_text = Game.t("custom.set_name")
	add_name_edit.custom_minimum_size = Vector2(260, 0)
	box.add_child(add_name_edit)

	box.add_child(UITheme.label(Game.t("custom.stem"), 14, UITheme.TEXT_DIM))
	stem_edit = TextEdit.new()
	stem_edit.custom_minimum_size = Vector2(0, 80)
	stem_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(stem_edit)

	option_edits = []
	for key in QuizImport.OPTION_KEYS:
		var opt_edit := LineEdit.new()
		opt_edit.placeholder_text = Game.t("custom.option") % key
		box.add_child(opt_edit)
		option_edits.append(opt_edit)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	box.add_child(meta_row)

	answers_edit = LineEdit.new()
	answers_edit.placeholder_text = Game.t("custom.answers")
	answers_edit.custom_minimum_size = Vector2(260, 0)
	meta_row.add_child(answers_edit)

	meta_row.add_child(UITheme.label(Game.t("custom.domain"), 14, UITheme.TEXT_DIM))
	domain_spin = SpinBox.new()
	domain_spin.min_value = 0
	domain_spin.max_value = 4
	meta_row.add_child(domain_spin)

	box.add_child(UITheme.label(Game.t("custom.explanation"), 14, UITheme.TEXT_DIM))
	explanation_edit = TextEdit.new()
	explanation_edit.custom_minimum_size = Vector2(0, 60)
	explanation_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(explanation_edit)

	var add_btn := Button.new()
	add_btn.text = Game.t("custom.add_btn")
	add_btn.add_theme_font_size_override("font_size", UITheme.fs(16))
	UITheme.style_button(add_btn, UITheme.ACCENT.darkened(0.3))
	add_btn.pressed.connect(_on_add_pressed)
	box.add_child(add_btn)

	add_status = UITheme.label("", 14, UITheme.TEXT_DIM)
	add_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(add_status)
	return panel


func _on_add_pressed() -> void:
	var set_name := add_name_edit.text.strip_edges()
	if set_name == "":
		_set_status(add_status, Game.t("custom.name_required"), false)
		return
	var texts: Array = []
	for opt_edit in option_edits:
		texts.append((opt_edit as LineEdit).text)
	# Timestamp-based id so it never collides with bulk-imported ids.
	var question: Dictionary = QuizImport.build_question(
		"custom-%d" % int(Time.get_unix_time_from_system()),
		stem_edit.text,
		texts,
		Array(answers_edit.text.split(",", false)),
		explanation_edit.text,
		int(domain_spin.value),
	)
	var verdict: Dictionary = Game.append_to_custom_set(set_name, question)
	if not verdict["ok"]:
		_set_status(add_status, "\n".join(verdict["errors"]), false)
		return
	_set_status(add_status, Game.t("custom.added_ok") % [set_name, int(verdict["count"])], true)
	stem_edit.text = ""
	for opt_edit in option_edits:
		(opt_edit as LineEdit).text = ""
	answers_edit.text = ""
	explanation_edit.text = ""
	_refresh_pool_list()


func _set_status(label: Label, text: String, ok: bool) -> void:
	label.text = text
	label.add_theme_color_override("font_color", UITheme.GOOD if ok else UITheme.BAD)
