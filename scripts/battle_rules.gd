extends RefCounted
## Pure battle rules — no UI, no state. Kept separate so they can be unit-tested.

const BASE_XP := 100
const COMBO_STEP := 0.1
const COMBO_CAP := 10
const REQUEUE_OFFSET := 4
const REQUEUE_FRACTION := 0.35
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
