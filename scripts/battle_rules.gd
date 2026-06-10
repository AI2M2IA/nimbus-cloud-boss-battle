extends RefCounted
## Pure battle rules — no UI, no state. Kept separate so they can be unit-tested.

const BASE_XP := 100
const COMBO_STEP := 0.1
const COMBO_CAP := 10
const REQUEUE_OFFSET := 4
const REGEN_EVERY := 4


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


static func requeue_position(queue_size: int) -> int:
	return min(REQUEUE_OFFSET, queue_size)
