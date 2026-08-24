extends Node3D
## Preview harness for the Firebolt effects. Run `tools/preview_fire_fx.tscn` with summer_play
## to watch the bolt and the splash on a loop, without setting up a fight to cast one.
##
## Unlike its neighbours in tools/ this writes nothing — it is for tuning the numbers in
## scripts/fx/ by eye, and for checking that the Synty pack assets are still imported (it
## prints what it managed to load before the first shot).

const FireFx := preload("res://scripts/fx/fire_fx.gd")
const FireboltProjectileScript := preload("res://scripts/fx/firebolt_projectile.gd")
const FireSplashScript := preload("res://scripts/fx/fire_splash.gd")

## Roughly the geometry of a real cast: staff height, four tiles apart, chest-high target.
const FROM := Vector3(-4.0, 1.4, 0.0)
const TO := Vector3(4.0, 1.2, 0.0)
const GROUND_Y := 0.0
const PAUSE := 1.4


func _ready() -> void:
	_report_assets()
	_build_stage()
	while true:
		var bolt = FireboltProjectileScript.fire(self, FROM, TO)
		await bolt.impacted
		FireSplashScript.burst(self, TO, GROUND_Y)
		await get_tree().create_timer(PAUSE).timeout


func _report_assets() -> void:
	## The effects degrade quietly when a pack asset is missing, which is right in game and
	## unhelpful here — so say plainly what loaded.
	for path in [FireFx.TEX_BLOB, FireFx.TEX_SPARK, FireFx.TEX_SMOKE, FireFx.TEX_RING,
			FireFx.MESH_FLAME, FireFx.MESH_PUFF]:
		print("[preview_fire_fx] %s -> %s" % [path, "ok" if load(path) != null else "MISSING"])


func _build_stage() -> void:
	## A dark floor and a dim key light: the effects are additive, so they only read honestly
	## against something that is not already white.
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
	# Framed on the impact point rather than the whole flight path: the splash is the busier
	# of the two effects, and the bolt still crosses the frame on its way in.
	cam.position = Vector3(TO.x, 1.7, 5.5)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.current = true
	add_child(cam)
