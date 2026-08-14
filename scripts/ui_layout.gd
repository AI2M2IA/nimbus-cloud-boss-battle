extends RefCounted
## Pure responsive-layout rules shared by the menu and leaderboard.


static func responsive_columns(viewport_width: float, min_card_width: float, max_columns: int, outer_margin: float = 96.0, gap: float = 18.0, display_scale: float = 1.0) -> int:
	# Godot's Web viewport is measured in backing-store pixels. On HiDPI
	# phones that can make a narrow CSS viewport look tablet-sized unless the
	# platform scale is removed before choosing a layout cap. Card fitting still
	# uses backing pixels because Control minimum sizes are expressed there too.
	var logical_width := viewport_width / maxf(display_scale, 1.0)
	var density_cap := 1 if logical_width < 600.0 else (2 if logical_width < 1100.0 else max_columns)
	var available := maxf(viewport_width - outer_margin, min_card_width)
	var fitted := int(floor((available + gap) / (min_card_width + gap)))
	return clampi(mini(fitted, density_cap), 1, max_columns)
