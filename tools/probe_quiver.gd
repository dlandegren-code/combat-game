extends Node3D
## Dev tool: where a show_quiver Sidekick body's quiver actually ends up — its up axis and
## centre in the body's frame, after a few frames of idle. Prints [quiver] lines and quits.

const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")


func _ready() -> void:
	var body := SIDEKICK.instantiate()
	body.set("show_quiver", true)
	add_child(body)
	body.play("idle")
	for i in range(10):
		await get_tree().process_frame
	var sk: Skeleton3D = body.skeleton
	print("[quiver] body rot=%s scale=%s" % [body.rotation_degrees, body.scale])
	print("[quiver] skeleton path=%s xform=%s" % [body.get_path_to(sk), sk.transform])
	var b := sk.find_bone("UpperChest")
	print("[quiver] UpperChest rest_global=%s" % sk.get_bone_global_rest(b))
	print("[quiver] Head pose y=%s Hips=%s" % [(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin, (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))).origin])
	var q: Node3D = body.get("_quiver")
	var inv: Transform3D = body.global_transform.affine_inverse()
	var g: Transform3D = inv * q.global_transform
	print("[quiver] in body frame: origin=%s up=%s fwd=%s" % [g.origin, g.basis.y.normalized(), g.basis.z.normalized()])
	print("[quiver] body facing (global basis z)=%s" % body.global_transform.basis.z)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 30
	for shot in [["back", Vector3(0.0, 0.7, -2.2)], ["side", Vector3(2.2, 0.7, 0.0)], ["three", Vector3(1.6, 1.2, -1.6)]]:
		cam.position = shot[1]
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://.summer/local/quiver_%s.png" % shot[0])
	get_tree().quit()
