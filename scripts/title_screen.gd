extends Control
## The screen a returning player lands on: continue the character in the save, or start over.
##
## Only reached when a save exists — with none, the bootstrap goes straight to character
## creation, because a title screen whose only working button is "New" is a door with nothing
## behind it.
##
## Starting over is the one destructive thing in the game, so it asks first and says exactly
## what will be lost.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")

const TOWN_SCENE := "res://scenes/town.tscn"
const CREATION_SCENE := "res://scenes/character_creation.tscn"

var _confirm_new: ConfirmationDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self)
	ScreenPanelScript.title(column, "Combat Game")
	ScreenPanelScript.separator(column)

	var save := SaveGameScript.peek()
	if save.is_empty():
		# The file was there a moment ago and is not readable now. Say so rather than
		# pretending, and leave the file alone — it is not ours to delete.
		ScreenPanelScript.heading(column, "There is a save file, but it cannot be read")
		ScreenPanelScript.label(column,
			"Starting a new character will overwrite it.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.BAD)
	else:
		ScreenPanelScript.heading(column, "Saved %s" % SaveGameScript.describe_age(save.get("saved_at", 0)))
		for member in save.get("party", []):
			ScreenPanelScript.label(column, "%s the %s — level %d, %d xp" % [
				member.get("character_name", "?"),
				CharacterClassesScript.display_name(member.get("class_id", "")),
				int(member.get("level", 1)),
				int(member.get("xp", 0)),
			])
		ScreenPanelScript.label(column, "%d gold" % int(save.get("gold", 0)),
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.button(column, "Continue", _on_continue, not save.is_empty())
	ScreenPanelScript.button(column, "New Character", _on_new)
	ScreenPanelScript.button(column, "Quit", func(): get_tree().quit())

	_confirm_new = ConfirmationDialog.new()
	_confirm_new.title = "Start Over"
	_confirm_new.dialog_text = "Creating a new character replaces the saved one. " \
		+ "Everything they earned is gone for good."
	_confirm_new.ok_button_text = "Replace them"
	_confirm_new.confirmed.connect(_do_new)
	add_child(_confirm_new)


func _on_continue() -> void:
	if not SaveGameScript.load_into_state():
		ScreenPanelScript.toast(self, "That save could not be loaded — see the console.")
		return
	get_tree().change_scene_to_file(TOWN_SCENE)


func _on_new() -> void:
	_confirm_new.popup_centered()


func _do_new() -> void:
	## The save file itself is left in place until the new character is actually created — the
	## creation screen writes over it on arrival in town (see Town). Deleting it here would
	## lose the old party to somebody who then changed their mind on the creation screen.
	GameState.clear()
	get_tree().change_scene_to_file(CREATION_SCENE)
