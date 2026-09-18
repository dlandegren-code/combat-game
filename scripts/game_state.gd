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
const ProgressionScript := preload("res://scripts/progression.gd")
const QuestDefScript := preload("res://scripts/quest_def.gd")
const HirelingScript := preload("res://scripts/hireling.gd")

## Bumped when the shape of a SAVE changes, independently of a character's own schema — see
## CharacterData.SCHEMA_VERSION.
##
## 2 added the quest board's seed and the mercenary camp's. A version-1 save has neither, and
## both read as "nothing rolled yet" — which rolls a fresh one on the first visit, the same
## thing that happens to a new game.
const SCHEMA_VERSION := 2

## How many jobs are pinned up at once. Enough that there is a choice and a reason to weigh
## one against another, few enough that the board is read rather than scanned — and few enough
## that a party with no good option has to go and earn a level rather than hunt the list for
## the one quest that suits them.
const BOARD_OFFERS := 4

## How many bodies can go down at once, the hero included. Four because that is what the
## battlefield was built and balanced for — the authored scenario stands three heroes against
## five enemies — and because a fifth portrait starts crowding the column down the left of the
## quest screen. Raising it is a number here and a look at party_panel.gd.
const PARTY_MAX := 4

## How many sell-swords are sitting round the camp fire at once.
const CAMP_HIRELINGS := 3

signal party_changed
signal gold_changed(amount: int)

## The party, main character first, and everyone hired at the camp after them. Capped at
## PARTY_MAX. An array from the first day precisely so that hiring, when it arrived, was a
## screen and a price rather than a rewrite.
var party: Array = []

var gold: int = 0

## The contract the party is out on, or null — in town, and on a trip through the gate that
## nobody was paid to make. Set when a quest is taken off the board and cleared the moment the
## run is written back (QuestScene.settle).
##
## Untyped on purpose. This is an autoload, so it is parsed before most of the project, and
## naming a `class_name` here would tie it to the global class cache — which this project has
## been bitten by before for freshly-written scripts (see Combatant and its path-based
## `extends`). The preload above is the dependable way to reach the same script.
var current_quest = null

## What the quest board is showing. ONE number, because a board is its offers and its offers
## are derived from it (QuestDef.offers) — so the board can be closed, walked away from, saved
## and come back to without five quests being kept alive in between.
##
## Zero means "no board yet". It is rolled on the first visit and re-rolled whenever the party
## comes back from a quest, which is what makes the notice board worth reading again: the jobs
## that were on it were taken, or went to somebody else while you were underground.
var board_seed: int = 0

## Who is at the mercenary camp, kept exactly the way the board is and for the same reasons:
## one number, re-derived on every read, re-rolled when the party comes back from a quest. The
## people who were sitting round that fire took other work while you were underground.
var camp_seed: int = 0

## What the last quest paid out, for the town to report when the party walks back in:
## {outcome, kills, xp, gold}. Cleared once it has been shown.
var last_result: Dictionary = {}


func has_party() -> bool:
	return not party.is_empty()


func main_character():
	## The character the player made. Hirelings are everyone after them.
	return party[0] if has_party() else null


func party_is_full() -> bool:
	return party.size() >= PARTY_MAX


func add_member(data) -> bool:
	## Take somebody on. Returns false and changes nothing when there is no room, so a screen
	## with its buttons wrong cannot walk a fifth body into a four-body party.
	##
	## The cap is NOT applied to the seeding path that reads the old authored battlefield —
	## that scenario has three heroes and the cap is four, so it has never come near it. If the
	## authored party ever grows past the cap, this is the line that will say so.
	if party_is_full():
		return false
	party.append(data)
	party_changed.emit()
	return true


func remove_member(index: int) -> bool:
	## Part ways with a hireling. Returns false for a bad index or for the main character, who
	## cannot be dismissed — they are the one the save is about.
	##
	## Everything they were carrying goes with them, gear the party bought included. That is
	## the honest reading of paying somebody off, and it is what stops the camp from being a
	## way to launder a cheap recruit into a free set of leather armour: hire, strip, dismiss,
	## repeat. If that ever needs softening, it softens HERE, by handing their bag back.
	if index <= 0 or index >= party.size():
		return false
	party.remove_at(index)
	party_changed.emit()
	return true


func clear() -> void:
	## Abandon everything: for starting a new game over the top of an old one.
	party = []
	gold = 0
	current_quest = null
	board_seed = 0
	camp_seed = 0
	last_result = {}
	party_changed.emit()


# --- The quest board -------------------------------------------------------
# What is ON the board is QuestDef's business and DRAWING it is the board screen's. All that
# lives here is the seed, because that is the part that has to outlive both of them.

func quest_board() -> Array:
	## The offers currently pinned up, rolling a board if there is not one yet.
	##
	## Sized off the main character, not the party: a hireling's level is the hireling's, and a
	## veteran taking on a porter should not find the board suddenly offering easier work.
	if board_seed == 0:
		reroll_board()
	var level: int = main_character().level if has_party() else 1
	return QuestDefScript.offers(board_seed, level, BOARD_OFFERS)


func reroll_board() -> void:
	## New jobs on the board. Called on the first visit and on every return from a quest.
	##
	## randi() rather than the clock: two boards rolled in the same second must not be the
	## same board, and a run started at midnight must not get a different game from one
	## started at noon.
	board_seed = randi()
	if board_seed == 0:
		# Zero is the "no board" marker, so it is the one number this cannot return.
		board_seed = 1


# --- The mercenary camp ----------------------------------------------------
# The same shape as the board above, because it is the same idea: a seed, and people derived
# from it. WHO is at the camp is Hireling's business and drawing them is the camp screen's.

func hire_roster() -> Array:
	## Who is round the fire today, rolling a camp if there is not one yet.
	if camp_seed == 0:
		reroll_camp()
	var level: int = main_character().level if has_party() else 1
	return HirelingScript.roster(camp_seed, level, CAMP_HIRELINGS)


func reroll_camp() -> void:
	## New faces at the fire. Called on the first visit, on every return from a quest, and
	## after a hire — the person you just took on is not still sitting there to be hired twice.
	camp_seed = randi()
	if camp_seed == 0:
		camp_seed = 1


func hire(candidate: Dictionary) -> bool:
	## Take somebody on: pay them, add them, and roll the camp so they are not offered again.
	##
	## The ONE place hiring happens, so the three things that must go together cannot come
	## apart — a screen that spent the gold without adding the body, or added the body without
	## spending the gold, would both be one forgotten line away.
	if party_is_full():
		return false
	var price := int(candidate.get("price", 0))
	if not spend_gold(price):
		return false
	var data = HirelingScript.make_character(candidate)
	if not add_member(data):
		# Cannot happen — the cap was checked above — but refunding rather than swallowing the
		# gold is the difference between a bug and a bug that costs the player money.
		add_gold(price)
		return false
	reroll_camp()
	return true


func accept_quest(def) -> void:
	## Take a contract. From here until finish_quest the party is working for somebody.
	current_quest = def


func abandon_quest() -> void:
	current_quest = null


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
		# Two counters, and both of them matter: `xp` is the pool training spends, `xp_total`
		# is the life's work that decides the level. See CharacterData.
		member.xp += amount
		member.xp_total += amount
		member.level = ProgressionScript.level_for(member.xp_total)
	party_changed.emit()


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	## Take gold if there is enough, and say whether there was.
	##
	## Separate from add_gold(-n), which clamps at zero: a purchase must not go through for
	## whatever the party happened to have. Everything that spends money goes through here.
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func rest_party() -> void:
	## Everybody back to full. Called when the party pays for a night in town, which is the
	## only place with beds in it — the price is Town's business (Progression.REST_GOLD_PER_HP).
	##
	## Hit points and mana, and deliberately NOT ammunition. Sleeping mends a man and clears
	## his head; it does not put arrows back in his quiver. Arrows are bought, which is what
	## makes the bundle on the market shelf worth anything and what makes an archer's upkeep
	## different from a soldier's.
	for member in party:
		member.hp = CharacterDataScript.VITALS_FULL
		member.mana = CharacterDataScript.VITALS_FULL


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
		# The board, but not the quest: saving happens in town, and in town there is no quest
		# to be on. A save that carried one would be a save of a run that was abandoned.
		"board_seed": board_seed,
		"camp_seed": camp_seed,
	}


func from_dict(d: Dictionary) -> void:
	party = []
	for entry in d.get("party", []):
		party.append(CharacterDataScript.from_dict(entry))
	gold = int(d.get("gold", 0))
	board_seed = int(d.get("board_seed", 0))
	camp_seed = int(d.get("camp_seed", 0))
	current_quest = null
	last_result = {}
	party_changed.emit()
	gold_changed.emit(gold)
