extends Node3D
## Dev tool: which way a held item's parts point in the world in the idle pose, and which of the
## 24 right-angle orientations would turn a given part a given way while keeping its long axis
## where it is. Writes .summer/local/grip_probe.txt and quits.
##
## Each case: item, the item-space axis that must keep pointing the way it does now (the handle,
## the bow's length), the item-space axis to aim, and the world direction to aim it at.

const HERO_SCENE := preload("res://scenes/characters/hero.tscn")
const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")
const CASES := [
	["viking_axe", Vector3.UP, Vector3.BACK, Vector3.DOWN],
	["dane_axe", Vector3.UP, Vector3.BACK, Vector3.DOWN],
	["warhammer", Vector3.UP, Vector3.BACK, Vector3.DOWN],
	["boss_cleaver", Vector3.UP, Vector3.BACK, Vector3.DOWN],
	["short_bow", Vector3.UP, Vector3.FORWARD, Vector3.UP],
]


func _ready() -> void:
	var heroes: Array = []
	for i in range(CASES.size()):
		var item: ItemResource = load("res://resources/items/%s.tres" % CASES[i][0])
		var hero := HERO_SCENE.instantiate()
		var model := SIDEKICK.instantiate()
		model.name = "CharacterModel"
		model.position = Vector3(0, -1, 0)
		hero.add_child(model)
		hero.position = Vector3(i * 2.0, 0, 0)
		hero.get_node("Inventory").set("starting_item_1", item)
		add_child(hero)
		hero.set_process(false)
		hero.set_physics_process(false)
		model.play("idle")
		heroes.append([hero, item])
	await get_tree().create_timer(0.8).timeout
	var out: Array = []
	var orients := _orientations()
	for i in range(CASES.size()):
		var hero: Node3D = heroes[i][0]
		var item: ItemResource = heroes[i][1]
		var node := _worn_node(hero, item)
		if node == null:
			out.append("%s: worn model not found" % CASES[i][0])
			continue
		var now := Basis.from_euler(item.worn_rotation * PI / 180.0)
		var socket: Basis = node.global_transform.basis.orthonormalized() * now.inverse()
		var keep: Vector3 = CASES[i][1]
		var aim: Vector3 = CASES[i][2]
		var want: Vector3 = CASES[i][3]
		var keep_now: Vector3 = socket * now * keep
		out.append("%s now %s: long=%s aimed=%s" % [CASES[i][0], item.worn_rotation,
			keep_now.snapped(Vector3.ONE * 0.01), (socket * now * aim).snapped(Vector3.ONE * 0.01)])
		var best := Vector3.ZERO
		var best_score := -INF
		for b in orients:
			var long_dir: Vector3 = socket * b * keep
			if long_dir.dot(keep_now) < 0.9:
				continue
			var score: float = (socket * b * aim).dot(want)
			if score > best_score:
				best_score = score
				best = (b.get_euler() * 180.0 / PI).round()
		out.append("  best %s (aim . want = %.2f)" % [best, best_score])
	# The bow, freely: string straight up, length lying level along the way the body faces.
	var bow_hero: Node3D = heroes[CASES.size() - 1][0]
	var bow: ItemResource = heroes[CASES.size() - 1][1]
	var bnode := _worn_node(bow_hero, bow)
	if bnode != null:
		var bnow := Basis.from_euler(bow.worn_rotation * PI / 180.0)
		var bsock: Basis = bnode.global_transform.basis.orthonormalized() * bnow.inverse()
		var facing: Vector3 = (bow_hero.get_node("CharacterModel") as Node3D).global_transform.basis.z.normalized()
		var best_b := Vector3.ZERO
		var best_s := -INF
		for b in orients:
			var string_dir: Vector3 = bsock * b * Vector3.FORWARD
			var long_dir: Vector3 = bsock * b * Vector3.UP
			var score: float = string_dir.dot(Vector3.UP) + 0.5 * absf(long_dir.dot(facing))
			if score > best_s:
				best_s = score
				best_b = (b.get_euler() * 180.0 / PI).round()
		var chosen := Basis.from_euler(best_b * PI / 180.0)
		out.append("bow level, string up: %s string=%s long=%s" % [best_b,
			(bsock * chosen * Vector3.FORWARD).snapped(Vector3.ONE * 0.01),
			(bsock * chosen * Vector3.UP).snapped(Vector3.ONE * 0.01)])
	var f := FileAccess.open("res://.summer/local/grip_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()


func _orientations() -> Array:
	var out: Array = []
	for x in range(4):
		for y in range(4):
			for z in range(4):
				var b := Basis.from_euler(Vector3(x, y, z) * PI / 2.0)
				var dup := false
				for o in out:
					if (o as Basis).is_equal_approx(b):
						dup = true
						break
				if not dup:
					out.append(b)
	return out


func _worn_node(hero: Node, item: ItemResource) -> Node3D:
	## The model Combatant hung on a hand for `item`: a child of a bone socket that carries the
	## item's worn rotation and has a mesh in it.
	var want := Basis.from_euler(item.worn_rotation * PI / 180.0)
	for socket in hero.find_children("*", "BoneAttachment3D", true, false):
		for c in socket.get_children():
			if c is Node3D and (c as Node3D).basis.orthonormalized().is_equal_approx(want) 					and (c is MeshInstance3D or not c.find_children("*", "MeshInstance3D", true, false).is_empty()):
				return c
	return null
