extends Control
## The mercenary camp: where a lone hero stops being a lone hero.
##
## Two lists on one screen, because they are two halves of one decision. The top is the party
## as it stands, with a way to part company; the bottom is who is round the fire and what they
## are asking. Splitting them across two screens would mean walking back and forth to answer
## "can I afford this, and who would I be replacing".
##
## Like the notice board, the camp owns nothing: the roster is derived from GameState.camp_seed
## every time this screen draws (GameState.hire_roster), so it is stable while the party is in
## town and changes when they come back from a quest. See Hireling.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const HirelingScript := preload("res://scripts/hireling.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## The dismissal a player has already clicked once, by party index, or -1. Parting with
## somebody is permanent and takes their gear with them, so it asks twice — and it asks in
## place, on the button itself, rather than in a dialogue that would have to be built, focused
## and dismissed.
var _confirming: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self, true)
	ScreenPanelScript.title(column, "The Mercenary Camp")

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody here to hire anybody.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	ScreenPanelScript.label(column, "%d gold in the purse." % GameState.gold,
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	_draw_party(column)
	ScreenPanelScript.separator(column)
	_draw_fire(column)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)


func _draw_party(column: Node) -> void:
	ScreenPanelScript.heading(column, "Your company — %d of %d"
		% [GameState.party.size(), GameState.PARTY_MAX])
	for i in range(GameState.party.size()):
		var member = GameState.party[i]
		var line := "%s — level %d %s" % [
			member.character_name, member.level, member.class_id.capitalize()]
		if i == 0:
			# The main character is named without a button beside them, because there is no
			# version of this screen where dismissing them is a thing to offer.
			ScreenPanelScript.label(column, line + "   (you)", ScreenPanelScript.BODY_SIZE,
				ScreenPanelScript.GOOD)
			continue
		ScreenPanelScript.label(column, line)
		if _confirming == i:
			ScreenPanelScript.button(column,
				"Really part with %s? They keep their gear" % member.character_name,
				_on_dismiss.bind(i))
		else:
			ScreenPanelScript.button(column, "Part ways with %s" % member.character_name,
				_on_confirm.bind(i))
		ScreenPanelScript.spacer(column, 4.0)


func _draw_fire(column: Node) -> void:
	var full: bool = GameState.party_is_full()
	ScreenPanelScript.heading(column, "Round the fire")
	if full:
		ScreenPanelScript.label(column,
			"Four is as many as will follow one purse. Part with somebody first.",
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)

	for candidate in GameState.hire_roster():
		var price := int(candidate["price"])
		ScreenPanelScript.heading(column, String(candidate["character_name"]))
		for line in HirelingScript.describe(candidate):
			ScreenPanelScript.label(column, line, ScreenPanelScript.BODY_SIZE,
				ScreenPanelScript.BODY)
		var afford: bool = GameState.gold >= price
		ScreenPanelScript.label(column, "Asks %d gold to come along." % price,
			ScreenPanelScript.BODY_SIZE,
			ScreenPanelScript.MUTED if afford else ScreenPanelScript.BAD)
		# The button carries the name, so a test that walks this screen by pressing buttons
		# cannot match the wrong one — the same reason the notice board's buttons do.
		ScreenPanelScript.button(column,
			"Hire %s — %d gold" % [candidate["character_name"], price],
			_on_hire.bind(candidate), afford and not full)
		ScreenPanelScript.spacer(column, 6.0)

	ScreenPanelScript.label(column,
		"They take other work while you are away. Whoever is here now will not be here when "
		+ "you get back.", ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


# --- What the buttons do ---------------------------------------------------

func _on_hire(candidate: Dictionary) -> void:
	var who := String(candidate.get("character_name", "They"))
	if not GameState.hire(candidate):
		# The button should have been disabled, so this is a screen out of step with the state
		# rather than something the player did wrong. Say what is actually in the way.
		ScreenPanelScript.toast(self, "%s is not coming — the company is full or the purse is."
			% who)
		return
	# Hiring both spends gold and changes the party, which is exactly the kind of change the
	# town is the checkpoint for. Saved here rather than on the way back out, so closing the
	# game on this screen does not undo it.
	SaveGameScript.save()
	_confirming = -1
	_build()
	ScreenPanelScript.toast(self, "%s takes the coin and shoulders their pack." % who)


func _on_confirm(index: int) -> void:
	_confirming = index
	_build()


func _on_dismiss(index: int) -> void:
	if index <= 0 or index >= GameState.party.size():
		return
	var who: String = GameState.party[index].character_name
	if not GameState.remove_member(index):
		return
	SaveGameScript.save()
	_confirming = -1
	_build()
	ScreenPanelScript.toast(self, "%s takes their kit and goes." % who)


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
