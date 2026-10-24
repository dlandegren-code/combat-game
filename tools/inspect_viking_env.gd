extends Node3D
## Dev tool: what each Viking Realm environment FBX (assets/vikings/env/) is made of — its
## meshes, each one's transform under the scene root, and its bounds in root space — so the
## hall kit can be sized against the dungeon's 4 m tiles. Writes .summer/local/viking_env.txt
## and quits.

const DIR := "res://assets/vikings/env/"


func _ready() -> void:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".fbx"):
			continue
		var ps := load(DIR + f) as PackedScene
		if ps == null:
			out.append("%s: unloadable" % f)
			continue
		var root := ps.instantiate() as Node3D
		add_child(root)
		var box := AABB()
		var first := true
		var parts: Array = []
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf: Transform3D = root.global_transform.affine_inverse() * m.global_transform
			var b: AABB = xf * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
			parts.append("%s(rot=%s scl=%s at=%s)" % [m.name, xf.basis.get_euler().snapped(Vector3.ONE * 0.01),
				xf.basis.get_scale().snapped(Vector3.ONE * 0.01), xf.origin.snapped(Vector3.ONE * 0.01)])
		out.append("%s pos=%s size=%s %s" % [f.get_basename(), box.position.snapped(Vector3.ONE * 0.01),
			box.size.snapped(Vector3.ONE * 0.01), parts])
		root.queue_free()
	var file := FileAccess.open("res://.summer/local/viking_env.txt", FileAccess.WRITE)
	file.store_string("\n".join(out))
	file.close()
	get_tree().quit()
