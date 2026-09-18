extends RefCounted
class_name ScreenPanel
## Shared furniture for the flat menu screens — character creation, town, results.
##
## They are built in code rather than authored as scenes for the same reason the HUD and the
## toolbar are (see hud_slot.gd, action_toolbar.gd): every one of them is a list of lines and
## a column of buttons whose contents depend on what the party is, and a .tscn cannot say
## "one row per hero". Keeping the look in one place stops three screens drifting apart.
##
## Nothing here knows what a party is. It takes text and callables.

const BACKDROP := Color(0.07, 0.06, 0.09)
const TITLE := Color(1.0, 0.87, 0.60)
const HEADING := Color(0.90, 0.90, 0.94)
const BODY := Color(0.82, 0.82, 0.88)
const MUTED := Color(0.60, 0.58, 0.64)
const GOOD := Color(0.72, 0.90, 0.72)
const BAD := Color(0.93, 0.62, 0.58)

const TITLE_SIZE := 34
const HEADING_SIZE := 18
const BODY_SIZE := 15

const WIDTH := 640.0
## Room beside the column for a scrollbar, so a list that scrolls does not have its right-hand
## edge clipped by one.
const SCROLLBAR_ROOM := 14.0
const BUTTON_WIDTH := 260.0
const BUTTON_HEIGHT := 34.0


static func mount(host: Control, scrolling: bool = false) -> VBoxContainer:
	## Clear the screen and lay out a fresh centred column to fill. Returns the column.
	##
	## Clearing is what makes a redraw cheap: these screens rebuild themselves outright when
	## something changes (a class is picked, the party rests) rather than each of them
	## learning to update its own labels in place.
	##
	## `scrolling` for a screen whose content is a LIST — the training hall has a row per
	## skill and the market a row per item, and both are taller than a window. A centred
	## column that overflows just loses its bottom rows, and the buttons down there are the
	## ones the screen exists for.
	for child in host.get_children():
		child.queue_free()

	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(backdrop)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(WIDTH, 0)
	column.add_theme_constant_override("separation", 10)

	if not scrolling:
		var centre := CenterContainer.new()
		centre.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(centre)
		centre.add_child(column)
		return column

	# Centred by the SAME CenterContainer the short screens use, with the scroll box given an
	# explicit size.
	#
	# Three other arrangements were tried and each put the list against an edge: an
	# HBoxContainer with ALIGNMENT_CENTER sizes itself to its content rather than to the
	# window; a ScrollContainer does not stretch its child to its own width even with
	# horizontal scrolling off; and anchoring the box to the middle depends on the host
	# resolving its own anchors against the window, which is only true when the screen IS the
	# current scene. A CenterContainer around a box of known size depends on none of that, and
	# it is what every other screen in the game already uses.
	#
	# The height has to be explicit: a CenterContainer sizes its child to the child's minimum,
	# and a scroll box as tall as its contents has nothing to scroll.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(centre)

	var available: float = host.size.y
	if available <= 0.0:
		# A host that has not been laid out yet — measure the window instead of laying the
		# screen out to a height of nothing.
		available = host.get_viewport().get_visible_rect().size.y
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH + SCROLLBAR_ROOM, maxf(240.0, available - 40.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	centre.add_child(scroll)
	scroll.add_child(column)
	# Breathing room at the top and bottom of a scrolling list, so the first and last rows are
	# not flush against the window edge.
	spacer(column, 16.0)
	return column


static func label(column: Node, text: String, font_size: int = BODY_SIZE,
		colour: Color = BODY) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.custom_minimum_size = Vector2(WIDTH, 0)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", colour)
	column.add_child(item)
	return item


static func title(column: Node, text: String) -> Label:
	return label(column, text, TITLE_SIZE, TITLE)


static func heading(column: Node, text: String) -> Label:
	return label(column, text, HEADING_SIZE, HEADING)


static func separator(column: Node) -> void:
	column.add_child(HSeparator.new())


static func spacer(column: Node, height: float = 8.0) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	column.add_child(gap)


static func button(column: Node, text: String, handler: Callable,
		enabled: bool = true) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	item.disabled = not enabled
	if handler.is_valid():
		item.pressed.connect(handler)
	column.add_child(item)
	return item


static func row(column: Node) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(box)
	return box


static func toast(host: Control, text: String) -> void:
	## A line that says why nothing happened, for the buttons that belong to a phase that has
	## not been built yet. It cleans itself up, so a screen does not have to own one.
	var note := Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", BODY_SIZE)
	note.add_theme_color_override("font_color", TITLE)
	note.add_theme_constant_override("outline_size", 5)
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.position = Vector2(-140.0, -60.0)
	host.add_child(note)
	var fade := note.create_tween()
	fade.tween_interval(1.6)
	fade.tween_property(note, "modulate:a", 0.0, 0.5)
	fade.tween_callback(note.queue_free)
