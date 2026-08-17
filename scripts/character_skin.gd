extends Node3D
## Applies a body material to the instanced character GLB at runtime.
## The .tscn property-override on instanced GLB children is not reliably
## applied at runtime; setting material_override from code guarantees it.
## The head-mesh is left untouched so original facial features are preserved.
## When show_robe is enabled a tapered cylinder mesh is added around the
## upper legs to give a robe/skirt silhouette distinct from other characters.

@export var body_material: Material
@export var show_robe: bool = false
@export var robe_color: Color = Color(0.12, 0.06, 0.28, 1.0)
@export var show_quiver: bool = false

## SM_Arrow_01 runs along its local +Z: head at z = +0.43, fletching at z = -0.47.
const ARROW_HEAD_Z := 0.43
const ARROW_SCALE := 0.42
## Per-arrow (tilt from vertical, heading) in degrees, so the arrows fan out of the
## quiver mouth instead of standing in a single line.
const QUIVER_ARROW_FAN := [Vector2(9.0, 20.0), Vector2(15.0, 250.0)]
## Where the arrow heads rest inside the quiver (cylinder height 0.25 -> floor Y = -0.125).
const ARROW_HEAD_Y := -0.085
const ARROW_HEAD_SPREAD := 0.09

func _ready() -> void:
	call_deferred("_apply_body_material")
	call_deferred("_apply_quiver")

func _apply_body_material() -> void:
	if body_material == null:
		return
	var skeleton := get_node_or_null("character-male-d/character-male-d/Skeleton3D") as Skeleton3D
	var body_mesh := get_node_or_null("character-male-d/character-male-d/Skeleton3D/body-mesh") as MeshInstance3D
	if body_mesh:
		body_mesh.material_override = body_material
	if show_robe and skeleton:
		_add_robe(skeleton)

func _add_robe(skeleton: Skeleton3D) -> void:
	var robe := MeshInstance3D.new()
	robe.name = "Robe"
	var cyl := CylinderMesh.new()
	cyl.height = 0.20
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.22
	cyl.radial_segments = 12
	robe.mesh = cyl
	robe.position = Vector3(0.0, 0.11, -0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = robe_color
	mat.roughness = 0.85
	robe.material_override = mat
	skeleton.add_child(robe)

func _apply_quiver() -> void:
	if not show_quiver:
		return
	var skeleton := get_node_or_null("character-male-d/character-male-d/Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	var socket := BoneAttachment3D.new()
	socket.name = "QuiverSocket"
	socket.bone_name = "torso"
	skeleton.add_child(socket)

	var quiver := MeshInstance3D.new()
	quiver.name = "Quiver"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10
	cyl.bottom_radius = 0.07
	cyl.height = 0.25
	cyl.radial_segments = 10
	quiver.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.22, 0.12, 1.0)
	mat.roughness = 0.9
	quiver.material_override = mat
	quiver.position = Vector3(0.18, -0.02, -0.12)
	quiver.rotation_degrees = Vector3(15, 0, -20)
	socket.add_child(quiver)

	var arrow_mesh: Mesh = load("res://assets/PolygonDungeon/Models/SM_Arrow_01.res") as Mesh
	var synty_mat: Material = load("res://assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres") as Material
	for i in QUIVER_ARROW_FAN.size():
		var fan: Vector2 = QUIVER_ARROW_FAN[i]
		var arrow := MeshInstance3D.new()
		arrow.name = "Arrow" + str(i + 1)
		arrow.mesh = arrow_mesh
		if synty_mat:
			arrow.material_override = synty_mat
		arrow.scale = Vector3.ONE * ARROW_SCALE
		# Children of the quiver so they inherit its tilt. Rotating (90 - tilt) about
		# X stands the +Z shaft up fletching-first; the Y term picks the lean direction.
		arrow.rotation_degrees = Vector3(90.0 - fan.x, fan.y, 0.0)
		# `up` is where the shaft points after that rotation. Walking back along it from
		# the head position places the mesh origin correctly, so every head stays seated
		# on the quiver floor no matter how far the arrow leans.
		var tilt := deg_to_rad(fan.x)
		var head := deg_to_rad(fan.y)
		var up := Vector3(-sin(head) * sin(tilt), cos(tilt), -cos(head) * sin(tilt))
		# Nudge each head away from the lean so the shafts diverge instead of crossing.
		var head_pos := Vector3(-up.x, 0.0, -up.z) * ARROW_HEAD_SPREAD
		head_pos.y = ARROW_HEAD_Y
		arrow.position = head_pos + up * (ARROW_HEAD_Z * ARROW_SCALE)
		quiver.add_child(arrow)
