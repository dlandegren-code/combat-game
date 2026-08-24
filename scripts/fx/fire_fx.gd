extends RefCounted
## Shared building blocks for the fire effects (see firebolt_projectile.gd, fire_splash.gd).
##
## Everything here is built in code rather than saved as .tres/.tscn because the two effects
## want the *same* palette and the same soft-particle setup with only a few numbers changed.
## A helper call per emitter keeps them reading as one family; a folder of nearly identical
## material resources would not.
##
## The art is Synty's POLYGON Particle FX pack, imported under assets/PolygonParticles: the
## flat-shaded flame and puff meshes give the chunky low-poly silhouette the rest of the game
## has, and the soft round blobs fill in the glow behind them.

# --- Pack assets -----------------------------------------------------------

const TEX_BLOB := "res://assets/PolygonParticles/Textures/PolygonParticles_Soft_Spot.png"
const TEX_SPARK := "res://assets/PolygonParticles/Textures/PolygonParticles_Sparkle.png"
const TEX_SMOKE := "res://assets/PolygonParticles/Textures/PolygonParticles_Smoke_01.png"
const TEX_RING := "res://assets/PolygonParticles/Textures/PolygonParticles_Ring_02.png"
const MESH_FLAME := "res://assets/PolygonParticles/Models/SM_Flame_FX.obj"
const MESH_PUFF := "res://assets/PolygonParticles/Models/FX_Sphere_Puff_01.obj"

## The Synty meshes are authored in centimetres — the flame is ~20.8 units tall, the puff
## ~133 across — so anything drawing them has to scale by roughly this much to land at a
## sensible size on a 2-unit grid. Both effects derive their sizes from these two numbers
## rather than each carrying its own magic constant.
const FLAME_MESH_UNIT := 0.048   ## x this = a flame one metre tall
const PUFF_MESH_UNIT := 0.0075   ## x this = a puff one metre across

# --- Palette ---------------------------------------------------------------
## One fire ramp for every emitter: white-hot at birth, orange through the middle, dying to a
## dark ember. Sharing it is what makes the trail and the splash look like the same fire.

const HOT := Color(1.00, 0.95, 0.72)
const FLAME := Color(1.00, 0.55, 0.13)
const DEEP := Color(0.82, 0.18, 0.03)
const EMBER := Color(1.00, 0.72, 0.24)
const SMOKE := Color(0.16, 0.14, 0.13)


static func fire_ramp() -> GradientTexture1D:
	return _ramp(
		[0.0, 0.22, 0.55, 1.0],
		[HOT, FLAME, Color(DEEP, 0.7), Color(0.25, 0.04, 0.02, 0.0)])


static func ember_ramp() -> GradientTexture1D:
	## Embers hold their colour and then wink out rather than cooling through the ramp — a
	## spark that faded to dark red would just read as dirt.
	return _ramp([0.0, 0.7, 1.0], [HOT, EMBER, Color(EMBER, 0.0)])


static func smoke_ramp() -> GradientTexture1D:
	## Smoke starts lit by the fire it came out of, then goes cold and thins away.
	##
	## Kept very low in alpha on purpose. The pack's smoke texture is a hard-edged faceted
	## blob rather than a soft cloud, so at any real opacity it stops reading as smoke and
	## starts reading as pale grey polygons sitting in front of the fire.
	return _ramp(
		[0.0, 0.18, 1.0],
		[Color(0.34, 0.18, 0.09, 0.30), Color(SMOKE, 0.22), Color(SMOKE, 0.0)])


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
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


# --- Size-over-life curves -------------------------------------------------

static func shrink_curve(start: float = 1.0) -> CurveTexture:
	## Fire that only ever gets smaller: right for a trail, where each puff is left behind and
	## burns down where it was dropped.
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(0.45, start * 0.62))
	c.add_point(Vector2(1.0, 0.0))
	return _curve_tex(c)


static func puff_curve() -> CurveTexture:
	## Bloom, then collapse. An impact throws fire outward before it burns out, so the
	## particle has to grow first or the burst has no punch.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.18))
	c.add_point(Vector2(0.22, 1.0))
	c.add_point(Vector2(1.0, 0.05))
	return _curve_tex(c)


static func swell_curve() -> CurveTexture:
	## Smoke only ever expands as it cools.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	return _curve_tex(c)


static func _curve_tex(c: Curve) -> CurveTexture:
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


# --- Meshes / materials ----------------------------------------------------

static func blob_quad(texture_path: String, size: float, additive: bool = true) -> QuadMesh:
	## A camera-facing quad for one of the pack's round particle textures. BILLBOARD_PARTICLES
	## rather than plain BILLBOARD_ENABLED is what lets each particle carry its own spin, so a
	## trail of these does not read as a row of identical stamps.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	# Transparent particles must not write depth, or they sort against each other and punch
	# holes in the fire they are part of.
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


static func flame_mesh(tint: Color, tinted_per_particle: bool = false) -> ArrayMesh:
	## The Synty flame, flat-shaded and glowing. Returned as a Mesh so it can be used either
	## as a draw pass on an emitter or as a plain MeshInstance3D. Pass tinted_per_particle for
	## the emitter case, where each particle's own colour ramp should modulate the tint.
	return _tinted(MESH_FLAME, tint, tinted_per_particle)


static func puff_mesh(tint: Color, tinted_per_particle: bool = true) -> ArrayMesh:
	return _tinted(MESH_PUFF, tint, tinted_per_particle)


static func _tinted(mesh_path: String, tint: Color, tinted_per_particle: bool) -> ArrayMesh:
	var source := load(mesh_path) as ArrayMesh
	if source == null:
		# The pack meshes are dressing on top of the blob emitters, which read as fire on
		# their own. A missing or differently-imported mesh must not take the whole effect —
		# and with it the spell — down, so callers get null and simply skip that layer.
		push_warning("FireFx: could not load %s as an ArrayMesh; skipping that layer." % mesh_path)
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
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

static func process_material(ramp: GradientTexture1D, scale_curve: CurveTexture) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.color_ramp = ramp
	pm.scale_curve = scale_curve
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.gravity = Vector3.ZERO
	return pm


static func emitter(node_name: String, mesh: Mesh, process: ParticleProcessMaterial,
		amount: int, lifetime: float) -> GPUParticles3D:
	## Every emitter in both effects is built here so they share the settings that are easy to
	## forget: a generous visibility box — world-space particles wander far outside the node's
	## own bounds and would otherwise vanish the moment the emitter moves — and fixed_fps 0,
	## which advances particles on the real frame rate instead of a 30 Hz grid. Without that
	## last one a fast bolt lays its trail down in visible clumps.
	##
	## Emitters come back switched OFF. Both effects are positioned after they are built, and
	## a world-space emitter that started early would spit its first frame of fire out at the
	## origin of the arena.
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
