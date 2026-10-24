extends Node3D
## Dev tool: every Sidekick part in the given slots, each on its own with its set's palette, in a
## labelled grid seen from the side. Writes .summer/local/parts.png and quits.

const Body := preload("res://scripts/sidekick_body.gd")

@export var slots: Array = ["24ABAC", "25AHPF", "26AHPB", "27AHPL", "28AHPR"]
@export var columns := 7
@export var cell := 1.2


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.32, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 60, 0)
	add_child(sun)
	var files: Array = []
	for dir in Body.PART_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".fbx") and slots.any(func(s): return f.contains("_%s_" % s)):
				files.append(dir + f)
	files.sort()
	var i := 0
	for path in files:
		var root := (load(path) as PackedScene).instantiate()
		var src := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		var part: String = path.get_file().get_basename()
		var pal := Body._set_palette(part)
		if pal != "":
			mi.material_override = Body._material_for(Body.TEXTURE_DIR + pal)
		root.free()
		var box := mi.mesh.get_aabb()
		var s := 0.9 * cell / maxf(box.size.y, maxf(box.size.z, 0.01))
		mi.scale = Vector3.ONE * s
		var at := Vector3(0, -float(i / columns) * cell * 1.3, float(i % columns) * cell)
		mi.position = at - box.get_center() * s
		add_child(mi)
		var label := Label3D.new()
		label.text = part.replace("SK_", "").replace("_HU01", "")
		label.font_size = 28
		label.pixel_size = 0.004
		label.rotation_degrees = Vector3(0, 90, 0)
		label.position = at + Vector3(0, -cell * 0.6, 0)
		add_child(label)
		i += 1
	var rows := ceili(float(i) / columns)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * cell * 1.3 + 0.4
	add_child(cam)
	cam.position = Vector3(10, -(rows - 1) * cell * 0.65 - 0.1, (columns - 1) * cell * 0.5)
	cam.rotation_degrees = Vector3(0, 90, 0)
	cam.make_current()
	get_window().size = Vector2i(1800, int(1800.0 * cam.size / (columns * cell)))
	for k in range(5):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://.summer/local/parts.png")
	get_tree().quit()
