extends Control
class_name ItemSlot
## One inventory cell in the style of the Fantasy Warrior HUD icon sheets: a dark well, a
## hairline border, small corner brackets, and the item filling almost the whole thing.
##
## --- Why the frame is drawn rather than a sprite ---
##
## It was a sprite twice, and both were too heavy. Frame_Box24_Variant01 spends 9.6% of every
## cell per side on an ornate bevel, and Frame_Box_Small01 — the thinnest the pack ships —
## still spends 7.4%. The reference sheets frame an icon with a line about one pixel wide and
## let the item own the cell, and no amount of insetting gets a 19-pixel border to look like
## that. So the cell is drawn: a filled rect, a one-pixel edge, and eight short strokes at the
## corners.
##
## Drawing it also removes a layering problem. The old build stacked well, icon and frame as
## three children so the frame could sit ON TOP of the icon — which is exactly what made an
## item large enough to read collide with the bevel. A Control draws before its children, so
## the well and the border now go down first and the item is never overdrawn.
##
## Used for both halves of the inventory: the equipment doll's sockets and the backpack grid.
## An empty equipment socket shows a greyed ghost of what belongs there; an empty backpack
## cell shows nothing.

signal pressed
signal alt_pressed

## Preloaded rather than reached through its `class_name`, so this compiles regardless of
## whether the editor has rescanned and registered the global yet.
const Icons := preload("res://scripts/item_icons.gd")
const Thumbnails := preload("res://scripts/item_thumbnails.gd")
const ItemCardScript := preload("res://scripts/item_card.gd")

## Cell edge, in pixels, before the UI scale is applied. One pixel is the whole point.
const BORDER_PX := 1.0
## Corner brackets: how far along each edge they run, as a fraction of the cell, and how thick.
## They are what stops a plain rectangle reading as a debug outline.
const CORNER_SPAN := 0.20
const CORNER_PX := 2.0

## How far the icon is held back from the cell's edge, as a fraction of the cell.
##
## Two pixels of clearance at the reference size, no more. With a drawn hairline there is no
## bevel for the item to collide with, so it is held off the line only enough not to touch it.
const INSET := 0.03

const COLOR_WELL := Color(0.075, 0.098, 0.130, 0.94)
## The hairline and the brackets. Tan rather than the pack's saturated gold: at one pixel wide
## a bright gold line shimmers against the dark well, and the sheets use a muted edge.
const COLOR_EDGE := Color(0.55, 0.47, 0.33, 0.90)
const COLOR_EDGE_EMPTY := Color(0.34, 0.32, 0.30, 0.70)
const COLOR_EDGE_HOVER := Color(0.95, 0.83, 0.52, 1.0)
const COLOR_CORNER := Color(0.78, 0.66, 0.42, 0.95)
const COLOR_CORNER_EMPTY := Color(0.42, 0.40, 0.36, 0.65)
const COLOR_ICON_GHOST := Color(1, 1, 1, 0.16)
const COLOR_BROKEN := Color(0.85, 0.45, 0.40)
const BADGE_FONT_SIZE := 11

var _icon: TextureRect
var _badge: Label

var _item: ItemResource = null
var _hovered := false
## Whether this cell is showing something the character has equipped. Only the card uses it,
## for the ribbon; the cell itself looks the same either way.
var _equipped := false


func build(cell: float) -> void:
	custom_minimum_size = Vector2(cell, cell)
	size = Vector2(cell, cell)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The well and the border are drawn in _draw(), which happens before any child — so the
	# icon below is laid over them rather than under a frame.
	var inset: float = maxf(cell * INSET, 1.0)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(inset, inset)
	_icon.size = Vector2(cell - inset * 2.0, cell - inset * 2.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Bottom-right corner: durability for gear, charges for a stack.
	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_badge.position = Vector2(0, cell - 20)
	_badge.size = Vector2(cell - 6, 16)
	_badge.add_theme_font_size_override("font_size", BADGE_FONT_SIZE)
	_badge.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	_badge.add_theme_constant_override("outline_size", 4)
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	_restyle()


func _on_enter() -> void:
	_hovered = true
	_restyle()
	if _item != null:
		ItemCardScript.show_for(get_tree(), _item, get_global_mouse_position(), _equipped)


func _on_exit() -> void:
	_hovered = false
	_restyle()
	ItemCardScript.dismiss()


func set_equipped(equipped: bool) -> void:
	## Told by the panel, which is the only thing that knows: an inventory cell holds an item,
	## it does not hold the character wearing it.
	_equipped = equipped


func set_item(item: ItemResource, ghost_slot: int = -1) -> void:
	## Fill the cell. `ghost_slot` is an ItemResource.EquipSlot: pass it for an equipment
	## socket so an empty one still hints at what goes there, and leave it at -1 for a
	## backpack cell, which should just look empty.
	_item = item
	if item != null:
		# The flat category icon goes up straight away so no cell is ever blank, and the
		# item's own picture replaces it when it has been rendered — see _apply_thumbnail.
		_icon.texture = load(Icons.for_item(item))
		_apply_thumbnail(item)
		_badge.text = _badge_for(item)
		# No tooltip_text: the card does this now, and leaving it set would put a grey slab of
		# run-on text on top of the card a second after it appeared.
		tooltip_text = ""
	else:
		var ghost := Icons.for_empty_slot(ghost_slot) if ghost_slot >= 0 else ""
		_icon.texture = load(ghost) if ghost != "" else null
		_badge.text = ""
		tooltip_text = ""
	_restyle()


func _apply_thumbnail(item: ItemResource) -> void:
	## Swap in a photograph of the item's actual model once one exists.
	##
	## Not awaited by set_item: rendering needs a frame, and a cell that waited for one would
	## stall every panel repaint behind the whole bag. It arrives when it arrives, and after the
	## first time it is already cached and arrives the same frame.
	if not is_inside_tree():
		return
	var tex: Texture2D = await Thumbnails.texture_for(get_tree(), item)
	# The cell may have been given something else while that was rendering — a panel repaint,
	# or the player moving items about. Only paint if it is still showing what we photographed.
	if tex != null and _item == item and is_instance_valid(_icon):
		_icon.texture = tex


func get_item() -> ItemResource:
	return _item


func _badge_for(item: ItemResource) -> String:
	if item.item_type == ItemResource.ItemType.AMMO and item.ammo_amount > 0:
		return "x" + str(item.ammo_amount)
	if item.item_type == ItemResource.ItemType.CONSUMABLE:
		return ""
	if item.broken:
		return "!"
	# Durability only reads as useful on things that wear out.
	if item.is_hand_item():
		return str(item.durability)
	return ""


func _draw() -> void:
	## The whole cell: fill, hairline, brackets. Runs before the icon and badge children, so
	## nothing here can cover the item.
	var cell: float = minf(size.x, size.y)
	if cell <= 0.0:
		return
	# Scaled with the cell so the line stays a line on a big display instead of vanishing.
	var unit: float = maxf(cell / 72.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_WELL, true)

	var edge: Color = COLOR_EDGE_HOVER if _hovered else (
		COLOR_EDGE if _item != null else COLOR_EDGE_EMPTY)
	var w: float = BORDER_PX * unit
	# Inset by half the line width: draw_rect strokes centred on the rectangle, so on the
	# boundary itself half of every pixel would fall outside the cell and be clipped.
	draw_rect(Rect2(Vector2(w, w) * 0.5, size - Vector2(w, w)), edge, false, w)

	var corner: Color = COLOR_EDGE_HOVER if _hovered else (
		COLOR_CORNER if _item != null else COLOR_CORNER_EMPTY)
	var span: float = cell * CORNER_SPAN
	var cw: float = CORNER_PX * unit
	var half: float = cw * 0.5
	# Two strokes per corner, run along the inside of the edge so they read as brackets
	# thickening the line rather than as ticks floating beside it.
	for c in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), size]:
		var sx: float = 1.0 if c.x == 0.0 else -1.0
		var sy: float = 1.0 if c.y == 0.0 else -1.0
		var o := Vector2(c.x + sx * half, c.y + sy * half)
		draw_line(o, o + Vector2(sx * span, 0), corner, cw)
		draw_line(o, o + Vector2(0, sy * span), corner, cw)


func _restyle() -> void:
	if _item != null:
		# A broken weapon goes red whatever its own tint says: that reading matters more than
		# telling one jerkin from another.
		_icon.modulate = COLOR_BROKEN if _item.broken else _item.icon_tint
	else:
		_icon.modulate = COLOR_ICON_GHOST
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			alt_pressed.emit()
			accept_event()
