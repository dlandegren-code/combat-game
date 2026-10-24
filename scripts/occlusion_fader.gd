extends Node3D
## Keeps the party in view: lifts the roof off wherever they are, and ghosts any wall, door or
## beam that stands between the camera and somebody who matters.
##
## Visual only. Nothing here touches a collider — a ghosted wall still blocks a step, a sight
## line and an arrow exactly as a solid one does; you can just see past it. (Clicks never hit
## walls anyway: the move ray only asks the ground layer.)
##
## Uses GeometryInstance3D.transparency, so no material is duplicated or swapped — the shared
## atlas material stays shared — and fades rather than pops, so a wall that comes and goes as
## the camera orbits does not flicker.
##
## RoomBuilder fills `occluders` (walls, door leaves, beams) and `roofs` (region id -> roof
## pieces) as it builds, then adds this node.

## How see-through an occluding wall goes. Not all the way: the outline of the room is still
## worth seeing.
const GHOST := 0.78
## How fast things fade, in transparency per second.
const FADE_RATE := 4.0
## Seconds between re-deciding what should be faded; the fading itself runs every frame.
const RETHINK := 0.1
## A focus point's height off its origin — chest height, so a wall is "in the way" when it hides
## a character's body, not merely their feet.
const FOCUS_LIFT := 0.4
## Roof also lifts within this many world units of a focus point, so standing in a doorway does
## not leave the next room's roof hanging over your head.
const ROOF_RADIUS := 6.0

var occluders: Array = []       ## GeometryInstance3D
var roofs: Dictionary = {}      ## region id -> Array of GeometryInstance3D
var room: Node = null           ## the RoomBuilder, for region_at

var _boxes: Array = []          ## world AABB per occluder, parallel to `occluders`
var _target := {}               ## GeometryInstance3D -> transparency it is heading for
var _roof_boxes := {}           ## GeometryInstance3D (roof) -> world AABB
var _clock := 0.0


func _ready() -> void:
	# The builder's nodes are all in the tree by now, so world transforms mean something.
	for g in occluders:
		_boxes.append(_world_aabb(g))
	for id in roofs:
		for g in roofs[id]:
			_roof_boxes[g] = _world_aabb(g)
	_rethink()


static func _world_aabb(g: GeometryInstance3D) -> AABB:
	return g.global_transform * g.get_aabb()


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = RETHINK
		_rethink()
	var step := FADE_RATE * delta
	for g in _target:
		if not is_instance_valid(g):
			continue
		var want: float = _target[g]
		var now: float = g.transparency
		if absf(now - want) < 0.001:
			continue
		g.transparency = move_toward(now, want, step)
		# Fully gone is not drawn at all, rather than drawn invisible in the alpha pass.
		g.visible = g.transparency < 0.995


func _focus_points() -> Array:
	## Whom the camera must be able to see: the party, whoever's turn it is, and wherever the
	## camera itself is looking.
	var out: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		if c is Node3D and c.get("is_player_controlled") == true and c.get("is_alive") != false:
			out.append((c as Node3D).global_position + Vector3(0, FOCUS_LIFT, 0))
	var cm := get_tree().current_scene.get_node_or_null("CombatManager") if get_tree().current_scene else null
	var active = cm.get("current_combatant") if cm else null
	if active is Node3D and is_instance_valid(active):
		out.append((active as Node3D).global_position + Vector3(0, FOCUS_LIFT, 0))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.get("pivot") is Vector3:
		out.append(cam.get("pivot"))
	return out


func _rethink() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var focus := _focus_points()
	# Walls, doors, beams: ghosted while they cut a line from the eye to anybody in `focus`.
	for i in range(occluders.size()):
		var g = occluders[i]
		if not is_instance_valid(g):
			continue
		var box: AABB = _boxes[i]
		var hit := false
		for p in focus:
			if box.intersects_segment(eye, p):
				hit = true
				break
		_target[g] = GHOST if hit else 0.0
	# Roof: off over every region somebody in `focus` is in or near, and anywhere it is in the
	# way of the eye; on everywhere else, which is what keeps the rest of the hall a roofed hall.
	var open := {}
	if room != null:
		for p in focus:
			open[room.region_at(p.x, p.z)] = true
	for id in roofs:
		for g in roofs[id]:
			if not is_instance_valid(g):
				continue
			var off: bool = open.has(id)
			if not off:
				var box: AABB = _roof_boxes[g]
				var c := box.get_center()
				for p in focus:
					if Vector2(c.x - p.x, c.z - p.z).length() < ROOF_RADIUS or box.intersects_segment(eye, p):
						off = true
						break
			_target[g] = 1.0 if off else 0.0
