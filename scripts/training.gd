extends Control
## The training hall: where a skill's experience becomes a skill level.
##
## There are three different things a player can do to a skill here, and keeping them distinct
## is the whole point of the screen:
##
##   LEVEL UP   spend the skill's own experience to raise it. The only way a skill goes up.
##   TRAIN      pay a trainer in gold for an hour's practice, which is worth skill experience
##              and nothing else. It does not raise the skill; it feeds the pot that does.
##   ASSIGN     move one point of general experience — the kind earned by finishing quests and
##              killing things — into a skill. Once per skill per quest, no more.
##
## So a skill you use goes up because you used it, a skill you cannot practise can be paid for
## slowly, and the experience from adventuring in general trickles wherever you point it. The
## numbers are all in progression.gd; this file is the buttons.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"

## Which party member is being trained. An index rather than the character, so rebuilding the
## screen after a purchase does not have to go looking for them again.
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
	ScreenPanelScript.label(column,
		"%d general xp unspent   ·   %d gold in the purse" % [member.xp, GameState.gold],
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.label(column,
		"Skills rise on their own experience, earned by using them. General xp may be pushed "
		+ "into a skill one point at a time, once each per quest.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)

	for entry in ProgressionScript.SKILLS:
		_add_skill(column, member, entry)

	ScreenPanelScript.separator(column)
	ScreenPanelScript.label(column,
		"Attributes — strength, agility, stamina, intelligence, willpower — are raised by "
		+ "neither of these. They are waiting on a currency of their own.",
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)
	ScreenPanelScript.separator(column)
	ScreenPanelScript.button(column, "Back to town", _on_back)
	ScreenPanelScript.spacer(column, 16.0)


func _add_skill(column: Node, member, entry: Dictionary) -> void:
	var field: String = entry["field"]
	var current: int = int(member.stats.get(field))
	var banked: int = member.skill_xp_for(field)
	var capped: bool = current >= ProgressionScript.SKILL_CAP

	var headline: String = "%s  %d" % [entry["label"], current]
	if capped:
		headline += "   ·   trained as far as it goes"
	else:
		headline += "   ·   %d / %d skill xp toward %d" % [
			banked, ProgressionScript.xp_to_level(current), current + 1]
	ScreenPanelScript.heading(column, headline)
	ScreenPanelScript.label(column, "    " + String(entry["note"]),
		ScreenPanelScript.BODY_SIZE, ScreenPanelScript.MUTED)

	if capped:
		return

	var row := ScreenPanelScript.row(column)

	var level_button := ScreenPanelScript.button(row,
		"Level up to %d" % (current + 1), _on_level.bind(field),
		ProgressionScript.can_level(member, field))
	level_button.custom_minimum_size = Vector2(190, ScreenPanelScript.BUTTON_HEIGHT)
	level_button.size_flags_horizontal = Control.SIZE_FILL

	var price: int = ProgressionScript.train_gold_cost(current)
	var train_button := ScreenPanelScript.button(row,
		"Train — %d gold" % price, _on_train.bind(field),
		ProgressionScript.can_train(member, field, GameState.gold))
	train_button.custom_minimum_size = Vector2(170, ScreenPanelScript.BUTTON_HEIGHT)
	train_button.size_flags_horizontal = Control.SIZE_FILL

	var assign_button := ScreenPanelScript.button(row,
		"Assign 1 general xp", _on_assign.bind(field), member.may_assign_general(field))
	assign_button.custom_minimum_size = Vector2(200, ScreenPanelScript.BUTTON_HEIGHT)
	assign_button.size_flags_horizontal = Control.SIZE_FILL


# --- What the buttons do ---------------------------------------------------

func _on_level(field: String) -> void:
	var member = GameState.party[_who]
	var refusal: String = ProgressionScript.level_refusal(member, field)
	if refusal != "":
		ScreenPanelScript.toast(self, refusal)
		return
	if not ProgressionScript.level_up(member, field):
		ScreenPanelScript.toast(self, "That level could not be bought.")
		return
	_after_change("%s is now %d." % [ProgressionScript.label_for(field),
		int(member.stats.get(field))])


func _on_train(field: String) -> void:
	var member = GameState.party[_who]
	var refusal: String = ProgressionScript.train_refusal(member, field, GameState.gold)
	if refusal != "":
		ScreenPanelScript.toast(self, refusal)
		return
	var price: int = ProgressionScript.train_gold_cost(int(member.stats.get(field)))
	if not GameState.spend_gold(price):
		ScreenPanelScript.toast(self, "Not enough gold.")
		return
	member.add_skill_xp(field, ProgressionScript.TRAIN_XP)
	_after_change("An hour of %s: +%d skill xp." % [
		ProgressionScript.label_for(field).to_lower(), ProgressionScript.TRAIN_XP])


func _on_assign(field: String) -> void:
	var member = GameState.party[_who]
	if not member.assign_general_xp(field):
		# Two different refusals, and the player can act on each: wait for the next quest, or
		# go and earn some.
		if member.xp <= 0:
			ScreenPanelScript.toast(self, "%s has no general xp left." % member.character_name)
		else:
			ScreenPanelScript.toast(self, "%s has already taken its point from this quest."
				% ProgressionScript.label_for(field))
		return
	_after_change("+1 skill xp into %s." % ProgressionScript.label_for(field).to_lower())


func _after_change(note: String) -> void:
	GameState.party_changed.emit()
	# Progress belongs on disk. Town saves on arrival, but a player who trains three skills and
	# then closes the window should not lose them.
	SaveGameScript.save()
	_build()
	ScreenPanelScript.toast(self, note)


func _on_pick(index: int) -> void:
	_who = index
	_build()


func _on_back() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
