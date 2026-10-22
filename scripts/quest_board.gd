extends Control
## The notice board: the jobs going in Riverwatch, and the screen where a party decides which
## one it is good enough for.
##
## It is also the way OUT of town: the gate opens this screen, because every trip underground
## is now a trip into a particular place.
##
## The board owns NOTHING. What is pinned up is GameState.quest_offers — three jobs that stay
## until they are cleared or thrown away, each a seed and a tier (see QuestDef). Discarding one
## takes it down and pins a new one up in its place, on the spot.
##
## Taking a job sets GameState.current_quest and goes underground, where RoomBuilder builds the
## dungeon from that same seed and tier. Clear it and the reward is paid and the job comes off
## the board; walk out early and it is not, and the job is still there for another try.

const ScreenPanelScript := preload("res://scripts/ui_kit.gd")
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

	var shown: Array = GameState.quest_board().duplicate()
	shown.sort_custom(func(a, b): return a.tier < b.tier)
	for offer in shown:
		_draw_offer(column, offer)

	ScreenPanelScript.spacer(column, 6.0)
	ScreenPanelScript.label(column,
		"A notice stays up until the job is done or you tear it down.",
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
	ScreenPanelScript.button(column, "Discard: %s" % offer.title, _on_discard.bind(offer))
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


func _on_discard(offer) -> void:
	## Tear the notice down and redraw with the new one in its place. Saved, because the board
	## IS saved state now — a discard undone by quitting would be a free reroll.
	if not GameState.discard_offer(offer):
		return
	SaveGameScript.save()
	print("[Board] discarded: %s (tier %d, seed %d)" % [offer.title, offer.tier, offer.quest_seed])
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
