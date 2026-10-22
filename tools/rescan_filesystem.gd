@tool
extends Node
## Dev tool: opening this scene in the editor makes the editor rescan res:// and import
## anything new. Files dropped into the project from outside are otherwise never noticed
## (see the roadmap's note on THE IMPORT PROBLEM). Does nothing at runtime.

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var fs = Engine.get_singleton("EditorInterface").get_resource_filesystem()
	print("[Rescan] scanning res:// for new files")
	fs.scan()
