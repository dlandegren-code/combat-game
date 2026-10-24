extends Node3D
## Dev tool: one mesh resource (or scene) with a material, from the front and the side, framed by its AABB.
## Writes .summer/local/mesh_front.png and mesh_side.png, then quits.

@export var mesh_path := "res://assets/goblin_camp/SM_Prop_Quiver_01.fbx"
@export var material_path := "res://assets/goblin_camp/goblin_camp_mat_01_A.tres"


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var res: Resource = load(mesh_path)
	var holder: Node3D
	if res is PackedScene:
		holder = (res as PackedScene).instantiate()
	else:
		holder = MeshInstance3D.new()
		(holder as MeshInstance3D).mesh = res
	add_child(holder)
	var box := AABB()
	var first := true
	for n in [holder] + holder.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D:
			n.material_override = load(material_path)
			var b: AABB = n.global_transform * n.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	var c := box.get_center()
	var r := box.size.length()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for shot in [["front", Vector3(0, 0, -1)], ["side", Vector3(1, 0, 0)]]:
		cam.position = c + (shot[1] as Vector3) * r * 1.2
		cam.look_at(c, Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://.summer/local/mesh_%s.png" % shot[0])
	get_tree().quit()
