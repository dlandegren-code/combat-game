extends Control
## Combatant portraits, in the two layouts sheet 03 of the Fantasy Warrior HUD
## pack provides: the player party as a vertical column down the left edge, and
## the enemies as a horizontal row across the top.
##
## Builds one PortraitSlot per combatant and keeps whoever's turn it is
## highlighted, off CombatManager.turn_changed.

const PortraitSlotScript := preload("res://scripts/portrait_slot.gd")
const UiScaleScript := preload("res://scripts/ui_scale.gd")

## Authored at UiScale.REFERENCE_HEIGHT, like the plates themselves, and scaled to match so
## the gaps between portraits grow with the portraits rather than staying hairline-thin.
const EDGE_MARGIN_BASE := 12.0
const SLOT_SPACING_BASE := 10.0

## Enemy row sits below HUD/TurnLabel, which spans the full width at y 20-60.
const TOP_ROW_Y_BASE := 68.0

var _s := 1.0

@export var show_players: bool = true
@export var show_enemies: bool = true

var _slots: Array = []


func _ready() -> void:
	# CombatManager fills its combatant list in _ready; wait a frame so ours is
	# built after the group is fully populated regardless of node order.
	await get_tree().process_frame
	_build()


func _build() -> void:
	_s = UiScaleScript.of(get_viewport())
	if show_players:
		_build_player_column(_members(true))
	if show_enemies:
		_build_enemy_row(_members(false))

	# Looked up from the scene root rather than via get_parent() so this panel can
	# be nested at any depth (or instanced as its own scene) without rewiring.
	var cm := get_tree().current_scene.get_node_or_null("CombatManager")
	if cm and cm.has_signal("turn_changed"):
		cm.turn_changed.connect(_on_turn_changed)
		# CombatManager starts combat inside its own _ready, so the first
		# turn_changed fires before we get here. Seed from its current state.
		if cm.current_combatant:
			_on_turn_changed(cm.current_combatant)


func _build_player_column(members: Array) -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(EDGE_MARGIN_BASE * _s, EDGE_MARGIN_BASE * _s)
	column.add_theme_constant_override("separation", roundi(SLOT_SPACING_BASE * _s))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	for who in members:
		_add_slot(column, who, PortraitSlotScript.Style.ALLY)


func _build_enemy_row(members: Array) -> void:
	if members.is_empty():
		return
	# A full-width band holding a CenterContainer keeps the row centred no matter
	# how many enemies there are or how the window is resized.
	var band := CenterContainer.new()
	band.anchor_right = 1.0
	band.offset_top = TOP_ROW_Y_BASE * _s
	band.offset_bottom = TOP_ROW_Y_BASE * _s + _slot_height()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(SLOT_SPACING_BASE * _s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)
	for who in members:
		_add_slot(row, who, PortraitSlotScript.Style.ENEMY)


func _slot_height() -> float:
	## Must match the minimum size PortraitSlot gives itself, at the same scale.
	return (PortraitSlotScript.PORTRAIT_SIZE_BASE.y \
		+ PortraitSlotScript.BAR_HEIGHT_BASE \
		+ PortraitSlotScript.LABEL_HEIGHT_BASE) * _s


func _add_slot(parent: Node, who: Node, style: int) -> void:
	var slot: Control = Control.new()
	slot.set_script(PortraitSlotScript)
	parent.add_child(slot)
	slot.setup(who, style)
	_slots.append(slot)


func _members(player_controlled: bool) -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c):
			continue
		if c.is_player_controlled != player_controlled:
			continue
		out.append(c)
	# Stable, readable order: initiative descending, matching the turn order panel.
	out.sort_custom(func(a, b): return a.initiative > b.initiative)
	return out


func _on_turn_changed(active: Node) -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.set_active(slot.combatant == active)
