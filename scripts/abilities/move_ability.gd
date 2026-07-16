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
	# Reachable = there is a routed path (around walls / enemies, through allies) of at
	# most move_range tiles, ending on an unoccupied cell. The path check subsumes range.
	if not actor._can_move():
		return false
	if actor._is_tile_occupied_by_others(target, actor):
		return false
	var path: Array = actor._find_path(actor._snap_to_grid(actor.position), target, actor.move_range)
	return path.size() > 1

func execute(actor, target) -> void:
	actor._start_path_move(target)
