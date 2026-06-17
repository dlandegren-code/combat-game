extends Node
## Per-character inventory: holds items, allows equip/drop/pickup

const MAX_SLOTS := 4

@export var starting_item_name: String = ""
@export var starting_item_type: int = ItemResource.ItemType.WEAPON
@export var starting_item_attack: int = 0
@export var starting_item_damage: int = 0
@export var starting_item_durability: int = 10

var items: Array  ## Array[ItemResource], null means empty slot
var equipped_slot: int = -1  ## -1 = no weapon equipped

var character: CharacterBody3D  ## parent character, set on ready

func _ready() -> void:
	character = get_parent() as CharacterBody3D
	items.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		items[i] = null
	if starting_item_name != "":
		var item := ItemResource.new()
		item.item_name = starting_item_name
		item.item_type = starting_item_type
		item.attack_bonus = starting_item_attack
		item.damage_bonus = starting_item_damage
		item.durability = starting_item_durability
		add_item(item)


func add_item(item: ItemResource) -> bool:
	## Returns true if item was added, false if inventory full
	for i in range(MAX_SLOTS):
		if items[i] == null:
			items[i] = item
			# Auto-equip if this is our first weapon and nothing equipped
			if equipped_slot == -1 and (item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE):
				equip(i)
			return true
	return false


func remove_item(slot_index: int) -> ItemResource:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return null
	var item: ItemResource = items[slot_index]
	if item == null:
		return null
	if equipped_slot == slot_index:
		unequip()
	items[slot_index] = null
	return item


func equip(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return
	var item: ItemResource = items[slot_index]
	if item == null:
		return
	if item.item_type != ItemResource.ItemType.WEAPON and item.item_type != ItemResource.ItemType.THROWABLE:
		return

	if equipped_slot != -1:
		unequip()

	equipped_slot = slot_index
	_apply_item_bonuses(item)


func unequip() -> void:
	var item: ItemResource = null
	if equipped_slot >= 0 and equipped_slot < MAX_SLOTS:
		item = items[equipped_slot]
	if item:
		_remove_item_bonuses(item)
	equipped_slot = -1


func has_weapon_equipped() -> bool:
	if equipped_slot < 0:
		return false
	var item: ItemResource = items[equipped_slot]
	return item != null and (item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE)


func get_equipped_weapon() -> ItemResource:
	if equipped_slot < 0:
		return null
	return items[equipped_slot]


func get_equipped_attack_bonus() -> int:
	var item := get_equipped_weapon()
	if item == null:
		return 0
	return item.attack_bonus


func get_equipped_damage_bonus() -> int:
	var item := get_equipped_weapon()
	if item == null:
		return 0
	return item.damage_bonus


func degrade_equipped_weapon() -> void:
	var item := get_equipped_weapon()
	if item == null:
		return
	item.durability -= 1
	if item.durability <= 0:
		if character.has_method("_show_action_text"):
			character._show_action_text(item.item_name + " broke!")
		remove_item(equipped_slot)


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
		# Remove from equipped slot if it was equipped
		if equipped_slot == slot_index:
			unequip()
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
	character.has_weapon = true
	character.weapon_broken = false
	character.weapon_durability = item.durability


func _remove_item_bonuses(item: ItemResource) -> void:
	if not character:
		return
	character.attack_skill -= item.attack_bonus
	character.attack_dmg -= item.damage_bonus
	character.has_weapon = false
	character.weapon_broken = true
	character.weapon_durability = 0
