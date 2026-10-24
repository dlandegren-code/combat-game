extends Node3D
## Dev tool: a row of items dropped on a floor beside a hero for scale, seen from the game's
## camera angle and close up. Writes .summer/local/ground_wide.png and ground_close.png, then quits.

const GroundItem := preload("res://scripts/ground_item.gd")
const HERO := preload("res://scenes/characters/hero.tscn")
const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")

@export var items: Array = ["res://resources/items/quiver.tres", "res://resources/items/health_potion.tres",
	"res://resources/items/viking_axe.tres"]


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 6)
	floor_mi.mesh = plane
	add_child(floor_mi)
	var hero := HERO.instantiate()
	var model := SIDEKICK.instantiate()
	model.name = "CharacterModel"
	model.position = Vector3(0, -1, 0)
	hero.add_child(model)
	add_child(hero)
	hero.set_process(false)
	hero.set_physics_process(false)
	hero.position = Vector3(-2, 1, 0)
	for i in items.size():
		GroundItem.drop(self, load(items[i]), Vector3(i * 1.0, 0, 0))
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for shot in [["wide", Vector3(0, 7, 7), Vector3(0, 0, 0)], ["close", Vector3(0.3, 1.4, 1.6), Vector3(0.3, 0, 0)]]:
		cam.position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
		for k in range(6):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://.summer/local/ground_%s.png" % shot[0])
	get_tree().quit()
