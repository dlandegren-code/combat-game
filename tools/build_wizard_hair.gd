extends Node3D
## Editor tool: repaints the wizard's hair grey with darker streaks, writing
## assets/models/kenney/mini-characters-1/wizard_head_grey.res.
##
## Run it by playing tools/build_wizard_hair.tscn (summer_play), then read the
## console. It writes one .res and touches nothing else.
##
## WHY
## character-male-d ships with reddish-brown hair, and the head is ONE skinned
## surface — so the hair cannot be recoloured with a material override without
## also recolouring the face, ears and eyes. Repainting its UVs is the only way to
## touch just the hair.
##
## The output is applied via a head-mesh override on wizard_model.tscn ONLY, so the
## Archer (male_d_model.tscn, same .glb) keeps its original hair.
##
## The long strands that make the hair *long* are separate — they are built at
## runtime by CharacterSkin._apply_long_hair(). Keep the greys here in step with
## `hair_color_main` / `hair_color_streak` there.
##
## Re-run safe: geometry is always read from the pristine .glb.

const GLB := "res://assets/models/kenney/mini-characters-1/character-male-d.glb"
const OUT := "res://assets/models/kenney/mini-characters-1/wizard_head_grey.res"

## Flat colormap cells, as exact texel centres — (px + 0.5) / 512 — so the sample
## cannot drift onto a neighbouring cell. Sampled from this rig's own atlas.
const UV_GREY := Vector2(290.5 / 512.0, 413.5 / 512.0)     # light silver (0.94, 0.94, 0.97)
const UV_STREAK := Vector2(34.5 / 512.0, 397.5 / 512.0)    # charcoal     (0.27, 0.26, 0.30)

## Streaks run vertically around the head. Even wedges get silver, odd get charcoal.
@export var stripe_count := 8

## Drop the forehead quiff — the fin of hair that sticks up and forward over the brow.
## It reads fine on the Archer's short hair but fights the wizard's long hair.
##
## It is a flat fan of 9 triangles sitting at z = 0.168, i.e. PROUD of the skull's own
## front face at z = 0.158, while every other hair triangle sits at z <= 0.154 and
## tops out at exactly 0.671. So "centroid in front of the skull" isolates it exactly.
@export var drop_forehead_tuft := true
@export var tuft_cut_z := 0.160

var _parent := PackedInt32Array()


func _root(i: int) -> int:
	while _parent[i] != i:
		i = _parent[i]
	return i


func _ready() -> void:
	var glb: Node3D = (load(GLB) as PackedScene).instantiate()
	add_child(glb)
	await get_tree().process_frame

	var skel := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	var mi := skel.find_child("head-mesh", false, false) as MeshInstance3D
	var src := mi.mesh as ArrayMesh
	var a: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per_vert: int = bones.size() / verts.size()
	print("[hair] src verts=%d tris=%d" % [verts.size(), idx.size() / 3])

	# --- Find the hair: the component reaching highest up the skull. Same heuristic
	# that isolates the soldier's crest. Colour can't be used — the ginger hair and
	# the skin tones overlap in the atlas.
	var weld := _weld(verts)
	for t in range(0, idx.size(), 3):
		var r0 := _root(weld[idx[t]])
		for e in range(1, 3):
			var r := _root(weld[idx[t + e]])
			if r != r0:
				_parent[r] = r0
	var comps := {}
	for i in verts.size():
		var r := _root(weld[i])
		if comps.has(r):
			comps[r] = (comps[r] as AABB).expand(verts[i])
		else:
			comps[r] = AABB(verts[i], Vector3.ZERO)
	var hair := -1
	for r in comps:
		if hair < 0 or (comps[r] as AABB).end.y > (comps[hair] as AABB).end.y:
			hair = r
	var hair_box: AABB = comps[hair]
	print("[hair] components=%d hair_root=%d aabb=%s" % [comps.size(), hair, hair_box])
	var centre: Vector3 = hair_box.get_center()

	# --- Rebuild with ONE UV PER TRIANGLE for the hair.
	# Per-vertex striping would let a triangle straddling a stripe boundary
	# interpolate its UV between two distant atlas cells, smearing unrelated colours
	# across the face of it. Emitting fresh vertices per triangle keeps each flat.
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var ob := PackedInt32Array()
	var ow := PackedFloat32Array()
	var oi := PackedInt32Array()
	var silver := 0
	var charcoal := 0

	var dropped := 0
	for t in range(0, idx.size(), 3):
		var is_hair := _root(weld[idx[t]]) == hair
		var uv_flat := Vector2.ZERO
		if is_hair:
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			if drop_forehead_tuft and c.z > tuft_cut_z:
				dropped += 1
				continue
			var ang := atan2(c.x - centre.x, c.z - centre.z)      # -PI..PI
			var wedge := int(floor((ang + PI) / TAU * stripe_count)) % stripe_count
			if wedge % 2 == 0:
				uv_flat = UV_GREY
				silver += 1
			else:
				uv_flat = UV_STREAK
				charcoal += 1
		for e in range(3):
			var vi: int = idx[t + e]
			oi.append(ov.size())
			ov.append(verts[vi])
			on.append(norms[vi])
			ouv.append(uv_flat if is_hair else uvs[vi])
			for b in range(per_vert):
				ob.append(bones[vi * per_vert + b])
				ow.append(weights[vi * per_vert + b])
	print("[hair] hair tris: silver=%d charcoal=%d (stripes=%d) tuft_dropped=%d" % [
		silver, charcoal, stripe_count, dropped])

	# Dropping triangles can tear a hole in the shell. Count boundary edges (used by
	# exactly one triangle) across the hair before and after the cut: if the tuft was a
	# free-standing fin the count falls, but if it was plugging the cap the count rises
	# and there will be a visible notch at the hairline.
	print("[hair] hair boundary edges: before=%d after=%d" % [
		_boundary_edges(verts, idx, weld, hair, false),
		_boundary_edges(verts, idx, weld, hair, true)])

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
	print("[hair] out verts=%d save=%d aabb=%s" % [
		ov.size(), ResourceSaver.save(mesh, OUT), mesh.get_aabb()])
	print("[hair] DONE")


func _boundary_edges(verts: PackedVector3Array, idx: PackedInt32Array,
		weld: PackedInt32Array, hair: int, apply_cut: bool) -> int:
	## Edges of the hair shell shared by only one triangle. Counted on welded indices
	## so UV seams don't register as holes.
	var use := {}
	for t in range(0, idx.size(), 3):
		if _root(weld[idx[t]]) != hair:
			continue
		if apply_cut:
			var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
			if drop_forehead_tuft and c.z > tuft_cut_z:
				continue
		for e in range(3):
			var x := _root(weld[idx[t + e]])
			var y := _root(weld[idx[t + (e + 1) % 3]])
			var k := "%d_%d" % [min(x, y), max(x, y)]
			use[k] = (use[k] + 1) if use.has(k) else 1
	var open := 0
	for k in use:
		if use[k] == 1:
			open += 1
	return open


func _weld(verts: PackedVector3Array) -> PackedInt32Array:
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
