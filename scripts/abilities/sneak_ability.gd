extends "res://scripts/abilities/ability.gd"
## Creep, or stop creeping. One action for both, for the same reason Prone is one action: it is
## the same decision seen from either side.
##
## A standing choice rather than a thing you spend a turn on. Turned on, three things are true
## at once:
##
## MOVES ARE HALVED (Combatant.get_move_range). Creeping is slow, and it is the price of the
## other two — without it a sneak would be strictly better than walking and nobody would ever
## walk.
##
## EVERY MOVE IS ROLLED against the ears of anybody in range of hearing it — see
## Combatant.roll_stealth, which rolls once per move, and Enemy.notices_intruders, which is
## where the roll is finally spent.
##
## STOPPING BESIDE COVER HIDES YOU: a pillar, a crate, a cask, a shut door. That is one further
## roll against a goblin that can actually see you, and lying down is worth two points of it.
## See Combatant._update_hiding and Combatant.is_unseen_by.
##
## Self-targeted and FREE, so it neither ends the turn nor costs a tick. Creeping is how you
## walk, not something you stop and do: charging for it would mean paying to decide, and paying
## again to change your mind.
##
## --- What it does not do ---
##
## Nothing for a sneak caught in the open. Crossing bare floor inside the wedge a goblin is
## looking down is being looked straight at, and there is no roll for it — the hiding roll needs
## something to hide BEHIND and a stop to do it in. Where you put yourself is the first half of
## the problem and this ability is the second: off the guard's nose, behind a pillar, and quiet
## when you get there. A SLEEPING guard has no wedge at all and only its ears, which makes the
## noise roll the whole of getting past it. See Enemy.sight_arc_degrees and
## Enemy.notices_intruders.
##
## And nothing in a fight. Once the alarm has gone up there is nobody left to sneak past, so the
## cell greys out rather than pretending — the same way Ranged greys out without a bow.

func _init() -> void:
	display_name = "Sneak"
	target_kind = TargetKind.SELF


func get_cost(_actor) -> int:
	return 0


func can_use(actor) -> bool:
	return actor.is_alive and actor._exploring()


func unavailable_reason(_actor) -> String:
	return "resource"


func get_description(actor) -> String:
	if not actor._exploring():
		return "Nothing left to sneak past — the room already knows you are here."
	if actor.sneaking:
		return "Stop creeping and walk normally. Quicker to the eye, louder to the ear."
	var quiet: int = actor.get_stealth_skill()
	if actor.is_hiding():
		return ("Hidden (%d against their perception). Stop creeping, or take a step, and you "
			+ "are back in the open.") % actor.get_hide_total()
	return ("Creep at half pace: every move is rolled against the ears of anything nearby "
		+ "(stealth %d + 1d5). Stop beside a pillar or a crate to go to ground, and drop "
		+ "prone for a better job of it.") % quiet


func execute(actor, _target) -> void:
	actor.set_sneaking(not actor.sneaking)

## Empty on purpose. Stealth is earned on each sneaking STEP, where the roll actually happens
## (Combatant.roll_stealth) — awarding it here as well would pay twice for the click that
## merely starts sneaking.
func trains_skill() -> String:
	return ""
