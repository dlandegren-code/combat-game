extends Node3D
## Dev tool: checks that a character survives everything that is supposed to preserve them —
## leaving the quest scene, coming back to it, being created from a class, and being written
## to a save file and read back.
##
## Run it by playing tools/test_meta_roundtrip.tscn and reading the console. It changes
## nothing on disk; the only state it touches is GameState, which dies with the run.
##
## WHAT IT ACTUALLY PROVES
## The milestone Phase 0 is built around is "state survives a scene change", and the part of
## that which cannot be seen by looking at the screen is DRIFT: a stat that creeps up by the
## armour bonus every time a hero travels, an item that loses its identity, an equipment slot
## that reshuffles. So the test does the trip four times over and demands that laps 2, 3 and 4
## come back identical — a bug that adds the shield's armour on every hydration passes a
## single trip and fails here.
##
## WHY A SCENE AND NOT A UNIT TEST
## Hydration is only meaningful against a real Combatant: the stats are derived by _ready, the
## gear bonuses are folded in by the inventory, and the sockets are built off the model's
## skeleton. Mocking that would test the mock.

const QuestScene := preload("res://scenes/quest_scene.tscn")
const CharacterDataScript := preload("res://scripts/character_data.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const CombatantStatsScript := preload("res://scripts/combatant_stats.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const QuestDefScript := preload("res://scripts/quest_def.gd")
const HirelingScript := preload("res://scripts/hireling.gd")

## A save path of this test's own. The real one belongs to whoever is playing, and a dev tool
## has no business writing to it.
const TEST_SAVE := "user://roundtrip_test_save.json"

## Dropped into the first hero's bag during the first lap, to check that loot picked up on a
## quest is still there on the next one.
const LOOT_ITEM := "res://resources/items/health_potion.tres"

## Wound dealt on the first lap, to check that hit points are carried and not quietly healed.
const WOUND := 7

const LAPS := 4

## The report is written here as well as printed, because the editor's console keeps prints to
## itself — a run's result has to be readable after the game has closed.
const REPORT_PATH := "res://.summer/local/roundtrip_report.txt"

var _failures: Array = []
var _checks := 0
var _log: Array = []


func _ready() -> void:
	await _run()
	_say("")
	if _failures.is_empty():
		_say("[RoundTrip] PASS — %d checks" % _checks)
	else:
		_say("[RoundTrip] FAIL — %d of %d checks failed" % [_failures.size(), _checks])
		for line in _failures:
			_say("  x " + line)
	_write_report()
	# A non-zero exit code so a future CI run can tell the difference without reading the log.
	get_tree().quit(0 if _failures.is_empty() else 1)


func _say(line: String) -> void:
	print(line)
	_log.append(line)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(REPORT_PATH.get_base_dir())
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RoundTrip: could not write %s" % REPORT_PATH)
		return
	f.store_string("\n".join(_log) + "\n")
	f.close()


func _run() -> void:
	_check(GameState.party.is_empty(), "GameState starts with no party")

	# --- Lap 0: the seeding run, which leaves the authored heroes in place ---------------
	var quest := await _enter_quest()
	var seeded: Array = quest._party_views
	# Every stat each authored hero HAD, before anything has been captured. Lap 1 compares the
	# rebuilt hero against this, which is the only check that catches a stat the capture path
	# does not know about: lockpick_skill and interact_cost were both silently reverting to
	# their defaults because CombatantStats had no field for them.
	var authored_stats := {}
	for node in seeded:
		authored_stats[node.character_name] = _stat_snapshot(node)
	_check(not GameState.party.is_empty(), "first quest seeds a party from the authored heroes")
	_check(GameState.party.size() == seeded.size(),
		"one character per authored hero (%d data / %d bodies)" % [GameState.party.size(), seeded.size()])
	var first_names := _names_of(seeded)
	_say("[RoundTrip] seeded: %s" % ", ".join(first_names))
	for i in range(GameState.party.size()):
		var data = GameState.party[i]
		_check(data.stats != null, "%s has a stat block of their own" % data.character_name)
		_check(data.class_id in CharacterDataScript.CLASS_BODIES,
			"%s's class was recognised from their model (%s)" % [data.character_name, data.class_id])
		_check(_bag_count(data) > 0, "%s's starting gear was captured" % data.character_name)
		_check(not data.equipped.is_empty(), "%s's loadout was captured" % data.character_name)
		for item in data.bag:
			if item != null:
				_check(item.template_path != "",
					"%s's %s knows which template it came from" % [data.character_name, item.item_name])

	# The quest itself: one hero takes a wound and finds a potion.
	var hero: Node = seeded[0]
	var hurt_to: int = hero.hp - WOUND
	hero.hp = hurt_to
	var loot = (load(LOOT_ITEM) as ItemResource).make_instance()
	hero.inventory.add_item(loot)
	await _leave_quest(quest)

	_check(GameState.party[0].hp == hurt_to, "the wound was written back to the character")
	_check(_has_item(GameState.party[0], loot.item_name), "the potion was written back to the character")

	# --- Laps 1..n: hydration, which must come back the same every time -----------------
	var baseline := {}
	for lap in range(1, LAPS + 1):
		quest = await _enter_quest()
		var views: Array = quest._party_views
		_check(views.size() == GameState.party.size(),
			"lap %d spawned one body per character" % lap)
		_check(_authored_count(quest) == views.size(),
			"lap %d retired the authored heroes and left only the party" % lap)

		var snapshot := {}
		for i in range(views.size()):
			var view: Node = views[i]
			var data = GameState.party[i]
			if not is_instance_valid(view):
				_check(false, "lap %d: body %d went missing" % [lap, i])
				continue
			_check(view.character_name == data.character_name,
				"lap %d: %s came back under their own name" % [lap, data.character_name])
			_check(view.is_player_controlled, "lap %d: %s is player-controlled" % [lap, data.character_name])
			_check(view.get_node_or_null("CharacterModel") != null,
				"lap %d: %s has a body" % [lap, data.character_name])
			_check(_equipped_names(view) == _equipped_names_of_data(data),
				"lap %d: %s is holding exactly what they left town with (%s)"
					% [lap, data.character_name, ", ".join(_equipped_names(view))])
			if authored_stats.has(data.character_name):
				var was: Dictionary = authored_stats[data.character_name]
				var now: Dictionary = _stat_snapshot(view)
				for field in was:
					_check(now[field] == was[field],
						"lap %d: %s kept their %s (%s, not %s)"
							% [lap, data.character_name, field, was[field], now[field]])
			_check(_quiver_matches(view, data),
				"lap %d: %s's body is dressed as their class (quiver)" % [lap, data.character_name])
			snapshot[data.character_name] = {
				"hp": view.hp,
				"max_hp": view.max_hp,
				"armor": view.armor,
				"resistance": view.physical_resistance,
				"block_armor": data.stats.armor,
				"items": _bag_count(data),
			}

		_check(views[0].hp == hurt_to, "lap %d: the wound is still there" % lap)
		_check(_has_item(GameState.party[0], loot.item_name), "lap %d: the potion is still there" % lap)

		if baseline.is_empty():
			baseline = snapshot
			_say("[RoundTrip] baseline: %s" % baseline)
		else:
			for who in baseline:
				_check(snapshot.get(who) == baseline[who],
					"lap %d: %s came back unchanged (was %s, now %s)"
						% [lap, who, baseline[who], snapshot.get(who)])

		await _leave_quest(quest)

	# --- The save format, which Phase 2 will write to disk -------------------------------
	var before := GameState.to_dict()
	var text := JSON.stringify(before)
	var parsed = JSON.parse_string(text)
	_check(parsed != null, "a party survives being written as JSON")
	if parsed != null:
		var names_before := _data_names(GameState.party)
		var xp_before: int = GameState.party[0].xp
		var gold_before: int = GameState.gold
		var gear_before := _equipped_names_of_data(GameState.party[0])
		GameState.from_dict(parsed)
		_check(_data_names(GameState.party) == names_before, "names survive the save format")
		_check(GameState.party[0].xp == xp_before, "xp survives the save format")
		_check(GameState.gold == gold_before, "gold survives the save format")
		_check(_equipped_names_of_data(GameState.party[0]) == gear_before,
			"the loadout survives the save format (%s)" % ", ".join(gear_before))
		_check(GameState.party[0].hp == hurt_to, "wounds survive the save format")

	# --- And the other way a character comes into existence ------------------------------
	await _run_creation_checks()

	# --- Training and the market ---------------------------------------------------------
	await _run_economy_checks()

	# --- Quests as described things, and the board they are pinned to --------------------
	await _run_quest_checks()

	# --- Hiring, and taking the people hired underground ---------------------------------
	await _run_hire_checks()

	# --- The screens, buttons and all ----------------------------------------------------
	await _run_screen_checks()

	# --- The save file -------------------------------------------------------------------
	_run_save_checks()

	# Last of all, because several of the screens above save as they go: a test run must leave
	# the player's save exactly as it found it.
	_check(FileAccess.file_exists(SaveGameScript.PATH) == _real_save_existed,
		"the run left the player's save file as it found it")


# --- Created characters, standing in for the creation screen ----------------

func _run_creation_checks() -> void:
	## Everything the creation screen does, minus the buttons: make a character of each class,
	## then take one of them on a quest and check the body that comes out the other end is the
	## character that was made.
	for class_id in CharacterClassesScript.ORDER:
		var made = CharacterClassesScript.make(class_id, "")
		_check(made.class_id == class_id, "a %s can be created" % class_id)
		_check(made.stats != null, "a new %s has a stat block" % class_id)
		_check(_bag_count(made) > 0, "a new %s starts with gear" % class_id)
		_check(not made.equipped.is_empty(), "a new %s starts wearing some of it" % class_id)
		_check(made.character_name != "", "a nameless %s is given one" % class_id)
		_check(not CharacterClassesScript.summary_lines(class_id).is_empty(),
			"a %s can be described on the creation screen" % class_id)

	# The archer, because it is the class with the most to lose in a round trip: a two-handed
	# bow across both hand slots, a quiver that lives on the model rather than in a slot, and
	# the only lockpicking in the game.
	GameState.clear()
	var archer = CharacterClassesScript.make("archer", "Testwood")
	GameState.add_member(archer)
	var quest := await _enter_quest()
	var views: Array = quest._party_views
	_check(views.size() == 1, "a one-hero party takes one body into the quest")
	_check(_authored_count(quest) == 1, "the authored test party is retired for a real party")
	if views.size() == 1:
		var view: Node = views[0]
		_check(view.character_name == "Testwood", "the created name reached the dungeon")
		_check(view.lockpick_skill == 3, "the created archer can still pick locks (%d)"
			% view.lockpick_skill)
		_check(view.max_ammo == 12, "the created archer brought a full quiver's worth (%d)"
			% view.max_ammo)
		_check(view.hp == view.max_hp and view.max_hp == 20,
			"a new character arrives at full health (%d/%d)" % [view.hp, view.max_hp])
		_check(_equipped_names(view) == _equipped_names_of_data(archer),
			"the created loadout is what the inventory built (%s)"
				% ", ".join(_equipped_names(view)))
		_check(view.inventory.right_hand != null
				and view.inventory.right_hand == view.inventory.left_hand,
			"the bow is held in both hands")
		_check(_quiver_matches(view, archer), "the created archer wears their quiver")
		var model_path: String = view.get_node("CharacterModel").scene_file_path
		_check(model_path == archer.model_scene_path(),
			"the created archer wears the archer's body")
	await _leave_quest(quest)
	_check(GameState.party[0].character_name == "Testwood",
		"the created character survives the quest")
	_check(GameState.party[0].stats.lockpick_skill == 3,
		"the created archer's lockpicking survives capture (%d)"
			% GameState.party[0].stats.lockpick_skill)


# --- The screens themselves -------------------------------------------------

func _run_quest_checks() -> void:
	## A quest is a seed and a tier, and everything else about it is derived. That claim is
	## what the whole of Phase 4 is built on — the board stores one integer, a save stores two,
	## and the generator will be handed the same two — so it is checked directly rather than
	## inferred from a quest looking plausible on a screen.

	# --- The same two numbers give the same quest, every time -----------------------------
	var a = QuestDefScript.generate(918_273, 3)
	var b = QuestDefScript.generate(918_273, 3)
	_check(a.title == b.title, "the same seed names the same quest (%s)" % a.title)
	_check(a.theme == b.theme, "and puts it in the same kind of place")
	_check(a.reward_gold == b.reward_gold and a.reward_xp == b.reward_xp,
		"and pays the same for it")
	_check(a.enemy_budget == b.enemy_budget and a.loot_budget == b.loot_budget,
		"and fills it with the same amount of trouble")

	# --- Different seeds give different quests --------------------------------------------
	# A sweep rather than one comparison: two quests CAN legitimately come out with the same
	# name, and a single unlucky pair would fail a test that was right about the code.
	var titles := {}
	for i in range(24):
		titles[QuestDefScript.generate(5_000 + i * 7, 2).title] = true
	_check(titles.size() > 12, "24 seeds give a spread of quests (%d distinct names)"
		% titles.size())

	# --- A tier means something ------------------------------------------------------------
	var previous_gold := 0
	var previous_xp := 0
	var previous_enemies := 0
	var ladder_rises := true
	for tier in range(1, QuestDefScript.MAX_TIER + 1):
		var rung = QuestDefScript.generate(4_242 + tier, tier)
		_check(rung.tier == tier, "tier %d comes back as tier %d" % [tier, rung.tier])
		if rung.reward_gold <= previous_gold or rung.reward_xp <= previous_xp \
				or rung.enemy_budget <= previous_enemies:
			ladder_rises = false
		previous_gold = rung.reward_gold
		previous_xp = rung.reward_xp
		previous_enemies = rung.enemy_budget
	_check(ladder_rises,
		"every rung of the ladder pays more and is worse than the one below it")
	# The variance must never be wide enough to reorder the tiers, which is the one thing that
	# would make the labels on the board lie. Checked across seeds, not just the ladder above.
	var overlap := false
	for i in range(40):
		if QuestDefScript.generate(700 + i, 1).reward_gold \
				>= QuestDefScript.generate(9_000 + i, 2).reward_gold:
			overlap = true
	_check(not overlap, "and no lucky Simple job out-pays an unlucky Steady one")

	_check(QuestDefScript.generate(1, 99).tier == QuestDefScript.MAX_TIER,
		"a tier past the end of the ladder is clamped to it")
	_check(QuestDefScript.generate(1, -3).tier == 1, "and one below the bottom to the bottom")

	# --- A quest survives being written down ----------------------------------------------
	var written = QuestDefScript.from_dict(a.to_dict())
	_check(written != null, "a quest can be written down and read back")
	_check(written.title == a.title and written.tier == a.tier
			and written.reward_gold == a.reward_gold,
		"and comes back as the same quest")
	_check(QuestDefScript.from_dict({}) == null, "and an empty record is no quest at all")

	# --- The board -------------------------------------------------------------------------
	var board: Array = QuestDefScript.offers(555, 3, 4)
	_check(board.size() == 4, "the board puts up as many jobs as it is asked for")
	var sorted := true
	var in_range := true
	for i in range(board.size()):
		if board[i].tier < 1 or board[i].tier > QuestDefScript.MAX_TIER:
			in_range = false
		if i > 0 and board[i].tier < board[i - 1].tier:
			sorted = false
	_check(sorted, "hardest last")
	_check(in_range, "and nothing off the ladder")
	var again: Array = QuestDefScript.offers(555, 3, 4)
	var identical := true
	for i in range(board.size()):
		if board[i].title != again[i].title or board[i].quest_seed != again[i].quest_seed:
			identical = false
	_check(identical, "the same board seed puts up the same board")
	var other: Array = QuestDefScript.offers(556, 3, 4)
	_check(other[0].quest_seed != board[0].quest_seed, "and a different seed a different one")

	# A board is sized to the party. A fresh hero must never be shown nothing but work that
	# would kill them, which is the failure this spread exists to prevent.
	var beginners_luck := false
	for i in range(20):
		for offer in QuestDefScript.offers(3_000 + i, 1, 4):
			if offer.tier == 1:
				beginners_luck = true
				break
	_check(beginners_luck, "a level 1 party is offered work a level 1 party can do")

	# --- The board as GameState keeps it ---------------------------------------------------
	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("soldier", "Contractor"))
	_check(GameState.board_seed == 0, "a new game has no board yet")
	var pinned: Array = GameState.quest_board()
	_check(GameState.board_seed != 0, "reading the board rolls one")
	_check(pinned.size() == GameState.BOARD_OFFERS, "with the town's usual number of jobs")
	_check(GameState.quest_board()[0].title == pinned[0].title,
		"and reading it again shows the same jobs")
	var was := GameState.board_seed
	GameState.reroll_board()
	_check(GameState.board_seed != was and GameState.board_seed != 0,
		"rerolling puts up a different board")

	# --- Taking a job, and being paid for it -----------------------------------------------
	# Through the real settlement path (QuestScene.settle), because the question is not whether
	# the arithmetic is right but whether the contract reaches it.
	var job = QuestDefScript.generate(31_337, 3)
	GameState.accept_quest(job)
	_check(GameState.current_quest == job, "a job taken off the board is the job the party is on")
	var gold_before: int = GameState.gold
	var xp_before: int = GameState.party[0].xp
	var board_before: int = GameState.board_seed

	var quest := await _enter_quest()
	var settlement: Dictionary = await _leave_quest(quest, "victory")
	_check(GameState.gold == gold_before + job.reward_gold,
		"clearing it pays the contract in gold (%d -> %d, contract %d)"
			% [gold_before, GameState.gold, job.reward_gold])
	_check(GameState.party[0].xp == xp_before + job.reward_xp, "and in experience")
	_check(settlement.get("quest_paid", false), "and the results screen is told it was settled")
	_check(String(settlement.get("quest", "")) == job.title, "and which job it was")
	_check(GameState.current_quest == null, "the party is not on a quest any more")
	_check(GameState.board_seed != board_before, "and the board has gone up fresh")

	# --- Walking out of a job you took -----------------------------------------------------
	var abandoned = QuestDefScript.generate(4_711, 2)
	GameState.accept_quest(abandoned)
	gold_before = GameState.gold
	xp_before = GameState.party[0].xp
	quest = await _enter_quest()
	settlement = await _leave_quest(quest, "retreat")
	_check(GameState.gold == gold_before, "walking out of a contract pays nothing")
	_check(GameState.party[0].xp == xp_before, "and teaches nothing")
	_check(not settlement.get("quest_paid", true), "and the results screen says so")
	_check(String(settlement.get("quest", "")) == abandoned.title,
		"while still naming the job that was dropped")

	# --- A trip through the gate on the party's own account --------------------------------
	_check(GameState.current_quest == null, "no contract after the last one was dropped")
	gold_before = GameState.gold
	quest = await _enter_quest()
	settlement = await _leave_quest(quest, "victory")
	_check(String(settlement.get("quest", "")) == "",
		"an uncontracted trip settles with no job attached")
	_check(GameState.gold == gold_before, "and pays only for what was killed")


func _run_hire_checks() -> void:
	## The mercenary camp. A camp is a seed and the people at it are derived from it, exactly as
	## a quest board is — so the same properties are worth the same checks — but hiring differs
	## from taking a contract in one way that matters: it produces a PERSON, and that person has
	## to survive everything a person has to survive. So this ends by taking one underground.

	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("soldier", "Chief"))
	GameState.gold = 2_000

	# --- Who is at the fire ---------------------------------------------------------------
	_check(GameState.camp_seed == 0, "a new game has no camp yet")
	var roster: Array = GameState.hire_roster()
	_check(GameState.camp_seed != 0, "walking up to the fire rolls one")
	_check(roster.size() == GameState.CAMP_HIRELINGS,
		"with the usual number of sell-swords at it (%d)" % roster.size())
	var second: Array = GameState.hire_roster()
	_check(second.size() == roster.size()
			and String(second[0]["character_name"]) == String(roster[0]["character_name"]),
		"and looking again shows the same people")

	var cheapest_first := true
	var named := true
	var classes_known := true
	for i in range(roster.size()):
		if i > 0 and int(roster[i]["price"]) < int(roster[i - 1]["price"]):
			cheapest_first = false
		if String(roster[i]["character_name"]).strip_edges() == "":
			named = false
		if not CharacterClassesScript.CLASSES.has(String(roster[i]["class_id"])):
			classes_known = false
	_check(cheapest_first, "cheapest first, so the list reads as a price board")
	_check(named, "everybody has a name")
	_check(classes_known, "and a class the game knows how to build")

	# The same seed gives the same people, and a different one different people. The property
	# the whole seed-derived approach rests on, checked here as it is for quests.
	var a: Array = HirelingScript.roster(24_601, 2, 3)
	var b: Array = HirelingScript.roster(24_601, 2, 3)
	var same := true
	for i in range(a.size()):
		if String(a[i]["character_name"]) != String(b[i]["character_name"]) \
				or int(a[i]["price"]) != int(b[i]["price"]):
			same = false
	_check(same, "the same camp seed sits the same people round the fire")
	var faces := {}
	for i in range(30):
		for who in HirelingScript.roster(80_000 + i * 13, 2, 3):
			faces[String(who["character_name"])] = true
	_check(faces.size() > 40, "and 30 camps give a spread of people (%d distinct names)"
		% faces.size())

	# Experience costs money, and a raw recruit is affordable after one dungeon. The camp
	# existing at all is only useful if a lone hero can afford the first one.
	_check(ProgressionScript.hire_cost(0) == ProgressionScript.HIRE_GOLD_BASE,
		"a green recruit asks the base fee (%d gold)" % ProgressionScript.hire_cost(0))
	_check(ProgressionScript.hire_cost(6) > ProgressionScript.hire_cost(2),
		"and every year behind them puts the price up")

	# --- What a hireling actually is -------------------------------------------------------
	var veteran = HirelingScript.make_character(
		{"class_id": "archer", "character_name": "Test Hire", "level": 4, "bonus": 6})
	_check(veteran.character_name == "Test Hire", "a hireling is made with the name advertised")
	_check(veteran.level == 4, "and the level advertised (%d)" % veteran.level)
	_check(veteran.stats != null and veteran.id != "", "with a stat block and an id of their own")
	_check(not veteran.bag.is_empty(), "and their class's kit in their pack")
	_check(veteran.xp == 0, "they bring no unspent experience for their employer to cash in")
	var raw = CharacterClassesScript.make("archer", "Raw")
	var grew := false
	for field in CharacterClassesScript.growth_for("archer"):
		if int(veteran.stats.get(field)) > int(raw.stats.get(field)):
			grew = true
	_check(grew, "but they ARE better at their trade than a fresh recruit")
	_check(int(veteran.stats.get("ranged_skill")) > int(raw.stats.get("ranged_skill")),
		"starting with the thing their class is best at (archery %d vs %d)"
			% [int(veteran.stats.get("ranged_skill")), int(raw.stats.get("ranged_skill"))])
	# The cap has to hold even when somebody is handed more levels than there are skills to
	# put them in, which is the one input that could spin the round-robin forever.
	var maxed = HirelingScript.make_character(
		{"class_id": "soldier", "character_name": "Maxed", "level": 6, "bonus": 400})
	var capped := true
	for field in CharacterClassesScript.growth_for("soldier"):
		if int(maxed.stats.get(field)) > ProgressionScript.SKILL_CAP:
			capped = false
	_check(capped, "and no amount of experience takes a skill past the cap")

	# --- Paying for one --------------------------------------------------------------------
	roster = GameState.hire_roster()
	var candidate: Dictionary = roster[0]
	var price := int(candidate["price"])
	var purse: int = GameState.gold
	var camp_before: int = GameState.camp_seed
	_check(GameState.hire(candidate), "a sell-sword can be hired")
	_check(GameState.gold == purse - price, "which costs what they asked (%d gold)" % price)
	_check(GameState.party.size() == 2, "and puts them in the party")
	_check(GameState.party[1].character_name == String(candidate["character_name"]),
		"the one who was asked, by name")
	_check(GameState.camp_seed != camp_before,
		"and the camp rolls again, so the same person cannot be hired twice")

	# A purse that cannot cover it buys nothing at all — neither the body nor half the gold.
	GameState.gold = 0
	var dear: Dictionary = GameState.hire_roster()[0]
	_check(not GameState.hire(dear), "somebody who cannot be paid does not come along")
	_check(GameState.party.size() == 2, "and the party is unchanged")
	_check(GameState.gold == 0, "and so is the purse")
	GameState.gold = 2_000

	# --- The cap ---------------------------------------------------------------------------
	while not GameState.party_is_full():
		_check(GameState.hire(GameState.hire_roster()[0]), "another one signs on")
	_check(GameState.party.size() == GameState.PARTY_MAX,
		"the company fills up at %d" % GameState.PARTY_MAX)
	purse = GameState.gold
	_check(not GameState.hire(GameState.hire_roster()[0]), "and a fifth is turned away")
	_check(GameState.gold == purse, "without being paid for")

	# --- Parting company -------------------------------------------------------------------
	var leaving: String = GameState.party[1].character_name
	_check(GameState.remove_member(1), "a hireling can be let go")
	_check(GameState.party.size() == GameState.PARTY_MAX - 1, "which shortens the company")
	_check(GameState.party[0].character_name == "Chief", "the hero stays at the head of it")
	var still_here := false
	for member in GameState.party:
		if member.character_name == leaving:
			still_here = true
	_check(not still_here, "and the one let go is gone")
	_check(not GameState.remove_member(0), "the hero cannot be dismissed")
	_check(not GameState.remove_member(99), "nor can somebody who is not in the party")
	_check(GameState.party.size() == GameState.PARTY_MAX - 1, "and neither attempt changed it")

	# --- Underground with the hired help ---------------------------------------------------
	# The point of the whole feature, and the part that was never exercised before: a party
	# bigger than the authored scenario's three hand-placed heroes.
	_check(GameState.party.size() > 2, "the party is now bigger than a lone hero")
	var expected := _data_names(GameState.party)
	var quest := await _enter_quest()
	var views: Array = quest._party_views
	_check(views.size() == GameState.party.size(),
		"every one of them gets a body in the quest (%d of %d)"
			% [views.size(), GameState.party.size()])
	_check(_names_of(views) == expected, "and they are the right people, in party order")

	# Nobody inside a wall and nobody standing on anybody. The authored scene has three marks
	# and the party is bigger than that, so at least one of these squares was SEARCHED for —
	# which is the thing that would silently go wrong.
	var room := quest.get_node_or_null("DungeonRoom")
	var on_floor := true
	var apart := true
	for i in range(views.size()):
		var here: Vector3 = views[i].position
		if room != null and room.has_method("is_floor_at") \
				and not room.is_floor_at(here.x, here.z):
			on_floor = false
		for j in range(i + 1, views.size()):
			if here.distance_to(views[j].position) < 1.0:
				apart = false
	_check(on_floor, "every one of them is standing on dungeon floor")
	_check(apart, "and no two of them on the same square")
	# They are real combatants, not decoration: the turn order has to know about them.
	var in_order := 0
	for c in get_tree().get_nodes_in_group("combatants"):
		if is_instance_valid(c) and c.get("is_player_controlled") == true:
			in_order += 1
	_check(in_order == views.size(),
		"and all %d are dealt into the fight as player-controlled" % views.size())

	var hire_hp: int = views[-1].hp
	views[-1].hp = maxi(1, hire_hp - 3)
	await _leave_quest(quest, "retreat")
	_check(GameState.party.size() == expected.size(), "everybody comes back out")
	_check(_data_names(GameState.party) == expected, "as the same people")
	_check(GameState.party[-1].hp == maxi(1, hire_hp - 3),
		"and a hireling's wounds are written back like anybody else's")


func _run_screen_checks() -> void:
	## Mount each town screen with a real party in memory and press the buttons that DO
	## something, rather than the ones that change scene.
	##
	## This is the only part of the game a mouse would normally be needed for, and the glue
	## between a button and the rules is exactly where a typo lives: a format string with the
	## wrong number of arguments, a handler that spends gold twice, a list that assumes one
	## party member. Pressing the real buttons is the only way to catch those.
	##
	## The screens save as they go, and they save to the PLAYER's file, so that file is put
	## back exactly as it was afterwards — see _guard_real_save.
	_guard_real_save()

	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("soldier", "Screens"))
	GameState.add_member(CharacterClassesScript.make("archer", "Second"))
	GameState.gold = 500
	GameState.award_xp(400)

	# --- Training hall ---
	var training: Node = await _mount("res://scenes/training.tscn")
	var before_skill: int = int(GameState.party[0].stats.attack_skill)
	var before_xp: int = GameState.party[0].xp
	var before_gold: int = GameState.gold
	_check(_press(training, "Train"), "the training hall sells an hour of practice")
	_check(GameState.gold < before_gold, "which costs gold")
	_check(GameState.party[0].skill_xp_for("attack_skill") > 0, "and is worth skill xp")
	_check(int(GameState.party[0].stats.attack_skill) == before_skill,
		"but does not raise the skill on its own")
	_check(_press(training, "Assign"), "general xp can be pushed into a skill")
	_check(GameState.party[0].xp < before_xp, "which spends it")
	# The second party member is reachable, which is what the picker is for.
	_check(_press(training, "Second"), "the training hall can switch to the other hero")
	_check(_press(training, "Assign"), "and spend on them instead")
	_check(GameState.party[1].xp < 400, "which came out of THEIR general xp")
	_free(training)

	# --- Market ---
	var shop: Node = await _mount("res://scenes/shop.tscn")
	before_gold = GameState.gold
	var before_bag: int = _bag_count(GameState.party[0])
	_check(_press(shop, "Health Potion"), "the market sells potions")
	_check(GameState.gold < before_gold, "buying one costs gold")
	_check(_bag_count(GameState.party[0]) == before_bag + 1, "and puts it in the pack")
	before_gold = GameState.gold
	_check(_press(shop, "Sell Health Potion"), "and will buy it back")
	_check(GameState.gold > before_gold, "for money")
	_check(_bag_count(GameState.party[0]) == before_bag, "out of the pack")
	_free(shop)

	# --- The notice board ---
	# Mounted and read, NOT pressed. Every button on this screen changes scene, and a scene
	# change here would free the test along with the board — so what it can honestly check is
	# that the board draws the jobs GameState says are pinned up, one takeable button each.
	# The taking itself is covered against the real settlement path in _run_quest_checks.
	GameState.reroll_board()
	var offers: Array = GameState.quest_board()
	var board_screen: Node = await _mount("res://scenes/quest_board.tscn")
	_check(_has_buttons(board_screen), "the notice board draws")
	var all_pinned := true
	for offer in offers:
		if _find_button(board_screen, "Take: %s" % offer.title) == null:
			all_pinned = false
	_check(all_pinned, "with a button for every one of the %d jobs going" % offers.size())
	_check(_find_button(board_screen, "Back to town") != null, "and a way to walk away")
	_free(board_screen)

	# --- The mercenary camp ---
	# Pressed for real, unlike the notice board: hiring and dismissing both stay on this screen,
	# so the buttons that matter here can be walked the way the training hall's are.
	GameState.camp_seed = 0
	var camp_offer: Dictionary = GameState.hire_roster()[0]
	GameState.gold = 2_000
	var company: int = GameState.party.size()
	var camp: Node = await _mount("res://scenes/hire_camp.tscn")
	before_gold = GameState.gold
	_check(_press(camp, "Hire %s" % camp_offer["character_name"]),
		"the camp signs somebody on")
	_check(GameState.party.size() == company + 1, "who joins the company")
	_check(GameState.gold < before_gold, "for money")
	# Parting company asks twice, in place, so the first press must NOT remove anybody.
	var newcomer: String = GameState.party[-1].character_name
	_check(_press(camp, "Part ways with %s" % newcomer), "parting company asks first")
	_check(GameState.party.size() == company + 1, "and changes nothing until it is confirmed")
	_check(_press(camp, "Really part with %s" % newcomer), "confirming it goes through")
	_check(GameState.party.size() == company, "and the company is back to what it was")
	_free(camp)

	# --- Town, including the bed ---
	GameState.party[0].hp = 4
	var town: Node = await _mount("res://scenes/town.tscn")
	before_gold = GameState.gold
	# The bed is the healer's house now, not a button in a list — the town is a place.
	_check(_press(town, "Healer"), "the healer's house takes a wounded party in")
	_check(GameState.gold < before_gold, "which is not free")
	_check(GameState.party[0].hp == CharacterDataScript.VITALS_FULL, "and mends them")
	_free(town)

	# --- The screens that only report ---
	GameState.last_result = {"outcome": "victory", "kills": 3, "xp": 60, "gold": 45,
		"loot": ["Health Potion"], "fallen": []}
	var results: Node = await _mount("res://scenes/results_screen.tscn")
	_check(_has_buttons(results), "the results screen draws")
	_check(GameState.last_result.is_empty(), "and consumes the result so it is not shown twice")
	_free(results)

	var creation: Node = await _mount("res://scenes/character_creation.tscn")
	_check(_has_buttons(creation), "character creation draws")
	_check(_press(creation, "Wizard"), "and a class can be chosen")
	# Choosing a class must not COMMIT one. An earlier run of this test left a brand-new
	# wizard in the save file, which can only have come from the Begin handler running off a
	# class button — so the party in memory is checked rather than assumed. If this ever
	# fails, that press is committing a character and changing scene behind the test's back.
	_check(GameState.party.size() == 2 and GameState.party[0].character_name == "Screens",
		"and choosing it did not replace the party (%d members, first is %s)"
			% [GameState.party.size(), GameState.party[0].character_name])
	_free(creation)

	var title: Node = await _mount("res://scenes/title_screen.tscn")
	_check(_has_buttons(title), "the title screen draws")
	_free(title)

	_restore_real_save()


func _mount(path: String) -> Node:
	var screen := (load(path) as PackedScene).instantiate()
	# A size for the flat screens, which anchor to their parent: a zero-sized parent gives a
	# zero-sized screen with nothing laid out in it. The town is a Node3D and has no size — it
	# builds its own camera and puts its buttons in a CanvasLayer.
	var as_control := screen as Control
	if as_control != null:
		as_control.size = Vector2(1280, 720)
	add_child(screen)
	await get_tree().process_frame
	return screen


func _free(screen: Node) -> void:
	remove_child(screen)
	screen.queue_free()


func _press(root: Node, fragment: String) -> bool:
	## Press the first enabled button whose label contains `fragment`. Returns false if there
	## is no such button, which is itself worth failing on — a screen that has lost its Train
	## button is broken even though nothing crashed.
	var button := _find_button(root, fragment)
	if button == null:
		return false
	# Logged, because a button-walking test that matches the WRONG button passes just as
	# happily as one that matches the right one. The report should say what was clicked.
	_say("[press] %s" % button.text)
	button.pressed.emit()
	return true


func _find_button(node: Node, fragment: String) -> Button:
	if node is Button and not node.disabled and String(node.text).contains(fragment):
		return node
	for child in node.get_children():
		var found := _find_button(child, fragment)
		if found != null:
			return found
	return null


func _has_buttons(node: Node) -> bool:
	if node is Button:
		return true
	for child in node.get_children():
		if _has_buttons(child):
			return true
	return false


# --- The player's save file, which a test must leave exactly as it found ----

var _real_save_backup := PackedByteArray()
var _real_save_existed := false


func _guard_real_save() -> void:
	_real_save_existed = FileAccess.file_exists(SaveGameScript.PATH)
	if _real_save_existed:
		_real_save_backup = FileAccess.get_file_as_bytes(SaveGameScript.PATH)


func _restore_real_save() -> void:
	if _real_save_existed:
		var f := FileAccess.open(SaveGameScript.PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_real_save_backup)
			f.close()
		_check(FileAccess.file_exists(SaveGameScript.PATH), "the player's save was put back")
	else:
		SaveGameScript.delete()
		_check(not FileAccess.file_exists(SaveGameScript.PATH),
			"no save was left behind where there was none")


# --- Training and the market, standing in for those screens -----------------

func _run_economy_checks() -> void:
	## The two experience economies, and the rules that keep them apart.
	##
	## The one worth the most care is the ROOF: a skill earns only so much from ordinary use in
	## one quest. A game where the best way to train is to stand in a cleared room shoving a
	## wall is a bad game, and nothing else in the code would notice that it had become one.
	GameState.clear()
	var hero = CharacterClassesScript.make("soldier", "Coin")
	GameState.add_member(hero)

	# --- A skill levels on its OWN experience ---
	var melee := "attack_skill"
	var start_level: int = int(hero.stats.get(melee))
	_check(hero.skill_xp_for(melee) == 0, "a new character has banked no skill xp")
	_check(not ProgressionScript.can_level(hero, melee), "and so cannot level anything")
	_check(ProgressionScript.level_refusal(hero, melee).contains("skill xp"),
		"the refusal says what is missing")

	var cost: int = ProgressionScript.xp_to_level(start_level)
	hero.add_skill_xp(melee, cost)
	_check(ProgressionScript.can_level(hero, melee), "with the xp banked, it can")
	_check(ProgressionScript.level_up(hero, melee), "and the level is bought")
	_check(int(hero.stats.get(melee)) == start_level + 1,
		"the skill went up by one (%d)" % int(hero.stats.get(melee)))
	_check(hero.skill_xp_for(melee) == 0, "and the xp was spent")
	_check(hero.xp == 0, "levelling a skill costs no general xp")

	# Each skill keeps its own pot, which is the whole point of levelling them separately.
	hero.add_skill_xp("ranged_skill", 99)
	_check(hero.skill_xp_for(melee) == 0, "xp banked for archery is not xp for melee")
	_check(not ProgressionScript.can_level(hero, melee), "and cannot level melee")
	_check(ProgressionScript.can_level(hero, "ranged_skill"), "but can level archery")

	# --- Training buys skill xp with gold, and does NOT raise the skill ---
	GameState.clear()
	var archer = CharacterClassesScript.make("archer", "Tutor")
	GameState.add_member(archer)
	var before_level: int = int(archer.stats.get("ranged_skill"))
	var price: int = ProgressionScript.train_gold_cost(before_level)
	GameState.gold = 0
	_check(not ProgressionScript.can_train(archer, "ranged_skill", GameState.gold),
		"training is refused with no gold")
	GameState.add_gold(price)
	_check(ProgressionScript.can_train(archer, "ranged_skill", GameState.gold),
		"and allowed with it")
	_check(GameState.spend_gold(price), "the trainer is paid")
	archer.add_skill_xp("ranged_skill", ProgressionScript.TRAIN_XP)
	_check(archer.skill_xp_for("ranged_skill") == ProgressionScript.TRAIN_XP,
		"an hour of training is worth skill xp")
	_check(int(archer.stats.get("ranged_skill")) == before_level,
		"and does NOT raise the skill by itself")

	# --- General xp: one point per skill per quest ---
	GameState.award_xp(20)
	_check(archer.xp == 20 and archer.xp_total == 20, "general xp lands in both counters")
	var banked: int = archer.skill_xp_for("throw_skill")
	_check(archer.may_assign_general("throw_skill"), "a fresh quest allows an assignment")
	_check(archer.assign_general_xp("throw_skill"), "which moves a point into the skill")
	_check(archer.skill_xp_for("throw_skill") == banked + 1, "the skill gained it")
	_check(archer.xp == 19, "and the general pool paid for it")
	_check(not archer.may_assign_general("throw_skill"), "that skill has had its point")
	_check(not archer.assign_general_xp("throw_skill"), "and a second is refused")
	_check(archer.xp == 19, "a refused assignment costs nothing")
	_check(archer.may_assign_general("trip_skill"), "but another skill may still take one")
	_check(archer.assign_general_xp("trip_skill"), "and does")
	archer.refresh_general_allowance()
	_check(archer.may_assign_general("throw_skill"),
		"finishing a quest gives every skill its allowance back")

	var pauper = CharacterClassesScript.make("soldier", "Pauper")
	_check(not pauper.may_assign_general("attack_skill"),
		"with no general xp there is nothing to assign")

	# --- The roof on earning by use ---
	var body := _ledger_body()
	for i in range(12):
		body.award_skill_use("attack_skill", false)
	_check(body.skill_xp_earned.get("attack_skill", 0) == ProgressionScript.QUEST_USE_CAP,
		"ordinary use stops paying at the roof (%d xp for twelve swings)"
			% int(body.skill_xp_earned.get("attack_skill", 0)))
	body.award_skill_use("attack_skill", true)
	_check(body.skill_xp_earned.get("attack_skill", 0)
			== ProgressionScript.QUEST_USE_CAP + ProgressionScript.CRIT_XP,
		"a critical pays over the roof")
	body.award_skill_use("parry_skill", false)
	_check(body.skill_xp_earned.get("parry_skill", 0) == ProgressionScript.USE_XP,
		"one skill roof is not another")
	_check(ProgressionScript.is_skill("attack_skill")
			and not ProgressionScript.is_skill("stamina"),
		"attributes are not skills and are not trained here")
	body.free()

	# A goblin learns nothing: the ledger exists to be carried home, and it has no home.
	var goblin := _ledger_body()
	goblin.is_player_controlled = false
	goblin.award_skill_use("attack_skill", true)
	_check(goblin.skill_xp_earned.is_empty(), "an enemy banks no skill xp")
	goblin.free()

	# --- Does any of it reach the dungeon and come back? ---
	GameState.clear()
	var fighter = CharacterClassesScript.make("soldier", "Blade")
	GameState.add_member(fighter)
	var trained_to: int = int(fighter.stats.get(melee))
	var quest := await _enter_quest()
	var views: Array = quest._party_views
	if views.size() == 1:
		var view: Node = views[0]
		_check(view.attack_skill == trained_to, "the skill level reached the dungeon")
		_check(view.skill_xp_earned.is_empty(), "and it starts having learned nothing")
		view.award_skill_use(melee, false)
		view.award_skill_use(melee, true)
		_check(view.skill_xp_earned.get(melee, 0)
				== ProgressionScript.USE_XP + ProgressionScript.CRIT_XP,
			"using it down there is recorded on the body")

		# And now through the REAL combat path rather than by calling the award directly. A
		# blow aimed at the hero makes them parry, and parrying is a skill being used; the
		# attacker's die is rolled by the defender and left on the attacker for whoever awards
		# their experience. Both of those are wiring that a direct call would never test.
		var foe: Node = _first_enemy(quest)
		if foe != null:
			var parry_before: int = int(view.skill_xp_earned.get("parry_skill", 0))
			foe.consume_skill_die()
			view.take_damage(1, 3, false, foe)
			_check(int(view.skill_xp_earned.get("parry_skill", 0)) > parry_before,
				"defending against a real blow earned parry (%d)"
					% int(view.skill_xp_earned.get("parry_skill", 0)))
			var die: int = foe.consume_skill_die()
			_check(die >= 1 and die <= 5,
				"and the attacker was told what their die came up (%d)" % die)
		else:
			_check(false, "the quest has an enemy to test the combat hooks with")
	else:
		_check(false, "the fighter took a body into the quest")
	await _leave_quest(quest)
	_check(fighter.skill_xp_for(melee) == ProgressionScript.USE_XP + ProgressionScript.CRIT_XP,
		"and the quest handed it to the character (%d)" % fighter.skill_xp_for(melee))
	_check(fighter.general_assigned.is_empty(),
		"finishing the quest refreshed the general allowance")


func _first_enemy(quest: Node) -> Node:
	for child in quest.get_children():
		if child is CharacterBody3D and child.get("is_player_controlled") == false \
				and child.get("is_alive") == true:
			return child
	return null


func _ledger_body() -> Node:
	## A bare player-controlled combatant, for exercising the experience ledger without
	## building a whole quest around it. Never enters the tree, so nothing else runs on it.
	var body := CharacterBody3D.new()
	body.set_script(load("res://scripts/player.gd"))
	body.is_player_controlled = true
	return body


# --- The save file, standing in for the town writing one --------------------

func _run_save_checks() -> void:
	## Write the party this test has been putting through the wringer, throw away everything in
	## memory, read it back, and check the character who comes out is the same one.
	##
	## Written to a path of its own: a dev tool must not be able to overwrite the save file of
	## whoever is playing the game.
	var before_names := _data_names(GameState.party)
	var before_gold: int = GameState.gold
	var before_xp: int = GameState.party[0].xp
	var before_hp: int = GameState.party[0].hp
	var before_gear := _equipped_names_of_data(GameState.party[0])
	var before_bag: int = _bag_count(GameState.party[0])
	var before_lockpick: int = GameState.party[0].stats.lockpick_skill
	var before_attack: int = GameState.party[0].stats.attack_skill
	var before_total: int = GameState.party[0].xp_total
	var before_skill_xp: int = GameState.party[0].skill_xp_for("attack_skill")
	# The board goes in the save so the jobs a player walked away from are still there when
	# they come back, rather than the game quietly reshuffling the notices overnight.
	GameState.reroll_board()
	var before_board: int = GameState.board_seed
	var before_offers: Array = GameState.quest_board()
	GameState.reroll_camp()
	var before_camp: int = GameState.camp_seed
	var before_roster: Array = GameState.hire_roster()

	SaveGameScript.delete(TEST_SAVE)
	_check(not SaveGameScript.has_save(TEST_SAVE), "no save file to begin with")
	_check(SaveGameScript.load_into_state(TEST_SAVE) == false,
		"loading a save that is not there fails rather than crashing")
	_check(SaveGameScript.peek(TEST_SAVE).is_empty(), "and there is nothing to peek at")
	_check(not GameState.party.is_empty(), "a failed load left the party in memory alone")

	_check(SaveGameScript.save(TEST_SAVE), "the party can be saved")
	_check(SaveGameScript.has_save(TEST_SAVE), "the save file is on disk")

	var summary := SaveGameScript.peek(TEST_SAVE)
	_check(not summary.is_empty(), "the save can be read without loading it")
	_check(summary.get("gold", -1) == before_gold, "the save says how much gold is in it")
	_check(summary.get("party", []).size() == before_names.size(),
		"the save says who is in it, without loading them")
	_check(SaveGameScript.describe_age(summary.get("saved_at", 0)) == "just now",
		"a save just written reads as just written")

	GameState.clear()
	_check(not GameState.has_party(), "the party in memory can be thrown away")
	_check(SaveGameScript.load_into_state(TEST_SAVE), "the save loads")

	_check(_data_names(GameState.party) == before_names, "the party came back")
	_check(GameState.gold == before_gold, "the gold came back (%d)" % GameState.gold)
	_check(GameState.party[0].xp == before_xp, "the xp came back (%d)" % GameState.party[0].xp)
	_check(GameState.party[0].hp == before_hp, "the wounds came back")
	_check(_bag_count(GameState.party[0]) == before_bag, "every item came back")
	_check(_equipped_names_of_data(GameState.party[0]) == before_gear,
		"the loadout came back (%s)" % ", ".join(_equipped_names_of_data(GameState.party[0])))
	_check(GameState.party[0].stats.lockpick_skill == before_lockpick,
		"the trained skills came back")
	_check(GameState.party[0].stats.attack_skill == before_attack,
		"including the one that was paid for (%d)" % GameState.party[0].stats.attack_skill)
	_check(GameState.party[0].xp_total == before_total,
		"and the character history came back (%d)" % GameState.party[0].xp_total)
	_check(GameState.party[0].skill_xp_for("attack_skill") == before_skill_xp,
		"each skill own experience survives the save format")
	_check(GameState.party[0].stats != null and GameState.party[0].id != "",
		"the loaded character still has a stat block and an id")
	_check(GameState.board_seed == before_board, "the notice board came back")
	var reloaded_offers: Array = GameState.quest_board()
	var same_jobs := reloaded_offers.size() == before_offers.size()
	for i in range(reloaded_offers.size()):
		if i >= before_offers.size() or reloaded_offers[i].title != before_offers[i].title:
			same_jobs = false
	_check(same_jobs, "showing the same jobs it was showing when the game was closed")
	_check(GameState.camp_seed == before_camp, "and the camp came back")
	var reloaded_roster: Array = GameState.hire_roster()
	var same_faces := reloaded_roster.size() == before_roster.size()
	for i in range(reloaded_roster.size()):
		if i >= before_roster.size() or String(reloaded_roster[i]["character_name"]) \
				!= String(before_roster[i]["character_name"]):
			same_faces = false
	_check(same_faces, "with the same people sitting round its fire")

	# A save from a future version of the game must be refused rather than half-read: loading
	# a character out of a format we do not understand is how a party quietly loses its gear.
	var newer := SaveGameScript.read(TEST_SAVE)
	newer["save_version"] = SaveGameScript.SAVE_VERSION + 1
	_write_json(TEST_SAVE, newer)
	_check(SaveGameScript.read(TEST_SAVE).is_empty(),
		"a save from a newer version of the game is refused")
	_check(SaveGameScript.load_into_state(TEST_SAVE) == false, "and loading it changes nothing")
	_check(not GameState.party.is_empty(), "the party in memory survived that")

	# Neither should a file that is not a save at all.
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("this is not a save file")
	f.close()
	_check(SaveGameScript.read(TEST_SAVE).is_empty(), "a file that is not a save is refused")
	_check(SaveGameScript.load_into_state(TEST_SAVE) == false,
		"and that does not empty the party either")
	_check(not GameState.party.is_empty(), "the party in memory survived that too")

	_check(SaveGameScript.delete(TEST_SAVE), "a save can be deleted")
	_check(not SaveGameScript.has_save(TEST_SAVE), "and then it is gone")
	# The half-written file the atomic write uses, if anything went wrong mid-test.
	DirAccess.remove_absolute(TEST_SAVE + ".part")


func _write_json(path: String, payload: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))
	f.close()


# --- Quest entry / exit, standing in for the screens that will do it ---------

func _enter_quest() -> Node:
	var quest := QuestScene.instantiate()
	add_child(quest)
	# Two frames: one for the deferred CombatManager boot, one for the party panel, which
	# waits a frame of its own before building.
	await get_tree().process_frame
	await get_tree().process_frame
	return quest


func _leave_quest(quest: Node, outcome: String = "retreat") -> Dictionary:
	## What finish_quest does, minus the change_scene_to_file — a scene change here would free
	## this test along with the quest. The settlement itself is the quest's own method, so this
	## helper cannot drift away from what leaving a dungeon really does: the capture, the pay
	## for the bodies, the contract, the board going up fresh.
	var settlement: Dictionary = quest.settle(outcome)
	remove_child(quest)
	quest.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return settlement


# --- Small helpers ----------------------------------------------------------

func _authored_count(quest: Node) -> int:
	var n := 0
	for child in quest.get_children():
		if child is CharacterBody3D and child.get("is_player_controlled") == true:
			n += 1
	return n


func _names_of(views: Array) -> Array:
	var out: Array = []
	for view in views:
		out.append(view.character_name)
	return out


func _data_names(party: Array) -> Array:
	var out: Array = []
	for member in party:
		out.append(member.character_name)
	return out


func _bag_count(data) -> int:
	var n := 0
	for item in data.bag:
		if item != null:
			n += 1
	return n


func _has_item(data, item_name: String) -> bool:
	for item in data.bag:
		if item != null and item.item_name == item_name:
			return true
	return false


func _equipped_names(view: Node) -> Array:
	var out: Array = []
	for slot in ["right_hand", "left_hand", "armor", "helmet", "legs"]:
		var item: ItemResource = view.inventory.get(slot)
		out.append(item.item_name if item != null else "-")
	return out


func _equipped_names_of_data(data) -> Array:
	var out: Array = []
	for slot in [ItemResource.EquipSlot.RIGHT_HAND, ItemResource.EquipSlot.LEFT_HAND,
			ItemResource.EquipSlot.ARMOR, ItemResource.EquipSlot.HELMET,
			ItemResource.EquipSlot.LEGS]:
		var idx: int = int(data.equipped.get(slot, -1))
		if idx >= 0 and idx < data.bag.size() and data.bag[idx] != null:
			out.append(data.bag[idx].item_name)
		else:
			out.append("-")
	return out


## Runtime state rather than character definition: these legitimately differ between one
## quest and the next, so _stat_snapshot leaves them out.
const NOT_A_STAT := ["hp", "max_hp", "mana", "max_mana", "is_alive", "is_prone", "sneaking",
	"is_moving", "can_act", "next_turn_at", "action_turn_at", "is_player_controlled",
	"selected_action", "action_pinned"]


func _stat_snapshot(node: Node) -> Dictionary:
	## Every number, flag and name that makes this character who they are, read off the live
	## body.
	##
	## The field list comes from the COMBATANT's own script variables, deliberately NOT from
	## CombatantStats. Deriving it from the stat block would make this check blind to the one
	## bug it exists for: a stat that the block has no field for is dropped by the capture
	## path, and comparing block-to-block would never notice, because both sides would be
	## missing it.
	var out := {}
	for prop in node.get_script().get_script_property_list():
		var field: String = prop["name"]
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if field.begins_with("_") or NOT_A_STAT.has(field):
			continue
		var value = node.get(field)
		# Scalars only: a node, an array or a resource is either runtime wiring or a thing
		# compared elsewhere (the inventory has its own checks).
		if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
			out[field] = value
	return out


func _quiver_matches(view: Node, data) -> bool:
	## A class's body carries properties of its own — the archer's quiver is one — and they
	## have to be set before the model enters the tree or CharacterSkin never builds them.
	var model: Node = view.get_node_or_null("CharacterModel")
	if model == null:
		return false
	# `== true` rather than a bool() cast: GDScript has no bool constructor, and both sides
	# can legitimately be null (a model with no such property at all).
	var wants: bool = data.model_props().get("show_quiver", false) == true
	return (model.get("show_quiver") == true) == wants


func _check(passed: bool, what: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(what)
