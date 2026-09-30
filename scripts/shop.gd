extends Control
## A market stall: gold in, gear out, and the other way round.
##
## ONE screen for all three of the town's shops. Which one the player walked into is
## `opening_shop`, set by Town on the way in, and all it changes is the sign over the door and
## what is on the shelf. A shop is not different enough from another shop to be its own scene.
##
## Prices are the item's own business (ItemResource.gold_value / sell_value, derived from what
## the thing actually does), and the gap between the two is what stops a dungeon full of
## goblin daggers from being an income. What is FOR SALE is here, because that is a property
## of this town rather than of the items.

const ScreenPanelScript := preload("res://scripts/ui_kit.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## Everything the town can sell, between the three of them. A fixed list, and an honest one:
## everything here is already in resources/items, so nothing had to be invented to fill a
## shelf.
##
## Phase 4 can rotate this — a quest board that generates dungeons ought to have a market that
## restocks — but a fixed shop is not a placeholder. Knowing that the armourer always has
## greaves is what lets a player save up for them.
const STOCK := [
	"res://resources/items/health_potion.tres",
	"res://resources/items/bottle_of_water.tres",
	"res://resources/items/bottle_of_beer.tres",
	"res://resources/items/bottle_of_wine.tres",
	"res://resources/items/arrow_bundle.tres",
	"res://resources/items/quiver.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/wooden_shield.tres",
	"res://resources/items/leather_armor.tres",
	"res://resources/items/reinforced_leather_armor.tres",
	"res://resources/items/leather_greaves.tres",
	"res://resources/items/knight_helmet.tres",
	"res://resources/items/short_bow.tres",
	"res://resources/items/longbow.tres",
	"res://resources/items/warhammer.tres",
	"res://resources/items/heavy_armor.tres",
]

## Who sells what, by the item's own type. Keyed by the service id in TownLayout.SERVICES, so
## the building the player clicked and the shelf they are shown cannot drift apart.
##
## The general store's list is EMPTY, and that is the point: it means "whatever the other two
## do not take" rather than a third hand-written list. Add a new kind of item and it appears
## on somebody's shelf without this table being touched — which is the only version of
## "everything else" that stays true.
const SHOPS := {
	"armorer": {
		"title": "The Armourer",
		"types": [ItemResource.ItemType.SHIELD, ItemResource.ItemType.ARMOR,
			ItemResource.ItemType.HELMET, ItemResource.ItemType.LEGS],
		"empty": "The forge is cold today.",
	},
	"weaponsmith": {
		"title": "The Weapon Shop",
		"types": [ItemResource.ItemType.WEAPON, ItemResource.ItemType.THROWABLE,
			ItemResource.ItemType.AMMO],
		"empty": "Nothing on the rack today.",
	},
	"general": {
		"title": "The General Store",
		"types": [],
		"empty": "The shelves are bare today.",
	},
}

const DEFAULT_SHOP := "general"

## Which stall the player walked into. Set by Town before it changes scene.
##
## A static rather than a GameState field, for the same reason PartySheet.opening_tab is one:
## which door was opened is a property of this trip to this screen, not of the game, and it
## has no business being saved or reset by GameState.clear().
static var opening_shop: String = DEFAULT_SHOP

## Title, flourish, party picker, purse line, separators and the way out — everything on this
## screen that is not one of the two lists, INCLUDING the panel's own padding. Taken off the
## window height to size them, so this has to move whenever that padding does.
const HEADER_AND_FOOTER := 346.0

var _who: int = 0
var _shop: String = DEFAULT_SHOP


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop = opening_shop if SHOPS.has(opening_shop) else DEFAULT_SHOP
	_build()


func _build() -> void:
	## Two boxes side by side: the shelf on the left, the character's pack on the right.
	##
	## Stacked, this screen meant scrolling past thirteen things on the shelf to reach your own
	## kit — and buying and selling are the same decision looked at from two sides, so the two
	## lists want to be readable against each other. The header and the way out span both; each
	## list scrolls on its own.
	var column := ScreenPanelScript.mount_wide(self)
	ScreenPanelScript.title(column, String(SHOPS[_shop]["title"]))

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody here to buy anything.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	_who = clampi(_who, 0, GameState.party.size() - 1)
	var member = GameState.party[_who]

	if GameState.party.size() > 1:
		var picker := ScreenPanelScript.row(column)
		for i in range(GameState.party.size()):
			ScreenPanelScript.pill(picker, GameState.party[i].character_name,
				_on_pick.bind(i), i != _who)

	ScreenPanelScript.label(column, "%d gold   ·   buying for %s, who has %d of %d pack slots free" % [
		GameState.gold, member.character_name, _free_slots(member), _bag_size(member),
	], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	var halves: Array = ScreenPanelScript.split(column, _list_height())
	_add_stock(halves[0], member)
	_add_pack(halves[1], member)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)


func _list_height() -> float:
	## How tall the two boxes are: what the window has left after the title, the picker, the
	## purse line and the way out. Measured rather than fixed, so the market fills a tall
	## window instead of leaving a band of empty panel under it.
	var available: float = size.y
	if available <= 0.0:
		available = get_viewport().get_visible_rect().size.y
	return clampf(available - HEADER_AND_FOOTER, 180.0, 620.0)


func _add_stock(column: Node, member) -> void:
	## The shelf: one framed row per item, with the item's OWN icon in it.
	##
	## The same ItemSlot the dungeon's backpack is built from (see UiKit.item_row), so a potion
	## on the shelf is the same picture as the potion in the bag it ends up in. A shop that
	## lists gear by name is a spreadsheet, and by the time a player reaches the market they
	## have already learned what these things look like.
	ScreenPanelScript.heading(column, "For sale")
	var shelf := stock_for(_shop)
	if shelf.is_empty():
		ScreenPanelScript.label(column, String(SHOPS[_shop]["empty"]),
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
		return
	for path in shelf:
		var template = load(path)
		if template == null:
			continue
		var price: int = template.gold_value()
		var affordable: bool = GameState.gold >= price and member.bag_has_room()
		ScreenPanelScript.item_row(column, template, _describe(template), "%d g" % price, [
			{"label": "Buy", "handler": _on_buy.bind(path), "enabled": affordable,
				"width": 76.0},
		])


func _add_pack(column: Node, member) -> void:
	ScreenPanelScript.heading(column, "%s carries" % member.character_name)
	var anything := false
	for idx in range(member.bag.size()):
		var item = member.bag[idx]
		if item == null:
			continue
		anything = true
		var note: String = _describe(item)
		if member.is_equipped(idx):
			# Said in words rather than shown by greying the row out: selling what you are
			# wearing is allowed (it comes off on the way out), and a disabled-looking row
			# would suggest otherwise.
			note += "  ·  in use"
		ScreenPanelScript.item_row(column, item, note, "%d g" % item.sell_value(), [
			{"label": "Sell", "handler": _on_sell.bind(idx), "width": 84.0},
		])
	if not anything:
		ScreenPanelScript.label(column, "    Empty.", ScreenPanelScript.BODY_SIZE,
			ScreenPanelScript.MUTED)


static func stock_for(shop_id: String) -> Array:
	## What this stall has on its shelf, out of everything the town sells.
	##
	## Static so the round-trip test can ask the question without standing a screen up, and so
	## that "what does the armourer sell" has one answer rather than one per caller.
	var spec: Dictionary = SHOPS.get(shop_id, SHOPS[DEFAULT_SHOP])
	var wanted: Array = spec["types"]
	var out: Array = []
	for path in STOCK:
		var template = load(path)
		if template == null:
			continue
		if wanted.is_empty():
			# The general store: whatever nobody else deals in.
			if not _spoken_for(template.item_type):
				out.append(path)
		elif template.item_type in wanted:
			out.append(path)
	return out


static func _spoken_for(item_type: int) -> bool:
	for id in SHOPS:
		var types: Array = SHOPS[id]["types"]
		if not types.is_empty() and item_type in types:
			return true
	return false


func _describe(item) -> String:
	## The item's own words for itself — the same helpers the inventory card uses, so a sword
	## reads the same in a shop as it does in a pack.
	var parts: Array = [item.type_name()]
	var head: Array = item.headline_stat()
	if head.size() == 2:
		parts.append("%s %+d" % [head[1], head[0]])
	for line in item.stat_lines():
		parts.append("%s %s" % [line[0], line[1]])
	return "  ·  ".join(parts)


# --- Buying and selling ----------------------------------------------------

func _on_buy(path: String) -> void:
	var member = GameState.party[_who]
	var template = load(path)
	if template == null:
		return
	if not member.bag_has_room():
		ScreenPanelScript.toast(self, "%s cannot carry any more." % member.character_name)
		return
	var price: int = template.gold_value()
	if not GameState.spend_gold(price):
		ScreenPanelScript.toast(self, "That costs %d gold and the party has %d."
			% [price, GameState.gold])
		return

	# An instance of its own, like every other item that enters play, so that its durability
	# is this character's and it knows which template it came from (it has to be saveable).
	var item = template.make_instance()
	# Should be unreachable — room was just checked — but putting the gold back is the only
	# acceptable way to fail a purchase.
	if not member.bag_add(item):
		GameState.add_gold(price)
		ScreenPanelScript.toast(self, "That would not fit after all.")
		return

	# Worn straight away only when the slot it wants is EMPTY. Buying armour with none on is
	# obviously putting it on; buying a second sword is a decision about which to hold, and
	# this screen is not the place to make it — the inventory in the dungeon is.
	var note: String = "Bought %s." % item.item_name
	if member.slot_is_free(item):
		var idx: int = member.bag.find(item)
		if idx >= 0 and member.equip_from_bag(idx):
			note = "Bought %s, and put it on." % item.item_name

	GameState.party_changed.emit()
	SaveGameScript.save()
	_build()
	ScreenPanelScript.toast(self, note)


func _on_sell(idx: int) -> void:
	var member = GameState.party[_who]
	if idx < 0 or idx >= member.bag.size() or member.bag[idx] == null:
		return
	var item = member.bag[idx]
	var paid: int = item.sell_value()
	var was_worn: bool = member.is_equipped(idx)
	# bag_remove_at clears the equipment slots pointing at it, which is the whole reason
	# selling goes through CharacterData rather than poking the array here.
	member.bag_remove_at(idx)
	GameState.add_gold(paid)

	GameState.party_changed.emit()
	SaveGameScript.save()
	_build()
	var note: String = "Sold %s for %d gold." % [item.item_name, paid]
	if was_worn:
		note += " %s is no longer using it." % member.character_name
	ScreenPanelScript.toast(self, note)


func _free_slots(member) -> int:
	var free := 0
	for item in member.bag:
		if item == null:
			free += 1
	return free


func _bag_size(member) -> int:
	return maxi(member.bag.size(), 1)


func _on_pick(index: int) -> void:
	_who = index
	_build()


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
