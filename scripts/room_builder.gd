@tool
extends Node3D
## Builds the dungeon chamber + connected room from Synty modular pieces.
## Pieces are scaled by SCALE (Synty tiles are a chunky 5 units; scaling them
## down sits better against the ~1-unit characters). Layout is defined in tiles,
## so changing SCALE just resizes everything. Floor tile prefabs carry their own
## material + collision; the ±14 movement bound keeps units inside the chamber.
##
## Regenerates on _ready (runs in-editor via @tool).

const FLOORS_DIR := "res://Assets/PolygonDungeon/Prefabs/Environments/Floors/"
const MAIN_TILES := ["SM_Env_Tiles_01.tscn", "SM_Env_Tiles_02.tscn", "SM_Env_Tiles_03.tscn"]
const ROOM_CENTER_TILE := "SM_Env_Tiles_05.tscn"
const CIRCLE_QUARTER := "SM_Env_Tiles_06.tscn"

const SCALE := 0.8                 # dial the whole environment's size here
const TILE := 5.0 * SCALE          # world units per tile (= 4.0 at 0.8)
const FLOOR_Y := 0.0
const SEED := 1337

const CHAMBER_TILES := 8           # 8x8 chamber, centered on origin
const ROOM_TILES := 3              # 3x3 room, centered on the chamber's north edge

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rng.seed = SEED
	_build_chamber()
	_build_room()


func _build_chamber() -> void:
	var x0 := -CHAMBER_TILES / 2.0 * TILE      # -16
	# The center 2x2 (indices mid-1, mid) is left for the circle.
	@warning_ignore("integer_division")
	var mid := CHAMBER_TILES / 2               # 4
	for r in range(CHAMBER_TILES):
		for c in range(CHAMBER_TILES):
			if (c == mid - 1 or c == mid) and (r == mid - 1 or r == mid):
				continue
			_place_tile(_random_main_tile(), x0 + c * TILE, x0 + r * TILE, 0.0)
	# Center circle: four quarter-circle tiles, each rotated so its arc faces the
	# shared origin -> one filled circle two tiles wide.
	_place_tile(CIRCLE_QUARTER, TILE, TILE, 180.0)
	_place_tile(CIRCLE_QUARTER, TILE, -TILE, 270.0)
	_place_tile(CIRCLE_QUARTER, -TILE, -TILE, 0.0)
	_place_tile(CIRCLE_QUARTER, -TILE, TILE, 90.0)


func _build_room() -> void:
	var x0 := -ROOM_TILES / 2.0 * TILE                    # -6 (centered on x=0)
	var z0 := CHAMBER_TILES / 2.0 * TILE                  # 16 (chamber's north edge)
	@warning_ignore("integer_division")
	var mid := ROOM_TILES / 2                             # 1
	for r in range(ROOM_TILES):
		for c in range(ROOM_TILES):
			var tile: String = ROOM_CENTER_TILE if (c == mid and r == mid) else _random_main_tile()
			_place_tile(tile, x0 + c * TILE, z0 + r * TILE, 0.0)


func _place_tile(prefab_file: String, x: float, z: float, rot_y_deg: float) -> void:
	var scene: PackedScene = load(FLOORS_DIR + prefab_file)
	if scene == null:
		return
	var tile: Node3D = scene.instantiate()
	tile.position = Vector3(x, FLOOR_Y, z)
	tile.rotation_degrees = Vector3(0, rot_y_deg, 0)
	tile.scale = Vector3(SCALE, SCALE, SCALE)
	add_child(tile)


func _random_main_tile() -> String:
	return MAIN_TILES[_rng.randi() % MAIN_TILES.size()]
