extends RefCounted
## Shared modal dialog (dim + centered card) used by battle.gd's
## resume/leave dialogs and mode_battle.gd's abandon dialog, which were
## building the same ~60-line layout independently. Actions stack vertically
## so a three-option dialog can't squeeze off the screen on narrow windows,
## and the first action grabs focus so the dialog is keyboard-usable.

const UITheme := preload("res://scripts/ui_theme.gd")


## actions: [{text: String, color: Color, on_pressed: Callable}].
## Returns the dialog root; the caller keeps it and closes it with close().
static func show(parent: Control, title: String, body: String, actions: Array) -> Control:
	var dialog := Control.new()
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dialog)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, 16, 28))
	var available_width := maxf(parent.get_viewport_rect().size.x - 32.0, 240.0)
	panel.custom_minimum_size = Vector2(minf(520.0, available_width), 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title_label := UITheme.label(title, 24, UITheme.ACCENT)
	title_label.accessibility_name = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	var body_label := UITheme.label(body, 15, UITheme.TEXT)
	body_label.accessibility_description = body
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body_label)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	var first: Button = null
	for action in actions:
		var btn := Button.new()
		btn.text = String(action["text"])
		btn.add_theme_font_size_override("font_size", UITheme.fs(16))
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(btn, action["color"])
		btn.pressed.connect(action["on_pressed"])
		buttons.add_child(btn)
		if first == null:
			first = btn
	if first != null:
		first.grab_focus()
	return dialog


static func close(dialog: Control) -> void:
	if dialog != null:
		dialog.queue_free()
