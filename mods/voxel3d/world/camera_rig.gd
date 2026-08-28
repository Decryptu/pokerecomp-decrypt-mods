extends RefCounted

## Where the overworld's eye sits, what lens is on it, and the ease between one
## setting and the next.

const Steering: GDScript = preload("../steering.gd")

const PITCH_LIMITS := Vector2(12.0, 88.0)
const PITCH_STEP: float = 6.0
const PITCH_DEFAULT: float = 50.0

const DISTANCE_LIMITS := Vector2(48.0, 480.0)
const DISTANCE_STEP: float = 24.0
const DISTANCE_DEFAULT: float = 190.0

const FOV_DEFAULT: float = 42.0

const BOX_CLEARANCE: int = 16

var _pitch: float = PITCH_DEFAULT
var _distance: float = DISTANCE_DEFAULT
var _zoom: float = 1.0
var _pan: float = 0.0

var _pitch_from: float = PITCH_DEFAULT
var _distance_from: float = DISTANCE_DEFAULT
var _zoom_from: float = 1.0
var _pan_from: float = 0.0
var _pitch_goal: float = PITCH_DEFAULT
var _distance_goal: float = DISTANCE_DEFAULT
var _zoom_goal: float = 1.0
var _pan_goal: float = 0.0
var _t: float = 1.0

var _wheel_sign: int = 1
var _opening_pitch: float = PITCH_DEFAULT


func handle_input(event: InputEvent) -> bool:
	return steer(Steering.command(event, _wheel_sign))


func steer(command: StringName) -> bool:
	match command:
		Steering.ZOOM_IN:
			_aim(_pitch_goal, _distance_goal, _zoom_goal - Steering.ZOOM_STEP)
		Steering.ZOOM_OUT:
			_aim(_pitch_goal, _distance_goal, _zoom_goal + Steering.ZOOM_STEP)
		Steering.PITCH_UP:
			_aim(_pitch_goal + PITCH_STEP, _distance_goal, _zoom_goal)
		Steering.PITCH_DOWN:
			_aim(_pitch_goal - PITCH_STEP, _distance_goal, _zoom_goal)
		Steering.DOLLY_IN:
			_aim(_pitch_goal, _distance_goal - DISTANCE_STEP, _zoom_goal)
		Steering.DOLLY_OUT:
			_aim(_pitch_goal, _distance_goal + DISTANCE_STEP, _zoom_goal)
		Steering.RESET:
			_aim(_opening_pitch, DISTANCE_DEFAULT, 1.0)
		_:
			return false
	return true


func steer_by(command: StringName, notches: float) -> bool:
	match command:
		Steering.ZOOM_IN:
			_glide_zoom(-Steering.ZOOM_STEP * notches)
		Steering.ZOOM_OUT:
			_glide_zoom(Steering.ZOOM_STEP * notches)
		Steering.PITCH_UP:
			_glide_pitch(PITCH_STEP * notches)
		Steering.PITCH_DOWN:
			_glide_pitch(-PITCH_STEP * notches)
		Steering.DOLLY_IN:
			_glide_distance(-DISTANCE_STEP * notches)
		Steering.DOLLY_OUT:
			_glide_distance(DISTANCE_STEP * notches)
		_:
			return false
	return true


func _glide_pitch(degrees: float) -> void:
	var moved: float = clampf(
		_pitch_goal + degrees, PITCH_LIMITS.x, PITCH_LIMITS.y
	) - _pitch_goal
	_pitch += moved
	_pitch_from += moved
	_pitch_goal += moved


func _glide_distance(pixels: float) -> void:
	var moved: float = clampf(
		_distance_goal + pixels, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y
	) - _distance_goal
	_distance += moved
	_distance_from += moved
	_distance_goal += moved


func _glide_zoom(amount: float) -> void:
	var moved: float = clampf(
		_zoom_goal + amount, Steering.ZOOM_LIMITS.x, Steering.ZOOM_LIMITS.y
	) - _zoom_goal
	_zoom += moved
	_zoom_from += moved
	_zoom_goal += moved


func set_wheel_sign(sign_of_wheel: int) -> void:
	_wheel_sign = 1 if sign_of_wheel >= 0 else -1


func set_default_pitch(degrees: float) -> void:
	_opening_pitch = degrees
	_aim(degrees, _distance_goal, _zoom_goal)


func advance(delta: float) -> bool:
	if _t >= 1.0:
		return false
	_t = minf(1.0, _t + delta / Steering.TWEEN_TIME)
	var eased: float = _t * _t * (3.0 - 2.0 * _t)
	_pitch = _pitch_from + (_pitch_goal - _pitch_from) * eased
	_distance = _distance_from + (_distance_goal - _distance_from) * eased
	_zoom = _zoom_from + (_zoom_goal - _zoom_from) * eased
	_pan = _pan_from + (_pan_goal - _pan_from) * eased
	return true


func offset() -> Vector3:
	var above: float = deg_to_rad(_pitch)
	return Vector3(0.0, sin(above), cos(above)) * _distance


func fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV_DEFAULT) * 0.5) * _zoom))


func pan_for_text_box(
	box_top: float, frame_height: float, per_hardware_pixel: float = 1.0
) -> void:
	var wanted: float = 0.0
	if box_top > 0.0 and box_top < frame_height and frame_height > 0.0:
		wanted = maxf(0.0, 0.5 - (box_top - BOX_CLEARANCE * per_hardware_pixel)
			/ frame_height)
	if is_equal_approx(wanted, _pan_goal):
		return
	_aim(_pitch_goal, _distance_goal, _zoom_goal, wanted)


func pan() -> Vector3:
	if is_zero_approx(_pan):
		return Vector3.ZERO
	var above: float = deg_to_rad(_pitch)
	var frame: float = 2.0 * _distance * tan(deg_to_rad(fov()) * 0.5)
	return Vector3(0.0, -cos(above), sin(above)) * (_pan * frame)


func pitch() -> float:
	return _pitch


func distance() -> float:
	return _distance


func zoom() -> float:
	return _zoom


func _aim(
	pitch_degrees: float, distance_pixels: float, zoom_scale: float,
	pan_fraction: float = -1.0
) -> void:
	_pitch_from = _pitch
	_distance_from = _distance
	_zoom_from = _zoom
	_pan_from = _pan
	_pitch_goal = clampf(pitch_degrees, PITCH_LIMITS.x, PITCH_LIMITS.y)
	_distance_goal = clampf(distance_pixels, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_zoom_goal = clampf(zoom_scale, Steering.ZOOM_LIMITS.x, Steering.ZOOM_LIMITS.y)
	if pan_fraction >= 0.0:
		_pan_goal = pan_fraction
	_t = 0.0
