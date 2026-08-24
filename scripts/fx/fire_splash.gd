extends Node3D
class_name FireSplash
## The burst where a Firebolt lands: fire thrown outward, flame tongues, embers, smoke, a
## scorch ring on the floor and a flash of light. Spawned only on a bolt that actually
## connects, so it doubles as the "that one got through" read.
##
## Every emitter is one_shot with explosiveness 1.0 — the whole burst leaves in a single frame
## and then decays, which is what separates an impact from a campfire. The node frees itself
## once the slowest layer (smoke) has faded.

const FireFx := preload("res://scripts/fx/fire_fx.gd")

## How long the node lives. Must clear the longest lifetime below, or a layer gets cut short.
const LINGER := 1.5

## Ground ring: the scorch mark thrown out along the floor under the impact.
const RING_GROW_TIME := 0.45
const RING_START_SCALE := 0.35
const RING_END_SCALE := 2.4

var _at := Vector3.ZERO
var _ground_y := 0.0
var _ring_material: StandardMaterial3D


static func burst(parent: Node, at: Vector3, ground_y: float) -> void:
	## `at` is where the bolt struck (chest height); `ground_y` is the floor beneath it, which
	## the scorch ring is laid on. They are separate because the ring belongs on the floor even
	## when the bolt hits something tall.
	var fx := FireSplash.new()
	fx._at = at
	fx._ground_y = ground_y
	parent.add_child(fx)


func _ready() -> void:
	# Position before anything emits: the emitters work in world space, so a burst that
	# started a frame early would go off at the arena origin.
	global_position = _at
	_build_fireball()
	_build_flames()
	_build_chunks()
	_build_embers()
	_build_smoke()
	_build_ring()
	_build_flash()
	for child in get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = true
	await get_tree().create_timer(LINGER).timeout
	queue_free()


# --- Layers ----------------------------------------------------------------

func _build_fireball() -> void:
	## The body of the burst: soft blobs blown out in every direction and dragged to a stop,
	## so the fire bulges out fast and then hangs where it stopped instead of drifting away.
	var pm := FireFx.process_material(FireFx.fire_ramp(), FireFx.puff_curve())
	pm.emission_sphere_radius = 0.18
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, 1.2, 0)
	pm.damping_min = 6.0
	pm.damping_max = 11.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -120.0
	pm.angular_velocity_max = 120.0
	pm.scale_min = 0.7
	pm.scale_max = 1.5

	_add_burst("Fireball", FireFx.blob_quad(FireFx.TEX_BLOB, 0.7), pm, 34, 0.6)


func _build_flames() -> void:
	## Synty flame meshes riding the burst outward. particle_flag_align_y turns each one to
	## point along its own velocity, so the tongues splay out from the impact instead of all
	## standing upright — this is the layer that makes the splash read as low-poly rather than
	## as a generic soft-particle puff.
	var pm := FireFx.process_material(FireFx.fire_ramp(), FireFx.puff_curve())
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 85.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -1.0, 0)
	pm.damping_min = 5.0
	pm.damping_max = 9.0
	pm.particle_flag_align_y = true
	# Read as "flames between 0.35 m and 0.8 m tall" — the mesh itself is ~20.8 units.
	pm.scale_min = 0.35 * FireFx.FLAME_MESH_UNIT
	pm.scale_max = 0.8 * FireFx.FLAME_MESH_UNIT

	_add_burst("Flames", FireFx.flame_mesh(FireFx.FLAME, true), pm, 14, 0.5)


func _build_chunks() -> void:
	## A handful of the pack's faceted puffs, tumbling out slowly and swelling as they go.
	## Fewer and bigger than the blobs — they are there for silhouette, not for coverage.
	var pm := FireFx.process_material(FireFx.fire_ramp(), FireFx.puff_curve())
	pm.emission_sphere_radius = 0.15
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, 1.5, 0)
	pm.damping_min = 4.0
	pm.damping_max = 7.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	pm.scale_min = 0.5 * FireFx.PUFF_MESH_UNIT
	pm.scale_max = 1.1 * FireFx.PUFF_MESH_UNIT

	_add_burst("Chunks", FireFx.puff_mesh(FireFx.DEEP), pm, 7, 0.55)


func _build_embers() -> void:
	## Sparks thrown clear of the fire, falling under their own weight. They outlive the flame
	## so the burst has a tail rather than stopping dead.
	var pm := FireFx.process_material(FireFx.ember_ramp(), FireFx.shrink_curve())
	pm.emission_sphere_radius = 0.1
	pm.spread = 180.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.scale_min = 0.35
	pm.scale_max = 1.0

	_add_burst("Embers", FireFx.blob_quad(FireFx.TEX_SPARK, 0.22), pm, 30, 0.9)


func _build_smoke() -> void:
	var pm := FireFx.process_material(FireFx.smoke_ramp(), FireFx.swell_curve())
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -50.0
	pm.angular_velocity_max = 50.0
	pm.scale_min = 0.8
	pm.scale_max = 1.6

	_add_burst("Smoke", FireFx.blob_quad(FireFx.TEX_SMOKE, 0.75, false), pm, 16, 1.2)


func _add_burst(node_name: String, mesh: Mesh, pm: ParticleProcessMaterial,
		amount: int, lifetime: float) -> void:
	if mesh == null:
		return   # a pack mesh that failed to import — that layer is simply left out
	var p := FireFx.emitter(node_name, mesh, pm, amount, lifetime)
	p.one_shot = true
	p.explosiveness = 1.0   # the whole amount leaves on frame one
	p.randomness = 0.5
	add_child(p)


func _build_ring() -> void:
	## A flat scorch ring on the floor. Not particles: one quad whose scale and fade are driven
	## by a tween, which is both cheaper and easier to time against the flash than a
	## single-particle emitter would be.
	var tex: Texture2D = load(FireFx.TEX_RING)
	if tex == null:
		return
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_texture = tex
	_ring_material.albedo_color = Color(FireFx.FLAME, 0.9)
	_ring_material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _ring_material

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = quad
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Top level so the ring keeps the floor height set here rather than being dragged up to
	# the impact point by this node's own transform.
	ring.top_level = true
	add_child(ring)
	ring.global_position = Vector3(_at.x, _ground_y + 0.03, _at.z)
	ring.rotation_degrees = Vector3(-90, 0, 0)   # lay the quad flat on the floor
	ring.scale = Vector3.ONE * RING_START_SCALE

	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * RING_END_SCALE, RING_GROW_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_ring_material, "albedo_color:a", 0.0, RING_GROW_TIME) \
		.set_ease(Tween.EASE_IN)


func _build_flash() -> void:
	## The moment of ignition. Bright and very short — held any longer it stops reading as a
	## flash and starts lighting the room.
	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = Color(1.0, 0.72, 0.35)
	light.light_energy = 7.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
