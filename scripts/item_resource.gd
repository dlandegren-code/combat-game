extends Resource
class_name ItemResource

enum ItemType { WEAPON, THROWABLE, CONSUMABLE, AMMO }

@export var item_name: String = "Item"
@export var item_type: int = ItemType.WEAPON
@export var attack_bonus: int = 0
@export var damage_bonus: int = 0
@export var durability: int = 10
@export var shove_bonus: int = 0
@export var trip_bonus: int = 0
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
	if attack_bonus != 0:
		desc += " ATK+" + str(attack_bonus)
	if damage_bonus != 0:
		desc += " DMG+" + str(damage_bonus)
	if heal_amount > 0:
		desc += " Heal:" + str(heal_amount)
	if ammo_amount > 0:
		desc += " Ammo:" + str(ammo_amount)
	if item_type == ItemType.WEAPON or item_type == ItemType.THROWABLE:
		desc += " Dur:" + str(durability)
	return desc
