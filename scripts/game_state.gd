extends Node
## The one thing in the game that outlives a scene change: the party, its purse, and the
## quest it is on.
##
## Registered as an autoload (GameState), so it is a sibling of whatever scene is loaded and
## is never freed by loading another one. Everything a hero has earned lives in here as
## CharacterData; the town, the quest and the results screen all read the same copy.
##
## Deliberately dumb. It holds state and announces when it changes — it does not know how to
## build a combatant, run a quest or draw a screen. Hydration belongs to QuestScene, saving
## to the save system (Phase 2), and the rules of progression to the training screen
## (Phase 3). Keeping those out is what stops this from becoming the place every feature
## reaches into.

const CharacterDataScript := preload("res://scripts/character_data.gd")

## Bumped when the shape of a SAVE changes, independently of a character's own schema — see
## CharacterData.SCHEMA_VERSION.
const SCHEMA_VERSION := 1

signal party_changed
signal gold_changed(amount: int)

## The party, main character first. One member for now; hirelings join this same array in
## Phase 5, which is the whole reason it is an array from the start.
var party: Array = []

var gold: int = 0

## The quest being run, or {} in town. A plain Dictionary until Phase 4 gives quests a
## QuestDef resource of their own.
var current_quest: Dictionary = {}

## What the last quest paid out, for the town to report when the party walks back in:
## {outcome, kills, xp, gold}. Cleared once it has been shown.
var last_result: Dictionary = {}


func has_party() -> bool:
	return not party.is_empty()


func main_character():
	## The character the player made. Hirelings are everyone after them.
	return party[0] if has_party() else null


func add_member(data) -> void:
	party.append(data)
	party_changed.emit()


func clear() -> void:
	## Abandon everything: for starting a new game over the top of an old one.
	party = []
	gold = 0
	current_quest = {}
	last_result = {}
	party_changed.emit()


func award_xp(amount: int) -> void:
	## Split nothing and round nothing: everyone who went on the quest gets the full amount.
	##
	## Shared rather than divided so that taking a hireling along is never a tax on the main
	## character's progress — a party that levels slower than a lone hero would make Phase 5
	## a downgrade. What xp then BUYS is the training screen's business (Phase 3); until it
	## exists, this is a running total of what the party has earned.
	if amount <= 0:
		return
	for member in party:
		member.xp += amount
	party_changed.emit()


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


func rest_party() -> void:
	## Everybody back to full. Called when the party reaches town, which is the only place
	## that has beds in it.
	##
	## Free for now, and that is a placeholder rather than a decision: healing is exactly the
	## sort of thing the town economy should charge for (Phase 3), and a downed hero should
	## probably cost more than a scratched one. Until there is an economy to charge against,
	## a quest that leaves the party at 2 hp must not make the next one unplayable.
	for member in party:
		member.hp = CharacterDataScript.VITALS_FULL
		member.mana = CharacterDataScript.VITALS_FULL
		member.ammo = CharacterDataScript.VITALS_FULL


func take_last_result() -> Dictionary:
	## Read the last quest's outcome and forget it, so a second visit to town does not report
	## the same adventure again.
	var out := last_result
	last_result = {}
	return out


# --- Serialisation ---------------------------------------------------------
# The save system (Phase 2) writes these to user:// as JSON. No file I/O here on purpose:
# what a save CONTAINS is this object's business, and where it lives is not.

func to_dict() -> Dictionary:
	var members: Array = []
	for member in party:
		members.append(member.to_dict())
	return {
		"schema": SCHEMA_VERSION,
		"gold": gold,
		"party": members,
	}


func from_dict(d: Dictionary) -> void:
	party = []
	for entry in d.get("party", []):
		party.append(CharacterDataScript.from_dict(entry))
	gold = int(d.get("gold", 0))
	current_quest = {}
	last_result = {}
	party_changed.emit()
	gold_changed.emit(gold)
