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

const MODES := ["survival", "decay", "pet", "boss"]
const MAX_NAME_LENGTH := 12
const DEFAULT_TOP_N := 10
const FALLBACK_NAME := "???"


## Trim, strip line breaks, and cap a player name; empty becomes "???".
static func sanitize_name(name: String) -> String:
	var clean := name.replace("\n", " ").replace("\r", " ").strip_edges()
	if clean.length() > MAX_NAME_LENGTH:
		clean = clean.substr(0, MAX_NAME_LENGTH)
	return FALLBACK_NAME if clean == "" else clean


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
