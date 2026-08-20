extends Node3D
## Editor tool: splits character-male-d's body mesh into two surfaces — legs, and
## everything else — so the legs can carry their own material.
##
## Writes assets/models/kenney/mini-characters-1/archer_body_split.res.
## Run it by playing tools/build_archer_body_split.tscn (summer_play).
##
## WHY TWO SURFACES AND NOT A UV REPAINT
## The armour and hair tools recolour by repainting UVs onto flat cells of the shared
## colormap atlas. That does not work here: the archer's body-mesh is driven by
## `archer_body.tres` -> `archer_leather_albedo.png`, and that image is 98% two
## near-identical dark shades, so every UV lands on the same colour — there is no
## distinct region to point the legs at.
##
## A mesh can only take one material per SURFACE, so giving the legs a different
## colour means giving them their own surface. Surface 0 is torso + arms, surface 1 is
## the legs; `CharacterSkin` then assigns a material to each via
## set_surface_override_material.
##
## Re-run safe: geometry is always read from the pristine .glb.

const GLB := "res://assets/models/kenney/mini-characters-1/character-male-d.glb"
const OUT := "res://assets/models/kenney/mini-characters-1/archer_body_split.res"

## Bones whose triangles become the leg surfaces.
const LEG_BONES := ["leg-left", "leg-right"]

## Leg triangles below this height become a third surface, for boots. Legs run
## y 0 .. 0.176 and their triangle centroids cluster densely at 0 .. 0.02 (the foot),
## so 0.06 puts the boot top around mid-calf.
@export var boot_cut_y := 0.06


func _ready() -> void:
	var glb: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(glb)
	await get_tree().process_frame

	var skel := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	var mi := glb.find_child("body-mesh", false, false) as MeshInstance3D
	if mi == null:
		mi = glb.find_child("body-mesh", true, false) as MeshInstance3D
	var src := mi.mesh as ArrayMesh
	var a: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per_vert: int = bones.size() / verts.size()
	print("[split] src surfaces=%d verts=%d tris=%d" % [
		src.get_surface_count(), verts.size(), idx.size() / 3])

	var leg_ids := {}
	for n in LEG_BONES:
		var b := skel.find_bone(n)
		if b >= 0:
			leg_ids[b] = true
	print("[split] leg bone ids=%s" % str(leg_ids.keys()))

	# Split per TRIANGLE by dominant bone, matching how the armour cuirass was cut: a
	# per-vertex test would leave ragged edges at the hip where weights blend.
	var upper := PackedInt32Array()
	var legs := PackedInt32Array()
	var boots := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var dst := upper
		if leg_ids.has(_dominant_bone(idx, t, bones, weights, per_vert)):
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			dst = boots if c.y < boot_cut_y else legs
		for e in range(3):
			dst.append(idx[t + e])
	print("[split] tris: upper=%d legs=%d boots=%d" % [
		upper.size() / 3, legs.size() / 3, boots.size() / 3])

	var mesh := ArrayMesh.new()
	for tris in [upper, legs, boots]:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _subset(a, tris, per_vert))
	# Every surface keeps the source material as its default; CharacterSkin overrides
	# them per surface at runtime.
	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, src.surface_get_material(0))
	print("[split] out surfaces=%d save=%d" % [
		mesh.get_surface_count(), ResourceSaver.save(mesh, OUT)])
	for s in range(mesh.get_surface_count()):
		print("[split] surface%d aabb=%s" % [s, _surface_aabb(mesh, s)])
	print("[split] DONE")


func _surface_aabb(mesh: ArrayMesh, s: int) -> AABB:
	var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var box := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		box = box.expand(v)
	return box


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


func _subset(a: Array, tris: PackedInt32Array, per_vert: int) -> Array:
	## Rebuild surface arrays for just the referenced vertices, remapping indices and
	## carrying every per-vertex channel (including skinning) across unchanged.
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	for vi in tris:
		if not remap.has(vi):
			remap[vi] = order.size()
			order.append(vi)
		new_idx.append(remap[vi])

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)

	var src_v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nv := PackedVector3Array()
	for vi in order:
		nv.append(src_v[vi])
	out[Mesh.ARRAY_VERTEX] = nv

	if a[Mesh.ARRAY_NORMAL] != null:
		var src_n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var nn := PackedVector3Array()
		for vi in order:
			nn.append(src_n[vi])
		out[Mesh.ARRAY_NORMAL] = nn

	if a[Mesh.ARRAY_TEX_UV] != null:
		var src_uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var nuv := PackedVector2Array()
		for vi in order:
			nuv.append(src_uv[vi])
		out[Mesh.ARRAY_TEX_UV] = nuv

	if a[Mesh.ARRAY_BONES] != null:
		var src_b: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var src_w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var nb := PackedInt32Array()
		var nw := PackedFloat32Array()
		for vi in order:
			for b in range(per_vert):
				nb.append(src_b[vi * per_vert + b])
				nw.append(src_w[vi * per_vert + b])
		out[Mesh.ARRAY_BONES] = nb
		out[Mesh.ARRAY_WEIGHTS] = nw

	out[Mesh.ARRAY_INDEX] = new_idx
	return out
