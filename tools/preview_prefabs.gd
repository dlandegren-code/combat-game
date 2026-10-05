extends Node3D
## Dev tool: photographs a list of Synty prefabs one at a time, so a model can be judged by
## eye before it goes into the town. Run tools/preview_prefabs.tscn with summer_play; it
## writes .summer/local/prefab_<name>.png per model and quits.

const SyntyModelScript := preload("res://scripts/synty_model.gd")
const FARM_PREFABS := "res://assets/Synty/PolygonFarm/Prefabs/"
const DUNGEON_PREFABS := "res://assets/PolygonDungeon/Prefabs/"

const MODELS := [
	"dungeon:Environments/Pillars/SM_Env_Wall_Round_01",
	"dungeon:Environments/Pillars/SM_Env_Wall_Pillar_Large_Round_01",
	"dungeon:Environments/Walls/SM_Env_Wall_Half_01",
	"dungeon:Environments/Walls/SM_Env_Wall_DoorFrame_Round_01",
	"dungeon:Environments/Walls/SM_Env_Door_Frame_Round_01",
	"farm:Props/SM_Prop_Hay_Pile_01",
	"farm:Buildings/SM_Bld_Silo_01",
	"dungeon:Environments/Floors/SM_Env_GroundMound_01",
	"dungeon:Environments/Pillars/SM_Env_Pillar_Round_Simple_01",
]

const OUT_DIR := "res://.summer/local/"

var _camera: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 40.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	_camera = Camera3D.new()
	add_child(_camera)

	for entry in MODELS:
		var node := _load(entry)
		if node == null:
			print("[Preview] could not load %s" % entry)
			continue
		add_child(node)
		var box := _bounds(node)
		var centre := box.get_center()
		var reach := box.size.length()
		_camera.position = centre + Vector3(0.75, 0.55, 1.0).normalized() * reach * 1.15
		_camera.look_at(centre)
		for i in range(6):
			await get_tree().process_frame
		var file := String(entry).get_file()
		var err := get_viewport().get_texture().get_image().save_png(OUT_DIR + "prefab_" + file + ".png")
		print("[Preview] %s %s size %s min %s" % [file, "ok" if err == OK else "FAILED", box.size, box.position])
		remove_child(node)
		node.queue_free()
	get_tree().quit()


func _load(entry: String) -> Node3D:
	if entry.begins_with("farm:"):
		var packed := load(FARM_PREFABS + entry.trim_prefix("farm:") + ".tscn") as PackedScene
		return packed.instantiate() as Node3D if packed != null else null
	if entry.begins_with("res://"):
		var mi := MeshInstance3D.new()
		mi.mesh = load(entry) as Mesh
		return mi
	if entry.begins_with("dungeon:"):
		var packed := load(DUNGEON_PREFABS + entry.trim_prefix("dungeon:") + ".tscn") as PackedScene
		return packed.instantiate() as Node3D if packed != null else null
	return SyntyModelScript.meadow(entry)


func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mesh in meshes:
		var m := mesh as MeshInstance3D
		var local := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box
