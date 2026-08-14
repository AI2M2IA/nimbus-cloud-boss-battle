extends SceneTree
## Headless unit tests. Run from the project folder:
##   godot --headless --path . -s tests/run_tests.gd
## Exits 0 on success, 1 on failure.

const Rules := preload("res://scripts/battle_rules.gd")
const ModeRules := preload("res://scripts/mode_rules.gd")
const GameState := preload("res://scripts/game_state.gd")
const QuizImport := preload("res://scripts/quiz_import.gd")
const Leaderboard := preload("res://scripts/leaderboard.gd")
const PetAvatarScript := preload("res://scripts/pet_avatar.gd")
const ReviewSchedulerScript := preload("res://scripts/review_scheduler.gd")
# Deliberately NOT preloading scripts/ui/quiz_question_view.gd as a top-level
# const here: battle.gd/mode_battle.gd already preload it themselves, and a
# *second* top-level preload of the same script from this file (the -s main
# script) corrupts their reference at runtime -- Battle._build_ui() would
# fail with "Nonexistent function 'new' in base 'GDScript'" the moment any
# earlier test in this suite ran before a battle/mode_battle scene got
# add_child()'d. Grab the already-configured view from a real scene instance
# instead (see _test_select_two_keyboard), the same way _test_overflow_hint
# does, rather than instantiating the component standalone.

## Top-level scenes that must load and instantiate without a script compile
## error. This is what would have caught the UITheme global-class-name bug
## (a fresh clone with no .godot cache failed here, not in any pure-logic
## test above) — those only exercise RefCounted modules, never these scenes.
const SMOKE_SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/battle.tscn",
	"res://scenes/mode_battle.tscn",
	"res://scenes/custom_quiz.tscn",
	"res://scenes/leaderboard.tscn",
	"res://scenes/flashcards.tscn",
]

var checks := 0
var failures := 0

# Scratch slot a test can point a signal at. GDScript lambdas capture outer
# locals by value, not by reference, so `signal.connect(func(x): local = x)`
# silently never writes back to `local` -- routing through an instance
# method + instance var sidesteps that trap.
var _last_signal_payload = null


func _capture_signal_payload(payload) -> void:
	_last_signal_payload = payload


func _initialize() -> void:
	_test_rules()
	_test_checkpoints()
	_test_modes()
	_test_pet_avatar()
	_test_question_bank()
	_test_game_state()
	_test_save_hardening()
	_test_i18n()
	_test_quiz_import()
	_test_leaderboard()
	_test_custom_sets()
	_test_leaderboard_persistence()
	_test_mode_sessions()
	_test_review_scheduler()
	_test_text_scale()
	_test_branding()
	_test_scene_smoke()
	await _test_overflow_hint()
	await _test_select_two_keyboard()
	await _test_retreat_confirmation()
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


## Snapshot a user:// file's text, or null when it does not exist.
func _snapshot_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	return null if f == null else f.get_as_text()


## Restore a snapshot: write the text back, or remove the file if it
## did not exist before the test touched it.
func _restore_file(path: String, content) -> void:
	if content == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(String(content))


## The Game autoload is not exposed as a global identifier to a -s main
## script at compile time; resolve it through the tree instead (relative
## path -- during _initialize the absolute "/root/Game" is not wired yet).
func _game_autoload():
	return root.get_node("Game")


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

	check(Rules.requeue_position(20) == 7, "requeue scales with remaining queue size (20 -> 7)")
	check(Rules.requeue_position(65) == 22, "requeue scales for a long gauntlet-sized queue (65 -> 22)")
	check(Rules.requeue_position(4) == 4, "requeue at the offset boundary returns queue size")
	check(Rules.requeue_position(2) == 2, "requeue clamps to queue size for a short queue")
	check(Rules.requeue_position(0) == 0, "requeue into empty queue")


# ---------------------------------------------------------- run checkpoints

func _test_checkpoints() -> void:
	print("[checkpoints]")
	var bank := {"q1": true, "q2": true, "q3": true, "q4": true}

	var cp := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 1, 2, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	var ok := Rules.validate_checkpoint(cp, bank)
	check(not ok.is_empty(), "a well-formed checkpoint validates")
	check(ok.get("queue") == ["q3", "q4"], "queue order survives validation")
	check(int(ok.get("hearts", -1)) == 3, "hearts survive validation")
	check(int(ok.get("correct", -1)) == 2, "correct count survives validation")
	check(int(ok.get("answered", -1)) == 5, "answered count survives validation")
	check(int(ok.get("streak", -1)) == 1, "streak survives validation")
	check(int(ok.get("best_streak", -1)) == 2, "best_streak survives validation")
	check(int(ok.get("xp_earned", -1)) == 1300, "xp survives validation")
	check(int(ok.get("total", -1)) == 4, "total survives validation")
	check(ok.get("attempted") == ["q1", "q2", "q3"], "attempted ids survive validation")
	check(int(ok.get("first_try_correct", -1)) == 1, "first-attempt accuracy survives validation")
	check(ok.get("pool") == ["q1", "q2", "q3", "q4"], "sampled pool survives validation")

	# JSON round-trip turns every number into a float; integral floats must
	# still validate (that is how a real save.json comes back).
	var round_tripped = JSON.parse_string(JSON.stringify(cp))
	check(not Rules.validate_checkpoint(round_tripped, bank).is_empty(), "a JSON round-tripped checkpoint still validates")

	# best_streak predates nothing here, but an older save without the field
	# must still be accepted, falling back to the current streak.
	var legacy := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	legacy.erase("best_streak")
	var legacy_ok := Rules.validate_checkpoint(legacy, bank)
	check(not legacy_ok.is_empty(), "a checkpoint without best_streak still validates")
	check(int(legacy_ok.get("best_streak", -1)) == 1, "missing best_streak falls back to streak")

	check(Rules.validate_checkpoint("garbage", bank).is_empty(), "a non-dictionary checkpoint is dropped")
	check(Rules.validate_checkpoint({}, bank).is_empty(), "an empty checkpoint is dropped")
	var before_answer := Rules.make_checkpoint(
		["q1", "q2", "q3", "q4"], 3, 0, 1, 0, 0, 0, 4,
		[], 0, ["q1", "q2", "q3", "q4"])
	check(not Rules.validate_checkpoint(before_answer, bank).is_empty(), "leaving before the first answer preserves the sampled run")

	var no_queue := Rules.make_checkpoint(
		[], 3, 4, 4, 0, 0, 400, 4,
		["q1", "q2", "q3", "q4"], 4, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(no_queue, bank).is_empty(), "an empty queue is dropped")

	var foreign := Rules.make_checkpoint(
		["q3", "zz"], 3, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(foreign, bank).is_empty(), "a queue id missing from the bank is dropped")

	var dup := Rules.make_checkpoint(
		["q3", "q3"], 3, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(dup, bank).is_empty(), "duplicate queue ids are dropped")

	var dead := Rules.make_checkpoint(
		["q3", "q4"], 0, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(dead, bank).is_empty(), "zero hearts is dropped")

	var bad_math := Rules.make_checkpoint(
		["q3", "q4"], 3, 1, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(bad_math, bank).is_empty(), "correct + remaining != total is dropped")

	var bad_answered := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 1, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(bad_answered, bank).is_empty(), "answered < correct is dropped")

	var neg_xp := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 1, 1, -100, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(neg_xp, bank).is_empty(), "negative XP is dropped")

	var wrong_type := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	wrong_type["hearts"] = "three"
	check(Rules.validate_checkpoint(wrong_type, bank).is_empty(), "a non-numeric field is dropped")

	var fractional := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 1, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	fractional["xp_earned"] = 1300.5
	check(Rules.validate_checkpoint(fractional, bank).is_empty(), "a fractional float is dropped")

	var low_best := Rules.make_checkpoint(
		["q3", "q4"], 3, 2, 5, 3, 1, 1300, 4,
		["q1", "q2", "q3"], 1, ["q1", "q2", "q3", "q4"])
	check(Rules.validate_checkpoint(low_best, bank).is_empty(), "best_streak below streak is dropped")


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
	check(ModeRules.pet_goal(662) == 20, "pet goal stays 20 on the full bank")
	check(ModeRules.pet_goal(20) == 20, "pet goal stays 20 at exactly 20 questions")
	check(ModeRules.pet_goal(5) == 5, "pet goal scales down to a 5-question pool")
	check(ModeRules.pet_goal(1) == 1, "pet goal scales down to a 1-question pool")
	check(ModeRules.pet_outcome(5, 0, 5) == "saved", "scaled goal is winnable on a small pool")
	check(ModeRules.pet_outcome(4, 0, 5) == "ongoing", "scaled goal not yet met")
	check(ModeRules.pet_outcome(4, 3, 5) == "lost", "loss still takes precedence with a scaled goal")
	check(ModeRules.DECAY_QUESTION_CAP == 100, "decay has a 100-question cap")
	check(ModeRules.PETS.size() == 5, "5 pets available")
	check(ModeRules.is_valid_pet("cat") and ModeRules.is_valid_pet("fish"), "cat and fish are valid pets")
	check(not ModeRules.is_valid_pet("dragon"), "dragon is not a pet")
	check(ModeRules.is_valid_pet("hamster"), "hamster is a valid pet")

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


# --------------------------------------------------------------- pet avatar

func _test_pet_avatar() -> void:
	print("[pet_avatar]")
	var avatar = PetAvatarScript.new()
	avatar.set_pet("dog")
	check(avatar.pet_id == "dog", "dog avatar selected")
	avatar.set_pet("dragon")
	check(avatar.pet_id == "cat", "unknown pet falls back to cat")
	avatar.set_progress(7, 20, 1, 3)
	check(is_equal_approx(avatar.progress_ratio(), 0.35), "pet progress ratio")
	avatar.set_progress(99, 20, 9, 3)
	check(is_equal_approx(avatar.progress_ratio(), 1.0), "pet progress caps at 1.0")
	avatar.free()


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
	var bad_why_nots := 0
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
		if typeof(q.get("whyNots")) == TYPE_DICTIONARY:
			for why_key in q["whyNots"]:
				if not keys.has(why_key) or q.get("answers", []).has(why_key):
					bad_why_nots += 1
		if String(q.get("type", "")) == "select_two" and q.get("answers", []).size() != 2:
			bad_two += 1
	check(bad_fields == 0, "all questions have required fields")
	check(bad_answers == 0, "every answer key exists in options")
	check(bad_two == 0, "select_two questions have exactly 2 answers")
	check(bad_why_nots == 0, "distractor explanations follow their remapped option keys")

	# Regression: the original supplemental batch (vpc-q00..09) had the
	# correct answer on "A" in all 10 questions, with nothing here to catch
	# it — a player could learn to guess a fixed letter instead of reading
	# the question. Guards against the same mistake creeping back in for any
	# single-answer letter, without demanding perfect balance.
	var letter_counts := {"A": 0, "B": 0, "C": 0, "D": 0}
	var single_supplemental := 0
	for q in qs:
		if String(q.get("source", "")) != "supplemental":
			continue
		if String(q.get("type", "")) != "single":
			continue
		single_supplemental += 1
		var ans: Array = q.get("answers", [])
		if ans.size() == 1 and letter_counts.has(String(ans[0])):
			letter_counts[String(ans[0])] += 1
	var max_share := 0.0
	if single_supplemental > 0:
		for letter in letter_counts:
			max_share = max(max_share, float(letter_counts[letter]) / float(single_supplemental))
	check(
		single_supplemental == 0 or max_share <= 0.6,
		"supplemental answers aren't dominated by one letter (worst share %.0f%% of %d)"
			% [max_share * 100.0, single_supplemental]
	)

	var exam_letter_counts := {"A": 0, "B": 0, "C": 0, "D": 0}
	var single_exam := 0
	for q in qs:
		if String(q.get("source", "")) != "exam" or String(q.get("type", "")) != "single":
			continue
		single_exam += 1
		var answer: Array = q.get("answers", [])
		if answer.size() == 1 and exam_letter_counts.has(String(answer[0])):
			exam_letter_counts[String(answer[0])] += 1
	var exam_max_share := 0.0
	for letter in exam_letter_counts:
		if single_exam > 0:
			exam_max_share = max(exam_max_share, float(exam_letter_counts[letter]) / float(single_exam))
	check(
		single_exam == 0 or exam_max_share <= 0.35,
		"exam answers are balanced across A-D (worst share %.0f%% of %d)"
			% [exam_max_share * 100.0, single_exam]
	)

	# Regression: questions.json carries a `counts` summary block (total /
	# byDomain) that nothing else in the game or this test suite reads --
	# it silently drifted out of sync with the real array after a past
	# content edit and nobody noticed for a whole round of changes. Catch
	# that class of mistake here. Regenerate with
	# `python3 data/build_question_stats.py` after editing questions.json.
	var counts: Dictionary = data.get("counts", {})
	check(
		int(counts.get("total", -1)) == qs.size(),
		"counts.total (%s) matches the actual question count (%d)"
			% [str(counts.get("total")), qs.size()]
	)
	var actual_by_domain := {}
	for q in qs:
		# JSON.parse_string() yields floats for numeric fields, and
		# str(2.0) != "2" -- cast through int() first so the key matches
		# the plain "0".."4" string keys the JSON file itself uses.
		var domain_key := str(int(q.get("domain")))
		actual_by_domain[domain_key] = actual_by_domain.get(domain_key, 0) + 1
	var counts_by_domain: Dictionary = counts.get("byDomain", {})
	var by_domain_matches := counts_by_domain.size() == actual_by_domain.size()
	if by_domain_matches:
		for domain_key in actual_by_domain:
			if int(counts_by_domain.get(domain_key, -1)) != actual_by_domain[domain_key]:
				by_domain_matches = false
				break
	check(by_domain_matches, "counts.byDomain matches the actual per-domain breakdown (stale? re-run data/build_question_stats.py)")


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
		elif id == "d0":
			# Regression: this used to filter strictly on domain == 0 (a
			# 4-question pool) despite being billed as "Cross-domain warm-up".
			var domains_seen := {}
			for q in pool:
				domains_seen[int(q.get("domain", -99))] = true
			check(domains_seen.has(0), "Gatekeeper pool still includes its own domain-0 questions")
			for d in [1, 2, 3, 4]:
				check(domains_seen.has(d), "Gatekeeper pool includes domain %d (actually cross-domain now)" % d)
		else:
			var dom := int(b["domain"])
			var only_dom := true
			for q in pool:
				if int(q.get("domain", -99)) != dom:
					only_dom = false
			check(only_dom, "battle '%s' pool matches domain %d" % [id, dom])
	check(ids.size() == 6, "battle ids are unique")
	check(gs.get_battle("nope")["id"] == "d0", "unknown battle falls back to d0")

	var gatekeeper_pool := gs.questions_for_battle("d0")
	var gatekeeper_ids: Array = []
	for q in gatekeeper_pool:
		gatekeeper_ids.append(String(q.get("id", "")))
	var gatekeeper_checkpoint := Rules.make_checkpoint(
		gatekeeper_ids.slice(1), 5, 1, 1, 1, 1, 100, gatekeeper_ids.size(),
		[gatekeeper_ids[0]], 1, gatekeeper_ids)
	gs.save_data = {"xp": 0, "battles": {"d0": {"in_progress": gatekeeper_checkpoint}}}
	var restored_gatekeeper := gs.battle_checkpoint("d0")
	check(not restored_gatekeeper.is_empty(), "Gatekeeper checkpoint validates without drawing a new random pool")
	check(restored_gatekeeper["pool"] == gatekeeper_ids, "Gatekeeper keeps its exact sampled pool")

	gs.save_data = {"xp": 0, "battles": {}}
	gs._fallback = gs._load_lang_file("en")
	check(gs.player_rank() == "Cloud Novice", "rank at 0 XP")
	gs.save_data["xp"] = 9999
	check(gs.player_rank() == "Cloud Novice", "rank just under the first threshold")
	gs.save_data["xp"] = 10000
	check(gs.player_rank() == "Region Rookie", "rank at the first threshold")
	gs.save_data["xp"] = 45000
	check(gs.player_rank() == "Availability Zone Adventurer", "rank at 45000 XP")
	gs.save_data["xp"] = 999999
	check(gs.player_rank() == "Solutions Architect Hero", "top rank")
	var next: Dictionary = gs.next_rank_info()
	check(next.is_empty(), "no next rank at the top")
	gs.save_data["xp"] = 0
	next = gs.next_rank_info()
	check(int(next.get("remaining", -1)) == 10000, "next rank is 10000 XP away at zero")
	check(String(next.get("key", "")) == "rank.rookie", "next rank key is the rookie rank")

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


# ---------------------------------------------------------- save hardening

func _test_save_hardening() -> void:
	print("[save_hardening]")
	var gs = GameState.new()

	# A hand-edited save with wrong types must not survive as-is.
	var dirty := {
		"xp": "lots",
		"battles": {
			"d1": {"defeated": "yes", "best_accuracy": 9.0, "best_streak": -4, "attempts": "many"},
			"unknown": {"defeated": true},
		},
		"modes": {"survival": {"best_score": -10, "attempts": 2.5}, "unknown": {"best_score": 999}},
		"text_scale": 99.0,
		"lang": "../../etc/passwd",
		"unknown_key": 1,
		"player_name": "  ok name" + char(0x202E) + "  ",
	}
	var clean: Dictionary = gs._sanitize_save_data(dirty)
	check(int(clean.get("xp", -1)) == 0, "non-numeric XP resets to 0")
	check(typeof(clean.get("battles")) == TYPE_DICTIONARY, "battle records normalize to a dictionary")
	check(is_equal_approx(float(clean.get("text_scale", -1.0)), gs.TEXT_SCALE_MAX), "text_scale clamps to max")
	check(not clean.has("lang"), "unknown saved language is dropped")
	check(String(clean.get("player_name", "")) == "ok name", "saved player name is sanitized")
	check(clean["battles"].has("d1") and not clean["battles"].has("unknown"), "only known battle ids survive")
	check(is_equal_approx(float(clean["battles"]["d1"]["best_accuracy"]), 1.0), "battle accuracy clamps to 0..1")
	check(int(clean["battles"]["d1"]["best_streak"]) == 0, "negative battle streak resets to zero")
	check(clean["modes"].has("survival") and not clean["modes"].has("unknown"), "only known mode ids survive")
	check(int(clean["modes"]["survival"]["best_score"]) == 0, "negative mode score resets to zero")
	check(not clean.has("unknown_key"), "unknown keys are dropped")

	# set_language rejects unknown codes instead of writing them to the save.
	gs._fallback = gs._load_lang_file("en")
	gs.save_data = {"xp": 0, "battles": {}}
	gs.set_language("../../etc/passwd")
	check(gs.lang != "../../etc/passwd", "set_language rejects an unknown code")
	check(String(gs.save_data.get("lang", "")) != "../../etc/passwd", "an unknown lang code is never persisted")

	# Atomic writes leave no stray .tmp file behind.
	var snap = _snapshot_file(GameState.SAVE_PATH)
	gs.save_data = {"xp": 123, "battles": {}}
	gs._write_save()
	check(FileAccess.file_exists(GameState.SAVE_PATH), "atomic write lands the save file")
	check(not FileAccess.file_exists(GameState.SAVE_PATH + ".tmp"), "atomic write leaves no .tmp behind")
	var reloaded = JSON.parse_string(FileAccess.open(GameState.SAVE_PATH, FileAccess.READ).get_as_text())
	check(int(reloaded.get("xp", -1)) == 123, "the atomically written save parses back")
	_restore_file(GameState.SAVE_PATH, snap)
	gs.free()


# -------------------------------------------------------------------- i18n

func _test_i18n() -> void:
	print("[i18n]")
	var gs = GameState.new()
	var en: Dictionary = gs._load_lang_file("en")
	var pt: Dictionary = gs._load_lang_file("pt")
	check(en.size() > 0, "en.json loads (%d keys)" % en.size())
	check(pt.size() > 0, "pt.json loads (%d keys)" % pt.size())
	check(gs.LANGS.size() == 19, "19 languages defined (book reference list)")

	# Every language in LANGS must ship a complete, consistent file whose
	# format placeholders (%d, %s, %.1f) appear in the same order as English,
	# or runtime formatting would break after switching language.
	var re := RegEx.new()
	re.compile("%(\\.\\d+)?[dsf]")
	var bad_files: Array = []
	var bad_keys: Array = []
	var non_string: Array = []
	var bad_specs: Array = []
	for l in gs.LANGS:
		var code := String(l["code"])
		if code == "en":
			continue
		var d: Dictionary = gs._load_lang_file(code)
		if d.is_empty():
			bad_files.append(code)
			continue
		for key in en.keys():
			if not d.has(key) and not bad_keys.has(code):
				bad_keys.append(code)
		for key in d.keys():
			if not en.has(key):
				if not bad_keys.has(code):
					bad_keys.append(code)
			elif typeof(d[key]) != TYPE_STRING:
				if not non_string.has(code):
					non_string.append(code)
			else:
				var en_specs := []
				for m in re.search_all(String(en[key])):
					en_specs.append(m.get_string())
				var d_specs := []
				for m in re.search_all(String(d[key])):
					d_specs.append(m.get_string())
				if en_specs != d_specs and not bad_specs.has(code):
					bad_specs.append(code)
	check(bad_files.is_empty(), "every language file loads (bad: %s)" % str(bad_files))
	check(bad_keys.is_empty(), "key sets match en.json everywhere (bad: %s)" % str(bad_keys))
	check(non_string.is_empty(), "all i18n values are strings (bad: %s)" % str(non_string))
	check(bad_specs.is_empty(), "format placeholders match en order (bad: %s)" % str(bad_specs))

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

	# Every boss subtitle i18n key must exist in en.json.
	var missing_boss_keys := 0
	for b in gs.BATTLES:
		if not en.has(String(b["subtitle_key"])):
			missing_boss_keys += 1
	check(missing_boss_keys == 0, "boss subtitle keys exist in en.json")

	# Every rank i18n key must exist in en.json.
	var missing_rank_keys := 0
	for r in gs.RANKS:
		if not en.has(String(r[1])):
			missing_rank_keys += 1
	check(missing_rank_keys == 0, "rank keys exist in en.json")

	# Every pet has a translation key.
	var missing_pet_keys := 0
	for pet in ModeRules.PETS:
		if not en.has("pet.%s" % pet):
			missing_pet_keys += 1
	check(missing_pet_keys == 0, "every pet has a pet.* key in en.json")
	gs.free()


# --------------------------------------------------------------- quiz import

func _test_quiz_import() -> void:
	print("[quiz_import]")
	check(QuizImport.normalize([1, 2]).has("questions"), "normalize wraps a bare array")
	check(QuizImport.normalize({"questions": [1]})["questions"].size() == 1, "normalize passes a dict through")
	check(QuizImport.normalize("x")["questions"].is_empty(), "normalize coerces garbage to empty")
	var good := {"id": "q1", "stem": "s", "options": [{"key": "A", "text": "a"}, {"key": "B", "text": "b"}], "answers": ["A"], "type": "single", "explanation": "e", "domain": 1}
	var v1: Dictionary = QuizImport.validate_bank({"questions": [good]})
	check(v1["ok"], "a valid single question passes")
	check(int(v1["count"]) == 1, "count reports 1")
	check(not QuizImport.validate_bank({"questions": []})["ok"], "an empty bank fails")
	var miss: Dictionary = good.duplicate(true)
	miss.erase("explanation")
	check(not QuizImport.validate_bank({"questions": [miss]})["ok"], "a missing field fails")
	var bada: Dictionary = good.duplicate(true)
	bada["answers"] = ["C"]
	check(not QuizImport.validate_bank({"questions": [bada]})["ok"], "an answer not in options fails")
	var two: Dictionary = good.duplicate(true)
	two["type"] = "select_two"
	two["answers"] = ["A"]
	check(not QuizImport.validate_bank({"questions": [two]})["ok"], "select_two with one answer fails")
	check(not QuizImport.validate_bank({"questions": [good, good.duplicate(true)]})["ok"], "a duplicate id fails")
	var bq := QuizImport.build_question("c1", "stem", ["a", "b", "c", "d"], ["A"], "exp", 2)
	check(bq["type"] == "single" and bq["answers"] == ["A"], "build_question makes a single")
	check(bq["options"].size() == 4 and bq["options"][2]["key"] == "C", "build_question maps texts to A-D")
	check(QuizImport.build_question("c2", "s", ["a", "b", "c", "d"], ["A", "C"], "e", 2)["type"] == "select_two", "two answers make a select_two")
	check(QuizImport.validate_bank({"questions": [bq]})["ok"], "a built question validates")
	check(QuizImport.has_unsafe_chars(char(0x07)), "a control char is unsafe")
	check(QuizImport.has_unsafe_chars("a" + char(0x202E) + "b"), "a bidi override is unsafe")
	check(not QuizImport.has_unsafe_chars("plain text 123"), "plain text is safe")
	var over: Array = []
	for _i in range(QuizImport.MAX_QUESTIONS + 1):
		over.append(good)
	check(not QuizImport.validate_bank({"questions": over})["ok"], "an over-limit bank fails")
	var longq: Dictionary = good.duplicate(true)
	longq["id"] = "long1"
	longq["stem"] = "x".repeat(QuizImport.MAX_TEXT_LEN + 1)
	check(not QuizImport.validate_bank({"questions": [longq]})["ok"], "an over-long stem fails")
	var ctrlq: Dictionary = good.duplicate(true)
	ctrlq["id"] = "ctrl1"
	ctrlq["stem"] = "bad" + char(0x202E) + "stem"
	check(not QuizImport.validate_bank({"questions": [ctrlq]})["ok"], "a stem with a bidi override fails")
	var domq: Dictionary = good.duplicate(true)
	domq["id"] = "dom1"
	domq["domain"] = 99999
	check(not QuizImport.validate_bank({"questions": [domq]})["ok"], "an out-of-range domain fails")
	var fractional_domain: Dictionary = good.duplicate(true)
	fractional_domain["id"] = "fractional-domain"
	fractional_domain["domain"] = 1.5
	check(not QuizImport.validate_bank({"questions": [fractional_domain]})["ok"], "a fractional domain fails")
	var duplicate_answers: Dictionary = good.duplicate(true)
	duplicate_answers["id"] = "duplicate-answers"
	duplicate_answers["type"] = "select_two"
	duplicate_answers["answers"] = ["A", "A"]
	check(not QuizImport.validate_bank({"questions": [duplicate_answers]})["ok"], "duplicate answer keys fail")
	var invalid_option_key: Dictionary = good.duplicate(true)
	invalid_option_key["id"] = "invalid-option-key"
	invalid_option_key["options"][0]["key"] = "../A"
	invalid_option_key["answers"] = ["../A"]
	check(not QuizImport.validate_bank({"questions": [invalid_option_key]})["ok"], "non-canonical option keys fail")
	check(QuizImport.utf8_size("é") == 2, "import size uses UTF-8 bytes, not characters")


# ---------------------------------------------------------------- leaderboard

func _test_leaderboard() -> void:
	print("[leaderboard]")
	check(Leaderboard.sanitize_name("  Bob  ") == "Bob", "sanitize_name trims")
	check(Leaderboard.sanitize_name("") == Leaderboard.FALLBACK_NAME, "empty name -> fallback")
	check(Leaderboard.sanitize_name("a\nb") == "a b", "newlines become spaces")
	check(Leaderboard.sanitize_name("a" + char(0x202E) + "b") == "ab", "bidi overrides are stripped from names")
	check(Leaderboard.sanitize_name(char(0x200B)) == Leaderboard.FALLBACK_NAME, "a name of only unsafe chars falls back")
	check(Leaderboard.sanitize_name("abcdefghijklmnop").length() == Leaderboard.MAX_NAME_LENGTH, "name is capped")
	var a := Leaderboard.make_entry("A", "survival", 10, "2026-01-01T00:00:00")
	var b := Leaderboard.make_entry("B", "survival", 5, "2026-01-01T00:00:00")
	var c := Leaderboard.make_entry("C", "survival", 10, "2026-01-02T00:00:00")
	check(Leaderboard.ranks_before(a, b), "higher score ranks first")
	check(Leaderboard.ranks_before(a, c), "on a tie the earlier date ranks first")
	var arr: Array = []
	arr = Leaderboard.insert_entry(arr, b)
	arr = Leaderboard.insert_entry(arr, a)
	check(arr[0]["name"] == "A", "insert_entry keeps the array ranked")
	check(arr.size() == 2, "insert_entry grows the array")
	check(Leaderboard.sort_entries([b, a, c])[0]["score"] == 10, "sort_entries ranks an unsorted array")
	var mixed := [a, b, Leaderboard.make_entry("D", "decay", 99, "2026-01-01T00:00:00")]
	check(Leaderboard.top_for_mode(mixed, "survival", 10).size() == 2, "top_for_mode filters by mode")
	check(Leaderboard.top_for_mode(mixed, "survival", 1).size() == 1, "top_for_mode caps at N")

	# Per-mode bound: inserting past MAX_ENTRIES_PER_MODE trims the worst
	# entries of that mode only, so leaderboard.json can't grow unbounded.
	var capped: Array = []
	for i in range(Leaderboard.MAX_ENTRIES_PER_MODE + 5):
		capped = Leaderboard.insert_entry(capped, Leaderboard.make_entry("p%d" % i, "survival", i, "2026-01-01T00:00:00"))
	check(Leaderboard.top_for_mode(capped, "survival", 999).size() == Leaderboard.MAX_ENTRIES_PER_MODE, "one mode is capped at MAX_ENTRIES_PER_MODE")
	capped = Leaderboard.insert_entry(capped, Leaderboard.make_entry("other", "decay", 1, "2026-01-01T00:00:00"))
	check(Leaderboard.top_for_mode(capped, "decay", 999).size() == 1, "other modes are untouched by the cap")
	check(Leaderboard.top_for_mode(capped, "survival", 999)[0]["score"] == Leaderboard.MAX_ENTRIES_PER_MODE + 4, "the cap keeps the best entries")


# --------------------------------------------------------------- custom sets

func _test_custom_sets() -> void:
	print("[custom_sets]")
	var snap_sets = _snapshot_file(GameState.CUSTOM_SETS_PATH)
	var snap_save = _snapshot_file(GameState.SAVE_PATH)
	var gs = GameState.new()
	gs.custom_sets = []
	var q := QuizImport.build_question("u1", "stem", ["a", "b", "c", "d"], ["A"], "exp", 1)
	var id := gs.save_custom_set("My Set", [q])
	check(id != "", "save_custom_set returns an id")
	check(gs.list_custom_sets().size() == 1, "the set is listed")
	check(gs.get_custom_set(id)["questions"].size() == 1, "the set keeps its question")
	var verdict := gs.append_to_custom_set("My Set", QuizImport.build_question("u2", "s2", ["a", "b", "c", "d"], ["A"], "e", 1))
	check(verdict["ok"], "append_to_custom_set returns an ok verdict")
	check(gs.get_custom_set(id)["questions"].size() == 2, "append grew the set")
	gs.set_active_set(id)
	check(gs.active_set_id() == id, "the active set is tracked")
	gs.remove_custom_set(id)
	check(gs.list_custom_sets().is_empty(), "remove_custom_set clears the set")
	check(gs._sanitize_custom_sets([42, {"id": "", "name": "n", "questions": []}]).is_empty(), "load drops malformed and empty-id sets")
	var keepq := QuizImport.build_question("k1", "stem", ["a", "b", "c", "d"], ["A"], "exp", 1)
	var kept := gs._sanitize_custom_sets([{"id": "keep", "name": "Keep", "questions": [keepq]}])
	check(kept.size() == 1 and kept[0]["id"] == gs._custom_set_id("Keep"), "load keeps and canonicalizes a set whose questions validate")
	check(gs._sanitize_custom_sets([{"id": "bad", "name": "Bad", "questions": [{"id": "x"}]}]).is_empty(), "load drops a set with invalid questions")
	check(gs.save_custom_set(char(0x202E), [keepq]) == "", "a set name empty after sanitization is rejected")
	var sanitized_name := gs._sanitize_custom_sets([{
		"id": "spoofed",
		"name": "Safe" + char(0x202E) + " Name",
		"questions": [keepq],
	}])
	check(sanitized_name.size() == 1 and sanitized_name[0]["name"] == "Safe Name", "loaded set names strip unsafe formatting characters")
	# Regression: the ASCII-only slug used to collapse different names to the
	# same id and silently overwrite each other -- both a punctuation-only
	# difference and, worse, any pair of non-Latin names (which used to both
	# collapse all the way down to the single shared id "set-unnamed").
	check(gs._custom_set_id("My Set!") != gs._custom_set_id("My-Set"), "different names no longer collide on the same id")
	check(gs._custom_set_id("日本語のセット") != gs._custom_set_id("另一个套装"), "two non-Latin names no longer both collapse to set-unnamed")
	check(gs._custom_set_id("My Set") == gs._custom_set_id("My Set"), "the exact same name is still deterministic (re-import replaces)")
	gs.free()
	_restore_file(GameState.CUSTOM_SETS_PATH, snap_sets)
	_restore_file(GameState.SAVE_PATH, snap_save)


# ------------------------------------------------- leaderboard persistence

func _test_leaderboard_persistence() -> void:
	print("[leaderboard_persistence]")
	var snap_lb = _snapshot_file(GameState.LEADERBOARD_PATH)
	var snap_save = _snapshot_file(GameState.SAVE_PATH)
	var gs = GameState.new()
	gs.leaderboard_entries = []
	gs.save_data = {"xp": 0, "battles": {}}
	gs.record_score("Zed", "survival", 7)
	gs.record_score("Amy", "survival", 12)
	var top := gs.leaderboard_top("survival", 10)
	check(top.size() == 2, "two scores were recorded")
	check(top[0]["name"] == "Amy", "the higher score ranks first")
	var gs2 = GameState.new()
	gs2.leaderboard_entries = []
	gs2._load_leaderboard()
	check(gs2.leaderboard_top("survival", 10).size() == 2, "scores persist and reload")
	gs.free()
	gs2.free()
	_restore_file(GameState.LEADERBOARD_PATH, snap_lb)
	_restore_file(GameState.SAVE_PATH, snap_save)


# ----------------------------------------------- integration: mode sessions

func _test_mode_sessions() -> void:
	print("[mode_sessions]")
	check(not ModeRules.survival_is_over(2), "survival is alive at 2 wrong")
	check(ModeRules.survival_is_over(3), "survival ends at 3 wrong")
	var pts := 1000
	for i in range(20):
		pts = ModeRules.decay_points(pts, false)
	check(ModeRules.decay_is_over(pts), "decay reaches game over after enough wrong answers")
	check(not ModeRules.decay_is_over(ModeRules.decay_points(100, true)), "a correct answer keeps decay alive")
	check(ModeRules.pet_outcome(19, 0) == "ongoing", "the pet is ongoing before 20 correct")
	check(ModeRules.pet_outcome(20, 0) == "saved", "the pet is saved at 20 correct")
	check(ModeRules.pet_outcome(5, 3) == "lost", "the pet is lost at 3 wrong")
	check(ModeRules.is_valid_pet("cat") and not ModeRules.is_valid_pet("dragon"), "pet validation")


# ----------------------------------------------------------- review scheduler

func _test_review_scheduler() -> void:
	print("[review_scheduler]")
	var rs = ReviewSchedulerScript.new()
	var card = rs.new_card("fc-1", "1", 0)
	check(int(card["box"]) == 1, "new card starts in box 1")
	check(int(card["times_seen"]) == 0, "new card unseen")
	check(rs.is_due(card, 0), "box 1 card is always due")
	var promoted = rs.mark(card, true, 0)
	check(int(promoted["box"]) == 2, "success promotes to box 2")
	check(int(promoted["times_seen"]) == 1, "seen count increments")
	check(not rs.is_due(promoted, 1), "box 2 not due after 1 day")
	check(rs.is_due(promoted, 2), "box 2 due after 2 days")
	var reset = rs.mark(promoted, false, 5)
	check(int(reset["box"]) == 1, "failure resets to box 1")
	check(rs.interval_for_box(1) == 0 and rs.interval_for_box(2) == 2 and rs.interval_for_box(3) == 5 and rs.interval_for_box(4) == 10, "box intervals 0/2/5/10")
	var capped = rs.mark(rs.mark(rs.mark(rs.mark(card, true, 0), true, 0), true, 0), true, 0)
	check(int(capped["box"]) == 4, "box caps at 4")
	var cards = rs.ensure_cards_for_questions([], [{"id": "fc-a", "domain": "1"}, {"id": "fc-b", "domain": "2"}])
	check(cards.size() == 2, "ensure builds a card per item")
	check(rs.due_cards(cards, 0, "1").size() == 1, "due_cards filters by domain")
	var gsf = GameState.new()
	gsf._load_flashcards()
	check(gsf.flashcards.size() == 186, "186 flashcards loaded from data")
	check(rs.ensure_cards_for_questions([], gsf.flashcards).size() == 186, "a review card is built per flashcard")
	gsf.free()

# --------------------------------------------------------------- text scale

func _test_text_scale() -> void:
	print("[text_scale]")
	check(GameState.stepped_scale(1.0, 0.15) > 1.0, "plus increases scale")
	check(GameState.stepped_scale(1.0, -0.15) < 1.0, "minus decreases scale")
	check(GameState.stepped_scale(GameState.TEXT_SCALE_MAX, 0.15) == GameState.TEXT_SCALE_MAX, "clamps at max")
	check(GameState.stepped_scale(GameState.TEXT_SCALE_MIN, -0.15) == GameState.TEXT_SCALE_MIN, "clamps at min")

# ------------------------------------------------------------------- branding

func _test_branding() -> void:
	print("[branding]")
	check(String(ProjectSettings.get_setting("application/config/name", "")) == "Nimbus Cloud Boss Battle", "project name is the official title")
	var font_path := String(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	check(font_path == "res://fonts/notosans_fallback.tres", "project uses the single global fallback-font chain")
	var fallback_font := load(font_path) as Font
	check(fallback_font != null, "global fallback font loads")
	if fallback_font != null:
		check(fallback_font.has_char(0x25BC), "fallback font renders the overflow symbol")
		check(fallback_font.has_char(0x2713) and fallback_font.has_char(0x2717), "fallback font renders correct/wrong markers")
	var gs = GameState.new()
	var bad := 0
	for l in gs.LANGS:
		var d = gs._load_lang_file(String(l["code"]))
		if String(d.get("menu.title", "")) != "NIMBUS CLOUD BOSS BATTLE":
			bad += 1
	check(bad == 0, "menu.title is the official name in all %d locales" % gs.LANGS.size())
	gs.free()

# ---------------------------------------------------------------- scene smoke

## Every top-level scene must load and instantiate cleanly. Scripts that lean
## on a bare global class_name identifier (like UITheme) instead of an
## explicit preload only fail here — a fresh clone with no .godot cache has
## no global-script-class cache yet, and none of the checks above touch a
## scene at all, so they stayed green while the game itself failed to start.
func _test_scene_smoke() -> void:
	print("[scene_smoke]")
	for scene_path in SMOKE_SCENES:
		var packed: PackedScene = load(scene_path)
		check(packed != null, "loads without a script compile error: %s" % scene_path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		check(instance != null, "instantiates: %s" % scene_path)
		if instance != null:
			instance.free()


# --------------------------------------------------------------- overflow hint

## battle.gd/mode_battle.gd show a "▼" cue on the question card once its stem
## and options are tall enough to need scrolling (long multi-part scenario
## questions were easy to miss needing a scroll at the default window size).
## Verifying this by screenshotting a live xdotool session turned out to be
## unreliable: once a longer question shifts the answer buttons' positions,
## a hardcoded click coordinate silently misses and every later screenshot in
## the sequence is identical -- inconclusive, not a real check. This drives
## the scene directly instead: add the real instance to the tree, force the
## stem/options text long enough to guarantee overflow and confirm the hint
## appears, then shrink the text back down and confirm the hint hides again.
func _test_overflow_hint() -> void:
	print("[overflow_hint]")
	# Driving a real battle scene answers real questions (its handlers run),
	# which now writes battle checkpoints into the save -- snapshot the save
	# and force a fresh d0 battle so a leftover checkpoint can't push the
	# scene down the resume-dialog path and skew these layout checks.
	var snap_save = _snapshot_file(GameState.SAVE_PATH)
	_game_autoload().clear_battle_checkpoint("d0")
	await _check_overflow_hint_for_scene("res://scenes/battle.tscn")
	await _check_overflow_hint_for_scene("res://scenes/mode_battle.tscn")
	_restore_file(GameState.SAVE_PATH, snap_save)


func _check_overflow_hint_for_scene(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	# battle.gd/mode_battle.gd delegate the question card to a shared
	# QuizQuestionView (scripts/ui/quiz_question_view.gd); scroll/
	# overflow_hint/stem_text/options_box live on that child now, not on
	# the scene's own root instance.
	var view = instance.question_view
	var ok := is_instance_valid(view) and is_instance_valid(view.scroll) \
			and is_instance_valid(view.overflow_hint) and is_instance_valid(view.stem_text) \
			and is_instance_valid(view.options_box)
	check(ok, "%s: overflow hint UI nodes exist" % scene_path)
	if not ok:
		instance.queue_free()
		return

	view.stem_text.text = "LOREM ".repeat(400)
	for child in view.options_box.get_children():
		child.text = "X)  " + "filler option text ".repeat(30)
	await view._refresh_overflow_hint()
	await process_frame
	check(view.overflow_hint.visible, "%s: hint shows once content overflows" % scene_path)

	view.stem_text.text = "Short question."
	for child in view.options_box.get_children():
		child.text = "short"
	await view._refresh_overflow_hint()
	await process_frame
	check(not view.overflow_hint.visible, "%s: hint hides again once content fits" % scene_path)

	instance.queue_free()


# --------------------------------------------------------- select_two keyboard

## An earlier draft of the keyboard-shortcut feature (from a third-party
## review doc) called the option handler function directly instead of going
## through the Button -- that desyncs the button's visual pressed state from
## selected_keys, since BaseButton only redraws on set_pressed()/toggled, not
## on a bare function call. _activate_option() routes through the real Button
## so this can't regress silently; this test drives that exact select_two
## path with synthetic key events and checks the actual button_pressed state
## after each press, not just the internal selected_keys array.
func _test_select_two_keyboard() -> void:
	print("[select_two_keyboard]")
	# Same isolation as _test_overflow_hint: the synthetic key presses below
	# also hit the real first question's handlers, which write a checkpoint
	# into the save -- snapshot/restore so it never leaks between runs.
	var snap_save = _snapshot_file(GameState.SAVE_PATH)
	_game_autoload().clear_battle_checkpoint("d0")
	# Drive the already-configured question_view off a real battle.tscn
	# instance (same approach as _check_overflow_hint_for_scene) rather than
	# instantiating QuizQuestionView standalone -- see the note by the
	# top-of-file preload consts for why a second preload of that script
	# from this file breaks battle.gd's own copy.
	var packed: PackedScene = load("res://scenes/battle.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	var view = instance.question_view
	if not is_instance_valid(view):
		check(false, "select_two_keyboard: battle.tscn produced a question_view")
		instance.queue_free()
		return

	var restore_pool: Array = _game_autoload().questions.slice(0, 4)
	var restore_ids: Array = []
	var restore_bank := {}
	for q in restore_pool:
		var restore_id := String(q.get("id", ""))
		restore_ids.append(restore_id)
		restore_bank[restore_id] = true
	var restore_checkpoint := Rules.make_checkpoint(
		[restore_ids[2], restore_ids[3]], 3, 2, 5, 1, 2, 1300, 4,
		[restore_ids[0], restore_ids[1], restore_ids[2]], 1, restore_ids)
	instance._restore_checkpoint(Rules.validate_checkpoint(restore_checkpoint, restore_bank))
	check(instance.attempted.has(restore_ids[2]), "resume restores attempted ids for rematch semantics")
	check(instance.first_try_correct == 1, "resume restores first-attempt accuracy")
	check(instance.battle_pool_ids == restore_ids, "resume restores the exact sampled battle pool")

	var question := {
		"id": "test-select-two",
		"type": "select_two",
		"stem": "Synthetic select_two question for keyboard toggle testing.",
		"options": [
			{"key": "A", "text": "Option A"},
			{"key": "B", "text": "Option B"},
			{"key": "C", "text": "Option C"},
			{"key": "D", "text": "Option D"},
		],
		"answers": ["A", "C"],
	}
	view.show_question(question)
	await process_frame

	_last_signal_payload = null
	view.answer_submitted.connect(_capture_signal_payload)

	_press_key(view, KEY_A)
	await process_frame
	check(view.option_buttons["A"].button_pressed, "select_two: pressing A visually presses the button")
	check(view.selected_keys == ["A"], "select_two: pressing A selects it")

	_press_key(view, KEY_B)
	await process_frame
	check(view.option_buttons["B"].button_pressed, "select_two: pressing B visually presses the button")
	check(view.selected_keys == ["A", "B"], "select_two: A and B both selected")
	check(not view.confirm_btn.disabled, "select_two: confirm enables once 2 are selected")

	# Re-pressing an already-selected key must toggle it back OFF visually --
	# this is the exact bug the third-party doc's code would have missed,
	# since calling _on_option_toggled() directly never touches button_pressed.
	_press_key(view, KEY_A)
	await process_frame
	check(not view.option_buttons["A"].button_pressed, "select_two: re-pressing A visually un-presses the button")
	check(view.selected_keys == ["B"], "select_two: re-pressing A deselects it")
	check(view.confirm_btn.disabled, "select_two: confirm disables once back under 2")

	# Re-select A so A and B are both active, then pick a third (C): the
	# oldest selection (B) should be evicted and visually un-pressed.
	_press_key(view, KEY_A)
	await process_frame
	_press_key(view, KEY_C)
	await process_frame
	check(view.option_buttons["C"].button_pressed, "select_two: pressing a 3rd key (C) visually presses it")
	check(not view.option_buttons["B"].button_pressed, "select_two: 3rd pick evicts the oldest (B) visually")
	check(view.selected_keys == ["A", "C"], "select_two: selection is now A and C")
	check(not view.confirm_btn.disabled, "select_two: confirm stays enabled with exactly 2 selected")

	# Enter, with exactly 2 selected, should submit the current selection.
	_press_key(view, KEY_ENTER)
	await process_frame
	check(_last_signal_payload == ["A", "C"], "select_two: Enter submits the current selection")

	# The official exam bank contains E options, including correct E answers.
	# Keyboard-only players must be able to select them by letter or position.
	var e_question := {
		"id": "test-option-e",
		"type": "single",
		"stem": "Synthetic five-option keyboard question.",
		"options": [
			{"key": "A", "text": "Option A"},
			{"key": "B", "text": "Option B"},
			{"key": "C", "text": "Option C"},
			{"key": "D", "text": "Option D"},
			{"key": "E", "text": "Option E"},
		],
		"answers": ["E"],
	}
	view.show_question(e_question)
	_last_signal_payload = null
	_press_key(view, KEY_E)
	await process_frame
	check(_last_signal_payload == ["E"], "single: E selects the fifth option by letter")
	view.show_question(e_question)
	_last_signal_payload = null
	_press_key(view, KEY_5)
	await process_frame
	check(_last_signal_payload == ["E"], "single: 5 selects the fifth displayed option")

	instance.queue_free()
	_restore_file(GameState.SAVE_PATH, snap_save)


func _press_key(node, keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	node._unhandled_input(event)


# ------------------------------------------------------- retreat confirmation

## "Leave" and Esc must not discard an in-progress battle/run without
## confirmation. Both paths should create the shared modal dialog instead of
## changing scene directly. Only the gating is exercised here -- confirming
## would change this suite's own SceneTree.
func _test_retreat_confirmation() -> void:
	print("[retreat_confirmation]")
	await _check_retreat_confirmation_for_scene("res://scenes/battle.tscn")
	await _check_retreat_confirmation_for_scene("res://scenes/mode_battle.tscn")


func _check_retreat_confirmation_for_scene(scene_path: String) -> void:
	var packed: PackedScene = load(scene_path)
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	check(instance.dialog == null, "%s: confirmation dialog starts closed" % scene_path)

	# Call the same handler as the visible leave/abandon button rather than
	# searching the code-built UI tree for that button.
	if scene_path.ends_with("battle.tscn") and not scene_path.ends_with("mode_battle.tscn"):
		instance._show_leave_dialog()
	else:
		instance._show_abandon_dialog()
	await process_frame
	var dialog = instance.dialog
	check(is_instance_valid(dialog) and dialog.visible,
		"%s: leave button opens the confirmation dialog instead of leaving immediately" % scene_path)

	instance._close_dialog()
	await process_frame
	_press_key(instance, KEY_ESCAPE)
	await process_frame
	dialog = instance.dialog
	check(is_instance_valid(dialog) and dialog.visible,
		"%s: Esc also opens the confirmation dialog instead of leaving immediately" % scene_path)

	instance.queue_free()
