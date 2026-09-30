extends Node
## Dev tool: loads the quest scene, opens each HUD panel in turn, and saves a screenshot of
## each into .summer/local/hud/.
##
## Run it by playing tools/capture_hud.tscn.
##
## WHY THIS EXISTS
## The same reason capture_screens.gd does, for the other half of the game. The dungeon HUD is
## entirely look — whether a nine-patch frame's corners are the right size, whether a stat well
## reads as a well, whether a divider survives being stretched — and none of that raises an
## error. The round-trip test can say a panel draws; it cannot say it draws WELL.
##
## The panels show whoever CombatManager says is active, and combat starts on whoever wins
## initiative — which is often a goblin, and a goblin has no character sheet to draw. So the
## turn is handed to a player-controlled body before the shots are taken. That is poking at
## the combat layer's insides, which a dev tool may do and nothing else may.

const QUEST_SCENE := "res://scenes/quest_scene.tscn"
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const OUT_DIR := "res://.summer/local/hud"

## The quest scene has to boot its combat manager, spawn the party, build the toolbar and let
## the item thumbnails render — the last of which goes one item per frame through a shared
## viewport (see capture_screens.gd).
const BOOT_FRAMES := 40
const PANEL_FRAMES := 60

## The CanvasLayers to shoot, by node name. "" is the bare HUD: toolbar, portraits, turn
## label, initiative order — everything that is on screen when no panel is open.
const PANELS := [
	{"name": "01_hud", "node": ""},
	{"name": "02_inventory", "node": "InventoryPanel"},
	{"name": "03_sheet", "node": "CharacterSheetPanel"},
	{"name": "04_spells", "node": "SpellSheetPanel"},
]

var _save_existed := false
var _save_backup := PackedByteArray()


func _ready() -> void:
	_guard_save()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("wizard", "Ilse the Patient"))
	GameState.add_member(CharacterClassesScript.make("soldier", "Aldric"))
	GameState.add_member(CharacterClassesScript.make("archer", "Wren Blackthorn"))
	GameState.gold = 400
	GameState.award_xp(400)

	var quest := (load(QUEST_SCENE) as PackedScene).instantiate()
	add_child(quest)
	for i in range(BOOT_FRAMES):
		await get_tree().process_frame

	_hand_the_turn_to_a_hero(quest)

	for entry in PANELS:
		await _shoot(quest, entry)

	_restore_save()
	get_tree().quit()


func _hand_the_turn_to_a_hero(quest: Node) -> void:
	## The sheets draw whoever is active, and a goblin has no sheet worth drawing.
	var cm := quest.get_node_or_null("CombatManager")
	if cm == null:
		push_warning("CaptureHud: no CombatManager to ask")
		return
	var active = cm.get("current_combatant")
	if active != null and is_instance_valid(active) and active.get("is_player_controlled") == true:
		return
	for c in get_tree().get_nodes_in_group("combatants"):
		if is_instance_valid(c) and c.get("is_player_controlled") == true and c.get("is_alive"):
			cm.set("current_combatant", c)
			print("[Hud] turn handed to %s" % c.character_name)
			return
	push_warning("CaptureHud: no living hero to give the turn to")


func _shoot(quest: Node, entry: Dictionary) -> void:
	var wanted := String(entry["node"])
	# One panel at a time, so a shot of the inventory is not half covered by the spell book.
	for other in PANELS:
		var name := String(other["node"])
		if name == "":
			continue
		var layer := quest.get_node_or_null(name)
		if layer != null:
			layer.visible = name == wanted

	for i in range(PANEL_FRAMES):
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, entry["name"]]
	var err := image.save_png(path)
	print("[Hud] %s %-16s shot %dx%d" % [
		"ok  " if err == OK else "FAIL", entry["name"],
		image.get_width(), image.get_height()])


func _guard_save() -> void:
	_save_existed = FileAccess.file_exists(SaveGameScript.PATH)
	if _save_existed:
		_save_backup = FileAccess.get_file_as_bytes(SaveGameScript.PATH)


func _restore_save() -> void:
	if _save_existed:
		var f := FileAccess.open(SaveGameScript.PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_save_backup)
			f.close()
	else:
		SaveGameScript.delete()
