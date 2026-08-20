extends Node3D
## Editor tool: cuts a wearable-looking cuirass out of the Kenney soldier's body
## mesh and writes one variant per armour material, so dropped armour has real
## geometry instead of the coloured placeholder box.
##
## Run it by playing tools/build_armor_meshes.tscn (summer_play), then read the
## console. It only writes .res files — nothing else in the project is touched.
##
## WHY THIS APPROACH
## The project ships no armour model (checked the Synty PolygonDungeon pack and
## the Kenney sets — chests, crates and a weapon rack, but no torso armour). The
## body mesh is one connected shell, so unlike the head it cannot be split by
## topology; it IS cleanly separable by skin weights though, and the triangles
## whose dominant bone is `torso` form exactly a sleeveless chest piece.
##
## Colour comes from repainting UVs onto flat cells of the shared colormap atlas
## rather than from new textures or flat material overrides, so the result stays
## on-palette with the rest of the game.
##
## Re-run safe: geometry is always read from the pristine .glb.

const GLB := "res://assets/models/kenney/mini-arena/character-soldier.glb"
const OUT_DIR := "res://assets/models/kenney/mini-arena/"

## Cells of the shared colormap atlas (see .summer/AGENTS.md). Each entry is
## output-name -> UV to paint that variant with; every vertex gets the same UV, so
## the variant renders as one flat colour.
##
## Parts of the atlas are smooth gradient ramps rather than flat cells, so a UV
## rounding half a pixel either way can change the colour. The dark-brown entry is
## therefore given as an exact texel CENTRE — (px + 0.5) / 512 — which pins the
## sample to one texel and survives bilinear filtering. Prefer that form when
## adding variants; verify the sampled colour after regenerating.
const VARIANTS := {
	"armor_heavy": Vector2(0.343750, 0.882944),               # steel blue-grey (0.42, 0.44, 0.53)
	"armor_leather": Vector2(0.718750, 0.975000),             # leather brown   (0.71, 0.40, 0.26)
	"armor_leather_dark": Vector2(419.5 / 512.0, 492.5 / 512.0),  # dark brown  (0.55, 0.33, 0.26)
}

## Bone whose triangles form the chest piece.
@export var cut_bone := "torso"


func _ready() -> void:
	var glb: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(glb)
	# Bone poses are only valid once the skeleton is in the tree and processed.
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

	var bone_idx := skel.find_bone(cut_bone)
	if bone_idx < 0:
		print("[armor] no bone named '%s'" % cut_bone)
		return
	print("[armor] src verts=%d tris=%d cut_bone=%s(%d)" % [
		verts.size(), idx.size() / 3, cut_bone, bone_idx])

	# Rebake into the cut bone's space and drop skinning: the result is a static
	# prop, not part of a rig.
	var to_bone := skel.get_bone_global_pose(bone_idx).affine_inverse()

	# Collect the triangles this bone dominates. Per-triangle (not per-vertex) so
	# the shell stays watertight — a vertex-level test would leave ragged holes
	# along the shoulder and waist seams where weights blend.
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if _dominant_bone(idx, t, bones, weights, per_vert) == bone_idx:
			for e in range(3):
				keep.append(idx[t + e])
	print("[armor] kept tris=%d" % (keep.size() / 3))

	for name in VARIANTS:
		_write_variant(name, VARIANTS[name], src, verts, norms, keep, to_bone)
	print("[armor] DONE")


func _dominant_bone(idx: PackedInt32Array, t: int, bones: PackedInt32Array,
		weights: PackedFloat32Array, per_vert: int) -> int:
	## The bone carrying the most total weight across the triangle's 3 vertices.
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


func _write_variant(out_name: String, uv: Vector2, src: ArrayMesh,
		verts: PackedVector3Array, norms: PackedVector3Array,
		keep: PackedInt32Array, to_bone: Transform3D) -> void:
	## Rebuild the kept triangles as a standalone mesh, every vertex pinned to the
	## one flat palette cell `uv`.
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
		ouv.append(uv)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_INDEX] = new_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, src.surface_get_material(0))
	var path := OUT_DIR + out_name + ".res"
	print("[armor] %-14s verts=%-4d save=%d aabb=%s" % [
		out_name, ov.size(), ResourceSaver.save(mesh, path), mesh.get_aabb()])
