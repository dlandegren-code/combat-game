extends Node3D
## Preview harness for the combat effects in scripts/fx/. Run `tools/preview_fx.tscn` with
## summer_play to watch a Firebolt and a bowshot alternate on a loop, without having to set up
## a fight and win the initiative to see one.
##
## Unlike its neighbours in tools/ this writes nothing — it is for tuning the numbers in
## scripts/fx/ by eye, and for checking that the pack assets are still imported (it prints what
## it managed to load before the first shot, since the effects themselves fail quietly).

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")
const FireboltProjectileScript := preload("res://scripts/fx/firebolt_projectile.gd")
const FireSplashScript := preload("res://scripts/fx/fire_splash.gd")
const ArrowProjectileScript := preload("res://scripts/fx/arrow_projectile.gd")
const BloodSplashScript := preload("res://scripts/fx/blood_splash.gd")

## Roughly the geometry of a real shot: weapon height, four tiles apart, chest-high target.
const FROM := Vector3(-4.0, 1.4, 0.0)
const TO := Vector3(4.0, 1.2, 0.0)
const GROUND_Y := 0.0
const PAUSE := 1.6


func _ready() -> void:
	_report_assets()
	_build_stage()
	while true:
		await _firebolt()
		await get_tree().create_timer(PAUSE).timeout
		await _bowshot()
		await get_tree().create_timer(PAUSE).timeout
		# The two ends of Combatant._spill_blood's strength range, back to back, so a scratch
		# and a crit can be compared without waiting for the dice to produce both.
		_melee_hit(0.5)
		await get_tree().create_timer(PAUSE).timeout
		_melee_hit(1.6)
		await get_tree().create_timer(PAUSE).timeout


func _firebolt() -> void:
	var bolt = FireboltProjectileScript.fire(self, FROM, TO)
	await bolt.impacted
	FireSplashScript.burst(self, TO, GROUND_Y)


func _bowshot() -> void:
	var arrow = ArrowProjectileScript.loose(self, FROM, TO)
	await arrow.impacted
	BloodSplashScript.burst(self, TO, TO - FROM, GROUND_Y)


func _melee_hit(strength: float) -> void:
	## Blood with no projectile in front of it — what a sword or a shove into a wall looks like.
	BloodSplashScript.burst(self, TO, TO - FROM, GROUND_Y, strength)


func _report_assets() -> void:
	## The effects degrade quietly when a pack asset is missing, which is right in game and
	## unhelpful here — so say plainly what loaded.
	for path in [ParticleKit.TEX_BLOB, ParticleKit.TEX_DOT, ParticleKit.TEX_SPARK,
			ParticleKit.TEX_SMOKE, ParticleKit.TEX_RING, ParticleKit.MESH_FLAME,
			ParticleKit.MESH_PUFF, ParticleKit.MESH_CHUNK_SMALL, ParticleKit.MESH_CHUNK_LONG,
			ArrowProjectileScript.ARROW_MESH]:
		print("[preview_fx] %s -> %s" % [path, "ok" if load(path) != null else "MISSING"])


func _build_stage() -> void:
	## A dark floor and a dim key light: the fire is additive and only reads honestly against
	## something that is not already white, and the blood needs somewhere to stain.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.16, 0.18)
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	plane.material = floor_mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, GROUND_Y, 0)
	add_child(ground)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 0.35
	add_child(key)

	var cam := Camera3D.new()
	# Framed on the impact point rather than the whole flight path: the splashes are the busier
	# half of each effect, and the projectile still crosses the frame on its way in.
	cam.position = Vector3(TO.x, 1.7, 5.5)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.current = true
	add_child(cam)
