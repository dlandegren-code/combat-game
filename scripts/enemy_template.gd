@tool
extends Resource
## One kind of enemy, as data: what it looks like, what it can do, what it carries, what it
## costs out of a quest's enemy budget, and where it is found.
##
## A template is never a body. QuestScene dresses a generic enemy (scenes/enemies/enemy_base.tscn)
## from one at spawn — model, stat block, gear, size, tint — and DungeonGenerator only ever
## reads the numbers at the bottom to decide who is in a dungeon. So a new enemy is a new .tres
## in resources/enemies/ and a line in EnemyRoster.TEMPLATES, and nothing else.
##
## No class_name, deliberately, like the rest of the newer data scripts: a fresh class_name
## needs the editor to have rescanned before anything can name it, and this project has been
## bitten by that. Everything that needs the script preloads it by path.

## Stable key: what the layout records, what the save would record, what the tests ask for.
@export var id: String = ""

## Name shown over its head and in the initiative order. Empty uses the stat block's own name.
@export var display_name: String = ""

## Which AI it fights with: Enemy.EnemyType (0 melee, 1 archer, 2 boss). The boss AI is also
## what keeps it to the throne between fights.
@export var ai: int = 0

## The body. One of the Kenney character models the heroes and the old goblins already use,
## because those carry the animation clips the game plays (idle, walk, die, attack-melee-right,
## holding-both-shoot ...). The PolygonDungeon characters do not, yet.
@export var model_scene: PackedScene

## Properties set on the instanced model before it enters the tree — CharacterSkin's switches,
## such as show_quiver or robe_color.
@export var model_props: Dictionary = {}

## Its CombatantStats. Shared between every enemy made from this template, which is safe because
## an enemy copies the block into its own fields at _ready and never writes back to it.
@export var stats: Resource

## What it carries, up to four items, in the order the inventory should try to equip them.
## A boss MUST carry the iron key: the boss room's chest is locked to it.
@export var gear: Array[Resource] = []

## Size on top of what its AI's body type already gets (Enemy._apply_enemy_visual).
@export var size: float = 1.0

## Multiplied into the model's colours. White leaves it as it is.
@export var tint: Color = Color(1, 1, 1, 1)

@export var voice: String = "male_d"

# --- What the generator reads ----------------------------------------------

## Points out of QuestDef.enemy_budget. A plain goblin is 2 — the unit the budget was written in.
@export var cost: int = 2

## The quest themes it turns up in (QuestDef.THEMES ids).
@export var themes: PackedStringArray = PackedStringArray()

## The lowest tier it can appear at. A brute in a tier-1 job is a party wipe.
@export var min_tier: int = 1

## How often it is picked against the others that fit, relative to them.
@export var weight: float = 1.0

## Whether it can be the dungeon's boss — in the boss room, on the throne, with the key.
@export var is_boss: bool = false


func fits(theme: String, tier: int) -> bool:
	return themes.has(theme) and tier >= min_tier
