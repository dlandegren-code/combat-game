extends RefCounted
class_name Hireling
## The sell-swords waiting at the camp, and what it costs to take one along.
##
## Built the same way a quest is (see QuestDef): a camp is ONE seed, and who is sitting round
## its fire is derived from it. So the camp screen can be closed and reopened without the
## roster reshuffling, the seed is the only thing that has to be saved, and the same seed
## produces the same three people — which is what makes any of this testable.
##
## A candidate is a plain Dictionary until somebody pays for them. That is deliberate: making
## a CharacterData involves minting an id and building a bag of gear, and doing all of that
## four times over every time a screen redraws — for people who will never be hired — is work
## nobody asked for. `make_character` is the moment a candidate becomes a person.
##
## WHERE THEIR EXPERIENCE COMES FROM
## A hireling arrives already good at things, and there is no history behind that: they were
## not at the table when it was earned. So their levels are handed out down their class's
## growth list (CharacterClasses.growth_for) rather than distributed at random, which is what
## makes a level 4 archer reliably an ARCHER and not a lucky roll of five skills. Their xp
## pools are left EMPTY on purpose — a hireling brings what they have already learned, not a
## pot of unspent experience for their new employer to cash in.

const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const CharacterDataScript := preload("res://scripts/character_data.gd")
const ProgressionScript := preload("res://scripts/progression.gd")

## Skill levels a hireling has for each level above the first. Two, so a level 3 hire is four
## points better than a raw recruit — worth the money, and not worth more than the hero.
const SKILLS_PER_LEVEL := 2

## How far from the party's own level the camp's people range. Below, because a cheap body to
## stand in front of an archer is a real thing to want; above, because the point of hiring is
## sometimes to buy an ability the party has not got.
const LEVEL_SPREAD_LOW := -1
const LEVEL_SPREAD_HIGH := 2

## The most experienced sell-sword who will ever turn up looking for work. Somebody better
## than this is not standing round a fire in Riverwatch waiting to be asked.
const MAX_LEVEL := 6

## Names, drawn without regard to class so a name never gives away what somebody is. Two
## tables rather than one list of full names: twenty times twelve is two hundred and forty
## people, which is more than enough that the camp does not start repeating itself.
const GIVEN_NAMES := [
	"Bram", "Sera", "Oskar", "Wren", "Tobin", "Halla", "Ciaran", "Mira",
	"Dagen", "Elsa", "Rurik", "Nessa", "Joran", "Ilse", "Vance", "Thea",
	"Koll", "Brida", "Aldric", "Sixten",
]
const EPITHETS := [
	"Redhand", "Coldwater", "the Quiet", "Ashford", "Two-Coin", "the Younger",
	"Marsh", "Blackthorn", "the Patient", "Greave", "Stonebrook", "the Lame",
]


static func roster(camp_seed: int, party_level: int, count: int) -> Array:
	## Who is at the camp today. Cheapest first, so the list reads as a price board.
	##
	## Sized against the party the same way the quest board is: a camp offering nothing but
	## veterans to a fresh hero is a camp with nobody in it, and one offering nothing but raw
	## recruits to a veteran is the same camp failing in the other direction.
	var rng := RandomNumberGenerator.new()
	rng.seed = camp_seed

	var out: Array = []
	for i in range(maxi(1, count)):
		out.append(_candidate(rng, party_level))
	out.sort_custom(func(a, b): return a["price"] < b["price"])
	return out


static func _candidate(rng: RandomNumberGenerator, party_level: int) -> Dictionary:
	## One person. Every draw comes off the shared generator in a fixed order, so — exactly as
	## in QuestDef — inserting a roll in the middle of this would change every camp that has
	## ever been rolled. New draws go at the end.
	var class_id: String = CharacterClassesScript.ORDER[
		rng.randi() % CharacterClassesScript.ORDER.size()]
	var level := clampi(
		party_level + rng.randi_range(LEVEL_SPREAD_LOW, LEVEL_SPREAD_HIGH), 1, MAX_LEVEL)
	var name := "%s %s" % [
		GIVEN_NAMES[rng.randi() % GIVEN_NAMES.size()],
		EPITHETS[rng.randi() % EPITHETS.size()],
	]
	var bonus := (level - 1) * SKILLS_PER_LEVEL
	return {
		"class_id": class_id,
		"character_name": name,
		"level": level,
		"bonus": bonus,
		"price": ProgressionScript.hire_cost(bonus),
	}


static func make_character(candidate: Dictionary):
	## Turn a candidate into a real character, the moment somebody pays for them.
	##
	## Goes through CharacterClasses.make like every other new character — the starting gear,
	## the stat block and the loadout are the class's business, not this file's — and then adds
	## the one thing that makes a hireling different from a recruit: the years behind them.
	var data = CharacterClassesScript.make(
		String(candidate.get("class_id", "")), String(candidate.get("character_name", "")))
	_raise(data, int(candidate.get("bonus", 0)))
	# The badge, set to match what they can actually do. Derived from the level they were
	# advertised at rather than counted back out of their skills, so the number on the camp's
	# notice and the number on the party sheet are the same number.
	data.xp_total = ProgressionScript.xp_total_for_level(int(candidate.get("level", 1)))
	data.level = ProgressionScript.level_for(data.xp_total)
	# `xp` stays 0. See the header: they bring what they have learned, not a pot to spend.
	return data


static func _raise(data, points: int) -> void:
	## Spend `points` skill levels down the class's growth list, round and round, stopping at
	## the cap. Round-robin rather than all into the first skill: a soldier who is nothing but
	## melee is a worse hire than one who can also hold a shield up, and the growth list is
	## written best-first so the early points still land where they matter.
	var growth: Array = CharacterClassesScript.growth_for(data.class_id)
	if growth.is_empty() or points <= 0:
		return
	var spent := 0
	var guard := 0
	# Guarded rather than looped on `spent`, because every skill on the list can hit the cap
	# and then there is nowhere left to put a point — a plain while would spin forever.
	while spent < points and guard < points * growth.size() + growth.size():
		var field: String = growth[guard % growth.size()]
		guard += 1
		var current: int = int(data.stats.get(field))
		if current >= ProgressionScript.SKILL_CAP:
			continue
		data.stats.set(field, current + 1)
		spent += 1


static func describe(candidate: Dictionary) -> Array:
	## The two lines under a name on the camp screen: what they are, and what they are good at.
	var class_id := String(candidate.get("class_id", ""))
	var growth: Array = CharacterClassesScript.growth_for(class_id)
	var bonus := int(candidate.get("bonus", 0))
	var lines: Array = ["Level %d %s" % [
		int(candidate.get("level", 1)), CharacterClassesScript.display_name(class_id)]]
	if bonus <= 0:
		lines.append("Green as grass — everything still ahead of them.")
	else:
		# Named in the order the points actually went in, which is the order they are listed
		# in, so the line describes this person rather than the class in general.
		var shown: Array = []
		for i in range(mini(growth.size(), bonus)):
			shown.append(ProgressionScript.label_for(growth[i]).to_lower())
		lines.append("%d years of it, mostly %s." % [bonus, _and_list(shown)])
	return lines


static func _and_list(words: Array) -> String:
	if words.is_empty():
		return "keeping out of trouble"
	if words.size() == 1:
		return String(words[0])
	var head: Array = words.slice(0, words.size() - 1)
	return "%s and %s" % [", ".join(head), words[-1]]
