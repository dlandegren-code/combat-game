extends CanvasLayer
## What is inside the chest you just opened, as a grid of cells you can click one at a time.
##
## Opens by itself when any container reports being opened by a player character, and closes on
## the button or on Escape. Nothing else opens it: there is no toolbar cell for "loot", because
## a loot window with nothing to loot from is not a thing the player should be able to summon.
##
## --- Why a window rather than spilling on the floor ---
##
## Because the contents STAY. A container holds what it holds until somebody takes it, so a
## chest can be cracked open, half-emptied, and returned to two turns later. Spilling put
## everything on the floor at once and made "later" impossible.
##
## --- What a click costs ---
##
## One item, one Pick Up's worth of time, and the bill is settled when the window closes rather
## than per click — see Player._take_loot. So looting a chest is one turn whose length depends
## on how much you took, which is the honest reading of "reaching into a box repeatedly".
##
## SIZING: as with inventory_ui.gd, every measurement is authored against a reference height
## and multiplied by the viewport's scale, and the whole panel is rebuilt on resize.

const ItemSlotScript := preload("res://scripts/item_slot.gd")
const UiScaleScript := preload("res://scripts/ui_scale.gd")

## Cell edge in pixels at the reference height. Bumped from 54: between a thinner
## inset (see ItemSlot.INSET) and a larger cell, an item is now drawn about half again
## as big as it was, which is what it needed to be legible against this frame art.
const CELL_BASE := 72.0
const GAP_BASE := 6.0
const PAD_BASE := 14.0
const TITLE_BASE := 34.0
const HINT_BASE := 24.0
const BUTTON_BASE := 30.0
## Five to a row, matching the backpack grid so the two read as the same kind of container.
const COLUMNS := 5
## Rows always drawn, so the panel does not resize as it empties — a window that shrank under
## the pointer while you were clicking it would move the cell you were aiming at.
const ROWS := 2

const COLOR_LABEL := Color(0.72, 0.76, 0.84)

var _panel: Panel
var _title: Label
var _hint: Label
var _close: Button
var _cells: Array = []

var _s := 1.0
var _cell := CELL_BASE
var _gap := GAP_BASE
var _pad := PAD_BASE

## The container being looted, and whoever is doing it. Both null while closed.
var _container = null
var _actor = null
var _built := false


func _ready() -> void:
	layer = 2
	visible = false
	# Player._loot_window_open finds us by group rather than by path, so the panel can be moved
	# or re-parented in the scene without touching the character.
	add_to_group("loot_window")
	_panel = get_node_or_null("Panel")
	_title = get_node_or_null("Panel/Title")
	_rebuild.call_deferred()
	get_viewport().size_changed.connect(_rebuild)


func show_for(container, actor) -> void:
	## Put the window up on `container` for `actor`. The one way in, called by the character
	## doing the looting (Player._do_interact).
	##
	## Called rather than listening for a signal, because what is lootable is not known at
	## startup: chests and barrels exist from the first frame, but a CORPSE becomes a container
	## the moment somebody dies. Connecting to everything at _ready would have missed every one
	## of those, and re-scanning on a timer to catch them is worse than being told.
	##
	## Only for characters the player is driving. A goblin that ever learns to search a barrel
	## should not throw a window up in the player's face.
	if container == null or actor == null:
		return
	if not ("is_player_controlled" in actor) or not actor.is_player_controlled:
		return
	_container = container
	_actor = actor
	if container.has_signal("contents_changed") \
			and not container.contents_changed.is_connected(_refresh):
		container.contents_changed.connect(_refresh)
	visible = true
	_refresh()


func close() -> void:
	## Shut the window and hand the turn back. Told to the actor rather than done here, because
	## ending a turn is the character's business — see Player.finish_looting.
	if not visible:
		return
	visible = false
	if _container and _container.has_signal("contents_changed") \
			and _container.contents_changed.is_connected(_refresh):
		_container.contents_changed.disconnect(_refresh)
	var who = _actor
	_container = null
	_actor = null
	if who and who.has_method("finish_looting"):
		who.finish_looting()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- Layout ----------------------------------------------------------------

func _measure() -> void:
	_s = UiScaleScript.of(get_viewport())
	_cell = CELL_BASE * _s
	_gap = GAP_BASE * _s
	_pad = PAD_BASE * _s


func _panel_size() -> Vector2:
	var w: float = _pad * 2.0 + COLUMNS * _cell + (COLUMNS - 1) * _gap
	var h: float = TITLE_BASE * _s + ROWS * _cell + (ROWS - 1) * _gap \
		+ HINT_BASE * _s + BUTTON_BASE * _s + _pad * 2.0
	return Vector2(w, h)


func _rebuild() -> void:
	if _panel == null:
		return
	_measure()
	var sz := _panel_size()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -sz.x * 0.5
	_panel.offset_top = -sz.y * 0.5
	_panel.offset_right = sz.x * 0.5
	_panel.offset_bottom = sz.y * 0.5
	_build(sz)
	_refresh()


func _build(panel_size: Vector2) -> void:
	for c in _cells:
		if is_instance_valid(c):
			c.queue_free()
	_cells.clear()
	if _hint and is_instance_valid(_hint):
		_hint.queue_free()
	if _close and is_instance_valid(_close):
		_close.queue_free()

	if _title:
		_title.text = "Contents"
		_title.add_theme_font_size_override("font_size", int(16 * _s))

	var y: float = TITLE_BASE * _s
	for i in range(COLUMNS * ROWS):
		var slot = ItemSlotScript.new()
		@warning_ignore("integer_division")
		var row: int = i / COLUMNS
		var col: int = i % COLUMNS
		_panel.add_child(slot)
		slot.build(_cell)
		slot.position = Vector2(
			_pad + col * (_cell + _gap), y + row * (_cell + _gap))
		slot.pressed.connect(_on_cell_pressed.bind(i))
		_cells.append(slot)

	y += ROWS * _cell + (ROWS - 1) * _gap

	_hint = Label.new()
	_hint.text = "Click an item to take it"
	_hint.add_theme_color_override("font_color", COLOR_LABEL)
	_hint.add_theme_font_size_override("font_size", int(12 * _s))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, y)
	_hint.size = Vector2(panel_size.x, HINT_BASE * _s)
	_panel.add_child(_hint)
	y += HINT_BASE * _s

	_close = Button.new()
	_close.text = "Done"
	_close.add_theme_font_size_override("font_size", int(13 * _s))
	_close.position = Vector2(panel_size.x * 0.5 - 40.0 * _s, y)
	_close.size = Vector2(80.0 * _s, BUTTON_BASE * _s)
	_close.pressed.connect(close)
	_panel.add_child(_close)
	_built = true


# --- Contents --------------------------------------------------------------

func _refresh() -> void:
	if not _built:
		return
	var items: Array = []
	if _container and is_instance_valid(_container):
		items = _container.contents
	for i in _cells.size():
		_cells[i].set_item(items[i] if i < items.size() else null)
	if _hint:
		if items.is_empty():
			_hint.text = "Empty"
		else:
			var cost: int = _actor.loot_take_cost() if _actor and _actor.has_method("loot_take_cost") else 1
			_hint.text = "Click an item to take it  (%d tick%s each)" % [
				cost, "" if cost == 1 else "s"]
	# An emptied container is done with; leaving the window up would just be a box of nothing.
	if items.is_empty() and _container != null:
		close()


func _on_cell_pressed(index: int) -> void:
	## Cells past the end of the contents are dead, and a full bag is refused by the container
	## with its own message — so there is nothing to say here on failure.
	if _container == null or not is_instance_valid(_container) or _actor == null:
		return
	if index >= _container.contents.size():
		return
	if _actor.has_method("take_loot"):
		_actor.take_loot(_container, index)
