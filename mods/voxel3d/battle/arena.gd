extends RefCounted

## Where a fight is staged on the map, and the camera that shoots it.

const Steering: GDScript = preload("../steering.gd")

const CELL: float = 16.0

const GAP: float = 48.0
const GAP_CELLS: int = 3
const APRON_CELLS: int = 1
const SEARCH_CELLS: int = 6

const PLAYER_MARK := Vector2(40.0, 96.0)
const ENEMY_MARK := Vector2(124.0, 56.0)

const SIDE: float = 54.43
const BACK: float = 87.38
const HEIGHT: float = 32.78
const LOOK_X: float = -3.54
const LOOK_Y: float = -0.47
const FRAME_HEIGHT: float = 45.95

const TRAINER_BEHIND: float = 14.0
const TRAINER_ASIDE: float = -22.0

const CLEARANCE_SAMPLES: int = 12
const CLEARANCE: float = 4.0
const CLEARANCE_HEIGHT: float = 24.0

const CLIMB_RANGE: float = 45.0
const SWING_STEP: float = 0.08
const CLIMB_STEP: float = 0.08

const DRIFT_DEGREES: float = 1.0
const DRIFT_PERIOD: float = 19.0
const DRIFT_DOLLY: float = 1.6
const DRIFT_DOLLY_PERIOD: float = 13.0

const SHAKE_SCALE: float = FRAME_HEIGHT / 144.0

var _source: RefCounted = null
var _heights: RefCounted = null
var _mid := Vector3.ZERO

var _swing: float = 0.0
var _climb: float = 0.0
var _zoom: float = 1.0
var _swing_from: float = 0.0
var _climb_from: float = 0.0
var _zoom_from: float = 1.0
var _swing_goal: float = 0.0
var _climb_goal: float = 0.0
var _zoom_goal: float = 1.0
var _t: float = 1.0
var _drift: float = 0.0
var _shake := Vector2.ZERO
var _wheel_sign: int = 1


func stage(
	context: Gen2BattleWorldContext,
	source: RefCounted = null,
	heights: RefCounted = null,
) -> void:
	_source = source
	_heights = heights
	if context == null:
		_mid = Vector3.ZERO
		return
	var at: Vector2i = context.player_cell
	if source != null:
		at = _find_ground(source, context.player_cell)
	_mid = _centre(at) + Vector3(0.0, 0.0, -GAP * 0.5)


func _find_ground(source: RefCounted, from: Vector2i) -> Vector2i:
	var fallback: Vector2i = from
	var found_column: bool = false
	for radius: int in range(0, SEARCH_CELLS + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				if radius > 0 and absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var cell: Vector2i = from + Vector2i(offset_x, offset_y)
				if _fits(source, cell, APRON_CELLS) and _in_shot(cell):
					return cell
				if not found_column and _fits(source, cell, 0) and _in_shot(cell):
					fallback = cell
					found_column = true
	return fallback


func _in_shot(cell: Vector2i) -> bool:
	if _heights == null:
		return true
	var mid: Vector3 = _centre(cell) + Vector3(0.0, 0.0, -GAP * 0.5)
	var seat: Vector3 = mid + Vector3(SIDE, HEIGHT, BACK)
	if seat.y <= float(_occlusion_height(seat)) + CLEARANCE:
		return false
	for ground: Vector3 in [
		mid + Vector3(0.0, 0.0, -GAP * 0.5), mid + Vector3(0.0, 0.0, GAP * 0.5)
	]:
		if not _sight_line(seat, ground + Vector3(0.0, CLEARANCE_HEIGHT, 0.0)):
			return false
	return true


func _sight_line(from: Vector3, to: Vector3) -> bool:
	for step: int in range(1, CLEARANCE_SAMPLES):
		var at: Vector3 = to + (from - to) * (float(step) / float(CLEARANCE_SAMPLES))
		if at.y <= float(_occlusion_height(at)) + CLEARANCE:
			return false
	return true


func _occlusion_height(at: Vector3) -> int:
	if _heights.has_method(&"occlusion_height_at_position"):
		return int(_heights.call(&"occlusion_height_at_position", at))
	return int(_heights.height_at_position(at))


func _fits(source: RefCounted, cell: Vector2i, apron: int) -> bool:
	for step: int in range(-apron, GAP_CELLS + 1 + apron):
		for across: int in range(-apron, apron + 1):
			var at := Vector2i(cell.x + across, cell.y - step)
			if source.permission_at(at) != Gen2WorldCollision.LAND_TILE:
				return false
	return true


func _centre(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)


func enemy_ground() -> Vector3:
	return _mid + Vector3(0.0, 0.0, -GAP * 0.5)


func player_ground() -> Vector3:
	return _mid + Vector3(0.0, 0.0, GAP * 0.5)


func enemy_trainer_ground() -> Vector3:
	return enemy_ground() + Vector3(TRAINER_ASIDE, 0.0, -TRAINER_BEHIND)


func target() -> Vector3:
	return _mid + Vector3(LOOK_X, LOOK_Y + _shake.y * SHAKE_SCALE, 0.0) + _truck()


func set_shake(hardware_pixels: Vector2) -> void:
	_shake = hardware_pixels


func _truck() -> Vector3:
	if is_zero_approx(_shake.x):
		return Vector3.ZERO
	var yaw: float = _yaw()
	var forward := Vector3(
		-(SIDE * cos(yaw) - BACK * sin(yaw)), 0.0, -(SIDE * sin(yaw) + BACK * cos(yaw))
	)
	if forward.length_squared() <= 0.0:
		return Vector3.ZERO
	return forward.normalized().cross(Vector3.UP) * (_shake.x * SHAKE_SCALE)


func _yaw() -> float:
	return -_swing * deg_to_rad(_swing_range()) + _drift_yaw()


func _drift_yaw() -> float:
	return deg_to_rad(DRIFT_DEGREES) * sin(TAU * _drift / DRIFT_PERIOD)


func _drift_dolly() -> float:
	return DRIFT_DOLLY * sin(TAU * _drift / DRIFT_DOLLY_PERIOD)


func eye() -> Vector3:
	var yaw: float = _yaw()
	var seat: Vector3 = _mid + Vector3(
		SIDE * cos(yaw) - BACK * sin(yaw),
		HEIGHT,
		SIDE * sin(yaw) + BACK * cos(yaw)
	)
	seat.y += _shake.y * SHAKE_SCALE
	seat += _truck()
	var aim: Vector3 = target()
	var reach_now: float = (seat - aim).length()
	if reach_now > 0.001:
		seat = aim + (seat - aim) * (1.0 + _drift_dolly() / reach_now)
	if _climb <= 0.0:
		return seat

	var focus: Vector3 = target()
	var arm: Vector3 = seat - focus
	var flat: float = Vector2(arm.x, arm.z).length()
	var radius: float = arm.length()
	if flat < 0.001 or radius < 0.001:
		return seat
	var angle: float = minf(
		atan2(arm.y, flat) + _climb * deg_to_rad(CLIMB_RANGE), deg_to_rad(85.0)
	)
	var reach: float = radius * cos(angle)
	return focus + Vector3(
		arm.x / flat * reach, radius * sin(angle), arm.z / flat * reach
	)


func fov(frame_stretch: float = 1.0) -> float:
	var distance: float = (eye() - target()).length()
	if distance < 0.001:
		return 45.0
	return rad_to_deg(2.0 * atan((FRAME_HEIGHT * _zoom * frame_stretch * 0.5) / distance))


func _swing_range() -> float:
	return 90.0 - rad_to_deg(atan2(SIDE, BACK))


func handle_input(event: InputEvent) -> bool:
	return steer(Steering.command(event, _wheel_sign))


func steer(command: StringName) -> bool:
	match command:
		Steering.ZOOM_IN:
			_aim(_swing_goal, _climb_goal, _zoom_goal - Steering.ZOOM_STEP)
		Steering.ZOOM_OUT:
			_aim(_swing_goal, _climb_goal, _zoom_goal + Steering.ZOOM_STEP)
		Steering.PITCH_UP:
			_aim(_swing_goal, _climb_goal + CLIMB_STEP, _zoom_goal)
		Steering.PITCH_DOWN:
			_aim(_swing_goal, _climb_goal - CLIMB_STEP, _zoom_goal)
		Steering.SWING_RIGHT:
			_aim(_swing_goal + SWING_STEP, _climb_goal, _zoom_goal)
		Steering.SWING_LEFT:
			_aim(_swing_goal - SWING_STEP, _climb_goal, _zoom_goal)
		Steering.RESET:
			_aim(0.0, 0.0, 1.0)
		_:
			return false
	return true


func steer_by(command: StringName, notches: float) -> bool:
	match command:
		Steering.ZOOM_IN:
			_glide(0.0, 0.0, -Steering.ZOOM_STEP * notches)
		Steering.ZOOM_OUT:
			_glide(0.0, 0.0, Steering.ZOOM_STEP * notches)
		Steering.PITCH_UP:
			_glide(0.0, CLIMB_STEP * notches, 0.0)
		Steering.PITCH_DOWN:
			_glide(0.0, -CLIMB_STEP * notches, 0.0)
		Steering.SWING_RIGHT:
			_glide(SWING_STEP * notches, 0.0, 0.0)
		Steering.SWING_LEFT:
			_glide(-SWING_STEP * notches, 0.0, 0.0)
		_:
			return false
	return true


func _glide(swing: float, climb: float, zoom: float) -> void:
	var moved: float = clampf(_swing_goal + swing, 0.0, 1.0) - _swing_goal
	_swing += moved
	_swing_from += moved
	_swing_goal += moved
	moved = clampf(_climb_goal + climb, 0.0, 1.0) - _climb_goal
	_climb += moved
	_climb_from += moved
	_climb_goal += moved
	moved = clampf(
		_zoom_goal + zoom, Steering.ZOOM_LIMITS.x, Steering.ZOOM_LIMITS.y
	) - _zoom_goal
	_zoom += moved
	_zoom_from += moved
	_zoom_goal += moved


func set_wheel_sign(sign_of_wheel: int) -> void:
	_wheel_sign = 1 if sign_of_wheel >= 0 else -1


func advance(delta: float) -> bool:
	_drift += delta
	if _t >= 1.0:
		return false
	_t = minf(1.0, _t + delta / Steering.TWEEN_TIME)
	var eased: float = _t * _t * (3.0 - 2.0 * _t)
	_swing = _swing_from + (_swing_goal - _swing_from) * eased
	_climb = _climb_from + (_climb_goal - _climb_from) * eased
	_zoom = _zoom_from + (_zoom_goal - _zoom_from) * eased
	return true


func _aim(swing: float, climb: float, zoom: float) -> void:
	_swing_from = _swing
	_climb_from = _climb
	_zoom_from = _zoom
	_swing_goal = clampf(swing, 0.0, 1.0)
	_climb_goal = clampf(climb, 0.0, 1.0)
	_zoom_goal = clampf(zoom, Steering.ZOOM_LIMITS.x, Steering.ZOOM_LIMITS.y)
	_t = 0.0
