extends "res://scripts/abilities/ability.gd"
## Adjacent trip: knock the target prone (see Combatant._try_trip).

func _init() -> void:
	display_name = "Trip"
	target_kind = TargetKind.ENEMY

func get_cost(actor) -> int:
	return actor.trip_cost

func can_target(actor, target) -> bool:
	if target == null:
		return false
	var dist: float = abs(target.position.x - actor.position.x) + abs(target.position.z - actor.position.z)
	return dist <= actor.GRID_SIZE * 1.5

func execute(actor, target) -> void:
	actor._play_attack_anim("attack-kick-right")
	actor._try_trip(target)
