extends RefCounted

## Where the overworld's eye sits, what lens is on it, and the ease between one
## setting and the next.
##
## The renderer only exists while it is the selected view, so there is no "off"
## rung here: `V` is what turns the diorama on and off, and the host owns that.
## What is left is the shot, which is the one thing a player wants to change
## while walking around.
##
## The binding is not here. `steering.gd` owns what a key or a wheel notch means,
## so the overworld and the battle cannot disagree about it; this answers the
## commands an orbit about the player has an answer for and refuses the rest.
##
## Purely presentational. Nothing here reaches collision, movement, triggers or
## scripts, and the keys it reads are the ones the world screen did not claim.

const Steering: GDScript = preload("../steering.gd")

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

## The lens at zoom 1.0, in degrees, which is what the stage was framed at before
## the zoom was a lens rather than a dolly.
const FOV_DEFAULT: float = 42.0

var _pitch: float = PITCH_DEFAULT
var _distance: float = DISTANCE_DEFAULT
var _zoom: float = 1.0
## How far up the frame the shot is pushed, as a fraction of the frame's own
## height: what the text box asks for by being there. See `pan_for_text_box`.
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

## Which way a wheel notch zooms, from the player's own setting.
var _wheel_sign: int = 1
## The pitch the view opens at, which a RECENTRE goes back to rather than to the
## constant: the player chose it in the start menu and it is what "the way it
## was" means to them.
var _opening_pitch: float = PITCH_DEFAULT


## Every input event the world screen did not use. Answering true consumes it.
##
## Movement and interaction keys never arrive here: the screen claims those
## first, and an open overlay, a running script or a battle claims everything.
func handle_input(event: InputEvent) -> bool:
	return steer(Steering.command(event, _wheel_sign))


## One command, wherever it came from: a declared action the host resolved off a
## key, a pad, a stick or a finger, or the wheel this rig read itself.
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
			# A swing has no meaning about a player who is always in the middle
			# of the frame, so it is left for whoever else wants it.
			return false
	return true


## The same command held rather than pressed, worth [param notches] of its own
## step this frame. See `steering.gd:Glide`.
##
## A press aims at a goal and eases to it; a hold moves the goal itself, so this
## carries the value, the ease's starting point and the goal together. Anything
## already easing goes on easing to the shifted goal, and the PAN is untouched:
## a text box opening while the player holds the stick has its own tween running
## through this one.
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


## The pitch the view opens at, which is the player's own CAMERA setting. It
## eases like any other steer, so choosing it in the start menu shows what it
## does instead of snapping when the menu closes.
func set_default_pitch(degrees: float) -> void:
	_opening_pitch = degrees
	_aim(degrees, _distance_goal, _zoom_goal)


## Real frame time, so a fast-forward never speeds the camera up.
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


## Where the eye sits relative to what it is looking at.
func offset() -> Vector3:
	var pitch: float = deg_to_rad(_pitch)
	return Vector3(0.0, sin(pitch), cos(pitch)) * _distance


## The lens. Zooming the lens rather than the dolly is what keeps the pitch and
## the perspective the player set while only the framing changes.
func fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV_DEFAULT) * 0.5) * _zoom))


## How much of the frame the text box takes, turned into where the shot has to
## sit: the box covers everything below [param box_top], so the picture worth
## looking at is the band above it and the player belongs in the MIDDLE of that
## band rather than behind the box.
##
## [param box_top] and [param screen_height] are hardware pixels, and an empty
## box is a zero pan back to centre. The value is a fraction of the frame's own
## height, so it means the same thing at every zoom and every window size.
func pan_for_text_box(box_top: int, screen_height: int) -> void:
	var wanted: float = 0.0
	if box_top > 0 and box_top < screen_height:
		wanted = float(screen_height - box_top) / float(2 * screen_height)
	if is_equal_approx(wanted, _pan_goal):
		return
	_aim(_pitch_goal, _distance_goal, _zoom_goal, wanted)


## The translation that puts the shot where [method pan_for_text_box] asked for,
## applied to the eye and the target alike so it is a PAN and not a tilt: a tilt
## would rake the ground and swing the horizon, where the map wants the same
## picture moved up the frame.
func pan() -> Vector3:
	if is_zero_approx(_pan):
		return Vector3.ZERO
	var pitch: float = deg_to_rad(_pitch)
	# The frame's height in world pixels at the distance the eye is aimed from,
	# and the camera's own up axis, which is where a pan runs.
	var frame: float = 2.0 * _distance * tan(deg_to_rad(fov()) * 0.5)
	return Vector3(0.0, -cos(pitch), sin(pitch)) * (_pan * frame)


func pitch() -> float:
	return _pitch


func distance() -> float:
	return _distance


func zoom() -> float:
	return _zoom


func _aim(
	pitch_degrees: float, distance_pixels: float, zoom: float, pan_fraction: float = -1.0
) -> void:
	_pitch_from = _pitch
	_distance_from = _distance
	_zoom_from = _zoom
	_pan_from = _pan
	_pitch_goal = clampf(pitch_degrees, PITCH_LIMITS.x, PITCH_LIMITS.y)
	_distance_goal = clampf(distance_pixels, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_zoom_goal = clampf(zoom, Steering.ZOOM_LIMITS.x, Steering.ZOOM_LIMITS.y)
	if pan_fraction >= 0.0:
		_pan_goal = pan_fraction
	_t = 0.0
