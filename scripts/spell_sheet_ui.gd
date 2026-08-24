extends CanvasLayer
## The active character's spellbook: what they can cast, what it costs and what it does.
##
## Driven entirely off the Ability contract — it lists whatever in `abilities` answers true to
## is_spell() and asks each one for its own icon, costs, reach and description. Adding a second
## spell means writing the spell; this panel needs no edit.
##
## Clicking a spell selects it as the active action, exactly as clicking its hotbar cell would,
## so the book is usable rather than just readable. A spell you cannot currently afford is
## dimmed and unclickable.
##
## Sized through UiScale, rebuilt on resize, hidden until the toolbar's Spells button opens it.

const UiScaleScript := preload("res://scripts/ui_scale.gd")

const BACKPLATE := "res://assets/UI/SPR_FantasyWarrior_Box_Background_Shadowed.png"
const DIVIDER := "res://assets/UI/SPR_FantasyWarrior_Tracery_Horizontal01.png"
const WELL := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Mask01.png"
const WELL_FRAME := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Variant01.png"

const PAD_BASE := 16.0
const TITLE_H_BASE := 30.0
const HEADER_H_BASE := 20.0
const DIVIDER_H_BASE := 11.0
const ICON_BASE := 52.0
const ROW_H_BASE := 68.0
const PANEL_W_BASE := 380.0
## Height reserved when the character has no spells, for the "cannot cast" line.
const EMPTY_H_BASE := 40.0

const COLOR_WELL := Color(0.075, 0.098, 0.130, 0.94)
const COLOR_HEADING := Color(1.0, 0.84, 0.52)
const COLOR_NAME := Color(1.0, 0.95, 0.78)
const COLOR_STATS := Color(0.74, 0.78, 0.86)
const COLOR_DESC := Color(0.60, 0.64, 0.72)
const COLOR_DIM := Color(0.45, 0.47, 0.52)
const COLOR_HOVER := Color(1.35, 1.28, 1.05)

var _panel: Panel
var _title: Label
var _content: Control

var _s := 1.0
var _pad := PAD_BASE
var _icon := ICON_BASE
var _row_h := ROW_H_BASE

var _header: Label
## One entry per listed spell: {index, frame, icon, name, stats, desc, row}.
var _entries: Array = []
var _shown_for: Node = null
var _built := false


func _ready() -> void:
	layer = 2
	visible = false
	_panel = get_node_or_null("Panel")
	_title = get_node_or_null("Panel/Title")
	_rebuild.call_deferred()
	get_viewport().size_changed.connect(_rebuild)


func _active() -> Node:
	var cm := get_parent().get_node_or_null("CombatManager")
	var c: Node = cm.current_combatant if cm else null
	if c and is_instance_valid(c) and c.get("is_player_controlled"):
		return c
	return null


func _spells_of(c: Node) -> Array:
	## A non-caster has no spellbook, even though it carries the spell abilities — every player
	## gets the same ability list so hotbar indices stay stable, so "has the ability" is not the
	## same as "knows the spell". can_cast is the real test.
	var out: Array = []
	if c == null or not ("abilities" in c) or not c.can_cast:
		return out
	for i in c.abilities.size():
		if c.abilities[i].is_spell():
			out.append(i)
	return out


# --- construction ------------------------------------------------------------

func _rebuild() -> void:
	if _panel == null:
		return
	_built = false
	_entries.clear()
	_shown_for = null
	if _content and is_instance_valid(_content):
		_content.queue_free()

	_s = UiScaleScript.of(get_viewport())
	_pad = PAD_BASE * _s
	_icon = ICON_BASE * _s
	_row_h = ROW_H_BASE * _s

	# Built for whoever is active right now. Unlike the character sheet, the row COUNT depends
	# on the subject, so the panel is rebuilt when the subject changes rather than just
	# refilled — see _process.
	var who := _active()
	var spells := _spells_of(who)
	var rows: int = spells.size()
	var body: float = (rows * _row_h) if rows > 0 else (EMPTY_H_BASE * _s)
	var sz := Vector2(PANEL_W_BASE * _s,
		_pad + (TITLE_H_BASE + HEADER_H_BASE + DIVIDER_H_BASE) * _s + body + _pad)

	_panel.offset_left = -sz.x * 0.5
	_panel.offset_right = sz.x * 0.5
	_panel.offset_top = -sz.y * 0.5
	_panel.offset_bottom = sz.y * 0.5
	if _title:
		_title.add_theme_font_size_override("font_size", roundi(17.0 * _s))
		_title.add_theme_color_override("font_color", COLOR_HEADING)

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)

	var plate := TextureRect.new()
	plate.texture = load(BACKPLATE)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.size = sz
	plate.modulate = Color(1, 1, 1, 0.85)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(plate)

	var y: float = _pad + TITLE_H_BASE * _s

	_header = Label.new()
	_header.position = Vector2(_pad, y)
	_header.size = Vector2(sz.x - _pad * 2.0, HEADER_H_BASE * _s)
	_header.add_theme_font_size_override("font_size", roundi(12.0 * _s))
	_header.add_theme_color_override("font_color", COLOR_HEADING)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_header)
	y += HEADER_H_BASE * _s

	if ResourceLoader.exists(DIVIDER):
		var rule := TextureRect.new()
		rule.texture = load(DIVIDER)
		rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rule.stretch_mode = TextureRect.STRETCH_SCALE
		rule.position = Vector2(_pad, y)
		rule.size = Vector2(sz.x - _pad * 2.0, DIVIDER_H_BASE * _s)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(rule)
	y += DIVIDER_H_BASE * _s

	if rows == 0:
		var none := Label.new()
		none.text = "No spells. This character cannot cast."
		none.position = Vector2(_pad, y + 6.0 * _s)
		none.add_theme_font_size_override("font_size", roundi(12.0 * _s))
		none.add_theme_color_override("font_color", COLOR_DIM)
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(none)
	else:
		for n in rows:
			_build_row(spells[n], y + n * _row_h, sz.x)

	_shown_for = who
	_built = true


func _build_row(ability_index: int, y: float, panel_w: float) -> void:
	# The clickable region is the whole row, not just the icon, so the hit target matches what
	# reads as one item.
	var row := Control.new()
	row.position = Vector2(_pad, y)
	row.size = Vector2(panel_w - _pad * 2.0, _row_h)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(row)

	var well := _layer(WELL, Vector2.ZERO, _icon, row)
	well.modulate = COLOR_WELL
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var inset: float = _icon * 0.135
	icon.position = Vector2(inset, inset)
	icon.size = Vector2(_icon - inset * 2.0, _icon - inset * 2.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var frame := _layer(WELL_FRAME, Vector2.ZERO, _icon, row)

	var text_x: float = _icon + 12.0 * _s
	var name_label := Label.new()
	name_label.position = Vector2(text_x, 2.0 * _s)
	name_label.size = Vector2(row.size.x - text_x, 20.0 * _s)
	name_label.add_theme_font_size_override("font_size", roundi(14.0 * _s))
	name_label.add_theme_color_override("font_color", COLOR_NAME)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var stats := Label.new()
	stats.position = Vector2(text_x, 22.0 * _s)
	stats.size = Vector2(row.size.x - text_x, 18.0 * _s)
	stats.add_theme_font_size_override("font_size", roundi(11.0 * _s))
	stats.add_theme_color_override("font_color", COLOR_STATS)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stats)

	var desc := Label.new()
	desc.position = Vector2(text_x, 39.0 * _s)
	desc.size = Vector2(row.size.x - text_x, 24.0 * _s)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", roundi(10.0 * _s))
	desc.add_theme_color_override("font_color", COLOR_DESC)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc)

	var entry := {
		"index": ability_index, "frame": frame, "icon": icon,
		"name": name_label, "stats": stats, "desc": desc, "row": row,
	}
	_entries.append(entry)

	row.mouse_entered.connect(func(): frame.modulate = COLOR_HOVER)
	row.mouse_exited.connect(func(): frame.modulate = Color(1, 1, 1))
	row.gui_input.connect(_on_row_input.bind(ability_index))


func _layer(path: String, at: Vector2, cell: float, parent: Control) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	# Without IGNORE_SIZE the 512-square source becomes the minimum size and the explicit
	# size below is clamped straight back up to it.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = at
	rect.size = Vector2(cell, cell)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


# --- state ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or not _built:
		return
	var who := _active()
	if who != _shown_for:
		# Different character means a different number of rows, so this is a rebuild rather
		# than a refill.
		_rebuild()
		return
	if who == null:
		_title.text = "Spells"
		_header.text = ""
		return
	_title.text = who.character_name + " — Spells"
	_header.text = "Spell Power %d     Mana %d / %d" % [
		who.get_spell_power(), who.mana, who.max_mana] if who.can_cast else "Not a caster"
	for e in _entries:
		var ability = who.abilities[e["index"]]
		var usable: bool = ability.can_use(who)
		e["name"].text = ability.display_name
		e["stats"].text = "%d mana     %d TU     %d tiles     %s" % [
			ability.get_mana_cost(who), ability.get_cost(who), ability.get_range(who),
			ability.get_damage_text(who)]
		e["desc"].text = ability.get_description(who)
		e["icon"].texture = load(ability.get_icon_path()) if ResourceLoader.exists(ability.get_icon_path()) else null
		# Dim the whole entry when it cannot be cast, so "out of mana" is visible at a glance.
		var tint: Color = COLOR_NAME if usable else COLOR_DIM
		e["name"].add_theme_color_override("font_color", tint)
		e["icon"].modulate = Color(1, 1, 1) if usable else Color(1, 1, 1, 0.35)
		# Selected spell reads like a selected hotbar cell.
		if who.selected_action == e["index"]:
			e["frame"].modulate = COLOR_HOVER


func _on_row_input(event: InputEvent, ability_index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var who := _active()
	if who == null or not who.can_act:
		return
	var ability = who.abilities[ability_index]
	if not ability.can_use(who):
		return
	# Selects it; the player then clicks a target on the battlefield, same as any other action.
	who.select_action(ability_index)
