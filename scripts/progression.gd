extends RefCounted
class_name Progression
## The rules for getting better: what can be trained, what it costs, and how far it goes.
##
## One file, because these numbers only mean anything against each other. A skill point that
## costs a quest's worth of xp is a different game from one that costs a tenth of a quest, and
## that comparison is impossible to make if the costs live next to the buttons that spend them.
##
## THE SHAPE OF IT
## Training spends BOTH xp and gold. The xp is what the character learned and the gold is what
## the lesson cost, and needing both is what stops either resource from being the only thing
## that matters: a rich character with no experience has nothing to train, and an experienced
## one with no money has to go and earn some.
##
## Costs rise with the value being bought, so the tenth point of a skill costs twice the fifth.
## That is what keeps a long game interesting without any need for a cap on how far a
## character can go — except that there IS a cap, because the dice are 1d5 and a skill of 30
## would make every roll a formality (see Combatant's defence rolls).
##
## Attributes cost about four times what a skill does, and they should: stamina is five hit
## points, willpower is five mana, and agility is the whole dodge defence.

const CombatantStatsScript := preload("res://scripts/combatant_stats.gd")

## Cost per point = STEP * the value being bought. Buying the 6th point of a skill costs
## 60 xp and 30 gold; the 6th point of an attribute costs 240 xp and 120 gold.
const SKILL_XP_STEP := 10
const SKILL_GOLD_STEP := 5
const ATTR_XP_STEP := 40
const ATTR_GOLD_STEP := 20

## Where training stops. Rolls in this game are skill + 1d5 against skill + 1d5, so the gap
## between two numbers matters more than either number: at 15 against an unskilled 5 the die
## cannot save the loser, and there is nothing left to play for.
const SKILL_CAP := 15
const ATTR_CAP := 10

## What each level costs, cumulatively: level 2 at 100 xp earned, 3 at 300, 4 at 600, 5 at
## 1000. Rising, so a level always represents more than the last one did.
##
## Level is a badge — nothing in combat reads it. It exists so a player can see progress in one
## number, and so Phase 4 has something to size a quest's difficulty against.
const LEVEL_STEP := 100
const MAX_LEVEL := 30

## --- Town services ---
## Priced here rather than next to the button that charges it, for the same reason the
## training costs are: what a night's rest is worth only means anything next to what a skill
## point and a breastplate cost. See ItemResource.gold_value for the third leg of that.
##
## Per hit point restored. At 2 a badly mauled hero costs about half a dungeon's takings to
## put back together, which is enough for "go in wounded instead" to be a real decision
## without ever being the only one available.
const REST_GOLD_PER_HP := 2

## What a hero can be trained in, in the order the training screen lists it.
##
## A curated list rather than every field of CombatantStats: `weight` is a property of a body
## rather than an achievement, the action costs are the rules of the game rather than a
## character's business, and `can_cast` is not something you buy in a market town.
const TRAINABLE := [
	{"field": "attack_skill", "label": "Melee", "kind": "skill",
		"note": "Hitting things with what is in your hand."},
	{"field": "parry_skill", "label": "Parry", "kind": "skill",
		"note": "Turning a blow aside. Needs something in hand to turn it with."},
	{"field": "ranged_skill", "label": "Archery", "kind": "skill",
		"note": "Shooting. Distance and a crowded target both count against you."},
	{"field": "throw_skill", "label": "Throwing", "kind": "skill",
		"note": "Lobbing a weapon. One quick action rather than a considered shot."},
	{"field": "shove_skill", "label": "Shoving", "kind": "skill",
		"note": "Putting somebody where you want them."},
	{"field": "trip_skill", "label": "Tripping", "kind": "skill",
		"note": "Putting somebody on the floor, where the archers cannot see them."},
	{"field": "stealth_skill", "label": "Stealth", "kind": "skill",
		"note": "Crossing a room unheard, and going unnoticed once you stop."},
	{"field": "perception_skill", "label": "Perception", "kind": "skill",
		"note": "Noticing what is trying not to be noticed."},
	{"field": "lockpick_skill", "label": "Lockpicking", "kind": "skill",
		"note": "Chests and doors that somebody did not want opened."},
	{"field": "strength", "label": "Strength", "kind": "attribute",
		"note": "How hard a blow lands."},
	{"field": "agility", "label": "Agility", "kind": "attribute",
		"note": "The whole of the dodge defence, and it is rolled every time you are attacked."},
	{"field": "stamina", "label": "Stamina", "kind": "attribute",
		"note": "Five hit points a point, and how much defending you can do before your guard drops."},
	{"field": "intelligence", "label": "Intelligence", "kind": "attribute",
		"note": "Nothing yet. Bought now, it will be waiting when something reads it."},
	{"field": "willpower", "label": "Willpower", "kind": "attribute",
		"note": "Five mana a point, for those who can cast at all."},
]


static func cap_for(kind: String) -> int:
	return ATTR_CAP if kind == "attribute" else SKILL_CAP


static func xp_cost(kind: String, current: int) -> int:
	## What the NEXT point costs. Priced off the value being bought rather than the one being
	## left behind, so the first point of a skill at 0 is never free.
	var step: int = ATTR_XP_STEP if kind == "attribute" else SKILL_XP_STEP
	return step * (current + 1)


static func gold_cost(kind: String, current: int) -> int:
	var step: int = ATTR_GOLD_STEP if kind == "attribute" else SKILL_GOLD_STEP
	return step * (current + 1)


static func level_for(xp_total: int) -> int:
	## The level a lifetime's xp adds up to. Thresholds are LEVEL_STEP * (1 + 2 + ... + n), so
	## each level costs LEVEL_STEP more than the one before.
	var level := 1
	var needed := LEVEL_STEP
	var spent := 0
	while level < MAX_LEVEL and xp_total >= spent + needed:
		spent += needed
		needed += LEVEL_STEP
		level += 1
	return level


static func xp_for_next_level(xp_total: int) -> int:
	## How much more lifetime xp the next level needs, or 0 at the cap. For a progress line on
	## a screen; nothing decides anything by it.
	var level := 1
	var needed := LEVEL_STEP
	var spent := 0
	while level < MAX_LEVEL and xp_total >= spent + needed:
		spent += needed
		needed += LEVEL_STEP
		level += 1
	if level >= MAX_LEVEL:
		return 0
	return spent + needed - xp_total


static func can_train(member, entry: Dictionary, gold: int) -> bool:
	var current: int = int(member.stats.get(entry["field"]))
	if current >= cap_for(entry["kind"]):
		return false
	if member.xp < xp_cost(entry["kind"], current):
		return false
	return gold >= gold_cost(entry["kind"], current)


static func refusal(member, entry: Dictionary, gold: int) -> String:
	## Why a training button is disabled, in words the player can act on. Empty when it is not.
	var current: int = int(member.stats.get(entry["field"]))
	if current >= cap_for(entry["kind"]):
		return "%s is as high as it goes." % entry["label"]
	var xp_needed: int = xp_cost(entry["kind"], current)
	var gold_needed: int = gold_cost(entry["kind"], current)
	if member.xp < xp_needed:
		return "%s needs %d xp — %s has %d." % [entry["label"], xp_needed,
			member.character_name, member.xp]
	if gold < gold_needed:
		return "%s needs %d gold — the party has %d." % [entry["label"], gold_needed, gold]
	return ""


static func train(member, entry: Dictionary) -> bool:
	## Spend the xp and raise the stat. Gold is the party's and is taken by the caller, which
	## is the only thing in this file that is not one character's business.
	##
	## Returns false and changes nothing if the character cannot afford it, so a screen that
	## has got its buttons wrong cannot hand out free points.
	var field: String = entry["field"]
	var current: int = int(member.stats.get(field))
	if current >= cap_for(entry["kind"]):
		return false
	var cost: int = xp_cost(entry["kind"], current)
	if member.xp < cost:
		return false
	member.xp -= cost
	member.stats.set(field, current + 1)
	return true


static func entry_for(field: String) -> Dictionary:
	for entry in TRAINABLE:
		if entry["field"] == field:
			return entry
	return {}
