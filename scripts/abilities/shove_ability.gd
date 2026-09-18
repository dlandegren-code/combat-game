extends "res://scripts/abilities/ability.gd"
## Adjacent shove: knock the target back (see Combatant._try_shove).

func _init() -> void:
	display_name = "Shove"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.shove_cost

func can_target(actor, target) -> bool:
	return target != null and actor._is_adjacent(target.position)

func execute(actor, target) -> void:
	actor._play_attack_anim("attack-kick-right")
	actor._try_shove(target)


func get_cursor_icon(_actor, _target) -> String:
	## A shield, as in bracing behind one and putting your shoulder in. The loosest fit in the
	## set along with Trip's — swap it the moment there is art that actually means "shove".
	return CURSOR_SHIELD

func trains_skill() -> String:
	return "shove_skill"
