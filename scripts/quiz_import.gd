extends RefCounted
## Pure validation and normalization for player-authored question sets.
## No UI, no file access — mirrors battle_rules.gd / mode_rules.gd so the
## import pipeline stays unit-testable. The schema enforced here is the same
## one tests/run_tests.gd checks on the built-in data/questions.json.

const REQUIRED_FIELDS := ["id", "stem", "options", "answers", "type", "explanation", "domain"]
const VALID_TYPES := ["single", "select_two"]
const OPTION_KEYS := ["A", "B", "C", "D"]
const MAX_REPORTED_ERRORS := 12
const MAX_QUESTIONS := 1000
const MAX_OPTIONS := 12
const MAX_TEXT_LEN := 4000
const MAX_OPTION_TEXT_LEN := 1500
const MAX_ID_LEN := 200
const MAX_IMPORT_BYTES := 2000000
const MIN_DOMAIN := 0
const MAX_DOMAIN := 99


## True when a string carries ASCII control characters (other than tab and
## newline) or Unicode bidi-override / zero-width formatting characters, which
## can be used to spoof or break the on-screen layout. Such strings are
## rejected at validation time instead of being rendered as-is.
static func has_unsafe_chars(s: String) -> bool:
	for ch in s:
		var cp := ch.unicode_at(0)
		if cp < 0x20 and cp != 0x09 and cp != 0x0A and cp != 0x0D:
			return true
		if cp == 0x7F:
			return true
		if cp >= 0x202A and cp <= 0x202E:
			return true
		if cp >= 0x2066 and cp <= 0x2069:
			return true
		if cp == 0x200B or cp == 0x200E or cp == 0x200F or cp == 0xFEFF:
			return true
	return false


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
	if qs.size() > MAX_QUESTIONS:
		errors.append("The set has too many questions (%d); the limit is %d." % [qs.size(), MAX_QUESTIONS])
		return {"ok": false, "errors": errors, "count": qs.size()}

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
		elif qid.length() > MAX_ID_LEN:
			errors.append("%s: id is too long (limit %d)" % [label, MAX_ID_LEN])
		elif has_unsafe_chars(qid):
			errors.append("%s: id has control or formatting characters" % label)
		elif seen_ids.has(qid):
			errors.append("%s: duplicate id" % label)
		seen_ids[qid] = true

		var stem_s := String(q.get("stem", ""))
		if stem_s.strip_edges() == "":
			errors.append("%s: empty stem" % label)
		elif stem_s.length() > MAX_TEXT_LEN:
			errors.append("%s: stem is too long (limit %d)" % [label, MAX_TEXT_LEN])
		elif has_unsafe_chars(stem_s):
			errors.append("%s: stem has control or formatting characters" % label)
		var expl_s := String(q.get("explanation", ""))
		if expl_s.strip_edges() == "":
			errors.append("%s: empty explanation" % label)
		elif expl_s.length() > MAX_TEXT_LEN:
			errors.append("%s: explanation is too long (limit %d)" % [label, MAX_TEXT_LEN])
		elif has_unsafe_chars(expl_s):
			errors.append("%s: explanation has control or formatting characters" % label)
		var dom = q.get("domain")
		if typeof(dom) != TYPE_FLOAT and typeof(dom) != TYPE_INT:
			errors.append("%s: domain must be a number" % label)
		elif not is_finite(float(dom)) or float(dom) < MIN_DOMAIN or float(dom) > MAX_DOMAIN:
			errors.append("%s: domain is out of range (%d..%d)" % [label, MIN_DOMAIN, MAX_DOMAIN])

		var keys: Array = []
		var opts = q.get("options")
		if typeof(opts) != TYPE_ARRAY or (opts as Array).is_empty():
			errors.append("%s: options must be a non-empty array" % label)
		elif (opts as Array).size() > MAX_OPTIONS:
			errors.append("%s: too many options (limit %d)" % [label, MAX_OPTIONS])
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
				var otext := String((opt as Dictionary).get("text", ""))
				if otext.strip_edges() == "":
					errors.append("%s: option '%s' has empty text" % [label, key])
				elif otext.length() > MAX_OPTION_TEXT_LEN:
					errors.append("%s: option '%s' text is too long (limit %d)" % [label, key, MAX_OPTION_TEXT_LEN])
				elif has_unsafe_chars(otext):
					errors.append("%s: option '%s' has control or formatting characters" % [label, key])
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
