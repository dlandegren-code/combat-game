extends Node3D
## Dev tool: bakes the Viking Realm hall pieces (assets/vikings/env/*.fbx) into the two forms the
## room builder already uses for the Dungeon pack, so no builder path has to learn about FBX scenes:
##
##   assets/vikings/models/<mesh>.res    every mesh on its own — walls, door, throne, hearth...
##   assets/vikings/prefabs/<name>.tscn  a MeshInstance3D-rooted prefab with the atlas applied,
##                                       for what the builder instantiates whole: floor tiles,
##                                       pillars, and the loot containers. A chest's lid stays a
##                                       child named *_Lid on its authored hinge, which is what
##                                       LootContainer looks for; a lock rides on the lid.
##
## The pack's meshes arrive with an untextured BaseMAT; everything here uses its 01_A atlas.
## Play tools/build_viking_kit.tscn; it writes .summer/local/viking_kit.txt and quits. Safe to
## re-run: it only ever reads the FBX and overwrites its own outputs.

const SRC := "res://assets/vikings/env/"
const MODELS := "res://assets/vikings/models/"
const PREFABS := "res://assets/vikings/prefabs/"
const MAT := "res://assets/vikings/viking_mat_01_A.tres"
## Pieces the builder instantiates whole rather than placing as a mesh.
## Pieces drawn with something other than the atlas: the hall floor's UVs cover the whole 0..1
## square once per module, laid out for the pack's tiling plank texture.
const OWN_MATERIAL := {"SM_Bld_Base_Floor_01": "res://assets/vikings/viking_floor_mat.tres"}
## Pieces dressed with something from another file, baked into the prefab as extra meshes:
## [source scene, local position, local rotation in degrees]. The rack stands a sword, a spear
## and an axe in it — the pack's rack is an empty frame.
const WEP := "res://assets/vikings/weapons/"
const DECOR := {
	"SM_Prop_Weapon_Rack_01": [
		[WEP + "SM_Wep_Axe_01.fbx", Vector3(-0.45, 0.22, 0.26), Vector3(8, 0, 0)],
		[WEP + "SM_Wep_Spear_01.fbx", Vector3(0.0, 0.95, 0.3), Vector3(7, 0, 0)],
		[WEP + "SM_Wep_Sword_Short_01.fbx", Vector3(0.42, 1.06, 0.3), Vector3(97, 0, 0)],
	],
}
const PREFAB_PIECES := ["SM_Bld_Base_Floor_01", "SM_Bld_Pillar_02", "SM_Prop_Chest_01",
	"SM_Prop_Barrel_01", "SM_Prop_Barrel_03", "SM_Prop_Mead_Barrel_01", "SM_Gen_Prop_Crate_02",
	"SM_Gen_Prop_Crate_03", "SM_Prop_Weapon_Rack_01"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODELS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREFABS))
	var mat: Material = load(MAT)
	var out: Array = []
	for f in DirAccess.get_files_at(SRC):
		if not f.ends_with(".fbx"):
			continue
		var base := f.get_basename()
		var root := (load(SRC + f) as PackedScene).instantiate() as Node3D
		# In the tree, so global_transform means something: the parts' offsets come from it.
		add_child(root)
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		for mi in meshes:
			var path: String = MODELS + String(mi.name) + ".res"
			var err := ResourceSaver.save((mi as MeshInstance3D).mesh, path)
			out.append("%s -> %s (%s)" % [base, path.get_file(), error_string(err)])
		if PREFAB_PIECES.has(base):
			var piece_mat: Material = load(OWN_MATERIAL[base]) if OWN_MATERIAL.has(base) else mat
			out.append("  prefab %s: %s" % [base, error_string(_save_prefab(base, root, meshes, piece_mat))])
		root.free()
	var file := FileAccess.open("res://.summer/local/viking_kit.txt", FileAccess.WRITE)
	file.store_string("\n".join(out))
	file.close()
	get_tree().quit()


func _save_prefab(base: String, root: Node3D, meshes: Array, mat: Material) -> int:
	var body: MeshInstance3D = null
	for mi in meshes:
		if mi.name == base:
			body = mi
	if body == null:
		body = meshes[0]
	var body_xf: Transform3D = root.global_transform.affine_inverse() * body.global_transform
	var top := MeshInstance3D.new()
	top.name = base
	top.mesh = load(MODELS + String(body.name) + ".res")
	top.material_override = mat
	var lid: MeshInstance3D = null
	var rest: Array = []
	for mi in meshes:
		if mi == body:
			continue
		var part := MeshInstance3D.new()
		part.name = String(mi.name)
		# The suffix LootContainer finds a lid by.
		if part.name.contains("_Lid"):
			part.name = base + "_Lid"
			lid = part
		part.mesh = load(MODELS + String(mi.name) + ".res")
		part.material_override = mat
		part.transform = body_xf.affine_inverse() * (root.global_transform.affine_inverse() * mi.global_transform)
		rest.append(part)
	for part in rest:
		if part == lid:
			top.add_child(part)
	for part in rest:
		if part == lid:
			continue
		# A lock or latch is fixed to the lid, so it lifts with it.
		if lid != null and (part.name.contains("Lock") or part.name.contains("Latch")):
			part.transform = lid.transform.affine_inverse() * part.transform
			lid.add_child(part)
		else:
			top.add_child(part)
	for d in DECOR.get(base, []):
		var src := (load(d[0]) as PackedScene).instantiate()
		var wmi := src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var mesh_path: String = MODELS + String(wmi.name) + ".res"
		ResourceSaver.save(wmi.mesh, mesh_path)
		src.free()
		var part := MeshInstance3D.new()
		part.name = mesh_path.get_file().get_basename()
		part.mesh = load(mesh_path)
		part.material_override = mat
		part.position = d[1]
		part.rotation_degrees = d[2]
		top.add_child(part)
	for n in top.find_children("*", "", true, false):
		n.owner = top
	var ps := PackedScene.new()
	ps.pack(top)
	var err := ResourceSaver.save(ps, PREFABS + base + ".tscn")
	top.free()
	return err
