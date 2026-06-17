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

	# Rebuild slot display
	var needed := 0
	if inv.has_method("slot_count"):
		needed = inv.get("MAX_SLOTS") if inv.get("MAX_SLOTS") else 4

	# Only rebuild if slot count changed
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

	# Update text on each slot row
	var items: Array = inv.get("items") if inv.get("items") else []
	var equipped: int = inv.get("equipped_slot") if inv.get("equipped_slot") else -1

	for i in range(needed):
		var row: HBoxContainer = slot_list.get_child(i)
		var name_label: Label = row.get_node("Name")
		var use_btn: Button = row.get_node("Use")
		var equip_btn: Button = row.get_node("Equip")
		var drop_btn: Button = row.get_node("Drop")

		if i < items.size() and items[i] != null:
			var item: ItemResource = items[i]
			var desc := item.item_name
			if item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE:
				desc += " (Dur:" + str(item.durability) + ")"
			name_label.text = desc

			# Use button only for consumables and ammo
			if item.item_type == ItemResource.ItemType.CONSUMABLE or item.item_type == ItemResource.ItemType.AMMO:
				use_btn.visible = true
				use_btn.disabled = false
			else:
				use_btn.visible = false
				use_btn.disabled = true

			# Equip button only for weapons and throwables
			if item.item_type == ItemResource.ItemType.WEAPON or item.item_type == ItemResource.ItemType.THROWABLE:
				equip_btn.visible = true
				equip_btn.disabled = false
				if i == equipped:
					name_label.self_modulate = Color(1, 0.85, 0.3, 1)
					equip_btn.text = "*"
					equip_btn.disabled = true
				else:
					name_label.self_modulate = Color(1, 1, 1, 1)
					equip_btn.text = "E"
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


func _on_use(slot_index: int, active: Node) -> void:
	var inv: Node = active.get_node_or_null("Inventory")
	if inv and inv.has_method("use_consumable"):
		if inv.use_consumable(slot_index):
			if active.has_method("_update_health_bar"):
				active._update_health_bar()


func _on_equip(slot_index: int, active: Node) -> void:
	var inv: Node = active.get_node_or_null("Inventory")
	if inv and inv.has_method("equip"):
		inv.equip(slot_index)
		if active.has_method("_update_health_bar"):
			active._update_health_bar()


func _on_drop(slot_index: int, active: Node) -> void:
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
