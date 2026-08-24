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
const SwordSwingScript := preload("res://scripts/fx/sword_swing.gd")
const ParrySparksScript := preload("res://scripts/fx/parry_sparks.gd")
const ThrownWeaponScript := preload("res://scripts/fx/thrown_weapon.gd")

## Roughly the geometry of a real shot: weapon height, four tiles apart, chest-high target.
const FROM := Vector3(-4.0, 1.4, 0.0)
const TO := Vector3(4.0, 1.2, 0.0)
const GROUND_Y := 0.0
const PAUSE := 1.6
## Melee happens toe to toe, one tile apart, so the swing gets its own start point rather than
## reusing the archer's — an arc placed 62% of eight metres away would land nowhere near TO.
const MELEE_FROM := Vector3(TO.x - 2.0, 1.3, 0.0)


func _ready() -> void:
	_report_assets()
	_build_stage()
	while true:
		await _firebolt()
		await get_tree().create_timer(PAUSE).timeout
		await _bowshot()
		await get_tree().create_timer(PAUSE).timeout
		await _melee_hit(0.5, false)
		await get_tree().create_timer(PAUSE).timeout
		await _melee_hit(1.6, true)
		await get_tree().create_timer(PAUSE).timeout
		await _parried_hit()
		await get_tree().create_timer(PAUSE).timeout
		await _thrown_weapon()
		await get_tree().create_timer(PAUSE).timeout


func _firebolt() -> void:
	var bolt = FireboltProjectileScript.fire(self, FROM, TO)
	await bolt.impacted
	FireSplashScript.burst(self, TO, GROUND_Y)


func _bowshot() -> void:
	var arrow = ArrowProjectileScript.loose(self, FROM, TO)
	await arrow.impacted
	BloodSplashScript.burst(self, TO, TO - FROM, GROUND_Y)


func _melee_hit(strength: float, mirrored: bool) -> void:
	## A sword strike end to end: the arc across the target, then the wound it opens. Run at
	## both ends of the strength range so a scratch and a crit can be compared without waiting
	## for the dice to produce one of each.
	SwordSwingScript.swing(self, MELEE_FROM, TO, strength, mirrored)
	# Roughly where the blade would be at full extension, so the blood follows the cut.
	await get_tree().create_timer(0.1).timeout
	BloodSplashScript.burst(self, TO, TO - MELEE_FROM, GROUND_Y, strength)


func _thrown_weapon() -> void:
	## The hurl arc at the thrower, then the weapon itself cartwheeling across. In game the
	## projectile is a copy of the model out of the character's hand; here it is a stand-in
	## block of roughly axe-head size, since there is no character to take one from.
	SwordSwingScript.hurl(self, FROM, TO, 1.0)
	await get_tree().create_timer(0.06).timeout
	var weapon = ThrownWeaponScript.hurl(self, FROM, TO, _stand_in_weapon())
	await weapon.impacted
	BloodSplashScript.burst(self, TO, TO - FROM, GROUND_Y, 1.2)


func _stand_in_weapon() -> Node3D:
	## Unshaded on purpose: this stage has one dim key light and no ambient, so a lit stand-in
	## comes out near black and says nothing about how the real weapon reads. In game the model
	## arrives from the character's socket with its own material and the arena's lighting.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.62, 0.63, 0.68)
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.45, 0.5)
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	return mi


func _parried_hit() -> void:
	## The same swing, stopped: arc in, sparks instead of blood. Worth previewing next to
	## _melee_hit — the two have to be tellable apart at a glance while the fight is moving.
	SwordSwingScript.swing(self, MELEE_FROM, TO, 1.0, false)
	await get_tree().create_timer(0.1).timeout
	ParrySparksScript.clash(self, TO, MELEE_FROM, 1.0)


func _report_assets() -> void:
	## The effects degrade quietly when a pack asset is missing, which is right in game and
	## unhelpful here — so say plainly what loaded.
	for path in [ParticleKit.TEX_BLOB, ParticleKit.TEX_DOT, ParticleKit.TEX_SPARK,
			ParticleKit.TEX_SMOKE, ParticleKit.TEX_RING, ParticleKit.TEX_ARC,
			ParticleKit.MESH_FLAME,
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

	# Half the stage in dungeon-stone grey. Everything here is additive or near it, and an
	# effect tuned only against a dark floor can vanish over the pale flagstones the fights
	# actually happen on — this way both readings are on screen at once.
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.52, 0.52, 0.54)
	var stone_plane := PlaneMesh.new()
	stone_plane.size = Vector2(24, 11)
	stone_plane.material = stone_mat
	var stone := MeshInstance3D.new()
	stone.mesh = stone_plane
	stone.position = Vector3(0, GROUND_Y + 0.01, -6.0)
	add_child(stone)

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
