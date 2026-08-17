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

# Walls (double-sided so facing never matters) + a single doorway piece.
const WALL_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Wall_01_DoubleSided.res"
const DOOR_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Wall_DoorFrame_01.res"
const WALL_MAT := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"

# Stone props (same atlas material as the walls). Throne/vessel are solid obstacles;
# banners are flat wall decor (collision-free).
const THRONE_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Throne_01.res"
const VESSEL_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Vessel_01.res"
const WALL_BANNER_MESH := "res://Assets/PolygonDungeon/Models/SM_Prop_Wall_Banner_01.res"

const SCALE := 0.8                 # dial the whole environment's size here
const TILE := 5.0 * SCALE          # world units per tile (= 4.0 at 0.8)
const FLOOR_Y := 0.0
const SEED := 1337

const CHAMBER_TILES := 8           # 8x8 chamber, centered on origin
const ROOM_TILES := 3              # 3x3 room, north of the chamber
const ROOM_X0 := -8.0              # room's near-x corner (aligned to the door segment)
const DOOR_X0 := -4.0              # chamber north wall segment that holds the doorway

const LAYER_OBSTACLE := 4          # matches Combatant.LAYER_OBSTACLE (blocks move + LOS)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rng.seed = SEED
	_build_chamber()
	_build_room()
	_build_walls()
	_build_props()


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
	var x0 := ROOM_X0                                     # aligned so the door is the center tile
	var z0 := CHAMBER_TILES / 2.0 * TILE                  # 16 (chamber's north edge)
	@warning_ignore("integer_division")
	var mid := ROOM_TILES / 2                             # 1
	for r in range(ROOM_TILES):
		for c in range(ROOM_TILES):
			var tile: String = ROOM_CENTER_TILE if (c == mid and r == mid) else _random_main_tile()
			_place_tile(tile, x0 + c * TILE, z0 + r * TILE, 0.0)


func _build_walls() -> void:
	var half := CHAMBER_TILES / 2.0 * TILE                # 16
	# Chamber south & north walls (run along +X). North has the doorway.
	for i in range(CHAMBER_TILES):
		var x := -half + i * TILE
		_place_wall(WALL_MESH, x, -half, 0.0)
		var north_mesh := DOOR_MESH if is_equal_approx(x, DOOR_X0) else WALL_MESH
		_place_wall(north_mesh, x, half, 0.0)
	# Chamber east & west walls (rotated 90 -> run along Z).
	for i in range(CHAMBER_TILES):
		var z := half - i * TILE
		_place_wall(WALL_MESH, half, z, 90.0)
		_place_wall(WALL_MESH, -half, z, 90.0)
	# Room walls: north side + the two sides; the south side is the shared chamber
	# wall (with the doorway), so it's left open here.
	var rx_east := ROOM_X0 + ROOM_TILES * TILE            # 4
	var rz_north := half + ROOM_TILES * TILE              # 28
	for i in range(ROOM_TILES):
		_place_wall(WALL_MESH, ROOM_X0 + i * TILE, rz_north, 0.0)   # room north
		var z := rz_north - i * TILE
		_place_wall(WALL_MESH, rx_east, z, 90.0)                    # room east
		_place_wall(WALL_MESH, ROOM_X0, z, 90.0)                    # room west


func _place_wall(mesh_path: String, x: float, z: float, rot_y_deg: float) -> void:
	var m: Mesh = load(mesh_path)
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = load(WALL_MAT)
	mi.position = Vector3(x, FLOOR_Y, z)
	mi.rotation_degrees = Vector3(0, rot_y_deg, 0)
	mi.scale = Vector3(SCALE, SCALE, SCALE)
	add_child(mi)
	# Solid walls block movement + line of sight (obstacle layer 4). The doorway is
	# left collision-free so units can walk/shoot through the opening. The box is
	# sized from the mesh AABB and rides the MeshInstance's scale, so it matches.
	if mesh_path != DOOR_MESH:
		var aabb := m.get_aabb()
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_OBSTACLE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		cs.shape = box
		cs.position = aabb.get_center()
		body.add_child(cs)
		mi.add_child(body)


func _build_props() -> void:
	var half := CHAMBER_TILES / 2.0 * TILE                # 16
	# Throne centered on the vessel's x = 0 axis, spanning the two cells straddling that
	# line (x = -1 and x = 1), against the south wall, facing north. Placed WITHOUT a
	# collider (solid = false): its two cells are reserved explicitly below, so exactly
	# those squares block. A collider's footprint would spill into the neighbours.
	_place_prop(THRONE_MESH, 0.0, -half + 1.0, 0.0, false, FLOOR_Y, false, 2.2)
	_reserve_cell(-1.0, -half + 1.0)
	_reserve_cell(1.0, -half + 1.0)
	# Wall banners flanking the widened throne, hung high on the same wall (solid).
	# Rotated 180 so the decorated face points into the room, not at the wall.
	_place_prop(WALL_BANNER_MESH, -3.0, -half + 0.3, 180.0, true, 4.0)
	_place_prop(WALL_BANNER_MESH, 3.0, -half + 0.3, 180.0, true, 4.0)
	# Stone vessel on the circle's center crossing: block diagonal cuts through it (via
	# the collider) but do NOT reserve a cell, so the four squares around it stay walkable.
	_place_prop(VESSEL_MESH, 0.0, 0.0, 0.0, true, FLOOR_Y, false)


func _reserve_cell(x: float, z: float) -> void:
	## Invisible marker so _is_obstacle_at treats this grid cell as blocked. Used to
	## reserve every cell a multi-cell prop (the throne) sits on.
	var marker := Node3D.new()
	marker.position = Vector3(x, FLOOR_Y, z)
	marker.add_to_group("obstacles")
	add_child(marker)


func _place_prop(mesh_path: String, x: float, z: float, rot_y_deg: float, solid := true,
		y := FLOOR_Y, reserve_cell := true, scale_mul := 1.0) -> void:
	var m: Mesh = load(mesh_path)
	if m == null:
		return
	var s := SCALE * scale_mul
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = load(WALL_MAT)
	mi.position = Vector3(x, y, z)
	mi.rotation_degrees = Vector3(0, rot_y_deg, 0)
	mi.scale = Vector3(s, s, s)
	add_child(mi)
	if not solid:
		return
	# Cell reservation blocks moving ONTO the prop's tile (via the "obstacles" group,
	# read by _is_obstacle_at). Props sitting on a grid crossing (the vessel) skip this
	# so the four surrounding squares stay walkable; only diagonal cuts are blocked.
	if reserve_cell:
		mi.add_to_group("obstacles")
	# Obstacle-layer collider for line-of-sight + diagonal path blocking. Anchored on the
	# floor with a minimum height so short props (the vessel) still reach the ~1.6-high
	# movement/LOS rays instead of sitting under them.
	var aabb := m.get_aabb()
	var local_h: float = max(aabb.size.y, 2.5 / s)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_OBSTACLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x, local_h, aabb.size.z)
	cs.shape = box
	cs.position = Vector3(aabb.get_center().x, aabb.position.y + local_h * 0.5, aabb.get_center().z)
	body.add_child(cs)
	mi.add_child(body)


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
