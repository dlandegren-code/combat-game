extends CanvasLayer
## The bottom toolbar for whoever's turn it is: character sheet, inventory, stance selector,
## and a hotbar of eight assignable action slots.
##
## Replaces the old fixed ActionBar (seven text buttons hard-wired to ability indices 0-6).
## The hotbar keeps that convenience — a fresh character's slots are pre-filled with its
## abilities in order — but any slot can be re-pointed at any ability, so a player can put
## the three things they actually use under 1-2-3.
##
## Assignments are per character and held here rather than on the combatant, because they are
## a UI preference: nothing in combat resolution should be able to read or depend on them.
##
## Registered in the "action_toolbar" group so Player.gd can refresh it without knowing where
## in the scene it lives.

## Referenced through preloaded script constants rather than their `class_name` globals, so
## this compiles regardless of whether the editor has rescanned and registered them yet.
const HudSlotScript := preload("res://scripts/hud_slot.gd")
const StanceCat := preload("res://scripts/stance.gd")

const HOTBAR_SLOTS := 8
## Ability index meaning "nothing assigned".
const EMPTY := -1

const CELL := 52.0        ## hotbar cell, pixels square
const CELL_BIG := 58.0    ## sheet / inventory / stance cells
const GAP := 6.0
## Gap between the control group and the hotbar, so the two read as separate clusters.
const GROUP_GAP := 26.0
const BOTTOM_MARGIN := 16.0
## Space kept for the system-menu cluster in the very bottom-left corner (see
## system_menu.gd). The row is centred, but on a window narrow enough that centring would
## slide it under those buttons it is nudged right instead of overlapping them.
const MIN_LEFT := 186.0

const BACKPLATE := "res://assets/UI/SPR_FantasyWarrior_Box_Background_Shadowed.png"

## Two-letter stand-ins, because the ability set has no icon art yet. Abbreviations rather
## than initials: Trip and Throw both start with T.
const ABILITY_ABBREV := {
	"Move": "Mv", "Attack": "At", "Shove": "Sh", "Trip": "Tr",
	"Ranged": "Rn", "Throw": "Th", "Pick Up": "Pk",
}

var _root: Control
## Holds the whole row. Anchored to the bottom CENTRE, so the controls stay centred as the
## window resizes without anything having to recompute per-slot positions.
var _row: Control
var _sheet_slot: HudSlotScript
var _bag_slot: HudSlotScript
var _stance_slot: HudSlotScript
var _hotbar: Array = []

var _stance_popup: PopupMenu
var _assign_popup: PopupMenu
## Hotbar slot the assign popup was opened for.
var _assign_target := -1

## combatant -> Array[int] of HOTBAR_SLOTS ability indices (EMPTY for a free slot).
var _assignments: Dictionary = {}

var _active: Node = null


func _ready() -> void:
	add_to_group("action_toolbar")
	layer = 3
	_build()
	_reflow()
	get_viewport().size_changed.connect(_reflow)
	var cm := get_tree().current_scene.get_node_or_null("CombatManager")
	if cm and cm.has_signal("turn_changed"):
		cm.turn_changed.connect(_on_turn_changed)
		if cm.current_combatant:
			_on_turn_changed(cm.current_combatant)
		else:
			_root.visible = false
	else:
		_root.visible = false


# --- construction ------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Bar"
	# Must span the whole viewport, not just the bottom edge: _row anchors to 0.5 of this
	# node's width, so a zero-width parent would centre the row on x = 0 instead of on screen.
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var row_h := CELL_BIG + HudSlotScript.CAPTION_HEIGHT
	var row_y := -(row_h + BOTTOM_MARGIN)

	# Anchored left AND right to 0.5 makes the offsets below measure out from the horizontal
	# centre, so the row re-centres itself on resize. Slots are then placed in the row's own
	# coordinates and never need to know where the centre is.
	_row = Control.new()
	_row.name = "Row"
	_row.anchor_left = 0.5
	_row.anchor_right = 0.5
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_top = row_y
	_row.offset_bottom = row_y + row_h
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_row)

	var plate := TextureRect.new()
	plate.texture = load(BACKPLATE)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.modulate = Color(1, 1, 1, 0.72)
	plate.position = Vector2(-14.0, -10.0)
	plate.size = Vector2(_bar_width() + 28.0, row_h + 20.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(plate)

	var x := 0.0

	_sheet_slot = _add_slot(x, 0.0, CELL_BIG, HudSlotScript.FRAME_ORNATE, true)
	_sheet_slot.set_caption("Sheet")
	_sheet_slot.set_glyph("⚇")
	_sheet_slot.pressed.connect(_toggle_panel.bind("CharacterSheetPanel"))
	x += CELL_BIG + GAP

	_bag_slot = _add_slot(x, 0.0, CELL_BIG, HudSlotScript.FRAME_ORNATE, true)
	_bag_slot.set_caption("Bag")
	_bag_slot.set_glyph("▤")
	_bag_slot.pressed.connect(_toggle_panel.bind("InventoryPanel"))
	x += CELL_BIG + GAP

	_stance_slot = _add_slot(x, 0.0, CELL_BIG, HudSlotScript.FRAME_ORNATE, true)
	_stance_slot.pressed.connect(_open_stance_popup)
	x += CELL_BIG + GROUP_GAP

	for i in HOTBAR_SLOTS:
		var slot := _add_slot(x, 0.0, CELL, HudSlotScript.FRAME_STEEL, true)
		slot.set_hotkey(str(i + 1))
		slot.pressed.connect(_on_hotbar_pressed.bind(i))
		slot.alt_pressed.connect(_open_assign_popup.bind(i))
		_hotbar.append(slot)
		x += CELL + GAP

	_stance_popup = PopupMenu.new()
	_stance_popup.id_pressed.connect(_on_stance_chosen)
	_root.add_child(_stance_popup)

	_assign_popup = PopupMenu.new()
	_assign_popup.id_pressed.connect(_on_assign_chosen)
	_root.add_child(_assign_popup)


func _bar_width() -> float:
	return CELL_BIG * 3.0 + GAP * 2.0 + GROUP_GAP + CELL * HOTBAR_SLOTS + GAP * (HOTBAR_SLOTS - 1)


func _add_slot(x: float, y: float, cell: float, frame: String, caption: bool) -> HudSlotScript:
	## Parented to _row, so `x` is measured from the left end of the row rather than from the
	## screen edge — the row itself decides where that lands.
	var slot: HudSlotScript = HudSlotScript.new()
	_row.add_child(slot)
	slot.build(cell, frame, HudSlotScript.FRAME_GOLD, caption)
	slot.position = Vector2(x, y)
	return slot


func _reflow() -> void:
	## Centre the row, then push it right if that would tuck it under the system-menu cluster
	## in the corner. Both offsets shift together so the row keeps its width.
	if _row == null:
		return
	var half: float = _bar_width() * 0.5
	var centre: float = get_viewport().get_visible_rect().size.x * 0.5
	var shift: float = maxf(0.0, MIN_LEFT - (centre - half))
	_row.offset_left = -half + shift
	_row.offset_right = half + shift


# --- state ------------------------------------------------------------------

func _on_turn_changed(active: Node) -> void:
	## The toolbar belongs to the character being played, so it goes away entirely on an
	## enemy's turn rather than sitting there showing stale, unclickable controls.
	_active = active if (active and is_instance_valid(active) and active.is_player_controlled) else null
	if _active == null:
		_root.visible = false
		return
	_root.visible = true
	_ensure_assignments(_active)
	refresh()


func _ensure_assignments(who: Node) -> void:
	## First time we see a character, seed its hotbar with its abilities in order. Anything
	## past slot 8 is simply not reachable from the bar and must be re-assigned onto one.
	if _assignments.has(who):
		return
	var seeded: Array[int] = []
	var count: int = who.abilities.size() if "abilities" in who else 0
	for i in HOTBAR_SLOTS:
		seeded.append(i if i < count else EMPTY)
	_assignments[who] = seeded


func refresh() -> void:
	## Re-read everything that can change without the turn changing: which action is selected,
	## whether the character may still act, and the current stance.
	if _active == null or not is_instance_valid(_active):
		_root.visible = false
		return

	var can_act: bool = _active.can_act
	var selected: int = _active.selected_action

	_stance_slot.set_icon_path(StanceCat.icon_path(_active.defensive_option))
	_stance_slot.set_caption(StanceCat.display_name(_active.defensive_option))
	_stance_slot.set_enabled(can_act)

	_sheet_slot.set_enabled(true)
	_bag_slot.set_enabled(true)

	var assigned: Array = _assignments.get(_active, [])
	for i in _hotbar.size():
		var slot: HudSlotScript = _hotbar[i]
		var idx: int = assigned[i] if i < assigned.size() else EMPTY
		if idx == EMPTY or idx >= _active.abilities.size():
			slot.set_empty(true)
			slot.set_glyph("")
			slot.set_caption("")
			slot.set_selected(false)
			slot.set_enabled(can_act)
			continue
		var ability = _active.abilities[idx]
		slot.set_empty(false)
		slot.set_glyph(ABILITY_ABBREV.get(ability.display_name, ability.display_name.substr(0, 2)))
		slot.set_caption(ability.display_name)
		slot.set_selected(idx == selected)
		# Greyed when the character cannot act at all, or the ability has no resource left
		# (no ammo, no weapon to throw) — the same test the cursor feedback uses.
		slot.set_enabled(can_act and ability.can_use(_active))


# --- actions ----------------------------------------------------------------

func ability_in_slot(slot_index: int) -> int:
	## Which ability the given hotbar cell points at, or EMPTY. Exists so the number-key
	## shortcuts honour reassignments: pressing 3 must fire whatever the player put in the
	## third cell, not ability index 3.
	if _active == null:
		return EMPTY
	var assigned: Array = _assignments.get(_active, [])
	if slot_index < 0 or slot_index >= assigned.size():
		return EMPTY
	return assigned[slot_index]


func _on_hotbar_pressed(slot_index: int) -> void:
	if _active == null or not _active.can_act:
		return
	var assigned: Array = _assignments.get(_active, [])
	if slot_index >= assigned.size():
		return
	var idx: int = assigned[slot_index]
	if idx == EMPTY:
		# An empty cell is an invitation to fill it, so a left click opens the picker too
		# rather than doing nothing and leaving the player to discover right-click.
		_open_assign_popup(slot_index)
		return
	_active.select_action(idx)
	refresh()


func _toggle_panel(node_name: String) -> void:
	var panel := get_tree().current_scene.get_node_or_null(node_name)
	if panel:
		panel.visible = not panel.visible


# --- stance selector --------------------------------------------------------

func _open_stance_popup() -> void:
	if _active == null or not _active.can_act:
		return
	_stance_popup.clear()
	for s in StanceCat.available_for(_active):
		var tex: Texture2D = load(s["icon"]) if ResourceLoader.exists(s["icon"]) else null
		var label: String = "%s  —  %s" % [s["name"], s["hint"]]
		if tex:
			_stance_popup.add_icon_radio_check_item(tex, label, s["id"])
		else:
			_stance_popup.add_radio_check_item(label, s["id"])
		var at: int = _stance_popup.item_count - 1
		_stance_popup.set_item_checked(at, s["id"] == _active.defensive_option)
	_popup_above(_stance_popup, _stance_slot)


func _on_stance_chosen(id: int) -> void:
	if _active == null:
		return
	_active.defensive_option = id
	# Repaints the floating nameplate, which carries the stance line.
	if _active.has_method("_update_health_bar"):
		_active._update_health_bar()
	if _active.has_method("_show_action_text"):
		_active._show_action_text(StanceCat.display_name(id) + " stance")
	refresh()


# --- hotbar assignment ------------------------------------------------------

func _open_assign_popup(slot_index: int) -> void:
	if _active == null:
		return
	_assign_target = slot_index
	_assign_popup.clear()
	for i in _active.abilities.size():
		var ability = _active.abilities[i]
		_assign_popup.add_item("%s   (%d TU)" % [ability.display_name, ability.get_cost(_active)], i)
	_assign_popup.add_separator()
	_assign_popup.add_item("Clear slot", EMPTY)
	_popup_above(_assign_popup, _hotbar[slot_index])


func _on_assign_chosen(id: int) -> void:
	if _active == null or _assign_target < 0:
		return
	var assigned: Array = _assignments.get(_active, [])
	if _assign_target >= assigned.size():
		return
	# Keep the bar a set: putting an ability on a new slot clears it off its old one, so the
	# same action can never occupy two cells.
	if id != EMPTY:
		for i in assigned.size():
			if assigned[i] == id:
				assigned[i] = EMPTY
	assigned[_assign_target] = id
	_assign_target = -1
	refresh()


func _popup_above(popup: PopupMenu, anchor: Control) -> void:
	## Open the popup sitting on top of its control rather than at the mouse, so it never
	## covers the toolbar it was launched from.
	popup.reset_size()
	var origin := anchor.get_screen_position()
	popup.position = Vector2i(int(origin.x), int(origin.y - popup.size.y - 6))
	popup.popup()
