@tool
extends Node3D
## Places Kenney Mini Dungeon floor tiles across the battle grid.
## Uses floor.glb for most cells and floor-detail.glb for occasional variety.
## Random 90-degree rotation on each tile for visual variety.

@export var grid_extent := 30
@export var cell_size := 1.0
@export var floor_y := 0.0
@export var seed_value := 42
@export var detail_chance := 0.15

const FLOOR_PATH := "res://assets/models/kenney/mini-dungeon/floor.glb"
const DETAIL_PATH := "res://assets/models/kenney/mini-dungeon/floor-detail.glb"

var _floor_scene: PackedScene
var _detail_scene: PackedScene

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	_floor_scene = load(FLOOR_PATH) as PackedScene
	if _floor_scene == null:
		printerr("dungeon_floor: failed to load ", FLOOR_PATH)
		return

	_detail_scene = load(DETAIL_PATH) as PackedScene

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var half := float(grid_extent) / 2.0

	for gz in range(grid_extent):
		for gx in range(grid_extent):
			var x := -half + float(gx) * cell_size + cell_size / 2.0
			var z := -half + float(gz) * cell_size + cell_size / 2.0

			var use_detail := _detail_scene != null and rng.randf() < detail_chance
			var scene := _detail_scene if use_detail else _floor_scene

			var tile := scene.instantiate()
			tile.position = Vector3(x, floor_y, z)

			var rot_idx := rng.randi() % 4
			tile.rotation = Vector3(0, rot_idx * (PI / 2.0), 0)

			add_child(tile)
