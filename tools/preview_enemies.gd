extends Node3D
## Dev tool: enemy templates side by side, dressed by the game's own QuestScene._dress, idling and
## then mid-attack. Play tools/preview_enemies.tscn. Writes .summer/local/enemies_idle.png and
## enemies_attack.png, then keeps running.

const QuestScene := preload("res://scenes/quest_scene.tscn")
const RosterScript := preload("res://scripts/enemy_roster.gd")

@export var template_ids: Array = ["jarl", "berserker", "viking_archer", "shieldmaiden"]
const DX := 1.15

var _bodies: Array = []


func _ready() -> void:
	_stage()
	var dresser := QuestScene.instantiate()
	var x0 := -DX * (template_ids.size() - 1) / 2.0
	for i in range(template_ids.size()):
		var t = RosterScript.find(String(template_ids[i]))
		if t == null:
			push_warning("PreviewEnemies: no template %s" % template_ids[i])
			continue
		var e: Node = dresser._dress(t)
		e.position = Vector3(x0 + i * DX, 0, 0)
		add_child(e)
		e.set_process(false)
		e.set_physics_process(false)
		e.character_name = t.display_name
		for c in e.get_children():
			if c is VisualInstance3D and c.name != "CharacterModel":
				c.visible = false
		var label := Label3D.new()
		label.text = t.display_name
		label.font_size = 26
		label.pixel_size = 0.003
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(e.position.x, 1.75, 0)
		add_child(label)
		_bodies.append(e)
	dresser.free()
	await get_tree().create_timer(0.8).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))
	get_viewport().get_texture().get_image().save_png("res://.summer/local/enemies_idle.png")
	for e in _bodies:
		e._play_attack_anim("attack-melee-right")
	await get_tree().create_timer(0.55).timeout
	get_viewport().get_texture().get_image().save_png("res://.summer/local/enemies_attack.png")
	print("[PreviewEnemies] screenshots written")


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 6)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.27)
	floor_mesh.material_override = fm
	floor_mesh.position = Vector3(0, 0.11, 0)
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0.6, 1.5, 4.6)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.fov = 55
	add_child(cam)
	cam.make_current()
