extends CharacterBody3D
## Enemy: AI-controlled combatant with multiple enemy types

const GRID_SIZE := 1.0
const MOVE_SPEED := 4.0

enum EnemyType { GOBLIN, ARCHER, BOSS }

@export var enemy_type: int = EnemyType.GOBLIN

@export var initiative: int = 5
@export var character_name: String = "Goblin"
@export var is_player_controlled: bool = false
@export var move_cost_per_tile: int = 1
@export var attack_cost: int = 2
@export var armor: int = 1
@export var physical_resistance: int = 0  ## percentage 0-100
@export var attack_skill: int = 3       ## used in attack vs defense rolls
@export var parry_skill: int = 1        ## parry defense skill (low: no real training)
@export var dodge_skill: int = 3        ## dodge defense skill
@export_enum("Parry", "Dodge") var defensive_option: int = 1  ## 0=Parry, 1=Dodge
@export var shove_skill: int = 2
@export var trip_skill: int = 1
@export var shove_cost: int = 2
@export var trip_cost: int = 2
@export var ranged_skill: int = 3
@export var ranged_cost: int = 3
@export var ammo: int = 0
@export var max_ammo: int = 0
@export var ranged_range: int = 8
@export var throw_skill: int = 3
@export var throw_cost: int = 3
@export var throw_range: int = 5

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW }

var next_turn_at: int = 0
var is_prone: bool = false

var is_moving := false
var target_position := Vector3.ZERO

var hp := 10
var max_hp := 10
var attack_dmg := 3
var is_alive := true

var health_bar: Label3D
var inventory: Node  ## InventoryComponent

var _pending_cost: int = 0
var _action_used: int = Action.MOVE


func _ready() -> void:
	target_position = position
	position.y = _ground_y()
	health_bar = get_node("HealthBar")
	inventory = get_node_or_null("Inventory")
	_configure_from_type()
	_apply_enemy_visual()
	_update_health_bar()
	add_to_group("combatants")
	add_to_group("enemies")


func _configure_from_type() -> void:
	## Sets all stats based on enemy_type export
	match enemy_type:
		EnemyType.GOBLIN:
			character_name = "Goblin"
			hp = 10; max_hp = 10
			initiative = 5
			armor = 1
			attack_skill = 3; attack_dmg = 3
			parry_skill = 1; dodge_skill = 3
			defensive_option = 1  # Dodge
			shove_skill = 2; trip_skill = 1
			shove_cost = 2; trip_cost = 2
			move_cost_per_tile = 1; attack_cost = 2
			ranged_skill = 3; ranged_range = 8
			ammo = 0; max_ammo = 0
			throw_skill = 3; throw_range = 5; throw_cost = 3
		EnemyType.ARCHER:
			character_name = "Goblin Archer"
			hp = 8; max_hp = 8
			initiative = 7
			armor = 0
			attack_skill = 2; attack_dmg = 2  # Weak melee
			parry_skill = 1; dodge_skill = 4
			defensive_option = 1  # Dodge
			shove_skill = 1; trip_skill = 1
			shove_cost = 3; trip_cost = 3
			move_cost_per_tile = 1; attack_cost = 2
			ranged_skill = 5; ranged_range = 15; ranged_cost = 3
			ammo = 6; max_ammo = 6
			throw_skill = 2; throw_range = 4; throw_cost = 3
		EnemyType.BOSS:
			character_name = "Goblin Boss"
			hp = 30; max_hp = 30
			initiative = 6
			armor = 3
			attack_skill = 6; attack_dmg = 5
			parry_skill = 5; dodge_skill = 3
			defensive_option = 0  # Parry
			shove_skill = 4; trip_skill = 3
			shove_cost = 2; trip_cost = 2
			move_cost_per_tile = 1; attack_cost = 2
			ranged_skill = 1; ranged_range = 0
			ammo = 0; max_ammo = 0
			throw_skill = 4; throw_range = 4; throw_cost = 3


func _apply_enemy_visual() -> void:
	## Scale the CharacterModel and old Mesh based on enemy_type
	var model_node: Node3D = get_node_or_null("CharacterModel")
	var old_mesh: MeshInstance3D = get_node_or_null("Mesh")

	match enemy_type:
		EnemyType.GOBLIN:
			if model_node: model_node.scale = Vector3(1, 1, 1)
			if old_mesh: old_mesh.scale = Vector3(1, 1, 1)
		EnemyType.ARCHER:
			if model_node: model_node.scale = Vector3(0.85, 0.9, 0.85)
			if old_mesh: old_mesh.scale = Vector3(0.85, 0.9, 0.85)
		EnemyType.BOSS:
			if model_node: model_node.scale = Vector3(1.3, 1.25, 1.3)
			if old_mesh: old_mesh.scale = Vector3(1.3, 1.25, 1.3)


func enable_turn() -> void:
	if not is_alive:
		return
	if is_prone:
		is_prone = false
		_show_condition_text("Stood up")
		_update_health_bar()
		var combat_mgr := get_parent().get_node_or_null("CombatManager")
		if combat_mgr:
			combat_mgr.charge_defense_cost(self)


func disable_turn() -> void:
	pass


func take_turn() -> void:
	if not is_alive:
		end_my_turn(0)
		return

	match enemy_type:
		EnemyType.GOBLIN:
			_take_turn_goblin()
		EnemyType.ARCHER:
			_take_turn_archer()
		EnemyType.BOSS:
			_take_turn_boss()
		_:
			_take_turn_goblin()


func _take_turn_goblin() -> void:
	## Original goblin AI: move toward nearest, weighted random adjacent
	var player := _find_nearest_player()
	if not player or not player.is_alive:
		end_my_turn(0)
		return

	if _is_adjacent(player.position):
		_do_adjacent_action(player)
		await get_tree().create_timer(0.3).timeout
		end_my_turn(_pending_cost)
		return

	if is_prone:
		end_my_turn(1)
		return

	# Move one cell toward nearest player, avoiding occupied tiles
	_action_used = Action.MOVE
	_pending_cost = move_cost_per_tile
	_move_toward(player)
	is_moving = true


func _take_turn_archer() -> void:
	## Archer AI: stay at mid-range, fire arrows, retreat if threatened
	var player := _find_nearest_player()
	if not player or not player.is_alive:
		end_my_turn(0)
		return

	var dist_to_player: float = abs(player.position.x - position.x) + abs(player.position.z - position.z)

	if is_prone:
		end_my_turn(1)
		return

	# If adjacent to a player, try to move away or do weak melee
	if _is_adjacent(player.position):
		var roll := randi_range(1, 100)
		if roll <= 60 and _try_move_away(player):
			_action_used = Action.MOVE
			_pending_cost = move_cost_per_tile
			is_moving = true
		else:
			# Desperate melee
			_action_used = Action.ATTACK
			player.take_damage(attack_dmg, attack_skill, Action.ATTACK)
			_pending_cost = attack_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
		return

	# In optimal range (4+ tiles): fire arrows
	var effective_ranged_range: int = ranged_range
	if inventory and inventory.has_method("get_equipped_ranged_range"):
		var item_range: int = inventory.get_equipped_ranged_range()
		if item_range > 0:
			effective_ranged_range = item_range
	if ammo > 0 and dist_to_player >= 4 * GRID_SIZE and dist_to_player <= effective_ranged_range * GRID_SIZE:
		if _has_line_of_sight(player):
			_action_used = Action.RANGED
			ammo -= 1
			_update_health_bar()
			player.take_damage(attack_dmg, ranged_skill, Action.RANGED)
			_show_action_text("Arrow fired!")
			_pending_cost = ranged_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
			return

	# Out of ammo or bad range: reposition
	if ammo <= 0:
		# Move away from nearest player
		_try_move_away(player)
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true
		return

	# Move toward ideal range (if too far, move closer; if too close, back up)
	if dist_to_player > effective_ranged_range * 0.8 * GRID_SIZE:
		_move_toward(player)
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true
	else:
		_try_move_away(player)
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true


func _take_turn_boss() -> void:
	## Boss AI: target weakest player, shove to separate, attack otherwise
	var target := _find_weakest_player()
	if not target or not target.is_alive:
		end_my_turn(0)
		return

	if is_prone:
		end_my_turn(1)
		return

	# If adjacent: smart action selection
	if _is_adjacent(target.position):
		var roll := randi_range(1, 100)
		var has_ally_adjacent := _has_ally_adjacent_to(target)
		if has_ally_adjacent and roll <= 35:
			# Shove to separate from allies
			_action_used = Action.SHOVE
			_try_shove(target)
			_pending_cost = shove_cost
		elif roll <= 80:
			# Attack
			_action_used = Action.ATTACK
			target.take_damage(attack_dmg, attack_skill, Action.ATTACK)
			_pending_cost = attack_cost
		else:
			# Trip
			_action_used = Action.TRIP
			_try_trip(target)
			_pending_cost = trip_cost
		await get_tree().create_timer(0.3).timeout
		end_my_turn(_pending_cost)
		return

	# Move toward target
	_move_toward(target)
	_action_used = Action.MOVE
	_pending_cost = move_cost_per_tile
	is_moving = true


func _find_weakest_player() -> Node:
	## Returns the player-controlled combatant with the lowest current HP
	var players := get_tree().get_nodes_in_group("combatants")
	var best: Node = null
	var lowest_hp: int = 999

	for p in players:
		if not p.is_player_controlled or not p.is_alive:
			continue
		if p == self:
			continue
		if p.hp < lowest_hp:
			lowest_hp = p.hp
			best = p

	return best


func _has_ally_adjacent_to(target: Node) -> bool:
	## Returns true if another enemy is adjacent to the given target
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or c == target:
			continue
		if not is_instance_valid(c) or not c.is_alive:
			continue
		if c.is_player_controlled:
			continue
		if _is_adjacent(c.position, target.position):
			return true
	return false


func _try_move_away(from: Node) -> bool:
	## Try to move one tile away from the given node. Returns true if moved.
	var dir_away: Vector3 = position - from.position
	dir_away.y = 0
	if dir_away.length() < 0.01:
		dir_away = Vector3.RIGHT
	dir_away = dir_away.normalized()

	var move_dir := Vector3.ZERO
	if abs(dir_away.x) > abs(dir_away.z):
		move_dir.x = sign(dir_away.x)
	else:
		move_dir.z = sign(dir_away.z)

	var dest := _snap_to_grid(position + move_dir * GRID_SIZE)
	dest = _avoid_overlap(dest, self)
	if dest.distance_to(position) < 0.1:
		# Try perpendicular direction
		move_dir = Vector3(move_dir.z, 0, -move_dir.x)
		dest = _snap_to_grid(position + move_dir * GRID_SIZE)
		dest = _avoid_overlap(dest, self)
		if dest.distance_to(position) < 0.1:
			return false

	target_position = dest
	return true


func _move_toward(target: Node) -> void:
	## Set target_position one tile toward the target
	var dir_to: Vector3 = target.position - position
	dir_to.y = 0
	if dir_to.length() < 0.01:
		dir_to = Vector3.RIGHT
	dir_to = dir_to.normalized()

	var move_dir := Vector3.ZERO
	if abs(dir_to.x) > abs(dir_to.z):
		move_dir.x = sign(dir_to.x)
	else:
		move_dir.z = sign(dir_to.z)

	var dest := _snap_to_grid(position + move_dir * GRID_SIZE)
	dest = _avoid_overlap(dest, self)
	target_position = dest


func _find_nearest_player() -> Node:
	## Returns the nearest alive player-controlled combatant
	var best: Node = null
	var best_dist: float = INF
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or not c.is_player_controlled or not c.is_alive:
			continue
		if c == self:
			continue
		var dist: float = abs(c.position.x - position.x) + abs(c.position.z - position.z)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


func _do_adjacent_action(player: Node) -> void:
	## Weighted random action when adjacent: 60% attack, 25% shove, 15% trip
	var roll := randi_range(1, 100)
	if roll <= 60:
		_action_used = Action.ATTACK
		player.take_damage(attack_dmg, attack_skill, Action.ATTACK)
		_pending_cost = attack_cost
	elif roll <= 85:
		_action_used = Action.SHOVE
		_try_shove(player)
		_pending_cost = shove_cost
	else:
		_action_used = Action.TRIP
		_try_trip(player)
		_pending_cost = trip_cost


func _has_line_of_sight(target: Node) -> bool:
	var target_node := target as Node3D
	if not target_node:
		return false
	var space_state := get_world_3d().direct_space_state
	var from_pos := position + Vector3(0, 0.5, 0)
	var to_pos := target_node.position + Vector3(0, 0.5, 0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.collider == target


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


func _is_tile_occupied_by_others(tile: Vector3, exclude: Node = null) -> bool:
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == exclude:
			continue
		var current_tile: Vector3 = c._snap_to_grid(c.position)
		var target_tile: Vector3 = c._snap_to_grid(c.target_position)
		if current_tile.distance_to(tile) < 0.5 or target_tile.distance_to(tile) < 0.5:
			return true
	return false


func _avoid_overlap(tile: Vector3, exclude: Node) -> Vector3:
	if not _is_tile_occupied_by_others(tile, exclude):
		return tile

	var directions := [
		Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)
	]
	for radius in range(1, 5):
		for d in directions:
			var candidate: Vector3 = tile + d * radius * GRID_SIZE
			candidate.x = clamp(candidate.x, -14, 14)
			candidate.z = clamp(candidate.z, -14, 14)
			if not _is_tile_occupied_by_others(candidate, exclude):
				return candidate
	return _snap_to_grid(position)


func _is_adjacent(target_pos: Vector3, source_pos: Vector3 = Vector3.INF) -> bool:
	if source_pos == Vector3.INF:
		source_pos = position
	var dist: float = abs(target_pos.x - source_pos.x) + abs(target_pos.z - source_pos.z)
	return dist <= GRID_SIZE * 1.5


func _try_shove(target: Node) -> void:
	var def_result: Dictionary = target._attempt_defense(shove_skill)
	if def_result.defended:
		return
	var margin: int = def_result.attack_roll - def_result.defense_roll
	var tiles := clampi(margin, 1, 4)
	var push_dir: Vector3 = (target.position - position)
	push_dir.y = 0
	if push_dir.length() < 0.01:
		push_dir = Vector3.RIGHT
	push_dir = push_dir.normalized()
	var dest: Vector3 = target._snap_to_grid(target.position + push_dir * tiles * GRID_SIZE)
	dest.x = clamp(dest.x, -14, 14)
	dest.z = clamp(dest.z, -14, 14)
	dest = _avoid_overlap(dest, target)
	target.position = dest
	target.target_position = dest


func _try_trip(target: Node) -> void:
	var def_result: Dictionary = target._attempt_defense(trip_skill)
	if def_result.defended:
		return
	target.is_prone = true
	target._show_condition_text("PRONE!")
	target._update_health_bar()


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

func _has_defense_item() -> bool:
	if inventory and inventory.has_method("has_weapon_equipped"):
		return inventory.has_weapon_equipped() or _has_shield_equipped()
	return false

func _attempt_defense(attacker_skill: int, action_type: int = Action.ATTACK) -> Dictionary:
	var attack_roll := attacker_skill + randi_range(1, 5)
	var effective_dodge: int = dodge_skill - (2 if is_prone else 0)
	var result := { "defended": false, "attack_roll": attack_roll, "defense_roll": 0 }
	var is_ranged := (action_type == Action.RANGED or action_type == Action.THROW)

	if defensive_option == 0:
		if not _has_defense_item():
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


func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		pos.y,
		round(pos.z / GRID_SIZE) * GRID_SIZE
	)


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
	if inventory and inventory.armor:
		gear_lines.append("Armor:" + inventory.armor.item_name)
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
	end_my_turn(_pending_cost)


func end_my_turn(cost: int) -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.turn_done(cost)
