extends Resource
class_name Ability
## Base class for a combatant action/skill. Subclass it, override the pieces you
## need, and add an instance to a Combatant's `abilities` list to make it usable
## by the action bar (players) or the AI (enemies).
##
## Instances are stateless -- they read the actor's state at call time -- so a
## single instance can be shared across combatants. To add a new skill: make a
## new script extending this, override execute() (and can_target/get_range as
## needed), and append it to the combatant's abilities.

enum TargetKind { SELF, TILE, ENEMY }

@export var display_name: String = "Ability"
@export var target_kind: int = TargetKind.ENEMY

func targets_enemy() -> bool: return target_kind == TargetKind.ENEMY
func targets_tile() -> bool: return target_kind == TargetKind.TILE
func targets_self() -> bool: return target_kind == TargetKind.SELF

## Time-unit cost of using this ability (usually read from the actor's stats).
func get_cost(_actor) -> int:
	return 1

## Max targeting range in tiles.
func get_range(_actor) -> int:
	return 1

## Does the actor have the resources to use this at all right now (ammo, weapon)?
func can_use(_actor) -> bool:
	return true

## Can the actor act on `target` right now? `target` is a Node (ENEMY),
## a Vector3 tile (TILE), or null (SELF).
func can_target(_actor, _target) -> bool:
	return false

## Cursor-feedback hint when can_target() is false:
## "resource" = lacking ammo/weapon (help cursor), "range" = out of range /
## no line of sight (forbidden cursor).
func unavailable_reason(_actor) -> String:
	return "range"

## Perform the ability. May await (animations). `target` matches target_kind.
func execute(_actor, _target) -> void:
	pass
