extends Control
## The screen the game starts on, and the one it comes back to between quests.
##
## Two things at once, on purpose:
##
##   the FLOW CONTROLLER — the thin layer that decides which screen loads next, which is what
##   lets the battlefield be one scene among several instead of being the whole game
##
##   a PLACEHOLDER TOWN — a readout of what the party has: who they are, what they earned,
##   what they are carrying, how badly hurt they are
##
## The readout exists to make the round trip visible: the numbers on this screen come out of
## GameState, which survived the scene change, and that is the one thing Phase 0 sets out to
## prove. Phase 1 replaces it with the real town (shop, training, quest board) and with a
## character creation screen in front of it — the flow-control half of this file is what
## those hang off, and the readout half goes away.

const CharacterDataScript := preload("res://scripts/character_data.gd")

const QUEST_SCENE := "res://scenes/quest_scene.tscn"

const TITLE_FONT_SIZE := 34
const HEADING_FONT_SIZE := 18
const BODY_FONT_SIZE := 15
const PANEL_WIDTH := 560.0
const BUTTON_WIDTH := 200.0

var _column: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.07, 0.06, 0.09)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_column = VBoxContainer.new()
	_column.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_column.add_theme_constant_override("separation", 10)
	centre.add_child(_column)

	_add_label("Town", TITLE_FONT_SIZE, Color(1.0, 0.87, 0.60))
	_add_label("A placeholder for Phase 1's town screen. What it shows comes from GameState, "
		+ "which outlives every scene change.", BODY_FONT_SIZE, Color(0.60, 0.58, 0.64))
	_add_separator()

	_add_last_result()
	_add_party()
	_add_separator()
	_add_buttons()


# --- Readout ---------------------------------------------------------------

func _add_last_result() -> void:
	var result: Dictionary = GameState.take_last_result()
	if result.is_empty():
		return
	var outcome: String = result.get("outcome", "returned")
	_add_label("Back from the dungeon (%s): %d slain, +%d xp, +%d gold" % [
		outcome, result.get("kills", 0), result.get("xp", 0), result.get("gold", 0),
	], HEADING_FONT_SIZE, Color(0.72, 0.90, 0.72))
	_add_separator()


func _add_party() -> void:
	if not GameState.has_party():
		_add_label("No party yet.", HEADING_FONT_SIZE, Color(0.90, 0.90, 0.94))
		_add_label("Phase 1 puts character creation here. Until then the first quest reads "
			+ "the party out of the hand-placed heroes in the battlefield, so go adventuring "
			+ "once and they become real characters.", BODY_FONT_SIZE, Color(0.60, 0.58, 0.64))
		return

	_add_label("Party — %d gold" % GameState.gold, HEADING_FONT_SIZE, Color(0.90, 0.90, 0.94))
	for member in GameState.party:
		_add_label("  %s the %s — level %d, %d xp, hp %s, %s" % [
			member.character_name,
			member.class_id,
			member.level,
			member.xp,
			_hp_text(member),
			_gear_text(member),
		], BODY_FONT_SIZE, Color(0.82, 0.82, 0.88))


func _hp_text(member) -> String:
	## A character carries wounds between quests, and "full" is stored as a sentinel rather
	## than a number because max hp is derived from a body that does not exist in town — see
	## CharacterData.VITALS_FULL.
	if member.hp == CharacterDataScript.VITALS_FULL:
		return "full"
	return str(member.hp)


func _gear_text(member) -> String:
	var held: Array = []
	for slot in member.equipped.keys():
		var idx: int = int(member.equipped[slot])
		if idx >= 0 and idx < member.bag.size() and member.bag[idx] != null:
			var item_name: String = member.bag[idx].item_name
			if not held.has(item_name):
				held.append(item_name)
	var carried := 0
	for item in member.bag:
		if item != null:
			carried += 1
	if held.is_empty():
		return "%d items, nothing equipped" % carried
	return "%d items, wearing %s" % [carried, ", ".join(held)]


# --- Flow ------------------------------------------------------------------

func _add_buttons() -> void:
	_add_button("Go Adventuring", _on_adventure)
	if GameState.has_party():
		_add_button("Rest (free, for now)", _on_rest)
	_add_button("Quit", func(): get_tree().quit())


func _on_adventure() -> void:
	get_tree().change_scene_to_file(QUEST_SCENE)


func _on_rest() -> void:
	## Free, and a placeholder: healing is exactly what a town economy should charge for
	## (Phase 3). It is here because a party that came back at 2 hp must not be stuck with it.
	GameState.rest_party()
	_build()


# --- Small builders --------------------------------------------------------

func _add_label(text: String, font_size: int, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	_column.add_child(label)


func _add_separator() -> void:
	var sep := HSeparator.new()
	_column.add_child(sep)


func _add_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, 34)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(handler)
	_column.add_child(button)
