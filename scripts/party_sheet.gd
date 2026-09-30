extends Control
## The company, one member at a time: what they are carrying, what they are made of, and what
## they can cast — and the one place gear moves from one pack to another.
##
## WHY THIS IS NOT THE QUEST SCREEN'S PANELS
## The dungeon already has an inventory doll, a character sheet and a spell book
## (inventory_ui.gd, character_sheet_ui.gd, spell_sheet_ui.gd). Every one of them reads
## `CombatManager.current_combatant` and works on a live Combatant with an Inventory child,
## and the inventory one routes its clicks through Player.equip_weapon, which CHARGES TIME AND
## ENDS THE TURN. None of that exists in town and none of it should: there is no turn to end,
## no body to fold an armour bonus into, and nothing to spend time on. So this reads
## CharacterData directly and edits it through the operations CharacterData already owns
## (equip_from_bag, unequip_index, bag_add, bag_remove_at) — the same ones the shop buys and
## sells through.
##
## The DERIVED numbers on the sheet — hit points from stamina, mana from willpower — are
## computed here from Combatant's constants rather than from a body, exactly as
## CharacterClasses.summary_lines does for the creation screen. There is no Combatant in town
## to ask, and duplicating two multiplications is cheaper than building one to find out.
##
## Rearranging gear in town is FREE. In the dungeon it costs a turn, and that difference is
## the point of doing it here: sorting out who carries the spare shield is planning, and
## planning is what a town is for.

const ScreenPanelScript := preload("res://scripts/ui_kit.gd")
const CharacterDataScript := preload("res://scripts/character_data.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const CombatantScript := preload("res://scripts/combatant.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const PlayerScript := preload("res://scripts/player.gd")
const InventoryComponentScript := preload("res://scripts/inventory_component.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## The three pages, and the order the town's toolbar puts them in. A table rather than three
## constants because the toolbar builds its buttons from it — the town should not have to be
## edited to add a page here.
const TABS := [
	{"id": "gear", "label": "Gear"},
	{"id": "sheet", "label": "Sheet"},
	{"id": "spells", "label": "Spells"},
]

## Which page to open on. Set by whoever changes to this scene and read once, on the way in.
##
## A static rather than a GameState field: which page a player clicked is a property of THIS
## trip to this screen, not of the game, and it has no business being saved, reset by
## GameState.clear(), or readable by anything else. It survives the scene change because the
## script object does.
static var opening_tab: String = "gear"

## The slots shown on the Gear page, in the order a person puts them on.
const WORN_ORDER := [
	{"slot": ItemResource.EquipSlot.RIGHT_HAND, "label": "Right hand"},
	{"slot": ItemResource.EquipSlot.LEFT_HAND, "label": "Left hand"},
	{"slot": ItemResource.EquipSlot.ARMOR, "label": "Body"},
	{"slot": ItemResource.EquipSlot.HELMET, "label": "Head"},
	{"slot": ItemResource.EquipSlot.LEGS, "label": "Legs"},
]

const ATTRIBUTES := [
	{"field": "strength", "label": "Strength"},
	{"field": "agility", "label": "Agility"},
	{"field": "stamina", "label": "Stamina"},
	{"field": "intelligence", "label": "Intelligence"},
	{"field": "willpower", "label": "Willpower"},
	{"field": "charisma", "label": "Charisma"},
]

var _who: int = 0
var _tab: String = "gear"
## Who the Gear page is handing things TO. An index into the party, or -1 for nobody chosen
## yet. Kept across redraws so a player can empty one pack into another without re-picking the
## recipient after every single item.
var _giving_to: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab = opening_tab if _known_tab(opening_tab) else "gear"
	_build()


func _known_tab(id: String) -> bool:
	for tab in TABS:
		if String(tab["id"]) == id:
			return true
	return false


func _build() -> void:
	var column := ScreenPanelScript.mount(self, true)
	ScreenPanelScript.title(column, "The Company")

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody here to look at.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	_who = clampi(_who, 0, GameState.party.size() - 1)
	var member = GameState.party[_who]

	if GameState.party.size() > 1:
		var picker := ScreenPanelScript.row(column)
		for i in range(GameState.party.size()):
			var other = GameState.party[i]
			ScreenPanelScript.pill(picker, other.character_name, _on_who.bind(i), i != _who)

	ScreenPanelScript.heading(column, "%s — level %d %s" % [
		member.character_name, member.level,
		CharacterClassesScript.display_name(member.class_id)])

	var tabs := ScreenPanelScript.row(column)
	for tab in TABS:
		var id := String(tab["id"])
		ScreenPanelScript.pill(tabs, String(tab["label"]), _on_tab.bind(id), id != _tab)
	ScreenPanelScript.separator(column)

	match _tab:
		"sheet":
			_draw_sheet(column, member)
		"spells":
			_draw_spells(column, member)
		_:
			_draw_gear(column, member)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)


# --- Gear ------------------------------------------------------------------

func _draw_gear(column: Node, member) -> void:
	## Worn and carried, both as icon rows — the same ItemSlot the dungeon's equipment doll and
	## backpack are built from, so a shield reads the same in town as it does in the dark.
	ScreenPanelScript.heading(column, "Worn and held")
	for entry in WORN_ORDER:
		var slot: int = entry["slot"]
		var idx: int = int(member.equipped.get(slot, -1))
		var item = member.bag[idx] if idx >= 0 and idx < member.bag.size() else null
		if item == null:
			ScreenPanelScript.label(column, "%s: —" % entry["label"],
				ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
			continue
		# A two-hander fills both hands and is listed under both, so only the first listing
		# gets a row — the same sword twice, once with a Take off button and once without,
		# would read as two swords.
		if _is_offhand_of_two_hander(member, slot, idx):
			ScreenPanelScript.label(column, "%s: %s (both hands)"
				% [entry["label"], item.item_name],
				ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
			continue
		ScreenPanelScript.item_row(column, item,
			"%s%s" % [entry["label"], _bonus_text(item)], "", [
				{"label": "Take off", "handler": _on_take_off.bind(idx), "width": 92.0},
			])

	ScreenPanelScript.spacer(column, 6.0)
	if GameState.party.size() > 1:
		_draw_recipient(column)

	var carried := _carried_indices(member)
	ScreenPanelScript.heading(column, "Carried — %d of %d slots"
		% [_used_slots(member), InventoryComponentScript.MAX_SLOTS])
	if carried.is_empty():
		ScreenPanelScript.label(column, "Nothing but what they are wearing.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	for idx2 in carried:
		var item2 = member.bag[idx2]
		var actions: Array = []
		if InventoryComponentScript.preferred_slot(item2) >= 0:
			actions.append({"label": "Put on", "handler": _on_put_on.bind(idx2), "width": 82.0})
		if _giving_to >= 0 and _giving_to < GameState.party.size() and _giving_to != _who:
			var to = GameState.party[_giving_to]
			actions.append({"label": "Give to %s" % to.character_name,
				"handler": _on_give.bind(idx2), "enabled": to.bag_has_room(), "width": 128.0})
		ScreenPanelScript.item_row(column, item2, _carry_note(item2), "", actions)


func _is_offhand_of_two_hander(member, slot: int, idx: int) -> bool:
	## True for the LEFT_HAND listing of a weapon that is also in the right hand.
	if slot != ItemResource.EquipSlot.LEFT_HAND:
		return false
	return int(member.equipped.get(ItemResource.EquipSlot.RIGHT_HAND, -2)) == idx


func _carry_note(item) -> String:
	## What an unworn item is, in the fewest words that tell it from the one below it.
	var bonus := _bonus_text(item).strip_edges()
	if bonus == "":
		return item.type_name()
	return "%s  ·  %s" % [item.type_name(), bonus.trim_prefix("(").trim_suffix(")")]


func _draw_recipient(column: Node) -> void:
	## Who the next "Give" goes to, picked once rather than per item.
	##
	## One recipient chosen up front, and then one button per item, instead of a button per
	## item per member: with four in the company that would be three buttons on every line of a
	## full pack, which is a wall rather than a screen.
	ScreenPanelScript.label(column, "Hand things to:", ScreenPanelScript.BODY_SIZE,
		ScreenPanelScript.MUTED)
	var row := ScreenPanelScript.row(column)
	for i in range(GameState.party.size()):
		if i == _who:
			continue
		var other = GameState.party[i]
		# "Hand to Wren", not "Wren". The member picker at the top of the screen is also a row
		# of names, and two rows of bare names on one screen leaves the player guessing which
		# one changes who they are LOOKING at and which one changes who they are GIVING to.
		var text: String = "Hand to %s" % other.character_name
		if not other.bag_has_room():
			text += " (full)"
		ScreenPanelScript.pill(row, text, _on_recipient.bind(i), i != _giving_to)
	ScreenPanelScript.spacer(column, 6.0)


func _carried_indices(member) -> Array:
	## Bag slots holding something that is NOT being worn. The worn half is listed above by
	## slot, and an item that appeared in both lists would look like two items.
	var out: Array = []
	for i in range(member.bag.size()):
		if member.bag[i] != null and not member.is_equipped(i):
			out.append(i)
	return out


func _used_slots(member) -> int:
	var n := 0
	for item in member.bag:
		if item != null:
			n += 1
	return n


func _bonus_text(item) -> String:
	## The one or two numbers that decide whether this is better than that. Not a full item
	## card — the dungeon's inventory has one of those, with the art — just enough to choose by.
	var parts: Array = []
	if item.attack_bonus != 0:
		parts.append("%+d to hit" % item.attack_bonus)
	if item.damage_bonus != 0:
		parts.append("%+d damage" % item.damage_bonus)
	if item.armor_bonus != 0:
		parts.append("%+d armour" % item.armor_bonus)
	if item.resistance_bonus != 0:
		parts.append("%+d%% resistance" % item.resistance_bonus)
	if item.parry_bonus != 0:
		parts.append("%+d parry" % item.parry_bonus)
	if item.heal_amount > 0:
		parts.append("heals %d" % item.heal_amount)
	if item.ammo_amount > 0:
		parts.append("%d arrows" % item.ammo_amount)
	if parts.is_empty():
		return ""
	return "   (%s)" % ", ".join(parts)


# --- Sheet -----------------------------------------------------------------

func _draw_sheet(column: Node, member) -> void:
	var s: Resource = member.stats
	if s == null:
		ScreenPanelScript.label(column, "This character has no stat block.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.BAD)
		return

	ScreenPanelScript.heading(column, "Condition")
	var max_hp: int = maxi(1, int(s.stamina) * CombatantScript.HP_PER_STAMINA)
	var hp: int = max_hp if member.hp == CharacterDataScript.VITALS_FULL else member.hp
	ScreenPanelScript.label(column, "Hit points: %d of %d" % [hp, max_hp],
		ScreenPanelScript.BODY_SIZE,
		ScreenPanelScript.GOOD if hp >= max_hp else ScreenPanelScript.BAD)
	if s.can_cast:
		var max_mana: int = maxi(0, int(s.willpower) * CombatantScript.MANA_PER_WILLPOWER)
		var mana: int = max_mana if member.mana == CharacterDataScript.VITALS_FULL else member.mana
		ScreenPanelScript.label(column, "Mana: %d of %d" % [mana, max_mana])
	if int(s.max_ammo) > 0:
		var ammo: int = int(s.max_ammo) if member.ammo == CharacterDataScript.VITALS_FULL \
			else member.ammo
		ScreenPanelScript.label(column, "Arrows: %d of %d" % [ammo, int(s.max_ammo)])

	# Armour as it will actually be in the dungeon: the stat block plus what is worn. Shown
	# together because the number that matters is the total, and split because a player
	# choosing between two breastplates needs to see which part they are changing.
	var worn := _worn_bonuses(member)
	ScreenPanelScript.label(column, "Armour: %d%s      Resistance: %d%%%s" % [
		int(s.armor) + worn.x, _from_gear(worn.x),
		int(s.physical_resistance) + worn.y, _from_gear(worn.y)])
	ScreenPanelScript.label(column, "Initiative: %d      Move: %d tiles" % [
		int(s.initiative), int(s.move_range)])

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.heading(column, "Attributes")
	var attr_line: Array = []
	for entry in ATTRIBUTES:
		attr_line.append("%s %d" % [entry["label"], int(s.get(entry["field"]))])
	ScreenPanelScript.label(column, "   ".join(attr_line))
	ScreenPanelScript.label(column,
		"Attributes are not trainable yet — see the training hall.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.heading(column, "Skills")
	for entry in ProgressionScript.SKILLS:
		var field: String = entry["field"]
		var level: int = int(s.get(field))
		var pot: int = member.skill_xp_for(field)
		var needed: int = ProgressionScript.xp_to_level(level)
		var line := "%s %d" % [entry["label"], level]
		if level >= ProgressionScript.SKILL_CAP:
			line += "   (as high as it goes)"
		else:
			line += "   %d/%d xp to %d" % [pot, needed, level + 1]
		ScreenPanelScript.label(column, line, ScreenPanelScript.BODY_SIZE,
			ScreenPanelScript.GOOD if pot >= needed and level < ProgressionScript.SKILL_CAP
				else ScreenPanelScript.BODY)

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.label(column, "General xp: %d unspent, %d earned all told" % [
		member.xp, member.xp_total], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


func _worn_bonuses(member) -> Vector2i:
	## Armour and resistance from what is being worn, counted ONCE per item.
	##
	## Counted by bag index rather than by slot, because a two-handed weapon is listed under
	## both hands and a shield-and-sword pair is not — walking the slots would count the
	## two-hander's bonuses twice and nothing else's.
	var counted: Array = []
	var armour := 0
	var resist := 0
	for slot in member.equipped:
		var idx: int = int(member.equipped[slot])
		if idx in counted or idx < 0 or idx >= member.bag.size():
			continue
		counted.append(idx)
		var item = member.bag[idx]
		if item == null:
			continue
		armour += int(item.armor_bonus)
		resist += int(item.resistance_bonus)
	return Vector2i(armour, resist)


func _from_gear(amount: int) -> String:
	return "" if amount == 0 else " (%+d from gear)" % amount


# --- Spells ----------------------------------------------------------------

func _draw_spells(column: Node, member) -> void:
	var s: Resource = member.stats
	if s == null or not s.can_cast:
		ScreenPanelScript.label(column, "%s is no caster." % member.character_name,
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
		ScreenPanelScript.label(column,
			"Casting is a property of the class. Nothing in town can teach it.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
		return

	var max_mana: int = maxi(0, int(s.willpower) * CombatantScript.MANA_PER_WILLPOWER)
	var mana: int = max_mana if member.mana == CharacterDataScript.VITALS_FULL else member.mana
	ScreenPanelScript.label(column, "Mana: %d of %d      Spell power: %d (willpower)" % [
		mana, max_mana, int(s.willpower)])
	ScreenPanelScript.spacer(column, 6.0)

	# Off the real ability roster, so a second spell appears here the day it is written and
	# not the day somebody remembers this screen exists. Abilities are stateless and the ones
	# asked below ignore their actor, which is what makes them answerable without a body.
	var found := false
	for ability in PlayerScript.build_abilities():
		if not ability.is_spell():
			continue
		found = true
		ScreenPanelScript.heading(column, ability.display_name)
		ScreenPanelScript.label(column, ability.get_description(null))
		ScreenPanelScript.label(column, "%d mana, %d time, reach %d tiles" % [
			ability.get_mana_cost(null), int(s.spell_cost), ability.get_range(null)],
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
		ScreenPanelScript.spacer(column, 4.0)
	if not found:
		ScreenPanelScript.label(column, "No spells written yet.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	else:
		ScreenPanelScript.label(column, "Cast it from the action bar, down in the dark.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


# --- What the buttons do ---------------------------------------------------

func _on_who(index: int) -> void:
	_who = index
	# The recipient is cleared when the subject changes: "give to Wren" means nothing while
	# looking at Wren, and silently keeping a stale choice is how a player hands a sword to
	# somebody they were not looking at.
	_giving_to = -1
	_build()


func _on_tab(id: String) -> void:
	_tab = id
	_build()


func _on_recipient(index: int) -> void:
	_giving_to = index
	_build()


func _on_put_on(idx: int) -> void:
	var member = GameState.party[_who]
	if not member.equip_from_bag(idx):
		ScreenPanelScript.toast(self, "That is not something you wear.")
		return
	_save_and_redraw()


func _on_take_off(idx: int) -> void:
	GameState.party[_who].unequip_index(idx)
	_save_and_redraw()


func _on_give(idx: int) -> void:
	## Move one item from this pack to another's.
	##
	## Out of the giver FIRST — bag_remove_at also takes it off, which is what should happen
	## when you hand somebody the shield off your arm — and back into the giver untouched if
	## the receiver turns out to have no room. An item must never be able to evaporate between
	## two packs.
	if _giving_to < 0 or _giving_to >= GameState.party.size() or _giving_to == _who:
		return
	var from = GameState.party[_who]
	var to = GameState.party[_giving_to]
	var item = from.bag_remove_at(idx)
	if item == null:
		return
	if not to.bag_add(item):
		from.bag_add(item)
		ScreenPanelScript.toast(self, "%s has no room for it." % to.character_name)
		return
	_save_and_redraw()
	ScreenPanelScript.toast(self, "%s hands %s the %s."
		% [from.character_name, to.character_name, item.item_name])


func _save_and_redraw() -> void:
	# Town is the checkpoint, and moving gear between two people changes the party — so it is
	# written now rather than on the way back out. Closing the game on this screen must not
	# undo the sorting-out that was just done.
	SaveGameScript.save()
	_build()


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
