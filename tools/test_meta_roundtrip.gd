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
	_check(_press(training, "Melee"), "the training hall offers Melee")
	_check(int(GameState.party[0].stats.attack_skill) == before_skill + 1,
		"pressing it trained the skill")
	_check(GameState.party[0].xp < before_xp, "it cost xp")
	_check(GameState.gold < before_gold, "and gold")
	# The second party member is reachable, which is what the picker is for.
	_check(_press(training, "Second"), "the training hall can switch to the other hero")
	_check(_press(training, "Archery"), "and train them instead")
	_check(int(GameState.party[1].stats.ranged_skill) > 3, "which raised THEIR skill")
	_check(int(GameState.party[0].stats.ranged_skill) == 3, "and not the other one's")
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
	## Everything the training hall and the market do, minus the buttons — and then a quest, to
	## check that a trained skill and a bought sword actually reach the dungeon. A stat that
	## can be paid for but never arrives is the worst kind of bug: the receipt says it worked.
	GameState.clear()
	var hero = CharacterClassesScript.make("soldier", "Coin")
	GameState.add_member(hero)

	# --- Levels come off lifetime xp, not the spendable pool ---
	_check(ProgressionScript.level_for(0) == 1, "a new character is level 1")
	_check(ProgressionScript.level_for(100) == 2, "100 lifetime xp is level 2")
	_check(ProgressionScript.level_for(299) == 2, "and 299 is still level 2")
	_check(ProgressionScript.level_for(300) == 3, "300 is level 3 — each level costs more")
	_check(ProgressionScript.xp_for_next_level(0) == 100, "the screen can say what is left")

	GameState.award_xp(500)
	_check(hero.xp == 500 and hero.xp_total == 500, "earned xp lands in both counters")
	_check(hero.level == ProgressionScript.level_for(500), "and the level follows it")

	# --- Training spends both, and refuses when it cannot ---
	var entry: Dictionary = ProgressionScript.entry_for("attack_skill")
	var before_skill: int = int(hero.stats.attack_skill)
	var xp_price: int = ProgressionScript.xp_cost("skill", before_skill)
	var gold_price: int = ProgressionScript.gold_cost("skill", before_skill)

	GameState.gold = 0
	_check(not ProgressionScript.can_train(hero, entry, GameState.gold),
		"training is refused with no gold")
	_check(ProgressionScript.refusal(hero, entry, GameState.gold).contains("gold"),
		"and the refusal says it is the money")
	_check(int(hero.stats.attack_skill) == before_skill, "a refusal raises nothing")

	GameState.add_gold(gold_price)
	_check(ProgressionScript.can_train(hero, entry, GameState.gold), "with the money, it is on")
	_check(GameState.spend_gold(gold_price), "the gold is taken")
	_check(ProgressionScript.train(hero, entry), "the skill is bought")
	_check(int(hero.stats.attack_skill) == before_skill + 1,
		"the skill went up by one (%d)" % int(hero.stats.attack_skill))
	_check(hero.xp == 500 - xp_price, "the xp pool paid for it (%d left)" % hero.xp)
	_check(hero.xp_total == 500, "and spending it did not undo the character's history")
	_check(GameState.gold == 0, "and so did the purse")

	# The pool is a pool: spend it all and there is nothing left to train with, whatever the
	# character's level says.
	var broke = CharacterClassesScript.make("soldier", "Broke")
	_check(not ProgressionScript.can_train(broke, entry, 99999),
		"a character with no xp cannot train however rich the party is")

	# The cap is a real stop, not a slow-down.
	var capped = CharacterClassesScript.make("soldier", "Capped")
	capped.stats.attack_skill = ProgressionScript.SKILL_CAP
	capped.xp = 99999
	_check(not ProgressionScript.can_train(capped, entry, 99999), "a capped skill refuses")
	_check(ProgressionScript.refusal(capped, entry, 99999).contains("as high"),
		"and says that is why")

	# --- The market ---
	var potion = load("res://resources/items/health_potion.tres")
	var armour = load("res://resources/items/heavy_armor.tres")
	_check(potion.gold_value() > 0, "an item with no price of its own is still worth something")
	_check(armour.gold_value() > potion.gold_value(),
		"armour costs more than a potion (%d vs %d)" % [armour.gold_value(), potion.gold_value()])
	_check(potion.sell_value() < potion.gold_value(),
		"a shop sells dearer than it buys (%d / %d)" % [potion.gold_value(), potion.sell_value()])

	var bought_armour = armour.make_instance()
	GameState.gold = armour.gold_value()
	_check(GameState.spend_gold(armour.gold_value()), "armour can be paid for")
	_check(hero.bag_add(bought_armour), "and goes in the pack")
	var armour_idx: int = hero.bag.find(bought_armour)
	_check(hero.equip_from_bag(armour_idx), "and can be put on")
	_check(hero.is_equipped(armour_idx), "and reads as worn")

	# Selling something that is being worn has to take it off on the way out, or the character
	# keeps the armour bonus of a breastplate that belongs to somebody else now.
	var purse: int = GameState.gold
	var refund: int = bought_armour.sell_value()
	var sold = hero.bag_remove_at(armour_idx)
	GameState.add_gold(refund)
	_check(sold == bought_armour, "the right item was sold")
	_check(not hero.is_equipped(armour_idx), "and it is no longer worn")
	_check(hero.bag[armour_idx] == null, "and no longer carried")
	_check(GameState.gold == purse + refund, "and the party was paid (%d)" % GameState.gold)

	# A full pack refuses a purchase rather than dropping something.
	var hoarder = CharacterClassesScript.make("soldier", "Hoarder")
	var added := 0
	while hoarder.bag_add(potion.make_instance()):
		added += 1
		if added > 20:
			break
	_check(not hoarder.bag_has_room(), "a pack fills up")
	_check(not hoarder.bag_add(potion.make_instance()), "and then refuses more")

	# --- And now the part that matters: does any of it reach the dungeon? ---
	var trained_skill: int = int(hero.stats.attack_skill)
	var sword = load("res://resources/items/warhammer.tres").make_instance()
	hero.bag_add(sword)
	var sword_idx: int = hero.bag.find(sword)
	hero.equip_from_bag(sword_idx)
	var quest := await _enter_quest()
	var views: Array = quest._party_views
	if views.size() == 1:
		var view: Node = views[0]
		_check(view.attack_skill == trained_skill,
			"the trained skill reached the dungeon (%d)" % view.attack_skill)
		_check(view.inventory.right_hand != null
				and view.inventory.right_hand.item_name == sword.item_name,
			"the bought weapon is in the hero's hand")
	else:
		_check(false, "the trained hero took a body into the quest")
	await _leave_quest(quest)
	_check(int(GameState.party[0].stats.attack_skill) == trained_skill,
		"and the training survived the quest")


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
		"and the character's history came back (%d)" % GameState.party[0].xp_total)
	_check(GameState.party[0].stats != null and GameState.party[0].id != "",
		"the loaded character still has a stat block and an id")

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


func _leave_quest(quest: Node) -> void:
	## What finish_quest does, minus the change_scene_to_file — a scene change here would free
	## this test along with the quest. The capture is the part under test.
	for i in range(quest._party_views.size()):
		var view: Node = quest._party_views[i]
		if i < GameState.party.size() and is_instance_valid(view):
			GameState.party[i].capture_from(view)
	remove_child(quest)
	quest.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
