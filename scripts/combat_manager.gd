extends Node
## Tick-based combat manager: time-unit system with action costs

signal turn_changed(combatant: Node)

var combatants: Array[Node] = []
var current_combatant: Node = null
var current_tick: int = 0
var game_over := false

var turn_label: Label
var order_list: VBoxContainer


func _ready() -> void:
	turn_label = get_parent().get_node("HUD/TurnLabel")
	order_list = get_parent().get_node("InitiativePanel/Panel/OrderList")

	# Wire action bar buttons
	var ab := get_parent().get_node_or_null("ActionBar")
	if ab:
		for i in range(7):
			var btn: Button = ab.get_node("Panel/Bar/Btn" + str(i + 1))
			if btn:
				btn.pressed.connect(_on_action_selected.bind(i))

	_collect_combatants()
	_spawn_ground_items()
	if combatants.is_empty():
		return
	_start_combat()


func _on_action_selected(index: int) -> void:
	if not current_combatant or not current_combatant.is_player_controlled:
		return
	if current_combatant.has_method("select_action"):
		current_combatant.select_action(index)


func _collect_combatants() -> void:
	var all := get_tree().get_nodes_in_group("combatants")
	for c in all:
		if is_instance_valid(c):
			c.next_turn_at = 0
			combatants.append(c)


func _start_combat() -> void:
	# Initial order: initiative descending (higher goes first at tick 0)
	combatants.sort_custom(func(a, b): return a.initiative > b.initiative)
	current_tick = 0
	_activate_next()


func _activate_next() -> void:
	if game_over:
		return

	# Find combatant with minimum next_turn_at; ties broken by initiative
	var best: Node = null
	var best_tick: int = 0x7FFFFFFF
	var best_init: int = -1

	for c in combatants:
		if not is_instance_valid(c) or not c.is_alive:
			continue
		if c.next_turn_at < best_tick:
			best_tick = c.next_turn_at
			best_init = c.initiative
			best = c
		elif c.next_turn_at == best_tick and c.initiative > best_init:
			best_init = c.initiative
			best = c

	if not best:
		game_over = true
		if turn_label:
			turn_label.text = "The battlefield is silent..."
		return

	current_tick = best_tick
	current_combatant = best

	_update_initiative_display()
	_update_turn_label(best)

	best.enable_turn()
	turn_changed.emit(best)

	if not best.is_player_controlled and best.has_method("take_turn"):
		best.call_deferred("take_turn")


func turn_done(cost: int) -> void:
	if game_over or not current_combatant:
		return

	if is_instance_valid(current_combatant) and current_combatant.has_method("disable_turn"):
		current_combatant.disable_turn()

	current_combatant.next_turn_at += cost
	current_combatant = null
	_activate_next.call_deferred()


func on_character_died(who: Node) -> void:
	if game_over:
		return

	# Win/loss check
	var players_alive := false
	var enemies_alive := false
	for c in combatants:
		if not is_instance_valid(c) or not c.is_alive:
			continue
		if c.is_player_controlled:
			players_alive = true
		else:
			enemies_alive = true

	if not enemies_alive:
		game_over = true
		turn_label.text = "Victory! All enemies defeated."
		_update_initiative_display()
		return
	if not players_alive:
		game_over = true
		turn_label.text = "Defeat! All heroes have fallen."
		_update_initiative_display()
		return

	# If dead combatant was the current actor, advance
	if current_combatant == who:
		current_combatant = null
		_activate_next()


func _update_initiative_display() -> void:
	if not order_list:
		return
	for child in order_list.get_children():
		child.queue_free()

	var sorted := combatants.duplicate()
	sorted.sort_custom(func(a, b):
		if a.next_turn_at != b.next_turn_at:
			return a.next_turn_at < b.next_turn_at
		return a.initiative > b.initiative
	)

	for c in sorted:
		if not is_instance_valid(c):
			continue

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)

		var text: String = c.character_name + "  T" + str(c.next_turn_at)
		if not c.is_alive:
			label.self_modulate = Color(0.5, 0.5, 0.5, 1)
		elif c == current_combatant and not game_over:
			text = "> " + text + " <"
			label.self_modulate = Color(1, 1, 0.3, 1)
		else:
			label.self_modulate = Color(1, 1, 1, 1)

		label.text = text
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		order_list.add_child(label)


func charge_defense_cost(defender: Node) -> void:
	## Called when a defender successfully parries or dodges. Costs 1 time unit.
	if is_instance_valid(defender):
		defender.next_turn_at += 1


func _update_turn_label(combatant: Node) -> void:
	if turn_label:
		turn_label.text = combatant.character_name + "'s Turn  (T" + str(current_tick) + ")"


func _spawn_ground_items() -> void:
	## Spawn pickups on the battlefield at combat start
	# Health Potion at (-2, 0.2, 5)
	var potion := ItemResource.new()
	potion.item_name = "Health Potion"
	potion.item_type = ItemResource.ItemType.CONSUMABLE
	potion.heal_amount = 8
	_spawn_gi(potion, Vector3(-2, 0.2, 5))

	# Arrow Bundle at (3, 0.2, -3)
	var arrows := ItemResource.new()
	arrows.item_name = "Arrow Bundle"
	arrows.item_type = ItemResource.ItemType.AMMO
	arrows.ammo_amount = 4
	_spawn_gi(arrows, Vector3(3, 0.2, -3))

	# Warhammer at (1, 0.2, -5)
	var hammer := ItemResource.new()
	hammer.item_name = "Warhammer"
	hammer.item_type = ItemResource.ItemType.WEAPON
	hammer.attack_bonus = 1
	hammer.damage_bonus = 3
	hammer.durability = 8
	hammer.throw_range = 3
	_spawn_gi(hammer, Vector3(1, 0.2, -5))

	# Dagger at (-6, 0.2, -4)
	var dagger := ItemResource.new()
	dagger.item_name = "Dagger"
	dagger.item_type = ItemResource.ItemType.WEAPON
	dagger.attack_bonus = 4
	dagger.damage_bonus = 0
	dagger.durability = 5
	dagger.throw_range = 7
	_spawn_gi(dagger, Vector3(-6, 0.2, -4))

	# Wooden Shield at (-3, 0.2, -6)
	var shield := ItemResource.new()
	shield.item_name = "Wooden Shield"
	shield.item_type = ItemResource.ItemType.SHIELD
	shield.durability = 10
	shield.is_shield = true
	_spawn_gi(shield, Vector3(-3, 0.2, -6))

	# Longbow at (5, 0.2, 4)
	var bow := ItemResource.new()
	bow.item_name = "Longbow"
	bow.item_type = ItemResource.ItemType.WEAPON
	bow.handedness = ItemResource.Handedness.TWO_HANDED
	bow.attack_bonus = 2
	bow.damage_bonus = 1
	bow.durability = 12
	bow.ranged_range = 20
	bow.throw_range = 2
	_spawn_gi(bow, Vector3(5, 0.2, 4))


func _spawn_gi(item: ItemResource, at: Vector3) -> void:
	var gi := MeshInstance3D.new()
	gi.name = "GroundItem"
	gi.set_script(load("res://scripts/ground_item.gd"))
	gi.position = at
	gi.item_resource = item
	var _root := get_parent()
	_root.add_child.call_deferred(gi)
	gi.call_deferred("_apply_visual")
