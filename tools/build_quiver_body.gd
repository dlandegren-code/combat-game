extends Node3D
## Editor tool: bakes the quiver's body cylinder with deliberate UVs.
##
## Writes assets/PolygonDungeon/Models/quiver_body.res, used by
## scenes/items/quiver.tscn — which BOTH the ground pickup and the equipped quiver
## instantiate, so this fixes them together.
##
## WHY
## The body was a procedural CylinderMesh whose UVs span the whole 0..1 square, while
## Dungeon_Material_01_mat points at a texture ATLAS. That stretched the entire atlas
## around the quiver, so going around the circumference ran through unrelated swatches —
## blue-grey (0.33,0.52,0.70), pink (0.74,0.44,0.56), orange (0.86,0.59,0.35), teal
## (0.39,0.59,0.62) — before settling on leather brown. Those read as stripes running
## LENGTHWISE along the mesh: vertical on the worn quiver, horizontal on the pickup
## lying on its side. Same artifact, two orientations.
##
## A PrimitiveMesh's UVs cannot be edited, so the cylinder is baked to an ArrayMesh with
## the UVs replaced: one flat leather cell for the body and a darker cell for the top
## rim. Banding by HEIGHT gives horizontal rings on the worn quiver, which is the
## "sidewise" look, and it stays uniform around the circumference.

const ATLAS := "res://assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"
const OUT := "res://assets/PolygonDungeon/Models/quiver_body.res"

## Must match the cylinder quiver.tscn used, or the quiver changes shape.
const TOP_RADIUS := 0.12
const BOTTOM_RADIUS := 0.08
const HEIGHT := 0.3

## Exact texel centres — (px + 0.5) / 1024 — so a sample cannot drift onto a
## neighbouring swatch.
const UV_LEATHER := Vector2(796.5 / 1024.0, 512.5 / 1024.0)   # (0.60, 0.30, 0.24) leather
## Grey rim, not a darker brown: the old accidental banding showed a blue-grey swatch,
## and that grey detail is what the quiver is meant to read with. Picked as the largest
## flat mid-grey region safely inside the atlas — the only bigger one sits at v 0.004,
## right on the texture edge where filtering can bleed.
const UV_RIM := Vector2(348.5 / 1024.0, 628.5 / 1024.0)       # (0.44, 0.44, 0.44) stone grey

## Fraction of the height, from the top, painted with the rim colour.
@export var rim_fraction := 0.2


func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = TOP_RADIUS
	cyl.bottom_radius = BOTTOM_RADIUS
	cyl.height = HEIGHT
	var a: Array = cyl.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	print("[qbody] source cylinder verts=%d indices=%d aabb=%s" % [
		verts.size(), idx.size(), cyl.get_aabb()])

	# Where the rim band starts, in mesh space (cylinder spans -H/2 .. +H/2).
	var rim_y: float = HEIGHT * 0.5 - HEIGHT * rim_fraction

	# One UV per TRIANGLE, with fresh vertices per triangle. Assigning per vertex would
	# let a triangle straddling the band boundary interpolate between two distant atlas
	# cells, smearing unrelated colours across it — the same trap as the hair streaks.
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oi := PackedInt32Array()
	var rim_tris := 0
	var body_tris := 0

	var tri_count: int = (idx.size() if idx.size() > 0 else verts.size()) / 3
	for t in range(tri_count):
		var vi := [0, 0, 0]
		for e in range(3):
			vi[e] = idx[t * 3 + e] if idx.size() > 0 else t * 3 + e
		var centroid: Vector3 = (verts[vi[0]] + verts[vi[1]] + verts[vi[2]]) / 3.0
		var uv := UV_LEATHER
		if centroid.y >= rim_y:
			uv = UV_RIM
			rim_tris += 1
		else:
			body_tris += 1
		for e in range(3):
			oi.append(ov.size())
			ov.append(verts[vi[e]])
			on.append(norms[vi[e]])
			ouv.append(uv)
	print("[qbody] rim_y=%.3f  rim_tris=%d body_tris=%d" % [rim_y, rim_tris, body_tris])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_INDEX] = oi
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load(ATLAS))
	print("[qbody] out verts=%d save=%d aabb=%s" % [
		ov.size(), ResourceSaver.save(mesh, OUT), mesh.get_aabb()])

	# Confirm only the two intended colours survive.
	var mat: StandardMaterial3D = load(ATLAS)
	var img: Image = mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	var seen := {}
	for uv2 in ouv:
		var c: Color = img.get_pixelv(Vector2i(
			int(uv2.x * img.get_width()), int(uv2.y * img.get_height())))
		seen["(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]] = true
	print("[qbody] distinct colours on body = %s" % str(seen.keys()))
	print("[qbody] DONE")
