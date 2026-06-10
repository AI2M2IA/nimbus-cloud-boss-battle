extends Node
## Autoload "Game" — question bank, battle definitions, save data.

const QUESTIONS_PATH := "res://data/questions.json"
const SAVE_PATH := "user://save.json"

const BATTLES := [
	{
		"id": "d0",
		"boss": "The Cloud Gatekeeper",
		"subtitle": "Cross-domain warm-up",
		"domain": 0,
		"color": "#9b8cff",
		"hearts": 3,
	},
	{
		"id": "d1",
		"boss": "The Breach Baron",
		"subtitle": "D1 - Design Secure Architectures",
		"domain": 1,
		"color": "#ff5d5d",
		"hearts": 5,
	},
	{
		"id": "d2",
		"boss": "The Chaos Monkey King",
		"subtitle": "D2 - Design Resilient Architectures",
		"domain": 2,
		"color": "#3ecf8e",
		"hearts": 5,
	},
	{
		"id": "d3",
		"boss": "The Latency Demon",
		"subtitle": "D3 - High-Performing Architectures",
		"domain": 3,
		"color": "#4f9cf9",
		"hearts": 5,
	},
	{
		"id": "d4",
		"boss": "Bill Shock, Budget Devourer",
		"subtitle": "D4 - Cost-Optimized Architectures",
		"domain": 4,
		"color": "#ff9900",
		"hearts": 5,
	},
	{
		"id": "gauntlet",
		"boss": "The Examiner",
		"subtitle": "Final Gauntlet - full exam set",
		"domain": -1,
		"color": "#e8c14d",
		"hearts": 8,
	},
]

## Extra game modes (the classic boss battle is not listed here; it is the
## default flow driven by BATTLES). Thresholds live in scripts/mode_rules.gd.
const MODES := [
	{
		"id": "survival",
		"name_key": "mode.survival.name",
		"desc_key": "mode.survival.desc",
		"color": "#ff5d5d",
	},
	{
		"id": "decay",
		"name_key": "mode.decay.name",
		"desc_key": "mode.decay.desc",
		"color": "#4f9cf9",
	},
	{
		"id": "pet",
		"name_key": "mode.pet.name",
		"desc_key": "mode.pet.desc",
		"color": "#3ecf8e",
	},
]

const LANGS := [
	{"code": "en", "name": "English"},
	{"code": "zh", "name": "中文"},
	{"code": "hi", "name": "हिन्दी"},
	{"code": "es", "name": "Español"},
	{"code": "fr", "name": "Français"},
	{"code": "ar", "name": "العربية"},
	{"code": "bn", "name": "বাংলা"},
	{"code": "pt", "name": "Português"},
	{"code": "ru", "name": "Русский"},
	{"code": "ur", "name": "اردو"},
	{"code": "id", "name": "Bahasa Indonesia"},
	{"code": "de", "name": "Deutsch"},
	{"code": "ja", "name": "日本語"},
	{"code": "sw", "name": "Kiswahili"},
	{"code": "tr", "name": "Türkçe"},
	{"code": "vi", "name": "Tiếng Việt"},
	{"code": "ko", "name": "한국어"},
	{"code": "th", "name": "ไทย"},
	{"code": "he", "name": "עברית"},
]

var questions: Array = []
var save_data: Dictionary = {"xp": 0, "battles": {}}
var selected_battle_id: String = "d0"
var selected_mode: String = "survival"
var selected_pet: String = "cat"
var lang: String = "en"
var _strings: Dictionary = {}
var _fallback: Dictionary = {}


func _ready() -> void:
	_load_questions()
	_load_save()
	_fallback = _load_lang_file("en")
	lang = String(save_data.get("lang", "en"))
	_strings = _fallback if lang == "en" else _load_lang_file(lang)


## Translate a UI string key in the current language (falls back to English).
func t(key: String) -> String:
	return String(_strings.get(key, _fallback.get(key, key)))


func set_language(code: String) -> void:
	lang = code
	_strings = _fallback if code == "en" else _load_lang_file(code)
	save_data["lang"] = code
	_write_save()


func _load_lang_file(code: String) -> Dictionary:
	var f := FileAccess.open("res://data/i18n/%s.json" % code, FileAccess.READ)
	if f == null:
		push_error("Missing translation file for '%s'" % code)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _load_questions() -> void:
	var f := FileAccess.open(QUESTIONS_PATH, FileAccess.READ)
	if f == null:
		push_error("Could not open %s" % QUESTIONS_PATH)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY and data.has("questions"):
		questions = data["questions"]
	else:
		push_error("Unexpected questions.json format")


func get_battle(id: String) -> Dictionary:
	for b in BATTLES:
		if b["id"] == id:
			return b
	return BATTLES[0]


func questions_for_battle(id: String) -> Array:
	var battle := get_battle(id)
	var pool: Array = []
	for q in questions:
		if id == "gauntlet":
			if q.get("source", "") == "exam":
				pool.append(q)
		elif int(q.get("domain", -99)) == int(battle["domain"]):
			pool.append(q)
	pool.shuffle()
	return pool


func get_mode(id: String) -> Dictionary:
	for m in MODES:
		if m["id"] == id:
			return m
	return MODES[0]


## Full shuffled question pool — extra game modes draw from every domain.
func all_questions_shuffled() -> Array:
	var pool := questions.duplicate()
	pool.shuffle()
	return pool


## Languages that actually have a translation file shipped with the game.
func available_languages() -> Array:
	var out: Array = []
	for l in LANGS:
		if FileAccess.file_exists("res://data/i18n/%s.json" % l["code"]):
			out.append(l)
	return out


func battle_record(id: String) -> Dictionary:
	var battles: Dictionary = save_data.get("battles", {})
	return battles.get(id, {})


func record_result(id: String, defeated: bool, accuracy: float, best_streak: int, xp_gain: int) -> void:
	save_data["xp"] = int(save_data.get("xp", 0)) + xp_gain
	var battles: Dictionary = save_data.get("battles", {})
	var rec: Dictionary = battles.get(id, {
		"defeated": false, "best_accuracy": 0.0, "best_streak": 0, "attempts": 0,
	})
	rec["defeated"] = rec.get("defeated", false) or defeated
	rec["best_accuracy"] = max(float(rec.get("best_accuracy", 0.0)), accuracy)
	rec["best_streak"] = max(int(rec.get("best_streak", 0)), best_streak)
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	battles[id] = rec
	save_data["battles"] = battles
	_write_save()


func mode_record(mode_id: String) -> Dictionary:
	var modes: Dictionary = save_data.get("modes", {})
	return modes.get(mode_id, {})


func record_mode_result(mode_id: String, score: int, xp_gain: int) -> void:
	save_data["xp"] = int(save_data.get("xp", 0)) + xp_gain
	var modes: Dictionary = save_data.get("modes", {})
	var rec: Dictionary = modes.get(mode_id, {"best_score": 0, "attempts": 0})
	rec["best_score"] = max(int(rec.get("best_score", 0)), score)
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	modes[mode_id] = rec
	save_data["modes"] = modes
	_write_save()


func total_xp() -> int:
	return int(save_data.get("xp", 0))


func player_rank() -> String:
	var xp := total_xp()
	if xp >= 40000:
		return "Solutions Architect Hero"
	if xp >= 20000:
		return "Cloud Champion"
	if xp >= 10000:
		return "Well-Architected Warrior"
	if xp >= 4000:
		return "Availability Zone Adventurer"
	if xp >= 1000:
		return "Region Rookie"
	return "Cloud Novice"


func _write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data))


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		save_data = data
