extends RefCounted
## Generic particle plumbing shared by every effect under scripts/fx/, plus the paths to the
## Synty POLYGON Particle FX pack assets in assets/PolygonParticles.
##
## This file knows nothing about fire or blood — it only knows how to turn one of the pack's
## textures into a billboarded particle quad, one of its meshes into a tinted particle mesh,
## and a colour ramp plus a size curve into a working emitter. The effects themselves supply
## the palette (see fire_fx.gd, blood_fx.gd), which is what keeps a family of effects looking
## like a family without every one of them re-deriving the same soft-particle setup.
##
## Everything is built in code rather than saved as .tres because the numbers that differ
## between effects are a handful per emitter; a folder of nearly identical material resources
## would hide that.

# --- Pack assets -----------------------------------------------------------

## White RGB with a radial alpha falloff, so a tint applied on top comes through cleanly.
const TEX_BLOB := "res://assets/PolygonParticles/Textures/PolygonParticles_Soft_Spot.png"
## Same, but a hard-edged disc — for anything that should have an edge, like a droplet.
const TEX_DOT := "res://assets/PolygonParticles/Textures/PolygonParticles_Circle_01.png"
const TEX_SPARK := "res://assets/PolygonParticles/Textures/PolygonParticles_Sparkle.png"
const TEX_SMOKE := "res://assets/PolygonParticles/Textures/PolygonParticles_Smoke_01.png"
const TEX_RING := "res://assets/PolygonParticles/Textures/PolygonParticles_Ring_02.png"
const MESH_FLAME := "res://assets/PolygonParticles/Models/SM_Flame_FX.obj"
const MESH_PUFF := "res://assets/PolygonParticles/Models/FX_Sphere_Puff_01.obj"
const MESH_CHUNK_SMALL := "res://assets/PolygonParticles/Models/SM_GoreChunk_02.obj"
const MESH_CHUNK_LONG := "res://assets/PolygonParticles/Models/SM_GoreChunk_03.obj"

## The Synty meshes are authored in centimetres — the flame is ~20.8 units tall, the puff
## ~133 across, the gore chunks ~5–20 — so anything drawing them has to scale by roughly this
## much to land at a sensible size on a 2-unit grid. Effects derive their sizes from these
## rather than each carrying its own magic constant.
const FLAME_MESH_UNIT := 0.048   ## x this = a flame one metre tall
const PUFF_MESH_UNIT := 0.0075   ## x this = a puff one metre across
const CHUNK_MESH_UNIT := 0.11    ## x this = a chunk roughly one metre across


# --- Colour ramps and size-over-life curves --------------------------------

static func ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var o := PackedFloat32Array()
	for v in offsets:
		o.append(v)
	var c := PackedColorArray()
	for v in colors:
		c.append(v)
	# Offsets first: that setter resizes the colour array to match, so writing colours
	# afterwards is what actually fills them in. The other order drops points.
	g.offsets = o
	g.colors = c
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


static func shrink_curve(start: float = 1.0) -> CurveTexture:
	## Only ever gets smaller: right for a trail, where each puff is left behind and burns
	## down where it was dropped.
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(0.45, start * 0.62))
	c.add_point(Vector2(1.0, 0.0))
	return _curve_tex(c)


static func puff_curve() -> CurveTexture:
	## Bloom, then collapse. An impact throws material outward before it dies, so the
	## particle has to grow first or the burst has no punch.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.18))
	c.add_point(Vector2(0.22, 1.0))
	c.add_point(Vector2(1.0, 0.05))
	return _curve_tex(c)


static func swell_curve() -> CurveTexture:
	## Only ever expands, the way smoke and mist do as they thin out.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	return _curve_tex(c)


static func hold_curve() -> CurveTexture:
	## Full size almost immediately and stays there, leaving the colour ramp's alpha to do
	## the dying. Right for anything solid — a droplet does not shrink, it lands.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1.0, 0.9))
	return _curve_tex(c)


static func _curve_tex(c: Curve) -> CurveTexture:
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


# --- Meshes / materials ----------------------------------------------------

static func blob_quad(texture_path: String, size: float, additive: bool = true) -> QuadMesh:
	## A camera-facing quad for one of the pack's round particle textures. BILLBOARD_PARTICLES
	## rather than plain BILLBOARD_ENABLED is what lets each particle carry its own spin, so a
	## stream of these does not read as a row of identical stamps.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	# Transparent particles must not write depth, or they sort against each other and punch
	# holes in the effect they are part of.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true   # lets the process material's colour ramp through
	mat.disable_receive_shadows = true
	mat.albedo_texture = load(texture_path)

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	return quad


static func tinted_mesh(mesh_path: String, tint: Color, additive: bool = true,
		tinted_per_particle: bool = false) -> ArrayMesh:
	## One of the pack's meshes, flat-shaded and painted a single colour. Pass
	## tinted_per_particle when it is a draw pass on an emitter and each particle should take
	## its colour from the process material's ramp; leave it off for a lone MeshInstance3D.
	##
	## Careful: with tinted_per_particle the two colours MULTIPLY. A mesh tinted dark red and a
	## ramp of dark red come out near black, which is exactly how the blood gobbets first
	## looked. When the ramp is meant to own the colour, pass Color.WHITE here.
	var source := load(mesh_path) as ArrayMesh
	if source == null:
		# The pack meshes are dressing on top of the quad emitters, which read on their own.
		# A missing or differently-imported mesh must not take the whole effect — and with it
		# the action that spawned it — down, so callers get null and simply skip that layer.
		push_warning("ParticleKit: could not load %s as an ArrayMesh; skipping that layer." % mesh_path)
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = tinted_per_particle
	mat.disable_receive_shadows = true
	# A copy per effect: the imported mesh is a shared resource, and painting a material onto
	# it directly would tint every other user of it too.
	var out := source.duplicate() as ArrayMesh
	for i in range(out.get_surface_count()):
		out.surface_set_material(i, mat)
	return out


# --- Emitter assembly ------------------------------------------------------

static func process_material(color_ramp: GradientTexture1D, scale_curve: CurveTexture) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.color_ramp = color_ramp
	pm.scale_curve = scale_curve
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.gravity = Vector3.ZERO
	return pm


static func emitter(node_name: String, mesh: Mesh, process: ParticleProcessMaterial,
		amount: int, lifetime: float) -> GPUParticles3D:
	## Every emitter in every effect is built here so they share the settings that are easy to
	## forget: a generous visibility box — world-space particles wander far outside the node's
	## own bounds and would otherwise vanish the moment the emitter moves — and fixed_fps 0,
	## which advances particles on the real frame rate instead of a 30 Hz grid. Without that
	## last one a fast projectile lays its trail down in visible clumps.
	##
	## Emitters come back switched OFF. Effects are positioned after they are built, and a
	## world-space emitter that started early would spit its first frame out at the arena origin.
	var p := GPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = process
	p.draw_pass_1 = mesh
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = true
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	return p


static func one_shot(p: GPUParticles3D) -> GPUParticles3D:
	## Turn an emitter into a burst: the whole `amount` leaves on frame one and then decays.
	## That single frame is what separates an impact from a campfire.
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	return p


static func trail_along_travel(pm: ParticleProcessMaterial, half_length: float,
		thickness: float = 0.1) -> void:
	## Spawn from a box stretched along the emitter's -Z (its direction of travel) instead of
	## from a point, and this is the whole trick to a projectile trail. Particles spawn in
	## batches once per frame, so a point emitter on something moving 16 m/s lays them down in
	## clumps a third of a metre apart — visibly a dotted line. Spreading each batch along the
	## segment the projectile is about to cross fills those gaps at no extra particle cost.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(thickness, thickness, half_length)


static func spin(pm: ParticleProcessMaterial, degrees_per_second: float) -> void:
	## Random starting angle plus a random tumble, applied the same way everywhere.
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -degrees_per_second
	pm.angular_velocity_max = degrees_per_second
