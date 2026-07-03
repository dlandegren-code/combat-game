extends "res://scripts/combatant.gd"
## Player character: click-to-move on a grid, click adjacent enemy to attack.
## Shared combat/movement/equipment logic lives in Combatant (combatant.gd).

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW, PICKUP, EQUIP }

var selected_action: int = Action.MOVE
var _tiles_moved: int = 0

var move_indicator: MeshInstance3D

static var _bar_connected := false


func _post_setup() -> void:
	move_indicator = get_parent().get_node_or_null("MoveIndicator")
	if move_indicator:
		move_indicator.visible = false
	if is_player_controlled and not _bar_connected:
		_bar_connected = true
		_connect_action_bar()


func _is_ranged_action(action_type: int) -> bool:
	return action_type == Action.RANGED or action_type == Action.THROW


func enable_turn() -> void:
	if not is_alive:
		return
	_stand_up_if_prone()
	can_act = true
	selected_action = Action.MOVE
	_tiles_moved = 0
	_action_used = Action.MOVE
	_update_action_bar()


func disable_turn() -> void:
	can_act = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hide_indicator()
	_update_action_bar()  # disables buttons in UI


func _process(_delta: float) -> void:
	if not can_act or is_moving:
		return
	_update_cursor()


func _unhandled_input(event: InputEvent) -> void:
	if not can_act or is_moving:
		return
	if event.is_action_pressed("action_1"):
		select_action(Action.MOVE)
	elif event.is_action_pressed("action_2"):
		select_action(Action.ATTACK)
	elif event.is_action_pressed("action_3"):
		select_action(Action.SHOVE)
	elif event.is_action_pressed("action_4"):
		select_action(Action.TRIP)
	elif event.is_action_pressed("action_5"):
		select_action(Action.RANGED)
	elif event.is_action_pressed("action_6"):
		select_action(Action.THROW)
	elif event.is_action_pressed("action_7"):
		select_action(Action.PICKUP)


func _connect_action_bar() -> void:
	var root := get_parent()
	var ab := root.get_node_or_null("ActionBar")
	if not ab:
		return
	for i in range(7):
		var btn: Button = ab.get_node("Panel/Bar/Btn" + str(i + 1))
		if btn:
			btn.toggled.connect(_on_action_btn_toggled.bind(i, btn))
	# Defer initial sync so everyone is ready
	call_deferred("_update_action_bar")


func _on_action_btn_toggled(pressed: bool, index: int, btn: Button) -> void:
	if pressed:
		select_action(index)
	else:
		# Prevent deselecting all (must have one selected)
		var any_on := false
		var root := get_parent()
		var ab := root.get_node_or_null("ActionBar")
		if ab:
			for j in range(6):
				var other: Button = ab.get_node("Panel/Bar/Btn" + str(j + 1))
				if other and other.button_pressed:
					any_on = true
					break
		if not any_on:
			btn.set_pressed_no_signal(true)


func select_action(index: int) -> void:
	selected_action = index
	_update_action_bar()


func _update_action_bar() -> void:
	var root := get_parent()
	var ab := root.get_node_or_null("ActionBar")
	if not ab:
		return
	for i in range(7):
		var btn: Button = ab.get_node("Panel/Bar/Btn" + str(i + 1))
		if btn:
			btn.set_pressed_no_signal(i == selected_action)
			btn.disabled = not can_act


func _update_cursor() -> void:
	var viewport := get_viewport()
	if not viewport:
		_hide_indicator()
		return
	var mouse_pos := viewport.get_mouse_position()
	if viewport.gui_is_dragging():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_hide_indicator()
		return

	var camera := viewport.get_camera_3d()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 100.0
	var space_state := get_world_3d().direct_space_state

	# If using an offensive action, check enemies first
	if selected_action != Action.MOVE:
		var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
		enemy_query.collision_mask = LAYER_ENEMY
		var enemy_result := space_state.intersect_ray(enemy_query)
		if not enemy_result.is_empty():
			var collider: Node = enemy_result.collider
			if collider.has_method("take_damage"):
				if _can_target(collider):
					Input.set_default_cursor_shape(Input.CURSOR_CROSS)
					_hide_indicator()
					return
				# Distinguish "out of resources" from "out of range / blocked"
				match selected_action:
					Action.RANGED:
						if ammo <= 0:
							Input.set_default_cursor_shape(Input.CURSOR_HELP)
						else:
							Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
					Action.THROW:
						if not _has_usable_weapon():
							Input.set_default_cursor_shape(Input.CURSOR_HELP)
						else:
							Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
					_:
						Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
				_hide_indicator()
				return

	# Check ground for move (always available)
	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = LAYER_GROUND
	var result := space_state.intersect_ray(ground_query)
	if not result.is_empty():
		var clicked: Vector3 = result.position
		clicked.y = position.y
		var grid_pos := _snap_to_grid(clicked)
		if _can_move() and _is_in_range(grid_pos) and not _is_tile_occupied_by_others(grid_pos, self):
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			_show_indicator(grid_pos)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
			_hide_indicator()
		return

	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hide_indicator()


func _show_indicator(at: Vector3) -> void:
	if move_indicator:
		move_indicator.position = Vector3(at.x, 0.16, at.z)
		move_indicator.visible = true


func _hide_indicator() -> void:
	if move_indicator:
		move_indicator.visible = false


func _input(event: InputEvent) -> void:
	if not can_act or is_moving:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)


func _handle_click(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	var space_state := get_world_3d().direct_space_state

	# Pickup action: scan for nearby ground items
	if selected_action == Action.PICKUP:
		_play_attack_anim("pick-up")
		_do_pickup()
		is_moving = true
		target_position = position
		return

	# Offensive actions: check if we clicked an enemy
	if selected_action != Action.MOVE:
		var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
		enemy_query.collision_mask = LAYER_ENEMY
		var enemy_result := space_state.intersect_ray(enemy_query)

		if not enemy_result.is_empty():
			var collider: Node = enemy_result.collider
			if collider.has_method("take_damage") and _can_target(collider):
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				_hide_indicator()
				_face_target(collider)
				_action_used = selected_action
				match selected_action:
					Action.ATTACK:
						_play_attack_anim("attack-melee-right")
						collider.take_damage(_get_effective_attack_dmg(), _get_effective_attack_skill(), Action.ATTACK)
					Action.SHOVE:
						_play_attack_anim("attack-kick-right")
						_try_shove(collider)
					Action.TRIP:
						_play_attack_anim("attack-kick-right")
						_try_trip(collider)
					Action.RANGED:
						_play_attack_anim("holding-both-shoot")
						_do_ranged_attack(collider)
					Action.THROW:
						_play_attack_anim("attack-melee-right")
						_do_throw_attack(collider)
				is_moving = true
				target_position = position
				return

	# Move on ground
	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = LAYER_GROUND
	var result := space_state.intersect_ray(ground_query)

	if not result.is_empty():
		var clicked: Vector3 = result.position
		clicked.y = position.y
		var grid_pos := _snap_to_grid(clicked)
		if _can_move() and _is_in_range(grid_pos) and not _is_tile_occupied_by_others(grid_pos, self):
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			_hide_indicator()
			_tiles_moved = int(abs(grid_pos.x - position.x) + abs(grid_pos.z - position.z))
			_action_used = Action.MOVE
			target_position = grid_pos
			is_moving = true


func _can_target(collider: Node) -> bool:
	var dist: float = abs(collider.position.x - position.x) + abs(collider.position.z - position.z)
	match selected_action:
		Action.ATTACK, Action.SHOVE, Action.TRIP:
			return dist <= GRID_SIZE * 1.5
		Action.RANGED:
			if ammo <= 0:
				return false
			return dist <= _get_effective_ranged_range() * GRID_SIZE and _has_line_of_sight(collider)
		Action.THROW:
			if not _has_usable_weapon():
				return false
			return dist <= _get_effective_throw_range() * GRID_SIZE and _has_line_of_sight(collider)
	return false


func _do_ranged_attack(target: Node) -> void:
	if ammo <= 0:
		_show_action_text("No ammo!")
		return
	ammo -= 1
	_update_health_bar()
	target.take_damage(attack_dmg, ranged_skill, Action.RANGED)
	_show_action_text(str(ammo) + " arrows left")


func _do_throw_attack(target: Node) -> void:
	var thrown_item: ItemResource = null
	if inventory and inventory.has_method("get_equipped_weapon"):
		thrown_item = inventory.get_equipped_weapon()
	if thrown_item == null:
		_show_action_text("No weapon to throw!")
		return

	var throw_dir: Vector3 = (target.position - position)
	throw_dir.y = 0
	if throw_dir.length() < 0.01:
		throw_dir = Vector3.RIGHT
	throw_dir = throw_dir.normalized()

	var defended: bool = target.take_damage(attack_dmg, throw_skill, Action.THROW)
	# Remove the thrown weapon from the character's equipment
	if inventory and inventory.has_method("unequip_slot"):
		inventory.unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
	var slot := -1
	if inventory and inventory.has_method("get_item_slot"):
		slot = inventory.get_item_slot(thrown_item)
	if slot >= 0 and inventory and inventory.has_method("remove_item"):
		inventory.remove_item(slot)
	_update_health_bar()

	if defended:
		_show_action_text("Throw missed!")
		var land_pos: Vector3 = target._snap_to_grid(target.position + throw_dir * (randi_range(2, 4) * GRID_SIZE))
		_spawn_ground_item(thrown_item, Vector3(land_pos.x, 0.2, land_pos.z))
	else:
		_show_action_text("Weapon thrown!")
		var scatter_angle := randf_range(0, TAU)
		var scatter_dist := randf_range(1.0, 3.0) * GRID_SIZE
		var scatter_offset := Vector3(cos(scatter_angle), 0, sin(scatter_angle)) * scatter_dist
		var land_pos: Vector3 = target._snap_to_grid(target.position + scatter_offset)
		land_pos = _avoid_overlap(land_pos, target)
		_spawn_ground_item(thrown_item, Vector3(land_pos.x, 0.2, land_pos.z))


func _spawn_ground_item(item: ItemResource, at: Vector3) -> void:
	var gi := MeshInstance3D.new()
	gi.name = "GroundItem"
	gi.set_script(load("res://scripts/ground_item.gd"))
	gi.position = at
	gi.item_resource = item
	get_parent().add_child(gi)
	# Defer visual so the node is fully in the tree
	gi.call_deferred("_apply_visual")


func _avoid_overlap(tile: Vector3, exclude: Node) -> Vector3:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == exclude or not is_instance_valid(c):
			continue
		if c._snap_to_grid(c.position).distance_to(tile) < 0.5:
			return c._snap_to_grid(c.position)
	return tile


func _do_pickup() -> void:
	_action_used = Action.PICKUP
	var picked_up := false
	for gi in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(gi):
			continue
		var gi_node: Node3D = gi as Node3D
		if not gi_node:
			continue
		var dist: float = abs(gi_node.position.x - position.x) + abs(gi_node.position.z - position.z)
		if dist > GRID_SIZE * 2:
			continue
		var item: ItemResource = gi.get("item_resource")
		if not item:
			continue
		# Ammo and consumables are used immediately, not stored
		if item.item_type == ItemResource.ItemType.AMMO or item.item_type == ItemResource.ItemType.CONSUMABLE:
			var applied := false
			if item.heal_amount > 0:
				hp = min(hp + item.heal_amount, max_hp)
				_show_action_text("+" + str(item.heal_amount) + " HP")
				applied = true
			if item.ammo_amount > 0:
				if max_ammo <= 0:
					max_ammo = 10
				ammo = min(ammo + item.ammo_amount, max_ammo)
				_show_action_text("+" + str(item.ammo_amount) + " arrows")
				applied = true
			if applied:
				_update_health_bar()
				gi.queue_free()
				picked_up = true
				break
			continue
		if inventory and inventory.has_method("add_item"):
			if inventory.add_item(item):
				_show_action_text("Picked up " + item.item_name)
				gi.queue_free()
				picked_up = true
				break
	if not picked_up:
		if not inventory or inventory.is_full():
			_show_action_text("Inventory full!")
		else:
			_show_action_text("Nothing to pick up")
	_update_health_bar()


func equip_weapon(slot_index: int) -> void:
	## Swapping equipped weapon/shield is a full action.
	if not can_act or is_moving:
		return
	if not inventory or not inventory.has_method("equip"):
		return
	inventory.equip(slot_index)
	var new_item: ItemResource = null
	if inventory.has_method("get_equipped_weapon"):
		new_item = inventory.get_equipped_weapon()
	var item_name := "nothing"
	if new_item:
		item_name = new_item.item_name
	_show_action_text("Equipped " + item_name)
	_update_health_bar()
	_action_used = Action.EQUIP
	is_moving = true
	target_position = position


func unequip_item(item: ItemResource) -> void:
	## Unequip an already-equipped item. Costs a full action.
	if not can_act or is_moving:
		return
	if not inventory or not inventory.has_method("unequip_item"):
		return
	var was_equipped := false
	if inventory.get("right_hand") == item or inventory.get("left_hand") == item or inventory.get("armor") == item:
		was_equipped = true
	if not was_equipped:
		return
	inventory.unequip_item(item)
	_show_action_text("Unequipped " + item.item_name)
	_update_health_bar()
	_action_used = Action.EQUIP
	is_moving = true
	target_position = position


func _get_effective_ranged_range() -> int:
	if inventory and inventory.has_method("get_equipped_ranged_range"):
		var item_range: int = inventory.get_equipped_ranged_range()
		if item_range > 0:
			return item_range
	return ranged_range


func _get_effective_throw_range() -> int:
	if inventory and inventory.has_method("get_equipped_throw_range"):
		var item_range: int = inventory.get_equipped_throw_range()
		if item_range > 0:
			return item_range
	return throw_range


func _get_effective_attack_skill() -> int:
	if inventory and inventory.has_method("get_equipped_attack_bonus"):
		return attack_skill + inventory.get_equipped_attack_bonus()
	return attack_skill


func _get_effective_attack_dmg() -> int:
	if inventory and inventory.has_method("get_equipped_damage_bonus"):
		return attack_dmg + inventory.get_equipped_damage_bonus()
	return attack_dmg


func _try_shove(target: Node) -> int:
	var pushed := super._try_shove(target)
	if pushed < 0:
		_show_action_text("Shove blocked!")
	else:
		_show_action_text("Shoved " + str(pushed) + "!")
	return pushed


func _try_trip(target: Node) -> bool:
	var hit := super._try_trip(target)
	_show_action_text("Tripped!" if hit else "Trip blocked!")
	return hit


func _can_move() -> bool:
	return not is_prone


func _is_in_range(target: Vector3) -> bool:
	var dist: float = abs(target.x - position.x) + abs(target.z - position.z)
	return dist <= move_range * GRID_SIZE


func _on_move_complete() -> void:
	can_act = false
	var cost := 0
	match _action_used:
		Action.MOVE:
			cost = move_cost_per_tile
		Action.ATTACK:
			cost = attack_cost
		Action.SHOVE:
			cost = shove_cost
		Action.TRIP:
			cost = trip_cost
		Action.RANGED:
			cost = ranged_cost
		Action.THROW:
			cost = throw_cost
		Action.PICKUP:
			cost = 1
		Action.EQUIP:
			cost = equip_cost
	cost = max(cost, 1)
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.turn_done(cost)
