extends Resource
class_name CombatantStats
## Data-driven stat block for a combatant. Assign one to a Combatant's `stats`
## property to define a new combatant type (enemy or hero) with no code.
## When assigned, these values are copied onto the combatant at _ready,
## overriding any per-instance @export values set in the scene.
##
## Defaults match the base Hero so a blank resource is a sensible starting point.

@export var character_name: String = "Hero"
@export var initiative: int = 10

@export_group("Vitals")
@export var max_hp: int = 20
@export var attack_dmg: int = 4

@export_group("Movement")
@export var move_speed: float = 6.0     ## world units/sec while sliding to target
@export var move_range: int = 5         ## max tiles per move action
@export var move_cost_per_tile: int = 1

@export_group("Melee")
@export var attack_skill: int = 5
@export var attack_cost: int = 2
@export var shove_skill: int = 5
@export var shove_cost: int = 2
@export var trip_skill: int = 4
@export var trip_cost: int = 2

@export_group("Defense")
@export var armor: int = 0
@export var physical_resistance: int = 0  ## percentage 0-100
@export var parry_skill: int = 4
@export var dodge_skill: int = 5
@export_enum("Parry", "Dodge") var defensive_option: int = 0

@export_group("Ranged")
@export var ranged_skill: int = 3
@export var ranged_cost: int = 3
@export var ranged_range: int = 15
@export var ammo: int = 0
@export var max_ammo: int = 0

@export_group("Throw")
@export var throw_skill: int = 3
@export var throw_cost: int = 3
@export var throw_range: int = 5

@export_group("Physical")
@export var strength: int = 3
@export var weight: int = 2
@export var equip_cost: int = 1
