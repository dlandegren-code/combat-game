extends "res://scripts/abilities/ability.gd"
## Creep, or stop creeping. One action for both, for the same reason Prone is one action: it is
## the same decision seen from either side.
##
## A standing choice rather than a thing you spend a turn on. Turned on, every move this
## character makes is rolled against the ears of anybody in range of hearing it — see
## Combatant.roll_stealth, which rolls once per move, and Enemy.notices_intruders, which is
## where the roll is finally spent.
##
## Self-targeted and FREE, so it neither ends the turn nor costs a tick. Creeping is how you
## walk, not something you stop and do: charging for it would mean paying to decide, and paying
## again to change your mind.
##
## --- What it does not do ---
##
## Nothing about being SEEN. Stealth here is exactly one thing, noise, and a hero who creeps
## into a goblin's line of sight is looked straight at. Hiding from eyes wants cover and facing
## to mean something first — the sight test casts in every direction today (see
## Enemy._idle_look_around), so there is no such thing as being behind a guard yet.
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
	return ("Creep: every move is rolled against the ears of anything nearby (stealth %d + 1d5 "
		+ "against its perception). Does nothing about being seen.") % actor.get_stealth_skill()


func execute(actor, _target) -> void:
	actor.set_sneaking(not actor.sneaking)
