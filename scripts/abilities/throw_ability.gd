extends "res://scripts/abilities/ability.gd"
## Throw the equipped weapon at a target (see Combatant._do_throw_attack).

func _init() -> void:
	display_name = "Throw"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.throw_cost

func get_range(actor) -> int:
	return actor.get_throw_range()

func can_use(actor) -> bool:
	return actor._has_usable_weapon()

func can_target(actor, target) -> bool:
	if target == null or not actor._has_usable_weapon():
		return false
	var dist: float = abs(target.position.x - actor.position.x) + abs(target.position.z - actor.position.z)
	return dist <= get_range(actor) * actor.GRID_SIZE and actor._has_line_of_sight(target)

func unavailable_reason(actor) -> String:
	return "resource" if not actor._has_usable_weapon() else "range"

func execute(actor, target) -> void:
	actor._play_attack_anim("attack-melee-right")
	actor._do_throw_attack(target)
