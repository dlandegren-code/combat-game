extends Node
## Per-character inventory: holds items, allows equip/drop/pickup

const MAX_SLOTS := 4

enum EquipSlot { ANY_HAND, RIGHT_HAND, LEFT_HAND, ARMOR }

@export var starting_item_name: String = ""
@export var starting_item_type: int = ItemResource.ItemType.WEAPON
@export var starting_item_equip_slot: int = ItemResource.EquipSlot.ANY_HAND
@export var starting_item_handedness: int = ItemResource.Handedness.ONE_HANDED
@export var starting_item_attack: int = 0
@export var starting_item_damage: int = 0
@export var starting_item_durability: int = 10
@export var starting_item_armor: int = 0
@export var starting_item_resistance: int = 0
@export var starting_item_is_shield: bool = false
@export var starting_item_parry_ranged: bool = false
@export var starting_item_dodge_ranged: bool = false

@export var starting_item_2_name: String = ""
@export var starting_item_2_type: int = ItemResource.ItemType.WEAPON
@export var starting_item_2_equip_slot: int = ItemResource.EquipSlot.ANY_HAND
@export var starting_item_2_handedness: int = ItemResource.Handedness.ONE_HANDED
@export var starting_item_2_attack: int = 0
@export var starting_item_2_damage: int = 0
@export var starting_item_2_durability: int = 10
@export var starting_item_2_armor: int = 0
@export var starting_item_2_resistance: int = 0
@export var starting_item_2_is_shield: bool = false
@export var starting_item_2_parry_ranged: bool = false
@export var starting_item_2_dodge_ranged: bool = false

@export var starting_item_3_name: String = ""
@export var starting_item_3_type: int = ItemResource.ItemType.WEAPON
@export var starting_item_3_equip_slot: int = ItemResource.EquipSlot.ANY_HAND
@export var starting_item_3_handedness: int = ItemResource.Handedness.ONE_HANDED
@export var starting_item_3_attack: int = 0
@export var starting_item_3_damage: int = 0
@export var starting_item_3_durability: int = 10
@export var starting_item_3_armor: int = 0
@export var starting_item_3_resistance: int = 0
@export var starting_item_3_is_shield: bool = false
@export var starting_item_3_parry_ranged: bool = false
@export var starting_item_3_dodge_ranged: bool = false

var items: Array  ## Array[ItemResource], null means empty slot

## Equipment slots: each holds an ItemResource or null
var right_hand: ItemResource = null
var left_hand: ItemResource = null
var armor: ItemResource = null

var character: CharacterBody3D  ## parent character, set on ready

func _ready() -> void:
	character = get_parent() as CharacterBody3D
	items.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		items[i] = null
	_add_starting_item(starting_item_name, starting_item_type, starting_item_equip_slot,
		starting_item_handedness, starting_item_attack, starting_item_damage,
		starting_item_durability, starting_item_armor, starting_item_resistance,
		starting_item_is_shield, starting_item_parry_ranged, starting_item_dodge_ranged)
	_add_starting_item(starting_item_2_name, starting_item_2_type, starting_item_2_equip_slot,
		starting_item_2_handedness, starting_item_2_attack, starting_item_2_damage,
		starting_item_2_durability, starting_item_2_armor, starting_item_2_resistance,
		starting_item_2_is_shield, starting_item_2_parry_ranged, starting_item_2_dodge_ranged)
	_add_starting_item(starting_item_3_name, starting_item_3_type, starting_item_3_equip_slot,
		starting_item_3_handedness, starting_item_3_attack, starting_item_3_damage,
		starting_item_3_durability, starting_item_3_armor, starting_item_3_resistance,
		starting_item_3_is_shield, starting_item_3_parry_ranged, starting_item_3_dodge_ranged)


func _add_starting_item(name_str: String, type: int, slot: int, handed: int,
		atk: int, dmg: int, dur: int, armor_val: int, res: int,
		shield: bool, parry: bool, dodge: bool) -> void:
	if name_str == "":
		return
	var item := ItemResource.new()
	item.item_name = name_str
	item.item_type = type
	item.equip_slot = slot
	item.handedness = handed
	item.attack_bonus = atk
	item.damage_bonus = dmg
	item.durability = dur
	item.armor_bonus = armor_val
	item.resistance_bonus = res
	item.is_shield = shield
	item.parry_ranged = parry
	item.dodge_ranged = dodge
	add_item(item)
	# Auto-equip starting items into their intended slot
	if item.can_equip_in(ItemResource.EquipSlot.RIGHT_HAND):
		_equip_to(ItemResource.EquipSlot.RIGHT_HAND, item)
	elif item.can_equip_in(ItemResource.EquipSlot.LEFT_HAND):
		_equip_to(ItemResource.EquipSlot.LEFT_HAND, item)
	elif item.can_equip_in(ItemResource.EquipSlot.ARMOR):
		_equip_to(ItemResource.EquipSlot.ARMOR, item)


func add_item(item: ItemResource) -> bool:
	## Returns true if item was added, false if inventory full.
	for i in range(MAX_SLOTS):
		if items[i] == null:
			items[i] = item
			return true
	return false


func remove_item(slot_index: int) -> ItemResource:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return null
	var item: ItemResource = items[slot_index]
	if item == null:
		return null
	# Unequip from any slot if it was equipped
	if right_hand == item:
		unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
	if left_hand == item:
		unequip_slot(ItemResource.EquipSlot.LEFT_HAND)
	if armor == item:
		unequip_slot(ItemResource.EquipSlot.ARMOR)
	items[slot_index] = null
	return item


func get_item_slot(item: ItemResource) -> int:
	for i in range(MAX_SLOTS):
		if items[i] == item:
			return i
	return -1


func equip(slot_index: int) -> void:
	## Equip an item from the inventory bag into its preferred slot.
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return
	var item: ItemResource = items[slot_index]
	if item == null:
		return

	# Determine target slot based on item type and current equipment
	var target_slot := ItemResource.EquipSlot.ANY_HAND
	if item.item_type == ItemResource.ItemType.ARMOR:
		target_slot = ItemResource.EquipSlot.ARMOR
	elif item.equip_slot == ItemResource.EquipSlot.RIGHT_HAND:
		target_slot = ItemResource.EquipSlot.RIGHT_HAND
	elif item.equip_slot == ItemResource.EquipSlot.LEFT_HAND:
		target_slot = ItemResource.EquipSlot.LEFT_HAND
	elif item.equip_slot == ItemResource.EquipSlot.ANY_HAND:
		# Place 1H weapon in right hand if free, otherwise left hand if free
		if right_hand == null:
			target_slot = ItemResource.EquipSlot.RIGHT_HAND
		elif left_hand == null:
			target_slot = ItemResource.EquipSlot.LEFT_HAND
		else:
			# Replace right hand by default
			target_slot = ItemResource.EquipSlot.RIGHT_HAND

	_equip_to(target_slot, item)


func unequip_slot(slot: int) -> void:
	var item: ItemResource = null
	match slot:
		ItemResource.EquipSlot.RIGHT_HAND:
			item = right_hand
			right_hand = null
		ItemResource.EquipSlot.LEFT_HAND:
			item = left_hand
			left_hand = null
		ItemResource.EquipSlot.ARMOR:
			item = armor
			armor = null
	if item and character:
		_remove_item_bonuses(item)


func unequip_item(item: ItemResource) -> void:
	## Unequip the given item from whichever slot it is currently in.
	if item == null:
		return
	if right_hand == item:
		unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
	elif left_hand == item:
		unequip_slot(ItemResource.EquipSlot.LEFT_HAND)
	elif armor == item:
		unequip_slot(ItemResource.EquipSlot.ARMOR)


func _equip_to(slot: int, item: ItemResource) -> void:
	## Internal: equip item into the given slot, handling 2H conflicts.
	if item == null:
		return
	if not item.can_equip_in(slot):
		return

	# Unequip anything currently in the target slot
	unequip_slot(slot)

	# Two-handed weapons occupy both hands
	if item.handedness == ItemResource.Handedness.TWO_HANDED:
		unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
		unequip_slot(ItemResource.EquipSlot.LEFT_HAND)
		right_hand = item
		left_hand = item
		_apply_item_bonuses(item)
		return

	# One-handed item: if equipping into a hand, unequip 2H weapon first
	if slot == ItemResource.EquipSlot.RIGHT_HAND or slot == ItemResource.EquipSlot.LEFT_HAND:
		if right_hand and right_hand.handedness == ItemResource.Handedness.TWO_HANDED:
			unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
			unequip_slot(ItemResource.EquipSlot.LEFT_HAND)
		elif slot == ItemResource.EquipSlot.RIGHT_HAND and left_hand and left_hand.handedness == ItemResource.Handedness.TWO_HANDED:
			unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
			unequip_slot(ItemResource.EquipSlot.LEFT_HAND)

	match slot:
		ItemResource.EquipSlot.RIGHT_HAND:
			right_hand = item
		ItemResource.EquipSlot.LEFT_HAND:
			left_hand = item
		ItemResource.EquipSlot.ARMOR:
			armor = item

	_apply_item_bonuses(item)


func get_equipped_weapon() -> ItemResource:
	## Right hand is the primary weapon for attack calculations.
	return right_hand


func get_equipped_offhand() -> ItemResource:
	## Left hand item (shield or offhand weapon). Null if it is the same 2H weapon as right hand.
	if left_hand == right_hand:
		return null
	return left_hand


func has_weapon_equipped() -> bool:
	var weapon := get_equipped_weapon()
	return weapon != null and (weapon.item_type == ItemResource.ItemType.WEAPON or weapon.item_type == ItemResource.ItemType.THROWABLE)


func get_equipped_attack_bonus() -> int:
	var total := 0
	var main := get_equipped_weapon()
	if main:
		total += main.attack_bonus
	var off := get_equipped_offhand()
	if off and off.item_type == ItemResource.ItemType.WEAPON:
		total += off.attack_bonus
	return total


func get_equipped_damage_bonus() -> int:
	var total := 0
	var main := get_equipped_weapon()
	if main:
		total += main.damage_bonus
	var off := get_equipped_offhand()
	if off and off.item_type == ItemResource.ItemType.WEAPON:
		total += off.damage_bonus
	return total


func is_shield_equipped() -> bool:
	var off := get_equipped_offhand()
	if off == null:
		return false
	return off.item_type == ItemResource.ItemType.SHIELD or off.is_shield


func can_parry_ranged() -> bool:
	var off := get_equipped_offhand()
	if off and (off.is_shield or off.parry_ranged):
		return true
	var main := get_equipped_weapon()
	if main and (main.is_shield or main.parry_ranged):
		return true
	return false


func can_dodge_ranged() -> bool:
	var off := get_equipped_offhand()
	if off and off.dodge_ranged:
		return true
	var main := get_equipped_weapon()
	if main and main.dodge_ranged:
		return true
	return false


func get_armor_bonus() -> int:
	if armor:
		return armor.armor_bonus
	return 0


func get_resistance_bonus() -> int:
	if armor:
		return armor.resistance_bonus
	return 0


func degrade_equipped_weapon() -> void:
	## Degrade the item used to defend: right-hand weapon first, then left-hand shield.
	var item := get_equipped_weapon()
	if item == null or (item.item_type != ItemResource.ItemType.WEAPON and item.item_type != ItemResource.ItemType.THROWABLE):
		item = get_equipped_offhand()
	if item == null:
		return
	item.durability -= 1
	if item.durability <= 0:
		if character.has_method("_show_action_text"):
			character._show_action_text(item.item_name + " broke!")
		var slot := get_item_slot(item)
		if slot >= 0:
			remove_item(slot)


func use_consumable(slot_index: int) -> bool:
	## Uses a consumable/ammo item from the given slot. Returns true if consumed.
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	var item: ItemResource = items[slot_index]
	if item == null:
		return false
	if item.item_type != ItemResource.ItemType.CONSUMABLE and item.item_type != ItemResource.ItemType.AMMO:
		return false

	var applied := false

	# Heal effect
	if item.heal_amount > 0 and character:
		character.hp = min(character.hp + item.heal_amount, character.max_hp)
		if character.has_method("_update_health_bar"):
			character._update_health_bar()
		if character.has_method("_show_action_text"):
			character._show_action_text("+" + str(item.heal_amount) + " HP")
		applied = true

	# Ammo effect
	if item.ammo_amount > 0 and character:
		character.ammo = min(character.ammo + item.ammo_amount, character.max_ammo)
		if character.has_method("_update_health_bar"):
			character._update_health_bar()
		if character.has_method("_show_action_text"):
			character._show_action_text("+" + str(item.ammo_amount) + " arrows")
		applied = true

	if applied:
		# Unequip if it was equipped (consumables normally shouldn't be)
		if right_hand == item:
			unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
		if left_hand == item:
			unequip_slot(ItemResource.EquipSlot.LEFT_HAND)
		if armor == item:
			unequip_slot(ItemResource.EquipSlot.ARMOR)
		items[slot_index] = null
		return true
	return false


func is_full() -> bool:
	for i in range(MAX_SLOTS):
		if items[i] == null:
			return false
	return true


func slot_count() -> int:
	var count := 0
	for i in range(MAX_SLOTS):
		if items[i] != null:
			count += 1
	return count


func _apply_item_bonuses(item: ItemResource) -> void:
	if not character:
		return
	character.attack_skill += item.attack_bonus
	character.attack_dmg += item.damage_bonus
	character.armor += item.armor_bonus
	character.physical_resistance += item.resistance_bonus


func _remove_item_bonuses(item: ItemResource) -> void:
	if not character:
		return
	character.attack_skill -= item.attack_bonus
	character.attack_dmg -= item.damage_bonus
	character.armor -= item.armor_bonus
	character.physical_resistance -= item.resistance_bonus
