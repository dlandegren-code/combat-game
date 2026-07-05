extends "res://scripts/abilities/ability.gd"
## Move to a grid tile within move range.

func _init() -> void:
	display_name = "Move"
	target_kind = TargetKind.TILE

func get_cost(actor) -> int:
	return actor.move_cost_per_tile

func get_range(actor) -> int:
	return actor.move_range

func can_target(actor, target) -> bool:
	return actor._can_move() and actor._is_in_range(target) \
		and not actor._is_tile_occupied_by_others(target, actor)

func execute(actor, target) -> void:
	actor.target_position = target
	actor.is_moving = true
