extends Control
## What happened down there: the screen between a quest and the town.
##
## It reads GameState.last_result — written by QuestScene.finish_quest — and consumes it, so
## the same adventure is never reported twice. That is the only state it touches: the party
## was already updated before the quest scene was unloaded, which is the point of the whole
## data/view split.
##
## It exists because a scene change is a bad place to tell someone what they earned. Walking
## straight from the dungeon into the town screen, the xp and the gold just appeared as
## different numbers, and a wipe looked the same as a victory.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")

const TOWN_SCENE := "res://scenes/town.tscn"
const CREATION_SCENE := "res://scenes/character_creation.tscn"

## How each outcome is headlined, and in what colour.
const HEADLINES := {
	"victory": ["The dungeon is cleared", true],
	"retreat": ["You march back out", true],
	"defeat": ["The party has fallen", false],
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self)
	var result: Dictionary = GameState.take_last_result()
	var outcome: String = result.get("outcome", "retreat")
	var headline: Array = HEADLINES.get(outcome, ["You return", true])
	var good: bool = headline[1]

	ScreenPanelScript.title(column, headline[0])
	ScreenPanelScript.separator(column)

	if result.is_empty():
		# Nothing to report: the screen was reached without a quest behind it.
		ScreenPanelScript.label(column, "Nothing to report.", ScreenPanelScript.BODY_SIZE,
			ScreenPanelScript.MUTED)
	else:
		ScreenPanelScript.heading(column, "%d slain      +%d xp      +%d gold" % [
			result.get("kills", 0), result.get("xp", 0), result.get("gold", 0),
		])
		# The contract, said separately from the totals above, because the party needs to see
		# WHY a cleared job was worth so much more than the bodies in it — and, when they
		# walked out early, exactly what they left on the table.
		var quest: String = result.get("quest", "")
		if quest != "":
			if result.get("quest_paid", false):
				ScreenPanelScript.label(column, "Contract settled — %s: +%d gold, +%d xp." % [
					quest, result.get("quest_gold", 0), result.get("quest_xp", 0)],
					ScreenPanelScript.BODY_SIZE, ScreenPanelScript.GOOD)
			else:
				ScreenPanelScript.label(column,
					"Contract unfinished — %s. The job pays nothing until it is done." % quest,
					ScreenPanelScript.BODY_SIZE, ScreenPanelScript.BAD)
		var loot: Array = result.get("loot", [])
		if loot.is_empty():
			ScreenPanelScript.label(column, "Carried out: nothing you did not walk in with.",
				ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
		else:
			ScreenPanelScript.label(column, "Carried out: " + ", ".join(loot),
				ScreenPanelScript.BODY_SIZE, ScreenPanelScript.GOOD)
		var fallen: Array = result.get("fallen", [])
		if not fallen.is_empty():
			ScreenPanelScript.label(column, "Carried home: " + ", ".join(fallen),
				ScreenPanelScript.BODY_SIZE, ScreenPanelScript.BAD)
		if not good:
			ScreenPanelScript.label(column,
				"Whoever was left standing dragged the rest back. They will need rest before "
				+ "they are worth anything.", ScreenPanelScript.BODY_SIZE,
				ScreenPanelScript.MUTED)

	ScreenPanelScript.separator(column)
	if GameState.has_party():
		ScreenPanelScript.button(column, "Return to Riverwatch", _on_town)
	else:
		# No party and a result to show means the run was the old test scenario, which seeds
		# its own party — or something has gone wrong. Either way, offer the way forward.
		ScreenPanelScript.button(column, "Create a character", _on_create)


func _on_town() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)


func _on_create() -> void:
	get_tree().change_scene_to_file(CREATION_SCENE)
