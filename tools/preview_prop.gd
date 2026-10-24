extends Node3D
## Dev tool: one prop prefab close up, from the front and from the side, for placing what is
## baked onto it (tools/build_viking_kit.gd's DECOR). Writes .summer/local/prop_front.png and
## prop_side.png, then quits.

@export var prefab := "res://assets/vikings/weapons/SM_Wep_Bow_Rigged_01.fbx"


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
	add_child((load(prefab) as PackedScene).instantiate())
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for shot in [["front", Vector3(0.6, 1.1, 3.0)], ["side", Vector3(3.0, 1.1, 0.4)]]:
		cam.position = shot[1]
		cam.look_at(Vector3(0, 0.8, 0), Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://.summer/local/prop_%s.png" % shot[0])
	get_tree().quit()
