extends CanvasLayer
## Displays the active character's equipped slots: Right Hand, Left Hand, Armor

var slot_list: VBoxContainer
var title_label: Label

func _ready() -> void:
	slot_list = get_node("Panel/SlotList")
	title_label = get_node("Panel/Title")


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if not combat_mgr:
		_clear()
		return

	var active: Node = combat_mgr.current_combatant
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		_clear()
		return

	var inv: Node = active.get_node_or_null("Inventory")
	if not inv:
		_clear()
		return

	title_label.text = active.get("character_name") + " - Equipment"

	var main: ItemResource = inv.get("right_hand")
	var off: ItemResource = inv.get("left_hand")
	var armor_item: ItemResource = inv.get("armor")
	var two_handed := main != null and main == off

	_ensure_rows(3)

	_set_row(0, "Right Hand", _hand_desc(main, two_handed))
	_set_row(1, "Left Hand", _hand_desc(off, two_handed, true))
	_set_row(2, "Armor", _armor_desc(armor_item))


func _ensure_rows(count: int) -> void:
	while slot_list.get_child_count() < count:
		var row := HBoxContainer.new()
		var slot_label := Label.new()
		slot_label.name = "Slot"
		slot_label.custom_minimum_size = Vector2(70, 0)
		slot_label.add_theme_font_size_override("font_size", 12)
		row.add_child(slot_label)

		var item_label := Label.new()
		item_label.name = "Item"
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.add_theme_font_size_override("font_size", 12)
		row.add_child(item_label)

		var stat_label := Label.new()
		stat_label.name = "Stat"
		stat_label.add_theme_font_size_override("font_size", 12)
		row.add_child(stat_label)

		var drop_btn := Button.new()
		drop_btn.name = "Drop"
		drop_btn.text = "Drop"
		drop_btn.custom_minimum_size = Vector2(40, 0)
		drop_btn.add_theme_font_size_override("font_size", 10)
		drop_btn.pressed.connect(_on_unequip.bind(slot_list.get_child_count()))
		row.add_child(drop_btn)

		slot_list.add_child(row)


func _set_row(index: int, slot_name: String, data: Dictionary) -> void:
	var row: HBoxContainer = slot_list.get_child(index)
	row.get_node("Slot").text = slot_name + ":"
	row.get_node("Item").text = data.get("name", "(empty)")
	row.get_node("Stat").text = data.get("stat", "")
	var drop_btn: Button = row.get_node("Drop")
	var has_item: bool = data.get("name", "(empty)") != "(empty)"
	drop_btn.disabled = not has_item


func _hand_desc(item: ItemResource, two_handed: bool, offhand: bool = false) -> Dictionary:
	if item == null:
		return { "name": "(empty)", "stat": "" }
	var desc := item.item_name
	if two_handed:
		desc += " [2H]"
	elif offhand:
		desc += " [LH]"
	else:
		desc += " [RH]"
	var stat := ""
	if item.attack_bonus != 0 or item.damage_bonus != 0:
		stat = "ATK+" + str(item.attack_bonus) + " DMG+" + str(item.damage_bonus)
	if item.is_shield or item.item_type == ItemResource.ItemType.SHIELD:
		stat = "Shield"
	if item.durability > 0:
		stat += " Dur:" + str(item.durability)
	return { "name": desc, "stat": stat }


func _armor_desc(item: ItemResource) -> Dictionary:
	if item == null:
		return { "name": "(empty)", "stat": "" }
	var stat := "Armor+" + str(item.armor_bonus)
	if item.resistance_bonus != 0:
		stat += " Res+" + str(item.resistance_bonus) + "%"
	return { "name": item.item_name, "stat": stat }


func _on_unequip(slot_index: int) -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if not combat_mgr:
		return
	var active: Node = combat_mgr.current_combatant
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		return
	var inv: Node = active.get_node_or_null("Inventory")
	if not inv:
		return

	var item: ItemResource = null
	match slot_index:
		0:  # Right Hand
			item = inv.get("right_hand")
			if item and active.has_method("unequip_item"):
				active.unequip_item(item)
		1:  # Left Hand
			item = inv.get("left_hand")
			if item and active.has_method("unequip_item"):
				active.unequip_item(item)
		2:  # Armor
			item = inv.get("armor")
			if item and active.has_method("unequip_item"):
				active.unequip_item(item)


func _clear() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	title_label.text = "Equipment"
