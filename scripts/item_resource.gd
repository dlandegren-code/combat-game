extends Resource
class_name ItemResource

enum ItemType { WEAPON, THROWABLE, CONSUMABLE, AMMO, SHIELD, ARMOR }

enum EquipSlot {
	ANY_HAND,   ## Can go in either hand (1-handed weapons)
	RIGHT_HAND, ## Main hand only
	LEFT_HAND,  ## Offhand only (shields, offhand weapons)
	ARMOR       ## Armor slot, not hands
}

enum Handedness { ONE_HANDED, TWO_HANDED }

@export var item_name: String = "Item"
@export var item_type: int = ItemType.WEAPON
@export var equip_slot: int = EquipSlot.ANY_HAND
@export var handedness: int = Handedness.ONE_HANDED

@export var attack_bonus: int = 0
@export var damage_bonus: int = 0
@export var durability: int = 10
@export var shove_bonus: int = 0
@export var trip_bonus: int = 0
@export var ranged_range: int = 0   ## max tiles when used as ranged weapon; 0 = use character stat
@export var throw_range: int = 0    ## max tiles when thrown; 0 = use character stat

## Defense properties granted while this item is equipped
@export var is_shield: bool = false    ## Allows parrying ranged attacks
@export var parry_ranged: bool = false ## Skill/artifact that allows parrying ranged attacks
@export var dodge_ranged: bool = false ## Skill/artifact that allows dodging ranged attacks

## Armor stats (only relevant for ARMOR type)
@export var armor_bonus: int = 0
@export var resistance_bonus: int = 0  ## percentage 0-100

## Consumable effects (only relevant for CONSUMABLE and AMMO types)
@export var heal_amount: int = 0       ## HP restored on use (CONSUMABLE)
@export var ammo_amount: int = 0       ## Ammo restored on use (AMMO)

func get_description() -> String:
	var desc := item_name
	match item_type:
		ItemType.WEAPON:
			desc += " (Weapon)"
		ItemType.THROWABLE:
			desc += " (Throwable)"
		ItemType.CONSUMABLE:
			desc += " (Consumable)"
		ItemType.AMMO:
			desc += " (Ammo)"
		ItemType.SHIELD:
			desc += " (Shield)"
		ItemType.ARMOR:
			desc += " (Armor)"

	match handedness:
		Handedness.TWO_HANDED:
			desc += " 2H"
		Handedness.ONE_HANDED:
			if item_type == ItemType.WEAPON:
				desc += " 1H"

	if attack_bonus != 0:
		desc += " ATK+" + str(attack_bonus)
	if damage_bonus != 0:
		desc += " DMG+" + str(damage_bonus)
	if armor_bonus != 0:
		desc += " Armor+" + str(armor_bonus)
	if resistance_bonus != 0:
		desc += " Res+" + str(resistance_bonus) + "%"
	if heal_amount > 0:
		desc += " Heal:" + str(heal_amount)
	if ammo_amount > 0:
		desc += " Ammo:" + str(ammo_amount)
	if ranged_range > 0:
		desc += " RngRange:" + str(ranged_range)
	if throw_range > 0:
		desc += " ThrowRange:" + str(throw_range)
	if item_type == ItemType.WEAPON or item_type == ItemType.THROWABLE or item_type == ItemType.SHIELD:
		desc += " Dur:" + str(durability)
	if is_shield:
		desc += " [Shield]"
	if parry_ranged:
		desc += " [ParryRanged]"
	if dodge_ranged:
		desc += " [DodgeRanged]"
	return desc


func is_hand_item() -> bool:
	return item_type == ItemType.WEAPON or item_type == ItemType.THROWABLE or item_type == ItemType.SHIELD


func can_equip_in(slot: int) -> bool:
	match slot:
		EquipSlot.RIGHT_HAND:
			return is_hand_item() and equip_slot != EquipSlot.LEFT_HAND and equip_slot != EquipSlot.ARMOR
		EquipSlot.LEFT_HAND:
			return is_hand_item() and equip_slot != EquipSlot.RIGHT_HAND and equip_slot != EquipSlot.ARMOR
		EquipSlot.ARMOR:
			return item_type == ItemType.ARMOR or equip_slot == EquipSlot.ARMOR
	return false
