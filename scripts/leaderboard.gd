extends RefCounted
## Pure ranking logic for the local, offline leaderboard.
## No UI, no file access — persistence lives in game_state.gd.
##
## Entry shape (kept flat and minimal so an online sync could serialize it
## later without changes): {name: String, mode: String, score: int, date: String}.
## Dates are ISO 8601 UTC strings, so lexicographic order is chronological.
##
## Ranked modes and what "score" means in each:
## - "survival": correct answers in the run
## - "decay":    final points pool
## - "pet":      best streak of the run
## - "boss":     XP earned in a boss battle

const QuizImport := preload("res://scripts/quiz_import.gd")

const MODES := ["survival", "decay", "pet", "boss"]
const MAX_NAME_LENGTH := 12
const DEFAULT_TOP_N := 10
const FALLBACK_NAME := "???"
## Per-mode cap so leaderboard.json can't grow without bound (record_score
## only ever appends; the display slices top-N anyway).
const MAX_ENTRIES_PER_MODE := 100
const MAX_SCORE := 2147483647
const INVALID_DATE := "9999-12-31T23:59:59"


## Trim, strip line breaks and control/bidi/zero-width characters, and cap a
## player name; empty becomes "???". Names are rendered in the UI, so the
## same character policy as imported question text applies.
static func sanitize_name(name: String) -> String:
	var clean := ""
	for ch in name.replace("\n", " ").replace("\r", " ").strip_edges():
		if not QuizImport.has_unsafe_chars(ch):
			clean += ch
	if clean.length() > MAX_NAME_LENGTH:
		clean = clean.substr(0, MAX_NAME_LENGTH)
	return FALLBACK_NAME if clean.strip_edges() == "" else clean


static func make_entry(name: String, mode: String, score: int, date: String) -> Dictionary:
	return {
		"name": sanitize_name(name),
		"mode": mode if MODES.has(mode) else "boss",
		"score": sanitize_score(score),
		"date": sanitize_date(date),
	}


static func sanitize_score(value) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number != floorf(number):
		return 0
	return mini(int(number), MAX_SCORE)


static func sanitize_date(value: String) -> String:
	if value.length() != 19 or QuizImport.has_unsafe_chars(value):
		return INVALID_DATE
	var iso := RegEx.create_from_string(
		"^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$")
	return value if iso.search(value) != null else INVALID_DATE


## True when a ranks strictly better than b: higher score first,
## then earlier date (first to reach the score keeps the spot).
static func ranks_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return int(a.get("score", 0)) > int(b.get("score", 0))
	return String(a.get("date", "")) < String(b.get("date", ""))


## Insert an entry into an already-ranked array, keeping it ranked, then
## trim the entry's mode to MAX_ENTRIES_PER_MODE so the stored file stays
## bounded. Stable: an entry that ties on score and date goes after
## existing ones. Returns a new array; the input is not mutated.
static func insert_entry(entries: Array, entry: Dictionary) -> Array:
	var out := entries.duplicate()
	var inserted := false
	for i in range(out.size()):
		if ranks_before(entry, out[i]):
			out.insert(i, entry)
			inserted = true
			break
	if not inserted:
		out.append(entry)
	var mode := String(entry.get("mode", ""))
	var kept := 0
	var trimmed: Array = []
	for e in out:
		if String(e.get("mode", "")) != mode:
			trimmed.append(e)
			continue
		kept += 1
		if kept <= MAX_ENTRIES_PER_MODE:
			trimmed.append(e)
	return trimmed


## Re-rank an arbitrary array of entries (e.g. a hand-edited file).
## Built on insert_entry so ties keep their original relative order.
static func sort_entries(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		out = insert_entry(out, e)
	return out


## Top-N ranked entries for one mode. Input does not need to be sorted.
static func top_for_mode(entries: Array, mode: String, n: int = DEFAULT_TOP_N) -> Array:
	var filtered: Array = []
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and String(e.get("mode", "")) == mode:
			filtered.append(e)
	var ranked := sort_entries(filtered)
	return ranked.slice(0, max(n, 0))


## Rebuild raw persisted entries into the safe, expected shape. This keeps a
## hand-edited leaderboard from injecting unsafe names or malformed modes.
static func sanitize_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mode := String(entry.get("mode", ""))
		if not MODES.has(mode):
			continue
		out.append({
			"name": sanitize_name(String(entry.get("name", ""))),
			"mode": mode,
			"score": sanitize_score(entry.get("score", 0)),
			"date": sanitize_date(String(entry.get("date", ""))),
		})
	return out
