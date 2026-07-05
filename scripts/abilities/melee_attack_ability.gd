extends "res://scripts/abilities/ability.gd"
## Basic adjacent melee attack.

func _init() -> void:
	display_name = "Attack"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.attack_cost

func can_target(actor, target) -> bool:
	if target == null:
		return false
	var dist: float = abs(target.position.x - actor.position.x) + abs(target.position.z - actor.position.z)
	return dist <= actor.GRID_SIZE * 1.5

func execute(actor, target) -> void:
	actor._play_attack_anim("attack-melee-right")
	target.take_damage(actor.get_attack_damage(), actor.get_attack_skill(), false)
