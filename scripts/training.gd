extends Control
## The training hall: where xp and gold become a better character.
##
## This is the screen the whole game is pointed at. Everything else — the quest, the loot, the
## gold — exists so that a number on this screen can go up, and the reason it costs both xp
## and gold is so that neither one of those is ever the only thing worth having. The rules and
## the prices are all in progression.gd; this file is the buttons.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## Which party member is being trained. An index rather than the character, so that rebuilding
## the screen after a purchase does not need to go looking for them again.
var _who: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var column := ScreenPanelScript.mount(self, true)
	ScreenPanelScript.title(column, "Training Hall")

	if not GameState.has_party():
		ScreenPanelScript.label(column, "Nobody to train.")
		ScreenPanelScript.button(column, "Back to town", _on_back)
		return

	_who = clampi(_who, 0, GameState.party.size() - 1)
	var member = GameState.party[_who]

	if GameState.party.size() > 1:
		var picker := ScreenPanelScript.row(column)
		for i in range(GameState.party.size()):
			var text: String = GameState.party[i].character_name
			if i == _who:
				text = "> %s <" % text
			var pick := ScreenPanelScript.button(picker, text, _on_pick.bind(i))
			pick.custom_minimum_size = Vector2(150, ScreenPanelScript.BUTTON_HEIGHT)
			pick.size_flags_horizontal = Control.SIZE_FILL

	ScreenPanelScript.heading(column, "%s the %s — level %d" % [
		member.character_name,
		CharacterClassesScript.display_name(member.class_id),
		member.level,
	])
	var to_next: int = ProgressionScript.xp_for_next_level(member.xp_total)
	var next_line: String = "%d xp to level %d" % [to_next, member.level + 1] if to_next > 0 \
		else "as high a level as there is"
	ScreenPanelScript.label(column, "%d xp to spend   ·   %d gold in the purse   ·   %s" % [
		member.xp, GameState.gold, next_line,
	], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	_add_section(column, "Skills", "skill", member)
	_add_section(column, "Attributes", "attribute", member)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)
	ScreenPanelScript.spacer(column, 16.0)


func _add_section(column: Node, heading: String, kind: String, member) -> void:
	ScreenPanelScript.heading(column, heading)
	for entry in ProgressionScript.TRAINABLE:
		if entry["kind"] != kind:
			continue
		var current: int = int(member.stats.get(entry["field"]))
		var capped: bool = current >= ProgressionScript.cap_for(kind)
		var affordable: bool = ProgressionScript.can_train(member, entry, GameState.gold)

		var text: String
		if capped:
			text = "%s  %d  (trained as far as it goes)" % [entry["label"], current]
		else:
			text = "%s  %d → %d      %d xp · %d gold" % [
				entry["label"], current, current + 1,
				ProgressionScript.xp_cost(kind, current),
				ProgressionScript.gold_cost(kind, current),
			]
		var button := ScreenPanelScript.button(column, text, _on_train.bind(entry), affordable)
		button.custom_minimum_size = Vector2(ScreenPanelScript.WIDTH, ScreenPanelScript.BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_FILL
		ScreenPanelScript.label(column, "    " + entry["note"],
			ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)


func _on_pick(index: int) -> void:
	_who = index
	_build()


func _on_train(entry: Dictionary) -> void:
	var member = GameState.party[_who]
	var kind: String = entry["kind"]
	var current: int = int(member.stats.get(entry["field"]))
	var price: int = ProgressionScript.gold_cost(kind, current)

	# The refusal is checked before anything is spent, and it explains itself — a disabled
	# button the player cannot see the reason for is worse than no button.
	var refusal: String = ProgressionScript.refusal(member, entry, GameState.gold)
	if refusal != "":
		ScreenPanelScript.toast(self, refusal)
		return
	# Gold first: if the purse says no, no xp has been touched. The other way round would cost
	# the character their experience for a lesson they never had.
	if not GameState.spend_gold(price):
		ScreenPanelScript.toast(self, "Not enough gold.")
		return
	if not ProgressionScript.train(member, entry):
		# Should be unreachable — refusal() has already said yes — so put the money back
		# rather than quietly keeping it.
		GameState.add_gold(price)
		ScreenPanelScript.toast(self, "That training could not be given.")
		return

	GameState.party_changed.emit()
	# Training is progress, and progress belongs on disk. Town saves on arrival, but a player
	# who trains three skills and then closes the window should not lose them.
	SaveGameScript.save()
	_build()
	ScreenPanelScript.toast(self, "%s is now %d." % [entry["label"],
		int(member.stats.get(entry["field"]))])


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
