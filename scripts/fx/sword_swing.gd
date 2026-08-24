extends Node3D
class_name SwordSwing
## The arc a blade cuts through the air: a bright crescent that snaps open across the target,
## rolls through the swing and is gone in under a third of a second.
##
## Spawned from Combatant._swing_arc for every melee strike, landed or not — this is the SWING,
## not the hit. A parried blow still had a blade come through it, and the arc is what sells the
## defender's "Parry!" as something they had to actually stop.
##
## Two crescents, not one: a wide soft outer sweep for the volume of the cut and a smaller,
## brighter inner one for the edge. Neither is a mesh — each is a single billboarded particle,
## which is what makes this hold up under the free orbit camera. A slash locked into a fixed
## world plane looks superb from one angle and disappears edge-on from another, and the player
## can put the camera anywhere; a billboard reads from all of them. The particle's own `angle`
## gives the diagonal that a plain BILLBOARD_ENABLED quad could not have, and its angular
## velocity is the sweep.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

## Hot at the edge, cooling into steel behind it. Both are lifted well above the mid-greys a
## first pass used: additive over the dungeon's pale stone eats a lot of the value, and an arc
## that was merely light grey came out looking like a solid plastic crescent rather than a
## blade catching the light.
const EDGE := Color(1.00, 1.00, 1.00)
const BODY := Color(0.72, 0.84, 1.00)

## Height of the outer crescent for an ordinary weapon, in metres. Width follows from the
## texture's 2:1 shape.
const ARC_HEIGHT := 0.85

## How far in front of the attacker the arc sits, in metres. An absolute distance rather than
## a fraction of the gap: melee is always adjacent so the two would agree, but a throw can be
## six tiles out, and a fraction would strand its arc halfway across the arena.
## 1.2 m puts a cut on the near side of a defender standing one tile away.
const SWING_DISTANCE := 1.2
## A cut's diagonal, steep enough that the crescent reads as a blade path and not as a rainbow.
const SWING_TILT := 64.0
const SWING_SWEEP := 200.0

## A throw is the same blade on a different path: the arm comes over the shoulder and the
## weapon leaves at the top. So the arc sits ON the thrower instead of on the target, stands
## almost upright, and whips through faster than a cut does.
## Close in to the thrower's own shoulder, wherever the target happens to be.
const THROW_DISTANCE := 0.5
const THROW_TILT := 86.0
const THROW_SWEEP := 310.0
## Above the attacker's body origin, which already sits at about chest height.
const ARC_LIFT := 0.15

## Short on purpose. A slash that outlives the animation frame it belongs to stops reading as
## a movement and starts reading as a decal hanging in the air.
const OUTER_LIFE := 0.22
const INNER_LIFE := 0.15
const LINGER := 0.4   ## node lifetime; must clear the longest of the two above

var _at := Vector3.ZERO
var _facing := Vector3.FORWARD
var _strength := 1.0
## Which way the blade travels across the target, as a screen-space roll in degrees. Steep,
## because a shallow crescent reads as a rainbow rather than as a cut, and flipped between the
## main hand and the off-hand so a dual-wielder's two strikes visibly cross.
var _tilt := 0.0
## How fast the crescent carries round, in degrees per second — the sweep of the blade itself.
var _sweep := SWING_SWEEP


static func swing(parent: Node, from: Vector3, toward: Vector3, strength: float = 1.0,
		mirrored: bool = false) -> void:
	## A melee cut across the target. `from` is the attacker's body origin, `toward` the
	## target's, `strength` roughly how big the weapon is (1.0 for an ordinary sword), and
	## `mirrored` flips the diagonal for an off-hand strike.
	_spawn(parent, from, toward, strength,
		SWING_TILT if mirrored else -SWING_TILT, SWING_DISTANCE, SWING_SWEEP)


static func hurl(parent: Node, from: Vector3, toward: Vector3, strength: float = 1.0) -> void:
	## The arm coming over on a throw. Same crescent, but tight to the thrower and near
	## vertical — the weapon it belongs to is about to leave the hand and fly the rest itself.
	_spawn(parent, from, toward, strength, THROW_TILT, THROW_DISTANCE, THROW_SWEEP)


static func _spawn(parent: Node, from: Vector3, toward: Vector3, strength: float,
		tilt: float, distance: float, sweep: float) -> void:
	var fx := SwordSwing.new()
	fx._strength = clampf(strength, 0.6, 1.6)
	fx._tilt = tilt
	fx._sweep = sweep
	var line := toward - from
	line.y = 0.0
	if line.length() > 0.01:
		fx._facing = line.normalized()
		fx._at = from + fx._facing * distance + Vector3(0, ARC_LIFT, 0)
	else:
		# Attacker and target on the same spot should not happen, but a zero-length line would
		# take look_at down with it, so the arc just goes off where the attacker stands.
		fx._at = from + Vector3(0, ARC_LIFT, 0)
	parent.add_child(fx)


func _ready() -> void:
	# Placed and aimed before anything emits: the emitters work in world space, so an arc that
	# started a frame early would flash at the arena origin.
	global_position = _at
	look_at(_at + _facing, Vector3.UP)
	# The edge arc lags the sweep by a few degrees rather than sitting concentric inside it —
	# two arcs on the same centre read as ripples, offset ones as a blade and its wake.
	_build_arc("Sweep", ARC_HEIGHT, _tilt, _sweep, OUTER_LIFE, Color(BODY, 0.8))
	_build_arc("Edge", ARC_HEIGHT * 0.78, _tilt - 16.0, _sweep * 1.25, INNER_LIFE, Color(EDGE, 1.0))
	for child in get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = true
	await get_tree().create_timer(LINGER).timeout
	queue_free()


func _build_arc(node_name: String, height: float, tilt: float, sweep: float,
		life: float, tint: Color) -> void:
	## One crescent. It is a single particle, so `angle` is the diagonal it starts at and
	## `angular_velocity` is how fast the blade carries it round; there is no randomness at all
	## because a swing is a deliberate movement, not a spray.
	# Brightest on the frame it appears and falling away immediately: a slash is a flash of
	# reflected light, so it has to be at full value the moment the eye lands on it.
	var pm := ParticleKit.process_material(
		ParticleKit.ramp([0.0, 0.35, 1.0], [tint, Color(tint, tint.a * 0.45), Color(tint, 0.0)]),
		_open_curve())
	pm.emission_sphere_radius = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.angle_min = tilt
	pm.angle_max = tilt
	pm.angular_velocity_min = sweep
	pm.angular_velocity_max = sweep
	pm.scale_min = _strength
	pm.scale_max = _strength

	var size := Vector2(height * ParticleKit.ARC_ASPECT, height)
	var p := ParticleKit.one_shot(ParticleKit.emitter(
		node_name, ParticleKit.sprite_quad(ParticleKit.TEX_ARC, size), pm, 1, life))
	p.randomness = 0.0   # one particle, one intended pose — nothing here should vary
	add_child(p)


func _open_curve() -> CurveTexture:
	## Snaps open, then stretches slightly as it goes. The arc has to arrive at nearly full
	## width on its first frame — a crescent that grew in from nothing would read as a portal
	## opening rather than as a blade already moving when you first see it.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.8))
	c.add_point(Vector2(0.2, 1.05))
	c.add_point(Vector2(1.0, 1.15))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex
