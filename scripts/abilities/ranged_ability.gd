extends "res://scripts/abilities/ability.gd"
## Ranged attack: consumes ammo, needs line of sight (see Combatant._do_ranged_attack).

func _init() -> void:
	display_name = "Ranged"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.ranged_cost

func get_range(actor) -> int:
	return actor.get_ranged_range()

func can_use(actor) -> bool:
	return actor.ammo > 0

func can_target(actor, target) -> bool:
	if target == null or actor.ammo <= 0:
		return false
	var dist: float = abs(target.position.x - actor.position.x) + abs(target.position.z - actor.position.z)
	return dist <= get_range(actor) * actor.GRID_SIZE and actor._has_line_of_sight(target)

func unavailable_reason(actor) -> String:
	return "resource" if actor.ammo <= 0 else "range"

func execute(actor, target) -> void:
	actor._play_attack_anim("holding-both-shoot")
	actor._do_ranged_attack(target)
