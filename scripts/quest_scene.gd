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
const HERO_SCENE := preload("res://scenes/characters/hero.tscn")

## Where the party goes when the quest ends. The town screen replaces this in Phase 1; the
## bootstrap screen standing in for it already does the one thing that matters here, which is
## to show what the party came back with.
const TOWN_SCENE := "res://scenes/bootstrap.tscn"

## Placeholders, and marked as such: what a quest PAYS is a property of the quest, and in
## Phase 4 it comes off QuestDef (reward_gold, difficulty tier) rather than being counted in
## bodies. Until a quest is a thing that can be described, the only measure of how it went
## that this scene actually has is how many enemies are down.
const XP_PER_KILL := 20
const GOLD_PER_KILL := 15

## The bodies standing in for GameState.party, in the same order. Written at hydration and
## read back at capture, so the pairing between a hero and their data is never guessed from a
## name.
var _party_views: Array = []

## A quest ends once. The Town button, a victory and a defeat can all arrive at
## finish_quest, and two of them arriving together must not pay the party twice.
var _finished := false


func _ready() -> void:
	var authored := _authored_heroes()
	if GameState.has_party():
		_party_views = _spawn_party(authored)
	else:
		_party_views = authored
		_seed_party(authored)
	GameState.current_quest = {"scene": scene_file_path}


# --- Hydration -------------------------------------------------------------

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


func _spawn_party(authored: Array) -> Array:
	## Build one body per party member, and retire the authored ones.
	##
	## The authored heroes are kept only for their POSITIONS — a hand-placed body is the old
	## scenario's idea of where the party comes in, and standing the real party on those
	## squares keeps the test scenario playable. Phase 4's generator will hand over real
	## spawn points instead.
	var marks: Array = []
	for node in authored:
		marks.append(node.position)
	for node in authored:
		_retire(node)

	var views: Array = []
	for i in range(GameState.party.size()):
		var at: Vector3 = marks[i] if i < marks.size() else _spare_mark(marks, i)
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


func _spare_mark(marks: Array, index: int) -> Vector3:
	## A square for a party member the old scenario has no hand-placed body for — a hireling,
	## once Phase 5 arrives. Stepped along x from the last mark, which is flat ground in this
	## room; a generated quest will supply its own points and never come here.
	var base: Vector3 = marks[-1] if not marks.is_empty() else Vector3.ZERO
	return base + Vector3(2.0 * (index - marks.size() + 1), 0.0, 0.0)


# --- Capture ---------------------------------------------------------------

func finish_quest(outcome: String = "retreat") -> void:
	## The end of a run, by whatever route: cleared, wiped out, or walked out of.
	##
	## The ONE place a quest writes itself back into the party, which is what makes everything
	## that happened down here durable. Phase 1 gives victory and defeat their own signal out
	## of the combat layer and puts a results screen between here and town; both will come
	## through this function.
	if _finished:
		return
	_finished = true

	var kills := _enemies_slain()
	for i in range(_party_views.size()):
		var view: Node = _party_views[i]
		if i >= GameState.party.size() or not is_instance_valid(view):
			continue
		GameState.party[i].capture_from(view)

	var xp := kills * XP_PER_KILL
	var coin := kills * GOLD_PER_KILL
	GameState.award_xp(xp)
	GameState.add_gold(coin)
	GameState.last_result = {
		"outcome": outcome,
		"kills": kills,
		"xp": xp,
		"gold": coin,
	}
	GameState.current_quest = {}
	print("[Quest] %s — %d slain, +%d xp, +%d gold" % [outcome, kills, xp, coin])
	get_tree().change_scene_to_file(TOWN_SCENE)


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
