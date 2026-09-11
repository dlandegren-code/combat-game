extends CanvasLayer
## The hover card for an item: what page 11 of the Fantasy Warrior HUD sheets shows beside a
## piece of gear — a ribbon, the item's picture, its name, what kind of thing it is, the one
## number it leads with, and everything else as a list.
##
## Replaces a plain Godot tooltip, which put the same facts in one grey run-on line
## ("Rusty Sword (Weapon) 1H ATK+1 DMG+1 Dur:71") that had to be read rather than glanced at.
## ItemResource still builds that string for debugging; the card reads the same facts through
## type_name / headline_stat / stat_lines instead, so nothing here picks a sentence apart.
##
## --- Where it lives ---
##
## Its own CanvasLayer above every panel, made on demand and parented to the tree root, because
## a card owned by a slot would be clipped by the panel the slot sits in and would die with it.
## One card exists at a time and is moved and refilled, since only one thing can be hovered.

const Thumbnails := preload("res://scripts/item_thumbnails.gd")
const UiScaleScript := preload("res://scripts/ui_scale.gd")

## Above the panels (2) and the toolbar (3): a card that appeared behind the bag it describes
## would be worse than none.
const LAYER := 5

const WIDTH_BASE := 236.0
const PAD_BASE := 12.0
const ICON_BASE := 56.0
const ROW_BASE := 17.0
const RIBBON_BASE := 20.0
## Gap between the pointer and the card's corner, so the cursor never sits on top of it.
const CURSOR_GAP := 18.0

const COLOR_BACK := Color(0.055, 0.075, 0.105, 0.96)
const COLOR_EDGE := Color(0.55, 0.47, 0.33, 0.95)
const COLOR_NAME := Color(0.97, 0.95, 0.90)
const COLOR_KIND := Color(0.52, 0.68, 0.90)
const COLOR_LABEL := Color(0.62, 0.66, 0.74)
const COLOR_VALUE := Color(0.55, 0.82, 0.52)
const COLOR_HEAD := Color(0.97, 0.90, 0.66)
const COLOR_RULE := Color(1, 1, 1, 0.13)
const COLOR_RIBBON := Color(0.72, 0.60, 0.33, 1.0)
const COLOR_RIBBON_TEXT := Color(0.10, 0.09, 0.07)
const COLOR_BROKEN := Color(0.85, 0.45, 0.40)

static var _instance: CanvasLayer

var _panel: Control
var _s := 1.0


static func show_for(tree: SceneTree, item: ItemResource, at: Vector2,
		equipped: bool = false) -> void:
	## Put the card up for `item` near `at` (a screen position). Called on hover.
	if tree == null or item == null:
		return
	var card = _ensure(tree)
	card._fill(item, equipped)
	card._place(at)
	card.visible = true


static func dismiss() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.visible = false


static func _ensure(tree: SceneTree):
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var card = load("res://scripts/item_card.gd").new()
	card.layer = LAYER
	card.visible = false
	tree.root.add_child(card)
	_instance = card
	return card


func _ready() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)


func _place(at: Vector2) -> void:
	## Beside the pointer, and always fully on screen: a card that ran off the edge would hide
	## the very stats it exists to show.
	var view: Vector2 = _panel.get_viewport_rect().size
	var pos := at + Vector2(CURSOR_GAP, CURSOR_GAP)
	pos.x = minf(pos.x, view.x - _panel.size.x - 4.0)
	pos.y = minf(pos.y, view.y - _panel.size.y - 4.0)
	_panel.position = Vector2(maxf(pos.x, 4.0), maxf(pos.y, 4.0))


func _fill(item: ItemResource, equipped: bool) -> void:
	_s = UiScaleScript.of(get_viewport())
	for c in _panel.get_children():
		c.queue_free()

	var pad: float = PAD_BASE * _s
	var width: float = WIDTH_BASE * _s
	var icon_size: float = ICON_BASE * _s
	var row: float = ROW_BASE * _s
	var ribbon: float = RIBBON_BASE * _s if equipped else 0.0
	var y: float = ribbon + pad

	if equipped:
		_rect(Vector2(0, 0), Vector2(width * 0.44, ribbon), COLOR_RIBBON)
		_text("EQUIPPED", Vector2(0, 0), Vector2(width * 0.44, ribbon), 10,
			COLOR_RIBBON_TEXT, HORIZONTAL_ALIGNMENT_CENTER)

	# Picture, name, kind.
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(pad, y)
	icon.size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(icon)
	_apply_icon(icon, item)

	var text_x: float = pad + icon_size + pad * 0.75
	var text_w: float = width - text_x - pad
	_text(item.item_name.to_upper(), Vector2(text_x, y + 2.0 * _s), Vector2(text_w, row * 1.4),
		14, COLOR_BROKEN if item.broken else COLOR_NAME)
	_text(item.type_name(), Vector2(text_x, y + row * 1.5), Vector2(text_w, row), 11, COLOR_KIND)

	var head: Array = item.headline_stat()
	if head.size() == 2 and head[0] != 0:
		_text("%+d %s" % [head[0], head[1]] if head[1] != "Arrows" and head[1] != "Healing"
				else "%d %s" % [head[0], head[1]],
			Vector2(text_x, y + row * 2.6), Vector2(text_w, row * 1.3), 13, COLOR_HEAD)

	y += maxf(icon_size, row * 4.0) + pad * 0.5
	var lines: Array = item.stat_lines()
	if not lines.is_empty():
		_rect(Vector2(pad, y), Vector2(width - pad * 2.0, maxf(1.0, _s)), COLOR_RULE)
		y += pad * 0.5
		for line in lines:
			_text(line[0], Vector2(pad, y), Vector2(text_w, row), 11, COLOR_LABEL)
			_text(str(line[1]), Vector2(pad, y), Vector2(width - pad * 2.0, row), 11,
				COLOR_BROKEN if str(line[1]) == "broken" else COLOR_VALUE,
				HORIZONTAL_ALIGNMENT_RIGHT)
			y += row
		y += pad * 0.25
	y += pad * 0.5

	_panel.size = Vector2(width, y)
	# The backdrop is added first but drawn last unless it is moved behind everything, so it
	# goes in at index 0 rather than being appended.
	var back := ColorRect.new()
	back.color = COLOR_BACK
	back.position = Vector2.ZERO
	back.size = _panel.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(back)
	_panel.move_child(back, 0)
	_edge(_panel.size)


func _edge(sz: Vector2) -> void:
	## The same hairline the cells use, so a card and a slot look like the same furniture.
	var w: float = maxf(1.0, _s)
	var lines := [
		[Vector2.ZERO, Vector2(sz.x, w)],
		[Vector2(0, sz.y - w), Vector2(sz.x, w)],
		[Vector2.ZERO, Vector2(w, sz.y)],
		[Vector2(sz.x - w, 0), Vector2(w, sz.y)],
	]
	for l in lines:
		var r := _rect(l[0], l[1], COLOR_EDGE)
		_panel.move_child(r, 1)


func _rect(pos: Vector2, sz: Vector2, colour: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = colour
	r.position = pos
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(r)
	return r


func _text(body: String, pos: Vector2, sz: Vector2, font: int, colour: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = body
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.add_theme_font_size_override("font_size", int(font * _s))
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l


func _apply_icon(icon: TextureRect, item: ItemResource) -> void:
	## The same photograph the inventory cell uses, and the same flat fallback while it renders.
	icon.texture = load(ItemIcons.for_item(item))
	icon.modulate = COLOR_BROKEN if item.broken else item.icon_tint
	var tex: Texture2D = await Thumbnails.texture_for(get_tree(), item)
	if tex != null and is_instance_valid(icon):
		icon.texture = tex
		# A photograph carries its own colour; only a drawn silhouette wants washing.
		icon.modulate = COLOR_BROKEN if item.broken else Color(1, 1, 1)
