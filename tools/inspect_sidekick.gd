extends Node
## Dev tool: prints the structure of imported Sidekick parts and clips, to
## .summer/local/sidekick_inspect.txt. Play tools/inspect_sidekick.tscn.

const PARTS := [
	"res://assets/vikings/characters/VikingRealm_Characters.fbx",
]
const CLIP := "res://assets/vikings/weapons/SM_Wep_Axe_01.fbx"
var _out: Array = []


func _ready() -> void:
	for p in PARTS:
		_dump_scene(p, true)
	_dump_scene(CLIP, true)
	var f := FileAccess.open("res://.summer/local/sidekick_inspect.txt", FileAccess.WRITE)
	f.store_string("\n".join(_out))
	f.close()
	get_tree().quit()


func _dump_scene(path: String, bones: bool) -> void:
	var ps: PackedScene = load(path)
	_out.append("== %s (%s)" % [path, ps != null])
	if ps == null:
		return
	var root := ps.instantiate()
	_walk(root, 0, true)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		for lib in ap.get_animation_library_list():
			for a in ap.get_animation_library(lib).get_animation_list():
				var anim := ap.get_animation(("%s/%s" % [lib, a]) if lib != "" else a)
				var tracks: Array = []
				for i in range(mini(anim.get_track_count(), 6)):
					tracks.append(str(anim.track_get_path(i)))
				_out.append("  anim '%s' len %.2f tracks %d e.g. %s" % [a, anim.length, anim.get_track_count(), tracks])
	root.free()


func _walk(n: Node, depth: int, bones: bool) -> void:
	var line := "%s%s [%s]" % ["  ".repeat(depth), n.name, n.get_class()]
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		line += " skel=%s surfaces=%d aabb=%s" % [mi.skeleton, mi.mesh.get_surface_count() if mi.mesh else 0, mi.get_aabb()]
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s)
				line += " mat%d=%s" % [s, (m.resource_name + ":" + m.get_class()) if m else "null"]
				if m is StandardMaterial3D:
					line += " tex=%s" % [(m as StandardMaterial3D).albedo_texture.resource_path if (m as StandardMaterial3D).albedo_texture else "none"]
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			var shapes: Array = []
			for b in range(am.get_blend_shape_count()):
				shapes.append(str(am.get_blend_shape_name(b)))
			line += " blendshapes=%d %s" % [shapes.size(), shapes]
			var weights: Array = []
			for b in range(am.get_blend_shape_count()):
				weights.append(mi.get_blend_shape_value(b))
			line += " weights=%s" % [weights]
		if mi.skin:
			line += " skin_binds=%d bind0=%s" % [mi.skin.get_bind_count(), mi.skin.get_bind_name(0)]
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		line += " bones=%d" % sk.get_bone_count()
		if bones:
			var names: Array = []
			for i in range(sk.get_bone_count()):
				names.append(sk.get_bone_name(i))
			line += " " + str(names)
	_out.append(line)
	for c in n.get_children():
		_walk(c, depth + 1, bones)
