extends Node3D
class_name ArrowProjectile
## An arrow in flight, from the bow to whatever it was loosed at, reporting back when it lands.
##
## The sibling of firebolt_projectile.gd and it works the same way: the shot is rolled on
## `impacted`, not at the click, so the damage number and the blood arrive with the arrow.
## Where the bolt is all particles, this is mostly one solid mesh — the same SM_Arrow_01 the
## quiver and the ammo pickup use, so what flies is recognisably what you picked up. The only
## particles are a thin scuff of air behind it, which is what sells the speed.
##
## Loose it with `loose()` and forget it — it frees itself once its wake has faded.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

## The game's own arrow, not one of the FX pack's flat arrow symbols. 0.93 units long, lying
## along its local Z with the shaft centred on the origin.
const ARROW_MESH := "res://assets/PolygonDungeon/Models/SM_Arrow_01.res"
const ARROW_MATERIAL := "res://assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"
## Fits the mesh to the game's proportions — a little under a metre, matching the arrows in
## the ground bundle so the two read as the same object.
const ARROW_SCALE := 0.9

## Emitted when the arrow reaches its target. Nothing else about the shot resolves before it.
signal impacted

## Metres per second. Faster than the Firebolt — an arrow that could be outrun would not read
## as one — but still slow enough to be seen crossing the arena.
const SPEED := 30.0
const MIN_FLIGHT := 0.12
const MAX_FLIGHT := 0.5

## How far the shaft bows upward at the midpoint. Bigger than the bolt's: an archer lofts a
## shot, and the arrow pitches nose-down on the way in because it stays tangent to the arc.
const ARC_HEIGHT := 0.35

## The wake takes a moment to die after the arrow stops, so the node outlives its own impact.
const WAKE_FADE := 0.35

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _duration := MIN_FLIGHT
var _elapsed := 0.0
var _flying := false

var _shaft: MeshInstance3D
var _wake: GPUParticles3D


static func loose(parent: Node, from: Vector3, to: Vector3) -> ArrowProjectile:
	## Build an arrow, put it in the world and loose it. Returns it so the caller can
	## `await arrow.impacted`.
	var arrow := ArrowProjectile.new()
	arrow._from = from
	arrow._to = to
	parent.add_child(arrow)
	return arrow


func _ready() -> void:
	_build_shaft()
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
	# Re-aimed every frame rather than once at launch: on an arc the heading keeps changing,
	# and an arrow that held its launch pitch would visibly fly sideways on the way down.
	_face_along(global_position - previous)
	if t >= 1.0:
		_impact()


func _point_at(t: float) -> Vector3:
	return _from.lerp(_to, t) + Vector3.UP * ARC_HEIGHT * sin(t * PI)


func _face_along(dir: Vector3) -> void:
	## look_at puts -Z down the direction of travel; the shaft is turned to match in
	## _build_shaft. A near-vertical heading is skipped rather than guarded with a different
	## up vector — arrows here are always loosed roughly level, and holding the previous
	## rotation for one frame is invisible where a look_at error is not.
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	look_at(global_position + dir, Vector3.UP)


func _impact() -> void:
	_flying = false
	global_position = _to
	if _shaft:
		# The arrow is spent at this point. It does not stick in the target — that would need
		# somewhere to live on a body that is about to play a hit or death animation — so it
		# simply stops being drawn, and the blood is what says it arrived.
		_shaft.visible = false
	if _wake:
		_wake.emitting = false
	impacted.emit()
	await get_tree().create_timer(WAKE_FADE).timeout
	queue_free()


# --- Construction ----------------------------------------------------------

func _build_shaft() -> void:
	var mesh: Mesh = load(ARROW_MESH)
	if mesh == null:
		return
	_shaft = MeshInstance3D.new()
	_shaft.name = "Shaft"
	_shaft.mesh = mesh
	# The Synty atlas, the same override the quiver and the ground bundle use — without it the
	# mesh takes the whole atlas across itself and comes out in unrelated stripes.
	var mat: Material = load(ARROW_MATERIAL)
	if mat:
		_shaft.material_override = mat
	_shaft.scale = Vector3.ONE * ARROW_SCALE
	# The mesh runs along +Z with the head forward; this node's forward is -Z, so turn it
	# about. Getting this backwards flies the arrow fletching-first, which reads immediately.
	_shaft.rotation_degrees = Vector3(0, 180, 0)
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shaft)


func _build_wake() -> void:
	## A scuff of disturbed air dragging behind the head. Deliberately at the edge of visible:
	## its whole job is to give the eye something continuous to follow between frames, because
	## a small solid mesh crossing the arena in a third of a second otherwise strobes. Any
	## heavier and the arrow reads as smoking, or as a fired shell rather than a loosed shaft —
	## which is exactly what a first pass at these numbers looked like.
	var pm := ParticleKit.process_material(
		ParticleKit.ramp([0.0, 0.35, 1.0],
			[Color(0.75, 0.73, 0.70, 0.09), Color(0.62, 0.60, 0.57, 0.05), Color(0.6, 0.6, 0.6, 0.0)]),
		ParticleKit.shrink_curve())
	ParticleKit.trail_along_travel(pm, 0.55, 0.04)
	pm.direction = Vector3(0, 0, 1)   # drift backwards out of the arrow's path
	pm.spread = 12.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	ParticleKit.spin(pm, 60.0)
	pm.scale_min = 0.25
	pm.scale_max = 0.6

	# Blended, not additive: a glowing arrow would look enchanted, and this one is just wood.
	_wake = ParticleKit.emitter(
		"Wake", ParticleKit.blob_quad(ParticleKit.TEX_BLOB, 0.16, false), pm, 34, WAKE_FADE)
	_wake.randomness = 0.5
	add_child(_wake)
