extends "res://scripts/abilities/ability.gd"
## Move to a grid tile within move range.

func _init() -> void:
	display_name = "Move"
	target_kind = TargetKind.TILE

func get_cost(actor) -> int:
	## Cheapest a move can be. The real price depends on how far the route turns out to be,
	## which isn't known until execute() has pathed — see execute / Combatant.get_move_cost.
	return actor.get_move_cost(1)

func get_range(actor) -> int:
	return actor.get_move_range()

func can_target(actor, target) -> bool:
	# Reachable = there is a routed path (around walls / enemies, through allies) of at
	# most get_move_range() tiles, ending on an unoccupied cell. The path check subsumes range.
	# get_move_range() rather than move_range so a guardian's planted feet shrink the
	# reachable set as well as the indicator.
	if not actor._can_move():
		return false
	if actor._is_tile_occupied_by_others(target, actor):
		return false
	var path: Array = actor._find_path(actor._snap_to_grid(actor.position), target, actor.get_move_range())
	return path.size() > 1

func execute(actor, target) -> void:
	actor._start_path_move(target)
	# Reprice now that the route length is known: _begin_action could only book the
	# minimum, since the path hadn't been walked yet.
	actor._pending_cost = actor.get_move_cost()


func get_cursor_icon(_actor, _target) -> String:
	## Nothing: movement keeps the pointing hand and the floor indicator. See
	## ActionCursors.move.
	return ""
