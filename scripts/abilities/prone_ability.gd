extends "res://scripts/abilities/ability.gd"
## Lie down, or get back up. One action for both, because they are the same decision seen from
## either side and a bar with "Stand Up" greyed out next to "Lie Down" tells the player nothing
## the character's pose does not already.
##
## Self-targeted: there is nothing to aim at, so Player.select_action runs it the moment the
## slot is clicked rather than arming it and waiting for a click on the world.
##
## --- What it costs ---
##
## Going down is FREE and does not end the turn. Dropping flat is not something you have to
## find time for, and charging for it would make "lie down, then shoot from cover" cost two
## turns instead of one.
##
## Getting up costs a tick and ends the turn, which is the whole balance of the thing: lying
## down shelters you from archers (see Combatant.PRONE_TARGET_PENALTY) and wrecks you in melee,
## and the price of changing your mind is a turn.
##
## Out of combat it does a third thing: a sneak who has gone to ground beside cover hides
## better lying down than crouching (Combatant.HIDE_PRONE_BONUS). Free there too, and it wants
## to be — the whole move is stop, drop, and let the patrol go past.
##
## And out of combat only, moving gets you up by itself (Combatant._start_path_move), so that
## loop is one click per stop rather than two. The price of changing your mind is a turn in a
## fight and nothing at all in a corridor, which is the same rule the tick system draws
## everywhere else.

func _init() -> void:
	display_name = "Prone"
	target_kind = TargetKind.SELF


func get_cost(actor) -> int:
	## Zero going down, and zero is meaningful here rather than rounded up to the usual floor —
	## see Player._use_self_ability, which leaves the turn running when an action is free.
	return actor.STAND_UP_COST if actor.is_prone else 0


func can_use(actor) -> bool:
	return actor.is_alive


func get_description(actor) -> String:
	if actor.is_prone:
		return "Get back on your feet. Costs a tick and ends the turn."
	if actor.sneaking:
		return ("Drop flat: worth %d to a hiding place, and a hard target for archers. Free, "
			+ "and moving gets you back up.") % actor.HIDE_PRONE_BONUS
	return "Drop flat: a hard target for archers, an easy one for anybody in reach. Free."


func execute(actor, _target) -> void:
	actor.toggle_prone()
