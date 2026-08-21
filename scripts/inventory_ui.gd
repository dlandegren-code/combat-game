extends CanvasLayer
## The active character's gear, as an equipment doll over a backpack grid.
##
## Top half: a humanoid outline with five sockets — Headgear, Right Hand, Torso, Left Hand,
## Legs — laid out where they sit on a body. The pack ships no paper-doll art, so the figure
## is drawn from a handful of Polygon2D pieces rather than imported; it only has to read as a
## silhouette behind the sockets.
##
## Bottom half: the un-equipped carry, one cell per InventoryComponent bag slot.
##
## Left-click moves an item between the two halves — a socket unequips, a bag cell equips
## into wherever the item belongs. Right-click drops it on the floor.
##
## Equipping and unequipping go through Player.equip_weapon / Player.unequip_item, which
## charge `equip_cost` and END THE TURN. That is pre-existing game rule, not something this
## panel adds, but it does mean a click here is a committing move rather than idle fiddling.
## Dropping is routed straight at the inventory instead, so it stays free.

const ItemSlotScript := preload("res://scripts/item_slot.gd")

const CELL := 54.0
const GAP := 6.0
const PAD := 14.0
## Doll area, measured from the panel's top-left below the title.
const DOLL_TOP := 34.0
const DOLL_HEIGHT := 214.0
const BAG_COLUMNS := 5

## Socket layout as fractions of the doll area, so the figure and its sockets scale together.
## Order is the draw/tab order: head, both hands flanking the torso, then legs.
const SOCKETS: Array[Dictionary] = [
	{"slot": ItemResource.EquipSlot.HELMET, "label": "Headgear", "at": Vector2(0.5, 0.04)},
	{"slot": ItemResource.EquipSlot.RIGHT_HAND, "label": "Right Hand", "at": Vector2(0.15, 0.40)},
	{"slot": ItemResource.EquipSlot.ARMOR, "label": "Torso", "at": Vector2(0.5, 0.40)},
	{"slot": ItemResource.EquipSlot.LEFT_HAND, "label": "Left Hand", "at": Vector2(0.85, 0.40)},
	{"slot": ItemResource.EquipSlot.LEGS, "label": "Legs", "at": Vector2(0.5, 0.76)},
]

const COLOR_FIGURE := Color(0.30, 0.36, 0.46, 0.55)
const COLOR_LABEL := Color(0.72, 0.76, 0.84)

var _panel: Panel
var _title: Label
var _doll: Control
var _bag: Control
var _sockets: Array = []      ## parallel to SOCKETS
var _bag_slots: Array = []
var _hint: Label

var _active: Node = null
var _built := false


func _ready() -> void:
	layer = 2
	_panel = get_node_or_null("Panel")
	_title = get_node_or_null("Panel/Title")
	# The old text rows are gone; drop whatever the scene still carries so the two cannot
	# both render.
	var stale := get_node_or_null("Panel/SlotList")
	if stale:
		stale.queue_free()
	# Deferred so the Panel's anchors have resolved into a real size before the doll is laid
	# out against its width.
	_build.call_deferred()


func _build() -> void:
	if _panel == null:
		return
	_doll = Control.new()
	_doll.name = "Doll"
	_doll.position = Vector2(PAD, DOLL_TOP)
	_doll.size = Vector2(_panel.size.x - PAD * 2.0, DOLL_HEIGHT)
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_doll)

	_draw_figure(_doll.size)

	for spec in SOCKETS:
		var at: Vector2 = spec["at"]
		var slot: ItemSlotScript = ItemSlotScript.new()
		_doll.add_child(slot)
		slot.build(CELL)
		# `at` marks the centre of the socket, so the cell is offset by half its size.
		slot.position = Vector2(
			at.x * _doll.size.x - CELL * 0.5,
			at.y * DOLL_HEIGHT)
		slot.pressed.connect(_on_socket_pressed.bind(spec["slot"]))
		slot.alt_pressed.connect(_on_socket_alt.bind(spec["slot"]))
		_sockets.append(slot)

		var cap := Label.new()
		cap.text = spec["label"]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = slot.position + Vector2(-14, CELL - 2)
		cap.size = Vector2(CELL + 28, 14)
		cap.add_theme_font_size_override("font_size", 10)
		cap.add_theme_color_override("font_color", COLOR_LABEL)
		cap.add_theme_constant_override("outline_size", 4)
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_doll.add_child(cap)

	var bag_top := DOLL_TOP + DOLL_HEIGHT + 18.0

	var bag_title := Label.new()
	bag_title.text = "Carried"
	bag_title.position = Vector2(PAD, bag_top - 18.0)
	bag_title.add_theme_font_size_override("font_size", 12)
	bag_title.add_theme_color_override("font_color", COLOR_LABEL)
	_panel.add_child(bag_title)

	_bag = Control.new()
	_bag.name = "Bag"
	_bag.position = Vector2(PAD, bag_top)
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_bag)

	# One cell per bag slot the component actually has, so the grid can never promise more
	# room than the inventory has.
	for i in InventoryComponentSlots():
		var cell: ItemSlotScript = ItemSlotScript.new()
		_bag.add_child(cell)
		cell.build(CELL)
		@warning_ignore("integer_division")
		var row: int = i / BAG_COLUMNS
		cell.position = Vector2(
			(i % BAG_COLUMNS) * (CELL + GAP),
			row * (CELL + GAP))
		cell.pressed.connect(_on_bag_pressed.bind(i))
		cell.alt_pressed.connect(_on_bag_alt.bind(i))
		_bag_slots.append(cell)

	_hint = Label.new()
	_hint.text = "Click to equip / unequip     Right-click to drop"
	_hint.position = Vector2(PAD, bag_top + CELL + GAP + 6.0)
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.59, 0.66))
	_panel.add_child(_hint)
	_built = true


func InventoryComponentSlots() -> int:
	## Read off the component rather than hard-coded, so raising MAX_SLOTS grows the grid.
	return preload("res://scripts/inventory_component.gd").MAX_SLOTS


func _draw_figure(area: Vector2) -> void:
	## A plain humanoid silhouette: head, torso, two arms, two legs. Drawn as polygons so it
	## needs no art and scales with the panel.
	var cx := area.x * 0.5
	var h := DOLL_HEIGHT
	var pieces := [
		# head
		Rect2(cx - 20, h * 0.03, 40, 34),
		# neck
		Rect2(cx - 8, h * 0.19, 16, 12),
		# torso
		Rect2(cx - 34, h * 0.25, 68, 74),
		# arms
		Rect2(cx - 56, h * 0.27, 20, 66),
		Rect2(cx + 36, h * 0.27, 20, 66),
		# hips
		Rect2(cx - 30, h * 0.62, 60, 18),
		# legs
		Rect2(cx - 27, h * 0.70, 22, 62),
		Rect2(cx + 5, h * 0.70, 22, 62),
	]
	for r in pieces:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			r.position,
			r.position + Vector2(r.size.x, 0),
			r.position + r.size,
			r.position + Vector2(0, r.size.y),
		])
		poly.color = COLOR_FIGURE
		_doll.add_child(poly)


# --- state ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or not _built:
		return
	var cm := get_parent().get_node_or_null("CombatManager")
	var active: Node = cm.current_combatant if cm else null
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		_active = null
		_title.text = "Inventory"
		_clear()
		return
	_active = active
	_title.text = active.character_name + " — Gear"
	_refresh()


func _refresh() -> void:
	var inv := _inv()
	if inv == null:
		_clear()
		return
	for i in SOCKETS.size():
		var slot: int = SOCKETS[i]["slot"]
		_sockets[i].set_item(_equipped_in(inv, slot), slot)
	for i in _bag_slots.size():
		var item: ItemResource = inv.items[i] if i < inv.items.size() else null
		# An equipped item still occupies a bag slot; showing it in both places would read as
		# two copies, so the grid only shows what is genuinely stowed.
		if item != null and _is_equipped(inv, item):
			item = null
		_bag_slots[i].set_item(item)


func _clear() -> void:
	for i in _sockets.size():
		_sockets[i].set_item(null, SOCKETS[i]["slot"])
	for cell in _bag_slots:
		cell.set_item(null)


func _inv() -> Node:
	if _active == null or not is_instance_valid(_active):
		return null
	return _active.get_node_or_null("Inventory")


func _equipped_in(inv: Node, slot: int) -> ItemResource:
	match slot:
		ItemResource.EquipSlot.RIGHT_HAND:
			return inv.right_hand
		ItemResource.EquipSlot.LEFT_HAND:
			# A two-hander fills both hands as one object; show it in the main hand only, or
			# it looks like the character is holding two of them.
			return null if inv.left_hand == inv.right_hand else inv.left_hand
		ItemResource.EquipSlot.ARMOR:
			return inv.armor
		ItemResource.EquipSlot.HELMET:
			return inv.helmet
		ItemResource.EquipSlot.LEGS:
			return inv.legs
	return null


func _is_equipped(inv: Node, item: ItemResource) -> bool:
	return item == inv.right_hand or item == inv.left_hand or item == inv.armor \
		or item == inv.helmet or item == inv.legs


# --- interaction ------------------------------------------------------------

func _on_socket_pressed(slot: int) -> void:
	var inv := _inv()
	if inv == null:
		return
	var item := _equipped_in(inv, slot)
	if item == null:
		return
	# Stays in the bag — unequipping is putting it away, not throwing it out.
	if _active.has_method("unequip_item"):
		_active.unequip_item(item)
	else:
		inv.unequip_item(item)


func _on_socket_alt(slot: int) -> void:
	var inv := _inv()
	if inv == null:
		return
	_drop(_equipped_in(inv, slot))


func _on_bag_pressed(index: int) -> void:
	var inv := _inv()
	if inv == null or index >= inv.items.size():
		return
	var item: ItemResource = inv.items[index]
	if item == null or _is_equipped(inv, item):
		return
	# InventoryComponent.equip works out the destination socket from the item's type, so this
	# is the one call for a weapon, a shield, armour, a helmet or greaves alike. Consumables
	# and ammo never reach the bag (Player._do_pickup spends them on the spot), so anything
	# non-equippable here simply declines to move.
	if _active.has_method("equip_weapon"):
		_active.equip_weapon(index)
	else:
		inv.equip(index)


func _on_bag_alt(index: int) -> void:
	var inv := _inv()
	if inv == null or index >= inv.items.size():
		return
	_drop(inv.items[index])


func _drop(item: ItemResource) -> void:
	if item == null or _active == null:
		return
	var inv := _inv()
	if inv == null:
		return
	var index: int = inv.get_item_slot(item)
	if index < 0:
		return
	inv.remove_item(index)   # also unequips it
	if _active.has_method("_drop_at_feet"):
		_active._drop_at_feet(item)
	if _active.has_method("_update_health_bar"):
		_active._update_health_bar()
