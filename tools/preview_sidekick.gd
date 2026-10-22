extends Node3D
## Dev tool: the Sidekick test character, in five stages of dress, for judging the gear-driven
## look. Play tools/preview_sidekick.tscn.
##
## Writes two screenshots to .summer/local/ (idle, and the middle of a sword swing), then keeps
## running: the line-up idles, and every few seconds the full knight swings, takes a hit or
## blocks, so the animation can be judged live. Close the window to stop.

const SidekickBody := preload("res://scripts/sidekick_body.gd")
const KENNEY_SOLDIER := "res://scenes/characters/soldier_model.tscn"

## Debug line-up, used when DEBUG_PARTS is set: the bare body with one suspect part left out
## per figure, to find which part renders wrong.
const DEBUG_PARTS := ["", "facial_hair", "hair", "tongue", "teeth", "foot_l"]
const DEBUG := false

const LINEUP := [
	{"label": "Bare body", "gear": []},
	{"label": "+ Cuirass", "gear": ["knight_cuirass"]},
	{"label": "+ Greaves, boots,\ngauntlets", "gear": ["knight_cuirass", "knight_greaves", "knight_boots", "knight_gauntlets"]},
	{"label": "Full knight", "gear": ["knight_cuirass", "knight_greaves", "knight_boots", "knight_gauntlets", "knight_helm"]},
	{"label": "Same, villain hood", "gear": ["knight_cuirass", "knight_greaves", "knight_boots", "knight_gauntlets", "villain_hood"]},
]
const SPACING := 1.1
const SHOT_IDLE := "res://.summer/local/sidekick_preview.png"
const SHOT_SWING := "res://.summer/local/sidekick_preview_swing.png"

var _bodies: Array = []


func _ready() -> void:
	_stage()
	var lineup: Array = LINEUP
	if DEBUG:
		lineup = []
		for d in DEBUG_PARTS:
			lineup.append({"label": "without " + d if d != "" else "all parts", "gear": [], "omit": d})
	var x0 := -SPACING * (lineup.size() - 1) / 2.0
	for i in range(lineup.size()):
		var body := SidekickBody.new()
		body.name = "Sidekick%d" % i
		body.position = Vector3(x0 + i * SPACING, 0, 0)
		body.omit = lineup[i].get("omit", "")
		add_child(body)
		body.build(lineup[i]["gear"])
		body.play("idle")
		_bodies.append(body)
		var label := Label3D.new()
		label.text = lineup[i]["label"]
		label.font_size = 28
		label.pixel_size = 0.004
		label.position = body.position + Vector3(0, 2.05, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 8
		add_child(label)
	# The game's current soldier, for scale and style next to the new bodies.
	var ks: PackedScene = load(KENNEY_SOLDIER)
	if ks:
		var k := ks.instantiate() as Node3D
		k.position = Vector3(x0 + lineup.size() * SPACING, 0, 0)
		# Combatant.CHARACTER_SCALE: how big the Kenney bodies are drawn in the game.
		k.scale = Vector3.ONE * 1.6
		add_child(k)
		var kap := k.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if kap and kap.has_animation("idle"):
			kap.play("idle")
		var kl := Label3D.new()
		kl.text = "Current (Kenney)"
		kl.font_size = 28
		kl.pixel_size = 0.004
		kl.outline_size = 8
		kl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		kl.position = k.position + Vector3(0, 2.05, 0)
		add_child(kl)
	await _shots()
	_cycle()


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 6)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.27)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0.55, 1.3, 5.4)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT_IDLE)
	for b in _bodies:
		b.play("attack")
	await get_tree().create_timer(0.45).timeout
	get_viewport().get_texture().get_image().save_png(SHOT_SWING)
	print("[SidekickPreview] screenshots written")
	for b in _bodies:
		b.play("idle")


func _cycle() -> void:
	var knight = _bodies[3]
	var moves := ["attack", "hit", "heavy", "block", "die"]
	var i := 0
	while is_inside_tree():
		await get_tree().create_timer(3.0).timeout
		knight.play(moves[i % moves.size()])
		await get_tree().create_timer(2.5).timeout
		knight.play("idle")
		i += 1
