@tool
extends Node3D
class_name LootContainer
## A chest, a cask or a crate: something you stand next to, work once, and take what is inside.
##
## Named LootContainer rather than Container because Godot already has a Container, and a UI
## base class quietly shadowing a dungeon prop is a bad afternoon.
##
## Answers the same three questions door.gd does — can_interact / interact_verb / interact —
## so it needs no new action and no change to interact_ability.gd. That was the point of
## writing the Open/Close action against a contract instead of against doors.
##
## --- What searching is ---
##
## Opening one does not empty it. The contents are rolled the first time it is opened and then
## HELD, and a character takes what they want an item at a time through the loot window (see
## loot_ui.gd); whatever is left is still there the next time anybody looks. So a chest can be
## cracked on turn one, half-emptied, and come back to later — which is also the shape a corpse
## will want when corpse-looting arrives.
##
## Nothing is rolled until somebody actually opens the thing, so a room full of barrels costs
## nothing until it is searched.

const PropSfx := preload("res://scripts/fx/prop_sfx.gd")

## Emitted when this container has been opened and is ready to be looted from. The loot window
## listens; nothing in the game rules does.
signal opened(container, actor)
## Emitted whenever the contents change, so an open window can repaint itself.
signal contents_changed

const LAYER_OBSTACLE := 4          # matches Combatant.LAYER_OBSTACLE
## Minimum collider height, in world units. A barrel is waist-high and a chest lower still;
## both have to reach the ~1.6-high movement and sight rays or units walk through them.
const BLOCK_HEIGHT := 2.2
## Seconds for a chest lid to come up.
const LID_TIME := 0.4
## Degrees the lid tilts back. Flip the sign if a lid ever hinges the other way round.
const LID_ANGLE_DEG := -75.0

## World Y of the arena floor's SURFACE — measured off it with a downward ray, not assumed.
##
## It is not zero, and that is the trap. RoomBuilder places everything at FLOOR_Y = 0, which is
## a tenth of a unit UNDER the floor you can see; on the throne, one-and-a-half units tall,
## nobody notices, but the chest mesh is 0.27 tall and a tenth of that is a third of the chest
## buried in the flagstones. So a container settles itself rather than trusting the y it is
## handed. (GroundItem.DROP_Y is this plus a little clearance, for the same reason.)
const FLOOR_SURFACE_Y := 0.1

# --- What this container is ------------------------------------------------

## "Open" for a chest, "Search" for anything without a lid — a barrel or a crate. Only ever
## shown to the player.
var open_verb := "Search"
## Shut and refusing. See _try_unlock for the two ways past it.
var locked := false
## The key_id an ItemResource must carry to open this. Empty means no key was ever cut for it
## and a lockpick is the only way in.
var key_id := ""
## What a lockpick roll has to beat. See _try_unlock.
var lock_difficulty := 8
## The loot TABLE: resource paths to draw from, and how many draws. Paths rather than loaded
## resources so a container costs nothing until somebody opens it.
var loot: Array = []
var loot_rolls := 1

## What is actually inside, once rolled. Array[ItemResource].
var contents: Array = []
## Whether the table has been rolled into `contents` yet. Distinct from `contents.is_empty()`,
## which is also true of a container that has been emptied by hand.
var _rolled := false

## Lid up or lid down. Toggles freely — see interact().
var is_open := false

var _prefab_path := ""
var _mesh_scale := 1.0
## The pack's prefab root, a MeshInstance3D carrying the body mesh.
var _visual: MeshInstance3D
## The prefab's lid node, or null for a barrel. Already sitting on its hinge — see _build_visual.
var _lid_hinge: Node3D
var _rng := RandomNumberGenerator.new()


func configure(at: Vector3, yaw_deg: float, prefab_path: String, mesh_scale: float) -> void:
	## Set a freshly-constructed container up, BEFORE adding it to the tree — _ready() turns
	## these into geometry.
	##
	## `prefab_path` is one of the pack's own prop prefabs, NOT a raw mesh, and that is the
	## whole trick to getting a chest lid right. The lid mesh is authored with its origin ON ITS
	## HINGE, so on its own it renders sticking out the front of the chest; the prefab is where
	## the artist recorded the transform that puts that hinge at the chest's top-back corner.
	## Reading it from there beats copying the numbers out, and it is right for every chest in
	## the pack rather than for the one somebody measured.
	##
	## An instance method rather than the static factory door.gd uses, and deliberately: a
	## static one would have to write `LootContainer.new()`, which needs the class_name global
	## to be registered, which needs the editor to have rescanned since this file was written.
	## The caller already holds the script (see RoomBuilder), so it can just call new() on it.
	## action_toolbar.gd avoids the same trap for the same reason.
	name = "LootContainer"
	_prefab_path = prefab_path
	_mesh_scale = mesh_scale
	position = at
	rotation_degrees = Vector3(0, yaw_deg, 0)


func _ready() -> void:
	add_to_group("interactables")
	# Its own group as well, so anything that wants the containers specifically can ask for
	# them without type-testing against a class_name that may not be registered yet.
	add_to_group("containers")
	# Solid, and it holds its square: you cannot walk through a chest, and a unit standing on
	# one would have nowhere to stand next to it from.
	add_to_group("obstacles")
	# Seeded off where it stands, so a given barrel gives the same thing every run of the same
	# level rather than rerolling each time the scene is reloaded mid-testing.
	_rng.seed = int(position.x * 1000.0) + int(position.z)
	_build_visual()
	_build_blocker()
	_rest_on_floor()


func _rest_on_floor() -> void:
	## Drop the container until the bottom of its body meets the floor, whatever the y it was
	## configured with. Derived from the mesh so a container whose origin is NOT at its base
	## still lands right — the two in the dungeon happen to have theirs at the base, which is
	## exactly the sort of thing that stops being true the day somebody adds a third.
	var aabb := _body_aabb()
	position.y = FLOOR_SURFACE_Y - aabb.position.y * _mesh_scale


# --- The contract ----------------------------------------------------------

func can_interact(_actor) -> bool:
	## Always worth trying, exactly as with a door: an empty barrel and a locked chest both say
	## so themselves rather than pretending to be scenery.
	return true


func interact_verb() -> String:
	if locked:
		return "Locked"
	if is_open:
		# A lid can always go back down. A barrel has nothing to put back.
		return "Close" if _lid_hinge else "Empty"
	if _rolled and contents.is_empty():
		# Known to be empty. Say so rather than promising a search that finds nothing.
		return "Empty" if _lid_hinge == null else "Open"
	return open_verb


func interact(actor) -> void:
	if locked and not _try_unlock(actor):
		return
	# Anything with a lid opens and shuts as often as you like; what it does NOT do is refill.
	# A barrel has no lid, so once it is empty there is nothing left to do to it.
	if is_open:
		if _lid_hinge == null:
			_say(actor, "Empty")
			return
		_set_lid(false)
		is_open = false
		_say(actor, "Closed")
		return
	_open(actor)


func interact_cursor_hint(actor) -> String:
	## What the mouse should say about this container for THIS character: "" to just open it,
	## "pick" if it is locked but they have a way in, "shut" if it is locked and they have not.
	##
	## Answered here rather than worked out by the ability, because the two ways past a lock are
	## this class's business (see _try_unlock) and a pointer that disagreed with what the click
	## then did would be worse than no pointer at all.
	if not locked or _actor_has_key(actor):
		return ""
	var skill: int = actor.lockpick_skill if (actor and "lockpick_skill" in actor) else 0
	return "pick" if skill > 0 else "shut"


func wants_loot_window() -> bool:
	## Whether a look inside is worth a window right now. Asked by whoever just worked this
	## thing; a locked or empty one says no and gets only its floating text.
	return is_open and not locked and not contents.is_empty()


func blocks_openably() -> bool:
	## Never. A container is furniture: opening it does not clear the square it stands on, so
	## pathfinding must not treat it as something it can work its way through the way it does a
	## door.
	return false


# --- Getting in ------------------------------------------------------------

func _try_unlock(actor) -> bool:
	## Two ways past a lock, tried in that order: the key that was cut for it, or a blade and
	## some patience. Returns whether the lock gave way; a failure has already said why by the
	## time it returns false.
	##
	## The key is NOT consumed. A key that vanishes into the lock it opens is a key the player
	## then has to wonder about, and this one opens a box in a dungeon, not a plot.
	if _actor_has_key(actor):
		locked = false
		PropSfx.lock_open(get_parent(), _sound_at())
		_say(actor, "Unlocked!")
		return true

	var skill: int = actor.lockpick_skill if "lockpick_skill" in actor else 0
	if skill <= 0:
		# Untrained is not a bad roll, it is not knowing how. No dice, so no false hope.
		PropSfx.door_locked(get_parent(), _sound_at())
		_say(actor, "Locked!")
		return false

	# The same 1-5 die every other contested roll in the game uses, so picking a lock reads
	# like a parry rather than like its own little subsystem.
	var die: int = _rng.randi_range(1, 5)
	# Trying a lock is how lockpicking is learned, and a lock that springs on a 5 or sticks on
	# a 1 teaches more than the ones in between (Progression).
	if actor != null and actor.has_method("award_skill_use"):
		actor.award_skill_use("lockpick_skill", die == 5 or die == 1)
	var roll: int = skill + die
	if roll < lock_difficulty:
		PropSfx.door_locked(get_parent(), _sound_at())
		_say(actor, "Lock holds! (%d vs %d)" % [roll, lock_difficulty])
		return false
	locked = false
	PropSfx.lock_open(get_parent(), _sound_at())
	_say(actor, "Picked it! (%d vs %d)" % [roll, lock_difficulty])
	return true


func _open(actor) -> void:
	is_open = true
	if _lid_hinge:
		_set_lid(true)
	else:
		PropSfx.rummage(get_parent(), _sound_at())

	# Rolled on first open and never again: shutting a chest and opening it does not restock it.
	if not _rolled:
		_rolled = true
		contents = _roll_contents()
	if contents.is_empty():
		_say(actor, "Nothing inside")
		return
	# The window goes up from Player._do_interact, once this returns — see wants_loot_window.
	opened.emit(self, actor)


func take(index: int, actor) -> bool:
	## Move one item from here into `actor`'s bag. False when it would not fit, in which case
	## nothing moves and nothing is charged — the caller prices the take, not this.
	if index < 0 or index >= contents.size() or actor == null:
		return false
	var inv = actor.inventory if "inventory" in actor else null
	if inv == null or not inv.has_method("add_item"):
		return false
	var item: ItemResource = contents[index]
	if not inv.add_item(item):
		_say(actor, "Bag is full!")
		return false
	contents.remove_at(index)
	_say(actor, item.item_name)
	contents_changed.emit()
	return true


func _roll_contents() -> Array:
	## Draw the table. Duplicated per instance for the reason CombatManager duplicates its
	## spawns: durability and breakage are per-item, and mutating the cached .tres poisons
	## every later copy.
	var out: Array = []
	if loot.is_empty() or loot_rolls <= 0:
		return out
	for i in range(loot_rolls):
		var path: String = loot[_rng.randi() % loot.size()]
		var template: ItemResource = load(path)
		if template == null:
			push_warning("Loot missing: " + path)
			continue
		out.append(template.make_instance())
	return out


func _set_lid(open: bool) -> void:
	## Swing the lid, and make the noise that goes with it.
	##
	## Negative about X lifts the front edge: the lid extends along +Z from a hinge at its own
	## origin, so a negative X rotation carries that +Z end up toward +Y.
	PropSfx.chest_open(get_parent(), _sound_at()) if open 		else PropSfx.door(get_parent(), _sound_at(), false)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(
		_lid_hinge, "rotation_degrees:x", LID_ANGLE_DEG if open else 0.0, LID_TIME)


func _say(actor, text: String) -> void:
	if actor and actor.has_method("_show_action_text"):
		actor._show_action_text(text)


func _actor_has_key(actor) -> bool:
	if key_id == "" or actor == null:
		return false
	var inv = actor.inventory if "inventory" in actor else null
	return inv != null and inv.has_method("has_key") and inv.has_key(key_id)


func _sound_at() -> Vector3:
	return global_position + Vector3(0, 0.6, 0)


# --- Construction ----------------------------------------------------------

func _build_visual() -> void:
	## Drop the pack's prefab in whole — body, lid and the lid's authored hinge transform — and
	## then take away the parts that are ours to decide.
	var scene: PackedScene = load(_prefab_path)
	if scene == null:
		push_warning("Container prefab missing: " + _prefab_path)
		return
	_visual = scene.instantiate() as MeshInstance3D
	if _visual == null:
		push_warning("Container prefab is not a MeshInstance3D: " + _prefab_path)
		return
	_visual.name = "Visual"
	_visual.scale = Vector3(_mesh_scale, _mesh_scale, _mesh_scale)
	add_child(_visual)
	_strip_prefab_colliders(_visual)
	_lid_hinge = _find_lid(_visual)


func _strip_prefab_colliders(node: Node) -> void:
	## The pack ships every prop with a convex MeshCollider on the DEFAULT layer, which is
	## LAYER_GROUND here — leave them in and the player's click-to-move ray starts hitting
	## chests and treating them as floor. This container builds its own on the obstacle layer
	## (see _build_blocker), so the prefab's are not wanted at all.
	for child in node.get_children():
		if child is StaticBody3D:
			child.queue_free()
			continue
		_strip_prefab_colliders(child)


func _find_lid(node: Node) -> Node3D:
	## The prefab's lid node, by name. A barrel has none, and gets rummaged through instead.
	for child in node.get_children():
		if child is Node3D and child.name.ends_with("_Lid"):
			return child
	return null


func _body_aabb() -> AABB:
	## The BODY's bounds, excluding the lid — the lid moves, and a container's footing and its
	## collider must not change when it opens.
	if _visual and _visual.mesh:
		return _visual.mesh.get_aabb()
	return AABB()


func _build_blocker() -> void:
	## Sized off the body, floored, and given a minimum height for the same reason the arena's
	## short props are (see RoomBuilder._place_prop): a waist-high box the sight rays fly over
	## is not an obstacle, it is a decal.
	var aabb := _body_aabb()
	if aabb.size == Vector3.ZERO:
		return
	var h: float = max(aabb.size.y * _mesh_scale, BLOCK_HEIGHT)
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = LAYER_OBSTACLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * _mesh_scale, h, aabb.size.z * _mesh_scale)
	cs.shape = box
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	add_child(body)
