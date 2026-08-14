extends RefCounted
## Pure responsive-layout rules shared by the menu and leaderboard.


static func logical_viewport_width(fallback_width: float) -> float:
	# With canvas_items stretching, get_viewport_rect() can stay at the project's
	# 720 px base width on both phones and tablets. The browser's CSS width is the
	# reliable responsive breakpoint; keep the fallback for native/headless runs.
	if OS.has_feature("web"):
		var browser_window = JavaScriptBridge.get_interface("window")
		if browser_window != null:
			var browser_width: Variant = browser_window.innerWidth
			if (browser_width is float or browser_width is int) and float(browser_width) > 0.0:
				return float(browser_width)
	return fallback_width


static func responsive_columns(viewport_width: float, min_card_width: float, max_columns: int, outer_margin: float = 96.0, gap: float = 18.0, breakpoint_width: float = -1.0) -> int:
	# Card fitting uses canvas pixels because Control minimum sizes are expressed
	# there too. The separate CSS-width cap prevents a HiDPI phone from looking
	# like a tablet while still allowing two columns on an actual tablet.
	var logical_width := breakpoint_width if breakpoint_width > 0.0 else viewport_width
	var density_cap := 1 if logical_width < 600.0 else (2 if logical_width < 1100.0 else max_columns)
	var available := maxf(viewport_width - outer_margin, min_card_width)
	var fitted := int(floor((available + gap) / (min_card_width + gap)))
	return clampi(mini(fitted, density_cap), 1, max_columns)
