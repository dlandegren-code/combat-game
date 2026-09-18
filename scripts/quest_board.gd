extends Control
## The notice board: the jobs going in Riverwatch, and the screen where a party decides which
## one it is good enough for.
##
## The board owns NOTHING. What is pinned up is derived from GameState.board_seed every time
## this screen is opened (GameState.quest_board), so closing it and opening it again shows the
## same four jobs, and the only way the list changes is the party coming back from a quest.
## That is the whole reason a quest is a seed and a tier — see QuestDef.
##
## WHAT TAKING A JOB DOES TODAY
## It sets GameState.current_quest and runs the one authored dungeon, because the generator
## that would build the place described is the next piece of Phase 4. So the tier, the theme
## and the enemy budget are on the card and not yet in the room. The one part that IS real is
## the contract: clear the dungeon with a job accepted and the reward is paid, walk out early
## and it is not. That is deliberate — the payment side is the part the rest of the game
## (results screen, save, economy) has to be wired through, and wiring it through a fixed room
## is how the generator lands later as a change to one scene rather than to six files.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"
const QUEST_SCENE := "res://scenes/quest_scene.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self, true)
	ScreenPanelScript.title(column, "The Notice Board")

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody here to take a job.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	var main = GameState.main_character()
	ScreenPanelScript.label(column,
		"%s, level %d — %d gold in the purse." % [
			main.character_name, main.level, GameState.gold],
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	for offer in GameState.quest_board():
		_draw_offer(column, offer)

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.label(column,
		"New notices go up while you are away. These will be gone when you get back.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)


func _draw_offer(column: Node, offer) -> void:
	ScreenPanelScript.heading(column, offer.title)
	ScreenPanelScript.label(column, offer.danger_line(), ScreenPanelScript.BODY_SIZE,
		_danger_colour(offer))
	ScreenPanelScript.label(column, offer.reward_line(), ScreenPanelScript.BODY_SIZE,
		ScreenPanelScript.MUTED)
	# The button carries the title, not "Accept". A screen the round-trip test walks by
	# pressing buttons has to have buttons that say which one they are, or a test that presses
	# the wrong one passes exactly as happily as one that presses the right one.
	ScreenPanelScript.button(column, "Take: %s" % offer.title, _on_take.bind(offer))
	ScreenPanelScript.spacer(column, 6.0)


func _danger_colour(offer) -> Color:
	## Green for work below the party's weight, amber-ish body text at their level, red above
	## it. The board is allowed to have an opinion — a tier number means nothing to somebody
	## reading it for the first time, and the one thing a notice board is for is letting a
	## player see at a glance which of these will get them killed.
	var level: int = GameState.main_character().level if GameState.has_party() else 1
	if offer.tier < level:
		return ScreenPanelScript.GOOD
	if offer.tier > level:
		return ScreenPanelScript.BAD
	return ScreenPanelScript.BODY


func _on_take(offer) -> void:
	GameState.accept_quest(offer)
	# Saved BEFORE the party leaves, so a crash underground costs the run and not the contract
	# — and so the board the save carries is the one this job was taken off. Town is still the
	# only place that writes (see SaveGame); this is town, one step before the gate.
	SaveGameScript.save()
	print("[Board] taken: %s (tier %d, seed %d)" % [offer.title, offer.tier, offer.quest_seed])
	get_tree().change_scene_to_file(QUEST_SCENE)


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
