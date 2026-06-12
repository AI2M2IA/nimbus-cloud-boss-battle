extends RefCounted
## Pure rules for the extra game modes (Survival, Points Decay, Save the Pet).
## No UI, no state — mirrors battle_rules.gd so everything is unit-testable.
##
## Constants (tuning knobs, documented here so tests and README stay honest):
## - Survival ends after exactly SURVIVAL_MAX_WRONG wrong answers.
## - Points Decay starts at DECAY_START_POINTS; a wrong answer subtracts
##   DECAY_WRONG_PENALTY, a correct one adds DECAY_CORRECT_REWARD; the pool
##   is clamped at 0 and the run ends when it reaches 0.
## - Save the Pet is won at PET_GOAL_CORRECT correct answers and lost at
##   PET_MAX_WRONG wrong answers; a loss takes precedence over a win.

const SURVIVAL_MAX_WRONG := 3

const DECAY_START_POINTS := 1000
const DECAY_WRONG_PENALTY := 100
const DECAY_CORRECT_REWARD := 50

const PET_MAX_WRONG := 3
const PET_GOAL_CORRECT := 20
const PETS := ["cat", "dog", "parrot", "fish", "hamster"]


## Survival: the run is over once `wrong` reaches SURVIVAL_MAX_WRONG.
static func survival_is_over(wrong: int) -> bool:
	return wrong >= SURVIVAL_MAX_WRONG


## Points Decay: returns the new points pool after one answer.
## Never goes below 0.
static func decay_points(points: int, correct: bool) -> int:
	var next := points + (DECAY_CORRECT_REWARD if correct else -DECAY_WRONG_PENALTY)
	return max(next, 0)


## Points Decay: the run is over once the pool is empty.
static func decay_is_over(points: int) -> bool:
	return points <= 0


## Save the Pet: "saved", "lost", or "ongoing" given the counters so far.
## A loss (3 wrong) takes precedence if both thresholds were somehow hit.
static func pet_outcome(correct: int, wrong: int) -> String:
	if wrong >= PET_MAX_WRONG:
		return "lost"
	if correct >= PET_GOAL_CORRECT:
		return "saved"
	return "ongoing"


static func is_valid_pet(pet: String) -> bool:
	return PETS.has(pet)
