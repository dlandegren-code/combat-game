extends Node3D
## Dev tool: the Quiver as worn equipment holding its own arrows — equip, shoot, unequip, drop,
## top up from a bundle, the body showing it, and a save round trip including an old-style
## archer whose arrows were stat-block numbers. Prints [qitem] PASS/FAIL lines and quits.

const HERO := preload("res://scenes/characters/hero.tscn")
const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")
const CharacterDataScript := preload("res://scripts/character_data.gd")

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print("[qitem] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _ready() -> void:
	var hero := HERO.instantiate()
	var model := SIDEKICK.instantiate()
	model.name = "CharacterModel"
	model.position = Vector3(0, -1, 0)
	hero.add_child(model)
	add_child(hero)
	await get_tree().process_frame
	var inv: Node = hero.inventory
	var q: ItemResource = (load("res://resources/items/quiver.tres") as ItemResource).make_instance()
	_check(q.item_type == ItemResource.ItemType.QUIVER and q.ammo_amount == 7 and q.ammo_capacity == 12,
		"template is a quiver of 7/12")
	_check(InventoryComponent_preferred(q) == ItemResource.EquipSlot.BACK, "a quiver goes on the back")
	inv.add_item(q)
	inv.equip(inv.get_item_slot(q))
	_check(inv.back == q, "equip() slings it")
	_check(hero.ammo == 7 and hero.max_ammo == 12, "its arrows are the wearer's (%d/%d)" % [hero.ammo, hero.max_ammo])
	hero.ammo -= 1
	_check(q.ammo_amount == 6, "a shot comes out of the quiver (%d)" % q.ammo_amount)
	hero._update_health_bar()
	await get_tree().process_frame
	var body: Node = hero.get_node("CharacterModel")
	var shown: Node3D = body.get("_quiver")
	_check(shown != null and shown.visible, "the body shows it slung")
	inv.unequip_item(q)
	_check(hero.ammo == 0 and hero.max_ammo == 0 and q.ammo_amount == 6,
		"taken off, the arrows stay in it (%d, wearer %d/%d)" % [q.ammo_amount, hero.ammo, hero.max_ammo])
	hero._update_health_bar()
	await get_tree().process_frame
	_check(shown != null and not shown.visible, "the body stops showing it")
	var bundle: ItemResource = (load("res://resources/items/arrow_bundle.tres") as ItemResource).make_instance()
	bundle.ammo_amount = 10
	inv.add_item(bundle)
	_check(not inv.use_consumable(inv.get_item_slot(bundle)) and bundle.ammo_amount == 10,
		"loose arrows need a quiver to go into")
	inv.equip(inv.get_item_slot(q))
	_check(hero.ammo == 6, "slung again with its 6")
	_check(inv.use_consumable(inv.get_item_slot(bundle)) and hero.ammo == 12 and bundle.ammo_amount == 4
		and inv.get_item_slot(bundle) >= 0, "a bundle tops it up to 12 and keeps the 4 that did not fit")
	_check(q.ammo_amount == 12, "the quiver holds them (%d)" % q.ammo_amount)
	# Save round trip while worn.
	hero.ammo -= 3
	var data = CharacterDataScript.from_combatant(hero)
	var back = CharacterDataScript.from_dict(data.to_dict())
	var bq: ItemResource = back.quiver()
	_check(bq != null and bq.ammo_amount == 9 and bq.ammo_capacity == 12,
		"saved and loaded, it is still slung with 9/12 (%s)" % [str(bq.ammo_amount) + "/" + str(bq.ammo_capacity) if bq else "none"])
	_check(int(back.stats.max_ammo) == 0, "and no loose arrows on the stat block")
	# Dropped: the arrows go with it.
	inv.remove_item(inv.get_item_slot(q))
	_check(inv.back == null and hero.ammo == 0 and q.ammo_amount == 9, "dropped, it takes its 9 arrows")
	# An old save: arrows on the stat block, no quiver.
	var old: Dictionary = data.to_dict()
	old["bag"] = []
	old["equipped"] = {}
	old["stats"]["ammo"] = 5
	old["stats"]["max_ammo"] = 12
	old["ammo"] = 4
	var migrated = CharacterDataScript.from_dict(old)
	var mq: ItemResource = migrated.quiver()
	_check(mq != null and mq.ammo_amount == 4 and mq.ammo_capacity == 12 and int(migrated.stats.max_ammo) == 0,
		"an old save's archer gets a slung quiver with their 4/12")
	var again = CharacterDataScript.from_dict(migrated.to_dict())
	var count := 0
	for it in again.bag:
		if it != null and it.item_type == ItemResource.ItemType.QUIVER:
			count += 1
	_check(count == 1, "and only once (%d quivers)" % count)
	print("[qitem] DONE %d failed" % _fails)
	get_tree().quit()


func InventoryComponent_preferred(item: ItemResource) -> int:
	return (load("res://scripts/inventory_component.gd") as GDScript).preferred_slot(item)
