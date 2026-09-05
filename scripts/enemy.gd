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
	## Original goblin AI: move toward nearest, weighted random adjacent — unless a guardian
	## has it pinned, in which case that is who it fights (see _pinning_guard).
	var player := _pinning_guard()
	if player == null:
		player = _find_nearest_reachable_player()
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

	# A shut door in the way is worth a turn: open it, and come through it next turn.
	if _try_open_door_toward(player):
		end_my_turn(_pending_cost)
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

	# Pinned in a guardian's zone. The reposition search below would pick a firing tile it
	# cannot legally reach — the guard clip truncates the route to nothing — and the archer
	# would spend the turn shuffling on the spot. Fight what is in front of it instead: point
	# blank if there are arrows left, steel if not.
	var pin := _pinning_guard()
	if pin != null:
		if ammo > 0:
			await _fire_arrow(pin)
		else:
			_action_used = Action.ATTACK
			_do_melee_attack(pin)
			_pending_cost = attack_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
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
		# Backing off to a firing tile, not closing on anyone — so a guardian met on the way
		# has genuinely turned us aside. See _move_intent.
		_move_intent = null
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
	for path in _reachable_paths(get_move_range()):
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
	# Recorded before the route is built: _clip_at_guard needs to know whether a guardian we
	# end up next to is who we were actually coming for.
	_move_intent = target
	# The one place the AI decides to go and get someone, which is exactly what a battle cry
	# is for. _charge_cry fires only the first time in a fight, so this is the moment the
	# enemy comes at you rather than a bellow on every turn it spends walking.
	_charge_cry()
	_move_toward(target)
	_action_used = Action.MOVE
	_pending_cost = get_move_cost()

	# There used to be an unconditional `is_moving = true` here. It was redundant — _follow_path
	# sets the flag whenever it queues a real route — and actively harmful: with nothing queued
	# it left the unit drifting toward a stale target_position from the previous move, which is
	# what used to (accidentally) end the turn of an enemy that was fully boxed in.
	#
	# Three outcomes now, and each has to end the turn exactly once:
	#   route queued   -> is_moving true; _physics_process reaches _on_move_complete.
	#   pinned in a zone -> _follow_path billed the floor and deferred the hook itself.
	#   no route at all -> nothing queued and no hook pending, so end it here.
	#
	# _move_tiles separates the last two: _move_toward zeroes it before pathing and only
	# _follow_path raises it, so 0 means we never got as far as queueing anything. Without this
	# branch a trapped enemy would stop the clock for good.
	if not is_moving and _move_tiles == 0:
		end_my_turn(_pending_cost)


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
	## Boss AI: target weakest player, shove to separate, attack otherwise. A guardian's zone
	## overrides the pick — the boss is the one enemy that deliberately dives the weakest hero,
	## so it is also the one interception has real work to do against.
	var target := _pinning_guard()
	if target == null:
		target = _find_weakest_reachable_player()
	if not target or not target.is_alive:
		end_my_turn(0)
		return

	if is_prone:
		end_my_turn(1)
		return

	# Same as the goblins: a door is a turn's work, not a dead end. Checked before the
	# adjacency test below cannot fire — a door between us and the target means we are not
	# adjacent to the target anyway.
	if not _is_adjacent(target.position) and _try_open_door_toward(target):
		end_my_turn(_pending_cost)
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


func _door_to_open_for(target: Node) -> Node:
	## The shut door standing between us and `target`, if we are already close enough to work
	## it. Null when there is nothing to open, or nothing worth opening.
	##
	## Checked against the route we could take with the doors AS THEY ARE first: if there is
	## already a way round, we take it rather than stopping to open something we never needed.
	## So a door only gets opened when it is genuinely the way through.
	var from_tile: Vector3 = _snap_to_grid(position)
	var to_tile: Vector3 = _snap_to_grid(target.position)
	if _find_path(from_tile, to_tile).size() > 1:
		return null
	var route: Array = _find_path(from_tile, to_tile, -1, true)
	if route.size() <= 1:
		return null
	for tile in route:
		var door: Node = _openable_door_at(tile)
		if door == null:
			continue
		# The FIRST door on the route and no further: a second one behind it is next turn's
		# problem, and we cannot reach past this one to work it anyway.
		#
		# Adjacency is measured to the door's SQUARE, not to the door. _is_adjacent allows half
		# a square of slack, which is right between two units standing on square centres and
		# wrong for a door standing on the line between two — measured raw, a goblin could
		# reach out and work a latch from a square and a half away.
		return door if _is_adjacent(_snap_to_grid((door as Node3D).global_position)) else null
	return null


func _try_open_door_toward(target: Node) -> bool:
	## Spend the turn opening the door in our way, if there is one within reach. True when we
	## did, and the caller should end its turn on that.
	var door: Node = _door_to_open_for(target)
	if door == null:
		return false
	_face_target(door as Node3D)
	door.interact(self)
	_show_action_text("Open!")
	_pending_cost = interact_cost
	return true


func _player_candidates() -> Array:
	## Every hero still standing. The raw pool both target pickers choose from.
	var out: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == self:
			continue
		if not c.is_player_controlled or not c.is_alive:
			continue
		out.append(c)
	return out


func _can_reach(target: Node) -> bool:
	## Is there a route to `target` at all — not this turn, but ever, as the board stands?
	## Asked with the same _find_path the move itself uses, so a target we call reachable is one
	## we can genuinely walk at. Somebody already at arm's length trivially counts.
	if _is_adjacent(target.position):
		return true
	# doors_openable: a shut door is a turn's work, not a wall. Without this a party could put
	# a door between themselves and the goblins and simply stop being a target.
	return _find_path(_snap_to_grid(position), _snap_to_grid(target.position), -1, true).size() > 1


func _reachable_or_all(candidates: Array) -> Array:
	## The candidates we can actually get to, or — if that is none of them — all of them.
	##
	## Reachability as the FIRST sort key, ahead of distance or hp. The hero behind a guarded
	## doorway may be the closest thing on the board, or the most wounded, and still be someone
	## we cannot lay a hand on; picking him anyway is how a goblin spends an entire fight
	## walking into a wall while a wizard stands in the open just beyond him.
	##
	## The fallback matters as much as the rule. When the whole party is behind one shut door
	## nothing is reachable, and an empty list would freeze the AI — so we go back to the full
	## pool and let _find_approach_path walk us at the door, which is the right instinct anyway.
	var reachable: Array = candidates.filter(_can_reach)
	return candidates if reachable.is_empty() else reachable


func _nearest_of(candidates: Array) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for c in candidates:
		var dist: float = abs(c.position.x - position.x) + abs(c.position.z - position.z)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


func _weakest_of(candidates: Array) -> Node:
	var best: Node = null
	var lowest_hp: int = 0
	for c in candidates:
		if best == null or c.hp < lowest_hp:
			lowest_hp = c.hp
			best = c
	return best


func _find_weakest_reachable_player() -> Node:
	## The most wounded hero we can get to. The boss's pick — see _reachable_or_all for why
	## "can get to" comes before "most wounded".
	return _weakest_of(_reachable_or_all(_player_candidates()))


func _find_nearest_reachable_player() -> Node:
	## The nearest hero we can get to. What anything that closes to melee should be walking at.
	return _nearest_of(_reachable_or_all(_player_candidates()))


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
	var step_count := 0
	if path.size() > 1:
		step_count = min(get_move_range(), path.size() - 1)
		while step_count >= 1 and _is_tile_occupied_by_others(path[step_count], self):
			step_count -= 1

	if step_count < 1:
		# Either there is no route to the target at all, or every tile we could stop on along
		# the one there is has somebody standing on it. Both used to end the turn on the spot,
		# which is how a bottleneck — a guarded doorway, say — left the goblins at the back
		# standing around in the chamber all fight while the two at the front did the work.
		#
		# Get as close as we can instead. A unit that cannot reach you should still be coming.
		path = _find_approach_path(to_tile, get_move_range())
		if path.size() <= 1:
			return
		# _find_approach_path only ever ends on a free tile, so there is nothing to walk back.
		step_count = path.size() - 1

	_follow_path(path.slice(0, step_count + 1))


func _pinning_guard() -> Node:
	## The guardian whose zone we are standing in, or null. A pinned enemy fights the guardian
	## and nobody else — it does not reach around him for the softer target behind.
	##
	## This is not the goblin getting clever; it is the opposite. The man in armour is in its
	## face, so that is what it hits. Targeting everywhere else stays exactly as dumb as it was.
	##
	## It is also load-bearing, not flavour. _find_nearest_player measures MANHATTAN distance
	## while _is_adjacent is CHEBYSHEV, so with GRID_SIZE 2 a goblin standing DIAGONALLY off the
	## guardian rates him at 4 — worse than a cardinally-adjacent wizard's 2, and level with a
	## wizard two clear tiles away. Without this the goblin would swing past the guardian's
	## shoulder at her, and since that tie breaks on scene-tree order it would look random.
	return _guard_at(_snap_to_grid(position))


func _find_nearest_player() -> Node:
	## The nearest alive hero, reachable or not.
	##
	## Deliberately NOT the reachable-first pick, and only the archer still uses it: an archer
	## shoots, so being unable to WALK to someone says nothing about being able to hit them.
	## A hero holding a doorway is the archer's best target precisely because he is standing in
	## the one gap in the wall, and filtering him out for being unwalkable would have the
	## archer turn away from the clearest shot on the board.
	return _nearest_of(_player_candidates())


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
	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.turn_done(cost)
