extends "res://scripts/combatant.gd"
## Enemy: AI-controlled combatant with multiple enemy types.
## Shared combat/movement/equipment logic lives in Combatant (combatant.gd).

enum EnemyType { GOBLIN, ARCHER, BOSS }

@export var enemy_type: int = EnemyType.GOBLIN

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW }

## Distance (in tiles) an archer tries to keep from its target before shooting.
## It backs away when the target is closer than this and fires from here or
## farther. Capped at the archer's actual ranged range. Raise to hang back more.
const ARCHER_PREFERRED_DIST := 10


func _pre_setup() -> void:
	# main.tscn does not store is_player_controlled on enemy nodes; enforce it.
	# All numeric stats (including move_speed/move_range) come from the assigned
	# `stats` resource, applied by the base before this hook runs.
	is_player_controlled = false
	_apply_enemy_visual()


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

	# Adjacent to a hero. With arrows we never melee: back off to shoot from range
	# next turn, or loose a point-blank arrow if cornered (still beats weak melee).
	# Only melee when out of arrows.
	if _is_adjacent(player.position):
		if ammo > 0:
			if _retreat_from(player):
				_action_used = Action.MOVE
				_pending_cost = move_cost_per_tile
				is_moving = true
				return
			await _fire_arrow(player)
			return
		# Out of arrows: melee.
		_action_used = Action.ATTACK
		_play_attack_anim("attack-melee-right")
		player.take_damage(attack_dmg, attack_skill, false)
		_pending_cost = attack_cost
		await get_tree().create_timer(0.3).timeout
		end_my_turn(_pending_cost)
		return

	# Effective max range (an equipped bow may extend the base stat).
	var max_range: int = ranged_range
	if inventory and inventory.has_method("get_equipped_ranged_range"):
		var item_range: int = inventory.get_equipped_ranged_range()
		if item_range > 0:
			max_range = item_range

	# Out of ammo: no point kiting (arrows never come back). Close in for melee
	# instead, which also brings a stranded archer back toward the fight.
	if ammo <= 0:
		_move_toward(player)
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true
		return

	# Preferred standoff: hang back this far before shooting (capped at our range).
	var preferred: float = min(ARCHER_PREFERRED_DIST, max_range) * GRID_SIZE
	var in_range := dist_to_player <= max_range * GRID_SIZE and _has_line_of_sight(player)

	# Out of range or no line of sight: close the gap to set up a shot.
	if not in_range:
		_move_toward(player)
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true
		return

	# Closer than we'd like: back away to keep our distance (staying in the arena).
	if dist_to_player < preferred and _retreat_from(player):
		_action_used = Action.MOVE
		_pending_cost = move_cost_per_tile
		is_moving = true
		return

	# At a comfortable distance, or cornered and unable to retreat: take the shot.
	await _fire_arrow(player)


func _fire_arrow(player: Node) -> void:
	_face_target(player)
	_action_used = Action.RANGED
	ammo -= 1
	_update_health_bar()
	_play_attack_anim("holding-both-shoot")
	player.take_damage(attack_dmg, ranged_skill, true)
	_show_action_text("Arrow fired!")
	_pending_cost = ranged_cost
	await get_tree().create_timer(0.3).timeout
	end_my_turn(_pending_cost)


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
			target.take_damage(attack_dmg, attack_skill, false)
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


func _min_player_dist(tile: Vector3) -> float:
	## Manhattan distance from a tile to the CLOSEST alive player. Used so the
	## archer backs away from the whole group, not just one hero.
	var best := INF
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or not c.is_player_controlled or not c.is_alive:
			continue
		var d: float = abs(c.position.x - tile.x) + abs(c.position.z - tile.z)
		if d < best:
			best = d
	return best


func _retreat_from(_target: Node) -> bool:
	## Back away from ALL players, not just the nearest, so the archer never flees
	## one hero straight into another. Picks the cardinal direction that most
	## increases the distance to the closest player, then slides up to move_range
	## tiles that way, stopping before any step brings a player closer again.
	## Stays inside the arena and skips occupied tiles. Returns false when no move
	## improves the situation (cornered) so the caller can fire instead of shuffling.
	var cur: Vector3 = _snap_to_grid(position)
	var cur_min: float = _min_player_dist(cur)

	var dirs := [
		Vector3(GRID_SIZE, 0, 0), Vector3(-GRID_SIZE, 0, 0),
		Vector3(0, 0, GRID_SIZE), Vector3(0, 0, -GRID_SIZE)
	]
	var best_dir := Vector3.ZERO
	var best_min := cur_min
	for d in dirs:
		var one: Vector3 = _snap_to_grid(cur + d)
		if not _is_in_arena(one) or _is_tile_occupied_by_others(one, self):
			continue
		var m: float = _min_player_dist(one)
		if m > best_min:
			best_min = m
			best_dir = d
	if best_dir == Vector3.ZERO:
		return false

	# Slide along the chosen direction, keeping the farthest tile that never lets
	# a player get closer than the previous step.
	var dest := cur
	var dest_min := cur_min
	for i in range(1, move_range + 1):
		var step: Vector3 = _snap_to_grid(cur + best_dir * GRID_SIZE * i)
		if not _is_in_arena(step) or _is_tile_occupied_by_others(step, self):
			break
		var m: float = _min_player_dist(step)
		if m < dest_min:
			break
		dest = step
		dest_min = m
	if dest.distance_to(cur) < 0.1:
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
		player.take_damage(attack_dmg, attack_skill, false)
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
