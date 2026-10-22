extends Node3D
## One quest, start to finish. This is the battlefield that used to BE the game; it is now
## one screen among several, and it owns the boundary between the party that persists
## (GameState, as CharacterData) and the Combatant nodes that stand in for them down here.
##
## Two jobs, one on each side of a run:
##
##   in    hydrate — every member of GameState.party becomes a body in this scene
##   out   capture — what happened to those bodies is written back into the party
##
## Nothing else in the scene knows GameState exists. The combat manager, the abilities, the
## inventory UI and the enemies all go on working with nodes exactly as they did.
##
## While there is no character creation screen yet (Phase 1), the first run through has
## nothing to hydrate FROM — so it leaves the hand-placed heroes of the old test scenario
## exactly where they are and reads them out into real characters instead. Every run after
## that spawns the party from data and retires the authored bodies. See _seed_party.

const CharacterDataScript := preload("res://scripts/character_data.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const HERO_SCENE := preload("res://scenes/characters/hero.tscn")

## The body every generated enemy is made from: a bare enemy with no model, no stats and an
## empty pack. Dressed from an EnemyTemplate (_dress) before it enters the tree.
const ENEMY_BASE := preload("res://scenes/enemies/enemy_base.tscn")
const RosterScript := preload("res://scripts/enemy_roster.gd")

## Where the party goes when the quest ends: the results screen, which reports what happened
## and then sends them on to town.
const RESULTS_SCENE := "res://scenes/results_screen.tscn"

## What a body is worth. This is the pay for FIGHTING, and it is all a trip through the gate
## on the party's own account ever earns; the pay for finishing a JOB comes off the contract
## the party took off the board (QuestDef.reward_gold / reward_xp) and is added in
## finish_quest. Two rates rather than one because they answer different questions — a quest
## abandoned halfway should still pay for the goblins, and a quest cleared should pay for more
## than the goblins.
const XP_PER_KILL := 20
const GOLD_PER_KILL := 15

## The bodies standing in for GameState.party, in the same order. Written at hydration and
## read back at capture, so the pairing between a hero and their data is never guessed from a
## name.
var _party_views: Array = []

## A quest ends once. The Town button, a victory and a defeat can all arrive at
## finish_quest, and two of them arriving together must not pay the party twice.
var _finished := false

## Set when the last enemy falls. The quest is not OVER at that point — there is a chest
## through the north door and loot on the floor — so this is the difference between "you may
## leave whenever you like" and "you have won", and it is what the Town button reads to decide
## which of those the player is doing.
var _field_held := false

## What each party member was carrying when they walked in, by item name. Diffed at the end to
## work out what they found, which is the one thing a results screen can say that the party
## sheet cannot.
var _gear_on_arrival: Array = []


func _ready() -> void:
	# The dungeon is already built: DungeonRoom is a child, and children are ready before their
	# parent. So the spawn points it worked out are there to be read.
	var marks := _entrance_marks()
	if not marks.is_empty():
		_retire_authored_scenery()
	var authored := _authored_heroes()
	if GameState.has_party():
		_party_views = _spawn_party(authored, marks)
	else:
		_party_views = authored
		_seed_party(authored)
		_move_to_marks(authored, marks)
	_spawn_enemies()
	_gear_on_arrival = _carried_names()
	_watch_the_fight()


func _watch_the_fight() -> void:
	## Listen for the combat layer deciding the quest one way or the other.
	##
	## Connected from here rather than wired in the scene because the manager is a child and
	## this is its parent: a signal connection made in the editor would have to be re-made by
	## hand in every quest scene that ever exists, and Phase 4 generates them.
	var cm := get_node_or_null("CombatManager")
	if cm == null:
		return
	if cm.has_signal("fight_won"):
		cm.fight_won.connect(_on_fight_won)
	if cm.has_signal("party_wiped"):
		cm.party_wiped.connect(_on_party_wiped)


func _on_fight_won() -> void:
	## The room is theirs. Nothing ends here on purpose — see _field_held.
	_field_held = true


func _on_party_wiped() -> void:
	## Nobody left to give an order to, so there is nothing to decide and no reason to make the
	## player click anything: straight to the results, where the run is reported as lost.
	finish_quest("defeat")


# --- Hydration -------------------------------------------------------------

func _entrance_marks() -> Array:
	## Where the party comes in: the generated dungeon's entrance, when there is one.
	var room := get_node_or_null("DungeonRoom")
	if room != null and room.has_method("party_spawns"):
		return room.party_spawns().duplicate()
	return []


func _move_to_marks(bodies: Array, marks: Array) -> void:
	## Stand the authored heroes in the entrance on the seeding run. Their hand-placed squares
	## were the old chamber's, and the chamber is not there any more.
	for i in range(mini(bodies.size(), marks.size())):
		var node: Node3D = bodies[i]
		node.position = marks[i]
		if "target_position" in node:
			node.target_position = marks[i]


func _spawn_enemies() -> void:
	## One body for every enemy the dungeon's layout placed, told which room it belongs to.
	##
	## Before CombatManager boots (deferred) so they are dealt into the order like anything
	## else, and positioned before entering the tree so an enemy's idle "home" is where it
	## actually stands (Enemy._pre_setup reads it in _ready).
	var room := get_node_or_null("DungeonRoom")
	if room == null or not room.has_method("enemy_spawns"):
		return
	var spawned: Array = []
	var per_name := {}
	for e in room.enemy_spawns():
		var template = RosterScript.find(String(e["kind"]))
		if template == null:
			push_warning("QuestScene: no enemy template '%s'" % e["kind"])
			continue
		var node := _dress(template)
		node.position = e["at"]
		node.home_room = int(e["room"])
		node.name = "%s%d" % [String(template.id).to_pascal_case(), spawned.size() + 1]
		add_child(node)
		if template.display_name != "":
			node.character_name = template.display_name
		spawned.append(node)
		per_name[node.character_name] = int(per_name.get(node.character_name, 0)) + 1
	# Number the rank and file so the initiative order can tell them apart — after the fact,
	# because the name comes off the stats resource in _ready. A lone boss keeps his own.
	var numbered := {}
	for node in spawned:
		var base: String = node.character_name
		if int(per_name[base]) > 1:
			numbered[base] = int(numbered.get(base, 0)) + 1
			node.character_name = "%s %d" % [base, numbered[base]]


func _dress(template) -> Node:
	## A bare enemy, made into what `template` describes. Everything here has to be in place
	## BEFORE the body enters the tree: Combatant._ready derives hit points from the stat block,
	## builds the weapon sockets off the model's skeleton, and the inventory equips its starting
	## items in its own _ready — all of which run inside add_child.
	var node := ENEMY_BASE.instantiate()
	node.stats = template.stats
	node.enemy_type = template.ai
	node.voice = template.voice
	node.body_scale = template.size
	node.tint = template.tint
	var model: Node3D = template.model_scene.instantiate()
	model.name = "CharacterModel"
	model.position = CharacterDataScript.MODEL_OFFSET
	for prop in template.model_props:
		model.set(prop, template.model_props[prop])
	node.add_child(model)
	var inv := node.get_node("Inventory")
	for i in range(mini(template.gear.size(), 4)):
		inv.set("starting_item_%d" % (i + 1), template.gear[i])
	return node


const ColumnScript := preload("res://scripts/column_obstacle.gd")
const GroundItemScript := preload("res://scripts/ground_item.gd")


func _retire_authored_scenery() -> void:
	## Take out what the old hand-built battlefield still has in the scene file: its four
	## enemies, its eight pillars and the shield on its floor. They stood in the old chamber, and
	## in a generated dungeon those squares are as likely to be solid rock as not. The dungeon
	## brings its own (RoomBuilder, _spawn_enemies).
	##
	## Done here rather than by deleting them from quest_scene.tscn because the scene could not
	## be edited safely while it was open in the editor; once they are deleted there, this finds
	## nothing to do. The CombatManager's own pickups are spawned later (deferred), so they are
	## not caught by the ground-item test.
	for child in get_children():
		var script = child.get_script()
		var is_enemy: bool = child is CharacterBody3D and child.get("is_player_controlled") == false
		if is_enemy or script == ColumnScript or script == GroundItemScript:
			_retire(child)


func _authored_heroes() -> Array:
	## The party the test scenario was built with: hand-placed, player-controlled bodies, in
	## scene order. That order is also the party order, which makes their positions the
	## party's spawn marks — see _spawn_party.
	var out: Array = []
	for child in get_children():
		if child is CharacterBody3D and child.get("is_player_controlled") == true:
			out.append(child)
	return out


func _seed_party(authored: Array) -> void:
	## Turn the authored heroes into characters, once, and then leave them be.
	##
	## This is the bridge off the single-scene design. Those three bodies are the only record
	## of what a starting hero is made of — attributes as scene exports, gear as .tres on an
	## Inventory node — and that knowledge would have died with the scene. So the first quest
	## reads it out into the party rather than throwing it away, and the run itself plays
	## exactly as it always did, because nothing in the scene is touched.
	##
	## Phase 1's creation screen makes characters the other way round, from a class and a
	## name, at which point this path stops being reached at all.
	if authored.is_empty():
		push_warning("QuestScene: no party to run this quest with, and none to seed one from.")
		return
	for node in authored:
		GameState.add_member(CharacterDataScript.from_combatant(node))
	print("[Quest] Party seeded from the authored battlefield: %s" % _view_names())


func _spawn_party(authored: Array, entrance: Array = []) -> Array:
	## Build one body per party member, and retire the authored ones.
	##
	## The squares come from the dungeon's entrance (`entrance`, from the generated layout).
	## Without one — a scene with no generated room — the authored heroes' positions stand in,
	## the old scenario's idea of where the party comes in.
	var marks: Array = entrance.duplicate()
	if marks.is_empty():
		for node in authored:
			marks.append(node.position)
	for node in authored:
		_retire(node)

	# Where the party is standing so far, so two hirelings cannot be handed the same square.
	# Filled as we go rather than computed up front, because each body placed is a square the
	# next search has to avoid — and the bodies are not in the tree yet to be found by group.
	var placed: Array = []
	var views: Array = []
	for i in range(GameState.party.size()):
		var at: Vector3 = marks[i] if i < marks.size() else _spare_mark(marks, placed)
		placed.append(at)
		views.append(_spawn_member(GameState.party[i], at, i))
	print("[Quest] Party hydrated from GameState: %s" % _view_names_of(views))
	return views


func _spawn_member(data, at: Vector3, index: int) -> Node:
	var node := HERO_SCENE.instantiate()
	# The body BEFORE the tree. Combatant._ready builds the weapon and helmet sockets off the
	# skeleton, scales the model and starts the idle animation, all from the CharacterModel
	# child — a model added after that runs would be a mannequin with no hands.
	var model := (load(data.model_scene_path()) as PackedScene).instantiate()
	model.name = "CharacterModel"
	model.position = CharacterDataScript.MODEL_OFFSET
	# Before the tree as well, because CharacterSkin reads these in its own _ready: an archer
	# whose quiver is switched on afterwards never gets one built.
	for prop in data.model_props():
		model.set(prop, data.model_props()[prop])
	node.add_child(model)
	# Same reason: the stat block has to be in place before _ready derives hit points from it.
	data.apply_to(node)
	node.name = "Hero%d" % (index + 1)
	node.position = at
	add_child(node)
	# add_child runs the whole _ready chain, so from here the body is live and the rest of the
	# character — gear, and the wounds they walked in with — can be poured into it.
	data.restore_into(node)
	return node


func _retire(node: Node) -> void:
	## Take an authored hero out of the scene before anything notices it was ever there.
	##
	## Out of the tree, not merely queued for deletion: queue_free does not take effect until
	## the end of the frame, and CombatManager boots before that — a body still in the
	## "combatants" group would be dealt into the initiative order and handed turns it can
	## never take.
	node.remove_from_group("combatants")
	remove_child(node)
	node.queue_free()


## How far out from the party's own marks a spare square is looked for, in grid squares. Four
## is the whole entry room and then some; a hireling who cannot be placed within four squares
## of the party is a hireling in a scene with no room to stand in.
const SPARE_SEARCH_RINGS := 4


func _spare_mark(marks: Array, taken: Array) -> Vector3:
	## A square for a party member the authored scenario has no hand-placed body for — which,
	## now that the camp exists, means a hireling.
	##
	## This used to step along +x from the last mark and hope. That was fine while the party
	## was always the authored three and this function was never called; the moment a fourth
	## body could be hired it became a way to stand somebody inside a wall, because +x from the
	## last mark is not floor in every room and certainly will not be in a generated one.
	##
	## So it SEARCHES: outward from the party's own marks, in rings, taking the first square
	## that has floor under it and nobody on it. The floor plan is asked for rather than
	## assumed (DungeonRoom.is_floor_at — the same authority Combatant._is_in_arena uses), so
	## this keeps working when Phase 4's generator starts building the room.
	var origin: Vector3 = marks[-1] if not marks.is_empty() else Vector3.ZERO
	var step := 2.0   # Combatant.GRID_SIZE; play squares sit on odd coordinates.
	for ring in range(1, SPARE_SEARCH_RINGS + 1):
		# Nearest ring first, and within a ring the squares beside the party before the ones
		# behind it, so a hireling falls in with the line rather than appearing in a corner.
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var square := origin + Vector3(dx * step, 0.0, dz * step)
				if _square_is_free(square, taken):
					return square
	# Nowhere in four rings. Standing them on the last mark is wrong, but it is a body in the
	# room rather than a crash, and it is loud enough in the log to be found.
	push_warning("QuestScene: no free square for a party member near %s" % origin)
	return origin


func _square_is_free(square: Vector3, taken: Array) -> bool:
	var room := get_node_or_null("DungeonRoom")
	if room != null and room.has_method("is_floor_at"):
		if not room.is_floor_at(square.x, square.z):
			return false
	for other in taken:
		if Vector3(other).distance_to(square) < 1.0:
			return false
	# Anything already standing there — the authored bodies are gone by now, but the enemies
	# are not, and a hireling must not arrive on top of a goblin.
	for c in get_tree().get_nodes_in_group("combatants"):
		if is_instance_valid(c) and Vector3(c.position).distance_to(square) < 1.0:
			return false
	return true


# --- Capture ---------------------------------------------------------------

func finish_quest(outcome: String = "retreat") -> void:
	## The end of a run, by whatever route: cleared, wiped out, or walked out of. Settle up and
	## send the party to the results screen.
	##
	## Every route out — the Town button, a victory, a wipe — arrives here, and `_finished`
	## makes sure two of them arriving together do not pay the party twice.
	if _finished:
		return
	settle(outcome)
	get_tree().change_scene_to_file(RESULTS_SCENE)


func settle(outcome: String = "retreat") -> Dictionary:
	## Everything the end of a run DOES, with nothing about where the player goes next.
	##
	## Split out of finish_quest for the same reason capture_party was, and after the same
	## thing went wrong twice: the round-trip test cannot call finish_quest, because it ends by
	## changing scene and that would free the test along with the quest. So the test had its
	## own idea of what leaving a dungeon means, and that copy quietly stopped matching — first
	## when skills began earning their own experience, and again the moment a quest could be
	## worth a contract. There is one definition, and the test calls it.
	##
	## Returns what was written to GameState.last_result, so a caller can check the settlement
	## without reading it back out of global state.
	_finished = true

	var kills := _enemies_slain()
	capture_party()

	var xp := kills * XP_PER_KILL
	var coin := kills * GOLD_PER_KILL

	# The contract, on top of the bodies — and only for finishing the job. A party that walks
	# back out of a dungeon it was paid to clear keeps what it killed and what it carried, and
	# gets nothing for the work it did not do. There is no contract at all when the party went
	# through the gate on its own account, which is what the gate is for.
	var contract = GameState.current_quest
	var paid := contract != null and outcome == "victory"
	if paid:
		xp += contract.reward_xp
		coin += contract.reward_gold

	GameState.award_xp(xp)
	GameState.add_gold(coin)
	GameState.last_result = {
		"outcome": outcome,
		"kills": kills,
		"xp": xp,
		"gold": coin,
		"loot": _loot_found(),
		"fallen": _fallen_names(),
		"skills": _skills_learned(),
		# What the results screen needs to say "and the contract paid": the title, and whether
		# it was actually earned. Flattened to plain values rather than handed the QuestDef,
		# because last_result is read after the quest scene is gone.
		"quest": contract.title if contract != null else "",
		"quest_paid": paid,
		"quest_gold": contract.reward_gold if paid else 0,
		"quest_xp": contract.reward_xp if paid else 0,
	}
	GameState.abandon_quest()
	# A cleared job comes off the board, and a new one goes up in its place. One walked out of
	# — or lost — stays pinned up, to be tried again or thrown away (QuestBoard's Discard).
	# Taking it down only on CLEARING is also what stops a contract being paid twice.
	if paid:
		GameState.complete_offer(contract)
	# And new faces at the mercenary camp, for the same reason: the sell-swords who were
	# sitting round that fire took other work while the party was underground.
	GameState.reroll_camp()
	print("[Quest] %s — %d slain, +%d xp, +%d gold" % [outcome, kills, xp, coin])
	var learned := _skills_learned()
	if not learned.is_empty():
		print("[Quest] skills learned: %s" % "; ".join(learned))
	return GameState.last_result


func capture_party() -> void:
	## Write every body back into the character it stands for.
	##
	## Its own function because it is the one thing hydration has to be symmetrical with, and
	## reading the two side by side is how that stays true. Everything ELSE that the end of a
	## run does now lives in settle(), which calls this first.
	for i in range(_party_views.size()):
		var view: Node = _party_views[i]
		if i >= GameState.party.size() or not is_instance_valid(view):
			continue
		var member = GameState.party[i]
		member.capture_from(view)
		# What each skill learned down here, and a fresh allowance of general xp to assign now
		# that a quest is behind them — see Progression on the two currencies.
		member.take_quest_skill_xp(view.skill_xp_earned)
		member.refresh_general_allowance()


func field_is_held() -> bool:
	## Whether the fighting is done. Read by the system menu, which offers to leave a won
	## quest in different words from an abandoned one.
	return _field_held


func _carried_names() -> Array:
	## Every item each party member holds, as a flat list of names per member.
	var out: Array = []
	for view in _party_views:
		var names: Array = []
		if is_instance_valid(view) and view.inventory != null:
			for item in view.inventory.items:
				if item != null:
					names.append(item.item_name)
		out.append(names)
	return out


func _loot_found() -> Array:
	## What the party is carrying that they did not walk in with.
	##
	## A diff of names rather than a tally kept as items are picked up: loot arrives through
	## the pickup ability, corpse looting and chests, and a results screen is not a good enough
	## reason to make three systems report to a fourth.
	var found: Array = []
	var now := _carried_names()
	for i in range(now.size()):
		var before: Array = _gear_on_arrival[i].duplicate() if i < _gear_on_arrival.size() else []
		for carried in now[i]:
			# Removed as it is matched, so two potions carried out with one carried in counts
			# as one found rather than none.
			var at: int = before.find(carried)
			if at >= 0:
				before.remove_at(at)
			else:
				found.append(carried)
	return found


func _skills_learned() -> Array:
	## What each hero's skills picked up down here, as readable lines for the results screen.
	## Read off the bodies rather than the characters so it reports THIS quest rather than
	## everything banked so far.
	var lines: Array = []
	for i in range(_party_views.size()):
		var view: Node = _party_views[i]
		if not is_instance_valid(view) or view.skill_xp_earned.is_empty():
			continue
		var parts: Array = []
		for field in view.skill_xp_earned:
			parts.append("%s +%d" % [ProgressionScript.label_for(String(field)),
				int(view.skill_xp_earned[field])])
		lines.append("%s: %s" % [view.character_name, ", ".join(parts)])
	return lines


func _fallen_names() -> Array:
	var fallen: Array = []
	for view in _party_views:
		if is_instance_valid(view) and not view.is_alive:
			fallen.append(view.character_name)
	return fallen


func _enemies_slain() -> int:
	## Corpses stay in the room and in the group (see Combatant._die) — they are lootable —
	## so the dead can simply be counted at the end rather than tallied as they fall.
	var dead := 0
	for c in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(c) and not c.is_alive:
			dead += 1
	return dead


func party_is_down() -> bool:
	## Nobody left standing. Phase 1 turns this into the defeat half of the quest-end signal.
	for view in _party_views:
		if is_instance_valid(view) and view.is_alive:
			return false
	return true


func _view_names() -> String:
	return _view_names_of(_party_views)


func _view_names_of(views: Array) -> String:
	var names: Array = []
	for view in views:
		if is_instance_valid(view):
			names.append(view.character_name)
	return ", ".join(names)
