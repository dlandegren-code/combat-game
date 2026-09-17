extends Control
## The market: gold in, gear out, and the other way round.
##
## Prices are the item's own business (ItemResource.gold_value / sell_value, derived from what
## the thing actually does), and the gap between the two is what stops a dungeon full of
## goblin daggers from being an income. What is FOR SALE is here, because that is a property
## of this town rather than of the items.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## What the town keeps in stock. A fixed list, and an honest one: everything here is already
## in resources/items, so nothing had to be invented to fill a shelf.
##
## Phase 4 can rotate this — a quest board that generates dungeons ought to have a market that
## restocks — but a fixed shop is not a placeholder. Knowing that the armourer always has
## greaves is what lets a player save up for them.
const STOCK := [
	"res://resources/items/health_potion.tres",
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

var _who: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self, true)
	ScreenPanelScript.title(column, "The Market")

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody here to buy anything.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	_who = clampi(_who, 0, GameState.party.size() - 1)
	var member = GameState.party[_who]

	if GameState.party.size() > 1:
		var picker := ScreenPanelScript.row(column)
		for i in range(GameState.party.size()):
			var text: String = GameState.party[i].character_name
			if i == _who:
				text = "> %s <" % text
			var pick := ScreenPanelScript.button(picker, text, _on_pick.bind(i))
			pick.custom_minimum_size = Vector2(150, ScreenPanelScript.BUTTON_HEIGHT)
			pick.size_flags_horizontal = Control.SIZE_FILL

	ScreenPanelScript.label(column, "%d gold   ·   buying for %s, who has %d of %d pack slots free" % [
		GameState.gold, member.character_name, _free_slots(member), _bag_size(member),
	], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	_add_stock(column, member)
	ScreenPanelScript.separator(column)
	_add_pack(column, member)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)
	ScreenPanelScript.spacer(column, 16.0)


func _add_stock(column: Node, member) -> void:
	ScreenPanelScript.heading(column, "For sale")
	for path in STOCK:
		var template = load(path)
		if template == null:
			continue
		var price: int = template.gold_value()
		var affordable: bool = GameState.gold >= price and member.bag_has_room()
		var button := ScreenPanelScript.button(column,
			"%s — %d gold" % [template.item_name, price], _on_buy.bind(path), affordable)
		button.custom_minimum_size = Vector2(ScreenPanelScript.WIDTH, ScreenPanelScript.BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_FILL
		ScreenPanelScript.label(column, "    " + _describe(template),
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


func _add_pack(column: Node, member) -> void:
	ScreenPanelScript.heading(column, "%s's pack" % member.character_name)
	var anything := false
	for idx in range(member.bag.size()):
		var item = member.bag[idx]
		if item == null:
			continue
		anything = true
		var worn: bool = member.is_equipped(idx)
		var label: String = "Sell %s — %d gold" % [item.item_name, item.sell_value()]
		if worn:
			label += "   (in use)"
		var button := ScreenPanelScript.button(column, label, _on_sell.bind(idx))
		button.custom_minimum_size = Vector2(ScreenPanelScript.WIDTH, ScreenPanelScript.BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_FILL
		ScreenPanelScript.label(column, "    " + _describe(item),
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	if not anything:
		ScreenPanelScript.label(column, "    Empty.", ScreenPanelScript.BODY_SIZE,
			ScreenPanelScript.MUTED)


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
