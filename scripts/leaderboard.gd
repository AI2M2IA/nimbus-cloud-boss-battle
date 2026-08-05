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
const MAX_ENTRIES_PER_MODE := 50
const FALLBACK_NAME := "???"


## Trim, strip line breaks, and cap a player name; empty or unsafe (bidi-
## override, zero-width, control characters -- see QuizImport.has_unsafe_chars)
## becomes "???". Applied both when an entry is created and, via
## sanitize_entries() below, when one is loaded from disk.
static func sanitize_name(name: String) -> String:
	var clean := name.replace("\n", " ").replace("\r", " ").strip_edges()
	if clean.length() > MAX_NAME_LENGTH:
		clean = clean.substr(0, MAX_NAME_LENGTH)
	if clean == "" or QuizImport.has_unsafe_chars(clean):
		return FALLBACK_NAME
	return clean


static func make_entry(name: String, mode: String, score: int, date: String) -> Dictionary:
	return {"name": sanitize_name(name), "mode": mode, "score": score, "date": date}


## True when a ranks strictly better than b: higher score first,
## then earlier date (first to reach the score keeps the spot).
static func ranks_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return int(a.get("score", 0)) > int(b.get("score", 0))
	return String(a.get("date", "")) < String(b.get("date", ""))


## Insert an entry into an already-ranked array, keeping it ranked.
## Stable: an entry that ties on score and date goes after existing ones.
## Returns a new array; the input is not mutated.
static func insert_entry(entries: Array, entry: Dictionary) -> Array:
	var out := entries.duplicate()
	for i in range(out.size()):
		if ranks_before(entry, out[i]):
			out.insert(i, entry)
			return out
	out.append(entry)
	return out


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


## Re-derives a raw (possibly hand-edited) entries array into well-shaped
## entries: drops anything that isn't a dictionary with a known mode, coerces
## score/date types, and re-applies sanitize_name. Called on every load so an
## edited leaderboard.json can't smuggle an oversized/unsafe name or a
## malformed score onto screen -- the same defense-in-depth custom_sets.json
## already gets on load, just applied here too.
static func sanitize_entries(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var mode := String(e.get("mode", ""))
		if not MODES.has(mode):
			continue
		var raw_score = e.get("score", 0)
		var score := int(raw_score) if (typeof(raw_score) == TYPE_INT or typeof(raw_score) == TYPE_FLOAT) else 0
		out.append({
			"name": sanitize_name(String(e.get("name", ""))),
			"mode": mode,
			"score": score,
			"date": String(e.get("date", "")),
		})
	return out


## Bounds stored entries to the top N per mode so the leaderboard file and
## its in-memory array don't grow without bound over months of local play.
## Display already only shows DEFAULT_TOP_N; this just bounds what's kept
## behind that so an O(n) insert and an O(n log n) load-time sort stay cheap
## indefinitely instead of growing with every single run ever recorded.
static func capped(entries: Array, per_mode_cap: int = MAX_ENTRIES_PER_MODE) -> Array:
	var out: Array = []
	for m in MODES:
		out.append_array(top_for_mode(entries, m, per_mode_cap))
	return sort_entries(out)
