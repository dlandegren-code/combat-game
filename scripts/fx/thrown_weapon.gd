extends Node3D
class_name ThrownWeapon
## A hurled weapon in flight: the actual axe, sword or dagger that left the thrower's hand,
## tumbling end over end across the arena and reporting back when it arrives.
##
## The third of the projectiles, after firebolt_projectile.gd and arrow_projectile.gd, and it
## resolves the same way — the throw is rolled on `impacted`, not at the click.
##
## What flies is a COPY OF THE MODEL THAT WAS IN THE HAND, handed in by the caller, rather than
## anything this file looks up. Resolving a weapon's model from its ItemResource is a
## thirty-line affair with a data-driven path, a name-based fallback table and per-type scaling
## (see Combatant._refresh_socket and ground_item.gd), and it already exists twice; a third copy
## here would be the one that quietly went out of date. Duplicating the node the character is
## visibly holding is also simply more correct — whatever you saw in the fist is what you see
## in the air.
##
## Throw it with `hurl()` and forget it — it frees itself once its wake has faded.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

## Emitted when the weapon reaches its target. Nothing else about the throw resolves before it.
signal impacted

## Metres per second. Slower than an arrow and much slower than the Firebolt: a thrown axe is
## a heavy object leaving a shoulder, and it should look like one.
const SPEED := 16.0
const MIN_FLIGHT := 0.18
const MAX_FLIGHT := 0.7

## A thrown weapon is lobbed far more than an arrow is loosed, so it bows a good deal higher.
const ARC_HEIGHT := 0.65

## Degrees per second the weapon tumbles about its own horizontal axis — about three quarters
## of a turn over a typical flight. Unmistakably end-over-end rather than a shape sliding
## sideways, but not so fast that a flat blade spends half its frames edge-on and strobes.
const TUMBLE := 540.0

const WAKE_FADE := 0.4

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _duration := MIN_FLIGHT
var _elapsed := 0.0
var _flying := false

var _visual: Node3D
var _spin: Node3D
var _wake: GPUParticles3D


static func hurl(parent: Node, from: Vector3, to: Vector3, visual: Node3D) -> ThrownWeapon:
	## `visual` is a detached, unparented copy of the weapon's model — see the note above.
	## Returns the projectile so the caller can `await weapon.impacted`.
	var fx := ThrownWeapon.new()
	fx._from = from
	fx._to = to
	fx._visual = visual
	parent.add_child(fx)
	return fx


func _ready() -> void:
	_build_visual()
	_build_wake()
	_launch()


func _launch() -> void:
	_duration = clampf(_from.distance_to(_to) / SPEED, MIN_FLIGHT, MAX_FLIGHT)
	_elapsed = 0.0
	global_position = _from
	_face_along(_to - _from)
	if _wake:
		_wake.emitting = true
	_flying = true


func _process(delta: float) -> void:
	if not _flying:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var previous := global_position
	global_position = _point_at(t)
	_face_along(global_position - previous)
	if _spin:
		# About the local X — the axis across the direction of travel — so the weapon cartwheels
		# through the vertical plane it was thrown in rather than spinning like a top.
		_spin.rotate_object_local(Vector3.RIGHT, deg_to_rad(TUMBLE) * delta)
	if t >= 1.0:
		_impact()


func _point_at(t: float) -> Vector3:
	return _from.lerp(_to, t) + Vector3.UP * ARC_HEIGHT * sin(t * PI)


func _face_along(dir: Vector3) -> void:
	## look_at puts -Z down the direction of travel. A near-vertical heading is skipped rather
	## than guarded with a different up vector — weapons here are thrown roughly level, and
	## holding the previous rotation for one frame is invisible where a look_at error is not.
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	look_at(global_position + dir, Vector3.UP)


func _impact() -> void:
	_flying = false
	global_position = _to
	if _spin:
		# The weapon stops being drawn here. It is not left stuck in anyone: the throw already
		# ends by dropping a real, pickup-able ground item on a nearby tile, and a second copy
		# hanging off the target would be a weapon that cannot be retrieved.
		_spin.visible = false
	if _wake:
		_wake.emitting = false
	impacted.emit()
	await get_tree().create_timer(WAKE_FADE).timeout
	queue_free()


# --- Construction ----------------------------------------------------------

func _build_visual() -> void:
	if _visual == null:
		return
	# A pivot between this node and the model, so the tumble is applied on top of whatever
	# hand-relative rotation the model came out of the socket with instead of fighting it.
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	# Re-centred: the copy still carries the offset that put it in a fist.
	_visual.position = Vector3.ZERO
	_spin.add_child(_visual)


func _build_wake() -> void:
	## The same near-invisible scuff of air the arrow leaves, and for the same reason: a solid
	## object crossing the arena in half a second strobes without something continuous behind it.
	var pm := ParticleKit.process_material(
		ParticleKit.ramp([0.0, 0.35, 1.0],
			[Color(0.75, 0.73, 0.70, 0.10), Color(0.62, 0.60, 0.57, 0.06), Color(0.6, 0.6, 0.6, 0.0)]),
		ParticleKit.shrink_curve())
	ParticleKit.trail_along_travel(pm, 0.4, 0.07)
	pm.direction = Vector3(0, 0, 1)   # drift backwards out of the weapon's path
	pm.spread = 16.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.6
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	ParticleKit.spin(pm, 60.0)
	pm.scale_min = 0.3
	pm.scale_max = 0.8

	# Blended, not additive: a glowing axe would look enchanted, and this one is just iron.
	_wake = ParticleKit.emitter(
		"Wake", ParticleKit.blob_quad(ParticleKit.TEX_BLOB, 0.22, false), pm, 34, WAKE_FADE)
	_wake.randomness = 0.5
	add_child(_wake)
