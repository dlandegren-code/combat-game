extends Resource
class_name CombatantStats
## Data-driven stat block for a combatant. Assign one to a Combatant's `stats`
## property to define a new combatant type (enemy or hero) with no code.
## When assigned, these values are copied onto the combatant at _ready,
## overriding any per-instance @export values set in the scene.
##
## Defaults match the base Hero so a blank resource is a sensible starting point.
##
## SCALES. Every skill is a d20 roll-under number — 13 succeeds on 1-13, a 65% chance — and
## contests are won by succeeding higher than the other side (see D20). Attributes are on the
## human 3-18 scale with 10 as average; monsters may go past 18. Trained skills top out at
## Progression.SKILL_CAP.

@export var character_name: String = "Hero"
@export var initiative: int = 10

@export_group("Vitals")
## No max_hp or dodge_skill: both are derived from attributes (stamina and agility) by
## Combatant._derive_stats() and get_dodge_skill(). Set stamina / agility instead.
@export var attack_dmg: int = 4

@export_group("Movement")
@export var move_speed: float = 6.0     ## world units/sec while sliding to target
@export var move_range: int = 5         ## max tiles per move action
@export var move_cost_per_tile: int = 1

@export_group("Melee")
@export var attack_skill: int = 13
@export var attack_cost: int = 2
@export var shove_skill: int = 13
@export var shove_cost: int = 2
@export var trip_skill: int = 11
@export var trip_cost: int = 2
@export var dual_wield_skill: bool = false  ## trained off-hand: no OFFHAND_HIT_PENALTY on the free off-hand attack

@export_group("Defense")
@export var armor: int = 0
@export var physical_resistance: int = 0  ## percentage 0-100
@export var parry_skill: int = 11
## Ids are load-bearing and append-only — see Stance. Protection additionally needs can_guard.
@export_enum("Parry", "Dodge", "Protection") var defensive_option: int = 0

## No ranged_range / throw_range here: reach is a property of the weapon, not the wielder.
## See ItemResource.ranged_range / throw_range and Combatant.get_ranged_range().
@export_group("Ranged")
@export var ranged_skill: int = 9
@export var ranged_cost: int = 3
@export var ammo: int = 0
@export var max_ammo: int = 0

@export_group("Stealth")
## Crossing a room without being heard. Rolled on the d20 on each move made while sneaking, as
## the defending side of a contest with the perception of anybody in earshot. It is rolled a second way for HIDING, when a sneak stops beside something
## and a goblin has a clear look at it. See Combatant.roll_stealth, Combatant.get_hide_skill and
## Enemy.notices_intruders.
@export var stealth_skill: int = 9
## Hearing somebody sneaking past, and spotting somebody hidden. The ACTIVE side of the contest:
## a listener has to succeed and roll higher than the sneak to notice them. Each listener rolls
## once per sneaking move (Combatant._listener_die), so a keen-eared goblin catches what a dull
## one misses without anybody re-rolling the same footstep every pulse.
@export var perception_skill: int = 10

@export_group("Throw")
@export var throw_skill: int = 9
@export var throw_cost: int = 1     ## a throw is one quick action (see Combatant.throw_cost)

@export_group("Interaction")
## Doors, chests and levers. Both of these were Combatant exports with no home in a stat
## block, which was harmless while a character only ever existed inside one scene — but a
## character that travels is rebuilt from this block, and anything missing from it silently
## reverts to the default. The authored archer's lockpicking went from 3 to 0 that way.
@export var interact_cost: int = 1
@export var lockpick_skill: int = 0

@export_group("Spellcasting")
## Off by default: only a character marked a caster gets a mana pool or any spell power, even
## though every character has willpower. See Combatant.can_cast.
@export var can_cast: bool = false
@export var spell_cost: int = 3     ## time units per cast; mana cost is per-spell

## Whether this combatant may take the Protection stance. Off by default for the same reason
## can_cast is — see Combatant.can_guard.
@export var can_guard: bool = false

## What each attribute drives is documented on Combatant's Attributes group; intelligence and
## charisma currently drive nothing.
@export_group("Attributes")
@export var strength: int = 10
@export var agility: int = 10
@export var stamina: int = 10
@export var intelligence: int = 10
@export var willpower: int = 10
@export var charisma: int = 10
@export var weight: int = 2
@export var equip_cost: int = 1
