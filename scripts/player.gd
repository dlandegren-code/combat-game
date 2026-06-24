extends CharacterBody3D
## Player character: click-to-move on a grid, click adjacent enemy to attack

const GRID_SIZE := 1.0
const MOVE_RANGE := 5
const MOVE_SPEED := 6.0

@export var initiative: int = 10
@export var character_name: String = "Hero"
@export var is_player_controlled: bool = true
@export var move_cost_per_tile: int = 1
@export var attack_cost: int = 2
@export var armor: int = 0
@export var physical_resistance: int = 0  ## percentage 0-100
@export var attack_skill: int = 5       ## used in attack vs defense rolls
@export var parry_skill: int = 4        ## parry defense skill
@export var dodge_skill: int = 5        ## dodge defense skill
@export_enum("Parry", "Dodge") var defensive_option: int = 0  ## 0=Parry, 1=Dodge
@export var shove_skill: int = 5
@export var trip_skill: int = 4
@export var shove_cost: int = 2
@export var trip_cost: int = 2
@export var ranged_skill: int = 3       ## used for bow/distance attacks
@export var ranged_cost: int = 3
@export var ammo: int = 0
@export var max_ammo: int = 0
@export var ranged_range: int = 15      ## max tiles for ranged
@export var throw_skill: int = 3       ## used for thrown weapon attacks
@export var throw_cost: int = 3
@export var throw_range: int = 5       ## max tiles for thrown
@export var equip_cost: int = 1        ## time cost to swap equipped weapon/shield

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW, PICKUP, EQUIP }

var next_turn_at: int = 0
var is_prone: bool = false

var can_act := false
var is_moving := false
var target_position := Vector3.ZERO
var selected_action: int = Action.MOVE

var hp := 20
var max_hp := 20
var attack_dmg := 4
var is_alive := true

var health_bar: Label3D
var move_indicator: MeshInstance3D
var inventory: Node  ## InventoryComponent

var _tiles_moved: int = 0
var _action_used: int = Action.MOVE


static var _bar_connected := false

func _ready() -> void:
	target_position = position
	position.y = _ground_y()
	health_bar = get_node("HealthBar")
	move_indicator = get_parent().get_node("MoveIndicator")
	move_indicator.visible = false
	inventory = get_node_or_null("Inventory")
	_update_health_bar()
	add_to_group("combatants")
	if not is_player_controlled:
		add_to_group("enemies")
	if is_player_controlled and not _bar_connected:
		_bar_connected = true
		_connect_action_bar()


func enable_turn() -> void:
	if not is_alive:
		return
	if is_prone:
		# Auto-stand costs 1 time unit
		is_prone = false
		_show_condition_text("Stood up")
		_update_health_bar()
		var combat_mgr := get_parent().get_node_or_null("CombatManager")
		if combat_mgr:
			combat_mgr.charge_defense_cost(self)
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
		selected_action = Action.MOVE
		_update_action_bar()
	elif event.is_action_pressed("action_2"):
		selected_action = Action.ATTACK
		_update_action_bar()
	elif event.is_action_pressed("action_3"):
		selected_action = Action.SHOVE
		_update_action_bar()
	elif event.is_action_pressed("action_4"):
		selected_action = Action.TRIP
		_update_action_bar()
	elif event.is_action_pressed("action_5"):
		selected_action = Action.RANGED
		_update_action_bar()
	elif event.is_action_pressed("action_6"):
		selected_action = Action.THROW
		_update_action_bar()
	elif event.is_action_pressed("action_7"):
		selected_action = Action.PICKUP
		_update_action_bar()


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
		enemy_query.collision_mask = 2
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
	ground_query.collision_mask = 1
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
		_do_pickup()
		is_moving = true
		target_position = position
		return

	# Offensive actions: check if we clicked an enemy
	if selected_action != Action.MOVE:
		var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
		enemy_query.collision_mask = 2
		var enemy_result := space_state.intersect_ray(enemy_query)

		if not enemy_result.is_empty():
			var collider: Node = enemy_result.collider
			if collider.has_method("take_damage") and _can_target(collider):
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				_hide_indicator()
				_action_used = selected_action
				match selected_action:
					Action.ATTACK:
						collider.take_damage(_get_effective_attack_dmg(), _get_effective_attack_skill(), Action.ATTACK)
					Action.SHOVE:
						_try_shove(collider)
					Action.TRIP:
						_try_trip(collider)
					Action.RANGED:
						_do_ranged_attack(collider)
					Action.THROW:
						_do_throw_attack(collider)
				is_moving = true
				target_position = position
				return

	# Move on ground
	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = 1
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


func _is_adjacent(target_pos: Vector3) -> bool:
	var dist: float = abs(target_pos.x - position.x) + abs(target_pos.z - position.z)
	return dist <= GRID_SIZE * 1.5


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


func _has_line_of_sight(target: Node) -> bool:
	var target_node := target as Node3D
	if not target_node:
		return false
	var space_state := get_world_3d().direct_space_state
	var from_pos := position + Vector3(0, 0.5, 0)
	var to_pos := target_node.position + Vector3(0, 0.5, 0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 2  ## only enemy layer -- ignore ground
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.collider == target


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
	var old_item: ItemResource = null
	if inventory.has_method("get_equipped_weapon"):
		old_item = inventory.get_equipped_weapon()
	inventory.equip(slot_index)
	var new_item: ItemResource = null
	if inventory.has_method("get_equipped_weapon"):
		new_item = inventory.get_equipped_weapon()
	if old_item == new_item:
		return
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


func take_damage(amount: int, attacker_skill: int = 0, _action_type: int = Action.ATTACK) -> bool:
	if not is_alive:
		return false

	var def_result: Dictionary = _attempt_defense(attacker_skill, _action_type)
	if def_result.defended:
		return true

	var effective: int = _calculate_damage(amount)
	hp -= effective
	if effective > 0:
		_show_damage_number(effective)
	_update_health_bar()
	if hp <= 0:
		is_alive = false
		_die()
	return false


func _attempt_defense(attacker_skill: int, action_type: int = Action.ATTACK) -> Dictionary:
	var attack_roll := attacker_skill + randi_range(1, 5)
	var effective_dodge: int = dodge_skill - (2 if is_prone else 0)
	var result := { "defended": false, "attack_roll": attack_roll, "defense_roll": 0 }
	var is_ranged := (action_type == Action.RANGED or action_type == Action.THROW)

	if defensive_option == 0:
		if not (_has_usable_weapon() or _has_shield_equipped()):
			return result
		if is_ranged and not _can_parry_ranged():
			return result
		result.defense_roll = parry_skill + randi_range(1, 5)
		if result.defense_roll >= attack_roll:
			if inventory and inventory.has_method("degrade_equipped_weapon"):
				inventory.degrade_equipped_weapon()
			_show_defense_result("Parry!")
			_update_health_bar()
			_charge_defense_cost()
			result.defended = true
	else:
		if is_ranged and not _can_dodge_ranged():
			return result
		result.defense_roll = effective_dodge + randi_range(1, 5)
		if result.defense_roll >= attack_roll:
			_show_defense_result("Dodge!")
			_charge_defense_cost()
			result.defended = true
	return result


func _show_defense_result(text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.5, 0)
	label.modulate = Color(0.6, 0.8, 0.6, 1)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 3.8, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _charge_defense_cost() -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.charge_defense_cost(self)


func _try_shove(target: Node) -> void:
	var def_result: Dictionary = target._attempt_defense(shove_skill)
	if def_result.defended:
		_show_action_text("Shove blocked!")
		return

	var margin: int = def_result.attack_roll - def_result.defense_roll
	var tiles := clampi(margin, 1, 4)
	var push_dir: Vector3 = (target.position - position)
	push_dir.y = 0
	if push_dir.length() < 0.01:
		push_dir = Vector3.RIGHT
	push_dir = push_dir.normalized()

	var dest: Vector3 = target._snap_to_grid(target.position + push_dir * tiles * GRID_SIZE)
	# Clamp to battlefield and avoid other combatants
	dest.x = clamp(dest.x, -14, 14)
	dest.z = clamp(dest.z, -14, 14)
	dest = _avoid_overlap(dest, target)

	target.position = dest
	target.target_position = dest
	_show_action_text("Shoved " + str(tiles) + "!")


func _try_trip(target: Node) -> void:
	var def_result: Dictionary = target._attempt_defense(trip_skill)
	if def_result.defended:
		_show_action_text("Trip blocked!")
		return

	target.is_prone = true
	target._show_condition_text("PRONE!")
	target._update_health_bar()
	_show_action_text("Tripped!")


func _show_action_text(text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 22
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 3.0, 0)
	label.modulate = Color(1, 0.7, 0.3, 1)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 4.2, 0.6).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


func _show_condition_text(text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 1.8, 0)
	label.modulate = Color(0.9, 0.3, 0.3, 1)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 3.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _avoid_overlap(tile: Vector3, exclude: Node) -> Vector3:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == exclude or not is_instance_valid(c):
			continue
		if c._snap_to_grid(c.position).distance_to(tile) < 0.5:
			return c._snap_to_grid(c.position)
	return tile


func _has_usable_weapon() -> bool:
	if inventory and inventory.has_method("has_weapon_equipped"):
		return inventory.has_weapon_equipped()
	return false

func _has_shield_equipped() -> bool:
	if inventory and inventory.has_method("is_shield_equipped"):
		return inventory.is_shield_equipped()
	return false

func _can_parry_ranged() -> bool:
	if inventory and inventory.has_method("can_parry_ranged"):
		return inventory.can_parry_ranged()
	return false

func _can_dodge_ranged() -> bool:
	if inventory and inventory.has_method("can_dodge_ranged"):
		return inventory.can_dodge_ranged()
	return false


func _can_move() -> bool:
	return not is_prone


func _calculate_damage(raw: int) -> int:
	var dmg := raw - armor
	if dmg <= 0:
		return 0
	dmg = roundi(dmg * (1.0 - physical_resistance / 100.0))
	return max(dmg, 0)


func _show_damage_number(amount: int) -> void:
	var label := Label3D.new()
	label.text = str(amount)
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.0, 0)
	label.modulate = Color(1, 0.2, 0.2, 1)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 3.5, 0.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _die() -> void:
	visible = false
	can_act = false
	var combat_mgr := get_parent().get_node("CombatManager")
	combat_mgr.on_character_died(self)


func _update_health_bar() -> void:
	if not health_bar:
		return
	var text := character_name + "\n" + str(hp) + "/" + str(max_hp)
	if armor > 0 or physical_resistance > 0:
		text += "\n"
		if armor > 0:
			text += "Armor:" + str(armor) + " "
		if physical_resistance > 0:
			text += "Res:" + str(physical_resistance) + "%"
	# Show equipped gear
	var gear_lines := []
	if inventory and inventory.has_method("get_equipped_weapon"):
		var main: ItemResource = inventory.get_equipped_weapon()
		if main:
			gear_lines.append("RH:" + main.item_name + "(" + str(main.durability) + ")")
	if inventory and inventory.has_method("get_equipped_offhand"):
		var off: ItemResource = inventory.get_equipped_offhand()
		if off:
			gear_lines.append("LH:" + off.item_name + "(" + str(off.durability) + ")")
	if inventory and inventory.has_method("get_armor_bonus"):
		var arm: ItemResource = inventory.armor
		if arm:
			gear_lines.append("Armor:" + arm.item_name)
	if not gear_lines.is_empty():
		text += "\n" + " ".join(gear_lines)
	if defensive_option == 0:
		text += " Stance:Parry"
	else:
		text += " Stance:Dodge"
	if is_prone:
		text += "\n[PRONE]"
	if max_ammo > 0:
		if ammo > 0:
			text += "\nAmmo:" + str(ammo)
		else:
			text += "\nAmmo:Empty"
	health_bar.text = text


func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		pos.y,
		round(pos.z / GRID_SIZE) * GRID_SIZE
	)


func _is_in_range(target: Vector3) -> bool:
	var dist: float = abs(target.x - position.x) + abs(target.z - position.z)
	return dist <= MOVE_RANGE * GRID_SIZE


func _is_tile_occupied_by_others(tile: Vector3, exclude: Node = null) -> bool:
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == exclude:
			continue
		var current_tile: Vector3 = c._snap_to_grid(c.position)
		var target_tile: Vector3 = c._snap_to_grid(c.target_position)
		if current_tile.distance_to(tile) < 0.5 or target_tile.distance_to(tile) < 0.5:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	var dir := target_position - position
	dir.y = 0  # Only move horizontally
	var dist := dir.length()

	if dist < 0.12:
		position = target_position
		position.y = _ground_y()
		is_moving = false
		velocity = Vector3.ZERO
		_on_move_complete()
	else:
		position += dir.normalized() * MOVE_SPEED * delta
		position.y = _ground_y()


func _ground_y() -> float:
	return 1.11


func _on_move_complete() -> void:
	can_act = false
	var cost := 0
	match _action_used:
		Action.MOVE:
			cost = _tiles_moved * move_cost_per_tile
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
