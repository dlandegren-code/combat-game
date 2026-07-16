extends "res://scripts/abilities/ability.gd"
## Basic adjacent melee attack.

func _init() -> void:
	display_name = "Attack"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.attack_cost

func can_target(actor, target) -> bool:
	return target != null and actor._is_adjacent(target.position)

func execute(actor, target) -> void:
	actor._play_attack_anim("attack-melee-right")
	target.take_damage(actor.get_attack_damage(), actor.get_attack_skill(), false)
