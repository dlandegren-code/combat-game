extends Node3D
## Dev tool: checks the Phase 0 round trip — that a character survives leaving the quest
## scene and coming back to it.
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
	_check(not GameState.party.is_empty(), "first quest seeds a party from the authored heroes")
	_check(GameState.party.size() == seeded.size(),
		"one character per authored hero (%d data / %d bodies)" % [GameState.party.size(), seeded.size()])
	var first_names := _names_of(seeded)
	_say("[RoundTrip] seeded: %s" % ", ".join(first_names))
	for i in range(GameState.party.size()):
		var data = GameState.party[i]
		_check(data.stats != null, "%s has a stat block of their own" % data.character_name)
		_check(data.class_id in CharacterDataScript.CLASS_MODELS,
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


func _check(passed: bool, what: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(what)
