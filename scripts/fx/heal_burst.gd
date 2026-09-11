extends Node3D
class_name HealBurst
## The bloom of a wound closing: motes rising off a character, a few bright sparks, and a ring
## of light at their feet.
##
## Rises rather than bursts, which is the whole difference between this and fire_splash.gd. An
## impact throws everything outward in one frame; a heal wells UP from the floor and gathers, so
## the emitters are given upward velocity, low spread and a lifetime long enough to travel a
## body's height. Read at a glance, a burst means something hit and a bloom means something
## mended.
##
## Spawned by Combatant.heal — the one place hit points go up, so a potion, a spell and anything
## added later all bloom without being taught to.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")
const HealFx := preload("res://scripts/fx/heal_fx.gd")
const AudioKit := preload("res://scripts/fx/audio_kit.gd")

## How long the node lives. Must clear the longest lifetime below, or a layer is cut short.
const LINGER := 1.6
## How far up the motes travel, roughly, in metres — about a character's height.
const RISE := 1.8

## --- The signs ---
##
## Five carved rune plates from the dungeon pack, stood upright on a circle about the character
## and turned outward, orbiting as they rise and fade. The pack ships them as scenery — the
## rune stones set into walls — and at a third of their size, tinted and lit from nowhere, they
## read as glyphs a spell has called up rather than as masonry.
##
## Five, not eight: enough to read as a circle from any angle, few enough that each one is a
## distinct shape rather than a green smear.
const RUNE_MESHES := [
	"res://Assets/PolygonDungeon/Models/SM_Env_Rune_Rounded_01.res",
	"res://Assets/PolygonDungeon/Models/SM_Env_Rune_Square_01.res",
	"res://Assets/PolygonDungeon/Models/SM_Env_Rune_Rounded_03.res",
	"res://Assets/PolygonDungeon/Models/SM_Env_Rune_Square_04.res",
	"res://Assets/PolygonDungeon/Models/SM_Env_Rune_Rounded_05.res",
]
const RUNE_RADIUS := 0.85
const RUNE_SCALE := 0.30
## Degrees a second. Fast enough to be clearly turning inside the effect's short life, slow
## enough that a rune is legible as it passes.
const RUNE_SPIN := 170.0
## How far the ring climbs, and how long the signs last — shorter than LINGER so they are gone
## before the motes are, leaving the last of the effect soft rather than geometric.
const RUNE_RISE := 0.8
const RUNE_TIME := 1.15
## The floor ring turns too, the other way, so the two read as one mechanism rather than two
## unrelated green things.
const FLOOR_SPIN := -60.0

## The ring at the feet: grows outward and fades, laid flat on the floor.
const RING_TIME := 0.55
const RING_START_SCALE := 0.25
const RING_END_SCALE := 1.6

const CLIPS := [
	"res://assets/audio/spells/heal_1.mp3",
	"res://assets/audio/spells/heal_2.mp3",
	"res://assets/audio/spells/heal_3.mp3",
	"res://assets/audio/spells/heal_4.mp3",
]
## Above the wound sounds it is meant to answer, and clean enough to carry over a fight.
const VOLUME_DB := -5.0

var _at := Vector3.ZERO
var _ground_y := 0.0
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _light: OmniLight3D
var _runes: Node3D
var _rune_material: StandardMaterial3D
var _elapsed := 0.0


static func bloom(parent: Node, at: Vector3, ground_y: float) -> void:
	## `at` is the character's middle and `ground_y` the floor under them. Separate, for the
	## same reason FireSplash keeps them apart: the ring belongs on the floor even when the
	## body above it is tall.
	if parent == null or not parent.is_inside_tree():
		return
	var fx := HealBurst.new()
	fx._at = at
	fx._ground_y = ground_y
	parent.add_child(fx)


func _ready() -> void:
	# Positioned before anything emits: the emitters work in world space, so a bloom that
	# started a frame early would go off at the arena origin.
	global_position = _at
	_build_motes()
	_build_sparks()
	_build_runes()
	_build_ring()
	_build_light()
	AudioKit.one_shot(get_parent(), _at, AudioKit.pick(CLIPS), VOLUME_DB, 0.04)
	await get_tree().create_timer(LINGER).timeout
	queue_free()


func _process(delta: float) -> void:
	_elapsed += delta
	if _ring_material:
		var t: float = clampf(_elapsed / RING_TIME, 0.0, 1.0)
		var s: float = lerpf(RING_START_SCALE, RING_END_SCALE, t)
		_ring.scale = Vector3(s, 1.0, s)
		# Fades as it grows, so the ring reads as spreading light rather than a solid disc
		# sitting on the floor.
		_ring_material.albedo_color.a = (1.0 - t) * 0.8
	if _light:
		# Brightest at the moment the wound closes, then out.
		_light.light_energy = maxf(0.0, 2.6 * (1.0 - _elapsed / RING_TIME))
	if _runes:
		var rt: float = clampf(_elapsed / RUNE_TIME, 0.0, 1.0)
		_runes.rotate_y(deg_to_rad(RUNE_SPIN) * delta)
		_runes.position.y = RUNE_RISE * rt
		if _rune_material:
			# Up fast, out slow: the signs snap into being and then dissolve, rather than
			# easing in as if somebody were turning a dial.
			var fade: float = minf(rt / 0.15, 1.0) * (1.0 - smoothstep(0.55, 1.0, rt))
			_rune_material.albedo_color.a = fade
	if _ring:
		_ring.rotate_y(deg_to_rad(FLOOR_SPIN) * delta)


func _build_motes() -> void:
	## The body of the effect: soft points welling up around the character.
	var pm := ParticleKit.process_material(HealFx.mote_ramp(), ParticleKit.swell_curve())
	# A cylinder of emission around the feet rather than a point, so the motes come off the
	# whole body instead of squirting out of one spot.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = RISE * 0.45
	pm.initial_velocity_max = RISE * 0.85
	# Gently upward: healing does not fall back down.
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	ParticleKit.spin(pm, 45.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	var p := ParticleKit.emitter(
		"Motes", ParticleKit.blob_quad(ParticleKit.TEX_BLOB, 0.34), pm, 44, 1.15)
	p.randomness = 0.5
	add_child(ParticleKit.one_shot(p))


func _build_sparks() -> void:
	var pm := ParticleKit.process_material(HealFx.spark_ramp(), ParticleKit.shrink_curve())
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = RISE * 0.7
	pm.initial_velocity_max = RISE * 1.3
	pm.gravity = Vector3(0, 0.2, 0)
	ParticleKit.spin(pm, 180.0)
	pm.scale_min = 0.35
	pm.scale_max = 0.8
	var p := ParticleKit.emitter(
		"Sparks", ParticleKit.blob_quad(ParticleKit.TEX_SPARK, 0.16), pm, 18, 0.9)
	p.randomness = 0.6
	add_child(ParticleKit.one_shot(p))


func _build_runes() -> void:
	## A ring of upright signs, turned to face outward from the character they surround.
	##
	## The orientation is built rather than guessed at with Euler angles: these plates lie flat
	## in XZ with their carved face pointing along Y, so the face is swung to -Z first and then
	## aimed outward. Written as a composed basis because the same thing in rotation_degrees
	## depends on Godot's rotation order and reads as three magic numbers.
	_runes = Node3D.new()
	_runes.name = "Runes"
	add_child(_runes)

	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = Color(HealFx.PALE, 1.0)
	_rune_material.emission_enabled = true
	_rune_material.emission = HealFx.LEAF
	_rune_material.emission_energy_multiplier = 2.2
	_rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rune_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rune_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rune_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rune_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	# Face swung from +Y to -Z, which is the direction Basis.looking_at aims.
	var upright := Basis.from_euler(Vector3(deg_to_rad(-90), 0, 0))
	for i in range(RUNE_MESHES.size()):
		var mesh: Mesh = load(RUNE_MESHES[i])
		if mesh == null:
			continue
		var angle: float = TAU * float(i) / float(RUNE_MESHES.size())
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var mi := MeshInstance3D.new()
		mi.name = "Rune%d" % i
		mi.mesh = mesh
		mi.material_override = _rune_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = outward * RUNE_RADIUS
		mi.basis = (Basis.looking_at(outward, Vector3.UP) * upright).scaled(
			Vector3.ONE * RUNE_SCALE)
		_runes.add_child(mi)


func _build_ring() -> void:
	## A flat disc on the floor that grows and fades — see _process. Built as a quad laid down
	## rather than as particles, because one clean expanding circle reads better than a ring of
	## points trying to be one.
	var tex: Texture2D = load(ParticleKit.TEX_RING)
	if tex == null:
		return
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_texture = tex
	_ring_material.albedo_color = HealFx.LEAF
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# No depth write, or the floor tile under it fights the ring for the same pixels.
	_ring_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = mesh
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Laid flat, and just clear of the floor so it does not z-fight the tile it sits on.
	_ring.rotation_degrees = Vector3(-90, 0, 0)
	_ring.position = Vector3(0, _ground_y - _at.y + 0.02, 0)
	add_child(_ring)


func _build_light() -> void:
	## A real light, so the heal lifts the character and the floor around them for a moment —
	## the same trick the Firebolt uses, in the opposite colour.
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = HealFx.LEAF
	_light.light_energy = 2.6
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(_light)
