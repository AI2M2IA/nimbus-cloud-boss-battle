extends SceneTree
## Headless unit tests. Run from the project folder:
##   godot --headless --path . -s tests/run_tests.gd
## Exits 0 on success, 1 on failure.

const Rules := preload("res://scripts/battle_rules.gd")
const ModeRules := preload("res://scripts/mode_rules.gd")
const GameState := preload("res://scripts/game_state.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_rules()
	_test_modes()
	_test_question_bank()
	_test_game_state()
	_test_i18n()
	print("--------------------------------------------------")
	print("%d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("  PASS  %s" % name)
	else:
		failures += 1
		printerr("  FAIL  %s" % name)


# ------------------------------------------------------------- battle rules

func _test_rules() -> void:
	print("[battle_rules]")
	check(Rules.is_correct(["A"], ["A"]), "single correct")
	check(not Rules.is_correct(["B"], ["A"]), "single wrong")
	check(Rules.is_correct(["C", "A"], ["A", "C"]), "select_two order-independent")
	check(not Rules.is_correct(["A"], ["A", "C"]), "partial select_two is wrong")
	check(not Rules.is_correct(["A", "B", "C"], ["A", "B"]), "too many picks is wrong")
	check(not Rules.is_correct([], ["A"]), "empty pick is wrong")

	check(Rules.multiplier(1) == 1.0, "multiplier starts at 1.0")
	check(is_equal_approx(Rules.multiplier(3), 1.2), "multiplier grows 0.1/streak")
	check(is_equal_approx(Rules.multiplier(11), 2.0), "multiplier caps at 2.0")
	check(is_equal_approx(Rules.multiplier(50), 2.0), "multiplier stays capped")
	check(Rules.xp_for_streak(1) == 100, "base XP is 100")
	check(Rules.xp_for_streak(11) == 200, "capped XP is 200")

	check(not Rules.regen_heart(0), "no regen at streak 0")
	check(not Rules.regen_heart(3), "no regen at streak 3")
	check(Rules.regen_heart(4), "regen at streak 4")
	check(Rules.regen_heart(8), "regen at streak 8")

	check(Rules.requeue_position(20) == 4, "requeue 4 deep in long queue")
	check(Rules.requeue_position(2) == 2, "requeue clamps to queue size")
	check(Rules.requeue_position(0) == 0, "requeue into empty queue")


# --------------------------------------------------------------- mode rules

func _test_modes() -> void:
	print("[mode_rules]")
	# Survival: exactly 3 wrong answers end the run.
	check(not ModeRules.survival_is_over(0), "survival ongoing at 0 wrong")
	check(not ModeRules.survival_is_over(2), "survival ongoing at 2 wrong")
	check(ModeRules.survival_is_over(3), "survival over at exactly 3 wrong")
	check(ModeRules.survival_is_over(4), "survival stays over past 3")

	# Points Decay: 1000 start, -100 wrong, +50 correct, clamp at 0.
	check(ModeRules.DECAY_START_POINTS == 1000, "decay starts at 1000 points")
	check(ModeRules.decay_points(1000, false) == 900, "wrong answer costs 100")
	check(ModeRules.decay_points(1000, true) == 1050, "correct answer earns 50")
	check(ModeRules.decay_points(100, false) == 0, "decay reaches exactly 0")
	check(ModeRules.decay_points(50, false) == 0, "decay clamps at 0, never negative")
	check(not ModeRules.decay_is_over(1), "decay ongoing at 1 point")
	check(ModeRules.decay_is_over(0), "decay over at exactly 0")
	var p := ModeRules.DECAY_START_POINTS
	for i in range(10):
		p = ModeRules.decay_points(p, false)
	check(ModeRules.decay_is_over(p), "10 straight misses end a fresh run")

	# Save the Pet: saved at 20 correct, lost at 3 wrong.
	check(ModeRules.pet_outcome(0, 0) == "ongoing", "pet run starts ongoing")
	check(ModeRules.pet_outcome(19, 2) == "ongoing", "pet ongoing at 19 correct / 2 wrong")
	check(ModeRules.pet_outcome(20, 0) == "saved", "pet saved at exactly 20 correct")
	check(ModeRules.pet_outcome(25, 2) == "saved", "pet stays saved past 20")
	check(ModeRules.pet_outcome(0, 3) == "lost", "pet lost at exactly 3 wrong")
	check(ModeRules.pet_outcome(19, 3) == "lost", "pet lost at 3 wrong even with 19 correct")
	check(ModeRules.pet_outcome(20, 3) == "lost", "loss takes precedence over win")
	check(ModeRules.PETS.size() == 4, "4 pets available")
	check(ModeRules.is_valid_pet("cat") and ModeRules.is_valid_pet("fish"), "cat and fish are valid pets")
	check(not ModeRules.is_valid_pet("dragon"), "dragon is not a pet")

	# Mode wiring in game_state.
	var gs = GameState.new()
	check(gs.MODES.size() == 3, "3 modes defined")
	check(gs.get_mode("pet")["id"] == "pet", "get_mode finds pet")
	check(gs.get_mode("nope")["id"] == "survival", "unknown mode falls back to survival")

	# record_mode_result mutates and persists; snapshot and restore the save.
	gs._load_save()
	var backup: Dictionary = gs.save_data.duplicate(true)
	gs.save_data = {"xp": 0, "battles": {}}
	gs.record_mode_result("survival", 12, 800)
	gs.record_mode_result("survival", 9, 300)
	var rec: Dictionary = gs.mode_record("survival")
	check(gs.total_xp() == 1100, "mode XP accumulates")
	check(int(rec.get("best_score", 0)) == 12, "best mode score kept")
	check(int(rec.get("attempts", 0)) == 2, "mode attempts counted")
	gs.save_data = backup
	gs._write_save()
	gs.free()


# ------------------------------------------------------------ question bank

func _test_question_bank() -> void:
	print("[questions.json]")
	var f := FileAccess.open("res://data/questions.json", FileAccess.READ)
	check(f != null, "file opens")
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	check(typeof(data) == TYPE_DICTIONARY and data.has("questions"), "has questions key")
	var qs: Array = data.get("questions", [])
	check(qs.size() > 0, "bank is not empty (%d questions)" % qs.size())

	var bad_fields := 0
	var bad_answers := 0
	var bad_two := 0
	for q in qs:
		for field in ["id", "stem", "options", "answers", "type", "explanation", "domain"]:
			if not q.has(field):
				bad_fields += 1
		var keys := []
		for opt in q.get("options", []):
			keys.append(opt.get("key", ""))
		for a in q.get("answers", []):
			if not keys.has(a):
				bad_answers += 1
		if String(q.get("type", "")) == "select_two" and q.get("answers", []).size() != 2:
			bad_two += 1
	check(bad_fields == 0, "all questions have required fields")
	check(bad_answers == 0, "every answer key exists in options")
	check(bad_two == 0, "select_two questions have exactly 2 answers")


# -------------------------------------------------------------- game state

func _test_game_state() -> void:
	print("[game_state]")
	var gs = GameState.new()
	gs._load_questions()
	check(gs.questions.size() > 0, "questions loaded")
	check(gs.BATTLES.size() == 6, "6 battles defined")

	var ids := {}
	var total_pool := 0
	for b in gs.BATTLES:
		var id := String(b["id"])
		ids[id] = true
		var pool: Array = gs.questions_for_battle(id)
		total_pool += pool.size()
		check(pool.size() > 0, "battle '%s' has questions (%d)" % [id, pool.size()])
		if id == "gauntlet":
			var only_exam := true
			for q in pool:
				if String(q.get("source", "")) != "exam":
					only_exam = false
			check(only_exam, "gauntlet uses exam questions only")
		else:
			var dom := int(b["domain"])
			var only_dom := true
			for q in pool:
				if int(q.get("domain", -99)) != dom:
					only_dom = false
			check(only_dom, "battle '%s' pool matches domain %d" % [id, dom])
	check(ids.size() == 6, "battle ids are unique")
	check(gs.get_battle("nope")["id"] == "d0", "unknown battle falls back to d0")

	gs.save_data = {"xp": 0, "battles": {}}
	check(gs.player_rank() == "Cloud Novice", "rank at 0 XP")
	gs.save_data["xp"] = 4500
	check(gs.player_rank() == "Availability Zone Adventurer", "rank at 4500 XP")
	gs.save_data["xp"] = 999999
	check(gs.player_rank() == "Solutions Architect Hero", "top rank")

	# record_result mutates and persists; snapshot the real save and restore it.
	gs._load_save()
	var backup: Dictionary = gs.save_data.duplicate(true)

	gs.save_data = {"xp": 0, "battles": {}}
	gs.record_result("d1", false, 0.5, 3, 700)
	gs.record_result("d1", true, 0.8, 6, 1200)
	var rec: Dictionary = gs.battle_record("d1")
	check(gs.total_xp() == 1900, "XP accumulates")
	check(rec.get("defeated", false) == true, "defeat flag sticks")
	check(is_equal_approx(float(rec.get("best_accuracy", 0.0)), 0.8), "best accuracy kept")
	check(int(rec.get("best_streak", 0)) == 6, "best streak kept")
	check(int(rec.get("attempts", 0)) == 2, "attempts counted")

	gs.save_data = backup
	gs._write_save()
	gs.free()


# -------------------------------------------------------------------- i18n

func _test_i18n() -> void:
	print("[i18n]")
	var gs = GameState.new()
	var en: Dictionary = gs._load_lang_file("en")
	var pt: Dictionary = gs._load_lang_file("pt-BR")
	check(en.size() > 0, "en.json loads (%d keys)" % en.size())
	check(pt.size() > 0, "pt-BR.json loads (%d keys)" % pt.size())

	var missing := 0
	for key in en.keys():
		if not pt.has(key):
			missing += 1
	check(missing == 0, "pt-BR covers every en key (%d missing)" % missing)

	var extra := 0
	for key in pt.keys():
		if not en.has(key):
			extra += 1
	check(extra == 0, "pt-BR has no unknown keys (%d extra)" % extra)

	var non_string := 0
	for d in [en, pt]:
		for key in d.keys():
			if typeof(d[key]) != TYPE_STRING:
				non_string += 1
	check(non_string == 0, "all i18n values are strings")

	# Format placeholders (%d, %s, %.1f, ...) must match across languages,
	# in the same order, or runtime formatting would break after switching.
	var re := RegEx.new()
	re.compile("%(\\.\\d+)?[dsf]")
	var spec_mismatch := 0
	for key in en.keys():
		if not pt.has(key):
			continue
		var en_specs := []
		for m in re.search_all(String(en[key])):
			en_specs.append(m.get_string())
		var pt_specs := []
		for m in re.search_all(String(pt[key])):
			pt_specs.append(m.get_string())
		if en_specs != pt_specs:
			spec_mismatch += 1
	check(spec_mismatch == 0, "format placeholders match across languages (%d mismatched)" % spec_mismatch)

	# t() resolution: current language first, English fallback, then the key.
	gs._fallback = en
	gs._strings = pt
	check(gs.t("menu.fight") == "LUTAR", "t() uses the current language")
	gs._strings = {}
	check(gs.t("menu.fight") == "FIGHT", "t() falls back to English")
	check(gs.t("nonexistent.key") == "nonexistent.key", "t() returns the key when unknown")

	# Every mode metadata key must exist in en.json.
	var missing_mode_keys := 0
	for m in gs.MODES:
		if not en.has(String(m["name_key"])):
			missing_mode_keys += 1
		if not en.has(String(m["desc_key"])):
			missing_mode_keys += 1
	check(missing_mode_keys == 0, "mode name/desc keys exist in en.json")

	# Every pet has a translation key.
	var missing_pet_keys := 0
	for pet in ModeRules.PETS:
		if not en.has("pet.%s" % pet):
			missing_pet_keys += 1
	check(missing_pet_keys == 0, "every pet has a pet.* key in en.json")
	gs.free()
