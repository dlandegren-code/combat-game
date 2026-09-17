extends Control
## The town: where the party is between quests, and the hub the whole game loop turns on.
##
## Pure UI, on purpose. A walkable 3D town is a lot of work for the same four decisions, and
## every one of those decisions is a button — so this is the cheap version of the right
## structure, and the screens behind the buttons do not care that it is cheap. If a proper
## town is ever built, it replaces this file and nothing else.
##
## The Quest Board is Phase 4 and its button says so rather than being absent, because the
## shape of the town is part of what these screens are for.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const CharacterDataScript := preload("res://scripts/character_data.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const CombatantScript := preload("res://scripts/combatant.gd")

const QUEST_SCENE := "res://scenes/quest_scene.tscn"
const CREATION_SCENE := "res://scenes/character_creation.tscn"
const TITLE_SCENE := "res://scenes/title_screen.tscn"
const TRAINING_SCENE := "res://scenes/training.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"

## What the last save attempt did, shown in the party panel: "" for none yet.
var _save_note: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Arriving in town IS the checkpoint. Everything that happened on the quest has already
	# been written back into the party by now (QuestScene.finish_quest), and nothing here is
	# mid-anything — see SaveGame's note on why this is the only moment the game saves.
	_autosave()
	_build()


func _autosave() -> void:
	if not GameState.has_party():
		return
	if SaveGameScript.save():
		_save_note = "Saved."
	else:
		# Loud, and stays on screen: a failed save is the one error in this game that costs
		# the player something they cannot get back by playing better.
		_save_note = "COULD NOT SAVE — see the console. Your progress is not on disk."


func _build() -> void:
	var column := ScreenPanelScript.mount(self)

	ScreenPanelScript.title(column, "Riverwatch")
	ScreenPanelScript.label(column,
		"A hard little town at the edge of the map. Train, buy what you can afford, and go "
		+ "back down into the dark.", ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	_add_party(column)
	ScreenPanelScript.separator(column)

	ScreenPanelScript.button(column, "Go Adventuring", _on_adventure, GameState.has_party())
	ScreenPanelScript.button(column, "Quest Board", _on_quest_board)
	ScreenPanelScript.button(column, "Shop", _on_shop)
	ScreenPanelScript.button(column, "Training", _on_training)
	if _anyone_hurt():
		var price: int = _rest_price()
		ScreenPanelScript.button(column, "Rest — %d gold" % price, _on_rest,
			GameState.gold >= price)
	ScreenPanelScript.spacer(column, 6.0)
	# The way to a different character. Safe to walk out of at any time: the party was saved
	# on arrival, so leaving town loses nothing.
	ScreenPanelScript.button(column, "Main Menu", _on_title)
	ScreenPanelScript.button(column, "Quit", func(): get_tree().quit())


func _add_party(column: Node) -> void:
	if not GameState.has_party():
		# Reachable only by getting here without a character, which the bootstrap is supposed
		# to prevent. Say so and offer the way out rather than showing an empty town.
		ScreenPanelScript.heading(column, "Nobody here yet")
		ScreenPanelScript.button(column, "Create a character", _on_create)
		return

	var banked: String = "Your party — %d gold" % GameState.gold
	if _save_note != "":
		banked += "      " + _save_note
	ScreenPanelScript.heading(column, banked)
	for member in GameState.party:
		ScreenPanelScript.label(column, "%s the %s — level %d, %d xp to spend, %s" % [
			member.character_name,
			CharacterClassesScript.display_name(member.class_id),
			member.level,
			member.xp,
			_condition(member),
		], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.HEADING)
		ScreenPanelScript.label(column, "    " + _gear_line(member),
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


func _condition(member) -> String:
	## Wounds are carried between quests — see CharacterData.VITALS_FULL for why "full" is a
	## sentinel rather than a number.
	if member.hp == CharacterDataScript.VITALS_FULL:
		return "unhurt"
	return "wounded (%d hp)" % member.hp


func _gear_line(member) -> String:
	var worn: Array = []
	var seen: Array = []
	for slot in member.equipped.keys():
		var idx: int = int(member.equipped[slot])
		if idx < 0 or idx >= member.bag.size() or member.bag[idx] == null:
			continue
		# A two-hander is listed under both hands; name it once.
		if seen.has(idx):
			continue
		seen.append(idx)
		worn.append(member.bag[idx].item_name)
	var carried: Array = []
	for i in range(member.bag.size()):
		if member.bag[i] != null and not seen.has(i):
			carried.append(member.bag[i].item_name)
	var parts: Array = []
	parts.append("using " + ", ".join(worn) if not worn.is_empty() else "empty-handed")
	if not carried.is_empty():
		parts.append("carrying " + ", ".join(carried))
	return "; ".join(parts)


func _anyone_hurt() -> bool:
	for member in GameState.party:
		if member.hp != CharacterDataScript.VITALS_FULL:
			return true
	return false


# --- Buttons ---------------------------------------------------------------

func _on_adventure() -> void:
	get_tree().change_scene_to_file(QUEST_SCENE)


func _on_create() -> void:
	get_tree().change_scene_to_file(CREATION_SCENE)


func _on_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _rest_price() -> int:
	## Charged per hit point actually missing, so patching up a scratch is cheap and carrying
	## a half-dead party home is not. Mana is mended for nothing — it comes back on its own
	## with a night's sleep, and charging for it would be charging twice for the same bed.
	var missing := 0
	for member in GameState.party:
		if member.hp != CharacterDataScript.VITALS_FULL:
			missing += maxi(0, _max_hp_of(member) - member.hp)
	return maxi(1, missing * ProgressionScript.REST_GOLD_PER_HP)


func _max_hp_of(member) -> int:
	## What this character's hit points come to, worked out the way the body does it — there is
	## no body in town to ask. See Combatant._derive_stats.
	return maxi(1, int(member.stats.stamina) * CombatantScript.HP_PER_STAMINA)


func _on_rest() -> void:
	var price: int = _rest_price()
	if not GameState.spend_gold(price):
		ScreenPanelScript.toast(self, "A bed costs %d gold and the party has %d."
			% [price, GameState.gold])
		return
	GameState.rest_party()
	# Saved straight away, like every other change made in town: the save should never be a
	# worse version of the party than the one on screen.
	_autosave()
	_build()
	ScreenPanelScript.toast(self, "Rested. Arrows are not included — buy those.")


func _on_quest_board() -> void:
	ScreenPanelScript.toast(self,
		"The board is empty — random quests are Phase 4. Go Adventuring runs the one dungeon.")


func _on_shop() -> void:
	get_tree().change_scene_to_file(SHOP_SCENE)


func _on_training() -> void:
	get_tree().change_scene_to_file(TRAINING_SCENE)
