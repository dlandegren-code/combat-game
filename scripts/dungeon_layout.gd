@tool
extends RefCounted
## A dungeon described as data: which tiles are floor, which room each belongs to, where the
## doors are, and where everything that is not masonry goes — the party, the enemies, the
## furniture, the loot on the floor.
##
## Made by DungeonGenerator from a quest's seed and tier, and turned into geometry by
## RoomBuilder. Nothing here touches a node, which is the point: the property Phase 4 is
## verified against ("the same seed reproduces the same quest") can be checked on this object
## directly, without building a scene to look at.
##
## TWO GRIDS, as everywhere else in the dungeon. The layout is in TILES — one Synty floor
## module, 4 world units — and everything that stands on the floor is on the play grid's 2-unit
## SQUARES, centred on odd coordinates. A tile is exactly two squares by two, and tile
## boundaries sit on multiples of 4, so a square is never on a tile line and "which tile is this
## square in" is a plain floor() with no edge cases.

const TILE := 4.0
const GRID := 2.0

## The seed and tier this was made from — kept so a builder can seed its own cosmetic rolls
## (which floor tile goes where) off the same number and stay reproducible.
var quest_seed := 0
var tier := 1
## The quest's theme (QuestDef.THEMES id): who lives here.
var theme := "dungeon"

## Every room and corridor, by id (its index here). Each is
##   {id, kind: "room" | "corridor", rect: Rect2i in tiles, role, depth, parent}
## where role is one of "entrance", "fight", "stores", "boss" for a room and "corridor" for a
## corridor, and depth is how many doors it is from the entrance.
var regions: Array = []

## Vector2i tile -> region id. The floor plan: a tile not in here is solid rock.
var tiles: Dictionary = {}

## The connections between regions. Each is {a: Vector2i, b: Vector2i, leaf: bool} — two tiles
## either side of one wall edge, and whether a door hangs there (true) or it is an open arch.
var doors: Array = []

## Squares the party comes in on, nearest the middle of the entrance first.
var party_spawns: Array = []

## {kind: EnemyTemplate id, at: Vector3, room: int} — the boss, if any, first.
var enemies: Array = []

## What stands in the rooms, as {type, room, at: Vector3, normal: Vector3, squares: Array}.
## `normal` points from the wall the thing is against into the room, and `squares` are the play
## squares it takes up, which nothing else may then be put on. Types the builder knows:
##   throne, banner, chest, barrel, crate, pillar, vessel, circle, table, bench, rack, statue, runestone (raiders only)
var features: Array = []

## {path: String, at: Vector3} — items lying loose on the floor.
var pickups: Array = []


# --- Asking where things are -----------------------------------------------

static func tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / TILE), floori(z / TILE))


func is_floor_at(x: float, z: float) -> bool:
	return tiles.has(tile_of(x, z))


func region_at(x: float, z: float) -> int:
	return int(tiles.get(tile_of(x, z), -1))


func rooms() -> Array:
	## The rooms, without the corridors joining them.
	var out: Array = []
	for r in regions:
		if r["kind"] == "room":
			out.append(r)
	return out


func room_with_role(role: String) -> Dictionary:
	for r in regions:
		if r["role"] == role:
			return r
	return {}


static func squares_in(rect: Rect2i) -> Array:
	## Every play square inside a tile rectangle, row by row.
	var out: Array = []
	var x0 := rect.position.x * TILE + GRID / 2.0
	var z0 := rect.position.y * TILE + GRID / 2.0
	for j in range(rect.size.y * 2):
		for i in range(rect.size.x * 2):
			out.append(Vector3(x0 + i * GRID, 0.0, z0 + j * GRID))
	return out


static func centre_of(rect: Rect2i) -> Vector3:
	## The middle of a tile rectangle in world space. Always on a LINE between squares, never on
	## a square: a rectangle of whole tiles is an even number of squares across.
	return Vector3((rect.position.x + rect.size.x / 2.0) * TILE, 0.0,
		(rect.position.y + rect.size.y / 2.0) * TILE)


func bounds() -> Rect2:
	## The floor's extent in world x/z, for anything that needs to size itself to the level.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in tiles:
		lo = Vector2(minf(lo.x, t.x * TILE), minf(lo.y, t.y * TILE))
		hi = Vector2(maxf(hi.x, (t.x + 1) * TILE), maxf(hi.y, (t.y + 1) * TILE))
	if lo.x == INF:
		return Rect2()
	return Rect2(lo, hi - lo)


# --- Doors -----------------------------------------------------------------

static func door_geometry(door: Dictionary) -> Dictionary:
	## Where a doorway's pieces go, worked out once so the builder and the generator cannot
	## disagree about it.
	##
	##   yaw          0 for a wall running along x, 90 for one running along z
	##   module_at    origin of the wall module (Synty modules start at their LEFT edge)
	##   seal_at      the door node: on the wall line, level with the doorway square
	##   leaf_offset  from seal_at to the hole in the art, along the door's own x
	##   gap_u        the doorway square's centre, measured along the module from its origin
	##   thresholds   the two squares either side of the doorway — what must be kept clear
	##
	## The module is 4 units and the hole in it is centred on the line between its two squares,
	## so the doorway has to be ONE of them; it is the one the movement code's snap picks, the
	## same choice room_builder always made for its single door. A module turned 90 degrees runs
	## along -z from its origin (local +x maps to world -z), which is why the two cases land on
	## different sides of the hole.
	var a: Vector2i = door["a"]
	var b: Vector2i = door["b"]
	if a.x == b.x:
		var line_z := maxi(a.y, b.y) * TILE
		var x0 := a.x * TILE
		var cell_x := x0 + 3.0
		return {
			"yaw": 0.0,
			"module_at": Vector3(x0, 0.0, line_z),
			"seal_at": Vector3(cell_x, 0.0, line_z),
			"leaf_offset": (x0 + 2.0) - cell_x,
			"gap_u": cell_x - x0,
			"thresholds": [Vector3(cell_x, 0.0, line_z - 1.0), Vector3(cell_x, 0.0, line_z + 1.0)],
		}
	var line_x := maxi(a.x, b.x) * TILE
	var z0 := (a.y + 1) * TILE
	var cell_z := z0 - 1.0
	return {
		"yaw": 90.0,
		"module_at": Vector3(line_x, 0.0, z0),
		"seal_at": Vector3(line_x, 0.0, cell_z),
		# Along the door's own x, which is world -z once it is turned: the hole is at z0 - 2,
		# one unit further down -z than the square, so +1.
		"leaf_offset": cell_z - (z0 - 2.0),
		"gap_u": z0 - cell_z,
		"thresholds": [Vector3(line_x - 1.0, 0.0, cell_z), Vector3(line_x + 1.0, 0.0, cell_z)],
	}


static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	## One name for the wall edge between two neighbouring tiles, whichever side it is asked from.
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


func door_squares() -> Array:
	## Every square on either side of every doorway.
	var out: Array = []
	for d in doors:
		out.append_array(door_geometry(d)["thresholds"])
	return out
