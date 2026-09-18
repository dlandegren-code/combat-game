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


## Which skill USING this teaches, as a CombatantStats field, or "" for an action that is not
## a skill. Player.gd awards the experience centrally once the action has resolved, so a new
## skill only has to name itself here — see Progression for the roof and the crit rule.
##
## Not every action is a skill. Walking, standing up and picking things off the floor are
## things anyone can do; Firebolt would be, but there is no spell skill on the stat block to
## put its experience into yet.
func trains_skill() -> String:
	return ""


# --- Cursor art -------------------------------------------------------------
# What the mouse wears while this action is armed and hovering something it could act on. The
# whole set lives here rather than one path per ability file, so the pointers can be compared
# to each other at a glance and none of them accidentally doubles up.
#
# Reusing the inventory icons on purpose: the cursor for Ranged and the bow in the bag being
# the same picture is most of what makes the pointer readable without a legend.

const ICONS := "res://assets/UI/icons/ICON_FantasyWarrior_Inventory_"
const CURSOR_SWORD := ICONS + "Swords01_Clean.png"
const CURSOR_BOW := ICONS + "Bows01_Clean.png"
const CURSOR_SPEAR := ICONS + "Spears01_Clean.png"
const CURSOR_AXE := ICONS + "Axes01_Clean.png"
## Unused. Kept named because it is the obvious pick for a spell and somebody will reach for it
## — it reads as a generic sparkle rather than as casting, which is why Firebolt uses the staff.
const CURSOR_MAGIC := ICONS + "Magic01_Clean.png"
const CURSOR_PACK := ICONS + "Backpack01_Clean.png"
const CURSOR_ITEMS := ICONS + "Items01_Clean.png"
const CURSOR_DAGGER := ICONS + "Daggers01_Clean.png"
const CURSOR_SHIELD := ICONS + "Shields01_Clean.png"
const CURSOR_STAFF := ICONS + "Staves01_Clean.png"


## Which pointer to show over `target`, which has ALREADY passed can_target. Return an icon
## path, or one of ActionCursors' non-icon specs (HELP for "would work, but not like this";
## "" for the plain can-act cross).
##
## Takes the target as well as the actor because one action can mean two things depending on
## what it is over — see interact_ability.gd, where the same Open/Close pointer becomes a
## lockpick when the thing under it is locked.
func get_cursor_icon(_actor, _target) -> String:
	return ""


# --- Spell metadata ---------------------------------------------------------
# Overridden by spells so the spell sheet can describe them without knowing any one of them.
# Kept on the base class rather than type-checked at the call site, so adding a second spell
# means writing the spell and nothing else.

## True for anything that belongs on the spell sheet.
func is_spell() -> bool:
	return false


## Mana this costs to cast, on top of the time cost from get_cost().
func get_mana_cost(_actor) -> int:
	return 0


## Icon for the spell sheet; "" for no art.
func get_icon_path() -> String:
	return ""


## One-line explanation shown under the name on the spell sheet.
func get_description(_actor) -> String:
	return ""


## Damage this would deal right now, as text ("7 fire"). Empty when it deals none.
func get_damage_text(_actor) -> String:
	return ""
