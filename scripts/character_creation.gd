extends Control
## Character creation: the screen the game opens on when there is nobody to play yet.
##
## Its whole job is to put one CharacterData into GameState and then get out of the way. The
## party it creates is the party every later screen reads — the town shows it, the quest scene
## builds bodies for it, and Phase 2 saves it.
##
## One character, deliberately. Hirelings are Phase 5, and they join the same array.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")

const TOWN_SCENE := "res://scenes/town.tscn"
const QUEST_SCENE := "res://scenes/quest_scene.tscn"

const DEFAULT_NAMES := {
	"soldier": "Aldric",
	"archer": "Rowan",
	"wizard": "Maelis",
}

var _class_id: String = CharacterClassesScript.ORDER[0]
var _name_field: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self)

	ScreenPanelScript.title(column, "A New Adventurer")
	ScreenPanelScript.label(column,
		"Pick what they are and give them a name. Everything after this — what they learn, "
		+ "what they carry, how far they get — is theirs to keep.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	var picks := ScreenPanelScript.row(column)
	for class_id in CharacterClassesScript.ORDER:
		var chosen: bool = class_id == _class_id
		var text: String = CharacterClassesScript.display_name(class_id)
		if chosen:
			text = "> %s <" % text
		var pick := ScreenPanelScript.button(picks, text, _on_class.bind(class_id))
		pick.custom_minimum_size = Vector2(150, ScreenPanelScript.BUTTON_HEIGHT)
		pick.size_flags_horizontal = Control.SIZE_FILL

	ScreenPanelScript.spacer(column, 4.0)
	ScreenPanelScript.heading(column, CharacterClassesScript.display_name(_class_id))
	ScreenPanelScript.label(column, CharacterClassesScript.blurb(_class_id),
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	for line in CharacterClassesScript.summary_lines(_class_id):
		ScreenPanelScript.label(column, line)

	ScreenPanelScript.separator(column)

	var name_row := ScreenPanelScript.row(column)
	ScreenPanelScript.label(name_row, "Name", ScreenPanelScript.BODY_SIZE,
		ScreenPanelScript.HEADING).custom_minimum_size = Vector2(60, 0)
	_name_field = LineEdit.new()
	_name_field.custom_minimum_size = Vector2(260, ScreenPanelScript.BUTTON_HEIGHT)
	_name_field.placeholder_text = DEFAULT_NAMES.get(_class_id, "Hero")
	_name_field.max_length = 24
	# Enter commits, because typing a name and reaching for the mouse is a small insult.
	_name_field.text_submitted.connect(func(_t): _on_begin())
	name_row.add_child(_name_field)
	_name_field.grab_focus()

	ScreenPanelScript.spacer(column, 4.0)
	ScreenPanelScript.button(column, "Begin", _on_begin)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.label(column,
		"Or play the old test scenario: the three hand-placed heroes the battlefield was "
		+ "built around. They become a real party on arrival, and the dungeon is balanced "
		+ "for three of them rather than for one.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.button(column, "Take the test party instead", _on_test_party)


func _on_class(class_id: String) -> void:
	# Keep anything already typed when switching class — the name is the player's, not the
	# class's.
	var typed: String = _name_field.text if _name_field != null else ""
	_class_id = class_id
	_build()
	if typed != "":
		_name_field.text = typed


func _on_begin() -> void:
	var chosen_name: String = _name_field.text.strip_edges()
	if chosen_name == "":
		chosen_name = DEFAULT_NAMES.get(_class_id, "Hero")
	GameState.clear()
	GameState.add_member(CharacterClassesScript.make(_class_id, chosen_name))
	print("[Creation] %s the %s joins the game" % [chosen_name, _class_id])
	get_tree().change_scene_to_file(TOWN_SCENE)


func _on_test_party() -> void:
	## Straight into the quest with an empty party, which is the signal QuestScene reads to
	## seed one from the hand-placed heroes (see QuestScene._seed_party). That path exists for
	## the old test scenario and this is the door to it.
	GameState.clear()
	get_tree().change_scene_to_file(QUEST_SCENE)
