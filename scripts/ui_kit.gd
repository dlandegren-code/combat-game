extends RefCounted
class_name UiKit
## The look of every flat screen in the game: a framed panel on a patterned ground, gold on
## navy, from the Synty INTERFACE - Fantasy Menus pack.
##
## This replaces screen_panel.gd and deliberately keeps its shape — mount / title / heading /
## label / button / row / separator / spacer / toast take the same arguments and mean the same
## things — so porting a screen was changing which file it preloads, not rewriting it. What
## changed is what those calls DRAW.
##
## THE PACK SHIPS ITS ART IN TWO HALVES
## Every frame comes as a white silhouette (the `_Mask` / `_Background` file) meant to be
## tinted, and a gold frame to lay over it. Godot's Button takes ONE StyleBox per state, so
## the two halves are composited HERE, once, and cached for the life of the run — see
## `_plate`. It is a few whole-image operations in the engine rather than a loop in GDScript,
## so it costs nothing worth measuring.
##
## The four button states are then ONE texture under four `modulate_color` values rather than
## four textures. A pressed button in this pack is the same button a shade darker, and saying
## that in a colour is cheaper than saying it in four files and impossible to get out of step.
##
## TEXTURE RECTS IGNORE THEIR OWN SIZE
## Every TextureRect built here sets EXPAND_IGNORE_SIZE. A TextureRect defaults to reporting
## its texture as its minimum size, and the dividers in this pack are 1024 pixels wide — so
## the first build of this produced panels eighteen hundred pixels across, sized to the rule
## under a heading rather than to the words beside it.
##
## NINE-PATCH MARGINS
## Each margin below is the size of the corner ornament in its own source art, so corners draw
## at their natural size and only the plain runs between them stretch. These are the numbers
## to nudge if a frame is ever swapped for another one in the pack.

const DIR := "res://assets/UI/FantasyMenus/SPR_FantasyMenus_"

## Panel: a big ornate frame over its own solid backing plate.
const TEX_PANEL_FRAME := preload(DIR + "Frame_Box_Large_01.png")
const TEX_PANEL_FILL := preload(DIR + "Frame_Box_Large_01_Background.png")
## The composited plate is RESIZED to this before use, and the slice is the corner ornament
## measured at that size. This is the part that has to be got right: a nine-patch draws its
## corners at the texture's own pixel size, so a 1024-pixel frame with 250-pixel corners puts
## 500 pixels of ornament into a panel 800 wide and leaves nothing in the middle. Sizing the
## plate to the job is what keeps the ornament proportionate.
const PANEL_SIZE := 400
const PANEL_SLICE := 98

## Button and row plate: the medium box, whose corners are plain brackets and whose edges are
## straight — the one frame in the pack that survives being stretched to any width.
const TEX_BOX_FRAME := preload(DIR + "Frame_Box_Medium_01.png")
const TEX_BOX_FILL := preload(DIR + "Frame_Box_Medium_01_Mask.png")
## Small, because the smallest thing wearing this plate is a 36-pixel-tall button, and two
## 26-pixel corners have to fit inside it with room to spare.
const BOX_SIZE := 96
const BOX_SLICE := 22
## The same frame again, bigger, for a HUD panel. The big ornate frame the town screens use is
## wrong down here: its corner scrollwork is a quarter of a 300-pixel sheet and swallows the
## section headings. This one's corners are plain brackets, so a panel can be small and still
## have its text start near its edge.
## The HUD panel's two lines and how far the inner one sits inside the outer.
const HUD_EDGE := Color(0.85, 0.68, 0.32, 0.95)
const HUD_EDGE_INNER := Color(0.85, 0.68, 0.32, 0.38)
const HUD_INNER_INSET := 4.0

const TEX_PATTERN := preload(DIR + "Background_Pattern_01.png")
const TEX_VIGNETTE := preload(DIR + "Background_Vignette_01.png")
## A soft tapered band, and the ONLY thing in the pack that survives being drawn as a rule.
## The ornate bars (Frame_Bar_06, Menu_Item_14) are built to be seen at about four to one; a
## divider across this panel is nearer sixty to one, and squashing one that far turns its
## scrollwork into a row of smears. This one is a gradient along its length, so stretching it
## only makes it longer.
const TEX_RULE := preload(DIR + "Line_Horizontal_01.png")
## Under a title, where there IS room to show an ornament at its own proportions. The barred
## one rather than the scrollwork: at the hundred-odd pixels a centred flourish gets, the
## scrollwork reads as a squiggle, where a bar with a star on each end still reads as a bar
## with a star on each end.
const TEX_FLOURISH := preload(DIR + "Frame_Bar_06.png")
const TEX_BULLET := preload(DIR + "Menu_Item_17.png")

## --- Palette ---
## Read off the pack's own screens rather than invented, so the art and the text agree about
## what colour the interface is.
const BACKDROP := Color(0.035, 0.063, 0.110)
const PANEL_NAVY := Color(0.063, 0.110, 0.192, 0.96)
const BUTTON_NAVY := Color(0.110, 0.196, 0.325, 0.98)
const ROW_NAVY := Color(0.086, 0.145, 0.247, 0.78)

const TITLE := Color(1.00, 0.84, 0.44)
const HEADING := Color(0.98, 0.88, 0.64)
const BODY := Color(0.84, 0.88, 0.95)
const MUTED := Color(0.55, 0.62, 0.74)
const GOOD := Color(0.62, 0.90, 0.70)
const BAD := Color(0.95, 0.56, 0.52)
const GOLD := Color(1.00, 0.78, 0.34)

## The four button states, as tints on the one composited plate.
const STATE_NORMAL := Color(1.00, 1.00, 1.00, 1.00)
const STATE_HOVER := Color(1.28, 1.22, 1.10, 1.00)
const STATE_PRESSED := Color(0.74, 0.74, 0.78, 1.00)
const STATE_DISABLED := Color(0.52, 0.55, 0.60, 0.70)

const TITLE_SIZE := 32
const HEADING_SIZE := 19
const BODY_SIZE := 15

## The content column. Kept narrow enough that the panel around it — this plus the padding on
## both sides, plus room for a scrollbar, plus whatever a row of buttons adds — still fits the
## smallest window the game is played in. capture_screens.gd prints the panel's real size next
## to the window's and warns when it stops fitting, which is how this number is checked.
const WIDTH := 620.0
## Inside the frame, not the frame itself. The panel art spends about a tenth of its edge on
## the border, and text run up against that reads as a mistake.
const PANEL_PAD := 36.0
## Extra at the BOTTOM only, and not an arbitrary one. A panel opens with a title, whose font
## carries its own leading, and closes with a button, which is a filled rectangle flush to its
## bounds — so the same number of pixels top and bottom does not read as the same gap. On the
## title screen it left "Quit" four pixels off the frame while the heading had forty.
const PANEL_PAD_BOTTOM_EXTRA := 14.0
const SCROLLBAR_ROOM := 16.0

## A two-column screen stretches to this at most, and to the window when that is narrower.
const WIDE_MAX := 1040.0
const COLUMN_GAP := 14.0
## Inside a row plate or a split box, between its frame and its contents.
const ROW_PAD := 12.0

const BUTTON_WIDTH := 264.0
const BUTTON_HEIGHT := 44.0
## One of several side by side — see `pill`.
const PILL_WIDTH := 120.0

## Icon cell on an item row — the same widget the dungeon's backpack is built from, at the
## size a list row can carry.
## Big enough to read a PHOTOGRAPH in, not just an icon. ItemSlot fills this with a render of
## the item's own 3D model, and at 44 a sword was a grey smudge — the whole reason for
## photographing the model rather than drawing one sword for every sword is that a Rusty Sword
## and a Ranger Dagger should not look the same.
const ITEM_CELL := 56.0
## A row-action button — "Buy", "Sell", "Put on". Narrow, because in a split screen it shares
## about a third of the window with an icon, a name and a price.
const ACTION_WIDTH := 76.0

## Text inset from a button's edge. The wide one clears the corner brackets completely; the
## tight one clears their ornament and no more, for buttons too small to afford the rest.
const BUTTON_PAD := 28.0
const BUTTON_PAD_TIGHT := 13.0

## The composited plates, built on first use and kept. Two of them, in two tints: one for the
## things you press and one for the strips they sit on.
static var _plates: Dictionary = {}


static func _plate(fill: Color, frame: Texture2D, mask: Texture2D, size: int) -> Texture2D:
	## Tint a silhouette and lay its gold frame over it, once.
	##
	## `blend_rect_mask` paints a flat colour through the silhouette's alpha, which is exactly
	## what the pack's `_Mask` and `_Background` files are for; `blend_rect` then drops the
	## gold on top. Both are engine-side operations over the whole image, so this is fast
	## enough to do at startup and simple enough to read.
	var key := "%s|%s|%d" % [frame.resource_path, fill, size]
	if _plates.has(key):
		return _plates[key]

	var gold_img := frame.get_image()
	var mask_img := mask.get_image()
	# Imported textures can arrive compressed, and the blend operations want straight RGBA.
	if gold_img.is_compressed():
		gold_img.decompress()
	if mask_img.is_compressed():
		mask_img.decompress()
	gold_img.convert(Image.FORMAT_RGBA8)
	mask_img.convert(Image.FORMAT_RGBA8)

	var w := mask_img.get_width()
	var h := mask_img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))

	var flat := Image.create(w, h, false, Image.FORMAT_RGBA8)
	flat.fill(fill)
	out.blend_rect_mask(flat, mask_img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	out.blend_rect(gold_img, Rect2i(0, 0, gold_img.get_width(), gold_img.get_height()),
		Vector2i.ZERO)

	# Down to working size last, so the tint and the frame are combined at full resolution and
	# only the result is resampled — resizing first would soften the gold before it is laid on.
	if size > 0 and size != w:
		out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var made := ImageTexture.create_from_image(out)
	_plates[key] = made
	return made


static func panel_texture() -> Texture2D:
	return _plate(PANEL_NAVY, TEX_PANEL_FRAME, TEX_PANEL_FILL, PANEL_SIZE)


static func button_texture() -> Texture2D:
	return _plate(BUTTON_NAVY, TEX_BOX_FRAME, TEX_BOX_FILL, BOX_SIZE)


static func row_texture() -> Texture2D:
	return _plate(ROW_NAVY, TEX_BOX_FRAME, TEX_BOX_FILL, BOX_SIZE)


# --- The screen ------------------------------------------------------------

static func mount(host: Control, scrolling: bool = false) -> VBoxContainer:
	## Clear the screen, lay the ground, stand a framed panel on it, and return the column
	## inside the panel for the caller to fill.
	##
	## Same contract the old ScreenPanel.mount had, including `scrolling` for a screen whose content is
	## a LIST — the market has a row per item and the training hall one per skill, and both are
	## taller than a window.
	##
	## A PanelContainer rather than a NinePatchRect with children hung off it. A NinePatchRect
	## is not a container: it never grows to fit what is inside it, so the first build of this
	## put a 400-pixel frame around 900 pixels of market and spilled the shelf out of the
	## bottom. A PanelContainer takes the same nine-patch art as a StyleBoxTexture, sizes
	## itself to its child, and takes the padding off the stylebox's content margins.
	for child in host.get_children():
		child.queue_free()

	_ground(host)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _panel_box())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.custom_minimum_size = Vector2(WIDTH, 0)
	column.add_theme_constant_override("separation", 8)

	if not scrolling:
		panel.add_child(column)
		return column

	# A list taller than the window. The scroll box is given an explicit height — a
	# CenterContainer sizes its child to that child's minimum, and a scroll box as tall as its
	# contents has nothing left to scroll.
	var available: float = host.size.y
	if available <= 0.0:
		available = host.get_viewport().get_visible_rect().size.y

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(
		WIDTH + SCROLLBAR_ROOM, maxf(280.0, available - PANEL_PAD * 2.0 - 24.0))
	panel.add_child(scroll)
	scroll.add_child(column)
	return column


static func _panel_box() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = panel_texture()
	box.texture_margin_left = PANEL_SLICE
	box.texture_margin_right = PANEL_SLICE
	box.texture_margin_top = PANEL_SLICE
	box.texture_margin_bottom = PANEL_SLICE
	box.content_margin_left = PANEL_PAD
	box.content_margin_right = PANEL_PAD
	box.content_margin_top = PANEL_PAD
	box.content_margin_bottom = PANEL_PAD + PANEL_PAD_BOTTOM_EXTRA
	return box


static func mount_wide(host: Control) -> VBoxContainer:
	## Like mount(), but as wide as the window sensibly allows — for a screen that puts two
	## lists SIDE BY SIDE rather than one above the other (see `split`).
	##
	## The width is taken from the viewport rather than fixed, because there is no window size
	## in project.godot: the game runs at whatever Godot's default is, and the editor's play
	## window is whatever it was last left at. A fixed 1040 looks right in one and hangs off
	## the edge in the other.
	var column := mount(host, false)
	column.custom_minimum_size = Vector2(_wide_width(host), 0)
	return column


static func _wide_width(host: Control) -> float:
	var available: float = host.size.x
	if available <= 0.0:
		available = host.get_viewport().get_visible_rect().size.x
	# Room for the frame, its padding, and a margin off the window's edge.
	return clampf(available - PANEL_PAD * 2.0 - 48.0, WIDTH, WIDE_MAX)


static func split(column: Node, height: float, count: int = 2) -> Array:
	## Two framed boxes side by side, each scrolling on its own. Returns their columns.
	##
	## The market is the reason this exists: what is for sale and what the party is carrying
	## are two lists you read AGAINST each other, and stacking them meant scrolling past
	## thirteen items on the shelf to reach your own pack. Side by side, both are in view and
	## each scrolls without moving the other.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(COLUMN_GAP))
	box.custom_minimum_size = Vector2(_width_of(column), height)
	column.add_child(box)

	var total := _width_of(column)
	var each := (total - COLUMN_GAP * (count - 1)) / float(count)

	var out: Array = []
	for i in range(count):
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", _row_box())
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(frame)

		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		frame.add_child(scroll)

		var inner := VBoxContainer.new()
		# The column carries its own width, which is what every helper below measures itself
		# against — see `_width_of`. Minus the scrollbar, which lives inside the box.
		inner.custom_minimum_size = Vector2(each - ROW_PAD * 2.0 - SCROLLBAR_ROOM, 0)
		inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_theme_constant_override("separation", 7)
		scroll.add_child(inner)
		out.append(inner)
	return out


static func _width_of(column: Node) -> float:
	## How wide the thing being filled is.
	##
	## Every helper here used to measure itself against the one WIDTH constant, which was fine
	## while every screen was one column. A split screen has columns of its own width, so the
	## column now CARRIES that width and the helpers ask it. A container with none set falls
	## back to the full panel, which is what an ordinary screen wants.
	var as_control := column as Control
	if as_control != null and as_control.custom_minimum_size.x > 0.0:
		return as_control.custom_minimum_size.x
	return WIDTH


static func _ground(host: Control) -> void:
	## What the panel stands on: flat navy, the pack's damask at a whisper, and a vignette to
	## pull the eye into the middle. Three cheap layers rather than a painted background,
	## because the same ground has to sit under nine different screens.
	var base := ColorRect.new()
	base.color = BACKDROP
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(base)

	var damask := TextureRect.new()
	damask.texture = TEX_PATTERN
	damask.stretch_mode = TextureRect.STRETCH_TILE
	damask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	damask.set_anchors_preset(Control.PRESET_FULL_RECT)
	damask.modulate = Color(1, 1, 1, 0.05)
	damask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(damask)

	var vignette := TextureRect.new()
	vignette.texture = TEX_VIGNETTE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.modulate = Color(1, 1, 1, 0.5)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(vignette)


# --- Text ------------------------------------------------------------------

static func label(column: Node, text: String, font_size: int = BODY_SIZE,
		colour: Color = BODY) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.custom_minimum_size = Vector2(_width_of(column), 0)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", colour)
	column.add_child(item)
	return item


static func title(column: Node, text: String) -> Label:
	var item := label(column, text, TITLE_SIZE, TITLE)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The pack's own title treatment: a flourish under the words rather than a rule across
	# them. It is what makes a screen read as a page rather than as a form.
	var flourish := TextureRect.new()
	flourish.texture = TEX_FLOURISH
	flourish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flourish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flourish.custom_minimum_size = Vector2(_width_of(column), 30)
	flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(flourish)
	return item


static func heading(column: Node, text: String) -> Label:
	## A section head: a small gold diamond, the words, and a rule running out to the edge.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(_width_of(column), 0)
	column.add_child(box)

	var bullet := TextureRect.new()
	bullet.texture = TEX_BULLET
	bullet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bullet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bullet.custom_minimum_size = Vector2(13, 13)
	bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bullet)

	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", HEADING_SIZE)
	item.add_theme_color_override("font_color", HEADING)
	box.add_child(item)

	var rule := TextureRect.new()
	rule.texture = TEX_RULE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.custom_minimum_size = Vector2(0, 7)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.modulate = Color(1.00, 0.82, 0.46, 0.38)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return item


static func separator(column: Node) -> void:
	var rule := TextureRect.new()
	rule.texture = TEX_RULE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.custom_minimum_size = Vector2(_width_of(column), 8)
	rule.modulate = Color(1.00, 0.82, 0.46, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)


static func spacer(column: Node, height: float = 8.0) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)


static func row(column: Node) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(box)
	return box


# --- Buttons ---------------------------------------------------------------

static func button(column: Node, text: String, handler: Callable,
		enabled: bool = true, width: float = BUTTON_WIDTH) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size = Vector2(width, BUTTON_HEIGHT)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	item.disabled = not enabled
	item.focus_mode = Control.FOCUS_NONE
	# NOT clipped: `width` is a floor, not a ceiling, and a button has to be able to grow to
	# fit its own label. Clipping it instead left the notice board offering to "Take: Sanctify
	# the Hollow Tomb" — a quest whose name ends one letter short of the truth. The row-action
	# buttons in item_row DO clip, because their labels are one word and their width is shared
	# with everything else on the row.
	style_button(item)
	if handler.is_valid():
		item.pressed.connect(handler)
	column.add_child(item)
	return item


static func pill(box: Node, text: String, handler: Callable, enabled: bool = true) -> Button:
	## A button for a ROW of them: a member picker, a set of tabs, a choice of recipient.
	##
	## Narrower than a standalone button and set to share the row evenly, because three
	## full-width buttons side by side are wider than the panel they sit in — which is exactly
	## how the party sheet first came out, spilling its picker off the right of the window.
	var item := button(box, text, handler, enabled, PILL_WIDTH)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item


static func style_button(item: Button, compact: bool = false) -> void:
	## Dress an existing Button in the pack. Public because the town's own buttons float over
	## the 3D clearing rather than sitting in a column, and they should not look like a
	## different game from the screens they open.
	##
	## `compact` for the small buttons on an item row. A full-size button holds its text well
	## clear of the corner brackets, which is right when there is room; on a 76-pixel "Take
	## off" the same padding leaves forty pixels of middle and the label comes out as "Take".
	var pad := BUTTON_PAD_TIGHT if compact else BUTTON_PAD
	item.add_theme_stylebox_override("normal", _button_box(STATE_NORMAL, pad))
	item.add_theme_stylebox_override("hover", _button_box(STATE_HOVER, pad))
	item.add_theme_stylebox_override("pressed", _button_box(STATE_PRESSED, pad))
	item.add_theme_stylebox_override("disabled", _button_box(STATE_DISABLED, pad))
	item.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	item.add_theme_color_override("font_color", TITLE)
	item.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.76))
	item.add_theme_color_override("font_pressed_color", Color(0.86, 0.72, 0.42))
	item.add_theme_color_override("font_disabled_color", Color(0.46, 0.50, 0.57))
	item.add_theme_font_size_override("font_size", 15)


static func _button_box(tint: Color, pad: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = button_texture()
	box.texture_margin_left = BOX_SLICE
	box.texture_margin_right = BOX_SLICE
	box.texture_margin_top = BOX_SLICE
	box.texture_margin_bottom = BOX_SLICE
	box.modulate_color = tint
	# Clear of the corner brackets. At 16 a long label sat on top of them, so the board's
	# "Take: Search the Forgotten Barrow" had gold scrollwork through its first and last
	# letters.
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


# --- Item rows -------------------------------------------------------------

static func item_row(column: Node, item, note: String, price: String,
		actions: Array) -> HBoxContainer:
	## One line of a market shelf or a pack: the item's own icon, its name, what it does, what
	## it is worth, and the buttons that act on it.
	##
	## The icon is an ItemSlot — the very widget the dungeon's backpack grid is made of — so a
	## potion looks the same on the shelf as it does in the bag it ends up in. That was the
	## point of the ask: a shop that lists gear by name is a spreadsheet, and by the time a
	## player reaches the market they have already learned what these things look like.
	##
	## The PRICE sits on the name's line rather than in a column of its own. With the market
	## split into two boxes each is about a third of the window wide, and a separate price
	## column took enough of that to squeeze "Health Potion" onto two lines and its stats onto
	## four. On the name's line it costs the row nothing and still lines up down the list.
	##
	## `actions` is an Array of {label, handler, enabled, width}.
	var frame := plate(column)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(box)

	var cell := ItemSlot.new()
	cell.build(ITEM_CELL)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# IN THE TREE FIRST, then given its item. ItemSlot shows the flat category icon at once and
	# swaps in a render of the item's own 3D model when it arrives — but that swap is a
	# coroutine that gives up immediately on a cell with no tree to await frames from
	# (ItemSlot._apply_thumbnail). Set before adding, every row in the market kept the generic
	# icon forever: one sword picture for every sword.
	box.add_child(cell)
	cell.set_item(item)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	box.add_child(words)

	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 8)
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(headline)

	var name_label := Label.new()
	name_label.text = item.item_name if item != null else "—"
	# Wrapped, so the label's MINIMUM width is one word rather than the whole name. A Label
	# that will not wrap reports its full text as a minimum, and a row of them was enough to
	# push the market's two columns wider than the window they sit in.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", HEADING)
	headline.add_child(name_label)

	if price != "":
		var coin := Label.new()
		coin.text = price
		coin.add_theme_font_size_override("font_size", 15)
		coin.add_theme_color_override("font_color", GOLD)
		coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		headline.add_child(coin)

	if note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_font_size_override("font_size", 12)
		note_label.add_theme_color_override("font_color", MUTED)
		words.add_child(note_label)

	for action in actions:
		var made := Button.new()
		made.text = String(action.get("label", "?"))
		# The LABEL stays short — "Buy", not "Buy Health Potion" — because a shelf of rows each
		# repeating its own item's name is noise. The NODE is named for both, so that anything
		# walking this screen by pressing buttons (the round-trip test) can say which row it
		# means. A screen with six buttons all reading "Buy" is unpressable by name otherwise.
		if item != null:
			made.name = "%s %s" % [made.text, item.item_name]
		made.custom_minimum_size = Vector2(float(action.get("width", ACTION_WIDTH)), 36.0)
		made.disabled = not bool(action.get("enabled", true))
		made.focus_mode = Control.FOCUS_NONE
		made.clip_text = true
		made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		style_button(made, true)
		made.add_theme_font_size_override("font_size", 14)
		var handler: Callable = action.get("handler", Callable())
		if handler.is_valid():
			made.pressed.connect(handler)
		box.add_child(made)
	return box


static func plate(column: Node) -> PanelContainer:
	## The framed strip an item row sits in, empty. Also for a screen that wants to group its
	## own rows — the results screen's takings, say.
	##
	## A PanelContainer for the same reason the panel itself is one: a NinePatchRect never
	## grows to fit its children, so the first build of this drew every market row at its
	## minimum height and let the item's name and its stat line spill through the frame.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _row_box())
	frame.custom_minimum_size = Vector2(_width_of(column), 0)
	column.add_child(frame)
	return frame


static func _row_box() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = row_texture()
	box.texture_margin_left = BOX_SLICE
	box.texture_margin_right = BOX_SLICE
	box.texture_margin_top = BOX_SLICE
	box.texture_margin_bottom = BOX_SLICE
	box.content_margin_left = ROW_PAD
	box.content_margin_right = ROW_PAD
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


# --- The dungeon's panels --------------------------------------------------
# The HUD lays its panels out by computed rectangle rather than with containers, so these take
# a rect and hand back a node instead of filling a column. Same art as the town, so a
# character sheet read underground is the same interface as the one read in the market.

static func hud_plate(parent: Node, size: Vector2) -> Panel:
	## The backing a HUD panel is drawn on: navy, with a plain double gold line round it.
	##
	## DRAWN, not a sprite, and deliberately. Every framed box in this pack carries corner
	## ornament — brackets, scrollwork, spikes — which is fine on a market row or a button,
	## where the frame is most of what you are looking at. On a character sheet the frame is
	## the least interesting thing on screen and the corners jut into the first line of every
	## section. The pack ships a plain double-line rectangle for exactly this, and this project
	## cannot import it (see the note in the plan about the editor not rescanning), so it is
	## reproduced here in two StyleBoxFlats.
	##
	## The same reasoning ItemSlot already used for its cells: art that is too heavy for the
	## job is worse than no art, and a line is a line.
	var plate := Panel.new()
	plate.add_theme_stylebox_override("panel", frame_style(PANEL_NAVY, HUD_EDGE, 2, 6))
	plate.size = size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)

	# The inner line of the pair. Transparent, so it is a line rather than a second panel.
	var inner := Panel.new()
	inner.add_theme_stylebox_override("panel",
		frame_style(Color(0, 0, 0, 0), HUD_EDGE_INNER, 1, 3))
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		inner.set("offset_" + side, HUD_INNER_INSET if side in ["left", "top"] else -HUD_INNER_INSET)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(inner)
	return plate


static func frame_style(fill: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	## A plain drawn frame: a fill, a line round it, and rounded corners if asked for.
	##
	## Public because the HUD's small frames — portrait plates, hotbar cells — want the same
	## treatment as the panels for the same reason: this pack's boxes all carry corner ornament,
	## and ornament on a 60-pixel cell lands on top of whatever the cell is showing.
	return _flat(fill, edge, width, radius)


static func _flat(fill: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box


# --- Odds and ends ---------------------------------------------------------

static func toast(host: Control, text: String) -> void:
	## A line that says why nothing happened. It cleans itself up, so a screen does not have to
	## own one.
	var note := Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", BODY_SIZE)
	note.add_theme_color_override("font_color", TITLE)
	note.add_theme_constant_override("outline_size", 6)
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.position = Vector2(-160.0, -54.0)
	host.add_child(note)
	var fade := note.create_tween()
	fade.tween_interval(1.6)
	fade.tween_property(note, "modulate:a", 0.0, 0.5)
	fade.tween_callback(note.queue_free)
