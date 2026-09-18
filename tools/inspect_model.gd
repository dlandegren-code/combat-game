extends Node3D
## Dev tool: dumps what a Synty FBX actually contains — mesh names, surfaces, and the UV
## rectangle each surface uses.
##
## Run it by playing tools/inspect_model.tscn; it writes .summer/local/model_report.txt.
##
## WHY UV BOUNDS
## Two of the meadow pack's textures look like they could be a tree's canopy and only one of
## them is; the pack's material list says which MATERIAL a surface wants but not which FILE.
## The UV rectangle settles it without guessing: a surface whose UVs sit inside a small cell
## is painted from the palette atlas, and one whose UVs span most of 0..1 has a texture of its
## own laid out across the whole image.

const MODELS := [
	"res://assets/Synty/PolygonMeadow/Models/SM_Env_Tree_Birch_01.fbx",
	"res://assets/Synty/PolygonMeadow/Models/SM_Env_Tree_Meadow_01.fbx",
	"res://assets/Synty/PolygonMeadow/Models/SM_Env_Bush_01.fbx",
	"res://assets/Synty/PolygonMeadow/Models/SM_Bld_Stone_Cabin_01.fbx",
]
const REPORT := "res://.summer/local/model_report.txt"

var _lines: Array[String] = []


func _ready() -> void:
	for path in MODELS:
		_lines.append("=== %s" % path.get_file())
		var packed := load(path) as PackedScene
		if packed == null:
			_lines.append("  (could not load)")
			continue
		var node := packed.instantiate()
		add_child(node)
		_dump(node, 1)
		remove_child(node)
		node.queue_free()
		_lines.append("")
	DirAccess.make_dir_recursive_absolute(REPORT.get_base_dir())
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("[Inspect] wrote %s" % REPORT)
	get_tree().quit()


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		var mesh := mesh_node.mesh
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else PackedVector2Array()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv_min := Vector2(999, 999)
			var uv_max := Vector2(-999, -999)
			for uv in uvs:
				uv_min = Vector2(minf(uv_min.x, uv.x), minf(uv_min.y, uv.y))
				uv_max = Vector2(maxf(uv_max.x, uv.x), maxf(uv_max.y, uv.y))
			var mat := mesh.surface_get_material(surface)
			var mat_name := String(mat.resource_name) if mat != null else "<none>"
			_lines.append("%s%s  surface %d: %d verts, uv %.3f,%.3f .. %.3f,%.3f  (fbx material: %s)" % [
				pad, node.name, surface, verts.size(),
				uv_min.x, uv_min.y, uv_max.x, uv_max.y, mat_name])
	else:
		_lines.append("%s%s [%s]" % [pad, node.name, node.get_class()])
	for child in node.get_children():
		_dump(child, depth + 1)
