extends Node
## Dev tool: prints every MeshInstance3D in the given scenes with its global AABB. Quits.

@export var scenes: Array = ["res://assets/goblin_camp/SM_Prop_Quiver_01.fbx", "res://assets/goblin_camp/SM_Wep_Arrow_01.fbx"]


func _ready() -> void:
	for p in scenes:
		var root := (load(p) as PackedScene).instantiate() as Node3D
		add_child(root)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			print("[probe] %s %s aabb=%s" % [p.get_file(), root.get_path_to(m), m.global_transform * m.mesh.get_aabb()])
	get_tree().quit()
