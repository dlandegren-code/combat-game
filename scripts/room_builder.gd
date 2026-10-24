@tool
extends Node3D
## Builds the dungeon a quest describes, from Synty modular pieces.
##
## WHAT IS BUILT is decided elsewhere: DungeonGenerator turns the quest's seed and tier into a
## DungeonLayout — which tiles are floor, which room each belongs to, where the doors are and
## what stands where — and this file only turns that into geometry. So it knows how to stand a
## wall, hang a door, seat a throne and fill a cask, and nothing at all about where any of them
## should go.
##
## Pieces are scaled by SCALE (Synty tiles are a chunky 5 units; scaling them down sits better
## against the ~1-unit characters), which makes a floor tile 4 world units — the layout's TILE —
## and every wall module two play squares long.
##
## It is still the AUTHORITY the rest of the game asks about the room: is_floor_at (where a unit
## can stand), idle_spots and patrol_ring (where an idle enemy takes itself), and now
## region_at (which room a square is in, which is what the alarm is scoped by).
##
## Regenerates on _ready (runs in-editor via @tool). In the editor, and in any run with no
## contract taken, it builds FALLBACK_SEED at tier 1, so the scene always has a dungeon in it.

const LayoutScript := preload("res://scripts/dungeon_layout.gd")
const GeneratorScript := preload("res://scripts/dungeon_generator.gd")
const QuestDefScript := preload("res://scripts/quest_def.gd")

## The dungeon built when there is no quest to read one from: the editor, a dev run of the quest
## scene on its own, and the round-trip test. Fixed, so all three see the same place.
const FALLBACK_SEED := 1337

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
const WALL_MAT := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"

# Stone props (same atlas material as the walls). Throne/vessel are solid obstacles;
# banners are flat wall decor (collision-free).
const THRONE_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Throne_01.res"
const VESSEL_MESH := "res://Assets/PolygonDungeon/Models/SM_Env_Stone_Vessel_01.res"
const WALL_BANNER_MESH := "res://Assets/PolygonDungeon/Models/SM_Prop_Wall_Banner_01.res"
## Spare scaling for the throne, on top of SCALE. A throne at bare scale is a dining chair.
const THRONE_SCALE_MUL := 2.2
## How high a banner hangs.
const BANNER_Y := 4.0

## The pillars a big room is ringed with: a short collider (see column_obstacle.gd) and the
## pack's round pillar for looks.
const ColumnScript := preload("res://scripts/column_obstacle.gd")
const PILLAR_VISUAL := preload("res://scenes/pillar_visual.tscn")

# Searchable furniture.
#
# The pack's PREFABS, not its raw meshes, unlike everything else in this file. A chest is two
# meshes plus the transform that marries them, and that transform lives in the prefab: the lid
# is authored with its origin on its own hinge, so placed at a raw offset it renders sticking
# out the front of the chest. Barrels and crates come through the same door for consistency.
const CHEST_PREFAB := "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Chest_01.tscn"

## The barrels in a stores room, one prefab after another along the wall.
const BARREL_PREFABS := [
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_01.tscn",
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_02.tscn",
	"res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Barrel_03.tscn",
]

## What comes out of a barrel: drink, and nothing but.
##
## One of these per barrel, picked when the room is built. A cask holds ONE liquid all the way
## down, so a barrel of beer gives beer and only beer; the random part is which barrel turns out
## to be the beer. Swords and breastplates live in the crates.
const BARREL_LIQUIDS := [
	"res://resources/items/bottle_of_beer.tres",
	"res://resources/items/bottle_of_water.tres",
	"res://resources/items/bottle_of_wine.tres",
]

## Bottles per barrel, all of them the same liquid. Enough that a barrel reads as a barrel
## rather than as a shelf with one bottle on it, and low enough that the drink does not
## out-heal the chest.
const BARREL_BOTTLES := 3

## The crates there are, and how many draws each gets. Unlocked, every one of them: this is the
## loot you get for looking round the room, and the lock is what makes the chest the chest.
##
## The pack ships no crate with a separate lid mesh, so these have no lid to swing and get
## searched the way a barrel is (LootContainer._find_lid). One is the pack's open-topped metal
## crate, which is the closest the art gets to saying "already unlocked".
const CRATES := [
	{"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Wood_01.tscn", "rolls": 2},
	{"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Metal_Open_01.tscn", "rolls": 1},
	{"prefab": "res://Assets/PolygonDungeon/Prefabs/Props/SM_Prop_Crate_Wood_03.tscn", "rolls": 2},
]

## What a crate might have in it. Gear, plus the one exception: a health potion — the only
## reason to bother with a crate when you are hurt rather than under-equipped. Ordinary kit on
## purpose: a crate is the consolation prize, and the thing worth having is behind the lock.
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
## boss is FOR, and it has to be worth crossing the dungeon and killing him for.
const CHEST_LOOT := [
	"res://resources/items/boss_cleaver.tres",
	"res://resources/items/reinforced_leather_armor.tres",
	"res://resources/items/heavy_armor.tres",
	"res://resources/items/knight_helmet.tres",
	"res://resources/items/ranger_dagger.tres",
]

## Spare scaling for the chest, on top of SCALE. Doubled, the chest stands about 1.14 — taller
## than the barrels, which is the call: a treasure chest is the thing worth walking over to.
const CHEST_SCALE_MUL := 2.0

## Whether the chest starts shut AND locked. True: getting in means the boss's key or a lockpick
## roll against CHEST_LOCK_PENALTY.
const CHEST_STARTS_LOCKED := true

## The lock on the chest, and the key that opens it. The id is shared with iron_key.tres by
## hand — there is no registry of locks, and for one chest a registry would be ceremony.
const CHEST_KEY_ID := "dungeon_chest"
## Taken off the lockpick skill before the d20 is read: the archer's starting 9 picks it on a
## 5 or less (25%), and nobody untrained gets to roll at all.
const CHEST_LOCK_PENALTY := 4

const SCALE := 0.8                 # dial the whole environment's size here
const TILE := 5.0 * SCALE          # world units per tile (= 4.0 at 0.8) — DungeonLayout.TILE
const FLOOR_Y := 0.0

const LAYER_OBSTACLE := 4          # matches Combatant.LAYER_OBSTACLE (blocks move + LOS)
## Combatant.GRID_SIZE: the play grid. The environment is built on TILE (4.0) and played on
## this (2.0), so one wall module spans exactly two squares — which is the whole reason a
## doorway needs deciding rather than just leaving a hole.
const GRID := 2.0
## How far a doorway jamb reaches past the edge of the doorway square, in world units. See
## _place_doorway_jambs — it exists to close the seam a diagonal step can otherwise graze.
const JAMB_OVERLAP := 0.06

const DoorScript := preload("res://scripts/door.gd")
const LootContainerScript := preload("res://scripts/loot_container.gd")
const OcclusionFaderScript := preload("res://scripts/occlusion_fader.gd")
const RosterScript := preload("res://scripts/enemy_roster.gd")

const DIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

## What a dungeon is built OUT of, by quest theme. The layout is the same whatever the kit — the
## generator never asks — so a kit only ever changes how a square looks, never what is on it.
##
## Scales are absolute (what the mesh is multiplied by), not on top of SCALE: the Dungeon pack's
## modules are 5 units and sit at 0.8, the Viking pack's are 2.5 m and sit at 1.6, and both come
## out at one TILE. A kit that leaves a key out gets the dungeon's.
const VK := "res://assets/vikings/"
const KITS := {
	"dungeon": {
		"floor_tiles": [FLOORS_DIR + "SM_Env_Tiles_01.tscn", FLOORS_DIR + "SM_Env_Tiles_02.tscn",
			FLOORS_DIR + "SM_Env_Tiles_03.tscn"],
		"floor_centre": FLOORS_DIR + ROOM_CENTER_TILE,
		"circle_quarter": FLOORS_DIR + CIRCLE_QUARTER,
		"module_scale": SCALE,
		"wall": WALL_MESH,
		"door_frame": DOOR_MESH,
		"door_leaf": DOOR_LEAF_MESH,
		"material": WALL_MAT,
		"throne": THRONE_MESH,
		"throne_scale": SCALE * THRONE_SCALE_MUL,
		"banner": WALL_BANNER_MESH,
		"banner_y": BANNER_Y,
		"banner_yaw": 180.0,
		"vessel": VESSEL_MESH,
		"vessel_scale": SCALE,
		"pillar": "",
		"chest": CHEST_PREFAB,
		"chest_scale": SCALE * CHEST_SCALE_MUL,
		"barrels": BARREL_PREFABS,
		"barrel_scale": SCALE,
		"crates": CRATES,
		"crate_scale": SCALE * CRATE_SCALE_MUL,
	},
	# A Viking mead hall: log walls, plank floor, the pack's carved high seat, a dragon banner
	# either side of it, a stone hearth where the dungeon has its vessel — and, only here, the
	# long tables the generator lays for this theme, furs to sleep on and torches on the walls.
	"raiders": {
		"floor_tiles": [VK + "prefabs/SM_Bld_Base_Floor_01.tscn"],
		"floor_centre": "",
		"circle_quarter": "",
		"module_scale": 1.6,
		"wall": VK + "models/SM_Bld_Wall_Logs_01.res",
		"door_frame": VK + "models/SM_Bld_Wall_Logs_Door_01.res",
		"door_leaf": VK + "models/SM_Bld_Door_01.res",
		"material": VK + "viking_mat_01_A.tres",
		"throne": VK + "models/SM_Prop_Throne_01.res",
		"throne_scale": 2.0,
		"banner": VK + "models/SM_Prop_Flag_02.res",
		"banner_cloth": VK + "models/SM_Prop_Flag_02_Flag.res",
		"banner_material": VK + "viking_banner_mat.tres",
		"banner_y": 0.0,
		"banner_yaw": 0.0,
		"banner_scale": 1.3,
		"vessel": VK + "models/SM_Prop_Fire_Pit_02.res",
		"vessel_scale": 0.9,
		"hearth_light": true,
		"pillar": VK + "prefabs/SM_Bld_Pillar_02.tscn",
		"pillar_scale": 1.6,
		"chest": VK + "prefabs/SM_Prop_Chest_01.tscn",
		"chest_scale": 1.6,
		"barrels": [VK + "prefabs/SM_Prop_Barrel_01.tscn", VK + "prefabs/SM_Prop_Mead_Barrel_01.tscn",
			VK + "prefabs/SM_Prop_Barrel_03.tscn"],
		"barrel_scale": 1.6,
		"crates": [{"prefab": VK + "prefabs/SM_Gen_Prop_Crate_03.tscn", "rolls": 2},
			{"prefab": VK + "prefabs/SM_Gen_Prop_Crate_02.tscn", "rolls": 2}],
		"crate_scale": 1.4,
		"table": VK + "models/SM_Prop_Table_02.res",
		"table_scale": 1.6,
		"table_food": VK + "models/SM_Prop_Boar_Roasted_01.res",
		"bench": VK + "models/SM_Prop_Bench_01.res",
		"rack": VK + "prefabs/SM_Prop_Weapon_Rack_01.tscn",
		"rack_scale": 1.35,
		# [mesh, scale, material ("" = the kit's)], one picked per piece. Scaled so each fills
		# about one square and stays under the 4.8 walls; the pack's colossus (Statue_02, 10 m)
		# is an outdoor piece and left out.
		"statues": [[VK + "models/SM_Prop_Statue_01.res", 1.35, ""],
			[VK + "models/SM_Prop_Statue_03.res", 1.05, ""],
			[VK + "models/SM_Prop_Statue_04.res", 1.05, ""]],
		"runestones": [[VK + "models/SM_Prop_RuneStone_01.res", 1.05, VK + "viking_mat_02_C.tres"],
			[VK + "models/SM_Prop_RuneStone_02.res", 0.95, VK + "viking_mat_02_C.tres"],
			[VK + "models/SM_Prop_RuneStone_03.res", 0.7, VK + "viking_mat_02_C.tres"],
			[VK + "models/SM_Prop_RuneStone_04.res", 1.2, VK + "viking_mat_02_C.tres"]],
		"pelts": [VK + "models/SM_Prop_Pelt_03.res", VK + "models/SM_Prop_Pelt_01.res"],
		"pelt_scale": 0.9,
		"torch": VK + "models/SM_Prop_Torch_01.res",
		"torch_scale": 1.6,
		"torch_y": 2.6,
		"room_light": true,
		# A shingled roof over every floor tile at wall-top height, and timber beams across each
		# room under it. The fader (occlusion_fader.gd) lifts the roof wherever the party is.
		"roof": VK + "models/SM_Bld_Base_Ceiling_01.res",
		"roof_material": VK + "viking_roof_mat.tres",
		"beam": VK + "models/SM_Gen_Bld_Beam_01.res",
		"beam_scale": 1.6,
	},
}
## What a weapon rack can be searched for: one of the raiders' own arms.
const RACK_LOOT := [
	"res://resources/items/viking_axe.tres",
	"res://resources/items/seax.tres",
	"res://resources/items/viking_spear.tres",
	"res://resources/items/viking_sword.tres",
	"res://resources/items/round_shield.tres",
]
## A kit's "throne_scale" is the high seat of something huge; a boss of ordinary size gets it at
## this share of that, which puts the seat about knee-high on a humanoid instead of at its hip.
const THRONE_NORMAL := 0.7
## A boss template at least this big (EnemyTemplate.size) gets the full-sized throne.
const THRONE_GIANT_SIZE := 1.5
## How warm and how far the hearth glows, for a kit with "hearth_light".
const HEARTH_COLOR := Color(1.0, 0.62, 0.3)
const HEARTH_ENERGY := 2.2
const HEARTH_RANGE := 11.0
## A kit with "room_light" hangs one warm, shadowless light over the middle of each room — the
## torchlight a hall full of torches would have, at the cost of one light a room, not one a torch.
const ROOM_LIGHT_COLOR := Color(1.0, 0.72, 0.45)
const ROOM_LIGHT_ENERGY := 1.4
const ROOM_LIGHT_Y := 3.4
## One wall torch every this many wall modules round a room, for a kit that has them.
const TORCH_EVERY := 3

var _rng := RandomNumberGenerator.new()

## The dungeon being built. See DungeonLayout.
var layout: RefCounted = null
## What it is being built out of: one of KITS, by the quest's theme.
var _kit: Dictionary = {}
## What the fader may ghost when it hides somebody (walls, doors, beams), and the roof by region.
var _occluders: Array = []
var _roofs: Dictionary = {}

## Somewhere an idle enemy might take itself, and what to look at once it gets there, keyed by
## what a body would be doing there. Filled as the room is BUILT, from the same positions the
## furniture is placed at, so a spot cannot come to mean a square the furniture has moved off.
var _idle_spots := {}


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_idle_spots.clear()
	_occluders.clear()
	_roofs.clear()
	layout = _choose_layout()
	_kit = KITS.get(String(layout.theme), KITS["dungeon"])
	_rng.seed = layout.quest_seed
	_build_floors()
	_build_walls()
	_build_features()
	_build_idle_corners()
	_build_dressing()
	# Not in the editor: there is no party there to keep in view, and the editor's own camera
	# would have the walls ghosting as it moves.
	if not Engine.is_editor_hint():
		var fader = OcclusionFaderScript.new()
		fader.name = "OcclusionFader"
		fader.occluders = _occluders
		fader.roofs = _roofs
		fader.room = self
		add_child(fader)


func _k(key: String):
	## The kit's piece for `key`, or the dungeon's when this kit has none.
	return _kit.get(key, KITS["dungeon"].get(key))


func _choose_layout() -> RefCounted:
	## The quest the party is on, or the fallback dungeon when there is none.
	##
	## Read off the GameState autoload by path rather than by name, because this script also
	## runs in the editor (@tool), where the autoload does not exist.
	var quest_seed := FALLBACK_SEED
	var tier := 1
	var budget: int = QuestDefScript.ENEMY_BUDGET_BASE
	var theme := "dungeon"
	if not Engine.is_editor_hint():
		var gs := get_node_or_null("/root/GameState")
		var q = gs.current_quest if gs != null else null
		if q != null:
			quest_seed = q.quest_seed
			tier = q.tier
			budget = q.enemy_budget
			theme = q.theme
	return GeneratorScript.generate(quest_seed, tier, budget, theme)


# --- What the rest of the game asks ----------------------------------------

func is_floor_at(x: float, z: float) -> bool:
	## Whether a play-grid square has dungeon floor under it. THE authority on where a unit can
	## be put, asked by Combatant._is_in_arena.
	return layout != null and layout.is_floor_at(x, z)


func region_at(x: float, z: float) -> int:
	## Which room or corridor a square is in, by DungeonLayout region id; -1 for rock.
	return layout.region_at(x, z) if layout != null else -1


func party_spawns() -> Array:
	return layout.party_spawns if layout != null else []


func enemy_spawns() -> Array:
	return layout.enemies if layout != null else []


func pickups() -> Array:
	return layout.pickups if layout != null else []


func floor_tiles() -> Array:
	return layout.tiles.keys() if layout != null else []


func idle_spots(kind: String, room: int = -1) -> Array:
	## Squares worth loitering at, by what a body would be doing there:
	##
	##   "seat"    the throne — the squares in front of it, facing out over the hall
	##   "stores"  the chest, the casks and the crates — the square you stand on to work one
	##   "corner"  the corners of a room, for anybody minded to lie down out of the way
	##
	## Each entry is {"at": Vector3, "face": Vector3, "perch": Vector3, "room": int}: the square
	## to stand on, the point to turn towards from it, and — for a spot you get ON rather than
	## stand beside — where to put yourself once you are there, or INF for nowhere but the square
	## itself.
	##
	## `room` keeps an enemy in its own room: a goblin going to lean on the casks should not
	## cross three rooms and a corridor to find some. -1 for anywhere.
	var all: Array = _idle_spots.get(kind, [])
	if room < 0:
		return all
	var out: Array = []
	for s in all:
		if int(s["room"]) == room:
			out.append(s)
	return out


func patrol_ring(room: int = -1) -> Array[Vector3]:
	## A beat round a room, for a patroller the scene did not author a route for. Derived from
	## the room rather than written down, so WHICH enemies patrol can be decided at runtime (see
	## CombatManager._cast_idle_roles). -1 means the biggest room.
	var ring: Array[Vector3] = []
	if layout == null:
		return ring
	var pick: Dictionary = {}
	if room >= 0 and room < layout.regions.size():
		pick = layout.regions[room]
	if pick.is_empty() or not pick.has("patrol"):
		var best := -1
		for r in layout.rooms():
			var area: int = r["rect"].size.x * r["rect"].size.y
			if area > best:
				best = area
				pick = r
	for p in pick.get("patrol", []):
		ring.append(p)
	return ring


func _room_centre(room: int) -> Vector3:
	if layout == null or room < 0 or room >= layout.regions.size():
		return Vector3.ZERO
	return LayoutScript.centre_of(layout.regions[room]["rect"])


func _add_idle_spot(kind: String, at: Vector3, face: Vector3, room: int,
		perch: Vector3 = Vector3.INF) -> void:
	if not _idle_spots.has(kind):
		_idle_spots[kind] = []
	_idle_spots[kind].append({"at": at, "face": face, "perch": perch, "room": room})


func _spot_beside(at: Vector3, normal: Vector3, room: int, kind: String) -> void:
	## Register the square in front of a piece of furniture standing against a wall: one step
	## from it into the room, facing back at it.
	_add_idle_spot(kind, at + normal * GRID, at, room)


func _build_idle_corners() -> void:
	## The free inside corners of every room. Out of the way by definition, which is what makes
	## them the place to have a lie-down: a goblin dozing in the middle of the floor is in the
	## way of everything, including the fight it is about to be in.
	for r in layout.rooms():
		for s in r.get("corners", []):
			_add_idle_spot("corner", s, _room_centre(r["id"]), r["id"])


# --- Floors ----------------------------------------------------------------

func _build_floors() -> void:
	# A round floor, where a room has one, takes the 2x2 tiles about its centre: four
	# quarter-circle tiles, each rotated so its arc faces the shared point. A kit with no
	# quarter-circle tile lays its ordinary floor there instead.
	var circled := {}
	var quarter: String = _k("circle_quarter")
	for f in layout.features:
		if f["type"] != "circle" or quarter == "":
			continue
		var c: Vector3 = f["at"]
		var ct := LayoutScript.tile_of(c.x, c.z)
		for dz in [-1, 0]:
			for dx in [-1, 0]:
				circled[ct + Vector2i(dx, dz)] = true
		_place_tile(quarter, c.x + TILE, c.z + TILE, 180.0)
		_place_tile(quarter, c.x + TILE, c.z - TILE, 270.0)
		_place_tile(quarter, c.x - TILE, c.z - TILE, 0.0)
		_place_tile(quarter, c.x - TILE, c.z + TILE, 90.0)

	for t in layout.tiles:
		if circled.has(t):
			continue
		var region: Dictionary = layout.regions[layout.tiles[t]]
		var rect: Rect2i = region["rect"]
		var tile: String = _random_main_tile()
		# The odd-sized room's middle tile gets the pack's centrepiece.
		if region["kind"] == "room" and rect.size.x % 2 == 1 and rect.size.y % 2 == 1 \
				and t == rect.position + rect.size / 2 and String(_k("floor_centre")) != "":
			tile = _k("floor_centre")
		_place_tile(tile, t.x * TILE, t.y * TILE, 0.0)


# --- Walls and doorways ----------------------------------------------------

func _build_walls() -> void:
	## A wall along every tile edge that has floor on one side and rock on the other, or that
	## divides two different rooms — except where the layout says there is a way through.
	var doorways := {}
	for d in layout.doors:
		doorways[LayoutScript.edge_key(d["a"], d["b"])] = d
	var done := {}
	for t in layout.tiles:
		for dir in DIRS:
			var n: Vector2i = t + dir
			var key := LayoutScript.edge_key(t, n)
			if done.has(key):
				continue
			done[key] = true
			if layout.tiles.has(n) and layout.tiles[n] == layout.tiles[t]:
				continue
			if doorways.has(key):
				_build_doorway(doorways[key])
				continue
			var at := _edge_module(t, dir)
			_place_wall(_k("wall"), at.x, at.z, at.y)


func _edge_module(t: Vector2i, dir: Vector2i) -> Vector3:
	## Where the wall module for one edge of a tile goes, as (x, yaw, z). Synty wall modules
	## start at their left edge: one at yaw 0 runs +x from its origin, one at yaw 90 runs -z.
	if dir == Vector2i(0, 1):
		return Vector3(t.x * TILE, 0.0, (t.y + 1) * TILE)
	if dir == Vector2i(0, -1):
		return Vector3(t.x * TILE, 0.0, t.y * TILE)
	if dir == Vector2i(1, 0):
		return Vector3((t.x + 1) * TILE, 90.0, (t.y + 1) * TILE)
	return Vector3(t.x * TILE, 90.0, (t.y + 1) * TILE)


func _build_doorway(door: Dictionary) -> void:
	## A doorframe module, and — where the layout says so — a door hung in it. The geometry is
	## the layout's (DungeonLayout.door_geometry), so the square the door seals and the squares
	## the generator kept clear of furniture are the same squares by construction.
	var g: Dictionary = LayoutScript.door_geometry(door)
	var at: Vector3 = g["module_at"]
	_place_wall(_k("door_frame"), at.x, at.z, g["yaw"], g["gap_u"])
	if door.get("leaf", false):
		var d = DoorScript.build(self, g["seal_at"], g["leaf_offset"], g["yaw"],
			_k("door_leaf"), _k("material"), _k("module_scale"))
		var leaf := d.get_node_or_null("Hinge/Leaf") as GeometryInstance3D
		if leaf != null:
			_occluders.append(leaf)


func _place_wall(mesh_path: String, x: float, z: float, rot_y_deg: float,
		gap_u: float = 0.0) -> void:
	var m: Mesh = load(mesh_path)
	if m == null:
		return
	var ms: float = _k("module_scale")
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = load(_k("material"))
	mi.position = Vector3(x, FLOOR_Y, z)
	mi.rotation_degrees = Vector3(0, rot_y_deg, 0)
	mi.scale = Vector3(ms, ms, ms)
	add_child(mi)
	_occluders.append(mi)
	# Solid walls block movement + line of sight (obstacle layer 4). The box is sized from the
	# mesh AABB and rides the MeshInstance's scale, so it matches.
	#
	# The doorway module is the exception: a module is 4 units and the play grid is 2, so
	# leaving the WHOLE module open would make a two-square hole in a wall whose art shows a
	# one-square door. It gets jambs instead — see _place_doorway_jambs.
	if mesh_path == _k("door_frame"):
		_place_doorway_jambs(mi, m, gap_u, ms)
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


func _place_doorway_jambs(mi: MeshInstance3D, m: Mesh, gap_u: float, ms: float) -> void:
	## Wall the solid parts of a doorway module and leave exactly one grid square open.
	##
	## `gap_u` is the centre of the doorway square measured ALONG the module from its origin, in
	## world units, whichever way the module is turned — so this works the same for a wall
	## running along x and one running along z.
	var aabb := m.get_aabb()
	var lo: float = aabb.position.x * ms
	var hi: float = lo + aabb.size.x * ms
	# Each jamb reaches a hair PAST the doorway square rather than stopping dead on its edge.
	# A diagonal step from the square beside the doorway to the square beyond it crosses the
	# wall plane exactly on that edge, and a ray that grazes the seam between two boxes reports
	# whatever floating point feels like. The overlap is far too small to trouble the ray down
	# the middle of the doorway square, a whole unit away.
	var gap_lo: float = gap_u - GRID / 2.0 + JAMB_OVERLAP
	var gap_hi: float = gap_u + GRID / 2.0 - JAMB_OVERLAP
	for span in [[lo, gap_lo], [gap_hi, hi]]:
		var width: float = span[1] - span[0]
		# A sliver is the module's own overlap with its neighbour, which that neighbour's
		# collider already covers.
		if width < 0.1:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_OBSTACLE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# In the module's OWN units, because the shape hangs off the MeshInstance and inherits
		# its scale. Only `width` and the span arrive in world units, so only they are divided
		# back out.
		box.size = Vector3(width / ms, aabb.size.y, aabb.size.z)
		cs.shape = box
		cs.position = Vector3(
			(span[0] + span[1]) / 2.0 / ms,
			aabb.get_center().y,
			aabb.get_center().z)
		body.add_child(cs)
		mi.add_child(body)


# --- Furniture -------------------------------------------------------------

static func _yaw_facing(normal: Vector3) -> float:
	## The yaw that turns a prop's front (+z) to face along `normal`.
	return rad_to_deg(atan2(normal.x, normal.z))


func _build_features() -> void:
	var barrel_index := 0
	for f in layout.features:
		var at: Vector3 = f["at"]
		var n: Vector3 = f["normal"]
		var room: int = f["room"]
		match String(f["type"]):
			"throne":
				_build_throne(at, n, room, f["squares"])
			"banner":
				# Rotated so the decorated face points into the room, not at the wall.
				var yaw: float = _yaw_facing(n) + float(_k("banner_yaw"))
				var bs: float = _kit.get("banner_scale", SCALE)
				_place_prop(_k("banner"), at.x, at.z, yaw, false, _k("banner_y"), true, bs / SCALE)
				if _kit.has("banner_cloth"):
					_place_prop(_kit["banner_cloth"], at.x, at.z, yaw, false, _k("banner_y"), true,
						bs / SCALE, _kit["banner_material"])
			"vessel":
				# On a grid crossing: blocks diagonal cuts through it (the collider) but does NOT
				# reserve a cell, so the four squares around it stay walkable.
				_place_prop(_k("vessel"), at.x, at.z, 0.0, true, FLOOR_Y, false,
					float(_k("vessel_scale")) / SCALE)
				if _kit.get("hearth_light", false):
					_place_hearth_light(at)
			"table":
				_build_table(at, n, f["squares"])
			"bench":
				_build_bench(at, n, f["squares"])
			"rack":
				_build_rack(at, n, room)
			"statue":
				_build_monument(at, n, "statues")
			"runestone":
				_build_monument(at, n, "runestones")
			"pillar":
				_place_column(at)
			"chest":
				_build_chest(at, n, room)
			"barrel":
				_build_barrel(at, n, room, barrel_index)
				barrel_index += 1
			"crate":
				_build_crate(at, n, room)


func _build_throne(at: Vector3, normal: Vector3, room: int, squares: Array) -> void:
	## Placed WITHOUT a collider: its two squares are reserved explicitly, so exactly those
	## squares block. A collider's footprint would spill into the neighbours.
	var abs_scale: float = _k("throne_scale")
	if _boss_size() < THRONE_GIANT_SIZE:
		abs_scale *= THRONE_NORMAL
	var mul: float = abs_scale / SCALE
	_place_prop(_k("throne"), at.x, at.z, _yaw_facing(normal), false, FLOOR_Y, false, mul)
	for s in squares:
		_reserve_cell(s.x, s.z)
	# The squares in front of it, looking out over the hall — where somebody holding this room
	# would put himself. Not the throne's OWN squares: those are reserved above.
	var seat := _throne_seat(at, normal, mul)
	for s in squares:
		_add_idle_spot("seat", s + normal * GRID, _room_centre(room), room, seat)


func _boss_size() -> float:
	## How big the dungeon's boss is, by its template; 1 when there is none.
	for e in layout.enemies:
		var t = RosterScript.find(String(e["kind"]))
		if t != null and t.is_boss:
			return t.size
	return 1.0


func _build_chest(at: Vector3, normal: Vector3, room: int) -> void:
	var chest = LootContainerScript.new()
	# The y here is a placeholder: a container settles onto the floor surface itself.
	# The chest's lid hinges at its local -Z, the side against the wall, and swings open over
	# the +Z side you stand on.
	chest.configure(at, _yaw_facing(normal), _k("chest"), _k("chest_scale"))
	chest.open_verb = "Open"
	chest.locked = CHEST_STARTS_LOCKED
	chest.key_id = CHEST_KEY_ID
	chest.lock_penalty = CHEST_LOCK_PENALTY
	chest.loot = CHEST_LOOT
	chest.loot_rolls = 2
	# Added last: _ready() builds the geometry, and it must not run before the fields above
	# are in place.
	add_child(chest)
	_spot_beside(at, normal, room, "stores")


func _build_barrel(at: Vector3, normal: Vector3, room: int, index: int) -> void:
	## Which liquid is rolled HERE, once per barrel, rather than left to the container: a `loot`
	## list of one means every bottle drawn is the same, which is what makes a barrel of wine a
	## barrel of wine. Rolled off the room's own _rng, so the casks come out the same way every
	## time the same quest is built.
	var barrel = LootContainerScript.new()
	var barrels: Array = _k("barrels")
	barrel.configure(at, _yaw_facing(normal), barrels[index % barrels.size()], _k("barrel_scale"))
	barrel.loot = [BARREL_LIQUIDS[_rng.randi() % BARREL_LIQUIDS.size()]]
	barrel.loot_rolls = BARREL_BOTTLES
	add_child(barrel)
	_spot_beside(at, normal, room, "stores")


func _build_crate(at: Vector3, normal: Vector3, room: int) -> void:
	var crates: Array = _k("crates")
	var entry: Dictionary = crates[_rng.randi() % crates.size()]
	var crate = LootContainerScript.new()
	crate.configure(at, _yaw_facing(normal), entry["prefab"], _k("crate_scale"))
	crate.loot = CRATE_LOOT
	crate.loot_rolls = entry["rolls"]
	add_child(crate)
	_spot_beside(at, normal, room, "stores")


func _place_column(at: Vector3) -> void:
	## A pillar, built the way the hand-placed ones in the old chamber were: a short cylinder on
	## the obstacle layer (column_obstacle.gd puts it in "obstacles") and the pack's round pillar.
	var body := StaticBody3D.new()
	body.set_script(ColumnScript)
	body.name = "Column"
	body.collision_layer = LAYER_OBSTACLE
	body.position = Vector3(at.x, FLOOR_Y, at.z)
	var cs := CollisionShape3D.new()
	cs.shape = CylinderShape3D.new()
	body.add_child(cs)
	var pillar: String = _k("pillar")
	if pillar == "":
		body.add_child(PILLAR_VISUAL.instantiate())
	else:
		var visual := (load(pillar) as PackedScene).instantiate() as Node3D
		visual.scale = Vector3.ONE * float(_kit.get("pillar_scale", 1.0))
		body.add_child(visual)
	add_child(body)


func _throne_seat(at: Vector3, normal: Vector3, scale_mul: float) -> Vector3:
	## Where on the throne somebody sits: the middle of the seat plate, at the height of it.
	##
	## Worth deriving rather than writing down, because the throne is placed from THIS file's
	## numbers and scaled by them too — a hand-measured seat height would be wrong the first
	## time anybody changed scale_mul, and wrong invisibly, with a boss hovering over his own
	## chair or buried in it.
	##
	## Two scans of the mesh, and both are confined to the MIDDLE THIRD of its width, which is
	## the whole trick: a chair's arms are higher than its seat, and a body sits between them.
	##
	## The SEAT PLATE is then the highest point of the throne that is forward of the throne's own
	## middle: a chair is a block you sit on with a slab behind it, so everything above the seat
	## is backrest, and everything above the seat is therefore BEHIND the middle.
	##
	## The SEAT DEPTH is what is left between the front of the backrest and the front of the
	## throne, and the sitter goes in the middle of it.
	##
	## The y returned is a HEIGHT ABOVE THE FLOOR, not a world y, and it is the height of the
	## SURFACE: what a body has to do to rest its own weight on that surface is the body's
	## business — see Enemy._seated_hip_drop. The forward offset is along `normal`, the way the
	## throne was turned to face.
	var m: Mesh = load(_k("throne"))
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
	var forward: float = (back_z + aabb.end.z) * 0.5 * s
	var out := at + normal * forward
	out.y = seat_y * s
	return out


func _reserve_cell(x: float, z: float) -> void:
	## Invisible marker so _is_obstacle_at treats this grid cell as blocked. Used to
	## reserve every cell a multi-cell prop (the throne) sits on.
	var marker := Node3D.new()
	marker.position = Vector3(x, FLOOR_Y, z)
	marker.add_to_group("obstacles")
	add_child(marker)


func _place_prop(mesh_path: String, x: float, z: float, rot_y_deg: float, solid := true,
		y := FLOOR_Y, reserve_cell := true, scale_mul := 1.0, material_path := "") -> MeshInstance3D:
	var m: Mesh = load(mesh_path)
	if m == null:
		return null
	var s := SCALE * scale_mul
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = load(material_path if material_path != "" else String(_k("material")))
	mi.position = Vector3(x, y, z)
	mi.rotation_degrees = Vector3(0, rot_y_deg, 0)
	mi.scale = Vector3(s, s, s)
	add_child(mi)
	if not solid:
		return mi
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
	return mi


func _place_tile(prefab_path: String, x: float, z: float, rot_y_deg: float) -> void:
	var scene: PackedScene = load(prefab_path)
	if scene == null:
		return
	var ms: float = _k("module_scale")
	var tile: Node3D = scene.instantiate()
	tile.position = Vector3(x, FLOOR_Y, z)
	tile.rotation_degrees = Vector3(0, rot_y_deg, 0)
	tile.scale = Vector3(ms, ms, ms)
	add_child(tile)


func _random_main_tile() -> String:
	var tiles: Array = _k("floor_tiles")
	return tiles[_rng.randi() % tiles.size()]


# --- Hall dressing (kits that have it) -------------------------------------

func _build_table(at: Vector3, along: Vector3, squares: Array) -> void:
	## A long table down two squares, the generator's "table". Its squares are reserved like the
	## throne's, and the collider makes it a thing you cannot see a goblin through either.
	if not _kit.has("table"):
		return
	var ts: float = _kit["table_scale"]
	var mi := _place_prop(_kit["table"], at.x, at.z, _yaw_facing(along), true, FLOOR_Y, false, ts / SCALE)
	for sq in squares:
		_reserve_cell(sq.x, sq.z)
	# Every other table has its dinner still on it.
	if mi != null and _kit.has("table_food") and _rng.randf() < 0.5:
		var top: float = mi.mesh.get_aabb().end.y * ts
		_place_prop(_kit["table_food"], at.x, at.z, _yaw_facing(along) + _rng.randf_range(-20.0, 20.0),
			false, top, false, ts / SCALE)


func _build_bench(at: Vector3, along: Vector3, squares: Array) -> void:
	## A bench down one side of a table. Its squares are reserved — nobody stands on a bench —
	## but it has no collider: it is knee-high, and a sight line or an arrow goes over it.
	if not _kit.has("bench"):
		return
	var ts: float = _kit["table_scale"]
	# The mesh is long along its own x and the table along its z, hence the quarter turn.
	_place_prop(_kit["bench"], at.x, at.z, _yaw_facing(along) + 90.0, false, FLOOR_Y, false, ts / SCALE)
	for sq in squares:
		_reserve_cell(sq.x, sq.z)


func _build_rack(at: Vector3, normal: Vector3, room: int) -> void:
	## A weapon rack against the wall, searched like a crate for one of the raiders' weapons.
	if not _kit.has("rack"):
		return
	var rack = LootContainerScript.new()
	rack.configure(at, _yaw_facing(normal), _kit["rack"], _kit["rack_scale"])
	rack.loot = RACK_LOOT
	rack.loot_rolls = 1
	add_child(rack)
	_spot_beside(at, normal, room, "stores")


func _build_monument(at: Vector3, normal: Vector3, list_key: String) -> void:
	## A statue or a rune stone against the wall, facing into the room: solid, holding its square,
	## and too tall to see past. Centred on the square by its bounds rather than its pivot — a
	## few of the rune stones are modelled well off their own origin.
	if not _kit.has(list_key):
		return
	var pick: Array = _kit[list_key][_rng.randi() % _kit[list_key].size()]
	var m: Mesh = load(pick[0])
	if m == null:
		return
	var sc: float = pick[1]
	var yaw := _yaw_facing(normal)
	var c := m.get_aabb().get_center() * sc
	var off := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(c.x, 0.0, c.z)
	_place_prop(pick[0], at.x - off.x, at.z - off.z, yaw, true, FLOOR_Y, false, sc / SCALE, pick[2])
	_reserve_cell(at.x, at.z)


func _place_hearth_light(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "HearthLight"
	light.light_color = HEARTH_COLOR
	light.light_energy = HEARTH_ENERGY
	light.omni_range = HEARTH_RANGE
	light.position = Vector3(at.x, 1.2, at.z)
	add_child(light)


func _build_dressing() -> void:
	## What a kit adds that the layout knows nothing about and no rule of the game cares about:
	## furs on the floor, torches on the walls. None of it blocks a square, a step or a sight line.
	## Drawn off the room's _rng AFTER everything that has a gameplay meaning, so it cannot move
	## a barrel's wine or a crate's loot.
	if _kit.has("pelts"):
		var pelts: Array = _kit["pelts"]
		var ps: float = _kit.get("pelt_scale", 1.0)
		# A fur in every free corner — that is where the raiders lie down (see "corner") — and
		# a big one laid before the high seat.
		for r in layout.rooms():
			for sq in r.get("corners", []):
				_place_prop(pelts[_rng.randi() % pelts.size()], sq.x, sq.z, _rng.randf_range(0.0, 360.0),
					false, FLOOR_Y + 0.02, false, ps / SCALE)
		for f in layout.features:
			if f["type"] == "throne":
				var rug: Vector3 = f["at"] + f["normal"] * GRID * 1.5
				_place_prop(pelts[pelts.size() - 1], rug.x, rug.z, _yaw_facing(f["normal"]), false,
					FLOOR_Y + 0.02, false, ps * 1.3 / SCALE)
	if _kit.has("torch"):
		_build_torches()
	if _kit.has("roof"):
		_build_roof()
	if _kit.get("room_light", false):
		for r in layout.rooms():
			var rect: Rect2i = r["rect"]
			var light := OmniLight3D.new()
			light.name = "RoomLight"
			light.light_color = ROOM_LIGHT_COLOR
			light.light_energy = ROOM_LIGHT_ENERGY
			light.omni_range = maxi(rect.size.x, rect.size.y) * TILE * 0.8
			var c := _room_centre(r["id"])
			light.position = Vector3(c.x, ROOM_LIGHT_Y, c.z)
			add_child(light)


func _build_roof() -> void:
	## One roof module over every floor tile, at the height of the wall tops, and a beam across
	## each room at every tile line along its length. No collider on any of it — nothing in the
	## game may hit a roof — and no shadow: lit from above, a roof would black out the hall.
	var ms: float = _k("module_scale")
	var top := 4.8
	var wm: Mesh = load(_k("wall"))
	if wm != null:
		top = wm.get_aabb().end.y * ms
	var roof_mesh: Mesh = load(_kit["roof"])
	var roof_mat: Material = load(_kit.get("roof_material", _k("material")))
	for t in layout.tiles:
		var mi := MeshInstance3D.new()
		mi.mesh = roof_mesh
		mi.material_override = roof_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(t.x * TILE, top, t.y * TILE)
		mi.scale = Vector3(ms, ms, ms)
		add_child(mi)
		var region: int = layout.tiles[t]
		if not _roofs.has(region):
			_roofs[region] = []
		_roofs[region].append(mi)
	if not _kit.has("beam"):
		return
	var beam: Mesh = load(_kit["beam"])
	if beam == null:
		return
	var bs: float = _kit["beam_scale"]
	var beam_len: float = beam.get_aabb().size.z
	var beam_y: float = top - beam.get_aabb().end.y * bs
	for r in layout.rooms():
		var rect: Rect2i = r["rect"]
		# Across the short way, one at every tile line along the long way.
		var along_x: bool = rect.size.x >= rect.size.y
		var lines: int = rect.size.x if along_x else rect.size.y
		var span: float = (rect.size.y if along_x else rect.size.x) * TILE
		for i in range(1, lines):
			var mi := MeshInstance3D.new()
			mi.mesh = beam
			mi.material_override = load(_k("material"))
			# Under a sun from above, a beam a tile apart stripes the whole floor with shadow.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if along_x:
				mi.position = Vector3((rect.position.x + i) * TILE, beam_y, rect.position.y * TILE)
				mi.rotation_degrees = Vector3.ZERO
			else:
				mi.position = Vector3(rect.position.x * TILE, beam_y, (rect.position.y + i) * TILE)
				mi.rotation_degrees = Vector3(0, 90, 0)
			# The beam's length is its own z; stretched to reach wall to wall.
			mi.scale = Vector3(bs, bs, span / beam_len)
			add_child(mi)
			_occluders.append(mi)


func _build_torches() -> void:
	## A torch on every few wall modules round each room, on the inside face, pointing out into it.
	var doorways := {}
	for d in layout.doors:
		doorways[LayoutScript.edge_key(d["a"], d["b"])] = true
	var ts: float = _kit["torch_scale"]
	var half_wall: float = 0.0
	var wm: Mesh = load(_k("wall"))
	if wm != null:
		half_wall = wm.get_aabb().end.z * float(_k("module_scale"))
	var count := 0
	for t in layout.tiles:
		var region: Dictionary = layout.regions[layout.tiles[t]]
		if region["kind"] != "room":
			continue
		for dir in DIRS:
			var n: Vector2i = t + dir
			if layout.tiles.has(n) and layout.tiles[n] == layout.tiles[t]:
				continue
			if doorways.has(LayoutScript.edge_key(t, n)):
				continue
			count += 1
			if count % TORCH_EVERY != 0:
				continue
			# The middle of the tile's edge, stood off the wall by its own half-thickness.
			var inward := Vector3(-dir.x, 0.0, -dir.y)
			var mid := Vector3((t.x + 0.5) * TILE, 0.0, (t.y + 0.5) * TILE) - inward * (TILE * 0.5 - half_wall)
			_place_prop(_kit["torch"], mid.x, mid.z, _yaw_facing(inward), false, _kit["torch_y"], false,
				ts / SCALE)
