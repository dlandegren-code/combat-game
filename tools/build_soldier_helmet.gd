extends Node3D
## Editor tool: splits the Kenney soldier's head into a removable helmet plus a
## bare head underneath, and writes both meshes to res://assets/models/kenney/mini-arena/.
##
## Run it by playing tools/build_soldier_helmet.tscn (summer_play), then read the
## console. It only writes .res files — nothing else in the project is touched.
##
## WHY THIS EXISTS
## The soldier's head is ONE skinned surface with no sub-nodes, so the helmet
## cannot be hidden by toggling visibility. It has to be split geometrically.
## The head is built from 9 connected components; sampling colormap.png through
## each component's UVs shows what they are:
##
##   comp 28  127 verts  silver (0.87,0.87,0.94)  <- the SKULL *is* the helmet
##   comp 58  160 verts  white                    <- the crest / plume on top
##   comp 80/85 42 each  skin   (0.86,0.62,0.47)  <- ears
##   comp 94/102/110/138/144                      <- eye, brow and mouth quads
##
## So "the helmet" is the skull shell, not just the crest, and there is no
## skin-coloured skull hiding underneath — the bare head has to be repainted.
##
## Re-run safe: geometry is always read from the pristine .glb, never from the
## outputs, so running this twice produces the same result.

## Pristine source geometry. Deliberately NOT soldier_model.tscn — that scene
## overrides head-mesh with this tool's own output, which would compound.
const GLB := "res://assets/models/kenney/mini-arena/character-soldier.glb"
const COLORMAP := "res://assets/models/kenney/mini-arena/Textures/colormap.png"
const OUT_HELM := "res://assets/models/kenney/mini-arena/soldier_helmet.res"
const OUT_HEAD := "res://assets/models/kenney/mini-arena/soldier_head_bare.res"

## Skin swatch to repaint the bare skull with. This is the UV the model's own ear
## components use, so the head stays on-palette instead of needing a new texture.
@export var skin_uv := Vector2(0.96875, 0.875)

@export_group("Helmet fit")
## How far the shell floats off the skull, in mesh units (x1.6 on screen). Big
## enough to avoid z-fighting, small enough not to read as a gap.
@export var shell_offset := 0.012
## Face opening. The shell sits OUTSIDE the skull, but the eye/brow/mouth quads
## are flush WITH it, so a closed shell would render in front of them and hide
## the face. These cuts keep the face open: shell faces are kept above
## y_top_cut all the way round, plus anything behind z_back down to y_back_cut.
## For a fully closed great-helm, set y_top_cut and y_back_cut to 0.0.
@export var y_top_cut := 0.53
@export var z_back := 0.05
@export var y_back_cut := 0.40

@export_group("Debug")
## Print each connected component with the palette colour it samples.
@export var log_components := true

var _parent := PackedInt32Array()


func _ready() -> void:
	var glb: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(glb)
	# Bone poses are only valid once the skeleton is in the tree and processed.
	await get_tree().process_frame

	var skel := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	var head_bone := skel.find_bone("head")
	var mi := glb.find_child("head-mesh", true, false) as MeshInstance3D
	var src := mi.mesh as ArrayMesh

	var a: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var per_vert: int = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
	print("[helm] src verts=%d tris=%d bones_per_vert=%d" % [
		verts.size(), idx.size() / 3, per_vert])

	var weld := _weld_positions(verts)
	_union_triangles(idx, weld)
	var roots := _classify(verts, uvs, weld)
	var crest_root: int = roots.crest
	var skull_root: int = roots.skull

	_build_helmet(skel, head_bone, src, a, weld, crest_root, skull_root)
	_build_head(src, a, per_vert, weld, crest_root, skull_root)
	print("[helm] DONE")


# --- Connected components -----------------------------------------------------

func _root(i: int) -> int:
	while _parent[i] != i:
		i = _parent[i]
	return i


func _weld_positions(verts: PackedVector3Array) -> PackedInt32Array:
	## Map each vertex to a shared id per unique position. Without this, UV-seam
	## duplicates sit at the same point but count as separate vertices, which
	## would split a single visual piece into several components.
	var key_of := {}
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	for i in verts.size():
		var v: Vector3 = verts[i]
		var k := "%d_%d_%d" % [roundi(v.x * 10000), roundi(v.y * 10000), roundi(v.z * 10000)]
		if not key_of.has(k):
			key_of[k] = key_of.size()
		weld[i] = key_of[k]
	_parent.resize(key_of.size())
	for i in _parent.size():
		_parent[i] = i
	return weld


func _union_triangles(idx: PackedInt32Array, weld: PackedInt32Array) -> void:
	## Union-find over triangle edges: anything reachable through shared
	## positions ends up in one component.
	for t in range(0, idx.size(), 3):
		var r0 := _root(weld[idx[t]])
		for e in range(1, 3):
			var r := _root(weld[idx[t + e]])
			if r != r0:
				_parent[r] = r0


func _classify(verts: PackedVector3Array, uvs: PackedVector2Array,
		weld: PackedInt32Array) -> Dictionary:
	## The crest is the piece reaching highest up the skull. The skull is the
	## largest of everything else — NOT the largest overall, because the crest
	## actually carries more vertices (160) than the skull does (127).
	var comps := {}
	for i in verts.size():
		var r := _root(weld[i])
		if not comps.has(r):
			comps[r] = {"n": 0, "aabb": AABB(verts[i], Vector3.ZERO), "uv": Vector2.ZERO}
		comps[r]["n"] += 1
		comps[r]["aabb"] = (comps[r]["aabb"] as AABB).expand(verts[i])
		comps[r]["uv"] += uvs[i]

	var img: Image = null
	if log_components:
		img = (load(COLORMAP) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()

	var crest := -1
	var skull := -1
	for r in comps:
		var uv: Vector2 = (comps[r]["uv"] as Vector2) / float(comps[r]["n"])
		if img:
			var px := Vector2i(
				clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1),
				clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
			print("[helm] comp=%d verts=%d aabb=%s color=%s" % [
				r, comps[r]["n"], comps[r]["aabb"], img.get_pixelv(px)])
		if crest < 0 or (comps[r]["aabb"] as AABB).end.y > (comps[crest]["aabb"] as AABB).end.y:
			crest = r
	for r in comps:
		if r != crest and (skull < 0 or comps[r]["n"] > comps[skull]["n"]):
			skull = r
	print("[helm] crest=%d (verts=%d) skull=%d (verts=%d)" % [
		crest, comps[crest]["n"], skull, comps[skull]["n"]])
	return {"crest": crest, "skull": skull}


func _smooth_normals(verts: PackedVector3Array, norms: PackedVector3Array,
		weld: PackedInt32Array) -> Dictionary:
	## One averaged normal per welded position. Offsetting along the raw
	## per-vertex normals would pull the shell apart at the model's hard edges,
	## because coincident vertices there point in different directions.
	var acc := {}
	for i in verts.size():
		var w := weld[i]
		acc[w] = (acc[w] if acc.has(w) else Vector3.ZERO) + norms[i]
	for w in acc:
		acc[w] = (acc[w] as Vector3).normalized()
	return acc


# --- Outputs ------------------------------------------------------------------

func _build_helmet(skel: Skeleton3D, head_bone: int, src: ArrayMesh, a: Array,
		weld: PackedInt32Array, crest_root: int, skull_root: int) -> void:
	## Silver shell (pushed clear of the head, face opening cut) + the crest
	## verbatim, both rebaked into head-bone space with skinning stripped, so the
	## result hangs off a BoneAttachment3D at identity and lands exactly where the
	## built-in helmet sat. The crest is weighted to the head bone alone, so a
	## rigid attachment reproduces it exactly rather than approximating.
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var smooth := _smooth_normals(verts, norms, weld)
	var to_bone := skel.get_bone_global_pose(head_bone).affine_inverse()

	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oi := PackedInt32Array()
	var crest_tris := 0
	var shell_tris := 0

	for t in range(0, idx.size(), 3):
		var root := _root(weld[idx[t]])
		var is_crest := root == crest_root
		if not is_crest and root != skull_root:
			continue
		var push := 0.0
		if is_crest:
			crest_tris += 1
		else:
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			if not (c.y >= y_top_cut or (c.z <= z_back and c.y >= y_back_cut)):
				continue
			shell_tris += 1
			push = shell_offset
		for e in range(3):
			var vi: int = idx[t + e]
			var n: Vector3 = smooth[weld[vi]]
			oi.append(ov.size())
			ov.append(to_bone * (verts[vi] + n * push))
			on.append((to_bone.basis * (n if push > 0.0 else norms[vi])).normalized())
			ouv.append(uvs[vi])  # keep the original silver / crest swatches

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_INDEX] = oi
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, src.surface_get_material(0))
	print("[helm] helmet crest_tris=%d shell_tris=%d save=%d aabb=%s" % [
		crest_tris, shell_tris, ResourceSaver.save(mesh, OUT_HELM), mesh.get_aabb()])


func _build_head(src: ArrayMesh, a: Array, per_vert: int, weld: PackedInt32Array,
		crest_root: int, skull_root: int) -> void:
	## Everything except the crest, with the skull repainted as skin. Stays in
	## mesh space and keeps its bones/weights, so it drops straight into the
	## skeleton as head-mesh and animates as before.
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]

	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var ob := PackedInt32Array()
	var ow := PackedFloat32Array()
	var oi := PackedInt32Array()
	var skull_tris := 0
	var other_tris := 0

	for t in range(0, idx.size(), 3):
		var root := _root(weld[idx[t]])
		if root == crest_root:
			continue
		var is_skull := root == skull_root
		if is_skull:
			skull_tris += 1
		else:
			other_tris += 1
		for e in range(3):
			var vi: int = idx[t + e]
			oi.append(ov.size())
			ov.append(verts[vi])
			on.append(norms[vi])
			# The skull WAS the helmet, so it must be repainted now it is bare —
			# otherwise removing the helmet leaves a silver head.
			ouv.append(skin_uv if is_skull else uvs[vi])
			for b in range(per_vert):
				ob.append(bones[vi * per_vert + b])
				ow.append(weights[vi * per_vert + b])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_BONES] = ob
	arrays[Mesh.ARRAY_WEIGHTS] = ow
	arrays[Mesh.ARRAY_INDEX] = oi
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, src.surface_get_material(0))
	print("[helm] head skull_tris=%d other_tris=%d save=%d aabb=%s" % [
		skull_tris, other_tris, ResourceSaver.save(mesh, OUT_HEAD), mesh.get_aabb()])
