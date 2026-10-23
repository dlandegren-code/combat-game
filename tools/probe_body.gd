extends Node3D
## Dev tool: is a clip actually posing a body? Prints bone poses against rest after playing idle.
## Each case is a body scene plus the props to set on it before it builds.

const CASES := [
	["res://scenes/characters/polygon_model.tscn", {}],
	["res://scenes/characters/sidekick_model.tscn", {}],
	["res://scenes/characters/polygon_model.tscn", {
		"source": "res://assets/vikings/characters/VikingRealm_Characters.fbx",
		"character": "SM_Chr_Warrior_Male_01",
		"texture": "res://assets/vikings/textures/PolygonVikingRealm_Texture_01_A.png"}],
]


func _ready() -> void:
	var out: Array = []
	for case in CASES:
		var path: String = case[0]
		var b := (load(path) as PackedScene).instantiate()
		for prop in case[1]:
			b.set(prop, case[1][prop])
		add_child(b)
		b.play("idle")
		for i in range(8):
			await get_tree().process_frame
		var sk: Skeleton3D = b.skeleton
		out.append("== %s %s playing=%s current=%s bones=%d" % [path, case[1].get("character", ""), b.anim.is_playing(), b.anim.current_animation, sk.get_bone_count()])
		for bone in ["Hips", "LeftUpperArm", "LeftLowerArm", "Head", "prop_r"]:
			var i := sk.find_bone(bone)
			if i < 0:
				out.append("  %s missing" % bone)
				continue
			out.append("  %s pose=%s rest=%s" % [bone, sk.get_bone_pose_rotation(i), sk.get_bone_rest(i).basis.get_rotation_quaternion()])
		var shown: Array = []
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).visible:
				shown.append("%s aabb=%s" % [mi.name, (mi as MeshInstance3D).get_aabb().size])
		out.append("  meshes %s" % [shown])
		var a: Animation = b.anim.get_animation("idle")
		var paths: Array = []
		for t in range(mini(a.get_track_count(), 5)):
			paths.append("%s(%d)" % [a.track_get_path(t), a.track_get_type(t)])
		out.append("  tracks %s" % [paths])
		out.append("  anim root=%s skeleton path=%s" % [b.anim.root_node, b.get_path_to(sk)])
	var f := FileAccess.open("res://.summer/local/probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
