extends Camera3D
## Orbit camera: right-drag to orbit, scroll to zoom, middle-drag to pan
## Restricted to front-facing hemisphere of the battlefield

@export var pivot: Vector3 = Vector3(0, 0.5, 0)
@export var min_distance: float = 4.0
@export var max_distance: float = 35.0
@export var orbit_speed: float = 0.005
@export var pan_speed: float = 0.02
@export var zoom_speed: float = 0.8

## Horizontal angle limits (radians): restrict to front-facing arc
@export var min_theta: float = -PI * 0.45
@export var max_theta: float = PI * 0.45
@export var min_phi: float = 0.25
@export var max_phi: float = PI * 0.45

var _theta: float = PI * 0.49  ## horizontal angle
var _phi: float = 0.55         ## vertical angle
var _distance: float = 16.0

var _is_orbiting: bool = false
var _is_panning: bool = false
var _last_mouse: Vector2


func _ready() -> void:
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
			_theta -= delta.x * orbit_speed
			_theta = clamp(_theta, min_theta, max_theta)
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
