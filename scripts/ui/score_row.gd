extends RefCounted
## Shared "record this run's score" UI: a hint label plus a name field + save
## button that posts to the local leaderboard. Used by battle.gd (boss
## battles, mode "boss") and mode_battle.gd (Survival / Points Decay / Save
## the Pet) -- both screens were building the same name-prompt-and-save row
## independently on their own end-of-run overlay.

const UITheme := preload("res://scripts/ui_theme.gd")


## Builds the row and wires the save button. mode_key must be one of
## Leaderboard.MODES ("survival", "decay", "pet", "boss") -- it's forwarded
## as-is to Game.record_score() to file the entry under the right board.
static func build(mode_key: String, score: int) -> VBoxContainer:
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
		Game.record_score(name_edit.text, mode_key, score)
		save_btn.disabled = true
		name_edit.editable = false
		hint.text = Game.t("lb.saved")
		hint.add_theme_color_override("font_color", UITheme.GOOD)
	save_btn.pressed.connect(on_save)
	row.add_child(save_btn)
	return col
