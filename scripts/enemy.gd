extends "res://scripts/combatant.gd"
## Enemy: AI-controlled combatant with multiple enemy types.
## Shared combat/movement/equipment logic lives in Combatant (combatant.gd).

enum EnemyType { GOBLIN, ARCHER, BOSS }

@export var enemy_type: int = EnemyType.GOBLIN

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW }

var _pending_cost: int = 0


func _pre_setup() -> void:
	# main.tscn does not store is_player_controlled on enemy nodes; enforce it.
	# All numeric stats (including move_speed/move_range) come from the assigned
	# `stats` resource, applied by the base before this hook runs.
	is_player_controlled = false
	_apply_enemy_visual()


func _is_ranged_action(action_type: int) -> bool:
	return action_type == Action.RANGED or action_type == Action.THROW


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
	_stand_up_if_prone()


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
			_play_attack_anim("attack-melee-right")
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
			_face_target(player)
			_action_used = Action.RANGED
			ammo -= 1
			_update_health_bar()
			_play_attack_anim("holding-both-shoot")
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
		_face_target(target)
		var roll := randi_range(1, 100)
		var has_ally_adjacent := _has_ally_adjacent_to(target)
		if has_ally_adjacent and roll <= 35:
			# Shove to separate from allies
			_action_used = Action.SHOVE
			_play_attack_anim("attack-kick-right")
			_try_shove(target)
			_pending_cost = shove_cost
		elif roll <= 80:
			# Attack
			_action_used = Action.ATTACK
			_play_attack_anim("attack-melee-right")
			target.take_damage(attack_dmg, attack_skill, Action.ATTACK)
			_pending_cost = attack_cost
		else:
			# Trip
			_action_used = Action.TRIP
			_play_attack_anim("attack-kick-right")
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
	## Move toward target using BFS pathfinding to route around obstacles
	var from_tile: Vector3 = _snap_to_grid(position)
	var to_tile: Vector3 = _snap_to_grid(target.position)

	var path: Array = _find_path(from_tile, to_tile)
	if path.size() <= 1:
		return

	var step_idx: int = min(move_range, path.size() - 1)
	var dest: Vector3 = path[step_idx]
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
	_face_target(player)
	var roll := randi_range(1, 100)
	if roll <= 60:
		_action_used = Action.ATTACK
		_play_attack_anim("attack-melee-right")
		player.take_damage(attack_dmg, attack_skill, Action.ATTACK)
		_pending_cost = attack_cost
	elif roll <= 85:
		_action_used = Action.SHOVE
		_play_attack_anim("attack-kick-right")
		_try_shove(player)
		_pending_cost = shove_cost
	else:
		_action_used = Action.TRIP
		_play_attack_anim("attack-kick-right")
		_try_trip(player)
		_pending_cost = trip_cost


func _tile_key(tile: Vector3) -> String:
	return str(int(round(tile.x))) + "," + str(int(round(tile.z)))


func _find_path(from_tile: Vector3, to_tile: Vector3) -> Array:
	## BFS returning the shortest obstacle-free path; combatant tiles are passable
	var dirs := [
		Vector3(GRID_SIZE, 0, 0), Vector3(-GRID_SIZE, 0, 0),
		Vector3(0, 0, GRID_SIZE), Vector3(0, 0, -GRID_SIZE)
	]
	var queue: Array = [[from_tile]]
	var visited: Dictionary = {}
	visited[_tile_key(from_tile)] = true

	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var cur: Vector3 = path[path.size() - 1]
		if cur.distance_to(to_tile) < 0.5:
			return path
		if path.size() > 50:
			continue
		for d in dirs:
			var nxt: Vector3 = _snap_to_grid(cur + d)
			var k: String = _tile_key(nxt)
			if visited.has(k):
				continue
			if _is_obstacle_at(nxt):
				continue
			visited[k] = true
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			queue.append(new_path)
	return []


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
			candidate.x = clamp(candidate.x, ARENA_MIN, ARENA_MAX)
			candidate.z = clamp(candidate.z, ARENA_MIN, ARENA_MAX)
			if not _is_tile_occupied_by_others(candidate, exclude):
				return candidate
	return _snap_to_grid(position)


func _on_move_complete() -> void:
	end_my_turn(_pending_cost)


func end_my_turn(cost: int) -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.turn_done(cost)
