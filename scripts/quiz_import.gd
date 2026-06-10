extends RefCounted
## Pure validation and normalization for player-authored question sets.
## No UI, no file access — mirrors battle_rules.gd / mode_rules.gd so the
## import pipeline stays unit-testable. The schema enforced here is the same
## one tests/run_tests.gd checks on the built-in data/questions.json.

const REQUIRED_FIELDS := ["id", "stem", "options", "answers", "type", "explanation", "domain"]
const VALID_TYPES := ["single", "select_two"]
const OPTION_KEYS := ["A", "B", "C", "D"]
const MAX_REPORTED_ERRORS := 12


## Coerce a raw parsed JSON value into the canonical {questions: [...]} shape.
## Accepts either a bare array of questions or a {questions: [...]} dictionary.
## Anything else normalizes to an empty bank (validate_bank will reject it).
static func normalize(data) -> Dictionary:
	if typeof(data) == TYPE_ARRAY:
		return {"questions": data}
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("questions")) == TYPE_ARRAY:
		return {"questions": data["questions"]}
	return {"questions": []}


## Validate a question bank (canonical or raw — normalize() is applied first).
## Returns {ok: bool, errors: Array[String], count: int}. Rules enforced:
## - the bank is non-empty
## - every question has the required fields
## - id, stem, and explanation are non-empty strings; ids are unique
## - options is a non-empty array of {key, text} with unique, non-empty keys
## - every answer key exists in the options
## - type is "single" (exactly 1 answer) or "select_two" (exactly 2 answers)
## - domain is a number
static func validate_bank(data) -> Dictionary:
	var errors: Array = []
	var bank := normalize(data)
	var qs: Array = bank["questions"]
	if qs.is_empty():
		errors.append("The set has no questions (expected an array or {\"questions\": [...]}).")
		return {"ok": false, "errors": errors, "count": 0}

	var seen_ids := {}
	for i in range(qs.size()):
		if errors.size() >= MAX_REPORTED_ERRORS:
			errors.append("(more errors omitted)")
			break
		var label := "question %d" % (i + 1)
		if typeof(qs[i]) != TYPE_DICTIONARY:
			errors.append("%s: not an object" % label)
			continue
		var q: Dictionary = qs[i]
		var qid := String(q.get("id", ""))
		if qid != "":
			label = "question %d (%s)" % [i + 1, qid]

		var missing: Array = []
		for field in REQUIRED_FIELDS:
			if not q.has(field):
				missing.append(field)
		if not missing.is_empty():
			errors.append("%s: missing field(s): %s" % [label, ", ".join(missing)])
			continue

		if qid.strip_edges() == "":
			errors.append("%s: empty id" % label)
		elif seen_ids.has(qid):
			errors.append("%s: duplicate id" % label)
		seen_ids[qid] = true

		if String(q.get("stem", "")).strip_edges() == "":
			errors.append("%s: empty stem" % label)
		if String(q.get("explanation", "")).strip_edges() == "":
			errors.append("%s: empty explanation" % label)
		if typeof(q.get("domain")) != TYPE_FLOAT and typeof(q.get("domain")) != TYPE_INT:
			errors.append("%s: domain must be a number" % label)

		var keys: Array = []
		var opts = q.get("options")
		if typeof(opts) != TYPE_ARRAY or (opts as Array).is_empty():
			errors.append("%s: options must be a non-empty array" % label)
		else:
			for opt in opts:
				if typeof(opt) != TYPE_DICTIONARY:
					errors.append("%s: option is not an object" % label)
					continue
				var key := String((opt as Dictionary).get("key", "")).strip_edges()
				if key == "":
					errors.append("%s: option with empty key" % label)
				elif keys.has(key):
					errors.append("%s: duplicate option key '%s'" % [label, key])
				if String((opt as Dictionary).get("text", "")).strip_edges() == "":
					errors.append("%s: option '%s' has empty text" % [label, key])
				keys.append(key)

		var answers = q.get("answers")
		if typeof(answers) != TYPE_ARRAY or (answers as Array).is_empty():
			errors.append("%s: answers must be a non-empty array" % label)
			answers = []
		for a in answers:
			if not keys.has(String(a)):
				errors.append("%s: answer key '%s' not found in options" % [label, String(a)])

		var qtype := String(q.get("type", ""))
		if not VALID_TYPES.has(qtype):
			errors.append("%s: type must be one of %s" % [label, ", ".join(VALID_TYPES)])
		elif qtype == "select_two" and (answers as Array).size() != 2:
			errors.append("%s: select_two needs exactly 2 answers" % label)
		elif qtype == "single" and (answers as Array).size() != 1:
			errors.append("%s: single needs exactly 1 answer" % label)

	return {"ok": errors.is_empty(), "errors": errors, "count": qs.size()}


## Build one canonical question from the "add one question" form fields.
## option_texts maps to keys A-D in order; the type is derived from the
## number of answer keys (1 = single, 2 = select_two). The result still
## goes through validate_bank, so a bad form input is reported, not trusted.
static func build_question(id: String, stem: String, option_texts: Array, answer_keys: Array, explanation: String, domain: int) -> Dictionary:
	var options: Array = []
	for i in range(min(option_texts.size(), OPTION_KEYS.size())):
		options.append({"key": OPTION_KEYS[i], "text": String(option_texts[i])})
	var answers: Array = []
	for a in answer_keys:
		var key := String(a).strip_edges().to_upper()
		if key != "" and not answers.has(key):
			answers.append(key)
	return {
		"id": id,
		"source": "custom",
		"domain": domain,
		"type": "select_two" if answers.size() == 2 else "single",
		"stem": stem,
		"options": options,
		"answers": answers,
		"explanation": explanation,
	}
