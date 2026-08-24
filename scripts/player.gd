extends "res://scripts/combatant.gd"
## Player character: click-to-move on a grid, click an enemy to use the selected
## ability. Actions are driven by the `abilities` list (see scripts/abilities/):
## the action bar, targeting, cursor and turn cost all read from it, so adding a
## new player skill is just adding an Ability to _build_abilities().

# Slot order of the action bar / abilities list. Values are indices into `abilities`.
enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW, PICKUP, FIREBOLT }

const MoveAbilityScript := preload("res://scripts/abilities/move_ability.gd")
const MeleeAttackAbilityScript := preload("res://scripts/abilities/melee_attack_ability.gd")
const ShoveAbilityScript := preload("res://scripts/abilities/shove_ability.gd")
const TripAbilityScript := preload("res://scripts/abilities/trip_ability.gd")
const RangedAbilityScript := preload("res://scripts/abilities/ranged_ability.gd")
const ThrowAbilityScript := preload("res://scripts/abilities/throw_ability.gd")
const PickupAbilityScript := preload("res://scripts/abilities/pickup_ability.gd")
const FireboltAbilityScript := preload("res://scripts/abilities/firebolt_ability.gd")

const FireboltProjectileScript := preload("res://scripts/fx/firebolt_projectile.gd")
const FireSplashScript := preload("res://scripts/fx/fire_splash.gd")

## How far from the square it was aimed at a thrown weapon may come to rest, in tiles.
## Keeps a deflected or dropped weapon within a step or two of the fight rather than
## skidding across the arena where nobody can reasonably go and fetch it.
const THROW_SCATTER_TILES := 2

var selected_action: int = Action.MOVE

var move_indicator: MeshInstance3D


func _post_setup() -> void:
	_build_abilities()
	move_indicator = get_parent().get_node_or_null("MoveIndicator")
	if move_indicator:
		move_indicator.visible = false


func _build_abilities() -> void:
	# Order must match the Action enum. The toolbar's hotbar seeds itself from this order.
	abilities = [
		MoveAbilityScript.new(),
		MeleeAttackAbilityScript.new(),
		ShoveAbilityScript.new(),
		TripAbilityScript.new(),
		RangedAbilityScript.new(),
		ThrowAbilityScript.new(),
		PickupAbilityScript.new(),
		# Given to everyone rather than only to casters, so ability indices stay the same for
		# every character (the hotbar stores them). A non-caster's can_use() is false, so the
		# cell greys out exactly as Ranged does without a bow.
		FireboltAbilityScript.new(),
	]


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


const HOTBAR_KEYS := 8


func _unhandled_input(event: InputEvent) -> void:
	if not can_act or is_moving:
		return
	# The number keys drive hotbar SLOTS, not ability indices. The slots are reassignable, so
	# "3" has to fire whatever the player dropped into the third cell.
	for slot in range(HOTBAR_KEYS):
		var action := "action_" + str(slot + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_activate_hotbar_slot(slot)
			return

	# World clicks live here rather than in _input() because Godot runs _input() BEFORE any
	# Control sees the event. Handling them there meant a click on an inventory slot ALSO
	# ordered the character to the tile behind the panel — it moved instead of equipping.
	# From _unhandled_input the GUI gets first refusal: a slot calls accept_event(), and the
	# panel behind it stops mouse events by default, so neither reaches the battlefield.
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_handle_click((event as InputEventMouseButton).position)


func _activate_hotbar_slot(slot: int) -> void:
	for bar in get_tree().get_nodes_in_group("action_toolbar"):
		var idx: int = bar.ability_in_slot(slot)
		if idx >= 0 and idx < abilities.size():
			select_action(idx)
		return


func select_action(index: int) -> void:
	selected_action = index
	_update_action_bar()


func _update_action_bar() -> void:
	## Push our state to the bottom toolbar. Found by group rather than by path so the toolbar
	## can be moved or re-parented in the scene without touching this.
	for bar in get_tree().get_nodes_in_group("action_toolbar"):
		bar.refresh()


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
	# Pointer is over a panel or a toolbar cell, so it is not aiming at the battlefield.
	# Without this the move indicator still lit up on the tile UNDERNEATH an open window,
	# advertising a move the click can no longer make.
	if viewport.gui_get_hovered_control() != null:
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
				# The turn is spent the moment the ability fires, so stop taking orders now
				# rather than when it finishes: a Firebolt spends most of a second in the air,
				# and without this the player could queue a second action mid-flight.
				can_act = false
				_update_action_bar()
				# Awaited because an ability may have a projectile to land before it resolves
				# (Firebolt), and the turn must not end under it. Awaiting a plain function
				# returns straight away, so every other ability behaves exactly as before.
				await ability.execute(self, collider)
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


func _do_firebolt(target: Node) -> void:
	## Mana is spent through spend_mana, which is the affordability check and the payment in
	## one — so the bolt cannot fire on an empty pool even if something bypassed can_use().
	if not spend_mana(FireboltAbilityScript.MANA_COST):
		_show_action_text("Not enough mana!")
		return
	_show_action_text("Firebolt!  %d mana left" % mana)
	_update_health_bar()

	# The bolt is a real projectile, so the attack is rolled when the fire ARRIVES rather than
	# at the click. That is what keeps the damage number, the hit reaction and the splash on
	# the same frame as the impact instead of half a second ahead of it. _handle_click awaits
	# the whole ability for the same reason — the turn must not end while the bolt is in the air.
	var impact_point: Vector3 = target.global_position + Vector3(0, PROJECTILE_IMPACT_HEIGHT, 0)
	var bolt = FireboltProjectileScript.fire(
		get_parent(), get_projectile_origin(impact_point), impact_point)
	await bolt.impacted

	if not is_instance_valid(target) or not target.is_alive:
		return
	# Resolved as a missile: same distance/engaged modifiers and the same defences as an arrow,
	# rather than magic getting its own parallel rules.
	var to_hit: int = get_missile_skill(
		get_spell_power(), target, FireboltAbilityScript.RANGE_TILES)
	var dmg: int = get_spell_power() + FireboltAbilityScript.DAMAGE_BONUS
	# FIRE, so armour does not soak it — but resistance still does.
	var defended: bool = target.take_damage(dmg, to_hit, true, self, DamageType.FIRE)
	# Only a bolt that got through bursts. A parried or dodged one is snuffed out, and the
	# defender's own "Parry!" / "Dodge!" text is the feedback for that — a splash there would
	# say the fire landed when the whole point is that it did not.
	if not defended:
		FireSplashScript.burst(get_parent(), impact_point, target.get_feet_y())


func _do_ranged_attack(target: Node) -> void:
	if ammo <= 0:
		_show_action_text("No ammo!")
		return
	ammo -= 1
	_update_health_bar()
	_show_action_text(str(ammo) + " arrows left")
	# Same arrangement as the Firebolt: the arrow is a real projectile, so the shot is rolled
	# when it ARRIVES rather than at the click, and _handle_click awaits the whole ability so
	# the turn cannot end while the arrow is still in the air.
	await _loose_arrow_at(target)


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

	var defended: bool = target.take_damage(
		get_attack_damage(), get_missile_skill(throw_skill, target, get_throw_range()), true, self)
	# Remove the thrown weapon from the character's equipment
	if inventory and inventory.has_method("unequip_slot"):
		inventory.unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
	var slot := -1
	if inventory and inventory.has_method("get_item_slot"):
		slot = inventory.get_item_slot(thrown_item)
	if slot >= 0 and inventory and inventory.has_method("remove_item"):
		inventory.remove_item(slot)
	_update_health_bar()

	# Either way the weapon comes to rest near the square it was aimed at — a deflected
	# throw carries on past the target, a connecting one drops beside them.
	var land_pos: Vector3
	if defended:
		_show_action_text("Throw missed!")
		land_pos = _throw_landing_tile(target, throw_dir, true)
	else:
		_show_action_text("Weapon thrown!")
		land_pos = _throw_landing_tile(target, throw_dir, false)
	_spawn_ground_item(thrown_item, Vector3(land_pos.x, GroundItemScript.DROP_Y, land_pos.z))


func _throw_landing_tile(target: Node, throw_dir: Vector3, deflected: bool) -> Vector3:
	## The square a thrown weapon comes to rest on: at most THROW_SCATTER_TILES from the
	## target's own square. A deflected throw carries on along the flight path; one that
	## connects drops in a random direction beside the target.
	##
	## The offset is built from whole grid steps rather than a free vector: _snap_to_grid
	## floors, so a diagonal world-space offset of two tiles quietly lands one square short.
	##
	## The distance steps in until the square is somewhere the weapon could actually be
	## retrieved from — a pillar's cell or anywhere outside the arena would strand it — and
	## falls back to the target's own square, which is always reachable.
	var home: Vector3 = target._snap_to_grid(target.position)
	var step: Vector3 = _to_grid_step(throw_dir) if deflected else GRID_DIRS[randi() % GRID_DIRS.size()]
	var tiles: int = randi_range(1, THROW_SCATTER_TILES)
	while tiles >= 1:
		var tile: Vector3 = _snap_to_grid(home + step * tiles)
		if _is_in_arena(tile) and not _is_obstacle_at(tile):
			return tile
		tiles -= 1
	return home


func _to_grid_step(v: Vector3) -> Vector3:
	## Quantise a free direction to one of the 8 grid steps. Same rule as _apply_push: a
	## component past 0.4 of a normalised vector counts, so a diagonal keeps both axes.
	var step := Vector3.ZERO
	if abs(v.x) > 0.4:
		step.x = sign(v.x) * GRID_SIZE
	if abs(v.z) > 0.4:
		step.z = sign(v.z) * GRID_SIZE
	if step == Vector3.ZERO:
		step.x = GRID_SIZE
	return step


## King-move reach (in tiles) for grabbing a ground item: 1 = any of the 8 surrounding
## squares (or the hero's own tile). Uses Chebyshev distance to match _is_adjacent and
## the 8-directional movement/melee model, so a diagonally-adjacent item is reachable
## even when a pillar blocks the cardinal approach cell.
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
		var reach: float = max(abs(gi_node.position.x - position.x), abs(gi_node.position.z - position.z))
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
	# The item stays referenced in the bag slot; capture it so we can name what was actually
	# equipped (equip() may route a 1H weapon to the off-hand when the main hand is full).
	var equipped: ItemResource = inventory.items[slot_index] if slot_index < inventory.items.size() else null
	inventory.equip(slot_index)
	var item_name := "nothing"
	var hand := ""
	if equipped:
		item_name = equipped.item_name
		if inventory.get("right_hand") == equipped:
			hand = " (main hand)"
		elif inventory.get("left_hand") == equipped:
			hand = " (off-hand)"
	_show_action_text("Equipped " + item_name + hand)
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
	if inventory.get("right_hand") == item or inventory.get("left_hand") == item \
			or inventory.get("armor") == item or inventory.get("helmet") == item \
			or inventory.get("legs") == item:
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
