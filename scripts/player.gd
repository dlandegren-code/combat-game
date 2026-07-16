extends "res://scripts/combatant.gd"
## Player character: click-to-move on a grid, click an enemy to use the selected
## ability. Actions are driven by the `abilities` list (see scripts/abilities/):
## the action bar, targeting, cursor and turn cost all read from it, so adding a
## new player skill is just adding an Ability to _build_abilities().

# Slot order of the action bar / abilities list. Values are indices into `abilities`.
enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW, PICKUP }

const MoveAbilityScript := preload("res://scripts/abilities/move_ability.gd")
const MeleeAttackAbilityScript := preload("res://scripts/abilities/melee_attack_ability.gd")
const ShoveAbilityScript := preload("res://scripts/abilities/shove_ability.gd")
const TripAbilityScript := preload("res://scripts/abilities/trip_ability.gd")
const RangedAbilityScript := preload("res://scripts/abilities/ranged_ability.gd")
const ThrowAbilityScript := preload("res://scripts/abilities/throw_ability.gd")
const PickupAbilityScript := preload("res://scripts/abilities/pickup_ability.gd")

var selected_action: int = Action.MOVE

var move_indicator: MeshInstance3D

static var _bar_connected := false


func _post_setup() -> void:
	_build_abilities()
	move_indicator = get_parent().get_node_or_null("MoveIndicator")
	if move_indicator:
		move_indicator.visible = false
	if is_player_controlled and not _bar_connected:
		_bar_connected = true
		_connect_action_bar()


func _build_abilities() -> void:
	# Order must match the Action enum / action-bar buttons Btn1..Btn7.
	abilities = [
		MoveAbilityScript.new(),
		MeleeAttackAbilityScript.new(),
		ShoveAbilityScript.new(),
		TripAbilityScript.new(),
		RangedAbilityScript.new(),
		ThrowAbilityScript.new(),
		PickupAbilityScript.new(),
	]


# Player attacks apply equipped-weapon bonuses on top of the base stats.
func get_attack_skill() -> int:
	if inventory and inventory.has_method("get_equipped_attack_bonus"):
		return attack_skill + inventory.get_equipped_attack_bonus()
	return attack_skill


func get_attack_damage() -> int:
	if inventory and inventory.has_method("get_equipped_damage_bonus"):
		return attack_dmg + inventory.get_equipped_damage_bonus()
	return attack_dmg


func enable_turn() -> void:
	if not is_alive:
		return
	_stand_up_if_prone()
	can_act = true
	selected_action = Action.MOVE
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
	for i in range(abilities.size()):
		if event.is_action_pressed("action_" + str(i + 1)):
			select_action(i)
			return


func _connect_action_bar() -> void:
	var root := get_parent()
	var ab := root.get_node_or_null("ActionBar")
	if not ab:
		return
	for i in range(abilities.size()):
		var btn: Button = ab.get_node_or_null("Panel/Bar/Btn" + str(i + 1))
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
			for j in range(abilities.size()):
				var other: Button = ab.get_node_or_null("Panel/Bar/Btn" + str(j + 1))
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
	for i in range(abilities.size()):
		var btn: Button = ab.get_node_or_null("Panel/Bar/Btn" + str(i + 1))
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

	var ability = abilities[selected_action]

	# Enemy-targeted abilities: check enemies first for aim feedback.
	if ability.targets_enemy():
		var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
		enemy_query.collision_mask = LAYER_ENEMY
		var enemy_result := space_state.intersect_ray(enemy_query)
		if not enemy_result.is_empty():
			var collider: Node = enemy_result.collider
			if collider.has_method("take_damage"):
				if ability.can_target(self, collider):
					Input.set_default_cursor_shape(Input.CURSOR_CROSS)
					_hide_indicator()
					return
				# Distinguish "out of resources" from "out of range / blocked"
				if ability.unavailable_reason(self) == "resource":
					Input.set_default_cursor_shape(Input.CURSOR_HELP)
				else:
					Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
				_hide_indicator()
				return

	# Ground = move (the fallback action, always available).
	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = LAYER_GROUND
	var result := space_state.intersect_ray(ground_query)
	if not result.is_empty():
		var clicked: Vector3 = result.position
		clicked.y = position.y
		var grid_pos := _snap_to_grid(clicked)
		# Selected tile-ability other than Move (e.g. Pick Up): its own cursor feedback.
		if ability.targets_tile() and selected_action != Action.MOVE:
			if ability.can_target(self, grid_pos):
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
			_hide_indicator()
			return
		if abilities[Action.MOVE].can_target(self, grid_pos):
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

	var ability = abilities[selected_action]

	# Self-targeted abilities (pickup): fire immediately, ends the turn in place.
	if ability.targets_self():
		_begin_action(selected_action)
		ability.execute(self, null)
		_end_action_in_place()
		return

	# Enemy-targeted abilities: use it if we clicked a valid enemy target.
	if ability.targets_enemy():
		var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
		enemy_query.collision_mask = LAYER_ENEMY
		var enemy_result := space_state.intersect_ray(enemy_query)
		if not enemy_result.is_empty():
			var collider: Node = enemy_result.collider
			if collider.has_method("take_damage") and ability.can_target(self, collider):
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				_hide_indicator()
				_face_target(collider)
				_begin_action(selected_action)
				ability.execute(self, collider)
				_end_action_in_place()
				return

	# Ground click. A selected tile-ability other than Move (e.g. Pick Up) acts on the
	# clicked tile if valid; otherwise fall back to Move (always available).
	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = LAYER_GROUND
	var result := space_state.intersect_ray(ground_query)
	if not result.is_empty():
		var clicked: Vector3 = result.position
		clicked.y = position.y
		var grid_pos := _snap_to_grid(clicked)
		if ability.targets_tile() and selected_action != Action.MOVE and ability.can_target(self, grid_pos):
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			_hide_indicator()
			_begin_action(selected_action)
			ability.execute(self, grid_pos)
			_end_action_in_place()
			return
		var move_ability = abilities[Action.MOVE]
		if move_ability.can_target(self, grid_pos):
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			_hide_indicator()
			_begin_action(Action.MOVE)
			move_ability.execute(self, grid_pos)  # sets target_position + is_moving


func _begin_action(slot: int) -> void:
	## Record the time-unit cost for the action being started this turn.
	_pending_cost = max(1, abilities[slot].get_cost(self))


func _end_action_in_place() -> void:
	## Instant (non-move) actions play in place, then the turn ends on arrival.
	is_moving = true
	target_position = position


func _do_ranged_attack(target: Node) -> void:
	if ammo <= 0:
		_show_action_text("No ammo!")
		return
	ammo -= 1
	_update_health_bar()
	target.take_damage(attack_dmg, ranged_skill, true)
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

	var defended: bool = target.take_damage(attack_dmg, throw_skill, true)
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


## Manhattan reach (in tiles) for grabbing a ground item: 1 = adjacent square (or
## the hero's own tile). Diagonals are 2 tiles of Manhattan distance, so excluded.
const PICKUP_REACH_TILES := 1


func _pickup_at(tile: Vector3) -> Node:
	## The ground item a click at `tile` should grab: the reachable pickup nearest the
	## clicked square (so clicking the warhammer grabs it, not whatever's closest to the
	## hero). Returns null if no pickup lies within reach.
	var best: Node = null
	var best_d := INF
	for gi in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(gi):
			continue
		var gi_node := gi as Node3D
		if not gi_node:
			continue
		var reach: float = abs(gi_node.position.x - position.x) + abs(gi_node.position.z - position.z)
		if reach > PICKUP_REACH_TILES * GRID_SIZE:
			continue
		var d: float = abs(gi_node.position.x - tile.x) + abs(gi_node.position.z - tile.z)
		if d < best_d:
			best_d = d
			best = gi
	return best


func _do_pickup(target_tile: Vector3 = Vector3.INF) -> void:
	var ref: Vector3 = target_tile if target_tile != Vector3.INF else position
	var gi: Node = _pickup_at(ref)
	if gi == null:
		if inventory and inventory.is_full():
			_show_action_text("Inventory full!")
		else:
			_show_action_text("Nothing to pick up")
		_update_health_bar()
		return
	var item: ItemResource = gi.get("item_resource")
	if not item:
		_update_health_bar()
		return
	# Ammo and consumables are used immediately, not stored.
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
			gi.queue_free()
		_update_health_bar()
		return
	# Everything else goes into the inventory.
	if inventory and inventory.has_method("add_item") and inventory.add_item(item):
		_show_action_text("Picked up " + item.item_name)
		gi.queue_free()
	else:
		_show_action_text("Inventory full!")
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
	_pending_cost = max(1, equip_cost)
	_end_action_in_place()


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
	_pending_cost = max(1, equip_cost)
	_end_action_in_place()


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


func _on_move_complete() -> void:
	can_act = false
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.turn_done(max(_pending_cost, 1))
