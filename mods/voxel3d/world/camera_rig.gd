extends RefCounted

## The camera's pitch and distance, and the ease between one setting and the
## next.
##
## The renderer only exists while it is the selected view, so there is no "off"
## rung here: `V` is what turns the diorama on and off, and the host owns that.
## What is left is where the eye sits, which is the one thing a player wants to
## change while walking around.
##
## Purely presentational. Nothing here reaches collision, movement, triggers or
## scripts, and the keys it reads are the ones the world screen did not claim.

## Degrees above the horizon. Near-flat reads as a street-level shot; near
## overhead is the tile page with height on it.
const PITCH_LIMITS := Vector2(12.0, 88.0)
const PITCH_STEP: float = 6.0
const PITCH_DEFAULT: float = 50.0

## Distance from the player, in world pixels. A walk cell is 16, so the default
## frames a little over a screen's worth of map.
const DISTANCE_LIMITS := Vector2(48.0, 480.0)
const DISTANCE_STEP: float = 24.0
const DISTANCE_DEFAULT: float = 190.0

const TWEEN_TIME: float = 0.22

var _pitch: float = PITCH_DEFAULT
var _distance: float = DISTANCE_DEFAULT
var _pitch_from: float = PITCH_DEFAULT
var _distance_from: float = DISTANCE_DEFAULT
var _pitch_goal: float = PITCH_DEFAULT
var _distance_goal: float = DISTANCE_DEFAULT
var _t: float = 1.0


## Every input event the world screen did not use. Answering true consumes it.
##
## Movement and interaction keys never arrive here: the screen claims those
## first, and an open overlay, a running script or a battle claims everything.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed:
		match key.keycode:
			KEY_Q:
				_aim(_pitch_goal - PITCH_STEP, _distance_goal)
			KEY_E:
				_aim(_pitch_goal + PITCH_STEP, _distance_goal)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_aim(_pitch_goal, _distance_goal + DISTANCE_STEP)
			KEY_EQUAL, KEY_KP_ADD:
				_aim(_pitch_goal, _distance_goal - DISTANCE_STEP)
			_:
				return false
		return true

	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_aim(_pitch_goal, _distance_goal - DISTANCE_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_aim(_pitch_goal, _distance_goal + DISTANCE_STEP)
			_:
				return false
		return true
	return false


## Real frame time, so a fast-forward never speeds the camera up.
func advance(delta: float) -> bool:
	if _t >= 1.0:
		return false
	_t = minf(1.0, _t + delta / TWEEN_TIME)
	var eased: float = _t * _t * (3.0 - 2.0 * _t)
	_pitch = _pitch_from + (_pitch_goal - _pitch_from) * eased
	_distance = _distance_from + (_distance_goal - _distance_from) * eased
	return true


## Where the eye sits relative to what it is looking at.
func offset() -> Vector3:
	var pitch: float = deg_to_rad(_pitch)
	return Vector3(0.0, sin(pitch), cos(pitch)) * _distance


func pitch() -> float:
	return _pitch


func distance() -> float:
	return _distance


func _aim(pitch_degrees: float, distance_pixels: float) -> void:
	_pitch_from = _pitch
	_distance_from = _distance
	_pitch_goal = clampf(pitch_degrees, PITCH_LIMITS.x, PITCH_LIMITS.y)
	_distance_goal = clampf(distance_pixels, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_t = 0.0
