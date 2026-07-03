extends CanvasLayer
## Displays the active player-controlled character's inventory on the right side

var slot_list: VBoxContainer
var title_label: Label

func _ready() -> void:
	slot_list = get_node("Panel/SlotList")
	title_label = get_node("Panel/Title")


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	# Find the active player-controlled combatant
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if not combat_mgr:
		_clear()
		return

	var active: Node = combat_mgr.current_combatant
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		_clear()
		return

	var inv: Node = active.get_node_or_null("Inventory")
	if not inv or not inv.has_method("slot_count"):
		_clear()
		return

	title_label.text = active.get("character_name") + " - Inventory"

	# Rebuild slot display if slot count changed
	var needed := 0
	if inv.has_method("slot_count"):
		needed = inv.get("MAX_SLOTS") if inv.get("MAX_SLOTS") else 4

	if slot_list.get_child_count() != needed:
		_clear()
		for i in range(needed):
			var row := HBoxContainer.new()
			row.name = "Slot" + str(i)

			var name_label := Label.new()
			name_label.name = "Name"
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.add_theme_font_size_override("font_size", 12)
			row.add_child(name_label)

			var use_btn := Button.new()
			use_btn.name = "Use"
			use_btn.text = "U"
			use_btn.custom_minimum_size = Vector2(24, 0)
			use_btn.set_meta("slot_index", i)
			use_btn.pressed.connect(_on_use.bind(i, active))
			row.add_child(use_btn)

			var equip_btn := Button.new()
			equip_btn.name = "Equip"
			equip_btn.text = "E"
			equip_btn.custom_minimum_size = Vector2(24, 0)
			equip_btn.set_meta("slot_index", i)
			equip_btn.pressed.connect(_on_equip.bind(i, active))
			row.add_child(equip_btn)

			var drop_btn := Button.new()
			drop_btn.name = "Drop"
			drop_btn.text = "D"
			drop_btn.custom_minimum_size = Vector2(24, 0)
			drop_btn.set_meta("slot_index", i)
			drop_btn.pressed.connect(_on_drop.bind(i, active))
			row.add_child(drop_btn)

			slot_list.add_child(row)

	var items: Array = inv.get("items") if inv.get("items") else []
	var main_hand: ItemResource = inv.get("right_hand") if inv.get("right_hand") else null
	var off_hand: ItemResource = inv.get("left_hand") if inv.get("left_hand") else null
	var armor_item: ItemResource = inv.get("armor") if inv.get("armor") else null

	for i in range(needed):
		var row: HBoxContainer = slot_list.get_child(i)
		var name_label: Label = row.get_node("Name")
		var use_btn: Button = row.get_node("Use")
		var equip_btn: Button = row.get_node("Equip")
		var drop_btn: Button = row.get_node("Drop")

		if i < items.size() and items[i] != null:
			var item: ItemResource = items[i]
			var desc := item.item_name
			if item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE or item.item_type == ItemResource.ItemType.SHIELD:
				desc += " (Dur:" + str(item.durability) + ")"
			if item.item_type == ItemResource.ItemType.ARMOR:
				desc += " (Armor:" + str(item.armor_bonus) + ")"
			if item.handedness == ItemResource.Handedness.TWO_HANDED:
				desc += " 2H"
			if item.is_shield:
				desc += " [Shield]"
			if item.parry_ranged:
				desc += " [ParryRanged]"
			if item.dodge_ranged:
				desc += " [DodgeRanged]"

			# Show which slot this item is equipped in
			if item == main_hand and item == off_hand:
				desc += " [2H]"
			elif item == main_hand:
				desc += " [RH]"
			elif item == off_hand:
				desc += " [LH]"
			elif item == armor_item:
				desc += " [Armor]"

			name_label.text = desc

			# Use button only for consumables and ammo
			if item.item_type == ItemResource.ItemType.CONSUMABLE or item.item_type == ItemResource.ItemType.AMMO:
				use_btn.visible = true
				use_btn.disabled = false
			else:
				use_btn.visible = false
				use_btn.disabled = true

			# Equip/unequip button for weapons, throwables, shields, and armor
			if item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE or item.item_type == ItemResource.ItemType.SHIELD or item.item_type == ItemResource.ItemType.ARMOR:
				equip_btn.visible = true
				if item == main_hand or item == off_hand or item == armor_item:
					name_label.self_modulate = Color(1, 0.85, 0.3, 1)
					equip_btn.text = "U"
					equip_btn.disabled = false
				else:
					name_label.self_modulate = Color(1, 1, 1, 1)
					equip_btn.text = "E"
					equip_btn.disabled = false
			else:
				equip_btn.visible = false
				equip_btn.disabled = true

			drop_btn.disabled = false
		else:
			name_label.text = "(empty)"
			name_label.self_modulate = Color(0.5, 0.5, 0.5, 1)
			use_btn.visible = false
			use_btn.disabled = true
			equip_btn.visible = false
			equip_btn.disabled = true
			drop_btn.disabled = true
			equip_btn.text = "E"


func _clear() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	title_label.text = "Inventory"


func _current_player() -> Node:
	## The combatant the panel is currently showing. Button callbacks resolve this
	## fresh instead of trusting the combatant bound when the rows were last built
	## (which goes stale as turns advance without the slot count changing).
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if not combat_mgr:
		return null
	var cur: Node = combat_mgr.current_combatant
	if not cur or not is_instance_valid(cur) or not cur.get("is_player_controlled"):
		return null
	return cur


func _on_use(slot_index: int, _bound: Node) -> void:
	var active := _current_player()
	if not active:
		return
	var inv: Node = active.get_node_or_null("Inventory")
	if inv and inv.has_method("use_consumable"):
		if inv.use_consumable(slot_index):
			if active.has_method("_update_health_bar"):
				active._update_health_bar()


func _on_equip(slot_index: int, _bound: Node) -> void:
	## Equipping/unequipping is a full combat action; it must be the active character's turn.
	var active := _current_player()
	if not active:
		return
	var inv: Node = active.get_node_or_null("Inventory")
	if not inv or not inv.has_method("unequip_item"):
		return
	var item: ItemResource = inv.items[slot_index]
	if item == null:
		return
	var is_equipped := false
	if item == inv.get("right_hand") or item == inv.get("left_hand") or item == inv.get("armor"):
		is_equipped = true
	if is_equipped:
		if active.has_method("unequip_item"):
			active.unequip_item(item)
		elif active.has_method("_update_health_bar"):
			active._update_health_bar()
	else:
		if active.has_method("equip_weapon"):
			active.equip_weapon(slot_index)
		elif active.has_method("_update_health_bar"):
			active._update_health_bar()


func _on_drop(slot_index: int, _bound: Node) -> void:
	var active := _current_player()
	if not active:
		return
	var inv: Node = active.get_node_or_null("Inventory")
	if not inv or not inv.has_method("remove_item"):
		return

	var item: ItemResource = inv.remove_item(slot_index)
	if item == null:
		return

	# Spawn ground item near the character
	var drop_pos: Vector3 = active.position + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1))
	if active.has_method("_spawn_ground_item"):
		active._spawn_ground_item(item, drop_pos)
	if active.has_method("_update_health_bar"):
		active._update_health_bar()
