@tool
extends Node
## Carves a leg piece off the soldier rig and saves it as greaves_leather.res.
##
## The same trick build_armor_meshes.gd uses for the chest pieces — cut the triangles one bone
## dominates, rebake into that bone's space, pin every vertex to one flat cell of the colormap
## atlas — but for a leg, and written as its own one-off rather than as another variant in that
## tool. Pointing that tool at a leg bone would have re-saved armor_heavy, armor_leather and
## armor_leather_dark as LEGS, since it writes one file per entry in its VARIANTS list.
##
## Run once; the .res it produces is what resources/items/leather_greaves.tres points at. Kept
## in the repo so the mesh can be regenerated rather than being an artefact nobody can rebuild.

const GLB := "res://assets/models/kenney/mini-arena/character-soldier.glb"
const OUT := "res://assets/models/kenney/mini-arena/greaves_leather.res"
## Leather brown, the same atlas cell build_armor_meshes.gd paints armor_leather with, so a
## greave and a leather jerkin look like they came out of the same tannery.
const UV := Vector2(0.718750, 0.975000)
## One leg, not both: an icon of a single greave reads better at 128 pixels than a disembodied
## pair, and the pair would be two shells with a gap of nothing between them.
const CUT_BONE := "leg-left"


func _ready() -> void:
	var glb: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(glb)
	await get_tree().process_frame

	var skel := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	var mi := glb.find_child("body-mesh", true, false) as MeshInstance3D
	var src := mi.mesh as ArrayMesh
	var a: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per_vert: int = bones.size() / verts.size()

	var bone_idx := skel.find_bone(CUT_BONE)
	if bone_idx < 0:
		print("[greaves] no bone named '%s'" % CUT_BONE)
		return
	var to_bone := skel.get_bone_global_pose(bone_idx).affine_inverse()

	# Per-triangle, not per-vertex, so the shell stays watertight where weights blend at the hip.
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if _dominant_bone(idx, t, bones, weights, per_vert) == bone_idx:
			for e in range(3):
				keep.append(idx[t + e])
	print("[greaves] kept tris=%d" % (keep.size() / 3))

	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	for vi in keep:
		if not remap.has(vi):
			remap[vi] = order.size()
			order.append(vi)
		new_idx.append(remap[vi])

	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	for vi in order:
		ov.append(to_bone * verts[vi])
		on.append((to_bone.basis * norms[vi]).normalized())
		ouv.append(UV)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_INDEX] = new_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, src.surface_get_material(0))
	print("[greaves] verts=%d save=%d aabb=%s" % [
		ov.size(), ResourceSaver.save(mesh, OUT), mesh.get_aabb()])
	get_tree().quit()


func _dominant_bone(idx: PackedInt32Array, t: int, bones: PackedInt32Array,
		weights: PackedFloat32Array, per_vert: int) -> int:
	var tally := {}
	for e in range(3):
		var vi: int = idx[t + e]
		for b in range(per_vert):
			var w: float = weights[vi * per_vert + b]
			if w > 0.001:
				var bi: int = bones[vi * per_vert + b]
				tally[bi] = (tally[bi] + w) if tally.has(bi) else w
	var best := -1
	var best_w := 0.0
	for bi in tally:
		if tally[bi] > best_w:
			best_w = tally[bi]
			best = bi
	return best
