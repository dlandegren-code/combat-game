extends "res://scripts/abilities/ability.gd"
## Pick up / use nearby ground items (see Combatant._do_pickup). No target.

func _init() -> void:
	display_name = "Pick Up"
	target_kind = TargetKind.SELF

func get_cost(_actor) -> int:
	return 1

func can_target(_actor, _target) -> bool:
	return true

func execute(actor, _target) -> void:
	actor._play_attack_anim("pick-up")
	actor._do_pickup()
