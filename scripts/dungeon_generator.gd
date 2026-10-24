@tool
extends RefCounted
## Makes a dungeon out of a quest's seed and tier: rooms, the corridors and doors between them,
## and what is standing in each one. Pure data in, pure data out — see DungeonLayout.
##
## THE SHAPE: rooms joined by short corridors, grown outward from an entrance. Each new room is
## hung off a free wall of one already placed, through a doorway, optionally down a corridor of
## up to CORRIDOR_MAX tiles, and the attempt is thrown away if it would overlap anything. So the
## dungeon is a tree — every room reachable, exactly one way in to each — and the boss room is
## hung off whichever room is deepest, so the hardest fight is the one furthest from the gate.
##
## Room-and-corridor rather than a cave or a BSP split because this is a TACTICAL game: a room
## is an encounter, its doorway is the choke point the fight is about, and the alarm is scoped
## to it (CombatManager._alert_room). A level made of encounters wants to be made of rooms.
##
## DETERMINISM: everything comes off one generator seeded once from the quest's seed, so the
## order of the draws is part of the contract, exactly as in QuestDef.generate. New rolls go at
## the end of a pass, never in the middle of one.

const LayoutScript := preload("res://scripts/dungeon_layout.gd")
const RosterScript := preload("res://scripts/enemy_roster.gd")

const TILE := 4.0
const GRID := 2.0

## Rooms in a dungeon, entrance and boss room included: ROOMS_BASE + tier. Four at tier 1 — the
## old authored dungeon's chamber and side room, plus a way in and one more fight — up to eight
## at tier 5.
const ROOMS_BASE := 3

## Room sizes, in tiles a side. Three tiles is six squares across, the smallest room a fight can
## move in; the boss room is bigger because it holds the throne, the chest and his guard.
const ROOM_MIN := 3
const ROOM_MAX := 5
const BOSS_MIN := 4
const BOSS_MAX := 6
const ENTRANCE_SIZE := 3

const CORRIDOR_MAX := 3
const PLACE_TRIES := 80

## Who can be in a dungeon, and what each costs out of QuestDef.enemy_budget, is the
## templates' business (resources/enemies/, listed in EnemyRoster). A plain goblin costs 2 —
## the unit the budget was written in.

## What lies loose on the floor. The same list the authored battlefield scattered by hand.
const PICKUP_TABLE := [
	"res://resources/items/health_potion.tres",
	"res://resources/items/health_potion.tres",
	"res://resources/items/arrow_bundle.tres",
	"res://resources/items/arrow_bundle.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/wooden_shield.tres",
	"res://resources/items/warhammer.tres",
	"res://resources/items/longbow.tres",
	"res://resources/items/quiver.tres",
	"res://resources/items/knight_helmet.tres",
]
const PICKUPS_BASE := 3

## Chance a plain fight room has a crate in it. The stores room always has its casks and crates.
const FIGHT_CRATE_CHANCE := 0.35
## How often a raiders fight room gets a weapon rack (a stores room always does).
const RACK_CHANCE := 0.6
## How often a raiders fight room gets a rune stone.
const RUNESTONE_CHANCE := 0.5

## The four ways out of a room, as tile steps: north (+z), east, south, west.
const DIRS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]


# --- The roster ------------------------------------------------------------

static func roster(quest_seed: int, tier: int, budget: int, theme: String = "dungeon") -> Array:
	## Who is down there, as EnemyTemplate ids, boss first. Its own generator rather than a draw
	## off the layout's, so a quest board can say how many enemies a job has without building
	## the floor plan to find out — and so changing the floor plan never changes the count.
	##
	## The boss is bought first, out of the theme's bosses that fit the tier; then the rest of
	## the budget goes on the theme's rank and file, by weight, among those it can still afford.
	var rng := RandomNumberGenerator.new()
	rng.seed = quest_seed ^ 0x51ED27
	var out: Array = []
	var left := budget
	var boss = RosterScript.pick(rng, RosterScript.candidates(theme, tier, true))
	if boss != null:
		out.append(boss.id)
		left -= boss.cost
	var pool: Array = RosterScript.candidates(theme, tier, false)
	while true:
		var affordable: Array = []
		for t in pool:
			if t.cost <= left:
				affordable.append(t)
		if affordable.is_empty():
			break
		var t = RosterScript.pick(rng, affordable)
		out.append(t.id)
		left -= t.cost
	return out


# --- The whole dungeon -----------------------------------------------------

static func generate(quest_seed: int, tier: int, enemy_budget: int,
		theme: String = "dungeon") -> RefCounted:
	var layout = LayoutScript.new()
	layout.quest_seed = quest_seed
	layout.tier = tier
	layout.theme = theme
	var rng := RandomNumberGenerator.new()
	rng.seed = quest_seed ^ 0x2545F491

	_add_region(layout, "room", Rect2i(-1, -1, ENTRANCE_SIZE, ENTRANCE_SIZE), "entrance", 0, -1,
		Vector2i.ZERO)
	var room_count := ROOMS_BASE + clampi(tier, 1, 5)
	for i in range(room_count - 2):
		_grow(layout, rng, false)
	if not _grow(layout, rng, true):
		# Nowhere to hang a big room off the deep end. Make the deepest room the boss's rather
		# than ship a dungeon with no boss room — small for a throne room, but a legal one.
		var deepest: Dictionary = _by_depth(layout)[0]
		if deepest["role"] != "entrance":
			deepest["role"] = "boss"

	_assign_roles(layout, rng)

	var taken := {}
	var near_door := _door_zone(layout)
	for room in layout.rooms():
		_furnish(layout, rng, room, taken, near_door)
	if theme == "raiders":
		# A mead hall has long tables down its rooms. Off a generator of its own, so the main
		# one draws exactly what it always drew and no other theme's dungeons change.
		var hall_rng := RandomNumberGenerator.new()
		hall_rng.seed = quest_seed ^ 0x6D656164
		for room in layout.rooms():
			_place_tables(layout, hall_rng, room, taken, near_door)
		# A weapon rack against the wall of every stores room and most fight rooms.
		for room in layout.rooms():
			var role := String(room["role"])
			if role == "stores" or (role == "fight" and hall_rng.randf() < RACK_CHANCE):
				_place_along_wall(layout, hall_rng, room, "rack", 1, taken, near_door)
		# Carved gods round the jarl's hall and one to meet you at the door; a rune stone in
		# about half the fight rooms.
		for room in layout.rooms():
			match String(room["role"]):
				"boss":
					_place_along_wall(layout, hall_rng, room, "statue", 2, taken, near_door)
				"entrance":
					_place_along_wall(layout, hall_rng, room, "statue", 1, taken, near_door)
				"fight":
					if hall_rng.randf() < RUNESTONE_CHANCE:
						_place_along_wall(layout, hall_rng, room, "runestone", 1, taken, near_door)
	_place_enemies(layout, rng, roster(quest_seed, tier, enemy_budget, theme), taken, near_door)
	_place_party(layout, taken, near_door)
	_place_pickups(layout, rng, taken, near_door)
	for room in layout.rooms():
		room["corners"] = _free_corners(room["rect"], taken, near_door)
		room["patrol"] = _patrol_ring(room["rect"])
	return layout


static func _add_region(layout, kind: String, rect: Rect2i, role: String, depth: int,
		parent: int, entry_dir: Vector2i) -> int:
	var id: int = layout.regions.size()
	layout.regions.append({
		"id": id, "kind": kind, "rect": rect, "role": role, "depth": depth, "parent": parent,
		# Which way the party was walking when they came in through this room's door — the
		# room's back wall is the one that way, which is where a throne goes.
		"entry_dir": entry_dir,
	})
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			layout.tiles[Vector2i(x, y)] = id
	return id


static func _by_depth(layout) -> Array:
	var rooms: Array = layout.rooms()
	rooms.sort_custom(func(a, b):
		if a["depth"] != b["depth"]:
			return a["depth"] > b["depth"]
		return a["id"] < b["id"])
	return rooms


static func _grow(layout, rng: RandomNumberGenerator, boss: bool) -> bool:
	## Hang one more room off the dungeon. False when PLACE_TRIES attempts all collided.
	var rooms: Array = layout.rooms()
	var deep: Array = _by_depth(layout)
	for attempt in range(PLACE_TRIES):
		var parent: Dictionary
		if boss:
			# Deepest first, then the next deepest, and so on — a few tries each.
			parent = deep[mini(attempt / 16, deep.size() - 1)]
		elif rng.randf() < 0.5:
			parent = rooms[-1]
		else:
			parent = rooms[rng.randi() % rooms.size()]
		var lo := BOSS_MIN if boss else ROOM_MIN
		var hi := BOSS_MAX if boss else ROOM_MAX
		var w := rng.randi_range(lo, hi)
		var h := rng.randi_range(lo, hi)
		var dir: Vector2i = DIRS[rng.randi() % DIRS.size()]
		var run := rng.randi_range(0, CORRIDOR_MAX)
		var pr: Rect2i = parent["rect"]

		# The tile inside the parent that the way out leaves from.
		var p: Vector2i
		if dir.x == 0:
			p = Vector2i(pr.position.x + _inner(rng, pr.size.x),
				pr.end.y - 1 if dir.y > 0 else pr.position.y)
		else:
			p = Vector2i(pr.end.x - 1 if dir.x > 0 else pr.position.x,
				pr.position.y + _inner(rng, pr.size.y))

		var corridor: Array = []
		for k in range(1, run + 1):
			corridor.append(p + dir * k)
		var e: Vector2i = p + dir * (run + 1)   # the new room's first tile

		var rect: Rect2i
		if dir == Vector2i(0, 1):
			rect = Rect2i(e.x - _inner(rng, w), e.y, w, h)
		elif dir == Vector2i(0, -1):
			rect = Rect2i(e.x - _inner(rng, w), e.y - h + 1, w, h)
		elif dir == Vector2i(1, 0):
			rect = Rect2i(e.x, e.y - _inner(rng, h), w, h)
		else:
			rect = Rect2i(e.x - w + 1, e.y - _inner(rng, h), w, h)

		if not _is_free(layout, rect, corridor):
			continue

		if run > 0:
			var c0: Vector2i = corridor[0]
			var c1: Vector2i = corridor[-1]
			var crect := Rect2i(Vector2i(mini(c0.x, c1.x), mini(c0.y, c1.y)),
				Vector2i(absi(c1.x - c0.x) + 1, absi(c1.y - c0.y) + 1))
			_add_region(layout, "corridor", crect, "corridor", parent["depth"], parent["id"], dir)
			# A door where the corridor leaves the room it starts from, and an open arch where it
			# arrives. One door per way in is enough to make a room a room — it is what sight and
			# sound have to get through — and two on every corridor would be a lot of clicking.
			layout.doors.append({"a": p, "b": c0, "leaf": true})
			layout.doors.append({"a": c1, "b": e, "leaf": false})
		else:
			layout.doors.append({"a": p, "b": e, "leaf": true})
		_add_region(layout, "room", rect, "boss" if boss else "fight",
			int(parent["depth"]) + 1, parent["id"], dir)
		return true
	return false


static func _inner(rng: RandomNumberGenerator, n: int) -> int:
	## An offset along a side of length n that keeps off its corners where it can.
	if n >= 3:
		return rng.randi_range(1, n - 2)
	return rng.randi_range(0, n - 1)


static func _is_free(layout, rect: Rect2i, corridor: Array) -> bool:
	for t in corridor:
		if layout.tiles.has(t):
			return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if layout.tiles.has(Vector2i(x, y)):
				return false
	return true


static func _assign_roles(layout, rng: RandomNumberGenerator) -> void:
	## One stores room, if there is a room to spare for it; everything else in the middle is a
	## plain fight.
	var middle: Array = []
	for r in layout.rooms():
		if r["role"] == "fight":
			middle.append(r)
	if not middle.is_empty():
		middle[rng.randi() % middle.size()]["role"] = "stores"


# --- Squares ---------------------------------------------------------------

static func _key(v: Vector3) -> Vector2i:
	return Vector2i(roundi(v.x), roundi(v.z))


static func _door_zone(layout) -> Dictionary:
	## Every square within one step of a doorway. Kept clear of furniture, so no room can be
	## sealed by its own casks, and of the party's arrival.
	var out := {}
	for t in layout.door_squares():
		for dz in [-GRID, 0.0, GRID]:
			for dx in [-GRID, 0.0, GRID]:
				out[_key(t + Vector3(dx, 0.0, dz))] = true
	return out


static func _wall_run(rect: Rect2i, dir: Vector2i) -> Array:
	## The squares along the inside of one wall of a room, in order along it. `dir` is the way
	## out through that wall.
	var out: Array = []
	var x0 := rect.position.x * TILE + 1.0
	var x1 := rect.end.x * TILE - 1.0
	var z0 := rect.position.y * TILE + 1.0
	var z1 := rect.end.y * TILE - 1.0
	if dir.x == 0:
		var z := z1 if dir.y > 0 else z0
		var x := x0
		while x <= x1:
			out.append(Vector3(x, 0.0, z))
			x += GRID
	else:
		var x := x1 if dir.x > 0 else x0
		var z := z0
		while z <= z1:
			out.append(Vector3(x, 0.0, z))
			z += GRID
	return out


static func _interior(rect: Rect2i) -> Array:
	## Squares a step clear of every wall.
	var out: Array = []
	for s in LayoutScript.squares_in(rect):
		if s.x > rect.position.x * TILE + 1.5 and s.x < rect.end.x * TILE - 1.5 \
				and s.z > rect.position.y * TILE + 1.5 and s.z < rect.end.y * TILE - 1.5:
			out.append(s)
	return out


static func _free(s: Vector3, taken: Dictionary, near_door: Dictionary) -> bool:
	return not taken.has(_key(s)) and not near_door.has(_key(s))


static func _take(taken: Dictionary, squares: Array) -> void:
	for s in squares:
		taken[_key(s)] = true


static func _sides_from(room: Dictionary) -> Array:
	## The four walls, back wall first: the one facing the way the party came in.
	var entry: Vector2i = room["entry_dir"]
	var out: Array = []
	if entry != Vector2i.ZERO:
		out.append(entry)
	for d in DIRS:
		if not out.has(d):
			out.append(d)
	return out


static func _normal(dir: Vector2i) -> Vector3:
	return Vector3(-dir.x, 0.0, -dir.y)


# --- Furniture -------------------------------------------------------------

static func _furnish(layout, rng: RandomNumberGenerator, room: Dictionary, taken: Dictionary,
		near_door: Dictionary) -> void:
	var rect: Rect2i = room["rect"]
	var id: int = room["id"]
	_place_columns(layout, room, taken, near_door)
	match String(room["role"]):
		"boss":
			_place_throne(layout, room, taken, near_door)
			_place_along_wall(layout, rng, room, "chest", 1, taken, near_door)
		"stores":
			_place_run(layout, room, "barrel", 3, taken, near_door)
			_place_along_wall(layout, rng, room, "crate", rng.randi_range(2, 3), taken, near_door)
		"fight":
			if rng.randf() < FIGHT_CRATE_CHANCE:
				_place_along_wall(layout, rng, room, "crate", 1, taken, near_door)


static func _place_columns(layout, room: Dictionary, taken: Dictionary,
		near_door: Dictionary) -> void:
	## Pillars in the big rooms, the way the authored chamber had them: a ring round the middle,
	## and in the biggest, the round floor and the stone vessel at its heart.
	var rect: Rect2i = room["rect"]
	if rect.size.x < 5 or rect.size.y < 5:
		return
	var c := LayoutScript.centre_of(rect)
	var offsets: Array = [Vector2(3, 3), Vector2(-3, 3), Vector2(3, -3), Vector2(-3, -3)]
	var grand := rect.size.x % 2 == 0 and rect.size.y % 2 == 0
	if grand:
		offsets = [Vector2(5, 3), Vector2(3, 5), Vector2(-3, 5), Vector2(-5, 3),
			Vector2(-5, -3), Vector2(-3, -5), Vector2(3, -5), Vector2(5, -3)]
		layout.features.append({"type": "circle", "room": room["id"], "at": c,
			"normal": Vector3.ZERO, "squares": []})
		# On the crossing in the middle: it blocks a diagonal through it but leaves the four
		# squares round it walkable, so it takes no square.
		layout.features.append({"type": "vessel", "room": room["id"], "at": c,
			"normal": Vector3.ZERO, "squares": []})
	for o in offsets:
		var s := c + Vector3(o.x, 0.0, o.y)
		if not _free(s, taken, near_door):
			continue
		layout.features.append({"type": "pillar", "room": room["id"], "at": s,
			"normal": Vector3.ZERO, "squares": [s]})
		_take(taken, [s])


static func _place_throne(layout, room: Dictionary, taken: Dictionary,
		near_door: Dictionary) -> void:
	## Two squares against the back wall, as near the middle of it as the doors allow, with a
	## banner either side.
	for dir in _sides_from(room):
		var run: Array = _wall_run(room["rect"], dir)
		var mid := (run.size() - 2) / 2
		for step in range(run.size()):
			# Out from the middle: 0, +1, -1, +2, -2 ...
			var i: int = mid + (step + 1) / 2 * (1 if step % 2 == 1 else -1)
			if i < 0 or i + 1 >= run.size():
				continue
			var a: Vector3 = run[i]
			var b: Vector3 = run[i + 1]
			# The squares in front of it too: the seat is reached from there.
			var n := _normal(dir)
			if not (_free(a, taken, near_door) and _free(b, taken, near_door)
					and _free(a + n * GRID, taken, near_door)
					and _free(b + n * GRID, taken, near_door)):
				continue
			var at := (a + b) / 2.0
			layout.features.append({"type": "throne", "room": room["id"], "at": at,
				"normal": n, "squares": [a, b]})
			_take(taken, [a, b])
			var along := (b - a).normalized()
			for side in [-1.0, 1.0]:
				layout.features.append({"type": "banner", "room": room["id"],
					"at": at + along * 3.0 * side - n * 0.7, "normal": n, "squares": []})
			return


static func _place_tables(layout, rng: RandomNumberGenerator, room: Dictionary,
		taken: Dictionary, near_door: Dictionary) -> void:
	## Long tables, two squares each, laid down the room's long way, clear of the walls and with
	## a square of floor all round so nothing gets sealed off behind one. Fight rooms only: the
	## boss's hall keeps its floor clear in front of the throne.
	##
	## A table gets a bench down each long side where the room has width for both — a 3 x 2
	## block with its ring of floor — and stands alone where it has not.
	if String(room["role"]) != "fight":
		return
	var rect: Rect2i = room["rect"]
	if rect.size.x < 3 or rect.size.y < 3:
		return
	var axis := Vector3(GRID, 0.0, 0.0) if rect.size.x >= rect.size.y else Vector3(0.0, 0.0, GRID)
	var want := 1 if mini(rect.size.x, rect.size.y) < 4 else 2
	var side := Vector3(axis.z, 0.0, axis.x)
	var spots: Array = _interior(rect)
	_shuffle(rng, spots)
	var placed := 0
	for with_benches in [true, false]:
		for a in spots:
			if placed >= want:
				return
			var b: Vector3 = a + axis
			var block: Array = [a, b]
			if with_benches:
				block += [a + side, b + side, a - side, b - side]
			var clear := true
			for sq in block:
				if not spots.has(sq):
					clear = false
					break
				for dx in [-GRID, 0.0, GRID]:
					for dz in [-GRID, 0.0, GRID]:
						if not _free(sq + Vector3(dx, 0.0, dz), taken, near_door):
							clear = false
			if not clear:
				continue
			layout.features.append({"type": "table", "room": room["id"], "at": (a + b) / 2.0,
				"normal": axis.normalized(), "squares": [a, b]})
			if with_benches:
				for k in [1.0, -1.0]:
					var pair: Array = [a + side * k, b + side * k]
					layout.features.append({"type": "bench", "room": room["id"],
						"at": (pair[0] + pair[1]) / 2.0, "normal": axis.normalized(), "squares": pair})
			_take(taken, block)
			placed += 1


static func _place_run(layout, room: Dictionary, type: String, count: int, taken: Dictionary,
		near_door: Dictionary) -> void:
	## `count` of a thing side by side along one wall, the way casks stand.
	for dir in _sides_from(room):
		var run: Array = _wall_run(room["rect"], dir)
		for i in range(1, run.size() - count):
			var ok := true
			for k in range(count):
				if not _free(run[i + k], taken, near_door):
					ok = false
					break
			if not ok:
				continue
			for k in range(count):
				layout.features.append({"type": type, "room": room["id"], "at": run[i + k],
					"normal": _normal(dir), "squares": [run[i + k]]})
				_take(taken, [run[i + k]])
			return


static func _place_along_wall(layout, rng: RandomNumberGenerator, room: Dictionary,
		type: String, count: int, taken: Dictionary, near_door: Dictionary) -> void:
	## `count` of a thing on free squares against any wall, corners excluded — those are where
	## somebody goes to lie down.
	var spots: Array = []
	for dir in DIRS:
		var run: Array = _wall_run(room["rect"], dir)
		for i in range(1, run.size() - 1):
			spots.append({"at": run[i], "normal": _normal(dir)})
	for k in range(count):
		var tries := 0
		while tries < 30 and not spots.is_empty():
			tries += 1
			var pick: Dictionary = spots[rng.randi() % spots.size()]
			if not _free(pick["at"], taken, near_door):
				continue
			layout.features.append({"type": type, "room": room["id"], "at": pick["at"],
				"normal": pick["normal"], "squares": [pick["at"]]})
			_take(taken, [pick["at"]])
			break


# --- Who and what is on the floor ------------------------------------------

static func _place_enemies(layout, rng: RandomNumberGenerator, kinds: Array, taken: Dictionary,
		near_door: Dictionary) -> void:
	## The boss in his own room, by his throne if he has one; one of his people with him if
	## there are enough to spare; everybody else spread round the fight rooms, a few to a room.
	##
	## `kinds` is a roster: template ids, boss first (see roster()).
	var boss_room: Dictionary = layout.room_with_role("boss")
	var others: Array = kinds.duplicate()
	var boss_kind := ""
	if not others.is_empty():
		var first = RosterScript.find(String(others[0]))
		if first != null and first.is_boss:
			boss_kind = String(others.pop_front())
	_shuffle(rng, others)

	if not boss_room.is_empty() and boss_kind != "":
		var spot := Vector3.INF
		for f in layout.features:
			if f["type"] == "throne" and f["room"] == boss_room["id"]:
				var s: Vector3 = f["squares"][0] + f["normal"] * GRID
				if _free(s, taken, near_door):
					spot = s
		if spot == Vector3.INF:
			spot = _random_square(rng, boss_room["rect"], taken, near_door)
		if spot != Vector3.INF:
			layout.enemies.append({"kind": boss_kind, "at": spot, "room": boss_room["id"]})
			_take(taken, [spot])
		if others.size() >= 3:
			_put(layout, rng, boss_room, others.pop_back(), taken, near_door)

	var rooms: Array = []
	for r in layout.rooms():
		if r["role"] == "fight" or r["role"] == "stores":
			rooms.append(r)
	if rooms.is_empty() and not boss_room.is_empty():
		rooms.append(boss_room)
	if rooms.is_empty():
		return
	var at := rng.randi() % rooms.size()
	while not others.is_empty():
		var placed := false
		for k in range(rooms.size()):
			var room: Dictionary = rooms[(at + k) % rooms.size()]
			if _put(layout, rng, room, others.back(), taken, near_door):
				others.pop_back()
				at = (at + k + 1) % rooms.size()
				placed = true
				break
		if not placed:
			# Every room is full. Better a smaller fight than a goblin in a wall.
			break


static func _put(layout, rng: RandomNumberGenerator, room: Dictionary, kind: String,
		taken: Dictionary, near_door: Dictionary) -> bool:
	var s := _random_square(rng, room["rect"], taken, near_door)
	if s == Vector3.INF:
		return false
	layout.enemies.append({"kind": kind, "at": s, "room": room["id"]})
	_take(taken, [s])
	return true


static func _random_square(rng: RandomNumberGenerator, rect: Rect2i, taken: Dictionary,
		near_door: Dictionary) -> Vector3:
	var pool: Array = []
	for s in _interior(rect):
		if _free(s, taken, near_door):
			pool.append(s)
	if pool.is_empty():
		return Vector3.INF
	return pool[rng.randi() % pool.size()]


static func _place_party(layout, taken: Dictionary, near_door: Dictionary) -> void:
	## The middle of the entrance, nearest first: enough squares for a full party and spares.
	var entrance: Dictionary = layout.room_with_role("entrance")
	if entrance.is_empty():
		return
	var c := LayoutScript.centre_of(entrance["rect"])
	var pool: Array = []
	for s in LayoutScript.squares_in(entrance["rect"]):
		if _free(s, taken, near_door):
			pool.append(s)
	pool.sort_custom(func(a, b):
		var da: float = a.distance_squared_to(c)
		var db: float = b.distance_squared_to(c)
		if not is_equal_approx(da, db):
			return da < db
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x)
	for i in range(mini(8, pool.size())):
		layout.party_spawns.append(pool[i])
	_take(taken, layout.party_spawns)


static func _place_pickups(layout, rng: RandomNumberGenerator, taken: Dictionary,
		near_door: Dictionary) -> void:
	var rooms: Array = []
	for r in layout.rooms():
		if r["role"] != "entrance":
			rooms.append(r)
	if rooms.is_empty():
		return
	for i in range(PICKUPS_BASE + layout.tier):
		var room: Dictionary = rooms[rng.randi() % rooms.size()]
		var s := _random_square(rng, room["rect"], taken, near_door)
		if s == Vector3.INF:
			continue
		layout.pickups.append({"path": PICKUP_TABLE[rng.randi() % PICKUP_TABLE.size()], "at": s})
		_take(taken, [s])


static func _free_corners(rect: Rect2i, taken: Dictionary, near_door: Dictionary) -> Array:
	var out: Array = []
	var xs := [rect.position.x * TILE + 1.0, rect.end.x * TILE - 1.0]
	var zs := [rect.position.y * TILE + 1.0, rect.end.y * TILE - 1.0]
	for z in zs:
		for x in xs:
			var s := Vector3(x, 0.0, z)
			if _free(s, taken, near_door):
				out.append(s)
	return out


static func _patrol_ring(rect: Rect2i) -> Array:
	## A beat a step in from the walls, corner to corner.
	var x0 := rect.position.x * TILE + 3.0
	var x1 := rect.end.x * TILE - 3.0
	var z0 := rect.position.y * TILE + 3.0
	var z1 := rect.end.y * TILE - 3.0
	return [Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1), Vector3(x0, 0.0, z0)]


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	## Array.shuffle() draws from the global generator, which would make the result depend on
	## whatever else has rolled a die this session. Fisher-Yates off our own.
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
