extends "res://scripts/abilities/ability.gd"
## Pick up / use the ground item on the clicked tile (see Player._do_pickup).

func _init() -> void:
	display_name = "Pick Up"
	target_kind = TargetKind.TILE

func get_cost(_actor) -> int:
	return 1

func get_range(actor) -> int:
	return actor.PICKUP_REACH_TILES

func can_target(actor, target) -> bool:
	# Valid only when there's a reachable ground item on/near the clicked tile.
	return actor._pickup_at(target) != null

func unavailable_reason(_actor) -> String:
	return "range"

func execute(actor, target) -> void:
	actor._play_attack_anim("pick-up")
	actor._do_pickup(target)
