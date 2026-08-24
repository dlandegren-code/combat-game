extends Node3D
class_name FireboltProjectile
## The Firebolt in flight: a Synty flame with a burning trail, thrown from the caster's staff
## to the target, which reports back the moment it arrives.
##
## The bolt owns the timing of the spell, not just its look. player.gd waits on `impacted`
## before rolling the attack, so the damage lands when the fire does rather than at the click.
## Travel time is therefore clamped at both ends: a point-blank bolt still has to be *seen*
## (MIN_FLIGHT), and a bolt across the whole arena must not leave the turn hanging (MAX_FLIGHT).
##
## Launch it with `fire()` and forget it — it frees itself once the trail it left behind has
## burned out.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")
const FireFx := preload("res://scripts/fx/fire_fx.gd")

## Emitted when the bolt reaches its target. Nothing else about the spell resolves before it.
signal impacted

## Metres per second. Fast enough to read as a bolt rather than a lobbed fireball, slow enough
## that the trail is still a ribbon rather than a dashed line at 30 fps.
const SPEED := 16.0
const MIN_FLIGHT := 0.16
const MAX_FLIGHT := 0.65

## How far the bolt bows upward at the midpoint. Just enough to look thrown rather than
## rail-straight; any more and it starts to read as a grenade.
const ARC_HEIGHT := 0.22

## Longest particle lifetime in the trail. The node has to outlive its own trail, or the fire
## it already dropped disappears with it the instant the bolt lands.
const TRAIL_FADE := 0.75

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _duration := MIN_FLIGHT
var _elapsed := 0.0
var _flying := false

var _core: Node3D
var _light: OmniLight3D
var _emitters: Array[GPUParticles3D] = []


static func fire(parent: Node, from: Vector3, to: Vector3) -> FireboltProjectile:
	## Build a bolt, put it in the world and launch it. Returns the bolt so the caller can
	## `await bolt.impacted`.
	var bolt := FireboltProjectile.new()
	bolt._from = from
	bolt._to = to
	# Everything is set up before the node enters the tree, so _ready() can place and light
	# the bolt on its very first frame — a world-space trail that starts one frame early
	# leaves a puff of fire at the arena origin.
	parent.add_child(bolt)
	return bolt


func _ready() -> void:
	_build_core()
	_build_trail()
	_build_embers()
	_build_smoke()
	_build_light()
	_launch()


func _launch() -> void:
	_duration = clampf(_from.distance_to(_to) / SPEED, MIN_FLIGHT, MAX_FLIGHT)
	_elapsed = 0.0
	global_position = _from
	_face_along(_to - _from)
	for p in _emitters:
		p.emitting = true
	_flying = true


func _process(delta: float) -> void:
	if not _flying:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var previous := global_position
	global_position = _point_at(t)
	_face_along(global_position - previous)
	# A slow roll about the direction of travel. The flame is a six-sided cone, so without
	# this its silhouette is dead still for the whole flight.
	if _core:
		_core.rotate_object_local(Vector3.FORWARD, delta * 7.0)
	if t >= 1.0:
		_impact()


func _point_at(t: float) -> Vector3:
	return _from.lerp(_to, t) + Vector3.UP * ARC_HEIGHT * sin(t * PI)


func _face_along(dir: Vector3) -> void:
	## look_at points -Z down the direction of travel, which is what the flame and the trail
	## are both built around. A near-vertical direction is skipped rather than guarded with a
	## different up vector: the bolt is always fired roughly horizontally, and holding the
	## previous rotation for one frame is invisible where a look_at error is not.
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	look_at(global_position + dir, Vector3.UP)


func _impact() -> void:
	_flying = false
	global_position = _to
	if _core:
		_core.visible = false
	if _light:
		_light.visible = false
	for p in _emitters:
		p.emitting = false
	impacted.emit()
	# Stay alive — silently — long enough for the fire already hanging in the air behind us to
	# burn out on its own. Freeing here would snip the trail off mid-flight.
	await get_tree().create_timer(TRAIL_FADE).timeout
	queue_free()


# --- Construction ----------------------------------------------------------

func _build_core() -> void:
	## Two nested flames: a wide dim one for the glow, a small bright one for the hot centre.
	## Both are rotated to trail *backwards* (+Z, away from the -Z the node points along), so
	## the teardrop's point streams behind the bolt like a comet rather than leading it.
	_core = Node3D.new()
	_core.name = "Core"
	add_child(_core)

	var outer := _flame_instance(FireFx.FLAME, 0.42, 1.0)
	if outer:
		_core.add_child(outer)
	var inner := _flame_instance(FireFx.HOT, 0.24, 0.62)
	if inner:
		_core.add_child(inner)


func _flame_instance(tint: Color, height: float, width_ratio: float) -> MeshInstance3D:
	var mesh := ParticleKit.tinted_mesh(ParticleKit.MESH_FLAME, tint)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var s: float = height * ParticleKit.FLAME_MESH_UNIT
	mi.scale = Vector3(s * width_ratio, s, s * width_ratio)
	# The mesh grows along +Y from its base; +90 degrees about X lays that down onto +Z.
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_trail() -> void:
	var pm := ParticleKit.process_material(FireFx.fire_ramp(), ParticleKit.shrink_curve())
	ParticleKit.trail_along_travel(pm, 0.5)
	# Fire wants to climb, and puffs shed off the sides of the bolt rather than being pushed
	# along by it. The bolt outruns them either way — that is what makes the trail.
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 1.1, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	ParticleKit.spin(pm, 90.0)
	pm.scale_min = 0.75
	pm.scale_max = 1.15

	# Dense, and big enough that neighbouring puffs overlap into a continuous ribbon of fire.
	var p := ParticleKit.emitter(
		"Trail", ParticleKit.blob_quad(ParticleKit.TEX_BLOB, 0.7), pm, 110, 0.5)
	p.randomness = 0.35
	add_child(p)
	_emitters.append(p)


func _build_embers() -> void:
	var pm := ParticleKit.process_material(FireFx.ember_ramp(), ParticleKit.shrink_curve())
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0, 0, 1)   # shed backwards, along the trail
	pm.spread = 55.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, -2.2, 0)  # sparks are heavy enough to fall out of the trail
	ParticleKit.spin(pm, 240.0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0

	var p := ParticleKit.emitter(
		"Embers", ParticleKit.blob_quad(ParticleKit.TEX_SPARK, 0.18), pm, 40, 0.55)
	p.randomness = 0.6
	add_child(p)
	_emitters.append(p)


func _build_smoke() -> void:
	var pm := ParticleKit.process_material(FireFx.smoke_ramp(), ParticleKit.swell_curve())
	ParticleKit.trail_along_travel(pm, 0.5, 0.08)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.5, 0)
	ParticleKit.spin(pm, 40.0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9

	# Smoke is the one layer that is NOT additive — additive smoke brightens whatever it
	# drifts over, which is the opposite of what smoke does. Thin and sparse: it is here to
	# dirty the wake, not to be seen in its own right (see FireFx.smoke_ramp).
	var p := ParticleKit.emitter(
		"Smoke", ParticleKit.blob_quad(ParticleKit.TEX_SMOKE, 0.45, false), pm, 12, TRAIL_FADE)
	p.randomness = 0.5
	add_child(p)
	_emitters.append(p)


func _build_light() -> void:
	## A real light, so the bolt actually lifts the floor and the walls it passes. Cheap:
	## shadows off, short range, and it lives for well under a second.
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = FireFx.FLAME
	_light.light_energy = 3.0
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(_light)
