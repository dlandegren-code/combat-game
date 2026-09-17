extends RefCounted
class_name CharacterClasses
## The catalogue a new character is made from: what a soldier, an archer or a wizard starts
## with, and how each of them is described on the creation screen.
##
## The numbers are not invented. They are lifted from the three heroes that were hand-placed
## in the old single-scene battlefield, which were the only definition of a starting hero the
## game had — so a character created on the creation screen is the same character the test
## scenario was balanced around.
##
## AUTHORING DATA, and only that. Nothing here is consulted after a character exists: the
## moment `make` hands back a CharacterData, that character owns its own stat block and
## training writes into it (Phase 3). Changing a class later will not retroactively change
## anybody who already took it, which is the behaviour you want — a hero is not a template
## instance.
##
## `stats` holds only the fields that differ from CombatantStats' own defaults, so a class is
## readable as "what makes this class different" rather than as forty numbers. See
## CharacterData.CLASS_BODIES for the other half of a class: the body it wears.

const CharacterDataScript := preload("res://scripts/character_data.gd")
const CombatantStatsScript := preload("res://scripts/combatant_stats.gd")
const CombatantScript := preload("res://scripts/combatant.gd")
const InventoryComponentScript := preload("res://scripts/inventory_component.gd")

const CLASSES := {
	"soldier": {
		"display_name": "Soldier",
		"blurb": "Sword, shield and the discipline to hold a line. Can take the Protection "
			+ "stance to guard the squares beside them, which nobody else can.",
		"voice": "male_a",
		"stats": {
			"can_guard": true,
			"agility": 5,
			"stamina": 4,
		},
		"items": [
			"res://resources/items/rusty_sword.tres",
			"res://resources/items/wooden_shield.tres",
			"res://resources/items/leather_armor.tres",
		],
	},
	"archer": {
		"display_name": "Archer",
		"blurb": "Fights at range and dodges rather than parries. Quick, lightly armoured, "
			+ "and the only one of the three who can pick a lock.",
		"voice": "male_b",
		"stats": {
			"initiative": 8,
			"attack_skill": 4,
			"parry_skill": 2,
			"defensive_option": 1,   ## Dodge — see Stance, where the ids are load-bearing
			"shove_skill": 2,
			"trip_skill": 3,
			"ammo": 7,
			"max_ammo": 12,
			"lockpick_skill": 3,
			"agility": 7,
			"stamina": 4,
		},
		"items": [
			"res://resources/items/ranger_dagger.tres",
			"res://resources/items/reinforced_leather_armor.tres",
			"res://resources/items/short_bow.tres",
			"res://resources/items/quiver.tres",
		],
	},
	"wizard": {
		"display_name": "Wizard",
		"blurb": "Throws firebolts and has the mana to keep doing it. Frail in a melee — "
			+ "fewer hit points than either of the others, and no armour to speak of.",
		"voice": "male_c",
		"stats": {
			"initiative": 8,
			"attack_skill": 4,
			"parry_skill": 2,
			"defensive_option": 1,   ## Dodge
			"shove_skill": 2,
			"trip_skill": 3,
			"can_cast": true,
			"intelligence": 5,
			"willpower": 5,
		},
		"items": [
			"res://resources/items/ranger_dagger.tres",
			"res://resources/items/gemstone_staff.tres",
		],
	},
}

## Order the classes are offered in on the creation screen.
const ORDER := ["soldier", "archer", "wizard"]


static func make(class_id: String, character_name: String):
	## Build a brand-new character. The one way a character comes into existence that is not
	## a save file being read or the old battlefield being harvested.
	var spec: Dictionary = CLASSES.get(class_id, CLASSES[CharacterDataScript.DEFAULT_CLASS])
	var data = CharacterDataScript.new()
	data.id = CharacterDataScript.make_id()
	data.class_id = class_id if CLASSES.has(class_id) else CharacterDataScript.DEFAULT_CLASS
	data.character_name = character_name.strip_edges()
	if data.character_name == "":
		data.character_name = spec["display_name"]
	data.voice = spec["voice"]
	data.stats = _stat_block(spec)
	# Left at "arrive at full": there is no body yet to ask how many hit points that is, which
	# is exactly what CharacterData.VITALS_FULL is for.
	data.bag = _starting_bag(spec)
	data.equipped = _starting_loadout(data.bag)
	return data


static func display_name(class_id: String) -> String:
	if CLASSES.has(class_id):
		return CLASSES[class_id]["display_name"]
	return class_id.capitalize()


static func blurb(class_id: String) -> String:
	return CLASSES[class_id]["blurb"] if CLASSES.has(class_id) else ""


static func summary_lines(class_id: String) -> Array:
	## The handful of numbers worth showing next to the blurb while choosing. Derived from the
	## stat block rather than written out again, so it cannot drift from what the class
	## actually is.
	if not CLASSES.has(class_id):
		return []
	var s: Resource = _stat_block(CLASSES[class_id])
	var hp: int = maxi(1, s.stamina * CombatantScript.HP_PER_STAMINA)
	var mana: int = (s.willpower * CombatantScript.MANA_PER_WILLPOWER) if s.can_cast else 0
	var lines: Array = [
		"%d hp   melee %d   ranged %d   %s %d" % [
			hp, s.attack_skill, s.ranged_skill,
			"dodge" if s.defensive_option == 1 else "parry",
			s.agility if s.defensive_option == 1 else s.parry_skill,
		],
		"str %d   agi %d   sta %d   int %d   wil %d" % [
			s.strength, s.agility, s.stamina, s.intelligence, s.willpower,
		],
	]
	var extras: Array = []
	if mana > 0:
		extras.append("%d mana" % mana)
	if s.can_guard:
		extras.append("can guard")
	if s.lockpick_skill > 0:
		extras.append("lockpicking %d" % s.lockpick_skill)
	if s.max_ammo > 0:
		extras.append("%d/%d arrows" % [s.ammo, s.max_ammo])
	if not extras.is_empty():
		lines.append(", ".join(extras))
	lines.append("Starts with: " + ", ".join(_item_names(CLASSES[class_id])))
	return lines



static func _stat_block(spec: Dictionary) -> Resource:
	var s: Resource = CombatantStatsScript.new()
	for field in spec["stats"]:
		# Silently ignoring an unknown field would let a typo cost a class its defining stat.
		if not (field in s):
			push_error("CharacterClasses: no such stat '%s'" % field)
			continue
		s.set(field, spec["stats"][field])
	return s


static func _starting_bag(spec: Dictionary) -> Array:
	## The bag is laid out exactly as InventoryComponent lays one out — fixed length, nulls
	## for the empty slots — because the equipment map points into it by index.
	var bag: Array = []
	bag.resize(InventoryComponentScript.MAX_SLOTS)
	var i := 0
	for path in spec["items"]:
		var template = load(path)
		if template == null:
			push_error("CharacterClasses: missing starting item %s" % path)
			continue
		bag[i] = template.make_instance()
		i += 1
	return bag



static func _starting_loadout(bag: Array) -> Dictionary:
	## What a new character walks out of the creation screen wearing.
	##
	## Follows the live rules exactly — InventoryComponent.preferred_slot for where a thing
	## goes, and later gear displacing earlier gear in the same slot, which is what _equip_to
	## does when it unequips the current occupant. Getting this wrong would be invisible until
	## the first quest, where the real inventory would disagree with what the town showed.
	var equipped := {}
	for idx in range(bag.size()):
		var item = bag[idx]
		if item == null:
			continue
		var slot: int = InventoryComponentScript.preferred_slot(item)
		if slot < 0:
			continue   # carried, not worn: arrows, potions, keys
		var two_handed: bool = item.handedness == ItemResource.Handedness.TWO_HANDED
		var to_a_hand: bool = slot == ItemResource.EquipSlot.RIGHT_HAND \
			or slot == ItemResource.EquipSlot.LEFT_HAND
		if to_a_hand:
			# Whatever was in the hands makes way, exactly as _equip_to arranges it: a
			# two-hander needs both hands, and a one-hander cannot share with one.
			var held = equipped.get(ItemResource.EquipSlot.RIGHT_HAND, -1)
			var offhand = equipped.get(ItemResource.EquipSlot.LEFT_HAND, -1)
			if two_handed or (held != -1 and held == offhand):
				equipped.erase(ItemResource.EquipSlot.RIGHT_HAND)
				equipped.erase(ItemResource.EquipSlot.LEFT_HAND)
		equipped[slot] = idx
		if two_handed:
			# Stored under both hands with the same index — the shape CharacterData captures
			# from a live inventory, so the two can be compared.
			equipped[ItemResource.EquipSlot.RIGHT_HAND] = idx
			equipped[ItemResource.EquipSlot.LEFT_HAND] = idx
	return equipped


static func _item_names(spec: Dictionary) -> Array:
	var names: Array = []
	for path in spec["items"]:
		var template = load(path)
		if template != null:
			names.append(template.item_name)
	return names
