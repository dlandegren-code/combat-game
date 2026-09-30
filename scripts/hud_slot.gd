extends Control
class_name HudSlot
## One framed, clickable cell of HUD chrome: a Fantasy Warrior HUD frame with an icon (or a
## glyph) inside it, an optional hotkey number in the corner and an optional caption below.
##
## Every control on the bottom toolbar is one of these — hotbar slots, the stance selector,
## the character-sheet and inventory buttons, and the round system buttons — so they share
## one set of hover/press/selected behaviours instead of each reinventing them.
##
## The frame art is drawn UNDER the icon and the icon is inset, the same trick
## PortraitSlot uses: these sprites are borders with a hole in the middle, so anything drawn
## at full size disappears behind the bevel.

signal pressed
## Right-click. The toolbar uses it for "reassign this hotbar slot".
signal alt_pressed

## The four frames a slot can wear, DRAWN rather than taken from the pack.
##
## Every framed box in Fantasy Menus carries corner ornament, and on a cell this size the
## ornament sits on top of the icon the cell exists to show — curls hanging off the corners of
## the Town and Quit buttons, brackets across a hotbar item. A cell's frame should be a line.
## See UiKit.frame_style, and ItemSlot, which reached the same conclusion about its own cells
## long before this.
##
## `radius` is what tells them apart by SHAPE as well as colour: the system cluster is round
## again — a radius of half the cell is a circle — which it was under the old pack and stopped
## being when this was sprites from the new one.
const FRAME_STEEL := "steel"
const FRAME_GOLD := "gold"
const FRAME_ORNATE := "ornate"
const FRAME_RING := "ring"

const FRAME_LOOKS := {
	FRAME_STEEL: {"edge": Color(0.58, 0.66, 0.80), "width": 2, "radius": 4, "inset": 0.10},
	FRAME_GOLD: {"edge": Color(1.00, 0.80, 0.36), "width": 3, "radius": 4, "inset": 0.10},
	FRAME_ORNATE: {"edge": Color(0.88, 0.72, 0.38), "width": 2, "radius": 6, "inset": 0.11},
	# Radius is filled in from the cell size at build time — see _look_of.
	FRAME_RING: {"edge": Color(0.88, 0.72, 0.38), "width": 2, "radius": -1, "inset": 0.16},
}

const COLOR_IDLE := Color(1, 1, 1)
const COLOR_HOVER := Color(1.35, 1.28, 1.05)
const COLOR_DISABLED := Color(0.45, 0.45, 0.50)
const COLOR_EMPTY_ICON := Color(1, 1, 1, 0.25)
const HOTKEY_FONT_SIZE := 12
const CAPTION_FONT_SIZE := 11
const CAPTION_HEIGHT := 14

var _frame: Panel
var _cell := 0.0
var _icon: TextureRect
var _glyph: Label
var _hotkey: Label
var _caption: Label

var _frame_idle := FRAME_STEEL
var _frame_selected := FRAME_GOLD
var _selected := false
var _hovered := false
var _enabled := true
## True while the slot holds nothing, so the frame still draws but reads as an empty socket.
var _empty := false


func build(cell: float, frame_idle: String = FRAME_STEEL, frame_selected: String = FRAME_GOLD,
		with_caption: bool = false) -> void:
	## Construct the slot at `cell` pixels square. Call once, after adding to the tree.
	_frame_idle = frame_idle
	_frame_selected = frame_selected
	var total_h: float = cell + (float(CAPTION_HEIGHT) if with_caption else 0.0)
	custom_minimum_size = Vector2(cell, total_h)
	size = Vector2(cell, total_h)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_cell = cell
	_frame = Panel.new()
	_frame.size = Vector2(cell, cell)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	var inset: float = cell * float(_look_of(frame_idle)["inset"])
	var inner: float = cell - inset * 2.0

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(inset, inset)
	_icon.size = Vector2(inner, inner)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Fallback for entries with no icon art: their initial, centred in the opening.
	_glyph = Label.new()
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.position = Vector2(inset, inset)
	_glyph.size = Vector2(inner, inner)
	_glyph.add_theme_font_size_override("font_size", int(inner * 0.5))
	_glyph.add_theme_color_override("font_color", Color(1.0, 0.90, 0.66))
	_glyph.add_theme_constant_override("outline_size", 4)
	_glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)

	_hotkey = Label.new()
	_hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hotkey.position = Vector2(0, cell - 18)
	_hotkey.size = Vector2(cell - 4, 16)
	_hotkey.add_theme_font_size_override("font_size", HOTKEY_FONT_SIZE)
	_hotkey.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	_hotkey.add_theme_constant_override("outline_size", 4)
	_hotkey.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotkey)

	if with_caption:
		_caption = Label.new()
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption.position = Vector2(-6, cell - 1)
		_caption.size = Vector2(cell + 12, CAPTION_HEIGHT)
		_caption.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
		_caption.add_theme_color_override("font_color", Color(1.0, 0.87, 0.60))
		_caption.add_theme_constant_override("outline_size", 4)
		_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_caption)

	mouse_entered.connect(func(): _hovered = true; _restyle())
	mouse_exited.connect(func(): _hovered = false; _restyle())
	_restyle()


func set_icon_path(path: String) -> void:
	_icon.texture = load(path) if path != "" and ResourceLoader.exists(path) else null
	if _icon.texture:
		_glyph.text = ""
	_restyle()


func set_glyph(text: String) -> void:
	## Used when there is no icon art — the action's initial stands in for a picture.
	_glyph.text = text
	_icon.texture = null
	_restyle()


func set_hotkey(text: String) -> void:
	_hotkey.text = text


func set_caption(text: String) -> void:
	if _caption:
		_caption.text = text


func set_selected(on: bool) -> void:
	_selected = on
	_restyle()


func set_enabled(on: bool) -> void:
	_enabled = on
	_restyle()


func set_empty(on: bool) -> void:
	_empty = on
	_restyle()


func _look_of(frame: String) -> Dictionary:
	## The frame's description, with the ring's radius resolved against this cell — half a
	## cell's width is a circle, and the cell size is not known until the slot is built.
	var look: Dictionary = FRAME_LOOKS.get(frame, FRAME_LOOKS[FRAME_STEEL]).duplicate()
	if int(look["radius"]) < 0:
		look["radius"] = int(round(_cell * 0.5))
	return look


func _restyle() -> void:
	var look := _look_of(_frame_selected if _selected else _frame_idle)
	_frame.add_theme_stylebox_override("panel", _frame_style(
		Color(0, 0, 0, 0), Color(look["edge"]), int(look["width"]), int(look["radius"])))
	var tint := COLOR_IDLE
	if not _enabled:
		tint = COLOR_DISABLED
	elif _hovered or _selected:
		tint = COLOR_HOVER
	_frame.modulate = tint
	_icon.modulate = COLOR_EMPTY_ICON if _empty else tint
	_glyph.modulate = COLOR_EMPTY_ICON if _empty else Color(1, 1, 1)


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			alt_pressed.emit()
			accept_event()


static func _frame_style(fill: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	## A plain drawn frame: a fill, a line round it, rounded corners if asked for.
	##
	## Six lines of its own rather than a call into UiKit. This is a leaf widget that the
	## dungeon builds dozens of before anything else is up, and reaching from here into the
	## screen kit — which reaches back into ItemSlot — was enough to stop the game booting at
	## all, with no error to show for it. A StyleBoxFlat is not worth a dependency.
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box
