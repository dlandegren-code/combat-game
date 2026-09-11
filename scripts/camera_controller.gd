extends Camera3D
## Orbit camera: right-drag to orbit (full 360°), scroll to zoom, middle-drag to pan

@export var pivot: Vector3 = Vector3(0, 0.5, 0)
@export var min_distance: float = 2.0
@export var max_distance: float = 35.0
@export var orbit_speed: float = 0.005
@export var pan_speed: float = 0.02
@export var zoom_speed: float = 0.8

## Vertical angle limits (radians): stay just above the floor, below straight-down.
## Horizontal orbit is unrestricted so all sides are viewable.
@export var min_phi: float = 0.15
@export var max_phi: float = PI * 0.49

var _theta: float = PI * 0.49  ## horizontal angle
var _phi: float = 0.55         ## vertical angle
var _distance: float = 16.0

## Whether the camera re-centres on whoever is active. Exposed so it can be switched off in the
## inspector without touching code — useful because this camera is also the audio LISTENER
## (Godot uses the active Camera3D unless there is an AudioListener3D), so it is the first
## thing to rule out when positional sound starts behaving oddly.
@export var follow_active: bool = true

## How long the pivot takes to slide to a newly active character, and how far above their feet
## it settles — chest height, so a character is framed rather than their shoes.
const FOLLOW_TIME := 0.25
const FOLLOW_LIFT := 0.5

## How far the active character may be from where the camera is already looking before it
## bothers to move, in world units — about four squares.
##
## This is the important one, and not for looks. The camera is the audio listener, so a camera
## that glided on EVERY turn change meant every clip in the game started while the listener was
## in flight and at a different distance from its emitter than the last one — swings, grunts and
## footfalls all arriving at a volume that was still settling. Most turns the character is
## already comfortably in frame and there is nothing to correct, so the honest fix is not a
## faster glide but no glide at all: move only when somebody is actually out of view.
const FOLLOW_DEADZONE := 9.0

var _is_orbiting: bool = false
var _is_panning: bool = false
var _last_mouse: Vector2
var _follow_tween: Tween


func _ready() -> void:
	_apply_orbit()
	# Follow whoever is active. This matters more than it looks: the party now starts in the
	# room north of the chamber, and a camera pinned to the chamber centre would open the game
	# looking at an empty floor with the heroes off the top edge.
	#
	# Off turn_changed, which fires for BOTH modes (see CombatManager) — so this is the camera
	# moving to the selected hero while exploring and to whoever's turn it is in a fight, with
	# no notion of either mode written down here.
	await get_tree().process_frame
	var cm := get_tree().current_scene.get_node_or_null("CombatManager")
	if cm and cm.has_signal("turn_changed"):
		cm.turn_changed.connect(_on_turn_changed)
		if cm.current_combatant:
			# The first turn_changed has already fired by now — CombatManager sets up inside
			# its own _ready. Snap rather than glide: there is nothing to glide from.
			focus_on(cm.current_combatant, true)


func _on_turn_changed(who: Node) -> void:
	if not follow_active:
		return
	focus_on(who, false)


func focus_on(who: Node, snap: bool = false) -> void:
	## Bring `who` to the middle of the view, keeping the orbit angle and zoom the player set.
	##
	## Only the pivot moves, deliberately: a camera that reset its own angle every turn would
	## undo the player's framing several times a minute, which is worse than not following at
	## all.
	if who == null or not is_instance_valid(who) or not (who is Node3D):
		return
	var to: Vector3 = (who as Node3D).global_position + Vector3(0, FOLLOW_LIFT, 0)
	# Already looking near enough at them: leave the camera — and therefore the listener —
	# exactly where it is. See FOLLOW_DEADZONE. A snap ignores this: it is the opening framing
	# or a deliberate jump, not a correction.
	if not snap and pivot.distance_to(to) <= FOLLOW_DEADZONE:
		return
	if _follow_tween and _follow_tween.is_valid():
		_follow_tween.kill()
	if snap:
		pivot = to
		_apply_orbit()
		return
	_follow_tween = create_tween()
	_follow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_follow_tween.tween_method(_set_pivot, pivot, to, FOLLOW_TIME)


func _set_pivot(p: Vector3) -> void:
	## Tween target. The pivot cannot just be interpolated as a property — the camera's own
	## position is derived from it, so every step has to re-run _apply_orbit.
	pivot = p
	_apply_orbit()


func _calc_start_from_transform() -> void:
	var offset: Vector3 = global_position - pivot
	_distance = offset.length()
	_distance = clamp(_distance, min_distance, max_distance)
	if _distance < 0.01:
		_distance = 10.0
		offset = Vector3(0, 0, -10)
	_phi = acos(clamp(offset.y / _distance, -1.0, 1.0))
	_theta = atan2(offset.x, -offset.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = event.pressed
			if _is_orbiting:
				_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			if _is_panning:
				_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance -= zoom_speed
			_distance = clamp(_distance, min_distance, max_distance)
			_apply_orbit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance += zoom_speed
			_distance = clamp(_distance, min_distance, max_distance)
			_apply_orbit()
	elif event is InputEventMouseMotion:
		if _is_orbiting:
			var delta: Vector2 = event.position - _last_mouse
			_last_mouse = event.position
			_theta -= delta.x * orbit_speed  # unrestricted: orbits fully around
			_phi -= delta.y * orbit_speed
			_phi = clamp(_phi, min_phi, max_phi)
			_apply_orbit()
		elif _is_panning:
			var delta: Vector2 = event.position - _last_mouse
			_last_mouse = event.position
			var right: Vector3 = global_transform.basis.x * (-delta.x * pan_speed)
			var up: Vector3 = global_transform.basis.y * (delta.y * pan_speed)
			pivot += right + up
			_apply_orbit()


func _apply_orbit() -> void:
	var x: float = _distance * sin(_phi) * sin(_theta)
	var y: float = _distance * cos(_phi)
	var z: float = -_distance * sin(_phi) * cos(_theta)
	global_position = pivot + Vector3(x, y, z)
	look_at(pivot, Vector3.UP)
