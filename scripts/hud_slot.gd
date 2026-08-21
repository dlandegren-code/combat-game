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

## Square frames. Steel reads as an ordinary cell, gold as the selected one.
const FRAME_STEEL := "res://assets/UI/SPR_FantasyWarrior_Frame_Box_Small03.png"
const FRAME_GOLD := "res://assets/UI/SPR_FantasyWarrior_Frame_Box_Small01.png"
## More ornate square, for the controls that are not hotbar cells.
const FRAME_ORNATE := "res://assets/UI/SPR_FantasyWarrior_Frame_Box_Medium01_Variant01.png"
## Round frame, for the system cluster.
const FRAME_RING := "res://assets/UI/SPR_FantasyWarrior_Ring_Small01_Variant01.png"

## How far each frame's border intrudes, as a fraction of the sprite's width. Measured off
## the alpha of each sprite; the icon is inset by this much so it sits in the opening.
const FRAME_INSETS := {
	FRAME_STEEL: 0.10,
	FRAME_GOLD: 0.10,
	FRAME_ORNATE: 0.11,
	FRAME_RING: 0.17,
}

const COLOR_IDLE := Color(1, 1, 1)
const COLOR_HOVER := Color(1.35, 1.28, 1.05)
const COLOR_DISABLED := Color(0.45, 0.45, 0.50)
const COLOR_EMPTY_ICON := Color(1, 1, 1, 0.25)
const HOTKEY_FONT_SIZE := 12
const CAPTION_FONT_SIZE := 11
const CAPTION_HEIGHT := 14

var _frame: TextureRect
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

	_frame = TextureRect.new()
	# Without IGNORE_SIZE the 512-square source becomes the minimum size and the explicit
	# size below is clamped straight back up to it.
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.size = Vector2(cell, cell)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	var inset: float = cell * float(FRAME_INSETS.get(frame_idle, 0.10))
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


func _restyle() -> void:
	var path: String = _frame_selected if _selected else _frame_idle
	_frame.texture = load(path)
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
