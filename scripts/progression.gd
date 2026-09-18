extends RefCounted
class_name Progression
## The rules for getting better: what can be improved, how it is earned, and what it costs.
##
## TWO CURRENCIES, AND THEY ARE NOT INTERCHANGEABLE
##
##   SKILL XP is earned by a skill, for that skill, by USING it. Every skill keeps its own
##   pot. Swinging a sword teaches you swordsmanship and teaches you nothing about picking
##   locks, which is the whole point of skills levelling separately rather than a character
##   level handing out points to spend anywhere.
##
##   GENERAL XP is earned by the party for finishing quests and putting enemies down. It is
##   NOT a pool to pour into whatever needs it: at most ONE point may be assigned to any one
##   skill per quest. It is a trickle that lets a hero nudge along something they did not get
##   to use, not a way to buy a skill they have never practised.
##
## Attributes (strength, agility, stamina...) are raised by neither. They are waiting on a
## currency of their own, and until that exists they do not appear on the training screen —
## better an honest gap than a system nobody decided on.
##
## THE ROOF, AND WHY IT IS LOW
## An ordinary use earns one XP, and a skill may only earn QUEST_USE_CAP of those in a single
## quest. Without that, the best way to train would be to stand in a cleared room shoving a
## wall, and any system that makes tedium optimal has already lost. A CRITICAL — a natural 5
## or a natural 1 on the die — pays more and ignores the roof entirely, because the moments
## you actually learn from are the ones that went unusually well or unusually badly.

const CombatantStatsScript := preload("res://scripts/combatant_stats.gd")

## --- Earning skill XP ---
const USE_XP := 1
## A natural 5 or 1. Success and failure both teach, which is why one number covers them.
const CRIT_XP := 3
## Ordinary XP a single skill may earn in one quest. Crits are paid on top of this and do not
## count against it.
const QUEST_USE_CAP := 3
## General XP that may be assigned to any ONE skill per quest.
const GENERAL_PER_SKILL := 1

## --- Levelling a skill ---
## Skill XP to go from `current` to the next level. Cheap to start something, dear to master
## it: the first level of a skill costs 4 and the fifteenth costs 32.
const LEVEL_XP_BASE := 4
const LEVEL_XP_STEP := 2

## --- Training ---
## Gold buys skill XP directly. Deliberately a poor deal next to using the skill — a quest
## where a skill is used and crits once pays about as much as 200 gold of tuition — so that
## training is how you top up a skill you cannot practise, not how you skip the practising.
const TRAIN_XP := 1
const TRAIN_GOLD_BASE := 8
const TRAIN_GOLD_STEP := 3

## Where training stops. Rolls are skill + 1d5 against skill + 1d5, so the GAP between two
## numbers decides everything: at 15 against an unskilled 5 the die cannot save the loser.
const SKILL_CAP := 15

## What a level of general xp is worth as a badge. Nothing in combat reads it; it exists so a
## player can see progress in one number and so Phase 4 can size a quest against a party.
const LEVEL_STEP := 100
const MAX_LEVEL := 30

## --- Town services ---
## Per hit point restored, so a mauling costs about half a dungeon's takings to put right.
const REST_GOLD_PER_HP := 2

## --- Hiring ---
## What a sell-sword asks to join the party: a fee for turning up, plus a price on every skill
## level they already have. Priced off what they BRING rather than off the level on their
## badge, so a class whose experience does not currently buy many skill levels is cheap rather
## than quietly a bad deal — see CharacterClasses.growth_for.
##
## A raw recruit at 40 gold is about half a cleared tier-1 dungeon: cheap enough that a lone
## hero can afford company after one trip, which is the whole point of the camp existing. A
## seasoned one runs to two or three hundred, which is a decision rather than a purchase. It
## is a ONE-OFF: there is no upkeep, because a wage per quest would be a second economy to
## balance and the thing that actually costs money is keeping them alive and armed.
const HIRE_GOLD_BASE := 40
const HIRE_GOLD_PER_SKILL := 22

## The skills, in the order the training screen lists them. `field` is the CombatantStats
## property; nothing outside this table needs to know the names.
const SKILLS := [
	{"field": "attack_skill", "label": "Melee",
		"note": "Hitting things with what is in your hand. Earned by attacking."},
	{"field": "parry_skill", "label": "Parry",
		"note": "Turning a blow aside. Earned when somebody swings at you and you turn it."},
	{"field": "ranged_skill", "label": "Archery",
		"note": "Shooting. Earned by shooting, hit or miss."},
	{"field": "throw_skill", "label": "Throwing",
		"note": "Lobbing a weapon. One quick action rather than a considered shot."},
	{"field": "shove_skill", "label": "Shoving",
		"note": "Putting somebody where you want them."},
	{"field": "trip_skill", "label": "Tripping",
		"note": "Putting somebody on the floor, where the archers cannot see them."},
	{"field": "stealth_skill", "label": "Stealth",
		"note": "Crossing a room unheard. Earned on every sneaking step."},
	{"field": "perception_skill", "label": "Perception",
		"note": "Noticing what is trying not to be noticed. No use earns it yet — train it."},
	{"field": "lockpick_skill", "label": "Lockpicking",
		"note": "Chests and doors somebody did not want opened. Earned on every lock tried."},
]


static func skill_entry(field: String) -> Dictionary:
	for entry in SKILLS:
		if entry["field"] == field:
			return entry
	return {}


static func is_skill(field: String) -> bool:
	return not skill_entry(field).is_empty()


static func label_for(field: String) -> String:
	var entry := skill_entry(field)
	return String(entry["label"]) if not entry.is_empty() else field


# --- Earning ---------------------------------------------------------------

static func use_award(crit: bool) -> int:
	return CRIT_XP if crit else USE_XP


static func capped_use_award(ordinary_so_far: int, crit: bool) -> int:
	## What a use is actually worth, given how much this skill has already earned the ordinary
	## way this quest. A crit always pays; an ordinary use pays nothing once the roof is hit.
	if crit:
		return CRIT_XP
	return USE_XP if ordinary_so_far < QUEST_USE_CAP else 0


# --- Levelling -------------------------------------------------------------

static func xp_to_level(current: int) -> int:
	return LEVEL_XP_BASE + LEVEL_XP_STEP * current


static func can_level(member, field: String) -> bool:
	var current: int = int(member.stats.get(field))
	if current >= SKILL_CAP:
		return false
	return member.skill_xp_for(field) >= xp_to_level(current)


static func level_up(member, field: String) -> bool:
	## Spend the skill's own XP and raise it by one. Returns false and changes nothing when it
	## cannot be afforded, so a screen with its buttons wrong cannot hand out free levels.
	if not can_level(member, field):
		return false
	var current: int = int(member.stats.get(field))
	member.spend_skill_xp(field, xp_to_level(current))
	member.stats.set(field, current + 1)
	return true


static func level_refusal(member, field: String) -> String:
	var current: int = int(member.stats.get(field))
	if current >= SKILL_CAP:
		return "%s is as high as it goes." % label_for(field)
	var needed: int = xp_to_level(current)
	var have: int = member.skill_xp_for(field)
	if have < needed:
		return "%s needs %d skill xp to reach %d — %s has %d." % [
			label_for(field), needed, current + 1, member.character_name, have]
	return ""


# --- Training --------------------------------------------------------------

static func train_gold_cost(current: int) -> int:
	return TRAIN_GOLD_BASE + TRAIN_GOLD_STEP * current


static func can_train(member, field: String, gold: int) -> bool:
	var current: int = int(member.stats.get(field))
	if current >= SKILL_CAP:
		return false
	return gold >= train_gold_cost(current)


static func train_refusal(member, field: String, gold: int) -> String:
	var current: int = int(member.stats.get(field))
	if current >= SKILL_CAP:
		return "%s is as high as it goes." % label_for(field)
	var price: int = train_gold_cost(current)
	if gold < price:
		return "An hour of %s costs %d gold — the party has %d." % [
			label_for(field).to_lower(), price, gold]
	return ""


# --- The character's badge -------------------------------------------------

static func level_for(xp_total: int) -> int:
	var level := 1
	var needed := LEVEL_STEP
	var spent := 0
	while level < MAX_LEVEL and xp_total >= spent + needed:
		spent += needed
		needed += LEVEL_STEP
		level += 1
	return level


static func xp_total_for_level(level: int) -> int:
	## The lifetime experience a character of this level has behind them — the inverse of
	## level_for, and the only honest way to give somebody a level they did not earn here
	## (a hireling). Walks the same ladder rather than solving it, so the two cannot disagree.
	var at := 1
	var needed := LEVEL_STEP
	var spent := 0
	while at < mini(level, MAX_LEVEL):
		spent += needed
		needed += LEVEL_STEP
		at += 1
	return spent


static func hire_cost(skill_levels: int) -> int:
	## What somebody with this many skill levels behind them asks to come along.
	return HIRE_GOLD_BASE + HIRE_GOLD_PER_SKILL * maxi(0, skill_levels)


static func xp_for_next_level(xp_total: int) -> int:
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
