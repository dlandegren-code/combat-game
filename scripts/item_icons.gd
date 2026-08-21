extends RefCounted
class_name ItemIcons
## Picks the inventory icon for an item, from the Fantasy Warrior HUD Icons_Inventory set.
##
## Resolution order:
##   1. ItemResource.icon_path, if the item names its own art.
##   2. A keyword in the item's name (cleaver -> axe, staff -> staff, ...).
##   3. The item's type (SHIELD -> shield, ARMOR -> armour, CONSUMABLE -> potion, ...).
##
## Deriving from name and type rather than requiring an icon on every .tres is what lets the
## eighteen existing items light up without being touched — the same approach
## Combatant._refresh_socket already uses to pick a 3D weapon model. Set `icon_path` on an
## item when you want to override the guess.

const DIR := "res://assets/UI/icons/ICON_FantasyWarrior_Inventory_"

const SWORD := DIR + "Swords01_Clean.png"
const DAGGER := DIR + "Daggers01_Clean.png"
const AXE := DIR + "Axes01_Clean.png"
const HAMMER := DIR + "Hammers01_Clean.png"
const MACE := DIR + "Maces01_Clean.png"
const SPEAR := DIR + "Spears01_Clean.png"
const BOW := DIR + "Bows01_Clean.png"
const ARROWS := DIR + "Arrows01_Clean.png"
const QUIVER := DIR + "Arrows02_Clean.png"
const STAFF := DIR + "Staves01_Clean.png"
const MAGIC := DIR + "Magic01_Clean.png"
const SHIELD := DIR + "Shields01_Clean.png"
const ARMOR := DIR + "Armor01_Clean.png"
const HELMET := DIR + "Helmets01_Clean.png"
const POTION := DIR + "Potions01_Clean.png"
const HEALING := DIR + "Healing01_Clean.png"
const GENERIC := DIR + "Items01_Clean.png"
const BACKPACK := DIR + "Backpack01_Clean.png"

## Checked in order, so put the specific words before the general ones — "short bow" must
## reach BOW before anything matches on "bow" inside another word.
const BY_KEYWORD: Array[Array] = [
	["cleaver", AXE], ["axe", AXE],
	["hammer", HAMMER], ["mace", MACE], ["club", MACE],
	["spear", SPEAR], ["lance", SPEAR],
	["bow", BOW],
	["arrow", ARROWS], ["quiver", QUIVER],
	["staff", STAFF], ["wand", MAGIC], ["scroll", MAGIC], ["orb", MAGIC],
	["dagger", DAGGER], ["knife", DAGGER],
	["sword", SWORD], ["blade", SWORD],
	["shield", SHIELD],
	["helm", HELMET], ["cap", HELMET], ["hood", HELMET],
	["greave", ARMOR], ["legging", ARMOR], ["boot", ARMOR],
	["armor", ARMOR], ["armour", ARMOR], ["mail", ARMOR], ["plate", ARMOR],
	["potion", POTION], ["elixir", POTION], ["flask", POTION],
	["bandage", HEALING], ["salve", HEALING],
]


static func for_item(item: ItemResource) -> String:
	if item == null:
		return ""
	if item.icon_path != "":
		return item.icon_path
	var lower := item.item_name.to_lower()
	for pair in BY_KEYWORD:
		if lower.find(pair[0]) >= 0:
			return pair[1]
	return _by_type(item.item_type)


static func _by_type(item_type: int) -> String:
	match item_type:
		ItemResource.ItemType.WEAPON, ItemResource.ItemType.THROWABLE:
			return SWORD
		ItemResource.ItemType.SHIELD:
			return SHIELD
		ItemResource.ItemType.ARMOR, ItemResource.ItemType.LEGS:
			return ARMOR
		ItemResource.ItemType.HELMET:
			return HELMET
		ItemResource.ItemType.CONSUMABLE:
			return POTION
		ItemResource.ItemType.AMMO:
			return ARROWS
	return GENERIC


static func for_empty_slot(slot: int) -> String:
	## Ghost icon shown greyed-out in an empty equipment socket, so the doll reads as "helmet
	## goes here" rather than as an unexplained hole.
	match slot:
		ItemResource.EquipSlot.HELMET:
			return HELMET
		ItemResource.EquipSlot.ARMOR:
			return ARMOR
		ItemResource.EquipSlot.LEGS:
			return ARMOR
		ItemResource.EquipSlot.RIGHT_HAND:
			return SWORD
		ItemResource.EquipSlot.LEFT_HAND:
			return SHIELD
	return GENERIC
