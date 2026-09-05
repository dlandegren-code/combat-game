extends Node
## Tick-based combat manager: time-unit system with action costs

signal turn_changed(combatant: Node)

const GroundItemScript := preload("res://scripts/ground_item.gd")

## Beat between an enemy's turn lighting up and it acting, so the player can register
## whose turn it is instead of the AI moving the instant they finish their own action.
const ENEMY_TURN_DELAY := 0.6

var combatants: Array[Node] = []
var current_combatant: Node = null
var current_tick: int = 0
var game_over := false

var turn_label: Label
var order_list: VBoxContainer


func _ready() -> void:
	turn_label = get_parent().get_node("HUD/TurnLabel")
	order_list = get_parent().get_node("InitiativePanel/Panel/OrderList")

	_collect_combatants()
	_spawn_ground_items()
	if combatants.is_empty():
		return
	_start_combat()


func _collect_combatants() -> void:
	var all := get_tree().get_nodes_in_group("combatants")
	for c in all:
		if is_instance_valid(c):
			c.next_turn_at = 0
			c.action_turn_at = 0
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
		_highlight_active(null)
		if turn_label:
			turn_label.text = "The battlefield is silent..."
		return

	current_tick = best_tick
	current_combatant = best

	_update_initiative_display()
	_update_turn_label(best)
	_highlight_active(best)

	best.enable_turn()
	turn_changed.emit(best)

	if not best.is_player_controlled and best.has_method("take_turn"):
		# Highlight now, act after a short beat — the player finishing their move no longer
		# snaps straight into the enemy's action.
		get_tree().create_timer(ENEMY_TURN_DELAY).timeout.connect(_begin_enemy_action.bind(best))


func _begin_enemy_action(who: Node) -> void:
	# Guard against the world changing during the delay (turn advanced, unit died, game over).
	if game_over or current_combatant != who or not is_instance_valid(who) or not who.is_alive:
		return
	who.take_turn()


func _highlight_active(active: Node) -> void:
	## Light the ring under `active` and clear it from everyone else (null = clear all).
	for c in combatants:
		if is_instance_valid(c) and c.has_method("set_turn_active"):
			c.set_turn_active(c == active and c.is_alive)


func turn_done(cost: int) -> void:
	if game_over or not current_combatant:
		return

	if is_instance_valid(current_combatant) and current_combatant.has_method("disable_turn"):
		current_combatant.disable_turn()

	current_combatant.next_turn_at += cost
	# Stamped so defense_debt() can tell the two things that push next_turn_at apart: this,
	# the action just taken, and the +1 per successful defence in charge_defense_cost. Only
	# the latter is debt — see Combatant.defense_debt.
	current_combatant.action_turn_at = current_combatant.next_turn_at
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

		# Defence debt: ticks of this character's next turn already spent reacting. Shown as
		# "+N" because it is time owed on top of T, and it is the resource that decides
		# whether they can still defend at all — see Combatant.defense_debt.
		#
		# The active combatant is never shown a debt: their next_turn_at IS current_tick by
		# definition, so it always reads zero, which is also why the amber/red states below
		# can never fight the yellow "it's your turn" highlight.
		var debt: int = c.defense_debt() if c.has_method("defense_debt") else 0
		var text: String = c.character_name + "  T" + str(c.next_turn_at)
		if debt > 0:
			text += "  +" + str(debt)
		if not c.is_alive:
			label.self_modulate = Color(0.5, 0.5, 0.5, 1)
		elif c == current_combatant and not game_over:
			text = "> " + text + " <"
			label.self_modulate = Color(1, 1, 0.3, 1)
		elif c.is_overwhelmed():
			text += "!"
			label.self_modulate = Color(1, 0.36, 0.30, 1)
		elif c.is_defense_strained():
			label.self_modulate = Color(1, 0.72, 0.26, 1)
		else:
			label.self_modulate = Color(1, 1, 1, 1)

		label.text = text
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		order_list.add_child(label)


func charge_defense_cost(defender: Node) -> void:
	## Called when a defender successfully parries or dodges. Costs 1 time unit.
	##
	## The panel is repainted here, not just on turn changes: this is the only place debt
	## grows, and a debt readout that only refreshed between turns would hide the very moment
	## a defender is being ground down.
	if is_instance_valid(defender):
		defender.next_turn_at += 1
		_update_initiative_display()
		# This is the moment a defender can tip over into overwhelmed, mid-exchange and
		# nowhere near a turn boundary. Their guard zone has to drop with it, or the floor
		# keeps advertising a line they can no longer hold.
		if defender.has_method("_refresh_guard_zone"):
			defender._refresh_guard_zone()


func _update_turn_label(combatant: Node) -> void:
	if turn_label:
		turn_label.text = combatant.character_name + "'s Turn  (T" + str(current_tick) + ")"


func _spawn_ground_items() -> void:
	## Spawn pickups on the battlefield at combat start (data-driven from .tres).
	_spawn_item("res://resources/items/health_potion.tres", Vector3(-1, 0.2, 5))
	_spawn_item("res://resources/items/arrow_bundle.tres", Vector3(3, 0.2, -3))
	_spawn_item("res://resources/items/quiver.tres", Vector3(4, 0.2, -3))
	_spawn_item("res://resources/items/warhammer.tres", Vector3(1, 0.2, -5))
	_spawn_item("res://resources/items/dagger.tres", Vector3(-7, 0.2, -3))
	_spawn_item("res://resources/items/wooden_shield.tres", Vector3(-3, 0.2, -7))
	_spawn_item("res://resources/items/longbow.tres", Vector3(5, 0.2, 5))
	_spawn_item("res://resources/items/knight_helmet.tres", Vector3(-5, 0.2, -5))


func _spawn_item(path: String, at: Vector3) -> void:
	var item: ItemResource = load(path)
	if item:
		# Duplicate so runtime changes (durability, pickup) don't mutate the cached .tres.
		_spawn_gi(item.duplicate(), at)


func _spawn_gi(item: ItemResource, at: Vector3) -> void:
	GroundItemScript.drop(get_parent(), item, at)
