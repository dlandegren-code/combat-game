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

## --- Display model ---
## When model_path is set, it drives BOTH the equipped (in-hand) and dropped
## (ground) visuals, replacing the old name/type-based lookups. Leave it "" to
## fall back to that legacy behaviour.
@export_group("Display Model")
@export var model_path: String = ""                ## PackedScene or Mesh to show; "" = auto by name/type
@export var model_material_path: String = ""       ## atlas material for meshes shipped without one; "" = embedded
@export var model_scale: float = 0.5               ## longest-dimension target size in tiles (<=0 = leave native scale)
@export var model_hand_position: Vector3 = Vector3.ZERO       ## offset in the hand socket
@export var model_hand_rotation: Vector3 = Vector3.ZERO       ## rotation in the hand socket (degrees)
@export var model_ground_rotation: Vector3 = Vector3(-90, 0, 0)  ## rotation when dropped on the ground (degrees)


func has_model() -> bool:
	return model_path != ""


func instantiate_model() -> Node3D:
	## Build the display node for this item's model: instantiate (PackedScene) or
	## wrap (Mesh), assign the material override if set, recenter on origin and
	## normalize scale. The caller positions/rotates it (hand vs ground). Returns
	## null if model_path is unset or fails to load.
	if model_path == "" or not ResourceLoader.exists(model_path):
		return null
	var loaded: Resource = ResourceLoader.load(model_path, "", ResourceLoader.CACHE_MODE_REUSE)
	var node: Node3D = null
	if loaded is PackedScene:
		node = (loaded as PackedScene).instantiate() as Node3D
	elif loaded is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = loaded as Mesh
		node = mi
	if node == null:
		return null

	var meshes: Array = []
	_collect_model_meshes(node, meshes)

	if model_material_path != "":
		var mat: Material = load(model_material_path)
		if mat:
			for m in meshes:
				(m as MeshInstance3D).material_override = mat

	_center_and_scale_model(node, meshes)
	return node


func _collect_model_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_model_meshes(child, out)


func _center_and_scale_model(node: Node3D, meshes: Array) -> void:
	var aabb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh:
			var maabb: AABB = mi.transform * mi.mesh.get_aabb()
			aabb = maabb if first else aabb.merge(maabb)
			first = false
	if first:
		return
	var offset: Vector3 = aabb.get_center()
	for m in meshes:
		(m as MeshInstance3D).position -= offset
	if model_scale > 0.0:
		var max_dim: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		if max_dim > 0.001:
			var s: float = model_scale / max_dim
			node.scale = Vector3(s, s, s)


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
