extends Node
## Per-character inventory: holds items, allows equip/drop/pickup

## Carry capacity. The inventory panel lays these out five to a row, so multiples of five
## fill the grid tidily; anything else leaves a short bottom row.
const MAX_SLOTS := 10

## Prefix stamped onto a weapon's name when it breaks ("Rusty Sword" -> "Broken Rusty
## Sword"). Safe to mutate: every runtime ItemResource is a per-character .duplicate(), so
## renaming one never touches the shared .tres or another character's copy.
const BROKEN_PREFIX := "Broken "

enum EquipSlot { ANY_HAND, RIGHT_HAND, LEFT_HAND, ARMOR }

## Items this character starts with (ItemResource .tres, assigned in the inspector).
## Each non-null slot is duplicated on load and auto-equipped into its slot.
@export var starting_item_1: ItemResource
@export var starting_item_2: ItemResource
@export var starting_item_3: ItemResource
@export var starting_item_4: ItemResource

var items: Array  ## Array[ItemResource], null means empty slot

## Equipment slots: each holds an ItemResource or null
var right_hand: ItemResource = null
var left_hand: ItemResource = null
var armor: ItemResource = null
var helmet: ItemResource = null
var legs: ItemResource = null

var character: CharacterBody3D  ## parent character, set on ready

func _ready() -> void:
	character = get_parent() as CharacterBody3D
	items.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		items[i] = null
	for template in [starting_item_1, starting_item_2, starting_item_3, starting_item_4]:
		if template == null:
			continue
		# Duplicate so each character has its own instance (durability, bonuses).
		_add_starting_item(template.duplicate())


func _add_starting_item(item: ItemResource) -> void:
	add_item(item)
	# Auto-equip starting items into their intended slot
	if item.can_equip_in(ItemResource.EquipSlot.RIGHT_HAND):
		_equip_to(ItemResource.EquipSlot.RIGHT_HAND, item)
	elif item.can_equip_in(ItemResource.EquipSlot.LEFT_HAND):
		_equip_to(ItemResource.EquipSlot.LEFT_HAND, item)
	elif item.can_equip_in(ItemResource.EquipSlot.ARMOR):
		_equip_to(ItemResource.EquipSlot.ARMOR, item)
	elif item.can_equip_in(ItemResource.EquipSlot.HELMET):
		_equip_to(ItemResource.EquipSlot.HELMET, item)
	elif item.can_equip_in(ItemResource.EquipSlot.LEGS):
		_equip_to(ItemResource.EquipSlot.LEGS, item)


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
	if helmet == item:
		unequip_slot(ItemResource.EquipSlot.HELMET)
	if legs == item:
		unequip_slot(ItemResource.EquipSlot.LEGS)
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
	elif item.item_type == ItemResource.ItemType.HELMET:
		target_slot = ItemResource.EquipSlot.HELMET
	elif item.item_type == ItemResource.ItemType.LEGS:
		target_slot = ItemResource.EquipSlot.LEGS
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


func try_auto_equip_hand(item: ItemResource) -> bool:
	## Arm an empty-handed character with a weapon or shield they just picked up. Returns true
	## if it ended up in a hand.
	##
	## Four gates, each closing off a way this could make a decision the player would not have:
	##
	##   quick to equip     only things drawn in one motion. A shield is strapped on and a
	##                      helmet buckled, so those stay deliberate actions with a real time
	##                      cost — never a side effect of bending down (ItemResource.EQUIP_*).
	##   two-handed         needs both hands, so it may only fill two empty ones. Otherwise
	##                      _equip_to would quietly strip whatever else was held.
	##   a free hand it fits  the hand has to be empty AND legal for this item, so a main-hand
	##                      weapon does not displace anything just because the off-hand is open.
	##   dual-wield         filling the last hand with a SECOND weapon starts a dual-wield, and
	##                      the off-hand strike carries OFFHAND_HIT_PENALTY unless trained. Only
	##                      do that unasked to someone with dual_wield_skill.
	##
	## Routed through equip() rather than _equip_to so hand choice, two-handed conflicts and the
	## bonus/repaint bookkeeping all stay in the one place that already knows about them.
	##
	## Called from the pickup path only, never from add_item: starting inventories flow through
	## add_item as well, and those are authored loadouts that must equip exactly as written
	## (see _add_starting_item).
	if item == null or not item.is_hand_item() or not item.is_quick_to_equip():
		return false

	if item.handedness == ItemResource.Handedness.TWO_HANDED:
		if right_hand != null or left_hand != null:
			return false
	else:
		var free_right: bool = right_hand == null and item.can_equip_in(ItemResource.EquipSlot.RIGHT_HAND)
		var free_left: bool = left_hand == null and item.can_equip_in(ItemResource.EquipSlot.LEFT_HAND)
		if not (free_right or free_left):
			return false
		if _would_start_dual_wield(item) and not _character_dual_wields():
			return false

	var slot: int = get_item_slot(item)
	if slot < 0:
		return false
	equip(slot)
	return right_hand == item or left_hand == item


func _would_start_dual_wield(item: ItemResource) -> bool:
	## True when putting `item` in the free hand would leave a weapon in BOTH hands. A shield in
	## the other hand is not dual-wielding, and neither is a second shield.
	if not _is_weaponlike(item):
		return false
	var held: ItemResource = right_hand if right_hand != null else left_hand
	return held != null and _is_weaponlike(held)


func _is_weaponlike(item: ItemResource) -> bool:
	return item != null and (item.item_type == ItemResource.ItemType.WEAPON \
		or item.item_type == ItemResource.ItemType.THROWABLE)


func _character_dual_wields() -> bool:
	return character != null and character.get("dual_wield_skill") == true


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
		ItemResource.EquipSlot.HELMET:
			item = helmet
			helmet = null
		ItemResource.EquipSlot.LEGS:
			item = legs
			legs = null
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
	elif helmet == item:
		unequip_slot(ItemResource.EquipSlot.HELMET)
	elif legs == item:
		unequip_slot(ItemResource.EquipSlot.LEGS)


func _equip_to(slot: int, item: ItemResource) -> void:
	## Internal: equip item into the given slot, handling 2H conflicts.
	if item == null:
		return
	if not item.can_equip_in(slot):
		return

	# Check for a 2H weapon currently equipped BEFORE we null the reference
	var has_2h_equipped := false
	if right_hand and right_hand.handedness == ItemResource.Handedness.TWO_HANDED:
		has_2h_equipped = true
	if left_hand and left_hand.handedness == ItemResource.Handedness.TWO_HANDED:
		has_2h_equipped = true

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

	# If equipping into a hand and a 2H weapon was equipped, clean both hands
	if has_2h_equipped and (slot == ItemResource.EquipSlot.RIGHT_HAND or slot == ItemResource.EquipSlot.LEFT_HAND):
		unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
		unequip_slot(ItemResource.EquipSlot.LEFT_HAND)

	match slot:
		ItemResource.EquipSlot.RIGHT_HAND:
			right_hand = item
		ItemResource.EquipSlot.LEFT_HAND:
			left_hand = item
		ItemResource.EquipSlot.ARMOR:
			armor = item
		ItemResource.EquipSlot.HELMET:
			helmet = item
		ItemResource.EquipSlot.LEGS:
			legs = item

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


func has_offhand_weapon() -> bool:
	## True when BOTH hands hold a distinct melee weapon (dual-wielding), which grants the
	## free off-hand attack. Excludes shields and 2H weapons (left_hand == right_hand).
	if right_hand == null or left_hand == null or left_hand == right_hand:
		return false
	return right_hand.item_type == ItemResource.ItemType.WEAPON \
		and left_hand.item_type == ItemResource.ItemType.WEAPON


func offhand_only() -> bool:
	## True when the ONLY melee weapon is in the off-hand (main hand empty or non-weapon).
	## Such a lone left-hand strike is resolved with off-hand stats + penalties.
	var main_is_weapon: bool = right_hand != null and right_hand.item_type == ItemResource.ItemType.WEAPON
	var off := get_equipped_offhand()
	return not main_is_weapon and off != null and off.item_type == ItemResource.ItemType.WEAPON


## Per-hand weapon bonuses. Each attack applies only its own hand's weapon — holding a
## second weapon does NOT passively buff the main hand (its payoff is the off-hand attack).
func _weapon_bonus(item: ItemResource, attack: bool) -> int:
	if item == null:
		return 0
	if item.item_type != ItemResource.ItemType.WEAPON and item.item_type != ItemResource.ItemType.THROWABLE:
		return 0
	var bonus: int = item.attack_bonus if attack else item.damage_bonus
	if item.broken:
		bonus -= ItemResource.BROKEN_HIT_PENALTY if attack else ItemResource.BROKEN_DAMAGE_PENALTY
	return bonus


func main_hand_attack_bonus() -> int:
	return _weapon_bonus(get_equipped_weapon(), true)


func main_hand_damage_bonus() -> int:
	return _weapon_bonus(get_equipped_weapon(), false)


func offhand_attack_bonus() -> int:
	return _weapon_bonus(get_equipped_offhand(), true)


func offhand_damage_bonus() -> int:
	return _weapon_bonus(get_equipped_offhand(), false)


func parry_bonus() -> int:
	## Combined parry bonus from BOTH hands, so a sword-and-board guard beats either piece on
	## its own. Unlike the attack/damage bonuses this is not per-hand: a parry is made with
	## whatever you are holding, not with one nominated weapon.
	##
	## A two-handed weapon counts once rather than twice: it occupies both slots as the same
	## object, and get_equipped_offhand() already reports null in that case.
	var total := 0
	for it in [get_equipped_weapon(), get_equipped_offhand()]:
		if it == null:
			continue
		total += it.parry_bonus
		# A ruined guard turns blades no better than it cuts with them.
		if it.broken:
			total -= ItemResource.BROKEN_HIT_PENALTY
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


func forget(item: ItemResource) -> void:
	## Take `item` out of this character's keeping entirely — bag slot and any equipment slot
	## still pointing at it.
	##
	## For looting a corpse. Equipping never removed anything from `items` (see _equip_to), so
	## a carried item can be in the bag AND in a hand at once, and a looter pulling a cleaver
	## off a body has to clear both or the corpse goes on holding a weapon somebody else now
	## owns.
	if item == null:
		return
	for i in range(items.size()):
		if items[i] == item:
			items[i] = null
	if right_hand == item:
		right_hand = null
	if left_hand == item:
		left_hand = null
	if armor == item:
		armor = null
	if helmet == item:
		helmet = null
	if legs == item:
		legs = null


func has_key(key_id: String) -> bool:
	## Whether this character is carrying a key cut for `key_id`. Bag only — a key is not
	## something you hold in your hand, so the equipment slots are not consulted.
	if key_id == "":
		return false
	for item in items:
		if item == null:
			continue
		if item.item_type == ItemResource.ItemType.KEY and item.key_id == key_id:
			return true
	return false


func get_weapon_sound(offhand: bool) -> int:
	## Which swing this hand makes (ItemResource.WeaponSound), or -1 for a hand holding no
	## weapon — an empty fist and a raised shield both cut the air too quietly to be worth a
	## clip, and weapon_sfx.swing() treats -1 as silence.
	var item: ItemResource = get_equipped_offhand() if offhand else get_equipped_weapon()
	if item == null or item.item_type != ItemResource.ItemType.WEAPON:
		return -1
	return item.weapon_sound


func get_equipped_ranged_range() -> int:
	var weapon := get_equipped_weapon()
	if weapon:
		return weapon.ranged_range
	return 0


func get_equipped_throw_range() -> int:
	var weapon := get_equipped_weapon()
	if weapon:
		return weapon.throw_range
	return 0


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
	# Already ruined: there is nothing left to wear down, and without this guard durability
	# would run negative and re-announce the break on every further parry.
	if item.broken:
		return
	item.durability -= 1
	if item.durability > 0:
		return
	_break_item(item)


func _break_item(item: ItemResource) -> void:
	## A weapon that has been parried to pieces. It is NOT destroyed — it is renamed and left
	## in place, so it can still be seen, dropped and picked over. What happens next is the
	## holder's business: Combatant._on_weapon_broke leaves it equipped, Enemy throws it down
	## and draws a spare.
	if character and character.has_method("_show_action_text"):
		character._show_action_text(item.item_name + " broke!")
	item.broken = true
	if not item.item_name.begins_with(BROKEN_PREFIX):
		item.item_name = BROKEN_PREFIX + item.item_name
	if character and character.has_method("_on_weapon_broke"):
		character._on_weapon_broke(item)


func find_weapon_slot() -> int:
	## First bag slot holding a serviceable weapon that is not already in a hand — what to
	## draw when the one you were using breaks. Shields and armour are skipped; a throwable
	## counts, since anything in the fist beats an empty one. Ruined weapons are skipped too,
	## or a goblin would keep drawing junk it had just discarded.
	for i in range(MAX_SLOTS):
		var it: ItemResource = items[i]
		if it == null or it == right_hand or it == left_hand:
			continue
		if it.item_type != ItemResource.ItemType.WEAPON and it.item_type != ItemResource.ItemType.THROWABLE:
			continue
		if it.broken:
			continue
		return i
	return -1


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

	# Heal effect. Handed to Combatant.heal rather than done here: it clamps at max_hp, reports
	# what was actually restored, plays the gesture and blooms. This used to add the hp inline
	# and print the potion's full value even when most of it spilled.
	if item.heal_amount > 0 and character and character.has_method("heal"):
		character.heal(item.heal_amount)
		applied = true

	# Ammo effect
	if item.ammo_amount > 0 and character:
		# A character with no quiver capacity yet gets one the moment they take up ammo.
		# Without this, max_ammo 0 clamps the gain to nothing while `applied` still goes true
		# below — the quiver would be consumed for no arrows at all.
		if character.max_ammo <= 0:
			character.max_ammo = 10
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
	# Weapon attack/damage bonuses are NOT baked into shared stats — they apply per hand at
	# attack time (see Combatant.get_attack_* / get_offhand_*). Only armor is passive.
	character.armor += item.armor_bonus
	character.physical_resistance += item.resistance_bonus
	_notify_equipment_changed()


func _remove_item_bonuses(item: ItemResource) -> void:
	if not character:
		return
	character.armor -= item.armor_bonus
	character.physical_resistance -= item.resistance_bonus
	_notify_equipment_changed()


func _notify_equipment_changed() -> void:
	## Every equip and unequip funnels through the two functions above — _equip_to ends in one,
	## unequip_slot in the other — so this is the one place that sees all of them, AI weapon
	## draws and two-handed swaps included.
	##
	## It was missing entirely: the nameplate shows the armour and resistance totals these
	## lines just changed, and nothing repainted it. Only the inventory PANEL happened to
	## refresh, so equipping from the UI looked correct while every other path went stale. It
	## matters more now that Protection is in — is_guarding() tests for a weapon or shield, so
	## without this, dropping the shield left the guard-zone decal painted on the floor.
	if character.has_method("_update_health_bar"):
		character._update_health_bar()
