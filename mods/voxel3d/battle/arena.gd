extends RefCounted

## Where a fight is staged on the map, and where it is shot from.
##
## `Gen2BattleWorldContext` says which cell the player was standing on and which
## way they were facing when the encounter started. Everything below is derived
## from that one line and the map's own collision: the two battlers stand on the
## ground the player was walking toward, and the camera sits behind the player's
## shoulder looking down the same axis.
##
## Purely a composition. Nothing here reaches the battle, and the battle reaches
## nothing here: a renderer that ignored all of it would draw the fight on a
## white field, which is what the cartridge does.

const CELL: float = 16.0

## How far along the axis each battler stands, as a fraction of the clear run
## found in front of the player, and the run the composition is drawn for.
const PLAYER_ALONG: float = 0.25
const ENEMY_ALONG: float = 0.9
const IDEAL_RUN_CELLS: int = 6
const MIN_RUN_CELLS: int = 2
## How far to look for clear ground before giving up and staging on the spot.
const SEARCH_CELLS: int = 8
## How far the arena may move from the player's own cell to find room.
const RELOCATE_CELLS: int = 4

## The eye, relative to the player's cell: behind it, off to one side, and above.
## The offset to one side is what makes it a shot over a shoulder rather than a
## line through both battlers, and it is what the lens is aimed back across.
const EYE_BACK: float = 110.0
const EYE_SIDE: float = 26.0
const EYE_HEIGHT: float = 68.0
## Where the lens looks, along the axis and above the ground. Biased toward the
## foe, because the shot is of what is being fought.
const LOOK_ALONG: float = 0.6
const LOOK_HEIGHT: float = 18.0

## How far the eye may swing around the arena and climb above its own seat, in
## degrees, and the step a key or a drag moves it by. Right ends side on, with
## both battlers the same distance away instead of one behind the other; left
## stops at the shot the rig was composed for, because there is nothing to the
## left of it.
const SWING_LIMITS := Vector2(0.0, 90.0)
const CLIMB_LIMITS := Vector2(0.0, 45.0)
const SWING_STEP: float = 7.5
const CLIMB_STEP: float = 5.0
## The lens, and how far it opens as the shot swings away from the composed one:
## swinging the eye round spreads the two battlers apart, so the frame has to
## widen by the amount they spread or one of them leaves it.
const FOV_BASE: float = 42.0
const FOV_SWING: float = 16.0

const ZOOM_LIMITS := Vector2(0.55, 1.8)
const ZOOM_STEP: float = 0.12
const TWEEN_TIME: float = 0.22

## Where the arena is, resolved once per battle.
var _origin := Vector3.ZERO
var _forward := Vector3(0.0, 0.0, 1.0)
var _right := Vector3(1.0, 0.0, 0.0)

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


## How far the arena reaches down its axis, in world pixels.
var _run: float = float(IDEAL_RUN_CELLS) * CELL


## A battle is staged down the axis the player was walking, which is the
## direction whatever they ran into is standing in, on the clear ground that
## direction actually has.
##
## The facing is only the preference. A player who meets something with their
## back to a wall has no room that way, and standing the foe inside a building is
## worse than turning the shot: so each cardinal direction is measured for how
## far it runs over walkable ground, and the longest wins with the facing
## breaking ties. [param source] is a `map_source.gd` and may be null, which
## stages on the spot.
func stage(context: Gen2BattleWorldContext, source: RefCounted = null) -> void:
	_run = float(IDEAL_RUN_CELLS) * CELL
	if context == null:
		_origin = Vector3.ZERO
		_forward = Vector3(0.0, 0.0, 1.0)
		_right = Vector3(1.0, 0.0, 0.0)
		return

	_origin = Vector3(
		context.player_cell.x * CELL + CELL * 0.5,
		0.0,
		context.player_cell.y * CELL + CELL * 0.5
	)
	_forward = _direction(context.player_facing)
	if source != null:
		var found: Dictionary = _find_ground(source, context.player_cell, context.player_facing)
		_origin = Vector3(
			int(found["cell"].x) * CELL + CELL * 0.5,
			0.0,
			int(found["cell"].y) * CELL + CELL * 0.5
		)
		_forward = _direction(int(found["facing"]))
		_run = float(maxi(int(found["run"]), MIN_RUN_CELLS)) * CELL
	_right = Vector3(-_forward.z, 0.0, _forward.x)


## The nearest cell with room to fight in, and the direction that room runs.
##
## The player's own cell is the first candidate and wins any tie, so the ordinary
## fight is staged exactly where they stopped. A player boxed into a walled yard
## has no arena there at all, though, and no camera placement rescues a shot with
## a fence through the middle of it: so the search widens by rings until it finds
## ground with a clear run, which is what puts the fight on the path outside
## rather than inside the wall.
func _find_ground(source: RefCounted, from: Vector2i, facing: int) -> Dictionary:
	var best := {"cell": from, "facing": facing, "run": 0}
	for radius: int in range(0, RELOCATE_CELLS + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				# Only the ring itself: the inside was searched at a smaller
				# radius and answered, or it would not have got here.
				if radius > 0 and absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var cell: Vector2i = from + Vector2i(offset_x, offset_y)
				if source.permission_at(cell) != Gen2WorldCollision.LAND_TILE:
					continue
				for candidate: int in 4:
					# The player's facing is tried first at every cell, so an
					# equal run keeps the direction they were walking.
					var try_facing: int = facing if candidate == 0 \
						else (candidate - 1 if candidate - 1 < facing else candidate)
					var run: int = _clear_run(source, cell, try_facing)
					if run > int(best["run"]):
						best = {"cell": cell, "facing": try_facing, "run": run}
		if int(best["run"]) >= IDEAL_RUN_CELLS:
			break
	return best


## Walkable cells in a straight line from the player, capped: past the ideal run
## a longer corridor is no better a stage, and measuring the whole of a route
## would let one open direction always win.
func _clear_run(source: RefCounted, from: Vector2i, facing: int) -> int:
	var step := Vector2i(
		int(_direction(facing).x), int(_direction(facing).z)
	)
	var run: int = 0
	while run < SEARCH_CELLS:
		var cell: Vector2i = from + step * (run + 1)
		if source.permission_at(cell) != Gen2WorldCollision.LAND_TILE:
			break
		run += 1
	return mini(run, IDEAL_RUN_CELLS)


static func _direction(facing: int) -> Vector3:
	match facing:
		Gen2WorldSprite.FACING_UP:
			return Vector3(0.0, 0.0, -1.0)
		Gen2WorldSprite.FACING_LEFT:
			return Vector3(-1.0, 0.0, 0.0)
		Gen2WorldSprite.FACING_RIGHT:
			return Vector3(1.0, 0.0, 0.0)
	return Vector3(0.0, 0.0, 1.0)


## Where each battler's feet are. The player's own Pokemon stands between the
## player and the foe, on the near side of the axis, which is the arrangement
## the flat view draws from the side.
func player_ground() -> Vector3:
	return _origin + _forward * (_run * PLAYER_ALONG) - _right * 7.0


func enemy_ground() -> Vector3:
	return _origin + _forward * (_run * ENEMY_ALONG) + _right * 7.0


## The eye, swung around the arena's centre and raised by whatever the player has
## asked for. The swing turns the whole seat about the axis rather than sliding
## it sideways, so the two battlers stay the same distance apart in the frame.
func eye() -> Vector3:
	var seat: Vector3 = -_forward * EYE_BACK + _right * EYE_SIDE
	var swung: Vector3 = seat.rotated(Vector3.UP, deg_to_rad(_swing))
	var pivot: Vector3 = target()
	var from_pivot: Vector3 = _origin + swung + Vector3(0.0, EYE_HEIGHT, 0.0) - pivot
	var climbed: Vector3 = from_pivot.rotated(
		_right.rotated(Vector3.UP, deg_to_rad(_swing)), -deg_to_rad(_climb)
	)
	return pivot + climbed * _zoom


func target() -> Vector3:
	return _origin + _forward * (_run * LOOK_ALONG) + Vector3(0.0, LOOK_HEIGHT, 0.0)


func fov() -> float:
	return FOV_BASE + FOV_SWING * (_swing / maxf(SWING_LIMITS.y, 1.0))


## The keys the battle screen does not read. `V` is the host's, so it never
## arrives, and neither does anything the menu or the text box wants.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed:
		match key.keycode:
			KEY_A:
				_aim(_swing_goal - SWING_STEP, _climb_goal, _zoom_goal)
			KEY_D:
				_aim(_swing_goal + SWING_STEP, _climb_goal, _zoom_goal)
			KEY_W:
				_aim(_swing_goal, _climb_goal + CLIMB_STEP, _zoom_goal)
			KEY_S:
				_aim(_swing_goal, _climb_goal - CLIMB_STEP, _zoom_goal)
			KEY_Q:
				_aim(_swing_goal, _climb_goal, _zoom_goal + ZOOM_STEP)
			KEY_E:
				_aim(_swing_goal, _climb_goal, _zoom_goal - ZOOM_STEP)
			_:
				return false
		return true

	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_aim(_swing_goal, _climb_goal, _zoom_goal - ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_aim(_swing_goal, _climb_goal, _zoom_goal + ZOOM_STEP)
			_:
				return false
		return true
	return false


func advance(delta: float) -> bool:
	if _t >= 1.0:
		return false
	_t = minf(1.0, _t + delta / TWEEN_TIME)
	var eased: float = _t * _t * (3.0 - 2.0 * _t)
	_swing = _swing_from + (_swing_goal - _swing_from) * eased
	_climb = _climb_from + (_climb_goal - _climb_from) * eased
	_zoom = _zoom_from + (_zoom_goal - _zoom_from) * eased
	return true


func _aim(swing: float, climb: float, zoom: float) -> void:
	_swing_from = _swing
	_climb_from = _climb
	_zoom_from = _zoom
	_swing_goal = clampf(swing, SWING_LIMITS.x, SWING_LIMITS.y)
	_climb_goal = clampf(climb, CLIMB_LIMITS.x, CLIMB_LIMITS.y)
	_zoom_goal = clampf(zoom, ZOOM_LIMITS.x, ZOOM_LIMITS.y)
	_t = 0.0
