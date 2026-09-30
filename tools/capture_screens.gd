extends Node
## Dev tool: mounts every flat town screen in turn with a real party and saves a screenshot of
## each into .summer/local/screens/.
##
## Run it by playing tools/capture_screens.tscn.
##
## WHY THIS EXISTS
## capture_town.gd closed the loop on the 3D town — build, capture, look, adjust. The flat
## screens had no such loop, and they are the part of the game that is ENTIRELY look: whether
## a panel's nine-patch margins are right, whether a row of buttons wraps, whether an item's
## icon lands in its well. None of that raises an error, and the round-trip test can only say
## that a button exists and does what it says.
##
## The party is built to make every branch draw something: four members so the pickers appear,
## gold enough that nothing is greyed out for poverty, a wound so the healer quotes a price,
## and a bag with room in it so the shop and the party sheet both have somewhere to put things.
##
## Like every dev tool here it puts the player's save file back exactly as it found it.

const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")
const PartySheetScript := preload("res://scripts/party_sheet.gd")
const ShopScript := preload("res://scripts/shop.gd")

const OUT_DIR := "res://.summer/local/screens"

## Frames to let a screen lay itself out AND photograph its items.
##
## Layout needs one or two — UiKit's scrolling variant measures the viewport, and a Control
## that has not been through a layout pass reports a size of zero. The item pictures need far
## more: ItemSlot shows a flat category icon immediately and swaps in a render of the item's
## own 3D model when it arrives, and those renders go through ONE shared viewport, one item
## per frame (ItemThumbnails._busy). A market with sixteen things on the shelf therefore needs
## sixteen frames before the shot shows what the player actually sees.
const SETTLE_FRAMES := 90

## What to shoot. `tab` is for the party sheet, whose three pages are one scene, and `shop`
## for the market, whose three stalls are one scene too.
const SCREENS := [
	{"name": "01_title", "scene": "res://scenes/title_screen.tscn"},
	{"name": "02_creation", "scene": "res://scenes/character_creation.tscn"},
	{"name": "03_board", "scene": "res://scenes/quest_board.tscn"},
	{"name": "04_camp", "scene": "res://scenes/hire_camp.tscn"},
	{"name": "05a_armorer", "scene": "res://scenes/shop.tscn", "shop": "armorer"},
	{"name": "05b_weaponsmith", "scene": "res://scenes/shop.tscn", "shop": "weaponsmith"},
	{"name": "05c_general", "scene": "res://scenes/shop.tscn", "shop": "general"},
	{"name": "06_training", "scene": "res://scenes/training.tscn"},
	{"name": "07_party_gear", "scene": "res://scenes/party_sheet.tscn", "tab": "gear"},
	{"name": "08_party_sheet", "scene": "res://scenes/party_sheet.tscn", "tab": "sheet"},
	{"name": "09_party_spells", "scene": "res://scenes/party_sheet.tscn", "tab": "spells"},
	{"name": "10_results", "scene": "res://scenes/results_screen.tscn"},
]

var _save_existed := false
var _save_backup := PackedByteArray()


func _ready() -> void:
	# A window big enough to judge a layout in. The editor's play window is whatever it was
	# left at, and a screen that fits at 1152 and spills at 848 is a screen worth seeing spill.
	get_window().size = Vector2i(1152, 720)
	await get_tree().process_frame
	_guard_save()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	for entry in SCREENS:
		_seed_party()
		if entry.has("tab"):
			PartySheetScript.opening_tab = String(entry["tab"])
		if entry.has("shop"):
			ShopScript.opening_shop = String(entry["shop"])
		await _shoot(entry)

	_restore_save()
	get_tree().quit()


func _seed_party() -> void:
	## A fresh party before every shot, because the screens SPEND: the shop takes gold, the
	## camp takes a hireling on. Re-seeding is what stops shot six being taken of a party that
	## shots one to five emptied.
	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("soldier", "Aldric"))
	GameState.add_member(CharacterClassesScript.make("archer", "Wren"))
	GameState.add_member(CharacterClassesScript.make("wizard", "Ilse"))
	GameState.gold = 900
	GameState.award_xp(400)
	GameState.party[0].hp = 12
	# Something loose in the pack, so the shop has something to offer to buy back and the
	# party sheet has a row under "Carried" rather than an empty heading.
	GameState.party[0].bag_add(
		(load("res://resources/items/health_potion.tres") as ItemResource).make_instance())
	# A result to report, for the screen whose whole job is reporting one.
	GameState.last_result = {
		"outcome": "victory", "kills": 5, "xp": 280, "gold": 225,
		"loot": ["Health Potion", "Knight Helmet"], "fallen": [],
		"skills": ["Aldric: Melee +3, Parry +1"],
		"quest": "Clear the Sunken Undercroft", "quest_paid": true,
		"quest_gold": 150, "quest_xp": 180,
	}


func _shoot(entry: Dictionary) -> void:
	var packed := load(String(entry["scene"])) as PackedScene
	if packed == null:
		push_warning("CaptureScreens: no scene at %s" % entry["scene"])
		return
	var screen := packed.instantiate()
	var as_control := screen as Control
	if as_control != null:
		as_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var panel := _find_panel(screen)
	var panel_size := panel.size if panel != null else Vector2.ZERO
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, entry["name"]]
	var err := image.save_png(path)
	print("[Screens] %s %-34s shot %dx%d  panel %dx%d" % [
		"ok  " if err == OK else "FAIL", entry["name"],
		image.get_width(), image.get_height(), panel_size.x, panel_size.y])
	if panel_size.x > image.get_width() or panel_size.y > image.get_height():
		push_warning("CaptureScreens: %s does not fit the window" % entry["name"])

	remove_child(screen)
	screen.queue_free()
	await get_tree().process_frame


func _find_panel(node: Node) -> Control:
	## The framed box UiKit.mount stands up, so a shot can report whether it fits.
	if node is PanelContainer:
		return node
	for child in node.get_children():
		var found := _find_panel(child)
		if found != null:
			return found
	return null


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
