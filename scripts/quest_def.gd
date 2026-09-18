extends Resource
class_name QuestDef
## One quest, described before anybody goes on it.
##
## A quest is a SEED and a TIER. Everything else — what it is called, where it claims to be,
## how many enemies are down there, what it pays — is DERIVED from those two numbers, so the
## only thing that has to be stored, shown on a board, saved, or handed to a generator is a
## pair of integers. Two quests with the same seed and tier are the same quest, on this
## machine and on anybody else's, today and after a rebalance of the tables below.
##
## That is the property Phase 4's verification is written against: "the same seed reproduces
## the same quest". It is also what makes a quest board cheap — the board stores its own seed
## and re-derives its offers, rather than keeping five resources alive between screens.
##
## WHAT IS AND IS NOT HOOKED UP YET
## `reward_gold` and `reward_xp` are paid, today, by QuestScene when a quest is cleared.
## `enemy_budget`, `loot_budget` and `theme` are DERIVED but not yet SPENT: the spawner, the
## loot tables and the parameterised room builder are the next three pieces of Phase 4, and
## until they exist every accepted quest runs the one authored dungeon. The budgets are here
## now because they are what those pieces will be written against, and because a tier that
## only changes the payout is a tier that lies about being harder.

## The hardest quest the board will ever put up. Tiers are meant to be few and to mean
## something: five steps between "a job for a beginner" and "this will probably kill you"
## leaves each one a recognisable change, where fifteen would leave the player unable to tell
## tier 7 from tier 8.
const MAX_TIER := 5

## --- What a tier is worth ---
## Paid ON CLEARING, on top of what the bodies themselves are worth (QuestScene's per-kill
## rates). The split is deliberate: kills pay for the fighting, the contract pays for
## finishing the job, and a party that retreats halfway keeps the first and forfeits the
## second. Tier 1 is sized to roughly match the five-enemy dungeon's kill income, so taking a
## contract for a room you were going to clear anyway about doubles what the trip is worth.
const REWARD_GOLD_BASE := 60
const REWARD_GOLD_STEP := 40
const REWARD_XP_BASE := 80
const REWARD_XP_STEP := 60

## --- What a tier costs to survive ---
## Difficulty points for the spawner to spend, in the same currency enemy templates will be
## priced in. Ten is the authored dungeon: five goblins at two points each.
const ENEMY_BUDGET_BASE := 10
const ENEMY_BUDGET_STEP := 6

## Gold-value of the loot the generator is to place. Loot is NOT scaled as steeply as the
## danger, on purpose — a deeper dungeon should be worth going into for the contract and the
## fight, not because the chests get proportionally fatter with every tier.
const LOOT_BUDGET_BASE := 60
const LOOT_BUDGET_STEP := 40

## How far either reward may drift from its tier's flat rate, so two tier-3 contracts on the
## same board are not obviously the same contract twice. Small enough that it never reorders
## the tiers: a lucky tier 2 must not out-pay an unlucky tier 3.
const REWARD_VARIANCE := 0.15

## What a tier is called on a board. A number tells a player nothing on their first visit.
const TIER_LABELS := ["", "Simple", "Steady", "Hard", "Grim", "Deadly"]

## The places a quest can claim to be, with the words each one is named out of.
##
## Theme does not yet reach the battlefield — see the header — so for now it decides the name
## and nothing else. It is a table rather than a list of strings because that is the shape it
## needs when the room builder and the spawner start reading it: `enemies` and `palette` are
## the columns waiting to be added, and adding them to a table nobody reads is how this stays
## a one-line change rather than a rewrite.
const THEMES := [
	{
		"id": "dungeon",
		"label": "dungeon",
		"task": ["Clear", "Sweep", "Take back"],
		"adjective": ["Old", "Sunken", "Iron", "Broken", "Quiet"],
		"place": ["Dungeon", "Undercroft", "Keep", "Cells", "Guardroom"],
	},
	{
		"id": "crypt",
		"label": "crypt",
		"task": ["Clear", "Sanctify", "Search"],
		"adjective": ["Flooded", "Sealed", "Cold", "Forgotten", "Hollow"],
		"place": ["Crypt", "Ossuary", "Tombs", "Vault", "Barrow"],
	},
	{
		"id": "warren",
		"label": "warren",
		"task": ["Clear", "Smoke out", "Break up"],
		"adjective": ["Stinking", "Deep", "Crowded", "Rotten", "Low"],
		"place": ["Warren", "Burrows", "Nest", "Den", "Tunnels"],
	},
]

@export var quest_seed: int = 0
@export var tier: int = 1
@export var theme: String = "dungeon"
@export var title: String = ""
@export var enemy_budget: int = 0
@export var loot_budget: int = 0
@export var reward_gold: int = 0
@export var reward_xp: int = 0


# --- Making one ------------------------------------------------------------

static func generate(from_seed: int, at_tier: int) -> QuestDef:
	## The one way a quest comes into existence. Same two numbers in, same quest out.
	##
	## Every draw comes off ONE generator seeded once, so the order of the draws below is part
	## of the contract: inserting a new roll in the middle changes every quest that has ever
	## been generated. New rolls go at the END, which is the same discipline the item enums
	## are kept under (ItemResource.ItemType) and for the same reason.
	var def := QuestDef.new()
	def.quest_seed = from_seed
	def.tier = clampi(at_tier, 1, MAX_TIER)

	var rng := RandomNumberGenerator.new()
	rng.seed = from_seed

	var theme_entry: Dictionary = THEMES[rng.randi() % THEMES.size()]
	def.theme = String(theme_entry["id"])
	def.title = _name_from(rng, theme_entry)

	var step := def.tier - 1
	def.enemy_budget = ENEMY_BUDGET_BASE + ENEMY_BUDGET_STEP * step
	def.loot_budget = LOOT_BUDGET_BASE + LOOT_BUDGET_STEP * step
	def.reward_gold = _varied(rng, REWARD_GOLD_BASE + REWARD_GOLD_STEP * step)
	def.reward_xp = _varied(rng, REWARD_XP_BASE + REWARD_XP_STEP * step)
	return def


static func offers(board_seed: int, party_level: int, count: int) -> Array:
	## A board's worth of quests, hardest last.
	##
	## The tiers are spread AROUND the party rather than handed out at random: a board of five
	## tier-5 contracts for a fresh hero is a board with nothing on it, and one of five tier-1s
	## for a veteran is the same board in the other direction. One step below the party so
	## there is always something safe, two above so there is always something they are not
	## ready for — which is the reason to come back.
	var centre := clampi(party_level, 1, MAX_TIER)
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed

	var out: Array = []
	for i in range(maxi(1, count)):
		var tier_for_this := clampi(centre + rng.randi_range(-1, 2), 1, MAX_TIER)
		# Each offer gets a seed of its OWN, derived from the board's. Two quests on one board
		# are then independent — the same seed cannot turn up twice because the board happened
		# to roll the same tier — and an accepted quest can be carried around, saved and
		# regenerated knowing only that one number.
		out.append(generate(rng.randi(), tier_for_this))
	out.sort_custom(func(a, b): return a.tier < b.tier)
	return out


static func _name_from(rng: RandomNumberGenerator, theme_entry: Dictionary) -> String:
	var task: Array = theme_entry["task"]
	var adjective: Array = theme_entry["adjective"]
	var place: Array = theme_entry["place"]
	return "%s the %s %s" % [
		task[rng.randi() % task.size()],
		adjective[rng.randi() % adjective.size()],
		place[rng.randi() % place.size()],
	]


static func _varied(rng: RandomNumberGenerator, flat: int) -> int:
	## A tier's flat rate, nudged. Rounded to 5 so a board reads as prices somebody quoted
	## rather than as the output of a formula.
	var swing := 1.0 + rng.randf_range(-REWARD_VARIANCE, REWARD_VARIANCE)
	return maxi(5, roundi(flat * swing / 5.0) * 5)


# --- Describing one --------------------------------------------------------

func tier_label() -> String:
	var at := clampi(tier, 1, TIER_LABELS.size() - 1)
	return String(TIER_LABELS[at])


func theme_label() -> String:
	for entry in THEMES:
		if String(entry["id"]) == theme:
			return String(entry["label"])
	return theme


func reward_line() -> String:
	return "%d gold and %d xp for clearing it" % [reward_gold, reward_xp]


func danger_line() -> String:
	## What the party is walking into, in the only terms the board honestly has: a tier and a
	## rough count. Deliberately vague about the count — "about six" — because the spawner
	## that will actually fill the place does not exist yet, and a board that promised exactly
	## six enemies would be the first thing to break when it does.
	return "%s — a %s, about %d of them down there" % [
		tier_label(), theme_label(), roundi(enemy_budget / 2.0)]


# --- Carrying one around ---------------------------------------------------
# An accepted quest travels in GameState.current_quest and has to survive a save, so it goes
# to JSON as the two numbers it is made of. Everything else is regenerated, which means an
# in-flight quest written by an older build comes back re-costed by the current tables rather
# than paying yesterday's rates out of a file.

func to_dict() -> Dictionary:
	return {"seed": quest_seed, "tier": tier}


static func from_dict(d: Dictionary) -> QuestDef:
	if d.is_empty() or not d.has("seed"):
		return null
	return generate(int(d.get("seed", 0)), int(d.get("tier", 1)))
