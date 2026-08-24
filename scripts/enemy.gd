extends "res://scripts/combatant.gd"
## Enemy: AI-controlled combatant with multiple enemy types.
## Shared combat/movement/equipment logic lives in Combatant (combatant.gd).

enum EnemyType { GOBLIN, ARCHER, BOSS }

@export var enemy_type: int = EnemyType.GOBLIN

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW }

## Distance (in tiles) an archer is happy to shoot from. At or beyond this it just looses an
## arrow; closer than this it spends the turn repositioning. Capped at the archer's actual
## ranged range.
##
## Tied to the penalty-free band deliberately: standing further back than this buys no safety
## the bow can pay for, since every band beyond it costs to-hit (Combatant.RANGE_FREE_TILES).
const ARCHER_PREFERRED_DIST := RANGE_FREE_TILES


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

	# Move toward the nearest player, avoiding occupied tiles
	_begin_move_toward(player)


func _take_turn_archer() -> void:
	## Archer AI: hold the tile that is FURTHEST from the heroes while still giving a clear
	## shot, and fire from there. It only ever walks a real BFS route, so it rounds pillars
	## and walls instead of sliding through them, and it only draws a blade when out of arrows.
	var player := _find_nearest_player()
	if not player or not player.is_alive:
		end_my_turn(0)
		return

	if is_prone:
		end_my_turn(1)
		return

	# Out of ammo: kiting is pointless (arrows never come back), so close in and melee.
	# This also walks a stranded archer back toward the fight.
	if ammo <= 0:
		if _is_adjacent(player.position):
			_action_used = Action.ATTACK
			_do_melee_attack(player)
			_pending_cost = attack_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
			return
		_begin_move_toward(player)
		return

	# Effective max range (an equipped bow may extend the base stat).
	var max_range: int = get_ranged_range()
	var preferred: float = min(ARCHER_PREFERRED_DIST, max_range) * GRID_SIZE

	var cur: Vector3 = _snap_to_grid(position)
	var can_fire_now: bool = _can_fire_from(cur, player, max_range)
	var cur_dist: float = _min_player_dist(cur)

	# Already standing far enough back with a clear line: just shoot. This is what stops
	# the "maximise distance" search below from backing up forever and never firing.
	if can_fire_now and cur_dist >= preferred:
		await _fire_arrow(player)
		return

	# Too close (or no shot from here): spend the turn walking to the best firing tile
	# we can actually reach — furthest from the nearest hero, still inside bow range,
	# still with line of sight.
	var path: Array = _best_firing_path(player, max_range, cur_dist)
	if not path.is_empty():
		_follow_path(path)
		_action_used = Action.MOVE
		_pending_cost = get_move_cost()
		return

	# Nothing reachable improves on where we stand. Cornered archers still loose a
	# point-blank arrow — it beats their dismal melee.
	if can_fire_now:
		await _fire_arrow(player)
		return

	# No shot from anywhere within a turn's walk (out of range, or fully blocked):
	# close the gap to set one up.
	_begin_move_toward(player)


func _can_fire_from(tile: Vector3, target: Node, max_range: int) -> bool:
	## Could we put an arrow into `target` while standing on `tile`? Same two conditions the
	## shot itself needs: inside the bow's range, and a clear line to the target.
	var dist: float = abs(target.position.x - tile.x) + abs(target.position.z - tile.z)
	if dist > max_range * GRID_SIZE:
		return false
	return _has_line_of_sight_from(tile, target)


func _best_firing_path(target: Node, max_range: int, cur_dist: float) -> Array:
	## Of every tile we could walk to this turn, the best place to shoot from: ACCURACY first,
	## then distance from the heroes. Returns its BFS path, or [] when standing still is
	## already as good. Ties go to the shorter walk.
	##
	## Accuracy has to lead now that the bow outranges its own useful range. Scoring purely on
	## distance — "as far away as possible, but within range" — would kite the archer out to
	## 15 tiles and a -6 to hit, where it is safe and completely useless. Range penalties come
	## in bands, so within a band it still backs off as far as it can for free.
	##
	## Distance is measured to the nearest hero (not just our target) so the archer never
	## backs away from one and straight into another.
	var best_path: Array = []
	var best_dist: float = cur_dist
	var best_penalty: int = _range_penalty(target, max_range, _snap_to_grid(position))
	var best_steps: int = 0
	for path in _reachable_paths(move_range):
		var tile: Vector3 = path[path.size() - 1]
		if not _can_fire_from(tile, target, max_range):
			continue
		var d: float = _min_player_dist(tile)
		var pen: int = _range_penalty(target, max_range, tile)
		var steps: int = path.size() - 1
		if pen < best_penalty:
			best_penalty = pen
			best_dist = d
			best_path = path
			best_steps = steps
		elif pen > best_penalty:
			continue
		elif d > best_dist + 0.01:
			best_dist = d
			best_path = path
			best_steps = steps
		elif not best_path.is_empty() and absf(d - best_dist) < 0.01 and steps < best_steps:
			best_path = path
			best_steps = steps
	return best_path


func _reachable_paths(max_steps: int) -> Array:
	## Every tile we could end this turn on, each as its BFS path from where we stand.
	## Uses the same rules as Combatant._find_path — obstacles, wall edges, other units and
	## no diagonal corner-cutting — just flooded outward instead of aimed at one goal.
	var start: Vector3 = _snap_to_grid(position)
	var out: Array = []
	var queue: Array = [[start]]
	var visited: Dictionary = {}
	visited[_tile_key(start)] = true

	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var cur: Vector3 = path[path.size() - 1]
		if path.size() - 1 >= max_steps:
			continue
		for d in GRID_DIRS:
			var nxt: Vector3 = _snap_to_grid(cur + d)
			var k: String = _tile_key(nxt)
			if visited.has(k):
				continue
			visited[k] = true
			if not _is_in_arena(nxt) or _is_tile_occupied_by_others(nxt, self):
				continue
			if _step_blocked_by_wall(cur, nxt) or _is_corner_blocked(cur, nxt):
				continue
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			out.append(new_path)
			queue.append(new_path)
	return out


func _begin_move_toward(target: Node) -> void:
	## _move_toward queues the route first, so get_move_cost() can price it by distance.
	_move_toward(target)
	_action_used = Action.MOVE
	_pending_cost = get_move_cost()
	is_moving = true


func _fire_arrow(player: Node) -> void:
	_face_target(player)
	_action_used = Action.RANGED
	ammo -= 1
	_update_health_bar()
	_play_attack_anim("holding-both-shoot")
	_show_action_text("Arrow fired!")
	_pending_cost = ranged_cost
	# The flight IS the beat between loosing and the turn passing, so the shot is awaited here
	# and the old flat 0.3s pause is gone. _loose_arrow_at rolls the hit on impact and leaves
	# the blood, so nothing about the shot resolves before the arrow gets there.
	await _loose_arrow_at(player)
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
			_do_melee_attack(target)
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
	_begin_move_toward(target)


func _on_weapon_broke(item: ItemResource) -> void:
	## Goblins do not fight on with a ruined weapon: they throw it down and draw whatever else
	## they are carrying. Both are FREE — no _pending_cost is touched and end_my_turn is not
	## called, so this costs no time and never interrupts the turn it happened during. It can
	## fire on the defender's side of someone else's attack, which is exactly why it must not
	## try to drive the turn machinery.
	if inventory == null:
		return
	var slot: int = inventory.get_item_slot(item)
	if slot >= 0:
		inventory.remove_item(slot)  # also unequips it from whichever hand held it
	else:
		inventory.unequip_item(item)
	_drop_at_feet(item)

	var replacement: int = inventory.find_weapon_slot()
	if replacement >= 0:
		inventory.equip(replacement)
		var drawn: ItemResource = inventory.get_equipped_weapon()
		if drawn:
			_show_action_text("Drew " + drawn.item_name)
	_update_health_bar()


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


func _move_toward(target: Node) -> void:
	## Walk the BFS route toward `target`, up to move_range tiles, following it waypoint
	## by waypoint so we route around walls/obstacles/heroes instead of cutting corners.
	## Stop on the last unoccupied tile (the target's own cell / an ally is never a
	## valid endpoint), so movement never ends on — or slices through — another unit.
	var from_tile: Vector3 = _snap_to_grid(position)
	var to_tile: Vector3 = _snap_to_grid(target.position)

	# Cleared up front so a bail-out below can't leave the previous move's tile count
	# behind for get_move_cost() to bill. A unit that goes nowhere still pays the floor
	# of 1, which is what keeps a boxed-in enemy from taking free turns forever.
	_move_tiles = 0

	var path: Array = _find_path(from_tile, to_tile)
	if path.size() <= 1:
		return

	var step_count: int = min(move_range, path.size() - 1)
	while step_count >= 1 and _is_tile_occupied_by_others(path[step_count], self):
		step_count -= 1
	if step_count < 1:
		return

	_follow_path(path.slice(0, step_count + 1))


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
		_do_melee_attack(player)
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


func _on_move_complete() -> void:
	end_my_turn(_pending_cost)


func end_my_turn(cost: int) -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.turn_done(cost)
