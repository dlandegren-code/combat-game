extends RefCounted
class_name SyntyModel
## Turns a raw imported Synty FBX into something usable in a scene.
##
## The meadow pack ships as source FBX rather than as a Godot package, which means two things
## have to be fixed at instance time:
##
##   LODs. Synty bakes each level of detail as its OWN mesh — a birch arrives as
##   _LOD0.._LOD3 plus three more for its branches, all sitting in the same place. Instanced
##   as-is, every tree is four trees stacked inside each other: wrong silhouette, wrong
##   alpha, and four times the triangles. Everything but LOD0 is deleted.
##
##   Materials. The pack's materials are Unity shaders (wind, triplanar rock, billboard tree
##   cards) that carry no meaning in Godot, so the FBX arrives untextured. Each mesh is
##   painted by matching its NAME against the pack's own material list — see MATERIALS, whose
##   keys came out of MaterialList_PNB_Meadow_Forest.txt rather than from guesswork.
##
## The farm pack needs none of this: it ships as a Godot package with its materials already
## assigned, so load() is enough there.

const MEADOW_MODELS := "res://assets/Synty/PolygonMeadow/Models/"
const MEADOW_MATS := "res://assets/Synty/PolygonMeadow/Materials/"

## Longest match wins, so "Tree_Birch" beats "Tree" and "_Branches" beats the trunk rule.
## Left of the arrow is a fragment of the MESH name; right is the material to paint it with.
## HOW THE MAPPING WAS ESTABLISHED
## The pack's material list names a material per mesh but not a FILE, and its textures are not
## self-explanatory: treeBirch_01 looks like a billboard card and is in fact the tree's whole
## unwrap, canopy and trunk both. What settled it was reading the UVs off the meshes
## (tools/inspect_model.gd): a surface whose UVs sit in a small cell — the cabin's are
## 0.016..0.104 — is painted from the palette atlas, and one that spans the full 0..1, as
## every tree LOD0 does, has a sheet of its own. Branch cards have theirs too (bare twigs).
const MATERIALS := {
	"Tree_Birch_01_Branches": "meadow_branches_2",
	"Tree_Birch_02_Branches": "meadow_branches_2",
	"Tree_Birch_03_Branches": "meadow_branches_2",
	"Tree_Birch": "meadow_birch",
	"Tree_Meadow_01_Branches": "meadow_branches",
	"Tree_Meadow_02_Branches": "meadow_branches",
	"Tree_Meadow": "meadow_tree",
	"Bush": "meadow_tree",
	"Grass_Large": "meadow_grass_tall",
	"Grass_Med": "meadow_grass_med",
	"Grass": "meadow_grass_med",
	"Flowers_Flat": "meadow_flowers",
	"Ground_Cover": "meadow_groundcover",
	"Rock": "meadow_rock",
	"Background_Hill": "meadow_rock",
}

## Anything not matched above is a hard surface — a building, a fence, a crate — and the pack
## paints all of those with its one atlas.
const DEFAULT_MATERIAL := "meadow_atlas"

static var _cache := {}


static func meadow(model_name: String, lod: int = 0) -> Node3D:
	## Instance a meadow model by name, LODs pruned and materials applied.
	##
	## `lod` picks WHICH level to keep. A birch's LOD0 is 20,000 verts and its LOD2 is 5,700
	## for the same silhouette at distance — which is the difference between a forest that
	## closes the horizon and a forest that halves the frame rate. Synty baked these levels
	## and then the pack shipped them as separate meshes, so using them is just a matter of
	## keeping a different one.
	var packed := _load(MEADOW_MODELS + model_name + ".fbx")
	if packed == null:
		push_error("SyntyModel: no such meadow model: %s" % model_name)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	_strip_lods(node, lod)
	_paint(node)
	return node


static func _load(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path]
	var packed := load(path) as PackedScene
	# Cached because the town plants dozens of trees from a handful of files, and re-loading
	# the same FBX per tree is the difference between a scene that builds instantly and one
	# that hitches.
	_cache[path] = packed
	return packed


static func _strip_lods(root: Node, keep: int) -> void:
	var wanted := "_LOD%d" % keep
	var kept_any := false
	for child in root.get_children():
		_strip_lods(child, keep)
		if String(child.name).ends_with(wanted):
			kept_any = true
	for child in root.get_children():
		var name := String(child.name)
		if not name.contains("_LOD"):
			continue
		# Fall back to LOD0 for a model that has no level that deep — the bushes stop at LOD1.
		var keep_this := name.ends_with(wanted) if kept_any else name.ends_with("_LOD0")
		if not keep_this:
			root.remove_child(child)
			child.queue_free()


static func _paint(node: Node) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		var material := _material_for(String(mesh_node.name))
		if material != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_paint(child)


static func _material_for(mesh_name: String) -> Material:
	var best_key := ""
	for key in MATERIALS:
		if mesh_name.contains(key) and key.length() > best_key.length():
			best_key = key
	var mat_name: String = MATERIALS[best_key] if best_key != "" else DEFAULT_MATERIAL
	return _load_material(mat_name)


static func _load_material(mat_name: String) -> Material:
	var path := MEADOW_MATS + mat_name + ".tres"
	if _cache.has(path):
		return _cache[path]
	var mat := load(path) as Material
	if mat == null:
		push_error("SyntyModel: missing material %s" % path)
	_cache[path] = mat
	return mat


static func find_child_containing(root: Node, fragment: String) -> Node3D:
	## The one part of a model something needs to move on its own — the windmill's blades,
	## for instance, which are their own mesh precisely so they can turn.
	if String(root.name).contains(fragment):
		return root as Node3D
	for child in root.get_children():
		var found := find_child_containing(child, fragment)
		if found != null:
			return found
	return null
