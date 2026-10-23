@tool
extends Node
## Dev tool: lets an agent ask the EDITOR to do the things only the editor can — notice new
## files, and reimport files whose import settings were changed on disk.
##
## Open tools/editor_bridge.tscn in the editor (summer_open_scene) and leave it open. While it is
## the edited scene it checks, once a second, for res://.summer/local/editor_request.json:
##
##   {"scan": true}                         rescan res:// (imports files copied in from outside)
##   {"reimport": ["res://a.fbx", ...]}     reimport these files with their current .import
##
## and writes res://.summer/local/editor_result.txt when done. The request file is deleted once
## taken. Does nothing at runtime.

const REQUEST := "res://.summer/local/editor_request.json"
const RESULT := "res://.summer/local/editor_result.txt"

var _t := 0.0


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	if not FileAccess.file_exists(REQUEST):
		return
	var text := FileAccess.get_file_as_string(REQUEST)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST))
	var req = JSON.parse_string(text)
	if typeof(req) != TYPE_DICTIONARY:
		_done("bad request: %s" % text)
		return
	var fs = Engine.get_singleton("EditorInterface").get_resource_filesystem()
	if req.get("scan", false):
		fs.scan()
		_done("scan started")
	var files: Array = req.get("reimport", [])
	if not files.is_empty():
		fs.reimport_files(PackedStringArray(files))
		_done("reimported %d" % files.size())


func _done(msg: String) -> void:
	print("[EditorBridge] " + msg)
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	f.store_string("%s %s\n" % [Time.get_datetime_string_from_system(), msg])
	f.close()
