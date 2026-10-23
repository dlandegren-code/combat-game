extends Node3D
## Dev tool: every clip the Sidekick body can play, one figure each, labelled with the name the
## game asks for it by. Play tools/preview_sidekick_anims.tscn.
##
## Looping clips loop; one-shots replay every few seconds. Writes two screenshots a second apart
## to .summer/local/ and keeps running.

const SidekickBody := preload("res://scripts/sidekick_body.gd")

const SHOWN := [
	"idle", "walk", "run", "crouch-walk", "sit", "pick-up", "interact-right", "open-chest",
	"attack-melee-right", "attack-melee-left", "attack-heavy", "attack-kick-right",
	"holding-both-shoot", "throw", "cast", "hit", "block", "dodge", "knocked-down", "die",
	"zombie-walk", "zombie-attack", "drink", "get-up",
]
## When non-empty, only these, close up at eye level, for judging a retarget.
const FOCUS := ["holding-both-shoot", "attack-kick-right", "kick-roundhouse", "cast", "crouch", "hit-heavy"]
const COLS := 8
const DX := 1.25
const DZ := 2.6
const SHOT_A := "res://.summer/local/sidekick_anims_a.png"
const SHOT_B := "res://.summer/local/sidekick_anims_b.png"

var _one_shots: Array = []


func _ready() -> void:
	_stage()
	var shown: Array = FOCUS if not FOCUS.is_empty() else SHOWN
	var cols := shown.size() if not FOCUS.is_empty() else COLS
	for i in range(shown.size()):
		var clip: String = shown[i]
		var col := i % cols
		var row := i / COLS
		var body := SidekickBody.new()
		body.position = Vector3((col - (cols - 1) / 2.0) * DX * 0.5, 0, -row * DZ * 0.5)
		if not FOCUS.is_empty():
			body.rotation_degrees.y = 35.0
		body.outfit = SidekickBody.parts_of_set("SK_FANT_KNGT_17")
		add_child(body)
		body.play(clip)
		var a: Animation = body.anim.get_animation(clip) if body.anim.has_animation(clip) else null
		if a != null and a.loop_mode == Animation.LOOP_NONE:
			_one_shots.append([body, clip])
		var label := Label3D.new()
		label.text = clip if a != null else clip + "\n(MISSING)"
		label.font_size = 30
		label.pixel_size = 0.0022
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = body.position + Vector3(0, 1.05, 0)
		add_child(label)
	await _shots()
	while is_inside_tree():
		await get_tree().create_timer(3.0).timeout
		for pair in _one_shots:
			pair[0].anim.stop()
			pair[0].play(pair[1])


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
	sun.rotation_degrees = Vector3(-45, 25, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 10)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, -2.6)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.27)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.2, 5.6)
	cam.rotation_degrees = Vector3(-28, 0, 0)
	if not FOCUS.is_empty():
		cam.position = Vector3(0, 0.62, 2.5)
		cam.rotation_degrees = Vector3(-3, 0, 0)
	cam.fov = 60
	add_child(cam)
	cam.make_current()


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(SHOT_A)
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(SHOT_B)
	print("[SidekickAnims] screenshots written")
