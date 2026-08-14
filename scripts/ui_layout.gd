extends RefCounted
## Pure responsive-layout rules shared by the menu and leaderboard.


static func responsive_columns(viewport_width: float, min_card_width: float, max_columns: int, outer_margin: float = 96.0, gap: float = 18.0) -> int:
	var available := maxf(viewport_width - outer_margin, min_card_width)
	return clampi(int(floor((available + gap) / (min_card_width + gap))), 1, max_columns)
