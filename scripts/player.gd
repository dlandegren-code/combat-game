extends "res://scripts/combatant.gd"
## Player character: click-to-move on a grid, click an enemy to use the selected
## ability. Actions are driven by the `abilities` list (see scripts/abilities/):
## the action bar, targeting, cursor and turn cost all read from it, so adding a
## new player skill is just adding an Ability to _build_abilities().

# Slot order of the action bar / abilities list. Values are indices into `abilities`.
enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW, PICKUP, FIREBOLT, INTERACT, PRONE,
	SNEAK }

const MoveAbilityScript := preload("res://scripts/abilities/move_ability.gd")
const MeleeAttackAbilityScript := preload("res://scripts/abilities/melee_attack_ability.gd")
const ShoveAbilityScript := preload("res://scripts/abilities/shove_ability.gd")
const TripAbilityScript := preload("res://scripts/abilities/trip_ability.gd")
const RangedAbilityScript := preload("res://scripts/abilities/ranged_ability.gd")
const ThrowAbilityScript := preload("res://scripts/abilities/throw_ability.gd")
const PickupAbilityScript := preload("res://scripts/abilities/pickup_ability.gd")
const FireboltAbilityScript := preload("res://scripts/abilities/firebolt_ability.gd")
const InteractAbilityScript := preload("res://scripts/abilities/interact_ability.gd")
const ProneAbilityScript := preload("res://scripts/abilities/prone_ability.gd")
const SneakAbilityScript := preload("res://scripts/abilities/sneak_ability.gd")
const ActionCursorsScript := preload("res://scripts/action_cursors.gd")

const FireboltProjectileScript := preload("res://scripts/fx/firebolt_projectile.gd")
const FireSplashScript := preload("res://scripts/fx/fire_splash.gd")
const ThrownWeaponScript := preload("res://scripts/fx/thrown_weapon.gd")

## How far from the square it was aimed at a thrown weapon may come to rest, in tiles.
## Keeps a deflected or dropped weapon within a step or two of the fight rather than
## skidding across the arena where nobody can reasonably go and fetch it.
const THROW_SCATTER_TILES := 2

## The action the player has PINNED, meaningful only while action_pinned is true. Left at its
## last value when unpinned so re-pinning the same thing is one click.
var selected_action: int = Action.MOVE

## False means the action is worked out from whatever the mouse is over — see _resolve_at.
## Clicking a hotbar slot pins that action; clicking the lit slot again lets go.
var action_pinned: bool = false

## Returned by the resolver when a click here would do nothing at all.
const NO_ACTION := -1

## The only actions ever inferred from a hover, in the order they win.
##
## Short on purpose. Everything left out — Shove, Trip, Ranged, Throw, Firebolt — either spends
## something that cannot be got back (ammo, mana, the weapon in your hand) or is a deliberate
## choice rather than the obvious thing to do to the square under the mouse. Those stay pinned
## by hand, which is not friction: they are the interesting decisions.
const INFERRED_TILE_ORDER := [Action.PICKUP, Action.INTERACT]

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
		# Everyone gets this for the same reason everyone gets Firebolt: ability indices are
		# stored in the hotbar, so they have to mean the same thing on every character.
		InteractAbilityScript.new(),
		ProneAbilityScript.new(),
		# Appended, never inserted: the hotbar stores ability INDICES per character, so putting
		# a new action anywhere but the end would silently re-point everybody's saved cells.
		SneakAbilityScript.new(),
	]


func enable_turn() -> void:
	if not is_alive:
		return
	# No automatic stand-up. A character who was knocked down starts their turn on the floor
	# and decides for themselves whether getting up is worth the tick — see prone_ability.gd.
	# The AI still stands by itself (Enemy.enable_turn); it has nobody to ask.
	can_act = true
	selected_action = Action.MOVE
	# And the action goes back to being read off the mouse each turn, rather than carrying last
	# turn's pin into this one.
	action_pinned = false
	_update_action_bar()


func disable_turn() -> void:
	can_act = false
	# A swing owed on arrival dies with the turn that ordered it — otherwise it would fire on
	# the next move this character made, at whoever was still standing there.
	_queued_attack = null
	_queued_attack_slot = NO_ACTION
	# Whatever happened, we are not looting any more. Left set, the next turn's first tile
	# action would decline to end itself and the character would hang.
	_looting = false
	ActionCursorsScript.neutral()
	_hide_indicator()
	_update_action_bar()  # disables buttons in UI


func _process(_delta: float) -> void:
	if not can_act or is_moving:
		return
	_update_cursor()


const HOTBAR_KEYS := 10

## Input action that passes control to the next hero while exploring. Guarded with
## InputMap.has_action at the call site, so a project without the binding simply has no
## party-switch key rather than throwing on every keypress.
const CYCLE_PARTY_ACTION := "cycle_party"


func _unhandled_input(event: InputEvent) -> void:
	if not can_act or is_moving:
		return

	# Switching between heroes, which only exists out of combat: in a fight, whose turn it is
	# is the clock's business and not the player's. Handled on the ACTIVE character only —
	# every other Player node has already returned above on can_act — so one key press cycles
	# once rather than once per party member.
	if InputMap.has_action(CYCLE_PARTY_ACTION) and event.is_action_pressed(CYCLE_PARTY_ACTION):
		var cm := _combat_mgr()
		if cm and cm.has_method("cycle_explorer"):
			cm.cycle_explorer(1)
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
	## An action with nothing to aim at happens the moment it is chosen: arming it and then
	## asking the player to click the battlefield would be asking where they want to stand up.
	if index >= 0 and index < abilities.size() and abilities[index].targets_self():
		_use_self_ability(index)
		return
	## Pin an action. Choosing the one already pinned lets go of it and hands the decision back
	## to the mouse, which is the only way back to automatic without a second control.
	if action_pinned and selected_action == index:
		action_pinned = false
	else:
		selected_action = index
		action_pinned = true
	_update_action_bar()


func _use_self_ability(index: int) -> void:
	## Run a self-targeted action now.
	##
	## A FREE one leaves the turn running. That is the one place in the game a cost of zero is
	## taken literally rather than floored to one: _begin_action and turn_done both round up,
	## because a zero-cost action that ended the turn would not advance the clock and the combat
	## manager would hand this character its turn straight back. Not ending the turn at all
	## sidesteps that entirely — lying down is something you do AND THEN act.
	if not can_act:
		return
	var ability = abilities[index]
	if not ability.can_use(self):
		return
	var cost: int = ability.get_cost(self)
	ability.execute(self, null)
	if cost <= 0:
		_update_action_bar()
		return
	_pending_cost = cost
	can_act = false
	_update_action_bar()
	_end_action_in_place()


func pinned_action() -> int:
	## The slot the toolbar should light, or NO_ACTION for none — an unlit bar is what
	## "whatever the mouse is over" looks like.
	return selected_action if action_pinned else NO_ACTION


# --- Working out what a click would do -------------------------------------

func _resolve_at(screen_pos: Vector2) -> Dictionary:
	## What a click at `screen_pos` would actually do, as {slot, target, tile, reason}.
	##
	## ONE answer, read by both the cursor and the click. They used to work it out separately
	## and could disagree — a pinned Pick Up over an unreachable square showed the forbidden
	## pointer while the click quietly moved you there instead. A pointer that promises one
	## thing and a click that does another is worse than no pointer, so there is now exactly
	## one place that decides.
	##
	## `slot` is NO_ACTION when nothing applies; `reason` then carries why, for the cursor.
	var out := {"slot": NO_ACTION, "target": null, "tile": Vector3.INF, "reason": "",
		"approach": Vector3.INF}
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if camera == null:
		return out
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var space_state := get_world_3d().direct_space_state

	# A pinned self-targeted action needs nothing under the mouse at all.
	if action_pinned and abilities[selected_action].targets_self():
		out.slot = selected_action
		return out

	# Enemies first: a body under the pointer is a stronger statement of intent than the floor
	# it happens to be standing on.
	var enemy_query := PhysicsRayQueryParameters3D.create(from, to)
	enemy_query.collision_mask = LAYER_ENEMY
	var enemy_result := space_state.intersect_ray(enemy_query)
	if not enemy_result.is_empty() and enemy_result.collider.has_method("take_damage"):
		var foe: Node = enemy_result.collider
		out.target = foe
		out.slot = _enemy_action_for(foe)
		if out.slot == NO_ACTION:
			# Out of reach for a swing, but perhaps not for a walk and then a swing.
			var approach: Vector3 = _approach_tile_for(foe)
			if approach != Vector3.INF:
				out.slot = Action.ATTACK
				out.approach = approach
			else:
				var refused = abilities[selected_action] if action_pinned else abilities[Action.ATTACK]
				out.reason = refused.unavailable_reason(self)
		return out

	# Then fittings — a door leaf, and whatever else grows a picker — for the same reason:
	# something you can work, under the pointer, beats the floor behind it.
	#
	# A door is the case that needs this. It answers to the grid square it SEALS, and for a
	# doorway that square is on the far side of the wall and half a square off from the hole in
	# the art, so "click the thing on that square" came out as clicking a patch of floor in the
	# next room while clicking the door did nothing. The picker puts the target back on the
	# door; the square still works, and is still what the rules use. See door.gd's header.
	#
	# Falls through when the fitting is out of reach or not this action's business, rather than
	# refusing the click: the floor behind an open door's swung-aside leaf is a fair place to
	# walk, and it would be strange for the leaf to be a hole in the battlefield.
	var fitting_query := PhysicsRayQueryParameters3D.create(from, to)
	fitting_query.collision_mask = LAYER_INTERACT
	var fitting_result := space_state.intersect_ray(fitting_query)
	if not fitting_result.is_empty():
		var fitting: Node = _fitting_of(fitting_result.collider)
		if fitting != null:
			var fit_tile: Vector3 = _snap_to_grid((fitting as Node3D).global_position)
			fit_tile.y = position.y
			if _interactable_at(fit_tile) == fitting:
				var fit_slot: int = _tile_action_for(fit_tile)
				if fit_slot != NO_ACTION:
					out.tile = fit_tile
					out.slot = fit_slot
					return out

	var ground_query := PhysicsRayQueryParameters3D.create(from, to)
	ground_query.collision_mask = LAYER_GROUND
	var ground_result := space_state.intersect_ray(ground_query)
	if ground_result.is_empty():
		return out
	var clicked: Vector3 = ground_result.position
	clicked.y = position.y
	out.tile = _snap_to_grid(clicked)
	out.slot = _tile_action_for(out.tile)
	if out.slot == NO_ACTION:
		out.reason = "range"
	return out


func _enemy_action_for(foe: Node) -> int:
	## Which action a click on `foe` runs. Pinned: that one, if it will take him. Otherwise the
	## plain melee attack when he is close enough to hit, and nothing at all when he is not.
	##
	## Nothing at all, rather than walking toward him: closing the distance and swinging is two
	## actions and most of a turn, and inventing it here would spend a turn the player never
	## agreed to. The forbidden pointer says so before the click.
	if action_pinned:
		var pinned = abilities[selected_action]
		if pinned.targets_enemy() and pinned.can_target(self, foe):
			return selected_action
		return NO_ACTION
	return Action.ATTACK if abilities[Action.ATTACK].can_target(self, foe) else NO_ACTION


func _approach_tile_for(foe: Node) -> Vector3:
	## The square to stand on to hit `foe`, when they are too far off to reach from here —
	## INF when there is no getting to them this turn.
	##
	## Taken off the shortest route to their OWN square rather than searched for separately:
	## _find_path leaves the goal square passable so a unit can path onto its target, which
	## makes the step before it a nearest square you can actually stand on and swing from. One
	## path search instead of one per neighbour, and it agrees with movement by construction.
	##
	## Melee only. A pinned bow or spell that is out of range stays refused: walking into range
	## and then shooting is a different promise, and one the range rules should make, not this.
	if action_pinned and selected_action != Action.ATTACK:
		return Vector3.INF
	if not _can_move() or not ("is_alive" in foe) or not foe.is_alive:
		return Vector3.INF
	var foe_tile: Vector3 = _snap_to_grid((foe as Node3D).position)
	# One further than we can walk: the last step of this route lands ON the target, and that
	# step is the one we do not take.
	var route: Array = _find_path(_snap_to_grid(position), foe_tile, get_move_range() + 1)
	if route.size() < 2:
		return Vector3.INF
	var stand_on: Vector3 = route[route.size() - 2]
	# Already standing there means we were adjacent all along, which _enemy_action_for handles.
	return Vector3.INF if stand_on.distance_to(_snap_to_grid(position)) < 0.5 else stand_on


func _tile_action_for(tile: Vector3) -> int:
	## Which action a click on `tile` runs. A pinned tile-action gets first refusal; failing
	## that — and when nothing is pinned — the square is read for what is on it, and Move is
	## the answer to everything else.
	if action_pinned:
		var pinned = abilities[selected_action]
		if pinned.targets_tile() and selected_action != Action.MOVE and pinned.can_target(self, tile):
			return selected_action
	else:
		for slot in INFERRED_TILE_ORDER:
			if abilities[slot].can_target(self, tile):
				return slot
	return Action.MOVE if abilities[Action.MOVE].can_target(self, tile) else NO_ACTION


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
		ActionCursorsScript.neutral()
		_hide_indicator()
		return
	# Pointer is over a panel or a toolbar cell, so it is not aiming at the battlefield.
	# Without this the move indicator still lit up on the tile UNDERNEATH an open window,
	# advertising a move the click can no longer make.
	if viewport.gui_get_hovered_control() != null:
		ActionCursorsScript.neutral()
		_hide_indicator()
		return

	var res := _resolve_at(mouse_pos)
	if res.slot == NO_ACTION:
		# Nothing doing here. "resource" gets the help cursor — the action fits this target but
		# something is missing — and everything else the forbidden one.
		if res.reason == "resource":
			ActionCursorsScript.show_action(ActionCursorsScript.HELP)
		elif res.target != null or res.tile != Vector3.INF:
			ActionCursorsScript.forbidden()
		else:
			ActionCursorsScript.neutral()
		_hide_indicator()
		return

	if res.slot == Action.MOVE:
		ActionCursorsScript.move()
		_show_indicator(res.tile)
		return

	if res.approach != Vector3.INF:
		# Walk-then-swing. The sword says what the click ends in, and the floor indicator on
		# the approach square says where it ends UP — between them the player can see the whole
		# move before committing to it.
		ActionCursorsScript.show_action(abilities[res.slot].get_cursor_icon(self, res.target))
		_show_indicator(res.approach)
		return

	# The resolved action's own pointer — a sword, a bow, a backpack — so the mouse says WHAT
	# the click will do, not merely that it will do something.
	var what = res.target if res.target != null else res.tile
	ActionCursorsScript.show_action(abilities[res.slot].get_cursor_icon(self, what))
	_hide_indicator()


func _show_indicator(at: Vector3) -> void:
	if move_indicator:
		move_indicator.position = Vector3(at.x, 0.16, at.z)
		move_indicator.visible = true


func _hide_indicator() -> void:
	if move_indicator:
		move_indicator.visible = false


func _handle_click(screen_pos: Vector2) -> void:
	## Do the thing the cursor has been promising. See _resolve_at: the promise and the deed
	## come from the same call, so they cannot come apart.
	var res := _resolve_at(screen_pos)
	if res.slot == NO_ACTION:
		return
	var ability = abilities[res.slot]
	ActionCursorsScript.neutral()
	_hide_indicator()

	# Starting something is the other way exploration ends. Swing at a goblin and the room is a
	# fight, whether or not anybody had noticed you — see CombatManager.raise_alarm, which lets
	# this action finish as the opening blow and begins the order when it reports in.
	#
	# Sited here rather than in each hostile branch below because both of them (a swing in
	# reach, and a walk-and-swing) come through this one call, and a third would too.
	var foe = res.get("target")
	if foe != null and is_instance_valid(foe) and _is_hostile(foe):
		var cm := _combat_mgr()
		if cm and cm.has_method("raise_alarm"):
			cm.raise_alarm(self)

	if res.slot == Action.MOVE:
		_begin_action(Action.MOVE)
		ability.execute(self, res.tile)   # sets target_position + is_moving
		return

	if ability.targets_self():
		_begin_action(res.slot)
		ability.execute(self, null)
		_end_action_in_place()
		return

	if res.approach != Vector3.INF:
		# Crossing the floor first. The turn is NOT ended here: _on_move_complete picks the
		# attack back up on arrival and bills the walk and the swing together.
		_queued_attack = res.target
		_queued_attack_slot = res.slot
		can_act = false
		_update_action_bar()
		_face_target(res.target)
		# Shout as the run STARTS. Without this a move-and-attack is silent for the whole walk
		# and then fires four sounds inside a tenth of a second on arrival — which is what
		# "the sound triggers too late" is: not one sound mistimed, but everything bunched at
		# the far end of a second of running. The grunt and the blow still land on the swing;
		# this fills the charge.
		_charge_shout()
		_start_path_move(res.approach, res.target)
		return

	if ability.targets_enemy():
		_face_target(res.target)
		_begin_action(res.slot)
		# The turn is spent the moment the ability fires, so stop taking orders now rather than
		# when it finishes: a Firebolt spends most of a second in the air, and without this the
		# player could queue a second action mid-flight.
		can_act = false
		_update_action_bar()
		# Awaited because an ability may have a projectile to land before it resolves
		# (Firebolt), and the turn must not end under it. Awaiting a plain function returns
		# straight away, so every other ability behaves exactly as before.
		await ability.execute(self, res.target)
		_end_action_in_place()
		return

	_begin_action(res.slot)
	ability.execute(self, res.tile)
	if _looting:
		# The window has the turn now. Stop taking battlefield orders, but do NOT end it —
		# finish_looting does that once the player is done taking things.
		can_act = false
		_update_action_bar()
		return
	_end_action_in_place()


# --- Looting ----------------------------------------------------------------
#
# A loot window suspends the turn instead of ending it. Opening the container costs its own
# tick, each item taken costs a Pick Up's worth, and the total is billed once when the window
# closes. Anything else would mean either a turn per item — which is nobody's idea of opening a
# box — or free loot.

## Who to hit on arrival, and with what, when a click ordered a move-and-attack. Null the rest
## of the time. See _run_queued_attack.
var _queued_attack: Node = null
var _queued_attack_slot: int = NO_ACTION

## True from the moment a loot window opens until it closes. While set, _handle_click leaves
## the turn running (see the tile branch) and can_act is false, so the battlefield ignores
## clicks and only the window is live.
var _looting := false


func loot_take_cost() -> int:
	## The time price of taking one item: whatever a Pick Up costs, asked of the ability rather
	## than written down again here, so the two cannot drift apart.
	return max(1, abilities[Action.PICKUP].get_cost(self))


func take_loot(container, index: int) -> void:
	## Take one item out of `container`, and pay for it only if it actually moved — a bag too
	## full to hold it has cost the character nothing but the reach.
	if container == null or not is_instance_valid(container):
		return
	if container.take(index, self):
		_pending_cost += loot_take_cost()


func finish_looting() -> void:
	## The window has closed. Settle up: the turn has been waiting on this.
	if not _looting:
		return
	_looting = false
	_end_action_in_place()


func _loot_window_open() -> bool:
	for w in get_tree().get_nodes_in_group("loot_window"):
		if w.visible:
			return true
	return false


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

	# Copy the model out of the hand while it is still there — unequipping empties the socket
	# and leaves nothing to fly.
	var flying_visual := take_held_weapon_visual()
	var impact_point: Vector3 = target.global_position + Vector3(0, PROJECTILE_IMPACT_HEIGHT, 0)
	var origin := get_projectile_origin(impact_point)

	# Wind up first, and only then let go: the weapon has to stay in the fist while the arm
	# comes over, or the character throws an empty hand and the axe appears out of nowhere.
	await get_tree().create_timer(SWING_WINDUP).timeout
	if not is_inside_tree():
		return

	# Remove the thrown weapon from the character's equipment
	if inventory and inventory.has_method("unequip_slot"):
		inventory.unequip_slot(ItemResource.EquipSlot.RIGHT_HAND)
	var slot := -1
	if inventory and inventory.has_method("get_item_slot"):
		slot = inventory.get_item_slot(thrown_item)
	if slot >= 0 and inventory and inventory.has_method("remove_item"):
		inventory.remove_item(slot)
	_update_health_bar()

	# Release: the arc of the arm, then the weapon itself. Only when it lands is the throw
	# rolled — the same arrangement as the bow and the Firebolt. _handle_click awaits the whole
	# ability, so the turn cannot end with the axe still in the air.
	SwordSwingScript.hurl(get_parent(), global_position, impact_point,
		clampf(float(get_attack_damage()) / SWING_REFERENCE_DAMAGE, 0.6, 1.6))
	if flying_visual != null:
		var weapon = ThrownWeaponScript.hurl(get_parent(), origin, impact_point, flying_visual)
		await weapon.impacted

	if not is_instance_valid(target):
		# Target gone while the weapon was in the air. Nothing left to roll against, but the
		# weapon still has to end up somewhere pickup-able, so it drops where it was aimed.
		_spawn_ground_item(
			thrown_item, Vector3(impact_point.x, GroundItemScript.DROP_Y, impact_point.z))
		return
	# A target that died mid-flight cannot defend, so the throw counts as landed and the weapon
	# drops beside the body rather than skidding past as a miss would.
	var defended: bool = target.is_alive and target.take_damage(
		get_attack_damage(), get_missile_skill(throw_skill, target, get_throw_range()),
		true, self)

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

## How far you can reach to work a door or a chest, in tiles. Arm's length, like Pick Up:
## you open a door by standing next to it, from either side.
const INTERACT_REACH_TILES := 1


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
		# The item has to be ON the square that was clicked, not merely the nearest one to it.
		#
		# This used to accept any pickup within reach and let the clicked tile choose between
		# them, which was friendly to a sloppy click and fatal to inferring the action from the
		# hover: standing next to a dagger made "Pick Up" a legal reading of EVERY square,
		# including the one you meant to walk to. Now the two readings cannot both apply.
		if not _on_tile(gi_node, tile):
			continue
		var d: float = abs(gi_node.position.x - tile.x) + abs(gi_node.position.z - tile.z)
		if d < best_d:
			best_d = d
			best = gi
	return best


func _on_tile(node: Node3D, tile: Vector3) -> bool:
	## Whether `node` stands on the grid square `tile`. Snapped rather than compared directly,
	## because a dropped item lands wherever it lands and a door sits on the line between two
	## squares — see Combatant._is_obstacle_at, which snaps for the same reason.
	var cell: Vector3 = _snap_to_grid(node.global_position)
	return absf(cell.x - tile.x) < 0.5 and absf(cell.z - tile.z) < 0.5


func _fitting_of(collider: Object) -> Node:
	## The interactable a pointer hit box belongs to, or null.
	##
	## Walked up the tree rather than read off the body, because a picker hangs wherever it has
	## to hang to sit on the art — a door's rides the hinge so it swings with the leaf — and the
	## thing that answers can_interact / interact is the node the whole fitting is built under.
	var node := collider as Node
	while node != null:
		if node.is_in_group("interactables") and node is Node3D:
			return node
		node = node.get_parent()
	return null


func _interactable_at(tile: Vector3) -> Node:
	## The door/chest/lever a click at `tile` should work: whatever is in the "interactables"
	## group, is willing to be worked right now, lies within reach of US, and is nearest the
	## square that was actually CLICKED. Two doors side by side therefore open the one pointed
	## at rather than the one that happens to be closest to the character.
	##
	## Reach is measured to the thing's own position rather than to its grid cell. A door
	## stands in a doorway, which is a hole in a wall on the boundary BETWEEN two squares, so
	## snapping it to a cell first would put it a whole cell further away than it looks.
	var best: Node = null
	var best_d := INF
	for it in get_tree().get_nodes_in_group("interactables"):
		if not is_instance_valid(it):
			continue
		var node := it as Node3D
		if node == null:
			continue
		if it.has_method("can_interact") and not it.can_interact(self):
			continue
		var reach: float = max(
			abs(node.global_position.x - position.x), abs(node.global_position.z - position.z))
		if reach > INTERACT_REACH_TILES * GRID_SIZE:
			continue
		# On the clicked square, for the same reason Pick Up now insists on it — see _on_tile.
		# For a door that square is the doorway itself, not the square you stand on to work it.
		if not _on_tile(node, tile):
			continue
		var d: float = abs(node.global_position.x - tile.x) + abs(node.global_position.z - tile.z)
		if d < best_d:
			best_d = d
			best = it
	return best


func _do_interact(target_tile: Vector3 = Vector3.INF) -> void:
	## Work the thing on the clicked tile. The verb is read off the target rather than decided
	## here, so "Open" and "Close" are the same action and the floating text still says which
	## of the two just happened.
	var ref: Vector3 = target_tile if target_tile != Vector3.INF else position
	var thing: Node = _interactable_at(ref)
	if thing == null:
		_show_action_text("Nothing to open")
		return
	var verb: String = thing.interact_verb() if thing.has_method("interact_verb") else "Use"
	_face_target(thing as Node3D)
	thing.interact(self)
	# Ask what it wants NOW, after being worked: a chest that was locked a moment ago may have
	# just been opened, and a corpse was lootable all along. Whoever says yes gets the window,
	# and the turn stays open while the player decides what to take — finish_looting ends it.
	_looting = false
	if thing.has_method("wants_loot_window") and thing.wants_loot_window():
		for w in get_tree().get_nodes_in_group("loot_window"):
			w.show_for(thing, self)
		_looting = _loot_window_open()
	if not _looting:
		_show_action_text(verb + "!")


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
	# Potions, quivers and arrow bundles used to be spent the instant they were picked up. They
	# go in the bag now: drinking a potion is a decision with a moment's cost to it, and it
	# should be possible to carry one for when it is needed. Using them is a separate action —
	# see use_item, wired to the bag slots by InventoryUI.
	# Everything goes into the inventory — and straight into a free hand if
	# that is what it found, so fetching a thrown weapon back arms you in the same action
	# instead of costing a second turn to draw it.
	if inventory and inventory.has_method("add_item") and inventory.add_item(item):
		var drew: bool = inventory.has_method("try_auto_equip_hand") \
			and inventory.try_auto_equip_hand(item)
		# "Drew" is the wording the weapon-break replacement already uses for the same event.
		_show_action_text(("Drew " if drew else "Picked up ") + item.item_name)
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
	# Priced by the item, floored at the character's own equip_cost: drawing a blade is quick,
	# strapping a shield or buckling a helmet is not, and body armour is slower still. This is
	# the same number that decides what may be auto-equipped on pickup.
	var cost: int = equip_cost
	if equipped:
		cost = max(cost, equipped.get_equip_time())
	_pending_cost = max(1, cost)
	_end_action_in_place()


func use_item(slot_index: int) -> void:
	## Drink a potion, or take the arrows from a quiver. A full action, priced the same way
	## equipping is: the potion is a swallow, the quiver has to be slung and sorted.
	if not can_act or is_moving:
		return
	if not inventory or not inventory.has_method("use_consumable"):
		return
	var item: ItemResource = inventory.items[slot_index] if slot_index < inventory.items.size() else null
	if item == null:
		return
	# use_consumable puts up its own "+8 HP" / "+9 arrows" text and clears the bag slot.
	if not inventory.use_consumable(slot_index):
		_show_action_text("Cannot use " + item.item_name)
		return
	_update_health_bar()
	_pending_cost = max(1, max(equip_cost, item.get_equip_time()))
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
	# Priced by the item, like equipping — but off its own unequip time, which is quick for
	# everything except body armour (see ItemResource.get_unequip_time).
	_pending_cost = max(1, max(equip_cost, item.get_unequip_time()))
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
	if _queued_attack != null:
		# Arrived with a swing owed. _run_queued_attack ends the turn itself, once the blow has
		# landed — awaiting it here would mean the turn ended before the animation.
		_run_queued_attack()
		return
	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.turn_done(max(_pending_cost, 1))


func _run_queued_attack() -> void:
	## The second half of a move-and-attack: we have arrived, so swing.
	##
	## Adjacency is checked AGAIN rather than assumed. A guardian's zone can stop a move short
	## (see Combatant._clip_at_guard), and the target can die to something else while we are
	## still walking — in both cases the walk happened and is charged for, and the swing simply
	## does not. Being intercepted on the way to someone is a real outcome, not an error.
	var foe: Node = _queued_attack
	var slot: int = _queued_attack_slot
	_queued_attack = null
	_queued_attack_slot = NO_ACTION

	var walked: int = get_move_cost()
	if is_instance_valid(foe) and foe.is_alive and _is_adjacent(foe.position) 			and slot >= 0 and slot < abilities.size():
		_face_target(foe as Node3D)
		# Walk AND swing: the whole turn is one bill, so a move-and-attack costs exactly what
		# doing the two separately would have.
		_pending_cost = walked + max(1, abilities[slot].get_cost(self))
		await abilities[slot].execute(self, foe)
	else:
		_pending_cost = walked
		_show_action_text("Stopped short!")

	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.turn_done(max(_pending_cost, 1))
