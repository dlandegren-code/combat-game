extends CanvasLayer
## The active character's gear, as an equipment doll over a backpack grid.
##
## Top half: a humanoid outline with five sockets — Headgear, Right Hand, Torso, Left Hand,
## Legs — laid out where they sit on a body. The pack ships no paper-doll art, so the figure
## is drawn from tapered polygons rather than imported; it only has to read as a silhouette
## behind the sockets.
##
## Bottom half: the un-equipped carry, one cell per InventoryComponent bag slot, five to a row.
##
## Left-click moves an item between the two halves — a socket unequips, a bag cell equips
## into wherever the item belongs. Right-click drops it on the floor.
##
## Equipping and unequipping go through Player.equip_weapon / Player.unequip_item, which
## charge `equip_cost` and END THE TURN. That is pre-existing game rule, not something this
## panel adds, but it does mean a click here is a committing move rather than idle fiddling.
## Dropping is routed straight at the inventory instead, so it stays free.
##
## SIZING: every measurement below is authored against REFERENCE_HEIGHT and multiplied by a
## scale taken from the actual viewport, so the panel holds its proportions on a laptop and
## does not shrink to a postage stamp on a big display. Everything is rebuilt on resize.

const ItemSlotScript := preload("res://scripts/item_slot.gd")
const InventoryComponentScript := preload("res://scripts/inventory_component.gd")
const UiScaleScript := preload("res://scripts/ui_scale.gd")

const CELL_BASE := 54.0
const GAP_BASE := 6.0
const PAD_BASE := 14.0
## Clears the panel's title label.
const DOLL_TOP_BASE := 34.0
const DOLL_HEIGHT_BASE := 214.0
## Gap between the doll and the "Carried" heading.
const BAG_GAP_BASE := 20.0
const HINT_BASE := 24.0
const BAG_COLUMNS := 5

## Socket layout as fractions of the doll area, so the figure and its sockets scale together.
## Order is head, both hands flanking the torso, then legs.
const SOCKETS: Array[Dictionary] = [
	{"slot": ItemResource.EquipSlot.HELMET, "label": "Headgear", "at": Vector2(0.5, 0.04)},
	{"slot": ItemResource.EquipSlot.RIGHT_HAND, "label": "Right Hand", "at": Vector2(0.15, 0.40)},
	{"slot": ItemResource.EquipSlot.ARMOR, "label": "Torso", "at": Vector2(0.5, 0.40)},
	{"slot": ItemResource.EquipSlot.LEFT_HAND, "label": "Left Hand", "at": Vector2(0.85, 0.40)},
	{"slot": ItemResource.EquipSlot.LEGS, "label": "Legs", "at": Vector2(0.5, 0.76)},
]

const COLOR_FIGURE := Color(0.32, 0.38, 0.49, 0.60)
const COLOR_LABEL := Color(0.72, 0.76, 0.84)

var _panel: Panel
var _title: Label
## Everything this script builds lives under here, so a resize can throw the lot away and
## rebuild at the new scale without disturbing the Panel or its Title from the scene.
var _content: Control
var _doll: Control
var _sockets: Array = []      ## parallel to SOCKETS
var _bag_slots: Array = []

# Scaled measurements, all derived in _measure().
var _s := 1.0
var _cell := CELL_BASE
var _gap := GAP_BASE
var _pad := PAD_BASE
var _doll_top := DOLL_TOP_BASE
var _doll_h := DOLL_HEIGHT_BASE

var _active: Node = null
var _built := false


func _ready() -> void:
	layer = 2
	# Closed until the toolbar's Bag button opens it, same as the character sheet. The panel
	# sits dead centre over the battlefield, so leaving it up by default would bury the fight.
	visible = false
	_panel = get_node_or_null("Panel")
	_title = get_node_or_null("Panel/Title")
	# The old text rows are gone; drop whatever the scene still carries so the two cannot
	# both render.
	var stale := get_node_or_null("Panel/SlotList")
	if stale:
		stale.queue_free()
	# Deferred so the viewport has a real size to scale against before anything is laid out.
	_rebuild.call_deferred()
	get_viewport().size_changed.connect(_rebuild)


func _bag_rows() -> int:
	var slots: int = InventoryComponentScript.MAX_SLOTS
	@warning_ignore("integer_division")
	var rows: int = slots / BAG_COLUMNS
	return rows + (1 if slots % BAG_COLUMNS != 0 else 0)


func _measure() -> void:
	## Derive the scale from the viewport, then every dimension from that.
	_s = UiScaleScript.of(get_viewport())
	_cell = CELL_BASE * _s
	_gap = GAP_BASE * _s
	_pad = PAD_BASE * _s
	_doll_top = DOLL_TOP_BASE * _s
	_doll_h = DOLL_HEIGHT_BASE * _s


func _panel_size() -> Vector2:
	var w: float = _pad * 2.0 + BAG_COLUMNS * _cell + (BAG_COLUMNS - 1) * _gap
	var rows: float = float(_bag_rows())
	var h: float = _doll_top + _doll_h + BAG_GAP_BASE * _s \
		+ rows * _cell + (rows - 1.0) * _gap + HINT_BASE * _s + _pad
	return Vector2(w, h)


func _rebuild() -> void:
	if _panel == null:
		return
	_built = false
	_sockets.clear()
	_bag_slots.clear()
	if _content and is_instance_valid(_content):
		_content.queue_free()

	_measure()
	# Panel is centre-anchored (all four anchors at 0.5), so its offsets are half-extents.
	var sz := _panel_size()
	_panel.offset_left = -sz.x * 0.5
	_panel.offset_right = sz.x * 0.5
	_panel.offset_top = -sz.y * 0.5
	_panel.offset_bottom = sz.y * 0.5
	if _title:
		_title.add_theme_font_size_override("font_size", int(16.0 * _s))

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)
	_build(sz)


func _build(panel_size: Vector2) -> void:
	_doll = Control.new()
	_doll.name = "Doll"
	_doll.position = Vector2(_pad, _doll_top)
	_doll.size = Vector2(panel_size.x - _pad * 2.0, _doll_h)
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_doll)

	_draw_figure(_doll.size)

	for spec in SOCKETS:
		var at: Vector2 = spec["at"]
		var slot: ItemSlotScript = ItemSlotScript.new()
		_doll.add_child(slot)
		slot.build(_cell)
		# `at` marks the centre of the socket, so the cell is offset by half its size.
		slot.position = Vector2(at.x * _doll.size.x - _cell * 0.5, at.y * _doll_h)
		slot.pressed.connect(_on_socket_pressed.bind(spec["slot"]))
		slot.alt_pressed.connect(_on_socket_alt.bind(spec["slot"]))
		_sockets.append(slot)

		var cap := Label.new()
		cap.text = spec["label"]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = slot.position + Vector2(-16.0 * _s, _cell - 2.0 * _s)
		cap.size = Vector2(_cell + 32.0 * _s, 14.0 * _s)
		cap.add_theme_font_size_override("font_size", int(10.0 * _s))
		cap.add_theme_color_override("font_color", COLOR_LABEL)
		cap.add_theme_constant_override("outline_size", 4)
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_doll.add_child(cap)

	var bag_top: float = _doll_top + _doll_h + BAG_GAP_BASE * _s

	var bag_title := Label.new()
	bag_title.text = "Carried"
	bag_title.position = Vector2(_pad, bag_top - 20.0 * _s)
	bag_title.add_theme_font_size_override("font_size", int(12.0 * _s))
	bag_title.add_theme_color_override("font_color", COLOR_LABEL)
	_content.add_child(bag_title)

	var bag := Control.new()
	bag.name = "Bag"
	bag.position = Vector2(_pad, bag_top)
	bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(bag)

	# One cell per bag slot the component actually has, so the grid can never promise more
	# room than the inventory has.
	for i in InventoryComponentScript.MAX_SLOTS:
		var cell: ItemSlotScript = ItemSlotScript.new()
		bag.add_child(cell)
		cell.build(_cell)
		@warning_ignore("integer_division")
		var row: int = i / BAG_COLUMNS
		cell.position = Vector2(
			(i % BAG_COLUMNS) * (_cell + _gap),
			row * (_cell + _gap))
		cell.pressed.connect(_on_bag_pressed.bind(i))
		cell.alt_pressed.connect(_on_bag_alt.bind(i))
		_bag_slots.append(cell)

	var rows := float(_bag_rows())
	var hint := Label.new()
	hint.text = "Click to equip / unequip     Right-click to drop"
	hint.position = Vector2(_pad, bag_top + rows * _cell + (rows - 1.0) * _gap + 6.0 * _s)
	hint.add_theme_font_size_override("font_size", int(10.0 * _s))
	hint.add_theme_color_override("font_color", Color(0.55, 0.59, 0.66))
	_content.add_child(hint)
	_built = true


func _draw_figure(area: Vector2) -> void:
	## Humanoid silhouette: head, neck, chest, waist, hips, two arms with hands, two legs with
	## feet. Built from tapered trapezoids and ellipses rather than plain rectangles, so the
	## body actually has shoulders, and limbs that narrow and splay the way limbs do.
	##
	## Vertical positions are fractions of the doll height; the widths and sideways offsets are
	## reference pixels multiplied by the UI scale, so the figure grows with everything else.
	var cx := area.x * 0.5
	var h := _doll_h
	var s := _s
	var parts: Array[PackedVector2Array] = []

	parts.append(_ellipse(cx, h * 0.115, 23.0 * s, 24.0 * s))                         # head
	parts.append(_taper(cx, h, 0.150, 0.205, 10.0 * s, 15.0 * s, 0.0, 0.0))           # neck
	parts.append(_taper(cx, h, 0.205, 0.395, 44.0 * s, 33.0 * s, 0.0, 0.0))           # chest
	parts.append(_taper(cx, h, 0.395, 0.500, 33.0 * s, 26.0 * s, 0.0, 0.0))           # waist
	parts.append(_taper(cx, h, 0.500, 0.575, 26.0 * s, 32.0 * s, 0.0, 0.0))           # hips
	for side in [-1.0, 1.0]:
		parts.append(_taper(cx, h, 0.220, 0.370, 11.0 * s, 9.0 * s, side * 36.0 * s, side * 48.0 * s))
		parts.append(_taper(cx, h, 0.370, 0.505, 9.0 * s, 7.0 * s, side * 48.0 * s, side * 56.0 * s))
		parts.append(_ellipse(cx + side * 60.0 * s, h * 0.530, 8.5 * s, 10.0 * s))    # hand
		parts.append(_taper(cx, h, 0.575, 0.730, 15.0 * s, 12.0 * s, side * 16.0 * s, side * 19.0 * s))
		parts.append(_taper(cx, h, 0.730, 0.895, 12.0 * s, 8.0 * s, side * 19.0 * s, side * 20.0 * s))
		parts.append(_taper(cx, h, 0.895, 0.935, 8.5 * s, 11.0 * s, side * 20.0 * s, side * 23.0 * s))

	for pts in parts:
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = COLOR_FIGURE
		_doll.add_child(poly)


func _taper(cx: float, h: float, top: float, bottom: float, half_top: float,
		half_bottom: float, dx_top: float, dx_bottom: float) -> PackedVector2Array:
	## One tapered segment. `top`/`bottom` are fractions of the doll's height; the halves are
	## its width either side of its own axis, and the dx pair offsets that axis from the centre
	## line — which is what lets an arm or a leg lean outwards as it descends.
	var y0 := h * top
	var y1 := h * bottom
	return PackedVector2Array([
		Vector2(cx + dx_top - half_top, y0),
		Vector2(cx + dx_top + half_top, y0),
		Vector2(cx + dx_bottom + half_bottom, y1),
		Vector2(cx + dx_bottom - half_bottom, y1),
	])


func _ellipse(cx: float, cy: float, rx: float, ry: float, segments: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


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
