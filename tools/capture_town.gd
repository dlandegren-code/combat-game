extends Node3D
## Dev tool: loads the town, lets it settle, and saves a screenshot of it.
##
## Run it by playing tools/capture_town.tscn. It writes .summer/local/town_preview.png and
## quits.
##
## WHY THIS EXISTS
## The town is the one part of this game whose correctness is entirely visual — whether a
## building faces the camera, whether a texture landed on the right surface, whether a button
## sits over the right roof. None of that shows up as an error, and the editor's MCP has no
## screenshot op, so without this the only way to see the scene is to ask the person at the
## keyboard. This closes the loop: build, capture, look, adjust.
##
## It populates a party first, because half the screen is buttons whose state depends on
## having one — and then puts the player's save file back exactly as it found it, because a
## dev tool has no business writing to that.

const TOWN_SCENE := "res://scenes/town.tscn"
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")

const SHOT := "res://.summer/local/town_preview.png"
const STATS := "res://.summer/local/town_stats.txt"
## Frames to wait before capturing. The scene builds in one, but shadows, the sky and the
## preprocessed particle systems all need a few more before they look like themselves.
const SETTLE_FRAMES := 12
const SETTLE_SECONDS := 0.8

var _save_existed := false
var _save_backup := PackedByteArray()


func _ready() -> void:
	_guard_save()

	GameState.clear()
	GameState.add_member(CharacterClassesScript.make("soldier", "Aldric"))
	GameState.gold = 120
	GameState.award_xp(260)
	# Wounded, so the healer's button shows its price rather than being greyed out.
	GameState.party[0].hp = 12

	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	add_child(town)

	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout

	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var err := image.save_png(SHOT)
	print("[Capture] %s -> %s (%dx%d)" % [
		"ok" if err == OK else "FAILED", SHOT, image.get_width(), image.get_height()])

	# What the scene costs, written next to the picture. A forest deep enough to hide the
	# horizon is easy to build and easy to overbuild, and "it looked fine in a screenshot" is
	# not the same as "it runs" — this is the number that tells the difference.
	var stats := PackedStringArray([
		"fps                 %d" % int(Performance.get_monitor(Performance.TIME_FPS)),
		"frame time (ms)     %.2f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"objects drawn       %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives drawn    %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draw calls          %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes in tree       %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"video memory (MB)   %.1f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
	])
	var f := FileAccess.open(STATS, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(stats) + "\n")
		f.close()
	print("[Capture] " + " | ".join(stats))

	_restore_save()
	get_tree().quit()


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
