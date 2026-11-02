extends RefCounted
## Pure battle rules — no UI, no state. Kept separate so they can be unit-tested.

const BASE_XP := 100
const COMBO_STEP := 0.1
const COMBO_CAP := 10
const REQUEUE_OFFSET := 4
const REQUEUE_FRACTION := 0.35
const REGEN_EVERY := 4
const CHECKPOINT_VERSION := 2


static func is_correct(chosen: Array, answers: Array) -> bool:
	if chosen.size() != answers.size():
		return false
	var a := chosen.duplicate()
	var b := answers.duplicate()
	a.sort()
	b.sort()
	return a == b


## streak is the streak AFTER the current correct answer (>= 1).
static func multiplier(streak: int) -> float:
	return 1.0 + COMBO_STEP * float(min(max(streak, 1) - 1, COMBO_CAP))


static func xp_for_streak(streak: int) -> int:
	return int(round(BASE_XP * multiplier(streak)))


static func regen_heart(streak: int) -> bool:
	return streak > 0 and streak % REGEN_EVERY == 0


## A checkpoint stores completed answers, while the resume UI describes the
## question that will be shown next. Keeping this conversion in the rules
## module prevents the dialog and restored HUD from drifting by one round.
static func next_round(answered: int) -> int:
	return maxi(answered, 0) + 1


## Distance to reinsert a missed question, scaled to how much queue is left.
## A fixed small offset means a miss in a long queue always comes right back
## in a couple of questions, which reads as "stuck on this one" rather than
## a fair second chance. Scales to REQUEUE_FRACTION of the remaining queue,
## clamped so it never runs past the end and never closer than
## REQUEUE_OFFSET — short queues keep the original snappy feel.
static func requeue_position(queue_size: int) -> int:
	if queue_size <= REQUEUE_OFFSET:
		return queue_size
	return clampi(int(float(queue_size) * REQUEUE_FRACTION), REQUEUE_OFFSET, queue_size)


# ------------------------------------------------------------ run checkpoints

## Snapshot of an in-progress boss battle, persisted by the Game autoload
## under save_data["battles"][boss_id]["in_progress"] so an interrupted run
## (Retreat, Esc, app quit) can later resume exactly where it stopped.
## "queue" holds the remaining question ids in order; "pool" identifies the
## exact sampled run (important for the randomized Gatekeeper); "attempted"
## and "first_try_correct" preserve rematch and accuracy semantics.
static func make_checkpoint(queue_ids: Array, hearts: int, correct: int, answered: int, streak: int, best_streak: int, xp_earned: int, total: int, attempted_ids: Array, first_try_correct: int, pool_ids: Array) -> Dictionary:
	return {
		"version": CHECKPOINT_VERSION,
		"queue": queue_ids.duplicate(),
		"pool": pool_ids.duplicate(),
		"attempted": attempted_ids.duplicate(),
		"first_try_correct": first_try_correct,
		"hearts": hearts,
		"correct": correct,
		"answered": answered,
		"streak": streak,
		"best_streak": best_streak,
		"xp_earned": xp_earned,
		"total": total,
	}


## Numeric checkpoint fields must be ints -- or integral floats, since a
## JSON round-trip (save.json) decodes every number as a float. Anything
## else (strings, bools, fractional floats) means a hand-edited or corrupt
## save and invalidates the whole checkpoint.
static func _checkpoint_int(data: Dictionary, key: String):
	var value = data.get(key)
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	return null


## Returns a normalized copy of a stored checkpoint, or {} when it cannot be
## trusted and should be dropped: wrong types, a queue id missing from the
## current question bank (bank_ids, an id -> true set; the bank changed
## under the save), duplicate ids, no hearts left, or counts that no longer
## add up (correct + remaining != total, answered < correct).
static func validate_checkpoint(data, bank_ids: Dictionary) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var version = _checkpoint_int(data, "version")
	if version != CHECKPOINT_VERSION:
		# Version 1 did not store enough information to restore first-attempt
		# accuracy correctly. Dropping it is safer than publishing a false score.
		return {}
	var queue = data.get("queue")
	if typeof(queue) != TYPE_ARRAY or (queue as Array).is_empty():
		return {}
	var pool = data.get("pool")
	var attempted = data.get("attempted")
	if typeof(pool) != TYPE_ARRAY or (pool as Array).is_empty() \
			or typeof(attempted) != TYPE_ARRAY:
		return {}
	var pool_ids: Array = []
	var pool_set := {}
	for entry in pool:
		if typeof(entry) != TYPE_STRING or not bank_ids.has(entry) or pool_set.has(entry):
			return {}
		pool_set[entry] = true
		pool_ids.append(entry)
	var ids: Array = []
	var seen := {}
	for entry in queue:
		if typeof(entry) != TYPE_STRING or not pool_set.has(entry) or seen.has(entry):
			return {}
		seen[entry] = true
		ids.append(entry)
	var attempted_ids: Array = []
	var attempted_set := {}
	for entry in attempted:
		if typeof(entry) != TYPE_STRING or not pool_set.has(entry) or attempted_set.has(entry):
			return {}
		attempted_set[entry] = true
		attempted_ids.append(entry)
	var hearts = _checkpoint_int(data, "hearts")
	var correct = _checkpoint_int(data, "correct")
	var answered = _checkpoint_int(data, "answered")
	var streak = _checkpoint_int(data, "streak")
	var xp_earned = _checkpoint_int(data, "xp_earned")
	var total = _checkpoint_int(data, "total")
	var first_try_correct = _checkpoint_int(data, "first_try_correct")
	if hearts == null or correct == null or answered == null \
			or streak == null or xp_earned == null or total == null \
			or first_try_correct == null:
		return {}
	if hearts < 1 or streak < 0 or xp_earned < 0 or answered < 0 or answered < correct \
			or first_try_correct < 0 or first_try_correct > correct:
		return {}
	if total <= 0 or correct < 0 or pool_ids.size() != total \
			or correct + ids.size() != total:
		return {}
	if attempted_ids.size() > answered or attempted_ids.size() < correct \
			or first_try_correct > attempted_ids.size():
		return {}
	# best_streak was added after the checkpoint format shipped; an older
	# save without it is still valid, so fall back to the current streak
	# instead of rejecting the run.
	var best_streak = _checkpoint_int(data, "best_streak")
	if best_streak == null:
		best_streak = streak
	if best_streak < streak:
		return {}
	return {
		"version": CHECKPOINT_VERSION,
		"queue": ids,
		"pool": pool_ids,
		"attempted": attempted_ids,
		"first_try_correct": first_try_correct,
		"hearts": hearts,
		"correct": correct,
		"answered": answered,
		"streak": streak,
		"best_streak": best_streak,
		"xp_earned": xp_earned,
		"total": total,
	}
