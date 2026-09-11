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

# Searchable furniture: the chest and the casks on the south wall — the one opposite the door —
# and the crates in the north-east corner.
#
# The pack's PREFABS, not its raw meshes, unlike everything else in this file. A chest is two
# meshes plus the transform that marries them, and that transform lives in the prefab: the lid
# is authored with its origin on its own hinge, so placed at a raw offset it renders sticking
# out the front of the chest. Barrels and crates come through the same door for consistency.
const CHEST_PREFAB := "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Chest_01.tscn"

## The barrels along the south wall, working east from the chest.
const BARREL_PREFABS := [
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_01.tscn",
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_02.tscn",
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_03.tscn",
]

## What comes out of a barrel: drink, and nothing but.
##
## One of these per barrel, picked at random when the room is built — see _build_containers.
## A cask holds ONE liquid all the way down, so a barrel of beer gives beer and only beer; the
## random part is which barrel turns out to be the beer.
##
## Swords and breastplates live in the crates in the corner now. A cooper does not store a
## shield in a cask.
const BARREL_LIQUIDS := [
	"res://resources/items/bottle_of_beer.tres",
	"res://resources/items/bottle_of_water.tres",
	"res://resources/items/bottle_of_wine.tres",
]

## Bottles per barrel, all of them the same liquid. Enough that a barrel reads as a barrel
## rather than as a shelf with one bottle on it, and low enough that the drink does not
## out-heal the chest.
const BARREL_BOTTLES := 3

## Crates stacked in the north-east corner, where the kit that used to be in the barrels lives
## now. Unlocked, every one of them: this is the loot you get for looking round the room, and
## the lock is what makes the chest the chest.
##
## Set against the two walls that meet there rather than in a row, so the corner reads as
## somebody's untidy store and not as a shop shelf: two on the east wall, one on the north,
## each yawed to face the room it is leaning out of. Every square listed is outside the ±14
## play bound (see Combatant.ARENA_MAX), so blocking them costs no floor — exactly as the
## south-wall furniture does at z = -15, and both are still reachable from the corner square.
##
## The pack ships no crate with a separate lid mesh, so these have no lid to swing and get
## searched the way a barrel is (LootContainer._find_lid). One of the three is the pack's
## open-topped metal crate, which is the closest the art gets to saying "already unlocked".
const CRATES := [
	{
		"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Wood_01.tscn",
		"x": 15.0, "z": 13.0, "yaw": 270.0, "rolls": 2,
	},
	{
		"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Metal_Open_01.tscn",
		"x": 15.0, "z": 11.0, "yaw": 270.0, "rolls": 1,
	},
	{
		"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Wood_03.tscn",
		"x": 13.0, "z": 15.0, "yaw": 180.0, "rolls": 2,
	},
]

## What a crate might have in it. Drawn from at random, so which crate gives what is settled by
## where it stands (LootContainer seeds itself off its position) rather than by the run.
##
## Gear, plus the one exception: a health potion. Not drink in the barrel sense — nobody kegs
## the stuff — and it is the only reason to bother with a crate when you are hurt rather than
## under-equipped, so it earns its slot. Beer, water and wine stay strictly in the casks
## (BARREL_LIQUIDS).
##
## Ordinary kit on purpose: a crate is the consolation prize for searching the room, and the
## thing worth having is still behind the lock.
const CRATE_LOOT := [
	"res://resources/items/health_potion.tres",
	"res://resources/items/rusty_sword.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/wooden_shield.tres",
	"res://resources/items/leather_armor.tres",
	"res://resources/items/leather_greaves.tres",
	"res://resources/items/short_bow.tres",
	"res://resources/items/quiver.tres",
	"res://resources/items/arrow_bundle.tres",
]

## Spare scaling for a crate, on top of SCALE, the way the chest has CHEST_SCALE_MUL. The crate
## meshes are a 1.07 cube, which at bare SCALE stands 0.85 — a hair over a barrel and well
## under the chest, which is the order these three want to be in but too tight to read as one.
const CRATE_SCALE_MUL := 1.25

## What the locked chest has in it. Two draws from the good stuff — this is what the key on the
## boss is FOR, and it has to be worth crossing the room and killing him for.
const CHEST_LOOT := [
	"res://resources/items/boss_cleaver.tres",
	"res://resources/items/reinforced_leather_armor.tres",
	"res://resources/items/heavy_armor.tres",
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

## How far off the wall a patrol walks its beat, in world units. Outside the ring of pillars
## (which stand at 3 and 5 either side of the middle) and a stride clear of the masonry, so the
## route is walkable the whole way round without the pathfinder having to thread anything.
const PATROL_INSET := 7.0

var _rng := RandomNumberGenerator.new()

## Somewhere an idle enemy might take itself, and what to look at once it gets there, keyed by
## what a body would be doing there. Filled as the room is BUILT, from the same positions the
## furniture is placed at, so a spot cannot come to mean a square the furniture has moved off.
var _idle_spots := {}


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rng.seed = SEED
	_idle_spots.clear()
	_build_chamber()
	_build_room()
	_build_walls()
	_build_door()
	_build_props()
	_build_containers()
	_build_idle_corners()


# --- Where an idle enemy might take itself ---------------------------------

func idle_spots(kind: String) -> Array:
	## Squares worth loitering at, by what a body would be doing there:
	##
	##   "seat"    the throne — the squares in front of it, facing out over the hall
	##   "stores"  the chest, the casks and the crates — the square you stand on to work one
	##   "corner"  the corners of the chamber, for anybody minded to lie down out of the way
	##
	## Each entry is {"at": Vector3, "face": Vector3, "perch": Vector3}: the square to stand on,
	## the point to turn towards from it, and — for a spot you get ON rather than stand beside —
	## where to put yourself once you are there, or INF for nowhere but the square itself. The
	## first two are given rather than the enemy guessing, because they do not follow from each
	## other: you face INTO the room from the throne and INTO the wall at a cask, and the room is
	## the only thing that knows which is which.
	##
	## Empty for a kind nothing registered, which every caller has to cope with anyway: this is
	## scenery, and a level without a throne in it is a legal level.
	return _idle_spots.get(kind, [])


func patrol_ring() -> Array[Vector3]:
	## A beat round the chamber, for a patroller the scene did not author a route for.
	##
	## Derived from the chamber rather than written down, so it cannot come to describe the old
	## floor plan — and so that WHICH enemies patrol can be decided at runtime (see
	## CombatManager._cast_idle_roles) without every one of them needing a route in the scene.
	## A patrol_route set by hand still wins: a beat that matters to the level is level design.
	var r: float = CHAMBER_TILES / 2.0 * TILE - PATROL_INSET
	var ring: Array[Vector3] = []
	for corner in [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		ring.append(Vector3(corner.x * r, FLOOR_Y, corner.y * r))
	return ring


func _add_idle_spot(kind: String, at: Vector3, face: Vector3,
		perch: Vector3 = Vector3.INF) -> void:
	if not _idle_spots.has(kind):
		_idle_spots[kind] = []
	_idle_spots[kind].append({"at": at, "face": face, "perch": perch})


func _spot_beside(x: float, z: float, kind: String) -> void:
	## Register the square in front of a piece of furniture standing against a wall: one step
	## from it towards the middle of the chamber, facing back at it.
	##
	## Worked out from which wall the thing is against rather than from a yaw, because that is
	## what decides where you can stand: the south-wall furniture is approached from the north
	## and the corner crates from whichever side is not masonry.
	var half: float = CHAMBER_TILES / 2.0 * TILE
	var at := Vector3(x, FLOOR_Y, z)
	if absf(z) > half - TILE:
		at.z -= signf(z) * GRID
	if absf(x) > half - TILE:
		at.x -= signf(x) * GRID
	_add_idle_spot(kind, at, Vector3(x, FLOOR_Y, z))


func _build_idle_corners() -> void:
	## The four inside corners of the chamber. Out of the way by definition, which is what makes
	## them the place to have a lie-down: a goblin dozing in the middle of the floor is in the
	## way of everything, including the fight it is about to be in.
	var c: float = CHAMBER_TILES / 2.0 * TILE - GRID / 2.0    # 15: the last square inside
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_idle_spot("corner", Vector3(sx * c, FLOOR_Y, sz * c), Vector3.ZERO)


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


func is_floor_at(x: float, z: float) -> bool:
	## Whether a play-grid square has dungeon floor under it: the chamber, or the room through
	## the north door.
	##
	## THE authority on where a unit can be put, asked by Combatant._is_in_arena — which was a
	## ±14 square before this existed and therefore said no to every square of the room. Worked
	## out from the same CHAMBER_TILES / ROOM_TILES / ROOM_X0 the geometry is BUILT from, so a
	## change to the floor plan cannot leave the play area describing the old one.
	##
	## Strictly inside, so a square whose centre sits exactly on a wall line is out. Play
	## squares are on odd coordinates and the walls on multiples of TILE, so in practice this
	## only ever decides the boundary cases the two grids create.
	var half := CHAMBER_TILES / 2.0 * TILE                # 16
	if _inside(x, -half, half) and _inside(z, -half, half):
		return true
	var room_x1 := ROOM_X0 + ROOM_TILES * TILE            # 4
	var room_z1 := half + ROOM_TILES * TILE               # 28
	return _inside(x, ROOM_X0, room_x1) and _inside(z, half, room_z1)


func _inside(v: float, lo: float, hi: float) -> bool:
	return v > lo and v < hi


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
	# The two squares in front of it, looking out over the hall — where somebody holding this
	# room would put himself. Not the throne's OWN squares: those are reserved above, which is
	# to say they are wall as far as walking is concerned, and a boss standing on one would be
	# standing on a square the rules say nothing can cross.
	var seat: Vector3 = _throne_seat(0.0, -half + 1.0, 2.2)
	for x in [-1.0, 1.0]:
		_add_idle_spot("seat", Vector3(x, FLOOR_Y, -half + 1.0 + GRID), Vector3.ZERO, seat)
	# Wall banners flanking the widened throne, hung high on the same wall (solid).
	# Rotated 180 so the decorated face points into the room, not at the wall.
	_place_prop(WALL_BANNER_MESH, -3.0, -half + 0.3, 180.0, true, 4.0)
	_place_prop(WALL_BANNER_MESH, 3.0, -half + 0.3, 180.0, true, 4.0)
	# Stone vessel on the circle's center crossing: block diagonal cuts through it (via
	# the collider) but do NOT reserve a cell, so the four squares around it stay walkable.
	_place_prop(VESSEL_MESH, 0.0, 0.0, 0.0, true, FLOOR_Y, false)


func _throne_seat(x: float, z: float, scale_mul: float) -> Vector3:
	## Where on the throne somebody sits: the middle of the seat plate, at the height of it.
	##
	## Worth deriving rather than writing down, because the throne is placed from THIS file's
	## numbers and scaled by them too — a hand-measured seat height would be wrong the first
	## time anybody changed scale_mul, and wrong invisibly, with a boss hovering over his own
	## chair or buried in it.
	##
	## Two scans of the mesh, and both are confined to the MIDDLE THIRD of its width, which is
	## the whole trick: a chair's arms are higher than its seat, and a body sits between them.
	## Scanning the full width finds the arms and seats the boss on top of them — on this throne
	## that is 1.50 against a seat at 0.82, most of a body's height too high, and it looked
	## exactly like what it was.
	##
	## The SEAT PLATE is then the highest point of the throne that is forward of the throne's own
	## middle: a chair is a block you sit on with a slab behind it, so everything above the seat
	## is backrest, and everything above the seat is therefore BEHIND the middle. On this mesh
	## the arms top out at 0.857 of 1.89 and the seat plate at 0.465, a flat central surface of
	## 38 vertices.
	##
	## The SEAT DEPTH is what is left between the front of the backrest and the front of the
	## throne, and the sitter goes in the middle of it — far enough forward not to be inside the
	## slab, far enough back not to be perched on the lip.
	##
	## The y returned is a HEIGHT ABOVE THE FLOOR, not a world y, and it is the height of the
	## SURFACE: what a body has to do to rest its own weight on that surface is the body's
	## business, and a surprisingly involved one — see Enemy._seated_hip_drop.
	var m: Mesh = load(THRONE_MESH)
	if m == null:
		return Vector3.INF
	var arr: Array = m.surface_get_arrays(0)
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return Vector3.INF
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var aabb: AABB = m.get_aabb()
	var mid_z: float = aabb.get_center().z
	var mid_x: float = aabb.get_center().x
	var half_seat: float = aabb.size.x / 6.0     # the middle third, so the arms are excluded
	var seat_y := -INF
	for v in verts:
		if v.z > mid_z and absf(v.x - mid_x) <= half_seat:
			seat_y = maxf(seat_y, v.y)
	if seat_y == -INF:
		return Vector3.INF
	# The backrest, measured down the middle for the same reason: an arm reaches as far forward
	# as the seat does, and taking it for the backrest would put the sitter on the front lip.
	var back_z := -INF
	for v in verts:
		if v.y > seat_y + 0.001 and absf(v.x - mid_x) <= half_seat:
			back_z = maxf(back_z, v.z)
	if back_z == -INF:
		back_z = aabb.position.z
	var s: float = SCALE * scale_mul
	return Vector3(x, seat_y * s, z + (back_z + aabb.end.z) * 0.5 * s)


func _build_containers() -> void:
	## Chest and casks along the south wall — the far side of the room from the door, so
	## crossing to them means crossing the fight — and crates in the north-east corner.
	##
	## Three kinds of container, and the split is deliberate: the barrels are drink and only
	## drink (BARREL_LIQUIDS), the crates are gear and the odd health potion (CRATE_LOOT), and
	## the one thing worth crossing the room for is locked in the chest.
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
	_spot_beside(-5.0, wall_z, "stores")

	# Barrels beside it, working east along the same wall. Casks: what comes out of one is
	# bottled drink, and one cask is one liquid.
	#
	# Which liquid is rolled HERE, once per barrel, rather than left to the container: a `loot`
	# list of one means every bottle LootContainer draws is the same, which is what makes a
	# barrel of wine a barrel of wine instead of a mixed crate of three. Rolled off the room's
	# own _rng, so the casks come out the same way every run of the same SEED — the same
	# promise the rest of this file already makes about which floor tile lands where. Change
	# SEED to reshuffle them.
	for i in range(BARREL_PREFABS.size()):
		var barrel = LootContainerScript.new()
		barrel.configure(Vector3(5.0 + i * 2.0, FLOOR_Y, wall_z), 0.0,
			BARREL_PREFABS[i], SCALE)
		barrel.loot = [BARREL_LIQUIDS[_rng.randi() % BARREL_LIQUIDS.size()]]
		barrel.loot_rolls = BARREL_BOTTLES
		add_child(barrel)
		_spot_beside(5.0 + i * 2.0, wall_z, "stores")

	# And the crates in the north-east corner, where the gear is. Unlocked, so no key_id and no
	# lock_difficulty: they open to anyone who walks over and looks.
	for entry in CRATES:
		var crate = LootContainerScript.new()
		crate.configure(Vector3(entry["x"], FLOOR_Y, entry["z"]), entry["yaw"],
			entry["prefab"], SCALE * CRATE_SCALE_MUL)
		crate.loot = CRATE_LOOT
		crate.loot_rolls = entry["rolls"]
		add_child(crate)
		_spot_beside(entry["x"], entry["z"], "stores")


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
