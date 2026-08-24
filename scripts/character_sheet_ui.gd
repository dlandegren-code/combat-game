extends CanvasLayer
## The active character's sheet, in three blocks:
##
##   ATTRIBUTES  the six core scores, each in its own framed well
##   SKILLS      what the character is trained at — the numbers that go into a to-hit or
##               defence roll
##   COMBAT      the derived, at-a-glance state: hit points, initiative, total armour and
##               resistance, and how far it moves
##
## The split is deliberate: attributes are what a character *is*, skills are what it can *do*,
## and combat values are what the dice actually get compared against. Reach and damage are
## absent on purpose — those belong to whatever is in the character's hands, so they are shown
## in the inventory's item tooltips rather than pretended to be personal traits.
##
## Sized through UiScale like the rest of the HUD, and rebuilt on resize. Hidden until the
## toolbar's Sheet button opens it.

const UiScaleScript := preload("res://scripts/ui_scale.gd")
const StanceCat := preload("res://scripts/stance.gd")

const BACKPLATE := "res://assets/UI/SPR_FantasyWarrior_Box_Background_Shadowed.png"
const DIVIDER := "res://assets/UI/SPR_FantasyWarrior_Tracery_Horizontal01.png"
## Same two layers the inventory's item cells use, so a stat well and an item slot read as
## parts of one interface.
const WELL := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Mask01.png"
const WELL_FRAME := "res://assets/UI/SPR_FantasyWarrior_Frame_Box24_Variant01.png"

const PAD_BASE := 16.0
const TITLE_H_BASE := 30.0
## Attribute wells: three across, two down.
const ATTR_COLUMNS := 3
const ATTR_CELL_BASE := 52.0
const ATTR_LABEL_H_BASE := 15.0
const ATTR_GAP_BASE := 8.0
## Name/value rows in the lower two blocks, two columns of them.
const ROW_H_BASE := 21.0
const ROW_COLUMNS := 2
const SECTION_HEAD_BASE := 19.0
const DIVIDER_H_BASE := 11.0
const SECTION_GAP_BASE := 10.0

const COLOR_WELL := Color(0.075, 0.098, 0.130, 0.94)
const COLOR_HEADING := Color(1.0, 0.84, 0.52)
const COLOR_NAME := Color(0.74, 0.78, 0.86)
const COLOR_VALUE := Color(1.0, 0.95, 0.78)
const COLOR_NOTE := Color(0.60, 0.64, 0.72)
const COLOR_LOW := Color(0.88, 0.42, 0.38)

## The six attributes, in the order they are laid out. `key` is the property on Combatant.
const ATTRIBUTES: Array[Dictionary] = [
	{"key": "strength", "short": "STR", "name": "Strength"},
	{"key": "agility", "short": "AGI", "name": "Agility"},
	{"key": "stamina", "short": "STA", "name": "Stamina"},
	{"key": "intelligence", "short": "INT", "name": "Intelligence"},
	{"key": "willpower", "short": "WIL", "name": "Willpower"},
	{"key": "charisma", "short": "CHA", "name": "Charisma"},
]

var _panel: Panel
var _title: Label
var _content: Control

var _s := 1.0
var _pad := PAD_BASE
var _attr_cell := ATTR_CELL_BASE
var _row_h := ROW_H_BASE

## Filled during a build so _refresh can update text without rebuilding nodes.
var _attr_values: Array = []      ## parallel to ATTRIBUTES
var _rows: Dictionary = {}        ## row id -> {name: Label, value: Label, note: Label}
var _shown_for: Node = null
var _built := false


func _ready() -> void:
	layer = 2
	visible = false
	_panel = get_node_or_null("Panel")
	_title = get_node_or_null("Panel/Title")
	# The old flat row list is gone; drop whatever the scene still carries.
	var stale := get_node_or_null("Panel/Rows")
	if stale:
		stale.queue_free()
	_rebuild.call_deferred()
	get_viewport().size_changed.connect(_rebuild)


# --- construction ------------------------------------------------------------

func _skill_rows() -> Array[Dictionary]:
	return [
		{"id": "melee", "name": "Melee"},
		{"id": "ranged", "name": "Ranged"},
		{"id": "throw", "name": "Throw"},
		{"id": "parry", "name": "Parry"},
		{"id": "dodge", "name": "Dodge"},
		{"id": "shove", "name": "Shove"},
		{"id": "trip", "name": "Trip"},
		{"id": "dual", "name": "Dual Wield"},
		{"id": "spell", "name": "Spell Power"},
	]


func _combat_rows() -> Array[Dictionary]:
	return [
		{"id": "hp", "name": "Hit Points"},
		{"id": "mana", "name": "Mana"},
		{"id": "init", "name": "Initiative"},
		{"id": "armor", "name": "Armour"},
		{"id": "resist", "name": "Resistance"},
		{"id": "stance", "name": "Stance"},
		{"id": "move", "name": "Move"},
	]


func _rows_height(count: int) -> float:
	@warning_ignore("integer_division")
	var lines: int = count / ROW_COLUMNS + (1 if count % ROW_COLUMNS != 0 else 0)
	return lines * _row_h


func _panel_size() -> Vector2:
	var w: float = _pad * 2.0 + ATTR_COLUMNS * _attr_cell + (ATTR_COLUMNS - 1) * ATTR_GAP_BASE * _s
	# Wide enough for two "Dual Wield  Trained" columns, which is what actually sets the width.
	w = maxf(w, 330.0 * _s)
	var section: float = (SECTION_HEAD_BASE + DIVIDER_H_BASE + SECTION_GAP_BASE) * _s
	var attrs: float = 2.0 * (_attr_cell + ATTR_LABEL_H_BASE * _s + ATTR_GAP_BASE * _s)
	var h: float = _pad + TITLE_H_BASE * _s \
		+ section + attrs \
		+ section + _rows_height(_skill_rows().size()) \
		+ section + _rows_height(_combat_rows().size()) \
		+ _pad
	return Vector2(w, h)


func _rebuild() -> void:
	if _panel == null:
		return
	_built = false
	_attr_values.clear()
	_rows.clear()
	_shown_for = null
	if _content and is_instance_valid(_content):
		_content.queue_free()

	_s = UiScaleScript.of(get_viewport())
	_pad = PAD_BASE * _s
	_attr_cell = ATTR_CELL_BASE * _s
	_row_h = ROW_H_BASE * _s

	var sz := _panel_size()
	# Panel is centre-anchored, so its offsets are half-extents.
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

	# Backing plate under everything, so the panel reads as tooled leather rather than the
	# default flat theme grey.
	var plate := TextureRect.new()
	plate.texture = load(BACKPLATE)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.size = sz
	plate.modulate = Color(1, 1, 1, 0.85)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(plate)

	var y: float = _pad + TITLE_H_BASE * _s
	y = _build_section("ATTRIBUTES", y, sz.x)
	y = _build_attributes(y, sz.x)
	y = _build_section("SKILLS", y, sz.x)
	y = _build_rows(_skill_rows(), y, sz.x)
	y = _build_section("COMBAT", y, sz.x)
	y = _build_rows(_combat_rows(), y, sz.x)
	_built = true


func _build_section(heading: String, y: float, panel_w: float) -> float:
	var head := Label.new()
	head.text = heading
	head.position = Vector2(_pad, y)
	head.size = Vector2(panel_w - _pad * 2.0, SECTION_HEAD_BASE * _s)
	head.add_theme_font_size_override("font_size", roundi(12.0 * _s))
	head.add_theme_color_override("font_color", COLOR_HEADING)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(head)

	# Guarded: a freshly-copied sprite is not a loadable resource until Godot has scanned and
	# imported it, and the section should still lay out correctly in the meantime.
	if ResourceLoader.exists(DIVIDER):
		var rule := TextureRect.new()
		rule.texture = load(DIVIDER)
		rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rule.stretch_mode = TextureRect.STRETCH_SCALE
		rule.position = Vector2(_pad, y + SECTION_HEAD_BASE * _s)
		rule.size = Vector2(panel_w - _pad * 2.0, DIVIDER_H_BASE * _s)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(rule)

	return y + (SECTION_HEAD_BASE + DIVIDER_H_BASE + SECTION_GAP_BASE) * _s


func _build_attributes(y: float, panel_w: float) -> float:
	var gap: float = ATTR_GAP_BASE * _s
	var span: float = (panel_w - _pad * 2.0 - (ATTR_COLUMNS - 1) * gap) / float(ATTR_COLUMNS)
	var label_h: float = ATTR_LABEL_H_BASE * _s
	for i in ATTRIBUTES.size():
		@warning_ignore("integer_division")
		var row: int = i / ATTR_COLUMNS
		var col: int = i % ATTR_COLUMNS
		# Cell centred in its column, so unequal column width never skews the grid.
		var cx: float = _pad + col * (span + gap) + span * 0.5
		var cy: float = y + row * (_attr_cell + label_h + gap)
		var at := Vector2(cx - _attr_cell * 0.5, cy)

		_layer(WELL, at, _attr_cell).modulate = COLOR_WELL
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.position = at
		value.size = Vector2(_attr_cell, _attr_cell)
		value.add_theme_font_size_override("font_size", roundi(22.0 * _s))
		value.add_theme_color_override("font_color", COLOR_VALUE)
		value.add_theme_constant_override("outline_size", 5)
		value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(value)
		_attr_values.append(value)

		_layer(WELL_FRAME, at, _attr_cell)

		var cap := Label.new()
		cap.text = ATTRIBUTES[i]["short"]
		cap.tooltip_text = ATTRIBUTES[i]["name"]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = Vector2(cx - span * 0.5, cy + _attr_cell)
		cap.size = Vector2(span, label_h)
		cap.add_theme_font_size_override("font_size", roundi(10.0 * _s))
		cap.add_theme_color_override("font_color", COLOR_NAME)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(cap)

	return y + 2.0 * (_attr_cell + label_h + gap)


func _build_rows(specs: Array[Dictionary], y: float, panel_w: float) -> float:
	var col_w: float = (panel_w - _pad * 2.0) / float(ROW_COLUMNS)
	for i in specs.size():
		@warning_ignore("integer_division")
		var line: int = i / ROW_COLUMNS
		var col: int = i % ROW_COLUMNS
		var x: float = _pad + col * col_w
		var ry: float = y + line * _row_h

		var name_label := Label.new()
		name_label.text = specs[i]["name"]
		name_label.position = Vector2(x, ry)
		name_label.size = Vector2(col_w * 0.58, _row_h)
		name_label.add_theme_font_size_override("font_size", roundi(12.0 * _s))
		name_label.add_theme_color_override("font_color", COLOR_NAME)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(name_label)

		var value := Label.new()
		value.position = Vector2(x + col_w * 0.58, ry)
		value.size = Vector2(col_w * 0.40, _row_h)
		value.add_theme_font_size_override("font_size", roundi(12.0 * _s))
		value.add_theme_color_override("font_color", COLOR_VALUE)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(value)

		_rows[specs[i]["id"]] = value

	return y + _rows_height(specs.size())


func _layer(path: String, at: Vector2, cell: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(path)
	# Without IGNORE_SIZE the 512-square source becomes the minimum size and the explicit
	# size below is clamped straight back up to it.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = at
	rect.size = Vector2(cell, cell)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(rect)
	return rect


# --- state ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or not _built:
		return
	var cm := get_parent().get_node_or_null("CombatManager")
	var active: Node = cm.current_combatant if cm else null
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		_title.text = "Character"
		_blank()
		_shown_for = null
		return
	_shown_for = active
	_title.text = active.character_name
	_populate(active)


func _populate(c: Node) -> void:
	for i in ATTRIBUTES.size():
		_attr_values[i].text = str(c.get(ATTRIBUTES[i]["key"]))

	# Skills print the bare stat next to the effective one where gear changes it, because that
	# gap is exactly what the player is choosing equipment for.
	_put("melee", _eff(c.attack_skill, c.get_attack_skill()))
	_put("ranged", str(c.ranged_skill))
	_put("throw", str(c.throw_skill))
	_put("parry", _eff(c.parry_skill, c.get_parry_skill()))
	_put("dodge", str(c.get_dodge_skill()))
	_put("shove", str(c.shove_skill))
	_put("trip", str(c.trip_skill))
	_put("dual", "Trained" if c.dual_wield_skill else "—")
	# A non-caster gets a dash rather than a zero: "0" reads as a bad caster, a dash as not a
	# caster at all. Same convention as the untrained Dual Wield row above.
	_put("spell", str(c.get_spell_power()) if c.can_cast else "—")

	_put("hp", "%d / %d" % [c.hp, c.max_hp])
	_put("mana", ("%d / %d" % [c.mana, c.max_mana]) if c.can_cast else "—")
	_put("init", str(c.initiative))
	_put("armor", str(c.armor))
	_put("resist", "%d%%" % c.physical_resistance)
	_put("stance", StanceCat.display_name(c.defensive_option))
	_put("move", "%d tiles" % c.move_range)

	# Hit points go red on the same threshold the party portraits use, so the two agree.
	var low: bool = c.max_hp > 0 and float(c.hp) / float(c.max_hp) <= 0.35
	_rows["hp"].add_theme_color_override("font_color", COLOR_LOW if low else COLOR_VALUE)


func _eff(base: int, effective: int) -> String:
	## "4" when gear adds nothing, "4 (6)" when it does.
	return str(base) if effective == base else "%d (%d)" % [base, effective]


func _put(id: String, text: String) -> void:
	if _rows.has(id):
		_rows[id].text = text


func _blank() -> void:
	for v in _attr_values:
		v.text = "—"
	for id in _rows:
		_rows[id].text = ""
