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
## The leaf that hangs in that frame. One of the pack's plain wooden doors; _02 through _05 are
## the same size and swap in without touching anything else.
const DOOR_LEAF_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Door_02.res"
## Where the hole is across the frame module, in the module's own units. Synty's wall pieces are
## a 5-unit span with the opening centred, so this is half of that rather than a number measured
## off the art — which is why it survives the mesh being swapped for another frame.
const DOOR_OPENING_LOCAL_X := 2.5
const WALL_MAT := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"

# Stone props (same atlas material as the walls). Throne/vessel are solid obstacles;
# banners are flat wall decor (collision-free).
const THRONE_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Throne_01.res"
const VESSEL_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Vessel_01.res"
const WALL_BANNER_MESH := "res://Assets/PolygonDungeon/Models/SM_Prop_Wall_Banner_01.res"

# Searchable furniture for the south wall — the one opposite the door.
#
# The pack's PREFABS, not its raw meshes, unlike everything else in this file. A chest is two
# meshes plus the transform that marries them, and that transform lives in the prefab: the lid
# is authored with its origin on its own hinge, so placed at a raw offset it renders sticking
# out the front of the chest. Barrels come through the same door for consistency.
const CHEST_PREFAB := "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Chest_01.tscn"
const BARREL_PREFABS := [
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_01.tscn",
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_02.tscn",
]

## What a barrel might have in it. Drawn from at random, so which barrel gives what is settled
## by where it stands (LootContainer seeds itself off its position) rather than by the run.
##
## Ordinary kit on purpose: a barrel is the consolation prize for searching the room, and the
## thing worth having is behind the lock.
const BARREL_LOOT := [
	"res://resources/items/health_potion.tres",
	"res://resources/items/arrow_bundle.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/wooden_shield.tres",
	"res://resources/items/leather_armor.tres",
]

## What the locked chest has in it. Two draws from the good stuff — this is what the key on the
## boss is FOR, and it has to be worth crossing the room and killing him for.
const CHEST_LOOT := [
	"res://resources/items/boss_cleaver.tres",
	"res://resources/items/reinforced_leather_armor.tres",
	"res://resources/items/knight_helmet.tres",
	"res://resources/items/ranger_dagger.tres",
]

## The lock on the chest, and the key that opens it. The id is shared with iron_key.tres by
## hand — there is no registry of locks, and for one chest a registry would be ceremony.
## Spare scaling for the chest, on top of SCALE, the way the throne has its own scale_mul in
## _build_props.
##
## Body and lid together come to 0.57 world units unscaled, against a barrel's 0.83. Doubled,
## the chest stands about 1.14 — taller than the barrels beside it, which is the call: a
## treasure chest is the thing on that wall worth walking over to, and it should look it.
const CHEST_SCALE_MUL := 2.0

## Whether the chest starts shut AND locked. True: getting in means the boss's key or a lockpick
## roll against CHEST_LOCK_DIFFICULTY. Flip to false to open and shut it freely, which is what
## it was set to briefly while the lid animation was being looked at.
const CHEST_STARTS_LOCKED := true

const CHEST_KEY_ID := "dungeon_chest"
## Beatable on a 1-5 die by a lockpick skill of 3 or better, and never by anybody untrained.
const CHEST_LOCK_DIFFICULTY := 8

const SCALE := 0.8                 # dial the whole environment's size here
const TILE := 5.0 * SCALE          # world units per tile (= 4.0 at 0.8)
const FLOOR_Y := 0.0
const SEED := 1337

const CHAMBER_TILES := 8           # 8x8 chamber, centered on origin
const ROOM_TILES := 3              # 3x3 room, north of the chamber
const ROOM_X0 := -8.0              # room's near-x corner (aligned to the door segment)
const DOOR_X0 := -4.0              # chamber north wall segment that holds the doorway

const LAYER_OBSTACLE := 4          # matches Combatant.LAYER_OBSTACLE (blocks move + LOS)
## Combatant.GRID_SIZE: the play grid the doorway has to line up with. The environment is built
## on TILE (4.0) and played on this (2.0), so one wall module spans exactly two squares — which
## is the whole reason a doorway needs deciding rather than just leaving a hole.
const GRID := 2.0
## How far a doorway jamb reaches past the edge of the doorway square, in world units. See
## _place_doorway_jambs — it exists to close the seam a diagonal step can otherwise graze.
const JAMB_OVERLAP := 0.06

const DoorScript := preload("res://scripts/door.gd")
const LootContainerScript := preload("res://scripts/loot_container.gd")

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
	_build_door()
	_build_props()
	_build_containers()


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


func doorway_cell_x() -> float:
	## Centre of the single grid square the doorway occupies, worked out from the hole in the
	## art with the same snap the movement code uses (Combatant._snap_to_grid). The hole is
	## centred on the LINE between two squares, so this picks one of them — and everything
	## else, jambs and door alike, is built from the answer so they cannot disagree.
	var opening_x := DOOR_X0 + DOOR_OPENING_LOCAL_X * SCALE
	return (floor(opening_x / GRID) + 0.5) * GRID


func _build_door() -> void:
	## Hang a door in the one doorway, worked out from the same DOOR_X0 the frame is placed
	## from. Sited here rather than inside _build_walls so the wall loop stays a wall loop.
	##
	## The frame piece runs from DOOR_X0 to DOOR_X0 + TILE along +X (Synty wall modules have
	## their origin on the left edge, not the middle), so the opening is DOOR_OPENING_LOCAL_X
	## into it. Yaw is 0 to match the north wall the frame sits in.
	var half := CHAMBER_TILES / 2.0 * TILE                # 16
	var opening_x := DOOR_X0 + DOOR_OPENING_LOCAL_X * SCALE
	var cell_x := doorway_cell_x()
	# The door stands on the square it seals; the leaf hangs over the hole in the art, half a
	# square away. See the header of door.gd for why those are not the same place.
	DoorScript.build(
		self, Vector3(cell_x, FLOOR_Y, half), opening_x - cell_x, 0.0,
		DOOR_LEAF_MESH, WALL_MAT, SCALE)


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
	# Solid walls block movement + line of sight (obstacle layer 4). The box is sized from the
	# mesh AABB and rides the MeshInstance's scale, so it matches.
	#
	# The doorway module is the exception, and it used to be handled by skipping its collider
	# entirely. That was wrong: a module is 4 units, the play grid is 2, so leaving the WHOLE
	# module open made a two-square hole in a wall whose art shows a one-square door. Units
	# walked through the masonry beside the door, and shot through it. It now gets jambs — see
	# _place_doorway_jambs — and only the doorway square itself is left open.
	if mesh_path == DOOR_MESH:
		_place_doorway_jambs(mi, m, x)
		return
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


func _place_doorway_jambs(mi: MeshInstance3D, m: Mesh, module_x: float) -> void:
	## Wall the solid parts of a doorway module and leave exactly one grid square open.
	##
	## Derived rather than measured: take the module's own span, take the square the doorway
	## snaps to, and make a collider out of whatever is left over on each side. So it stays
	## right if the module, DOOR_X0 or SCALE change, and it is the same arithmetic the pathing
	## uses to decide which square a position is in.
	var aabb := m.get_aabb()
	var lo: float = module_x + aabb.position.x * SCALE
	var hi: float = lo + aabb.size.x * SCALE
	# Each jamb reaches a hair PAST the doorway square rather than stopping dead on its edge.
	# A diagonal step from the square beside the doorway to the square beyond it crosses the
	# wall plane exactly on that edge, and a ray that grazes the seam between two boxes reports
	# whatever floating point feels like — which is how units were cutting the corner of the
	# jamb into the room, open door or shut. The overlap is far too small to trouble the ray
	# down the middle of the doorway square, a whole unit away.
	var gap_lo: float = doorway_cell_x() - GRID / 2.0 + JAMB_OVERLAP
	var gap_hi: float = doorway_cell_x() + GRID / 2.0 - JAMB_OVERLAP
	for span in [[lo, gap_lo], [gap_hi, hi]]:
		var width: float = span[1] - span[0]
		# A sliver is the module's own overlap with its neighbour, which that neighbour's
		# collider already covers. Building a box for it would only add contacts.
		if width < 0.1:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_OBSTACLE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Everything here is in the module's OWN units, not world units, because the shape
		# hangs off the MeshInstance and inherits its SCALE — the same convention the plain
		# wall collider above uses. Only `width` arrives in world units, so only `width` is
		# divided back out. Sizing the box in world units instead makes every jamb 20% too
		# narrow, which leaves precisely enough room for a diagonal step to clip its corner.
		box.size = Vector3(width / SCALE, aabb.size.y, aabb.size.z)
		cs.shape = box
		cs.position = Vector3(
			((span[0] + span[1]) / 2.0 - module_x) / SCALE,
			aabb.get_center().y,
			aabb.get_center().z)
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


func _build_containers() -> void:
	## Chest and barrels along the south wall — the far side of the room from the door, so
	## crossing to them means crossing the fight.
	##
	## Sited clear of the throne, which already holds the two squares either side of x = 0 (see
	## _build_props), and facing north into the room so their loot spills into the floor rather
	## than into the masonry behind them.
	var wall_z := -CHAMBER_TILES / 2.0 * TILE + 1.0     # -15, level with the throne
	var chest = LootContainerScript.new()
	# The y here is a placeholder: a container settles onto the floor surface itself, because
	# FLOOR_Y is under it. See LootContainer.FLOOR_SURFACE_Y.
	# Yaw 0 faces them into the room: the chest's lid hinges at its local -Z, which is the side
	# against the wall, and swings open over the +Z side you stand on.
	chest.configure(Vector3(-5.0, FLOOR_Y, wall_z), 0.0,
		CHEST_PREFAB, SCALE * CHEST_SCALE_MUL)
	chest.open_verb = "Open"
	chest.locked = CHEST_STARTS_LOCKED
	chest.key_id = CHEST_KEY_ID
	chest.lock_difficulty = CHEST_LOCK_DIFFICULTY
	chest.loot = CHEST_LOOT
	chest.loot_rolls = 2
	# Added last: _ready() builds the geometry, and it must not run before the fields above
	# are in place.
	add_child(chest)

	for i in range(BARREL_PREFABS.size()):
		var barrel = LootContainerScript.new()
		barrel.configure(Vector3(5.0 + i * 2.0, FLOOR_Y, wall_z), 0.0,
			BARREL_PREFABS[i], SCALE)
		barrel.loot = BARREL_LOOT
		barrel.loot_rolls = 1
		add_child(barrel)


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
