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
