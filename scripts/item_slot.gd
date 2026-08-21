extends Control
class_name ItemSlot
## One inventory cell in the style of sheet 27 of the Fantasy Warrior HUD pack: a dark
## cut-corner well with a gold frame around it and the item's icon in the middle.
##
## The pack has no single "slot" sprite, so the look is composed from three layers —
## Frame_Box24's mask tinted dark for the well, the item icon, then Frame_Box24_Variant01's
## gold frame on top. Layering the frame LAST is what keeps the icon from spilling over the
## bevel.
##
## Used for both halves of the inventory: the equipment doll's sockets and the backpack grid.
## An empty equipment socket shows a greyed ghost of what belongs there; an empty backpack
## cell shows nothing.

signal pressed
signal alt_pressed

## Preloaded rather than reached through its `class_name`, so this compiles regardless of
## whether the editor has rescanned and registered the global yet.
const Icons := preload("res://scripts/item_icons.gd")

const FRAME := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Variant01.png"
const WELL := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Mask01.png"

## How far the frame's bevel intrudes, as a fraction of the cell. Measured off the sprite.
const INSET := 0.135
const COLOR_WELL := Color(0.075, 0.098, 0.130, 0.94)
const COLOR_FRAME := Color(1, 1, 1)
const COLOR_FRAME_HOVER := Color(1.4, 1.32, 1.05)
const COLOR_FRAME_EMPTY := Color(0.62, 0.60, 0.58)
const COLOR_ICON_GHOST := Color(1, 1, 1, 0.16)
const COLOR_BROKEN := Color(0.85, 0.45, 0.40)
const BADGE_FONT_SIZE := 11

var _well: TextureRect
var _icon: TextureRect
var _frame: TextureRect
var _badge: Label

var _item: ItemResource = null
var _hovered := false


func build(cell: float) -> void:
	custom_minimum_size = Vector2(cell, cell)
	size = Vector2(cell, cell)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_well = _layer(WELL, cell)
	_well.modulate = COLOR_WELL

	var inset: float = cell * INSET
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(inset, inset)
	_icon.size = Vector2(cell - inset * 2.0, cell - inset * 2.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_frame = _layer(FRAME, cell)

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

	mouse_entered.connect(func(): _hovered = true; _restyle())
	mouse_exited.connect(func(): _hovered = false; _restyle())
	_restyle()


func _layer(path: String, cell: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	# Without IGNORE_SIZE the 512-square source becomes the minimum size and the explicit
	# size below is clamped straight back up to it.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(cell, cell)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func set_item(item: ItemResource, ghost_slot: int = -1) -> void:
	## Fill the cell. `ghost_slot` is an ItemResource.EquipSlot: pass it for an equipment
	## socket so an empty one still hints at what goes there, and leave it at -1 for a
	## backpack cell, which should just look empty.
	_item = item
	if item != null:
		_icon.texture = load(Icons.for_item(item))
		_badge.text = _badge_for(item)
		tooltip_text = item.get_description()
	else:
		var ghost := Icons.for_empty_slot(ghost_slot) if ghost_slot >= 0 else ""
		_icon.texture = load(ghost) if ghost != "" else null
		_badge.text = ""
		tooltip_text = ""
	_restyle()


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


func _restyle() -> void:
	var filled := _item != null
	if filled:
		_frame.modulate = COLOR_FRAME_HOVER if _hovered else COLOR_FRAME
		_icon.modulate = COLOR_BROKEN if _item.broken else Color(1, 1, 1)
	else:
		_frame.modulate = COLOR_FRAME_HOVER if _hovered else COLOR_FRAME_EMPTY
		_icon.modulate = COLOR_ICON_GHOST


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			alt_pressed.emit()
			accept_event()
