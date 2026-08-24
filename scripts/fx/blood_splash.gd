extends Node3D
class_name BloodSplash
## What a wound throws out: a cone of droplets away from whoever landed the blow, chunkier
## gobbets that arc and fall, a short haze at the wound and a stain on the floor underneath.
##
## Spawned from Combatant._spill_blood for every hit that gets through, whatever caused it —
## a blade, an arrow, a thrown axe, a wall. `strength` is what tells a scratch from a solid
## blow, so the same effect covers both without a second set of numbers.
##
## The counterpart to fire_splash.gd and built the same way — one_shot emitters that all leave
## on a single frame and then decay — but with two differences that matter:
##
##  * Nothing here is additive. Additive blood glows pink on a dark floor and vanishes on a
##    bright one; blended dark red reads as blood on both.
##  * It has a direction. Blood sprays away from the arrow rather than in every direction, so
##    the burst points along the shot and tells you where it came from.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")
const BloodFx := preload("res://scripts/fx/blood_fx.gd")

## How long the node lives. Must clear the longest lifetime below, or a layer gets cut short.
const LINGER := 1.6

## Floor stain: spreads fast, then soaks away.
const POOL_GROW_TIME := 0.5
const POOL_FADE_TIME := 0.9
const POOL_START_SCALE := 0.15
const POOL_END_SCALE := 1.1

var _at := Vector3.ZERO
var _direction := Vector3.FORWARD
var _ground_y := 0.0
var _strength := 1.0
var _pool_material: StandardMaterial3D


static func burst(parent: Node, at: Vector3, direction: Vector3, ground_y: float,
		strength: float = 1.0) -> void:
	## `at` is the wound, `direction` the way the blow was travelling (the spray goes with it,
	## not back at whoever struck), `ground_y` the floor beneath — separate from `at` because
	## the stain belongs on the floor however high up the hit landed — and `strength` roughly
	## how hard it landed, around 1.0 for an ordinary blow.
	var fx := BloodSplash.new()
	fx._at = at
	fx._strength = maxf(strength, 0.1)
	# Kept flat. This vector is what the node is turned to face, and a look_at along a vector
	# parallel to UP has no valid basis; the upward lift the spray and the gobbets want is in
	# their own `direction` instead, where it cannot break anything.
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() > 0.01:
		fx._direction = flat.normalized()
	else:
		# Nothing to spray away from — a body slammed into a wall has no attacker. A random
		# heading beats a fixed one: every such splash pointing the same way across the arena
		# would read as a bug rather than as blood.
		var angle := randf() * TAU
		fx._direction = Vector3(cos(angle), 0.0, sin(angle))
	fx._ground_y = ground_y
	parent.add_child(fx)


func _ready() -> void:
	# Position and aim before anything emits: the emitters work in world space, and the
	# process materials' `direction` is read through this node's own basis.
	global_position = _at
	look_at(_at + _direction, Vector3.UP)
	_build_spray()
	_build_gobbets()
	_build_mist()
	_build_pool()
	for child in get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = true
	await get_tree().create_timer(LINGER).timeout
	queue_free()


# --- Layers ----------------------------------------------------------------

func _build_spray() -> void:
	## The body of it: fine droplets driven out along the arrow's line in a wide cone, falling
	## as they go. Barely damped — blood is heavy, and droplets that hung in the air would read
	## as sparks — but under less than real gravity, because at 1 g the cone collapses into a
	## curtain within a frame or two and the burst stops pointing anywhere.
	var pm := ParticleKit.process_material(BloodFx.spray_ramp(), ParticleKit.hold_curve())
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(0, 0, -1)   # this node's forward, i.e. the way the arrow was going
	pm.spread = 55.0
	pm.initial_velocity_min = _speed(3.0)
	pm.initial_velocity_max = _speed(8.0)
	pm.gravity = Vector3(0, -8.0, 0)
	pm.damping_min = 0.2
	pm.damping_max = 1.2
	ParticleKit.spin(pm, 200.0)
	# A wide spread of sizes, not a wide spread of one size: uniform droplets read as a
	# pattern of dots rather than as spatter.
	pm.scale_min = 0.25
	pm.scale_max = 1.15

	# A hard-edged round dot rather than the soft blob the fire uses: blood has an edge, and
	# a soft-edged droplet reads as a smudge.
	_add_burst("Spray", ParticleKit.blob_quad(ParticleKit.TEX_DOT, 0.14, false), pm, 44, 0.8)


func _build_gobbets() -> void:
	## A dozen faceted chunks tumbling out slower and heavier than the spray. This is the layer
	## that makes the splash read as low-poly and of a piece with everything else Synty in the
	## scene, rather than as a generic red particle puff.
	##
	## The meshes go in WHITE and take their red from the ramp — tinting them as well would
	## multiply the two and turn the gobbets black (see ParticleKit.tinted_mesh).
	var pm := ParticleKit.process_material(BloodFx.chunk_ramp(), ParticleKit.hold_curve())
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 0.35, -1)
	pm.spread = 45.0
	pm.initial_velocity_min = _speed(2.0)
	pm.initial_velocity_max = _speed(4.5)
	pm.gravity = Vector3(0, -9.5, 0)
	ParticleKit.spin(pm, 420.0)   # end over end, the way a thrown scrap tumbles
	pm.scale_min = 0.15 * ParticleKit.CHUNK_MESH_UNIT
	pm.scale_max = 0.4 * ParticleKit.CHUNK_MESH_UNIT

	_add_burst("Gobbets",
		ParticleKit.tinted_mesh(ParticleKit.MESH_CHUNK_SMALL, Color.WHITE, false, true),
		pm, 12, 0.9)

	# A few longer, thinner ones on the same arc — two silhouettes read as spatter where one
	# repeated shape reads as a pattern.
	var pm_long := ParticleKit.process_material(BloodFx.chunk_ramp(), ParticleKit.hold_curve())
	pm_long.emission_sphere_radius = 0.08
	pm_long.direction = Vector3(0, 0.2, -1)
	pm_long.spread = 35.0
	pm_long.initial_velocity_min = _speed(3.0)
	pm_long.initial_velocity_max = _speed(6.5)
	pm_long.gravity = Vector3(0, -9.5, 0)
	pm_long.particle_flag_align_y = true   # streaks lie along their own flight, like flung drops
	pm_long.scale_min = 0.1 * ParticleKit.CHUNK_MESH_UNIT
	pm_long.scale_max = 0.25 * ParticleKit.CHUNK_MESH_UNIT

	_add_burst("Streaks",
		ParticleKit.tinted_mesh(ParticleKit.MESH_CHUNK_LONG, Color.WHITE, false, true),
		pm_long, 8, 0.8)


func _build_mist() -> void:
	## The haze right at the wound. Brief and thin — it is the flash of the hit, and holding it
	## any longer turns the target into a smoker.
	var pm := ParticleKit.process_material(BloodFx.mist_ramp(), ParticleKit.swell_curve())
	pm.emission_sphere_radius = 0.14
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 70.0
	pm.initial_velocity_min = _speed(0.6)
	pm.initial_velocity_max = _speed(2.0)
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	ParticleKit.spin(pm, 60.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2

	_add_burst("Mist", ParticleKit.blob_quad(ParticleKit.TEX_BLOB, 0.45, false), pm, 10, 0.35)


func _add_burst(node_name: String, mesh: Mesh, pm: ParticleProcessMaterial,
		amount: int, lifetime: float) -> void:
	if mesh == null:
		return   # a pack mesh that failed to import — that layer is simply left out
	# Particle COUNT carries the weight of the hit, which is why it is scaled here for every
	# layer at once rather than layer by layer: a harder blow means more blood, not bigger blood.
	var scaled: int = maxi(1, roundi(amount * _strength))
	add_child(ParticleKit.one_shot(ParticleKit.emitter(node_name, mesh, pm, scaled, lifetime)))


func _speed(base: float) -> float:
	## Velocity scales too, but far more gently than the count. A heavy blow throws blood
	## further; one that scaled linearly would fling it clean off the screen.
	return base * (0.75 + 0.25 * _strength)


func _build_pool() -> void:
	## The stain on the floor under the hit. A tweened quad rather than particles, for the same
	## reason the Firebolt's scorch ring is: one flat thing whose whole behaviour is "spread,
	## then soak away" is cheaper and easier to time as a tween.
	var tex: Texture2D = load(ParticleKit.TEX_BLOB)
	if tex == null:
		return
	_pool_material = StandardMaterial3D.new()
	_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_pool_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_pool_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pool_material.albedo_texture = tex
	_pool_material.albedo_color = Color(BloodFx.DARK, 0.0)
	_pool_material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _pool_material

	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	pool.mesh = quad
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Top level so the stain keeps the floor height set here rather than being dragged up to
	# the wound — and so this node's aiming rotation does not stand it on its edge.
	pool.top_level = true
	add_child(pool)
	# Offset towards where the spray is going, so the stain lands under the splash rather than
	# under the target's feet.
	var centre := _at + _direction * 0.5
	pool.global_position = Vector3(centre.x, _ground_y + 0.025, centre.z)
	pool.rotation_degrees = Vector3(-90, 0, randf_range(0.0, 360.0))
	pool.scale = Vector3.ONE * POOL_START_SCALE

	# Spreads and darkens on the way in, then soaks away more slowly than it arrived.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(pool, "scale", Vector3.ONE * POOL_END_SCALE * _strength, POOL_GROW_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_pool_material, "albedo_color:a", 0.75, POOL_GROW_TIME * 0.4)
	tween.chain().tween_property(_pool_material, "albedo_color:a", 0.0, POOL_FADE_TIME) \
		.set_ease(Tween.EASE_IN)
