extends Node3D
## Dev tool: four birches in a row, each painted a different way, photographed close up.
##
## Run it by playing tools/compare_tree_materials.tscn; it writes
## .summer/local/tree_variants.png.
##
## WHY
## A canopy is one mesh with the trunk, sharing one material, and the pack gives no clue which
## of its textures that material wants. Four attempts at 35 m in a wide shot all looked like
## "speckle" and told me nothing. One close photograph of the four side by side answers it in
## a single look, which is cheaper than four more guesses.

const MODEL := "SM_Env_Tree_Birch_01"
const TEX := "res://assets/Synty/PolygonMeadow/Textures/"
const SHOT := "res://.summer/local/tree_variants.png"

const SyntyModelScript := preload("res://scripts/synty_model.gd")


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.2
	add_child(sun)

	# left to right: the tree's own sheet opaque, the same sheet alpha-scissored, the palette
	# atlas, and a flat green.
	_variant(-9.0, _sheet(false))
	_variant(-3.0, _sheet(true))
	_variant(3.0, load("res://assets/Synty/PolygonMeadow/Materials/meadow_atlas.tres"))
	_variant(9.0, _flat())

	var camera := Camera3D.new()
	camera.position = Vector3(0, 6.0, 20.0)
	camera.fov = 55.0
	add_child(camera)
	camera.look_at(Vector3(0, 5.0, 0), Vector3.UP)

	for i in range(10):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	print("[Trees] %s" % ("ok" if image.save_png(SHOT) == OK else "FAILED"))
	get_tree().quit()


func _variant(x: float, material: Material) -> void:
	## One tree, with `material` forced onto every surface EXCEPT the branch cards, which have
	## a texture of their own and are not what is in question here.
	var tree := SyntyModelScript.meadow(MODEL)
	if tree == null:
		return
	tree.position = Vector3(x, 0, 0)
	add_child(tree)
	_repaint(tree, material)


func _repaint(node: Node, material: Material) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null and not String(mesh_node.name).contains("Branches"):
		for surface in range(mesh_node.mesh.get_surface_count()):
			mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_repaint(child, material)


func _sheet(scissor: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX + "treeBirch_01.png")
	mat.roughness = 0.9
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if scissor:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.4
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _flat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.70, 0.32)
	mat.roughness = 0.9
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat
