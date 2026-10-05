extends RefCounted
class_name D20
## The game's one die, and the rules for reading it.
##
## ROLL UNDER. Every skill is a number on the d20 scale and a check succeeds when the die comes
## up at or below it, so a skill IS its chance: 15 succeeds on 1-15, which is 75%. A modifier is
## the same unit — +1 is five percentage points — which is why every bonus and penalty in the
## game is a small whole number added to or taken off the skill before the die is read.
##
## Two faces are special:
##   1  — a CRITICAL success. Succeeds whatever the skill (so even a hopeless shot has a 5%
##        chance), and beats any ordinary success in a contest.
##   20 — a FUMBLE. Fails whatever the skill, so nothing is ever certain.
## Both count as decisive for experience (see Progression): the outcomes you learn from are
## the ones that went unusually well or unusually badly.
##
## CONTESTS. When two people are pitted against each other — a blade against a parry, a sneak
## against a listener — both roll against their own skill. A success beats a failure; when
## both succeed, the HIGHER roll wins, because it was the closer-run thing done well. Ties go
## to the defender: the active side has to actually beat the other one.
##
## Preloaded rather than reached through the class_name, for the same reason the rest of the
## project preloads its scripts — the global class cache is unreliable for a fresh script.

const SIDES := 20
const CRIT := 1
const FUMBLE := 20


static func roll() -> int:
	return randi_range(1, SIDES)


static func succeeds(die: int, skill: int) -> bool:
	if die == FUMBLE:
		return false
	return die == CRIT or die <= skill


static func is_decisive(die: int) -> bool:
	## A natural 1 or a natural 20. Success and failure both count: the point is that the
	## outcome was decisive, not that it was good.
	return die == CRIT or die == FUMBLE


static func active_wins(active_die: int, active_skill: int, passive_die: int,
		passive_skill: int) -> bool:
	## The contest rule — see the header. `active` is the side that has to make something
	## happen (the attacker, the listener); `passive` keeps the tie.
	if not succeeds(active_die, active_skill):
		return false
	if not succeeds(passive_die, passive_skill):
		return true
	if active_die == CRIT or passive_die == CRIT:
		return active_die == CRIT and passive_die != CRIT
	return active_die > passive_die


static func chance(skill: int) -> int:
	## Percent chance a plain check against this skill succeeds, crit and fumble included —
	## so it never reads 0% or 100%. For the screens: a player should see 75%, not "15".
	return clampi(skill, 1, SIDES - 1) * 100 / SIDES
