extends Node3D
class_name ParrySparks
## Steel on steel: the shower of sparks where a parry catches an incoming blade, plus the
## white glint of the two edges meeting and a moment of light off it.
##
## Spawned from Combatant._parry_sparks whenever a parry succeeds. It is the counterpart to
## blood_splash.gd — one says the blow went in, this one says it did not — and the pair is
## what makes the defender's floating "Parry!" read as something they had to physically stop
## rather than as a number that happened to come up.
##
## Nothing here is a mesh. Sparks are the pack's sparkle sprite, which already has the
## four-pointed star shape a struck spark wants, so the whole effect is three quad emitters
## and a light.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

## Struck steel throws a white-hot spark that cools to yellow and then to a dull orange as it
## falls. All additive — unlike blood, sparks genuinely are light.
const HOT := Color(1.00, 1.00, 0.93)
const WARM := Color(1.00, 0.86, 0.42)
const COOL := Color(1.00, 0.48, 0.10)

## Where the blades meet, along the line from the defender to whoever swung. Short, because
## the parry happens at arm's length — the two are standing on adjacent tiles.
const CONTACT_REACH := 0.55
## Above the body origin, which already sits at about chest height. Slightly higher than a
## wound, since a blade is caught up near the shoulder rather than taken in the ribs.
const CONTACT_LIFT := 0.2

const LINGER := 0.9   ## node lifetime; must clear the longest emitter below

var _at := Vector3.ZERO
var _facing := Vector3.FORWARD
var _strength := 1.0


static func clash(parent: Node, defender_at: Vector3, attacker_at: Vector3,
		strength: float = 1.0) -> void:
	## `defender_at` and `attacker_at` are the two body origins; the sparks go off between
	## them. No ground height, unlike the blood and the Firebolt: sparks burn out in the air
	## and leave nothing on the floor to place.
	var fx := ParrySparks.new()
	fx._strength = clampf(strength, 0.6, 1.5)
	var line := attacker_at - defender_at
	line.y = 0.0
	if line.length() > 0.01:
		fx._facing = line.normalized()
		fx._at = defender_at + fx._facing * CONTACT_REACH + Vector3(0, CONTACT_LIFT, 0)
	else:
		fx._at = defender_at + Vector3(0, CONTACT_LIFT, 0)
	parent.add_child(fx)


func _ready() -> void:
	# Placed and aimed before anything emits: the emitters work in world space, and each one's
	# `direction` is read through this node's own basis.
	global_position = _at
	look_at(_at + _facing, Vector3.UP)
	_build_sparks()
	_build_glint()
	_build_flash()
	for child in get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = true
	await get_tree().create_timer(LINGER).timeout
	queue_free()


# --- Layers ----------------------------------------------------------------

func _build_sparks() -> void:
	## The shower. Fast, thin and falling hard — a struck spark is a fleck of hot metal, so it
	## flies almost ballistically and dies where it lands. Barely damped for the same reason:
	## anything that slowed to a drift would read as an ember from the Firebolt instead.
	var pm := ParticleKit.process_material(
		ParticleKit.ramp([0.0, 0.3, 0.8, 1.0],
			[HOT, WARM, Color(COOL, 0.9), Color(COOL, 0.0)]),
		ParticleKit.shrink_curve())
	pm.emission_sphere_radius = 0.07
	# Out of the clash and upward, in a very wide fan: the blade skids off at an angle nobody
	# can predict, which is exactly what a near-hemisphere of directions looks like.
	pm.direction = Vector3(0, 0.5, -1)
	pm.spread = 85.0
	pm.initial_velocity_min = _speed(3.5)
	pm.initial_velocity_max = _speed(9.0)
	pm.gravity = Vector3(0, -14.0, 0)
	pm.damping_min = 0.0
	pm.damping_max = 0.8
	ParticleKit.spin(pm, 360.0)
	pm.scale_min = 0.3
	pm.scale_max = 0.9

	_add_burst("Sparks", ParticleKit.blob_quad(ParticleKit.TEX_SPARK, 0.15), 26, 0.45, pm)


func _build_glint() -> void:
	## The two edges meeting: one big star, held still, gone almost immediately. This is the
	## part the eye actually reads as "that was stopped"; the shower is the decoration around it.
	var pm := ParticleKit.process_material(
		ParticleKit.ramp([0.0, 0.4, 1.0], [HOT, Color(WARM, 0.8), Color(WARM, 0.0)]),
		ParticleKit.puff_curve())
	pm.emission_sphere_radius = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.angle_min = -25.0
	pm.angle_max = 25.0
	pm.angular_velocity_min = -70.0
	pm.angular_velocity_max = 70.0
	pm.scale_min = _strength
	pm.scale_max = _strength

	# scale_count off: the glint is the single point where the blades met, and a heavy blow
	# should make it bigger (which scale_min/max above already does), not make two of them.
	_add_burst("Glint", ParticleKit.blob_quad(ParticleKit.TEX_SPARK, 0.9), 1, 0.16, pm, false)


func _add_burst(node_name: String, mesh: Mesh, amount: int, life: float,
		pm: ParticleProcessMaterial, scale_count: bool = true) -> void:
	var scaled: int = maxi(1, roundi(amount * _strength)) if scale_count else amount
	add_child(ParticleKit.one_shot(ParticleKit.emitter(node_name, mesh, pm, scaled, life)))


func _build_flash() -> void:
	## A hard, very short pulse of light. Weaker and shorter than the Firebolt's — struck steel
	## is a spark, not an explosion — but enough that the parry registers even with the camera
	## turned away from the two fighters.
	var light := OmniLight3D.new()
	light.name = "Flash"
	light.light_color = WARM
	light.light_energy = 3.0 * _strength
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.16) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _speed(base: float) -> float:
	## As in blood_splash: a heavier blow throws sparks further, but only a little. Most of the
	## weight of a parry is carried by how many there are.
	return base * (0.8 + 0.2 * _strength)
