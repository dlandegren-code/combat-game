@tool
extends Node3D
class_name Door
## A hinged door standing in a doorway: swings open and shut, and blocks the way while it is
## shut.
##
## Built in code by room_builder.gd rather than saved as a scene, for the same reason the walls
## and props are — the doorway's position is derived from DOOR_X0 and the module size, and a
## door placed by hand in quest_scene.tscn would silently drift the moment either changed.
##
## --- What a door is, to the rest of the game ---
##
## Two things, and it stops being either the moment it opens:
##   * a member of the "obstacles" group, which is what Combatant._is_obstacle_at reads to
##     refuse a move ONTO the doorway square;
##   * a StaticBody3D on LAYER_OBSTACLE, which is what _step_blocked_by_wall rays hit, and so
##     is what refuses a move THROUGH the doorway — plus line of sight and diagonal cuts.
## Both are dropped when it opens and restored when it shuts, so an open door is as good as no
## door to pathing, shooting and spellcasting alike.
##
## --- Why the door is not where the hole in the art is ---
##
## The environment is built from 4-unit Synty modules; the game is played on 2-unit squares.
## A doorway module is therefore two squares wide while the hole in it is about one square
## wide, centred on the LINE between the two — so the visible gap belongs to neither square.
##
## Rather than pretend otherwise, a door carries both positions. The node itself stands on the
## square it seals, because that is the one the rules care about and it keeps _is_obstacle_at
## right by construction; the leaf hangs at `leaf_offset_x` from there, over the hole in the
## art. The gap between the two is about half a square, and it is the reason a character walks
## through a doorway looking slightly off-centre in it. Closing that properly means aligning
## the wall run to the play grid, which is level work, not door work.
##
## It is also in "interactables", which is the whole of the contract the Open/Close action
## knows about — see interact_ability.gd. Anything else answering can_interact / interact /
## interact_verb works with that action without either side being told about the other.

const PropSfx := preload("res://scripts/fx/prop_sfx.gd")

## Emitted after a toggle, once the swing has been ordered (not when it finishes).
signal toggled(open: bool)

## Degrees the leaf swings through. Negative carries it into the north room; flip the sign to
## have it open back into the chamber instead. Past 90 on purpose — a door stopped exactly
## square to the wall reads as a wall, and the extra ten degrees is what says "open".
const OPEN_ANGLE_DEG := -100.0
## Seconds for the swing. Long enough to be a heavy wooden door rather than a saloon flap.
const SWING_TIME := 0.5

## The play grid's square size — Combatant.GRID_SIZE. Not imported from there because a door
## is scenery and must not depend on the combatant class; a mismatch would show up the first
## time anyone walked through a shut door, which is a loud enough failure.
const CELL := 2.0

## Height of the collider that blocks the doorway, in world units. The leaf mesh is about two
## units tall, but the box has to reach the ~1.6-high movement and LOS rays with room to spare
## or a closed door would be shot straight over.
const BLOCK_HEIGHT := 2.6
## How thick the closed door is to a ray. The mesh is a couple of centimetres of plank; that is
## too thin to reliably catch a ray crossing it at a shallow angle.
const BLOCK_DEPTH := 0.5

const LAYER_OBSTACLE := 4          # matches Combatant.LAYER_OBSTACLE
const LAYER_INTERACT := 16         # matches Combatant.LAYER_INTERACT

## Least thickness of the pointer hit box around the leaf, in world units. The leaf mesh is a
## plank a couple of centimetres thick, which is a thin thing to ask a player to put a mouse on
## when the camera happens to be looking down its edge.
const PICK_DEPTH := 0.4

var is_open := false

## A locked door is a wall that answers back: still a legal thing to click, still refuses.
##
## Kept as plain state with no key or lockpick behind it yet, because the thing it is for right
## now is the level designer's — a door the party cannot simply shut in the goblins' faces, or
## one the goblins cannot simply open in theirs. Whoever adds keys unlocks it from there.
var locked := false

## Set by build() before the node enters the tree; _ready() turns them into geometry.
var _mesh_path := ""
var _material_path := ""
var _mesh_scale := 1.0
## Where the leaf hangs relative to the square this door seals. See the header.
var _leaf_offset_x := 0.0

var _hinge: Node3D
var _leaf: MeshInstance3D
var _body: StaticBody3D
var _picker: StaticBody3D
var _tween: Tween


static func build(parent: Node, seal_at: Vector3, leaf_offset_x: float, yaw_deg: float,
		mesh_path: String, material_path: String, mesh_scale: float,
		start_locked: bool = false) -> Door:
	## Stand a door sealing the square at `seal_at`, facing along `yaw_deg`, and return it.
	##
	## `seal_at` is the centre of the grid square the shut door closes off, in the parent's
	## space. `leaf_offset_x` slides the visible leaf from there to the hole in the art — see
	## the header for why those are not the same place.
	var d := Door.new()
	d.name = "Door"
	d._mesh_path = mesh_path
	d._material_path = material_path
	d._mesh_scale = mesh_scale
	d._leaf_offset_x = leaf_offset_x
	d.locked = start_locked
	d.position = seal_at
	d.rotation_degrees = Vector3(0, yaw_deg, 0)
	parent.add_child(d)
	return d


func _ready() -> void:
	add_to_group("interactables")
	_build_leaf()
	_build_picker()
	_build_blocker()
	_apply_blocking()


# --- The contract the Open/Close action uses -------------------------------

func can_interact(_actor) -> bool:
	## A door is always worth walking up to and trying, locked or not — refusing here would
	## make a locked door indistinguishable from a bare wall to whoever is clicking, and the
	## click would fall through to a move order. It says no in interact() instead, out loud.
	return true


func interact_verb() -> String:
	if locked:
		return "Locked"
	return "Close" if is_open else "Open"


func interact(_actor) -> void:
	if locked:
		PropSfx.door_locked(get_parent(), global_position + Vector3(0, 1.0, 0))
		return
	set_open(not is_open)


func interact_cursor_hint(_actor) -> String:
	## A door has no lockpick path — nobody has cut a key for one either — so it is open-or-not.
	return "shut" if locked else ""


func blocks_openably() -> bool:
	## True when this is in the way NOW but need not be: shut, and not locked.
	##
	## The question pathfinding asks. A shut door is a step that costs a turn instead of being
	## impossible, which is what lets an AI route through one; a LOCKED door is simply a wall,
	## and routing at it would have goblins queue up to rattle a handle all fight.
	return not is_open and not locked


# --- Opening and shutting --------------------------------------------------

func set_open(open: bool, animate: bool = true) -> void:
	if open == is_open:
		return
	is_open = open
	# Blocking changes NOW, not when the swing finishes. A door is open the moment you have
	# decided to open it, as far as the turn you spent on it is concerned; making the rules
	# wait half a second for an animation would mean a unit could not walk through a door it
	# had just opened, which is a rule nobody would guess.
	_apply_blocking()
	PropSfx.door(get_parent(), global_position + Vector3(0, 1.0, 0), open)
	var target: float = OPEN_ANGLE_DEG if open else 0.0
	if not animate or _hinge == null:
		if _hinge:
			_hinge.rotation_degrees.y = target
		toggled.emit(open)
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_hinge, "rotation_degrees:y", target, SWING_TIME)
	toggled.emit(open)


func _apply_blocking() -> void:
	if is_open:
		remove_from_group("obstacles")
	elif not is_in_group("obstacles"):
		add_to_group("obstacles")
	if _body:
		# Disabled rather than removed, so shutting the door does not have to rebuild it. The
		# call is deferred because a physics body may not change state mid-collision-step.
		_body.set_deferred("collision_layer", 0 if is_open else LAYER_OBSTACLE)


# --- Construction ----------------------------------------------------------

func _build_leaf() -> void:
	## A pivot at the hinge edge with the leaf hanging off it, so rotating the pivot about Y
	## swings the door the way a door swings rather than spinning it about its middle.
	var mesh: Mesh = load(_mesh_path)
	if mesh == null:
		push_warning("Door mesh missing: " + _mesh_path)
		return
	var width: float = mesh.get_aabb().size.x * _mesh_scale

	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	# Half a leaf to one side of the opening's centre: closed, the leaf then spans the opening
	# exactly, and the hinge sits against the jamb where the hinges of a real door would be.
	_hinge.position = Vector3(_leaf_offset_x - width * 0.5, 0.0, 0.0)
	add_child(_hinge)

	var mi := MeshInstance3D.new()
	mi.name = "Leaf"
	mi.mesh = mesh
	if _material_path != "":
		mi.material_override = load(_material_path)
	mi.scale = Vector3(_mesh_scale, _mesh_scale, _mesh_scale)
	_hinge.add_child(mi)
	_leaf = mi


func _build_picker() -> void:
	## A hit box shaped like the leaf, on the pointer-only layer, so a click LANDS ON THE DOOR.
	##
	## The alternative — and what this replaces — was clicking the floor square the door seals.
	## For a doorway that square is a poor stand-in for the door: it is on the far side of the
	## wall, half a square off from the hole in the art (see the header), and while the door is
	## shut it is a square nobody may walk on. So the only way to open the door was to click a
	## piece of floor inside the next room that looks like it has nothing to do with the door,
	## and the door itself — the obvious thing to click — did nothing at all.
	##
	## Hung off the hinge rather than the door, so it swings with the leaf and an open door is
	## clickable where it now stands. On LAYER_INTERACT alone: this is a target for the mouse
	## and must never be one for a step, an arrow or a sight line — _build_blocker owns that,
	## and it is what gets switched off when the door opens. This stays on either way, because
	## a door you cannot shut again is worse than one you cannot open.
	if _leaf == null or _leaf.mesh == null:
		return
	var aabb := _leaf.mesh.get_aabb()
	_picker = StaticBody3D.new()
	_picker.name = "Picker"
	_picker.collision_layer = LAYER_INTERACT
	_picker.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		aabb.size.x * _mesh_scale,
		aabb.size.y * _mesh_scale,
		maxf(aabb.size.z * _mesh_scale, PICK_DEPTH))
	cs.shape = box
	cs.position = aabb.get_center() * _mesh_scale
	_picker.add_child(cs)
	_hinge.add_child(_picker)


func _build_blocker() -> void:
	## The collider stays put on the sealed square whichever way the leaf is facing: it is
	## switched off when the door is open, so it never has to follow the swing. A collider
	## parented to the hinge would sweep through the doorway as the door moved and catch rays
	## sideways.
	##
	## A full CELL wide, NOT the width of the leaf. _step_blocked_by_wall casts its ray down
	## the middle of the square being entered, so a collider sized to the art — about half a
	## square, and off-centre at that — is missed by the very ray it exists to stop. The door
	## seals a square; the box is that square.
	_body = StaticBody3D.new()
	_body.name = "Blocker"
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL, BLOCK_HEIGHT, BLOCK_DEPTH)
	cs.shape = box
	cs.position = Vector3(0, BLOCK_HEIGHT * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)
