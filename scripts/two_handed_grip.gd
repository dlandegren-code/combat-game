extends SkeletonModifier3D
## Poses both arms onto a two-handed weapon so it reads as held in two hands: right hand
## raised, left hand lowered, shaft running diagonally across the chest.
##
## The Kenney mini rig makes this cheap. Each arm is ONE bone — `arm-left` extends along +X
## from its shoulder, `arm-right` along -X, both parented to `torso` with an identity rest
## basis — so there is no elbow to solve for and aiming the bone is the whole problem. Each
## arm is rotated to point from its shoulder at a hand target, which lands the hand on a
## sphere of radius ARM_LENGTH.
##
## The weapon then hangs between the two resulting hand positions rather than off either
## hand (Combatant parents it to a torso socket for this). That is the part that makes the
## pose predictable: the shaft angle is exactly what is specified here, instead of whatever
## falls out of each item's own hand-socket offsets.
##
## It runs as a SkeletonModifier3D so it lands AFTER the AnimationPlayer has written the
## frame's pose — bone poses set from _process would simply be overwritten. Combatant turns
## it off (and hands the weapon back to the right fist) for the duration of an attack, so
## swings still animate.

## Bones this poses, and the torso they hang off.
const LEFT_ARM_BONE := "arm-left"
const RIGHT_ARM_BONE := "arm-right"
const TORSO_BONE := "torso"

## Shoulder-to-hand distance, in mesh units. Measured on the rig: an arm's own triangles
## run 0 .. 0.284 out from its shoulder along the bone axis.
const ARM_LENGTH := 0.284

## Where each hand is aimed, in TORSO-bone space: +X is the character's LEFT, +Y up,
## +Z forward. The torso front face is at z 0.129, so these sit just off the chest.
##
## They are aim points, not exact hand positions — the arm cannot stretch, so the hand ends
## up where the ray from the shoulder crosses ARM_LENGTH. Moving a target further out only
## changes the angle, never the reach.
##
## The right hand riding high and the left low is what produces the "ready to swing"
## diagonal. Raise RIGHT_HAND_TARGET.y (or drop the left) for a steeper weapon; swap the two
## y values for a left-hander's stance.
##
## The gap between the two y values sets how far apart the hands sit vertically; the gap
## between the x values sets how far the arms splay to either side. Both have been widened
## from the first pass (hands 0.339 apart, arms almost in line at 0.091 of splay).
##
## Widening x also tilts the weapon: the shaft runs through both hands, so pushing them
## apart sideways swings it off vertical — 37 degrees at these values, up from 24. That is
## the trade, and the reason to reach for y rather than x if you only want a steeper weapon.
const LEFT_HAND_TARGET := Vector3(0.16, -0.11, 0.14)
const RIGHT_HAND_TARGET := Vector3(-0.13, 0.23, 0.14)

## Extra spin of EVERY two-hander about its own shaft, in degrees. Aligning the shaft is a
## shortest-arc rotation, which says nothing about roll. Per-weapon corrections belong on the
## item instead (ItemResource.model_grip_roll) — this is only for turning the whole set.
const GRIP_ROLL_DEG := 0.0

var _left_bone := -1
var _right_bone := -1
var _left_rot := Quaternion.IDENTITY
var _right_rot := Quaternion.IDENTITY
## Weapon placement in torso-bone space, handed to Combatant via get_grip_transform().
var _grip := Transform3D.IDENTITY
var _solved := false


func _ready() -> void:
	active = false
	_solve()


func is_solved() -> bool:
	return _solved


func get_grip_transform() -> Transform3D:
	return _grip


func _solve() -> void:
	## The stance is fixed relative to the torso, so it is worked out once rather than per
	## frame; _process_modification only has to stamp the result.
	var skel := get_skeleton()
	if skel == null:
		return
	_left_bone = skel.find_bone(LEFT_ARM_BONE)
	_right_bone = skel.find_bone(RIGHT_ARM_BONE)
	if _left_bone < 0 or _right_bone < 0:
		return

	# A bone's rest origin is expressed in its PARENT's space and both arms parent to the
	# torso, so these already ARE the shoulder positions in the space the targets use.
	var left_shoulder: Vector3 = skel.get_bone_rest(_left_bone).origin
	var right_shoulder: Vector3 = skel.get_bone_rest(_right_bone).origin

	var left_dir := (LEFT_HAND_TARGET - left_shoulder).normalized()
	var right_dir := (RIGHT_HAND_TARGET - right_shoulder).normalized()
	if left_dir.length_squared() < 0.5 or right_dir.length_squared() < 0.5:
		return  # target sat on top of a shoulder; no direction to aim along

	# Rest basis is identity, so a bone's pose rotation IS its rotation in torso space, and
	# the arm's rest direction is just its outward axis.
	_left_rot = Quaternion(Vector3.RIGHT, left_dir)
	_right_rot = Quaternion(Vector3.LEFT, right_dir)

	_grip = _shaft_transform(
		left_shoulder + left_dir * ARM_LENGTH,
		right_shoulder + right_dir * ARM_LENGTH)
	_solved = true


func _shaft_transform(left_hand: Vector3, right_hand: Vector3) -> Transform3D:
	## Weapon placement in torso space: sat at the midpoint of the two hands with its +Y
	## running from the low left hand up to the raised right one. Whatever the weapon's own
	## long axis is, place_weapon() turns it onto +Y first.
	var shaft := right_hand - left_hand
	if shaft.length() < 0.001:
		return Transform3D.IDENTITY
	shaft = shaft.normalized()
	return Transform3D(Basis(Quaternion(Vector3.UP, shaft)), (left_hand + right_hand) * 0.5)


func place_weapon(model: Node3D, roll_deg: float = 0.0) -> void:
	## Re-seat a weapon that was built for a hand socket into the two-handed grip. The
	## incoming node still carries the item's hand offset and rotation, which are tuned for a
	## fist and meaningless here, so its transform is replaced outright — only the uniform
	## scale that sized the model is carried over.
	##
	## `roll_deg` is the item's own correction (ItemResource.model_grip_roll): aligning the
	## shaft says nothing about which way the weapon FACES around it, and that depends on how
	## each model was authored. The bows need a half turn here; the staff and axes need none.
	if not _solved or model == null:
		return
	var model_scale := model.scale
	model.transform = Transform3D.IDENTITY
	# Turn the model's own longest dimension into the shaft, so a bow modelled along Z is
	# handled as readily as a staff modelled along Y — no per-weapon-type special casing.
	var align := Basis(Quaternion(_longest_axis(model), Vector3.UP))
	# Roll goes AFTER the alignment and BEFORE the grip, so it spins the weapon about its own
	# shaft rather than about whatever direction the grip happens to point.
	var roll := Basis(Vector3.UP, deg_to_rad(GRIP_ROLL_DEG + roll_deg))
	model.transform = Transform3D((_grip.basis * roll * align).scaled(model_scale), _grip.origin)


# Godot 4.6 drives the stack through _process_modification_with_delta; _process_modification
# is the pre-4.4 spelling. Both are implemented so the grip survives an engine update either
# way — the write is idempotent, so it costs nothing if a version ever calls both.

func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	## Runs inside the skeleton update, after the AnimationMixer has written this frame's
	## pose — so this overwrites the animated arms rather than being overwritten by them.
	if not _solved:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	skel.set_bone_pose_rotation(_left_bone, _left_rot)
	skel.set_bone_pose_rotation(_right_bone, _right_rot)


func _longest_axis(model: Node3D) -> Vector3:
	## The model's long dimension as a unit axis in its own local space, measured from the
	## meshes rather than assumed. Called with the model at identity, so the node's own scale
	## does not enter into it (and a uniform scale could not change the answer anyway).
	var boxes: Array = []
	_collect_mesh_aabbs(model, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return Vector3.UP
	var merged: AABB = boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	var s := merged.size
	if s.y >= s.x and s.y >= s.z:
		return Vector3.UP
	return Vector3.RIGHT if s.x >= s.z else Vector3.BACK


func _collect_mesh_aabbs(node: Node, xform: Transform3D, out: Array) -> void:
	var n3d := node as Node3D
	var here: Transform3D = xform * n3d.transform if n3d != null else xform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(here * mi.mesh.get_aabb())
	for c in node.get_children():
		_collect_mesh_aabbs(c, here, out)
