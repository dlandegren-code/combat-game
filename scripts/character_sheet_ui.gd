extends CanvasLayer
## The active character's stat block, opened from the toolbar's Sheet button.
##
## Shows the numbers that actually decide fights, with the equipment contribution folded in
## where there is one: the attack and parry rows print the effective value (weapon and shield
## bonuses included) next to the bare skill, because that difference is exactly what the
## player is choosing gear for.
##
## Hidden by default; the toolbar toggles `visible`.

## Referenced through the preloaded script rather than its `class_name` global, so this
## compiles regardless of whether the editor has rescanned and registered it yet.
const StanceCat := preload("res://scripts/stance.gd")

const ROW_FONT_SIZE := 13
const TITLE_FONT_SIZE := 16
const LABEL_WIDTH := 104
const VALUE_WIDTH := 74

var _rows: VBoxContainer
var _title: Label
var _shown_for: Node = null


func _ready() -> void:
	layer = 2
	_title = get_node_or_null("Panel/Title")
	_rows = get_node_or_null("Panel/Rows")
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	var cm := get_parent().get_node_or_null("CombatManager")
	var active: Node = cm.current_combatant if cm else null
	if not active or not is_instance_valid(active) or not active.get("is_player_controlled"):
		_title.text = "Character"
		_clear()
		_shown_for = null
		return
	# Rebuilt only when the subject changes; the values themselves are refreshed every frame.
	if active != _shown_for:
		_shown_for = active
		_clear()
	_populate(active)


func _populate(c: Node) -> void:
	_title.text = c.character_name
	var eff_attack: int = c.get_attack_skill()
	var eff_parry: int = c.get_parry_skill()

	var data := [
		["Health", "%d / %d" % [c.hp, c.max_hp], ""],
		["Armour", str(c.armor), "Res %d%%" % c.physical_resistance],
		["Initiative", str(c.initiative), ""],
		["—", "", ""],
		["Attack", _eff(c.attack_skill, eff_attack), "%d TU" % c.attack_cost],
		["Damage", str(c.get_attack_damage()), ""],
		["Stance", StanceCat.display_name(c.defensive_option), ""],
		["Parry", _eff(c.parry_skill, eff_parry), ""],
		["Dodge", str(c.dodge_skill), ""],
		["—", "", ""],
		["Ranged", str(c.ranged_skill), "%d TU  rng %d" % [c.ranged_cost, c.get_ranged_range()]],
		["Ammo", ("%d / %d" % [c.ammo, c.max_ammo]) if c.max_ammo > 0 else "—", ""],
		["Throw", str(c.throw_skill), "%d TU  rng %d" % [c.throw_cost, c.get_throw_range()]],
		["—", "", ""],
		["Shove", str(c.shove_skill), "%d TU" % c.shove_cost],
		["Trip", str(c.trip_skill), "%d TU" % c.trip_cost],
		["Move", "%d tiles" % c.move_range, "%d TU" % c.get_move_cost(c.move_range)],
		["Strength", str(c.strength), "Weight %d" % c.weight],
	]

	_ensure_rows(data.size())
	for i in data.size():
		var row: HBoxContainer = _rows.get_child(i)
		var spec: Array = data[i]
		var is_rule: bool = spec[0] == "—"
		row.get_node("Name").text = "" if is_rule else str(spec[0])
		row.get_node("Value").text = str(spec[1])
		row.get_node("Note").text = str(spec[2])
		# A blank row stands in for a horizontal rule between stat groups.
		row.custom_minimum_size = Vector2(0, 6 if is_rule else 0)


func _eff(base: int, effective: int) -> String:
	## "4" when gear adds nothing, "4 (6)" when it does — so the bonus is visible without a
	## second row per stat.
	return str(base) if effective == base else "%d (%d)" % [base, effective]


func _ensure_rows(count: int) -> void:
	while _rows.get_child_count() < count:
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		name_label.add_theme_color_override("font_color", Color(0.78, 0.80, 0.86))
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.name = "Value"
		value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
		value_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		value_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
		row.add_child(value_label)

		var note_label := Label.new()
		note_label.name = "Note"
		note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE - 1)
		note_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		row.add_child(note_label)

		_rows.add_child(row)
	while _rows.get_child_count() > count:
		var extra := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(extra)
		extra.queue_free()


func _clear() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
