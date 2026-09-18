extends Node3D
## Everything in the town that moves.
##
## The town is a backdrop with nothing to click on in it, so the only thing telling the player
## it is a place rather than a photograph is motion: the mill turning, washing pulling on the
## line, smoke leaving a chimney, a butterfly crossing the clearing, leaves coming down. None
## of it is interactive and none of it is simulated — it is the cheapest possible loop of each.
##
## Kept out of town.gd because that file is about what the town CONTAINS and this one is about
## what it DOES, and because everything here can be deleted without breaking the town.

# Preloaded rather than referenced by class_name: a freshly written global class is not
# reliably registered in the same session (the same reason player.gd extends combatant.gd by
# path). See scripts/synty_model.gd.
const SyntyModelScript := preload("res://scripts/synty_model.gd")

const WIND_SHADER := "res://assets/shaders/wind_sway.gdshader"

## The FX meshes the meadow pack ships, which is why there are butterflies and leaves at all.
const FX_BUTTERFLY := "FX_Butterfly_Mesh_01"
const FX_LEAF := "FX_Leaf_Meadows_01"

## Which materials count as foliage, and how far each should lean. A blade of grass reaches
## full lean within a metre; a tree has to be nearly rigid at head height or it looks like it
## is made of rubber, so its ramp is the height of the tree.
const WIND_TARGETS := {
	"meadow_grass_tall": {"strength": 0.16, "height": 1.6},
	"meadow_grass_med": {"strength": 0.13, "height": 1.0},
	"meadow_flowers": {"strength": 0.06, "height": 0.5},
	"meadow_groundcover": {"strength": 0.05, "height": 0.5},
	"meadow_branches": {"strength": 0.22, "height": 12.0},
	"meadow_branches_2": {"strength": 0.20, "height": 10.0},
	"meadow_birch": {"strength": 0.14, "height": 10.0},
	"meadow_tree": {"strength": 0.16, "height": 14.0},
}

## Radians per second for the mill. Slow: a windmill that spins like a fan reads as a toy.
const MILL_SPEED := 0.55

const BUTTERFLY_COUNT := 5
const BUTTERFLY_SPEED := 1.1
const BUTTERFLY_SCALE := 0.18

var _blades: Array[Node3D] = []
var _butterflies: Array = []
var _fire_light: OmniLight3D = null
var _time := 0.0
var _soft_dot: ImageTexture = null


func setup(world: Node3D) -> void:
	## Called by Town once the clearing has been built, with the node everything was built
	## under — the wind has to be applied to models that already exist.
	_apply_wind(world)
	_find_blades(world)


func add_chimney_smoke(at: Vector3, amount: int = 14) -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "ChimneySmoke"
	smoke.position = at
	smoke.amount = amount
	smoke.lifetime = 5.5
	smoke.preprocess = 3.0        ## so the chimney is already smoking when the screen appears
	smoke.draw_pass_1 = _soft_quad(0.9)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.25, 1.0, 0.0)
	mat.spread = 8.0
	mat.initial_velocity_min = 0.45
	mat.initial_velocity_max = 0.8
	# Drifting with the wind rather than straight up, matching the shader's wind direction.
	mat.gravity = Vector3(0.35, 0.18, 0.1)
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	mat.scale_over_velocity_min = 0.0
	mat.color = Color(0.86, 0.86, 0.89, 0.30)
	mat.color_ramp = _fade_ramp(Color(0.9, 0.9, 0.93, 0.34))
	smoke.process_material = mat
	add_child(smoke)


func add_campfire(at: Vector3) -> void:
	var fire := GPUParticles3D.new()
	fire.name = "Campfire"
	fire.position = at + Vector3(0, 0.25, 0)
	fire.amount = 22
	fire.lifetime = 1.1
	fire.draw_pass_1 = _soft_quad(0.34)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 16.0
	mat.initial_velocity_min = 0.9
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0.2, 0.6, 0)
	mat.scale_min = 0.4
	mat.scale_max = 0.9
	mat.color_ramp = _fade_ramp(Color(1.0, 0.62, 0.22, 0.85))
	fire.process_material = mat
	add_child(fire)

	# The light is what sells it, and the flicker is what sells the light.
	_fire_light = OmniLight3D.new()
	_fire_light.name = "CampfireLight"
	_fire_light.position = at + Vector3(0, 0.8, 0)
	_fire_light.light_color = Color(1.0, 0.66, 0.34)
	_fire_light.light_energy = 2.4
	_fire_light.omni_range = 9.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)


func add_falling_leaves(centre: Vector3, extent: Vector3) -> void:
	## Leaves over the whole clearing, using the pack's own leaf mesh.
	var mesh := _fx_mesh(FX_LEAF)
	if mesh == null:
		return
	var leaves := GPUParticles3D.new()
	leaves.name = "FallingLeaves"
	leaves.position = centre
	leaves.amount = 40
	leaves.lifetime = 11.0
	leaves.preprocess = 6.0
	leaves.draw_pass_1 = mesh
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extent
	mat.direction = Vector3(0.4, -1.0, 0.1)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0.5, -0.55, 0.15)
	# Tumbling as they come down, which is most of what makes a falling leaf look like one.
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.scale_min = 0.8
	mat.scale_max = 1.6
	leaves.process_material = mat
	add_child(leaves)


func add_butterflies(centre: Vector3, radius: float) -> void:
	var model := SyntyModelScript.meadow(FX_BUTTERFLY)
	if model == null:
		return
	model.queue_free()
	for i in range(BUTTERFLY_COUNT):
		var one := SyntyModelScript.meadow(FX_BUTTERFLY)
		if one == null:
			continue
		one.name = "Butterfly%d" % i
		one.scale = Vector3.ONE * BUTTERFLY_SCALE
		add_child(one)
		# Each gets its own circle, height and phase, so they never look like a formation.
		_butterflies.append({
			"node": one,
			"centre": centre + Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius * 0.6, radius * 0.6)),
			"radius": randf_range(1.6, 4.2),
			"height": randf_range(0.7, 2.1),
			"phase": randf() * TAU,
			"speed": BUTTERFLY_SPEED * randf_range(0.7, 1.4),
			"bob": randf_range(0.15, 0.45),
		})


func _process(delta: float) -> void:
	_time += delta
	for blade in _blades:
		if is_instance_valid(blade):
			# Around its own Z: the blades face the camera-ish, so Z is the axle.
			blade.rotate_object_local(Vector3(0, 0, 1), MILL_SPEED * delta)
	for b in _butterflies:
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			continue
		var t: float = _time * b["speed"] + b["phase"]
		var pos: Vector3 = b["centre"] + Vector3(cos(t) * b["radius"], b["height"] + sin(t * 2.3) * b["bob"], sin(t) * b["radius"])
		# Facing the way it is going, worked out from where it was rather than from calculus.
		var ahead: Vector3 = b["centre"] + Vector3(cos(t + 0.15) * b["radius"], b["height"], sin(t + 0.15) * b["radius"])
		node.position = pos
		if ahead.distance_to(pos) > 0.001:
			node.look_at(ahead, Vector3.UP)
	if _fire_light != null:
		# Two out-of-step sines rather than a random number per frame: noise reads as a fault,
		# and a fire's light wavers rather than strobing.
		var flicker := 2.2 + sin(_time * 7.3) * 0.28 + sin(_time * 3.1) * 0.18
		_fire_light.light_energy = flicker


# --- Wind ------------------------------------------------------------------

func _apply_wind(root: Node) -> void:
	## Swap every foliage material for a shader version of itself.
	##
	## The plain materials (assets/Synty/PolygonMeadow/Materials) stay the source of truth for
	## what a plant LOOKS like; this reads the texture back off each one and hands it to the
	## wind shader, so there is no second copy of "which texture is the grass" to keep in step.
	var shader := load(WIND_SHADER) as Shader
	if shader == null:
		push_warning("TownAmbience: no wind shader; the clearing will be still")
		return
	var swapped := {}
	_swap_materials(root, shader, swapped)


func _swap_materials(node: Node, shader: Shader, cache: Dictionary) -> void:
	var mesh_node := node as MeshInstance3D
	# Only the near band sways. The forest behind it is built from Synty's cheaper baked
	# levels (see SyntyModel.meadow), and running a vertex shader over a couple of hundred
	# distant trees costs frames to animate something nobody can see moving.
	if mesh_node != null and String(mesh_node.name).contains("_LOD") 			and not String(mesh_node.name).ends_with("_LOD0"):
		return
	if mesh_node != null and mesh_node.mesh != null:
		for surface in range(mesh_node.mesh.get_surface_count()):
			var current := mesh_node.get_surface_override_material(surface)
			var base := current as StandardMaterial3D
			if base == null:
				continue
			var key := String(base.resource_name)
			if not WIND_TARGETS.has(key):
				continue
			if not cache.has(key):
				cache[key] = _wind_material(shader, base, WIND_TARGETS[key])
			mesh_node.set_surface_override_material(surface, cache[key])
	for child in node.get_children():
		_swap_materials(child, shader, cache)


func _wind_material(shader: Shader, base: StandardMaterial3D, tuning: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_texture", base.albedo_texture)
	mat.set_shader_parameter("alpha_threshold", 0.4)
	mat.set_shader_parameter("sway_strength", tuning["strength"])
	mat.set_shader_parameter("sway_height", tuning["height"])
	mat.set_shader_parameter("wind_dir", Vector2(0.85, 0.35))
	return mat


func _find_blades(root: Node) -> void:
	if String(root.name).contains("Blades"):
		var node := root as Node3D
		if node != null:
			_blades.append(node)
	for child in root.get_children():
		_find_blades(child)


# --- Small builders --------------------------------------------------------

func _fx_mesh(model_name: String) -> Mesh:
	## The mesh out of one of the pack's FX models, for a particle system to draw.
	var model := SyntyModelScript.meadow(model_name)
	if model == null:
		return null
	var found := _first_mesh(model)
	var mesh: Mesh = found.mesh if found != null else null
	model.queue_free()
	return mesh


func _first_mesh(node: Node) -> MeshInstance3D:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		return mesh_node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _soft_quad(size: float) -> QuadMesh:
	## A camera-facing quad with a soft round blob on it, for smoke and embers. Built here
	## rather than imported: it is four vertices and a gradient, and an asset for it would be
	## one more file to find.
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _dot_texture()
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad


func _dot_texture() -> ImageTexture:
	if _soft_dot != null:
		return _soft_dot
	var side := 48
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var centre := (side - 1) * 0.5
	for y in range(side):
		for x in range(side):
			var d := Vector2(x - centre, y - centre).length() / centre
			# Squared falloff: a linear one has a visible edge where it reaches zero.
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	_soft_dot = ImageTexture.create_from_image(image)
	return _soft_dot


func _fade_ramp(tint: Color) -> GradientTexture1D:
	## Fully there at birth, gone by death.
	var gradient := Gradient.new()
	gradient.set_color(0, tint)
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
