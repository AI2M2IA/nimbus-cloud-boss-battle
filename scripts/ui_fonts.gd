class_name UIFonts
## Fallback font chain for the Web export, which ships without system fonts.
## Godot's default font covers Latin and Cyrillic only, so the CJK, Arabic,
## Hebrew, Indic, and Thai locales would render as tofu in the browser.
## The subsetted Noto fonts in res://assets/fonts/ (regular weight, subsetted
## to the characters used in data/i18n/<code>.json plus printable ASCII) are
## chained as fallbacks so a single Font can serve every locale. Callers can
## use the result as a theme default font.

const FALLBACK_PATHS: Array[String] = [
	"res://assets/fonts/noto-sans-sc-subset.ttf", # zh
	"res://assets/fonts/noto-sans-jp-subset.ttf", # ja
	"res://assets/fonts/noto-sans-kr-subset.ttf", # ko
	"res://assets/fonts/noto-sans-arabic-subset.ttf", # ar
	"res://assets/fonts/noto-sans-hebrew-subset.ttf", # he
	"res://assets/fonts/noto-sans-devanagari-subset.ttf", # hi
	"res://assets/fonts/noto-sans-bengali-subset.ttf", # bn
	"res://assets/fonts/noto-sans-thai-subset.ttf", # th
	"res://assets/fonts/noto-nastaliq-urdu-subset.ttf", # ur
]


static func build_fallback_font() -> Font:
	var root: FontFile = null
	for path in FALLBACK_PATHS:
		var ff := load(path) as FontFile
		if ff == null:
			push_warning("UIFonts: failed to load fallback font " + path)
			continue
		if root == null:
			root = ff
		else:
			root.fallbacks.append(ff)
	return root
