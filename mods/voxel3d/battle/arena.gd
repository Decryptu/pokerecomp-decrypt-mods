extends RefCounted

## Where a fight is staged on the map, and the camera that shoots it.
##
## The two battlers are PINNED to their patch of ground: each picture is drawn
## wherever its cell projects to, not at a fixed place on the screen. So the
## camera is not decoration. It is the thing that decides where the fight
## appears, and it has to put those two patches exactly where the hardware puts
## its two pictures:
##
##     the player's, bottom centre of its 6x6 slot     (40, 96)
##     the foe's,    bottom centre of its 7x7 slot     (124, 56)
##
## Four screen coordinates, so four equations. The rig below is their solution:
## SIDE, BACK and HEIGHT place the eye relative to the arena's midpoint, LOOK
## aims it, and FRAME_HEIGHT sets the lens. They are not numbers that looked
## about right; they came out of a solver and they land both marks to within a
## hundredth of a pixel. Changing the gap between the two battlers invalidates
## every one of them.
##
## Landing those marks is also what keeps the fight readable: the panels and the
## text box are drawn where the hardware draws them, and a composition that puts
## each battler in its own hardware slot cannot collide with either.
##
## EAST is what decides which battler is on which side. The arena's axis runs
## north to south with the foe at the north end, and an eye east of that axis
## sees the near end swing left and the far end right. That is the layout
## arrived at by standing in the right place rather than by mirroring anything,
## which is why the axis is the map's own north and not the way the player
## happened to be walking.
##
## Purely a composition: the camera looks at the map, and nothing here reaches
## collision, movement, triggers or scripts.

const Steering: GDScript = preload("../steering.gd")

const CELL: float = 16.0

## The gap between the two battlers, and the shape of ground that fits them.
##
## Three cells apart down one column, with a one-cell apron all round so the
## camera looks across floor rather than into a wall:
##
##     x x x
##     x O x     the foe
##     x x x
##     x x x
##     x P x     the player's
##     x x x
##
## When nowhere has room for that, the apron is given up and the bare column
## will do, because a corridor or a shop floor has room for the fight but not
## for the apron. If even the column will not fit, the fight is staged on the
## player's own cell and the camera takes what it can get.
const GAP: float = 48.0
const GAP_CELLS: int = 3
const APRON_CELLS: int = 1
## How far from the player the search looks for that shape.
const SEARCH_CELLS: int = 6

## The rig, in world pixels, solved against the four anchors above with the two
## battlers three cells apart: a 23.6 degree lens from about five cells back and
## two above the floor, which is what a 48 pixel picture standing on a 16 pixel
## cell forces on a 160 pixel screen.
const SIDE: float = 54.43
const BACK: float = 87.38
const HEIGHT: float = 32.78
const LOOK_X: float = -3.54
const LOOK_Y: float = -0.47
## How much world the frame is tall enough to hold at the aim distance. Together
## with that distance it is the lens, and it is what the zoom multiplies: moving
## the eye alone would change the perspective without changing the framing.
const FRAME_HEIGHT: float = 45.95

## Where the opposing trainer stands: behind their own Pokemon and off its
## shoulder, so the pair reads as one side of the fight and neither hides the
## other.
const TRAINER_BEHIND: float = 14.0
const TRAINER_ASIDE: float = -22.0

## How the shot is checked against the map. Walkable ground is not the same
## question as being able to SEE the two of them: the eye is low and a long way
## back, so a hedge, a ledge lip or a building corner anywhere along that line
## hides a battler completely while the cells it stands on are perfectly
## walkable. Every candidate arena is tested by looking down both sight lines.
const CLEARANCE_SAMPLES: int = 12
const CLEARANCE: float = 4.0
## How high up each battler has to be visible, which is about the middle of a
## picture: a shot that can see its feet and nothing else is not a shot.
const CLEARANCE_HEIGHT: float = 24.0

## What the player may do to the shot. Zero swing is the composition the rig was
## solved for and the stop, because past it the two battlers start swapping sides
## and the panels stop belonging to them. One swing ends square to the axis,
## where both stand at the same distance; one climb ends 45 degrees above the
## rig's own stance.
const CLIMB_RANGE: float = 45.0
const SWING_STEP: float = 0.08
const CLIMB_STEP: float = 0.08

var _source: RefCounted = null
var _heights: RefCounted = null
## The arena's midpoint, halfway between the two battlers.
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
## Which way a wheel notch zooms, from the player's own setting.
var _wheel_sign: int = 1


## Finds the ground this fight is shot on. [param source] is a `map_source.gd`
## and may be null, which stages on the player's own cell.
## [param heights] is the built `mesher.gd`, which is what answers how tall the
## thing standing in a cell turned out to be. Staging happens after the mesh for
## exactly that reason.
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
	# The cell the shape matched at is where the player's own battler stands, so
	# the midpoint is half the gap north of it.
	_mid = _centre(at) + Vector3(0.0, 0.0, -GAP * 0.5)


## The nearest cell the arena's shape fits on, with the player's battler standing
## there and the foe three cells north.
##
## The player's own cell is tried first and wins any tie, so an ordinary fight is
## staged where they stopped. The search then widens by rings, preferring the
## full shape with its apron and keeping the best bare column it saw in case
## nothing has room for one.
func _find_ground(source: RefCounted, from: Vector2i) -> Vector2i:
	var fallback: Vector2i = from
	var found_column: bool = false
	for radius: int in range(0, SEARCH_CELLS + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				# Only the ring itself: the inside was searched at a smaller
				# radius and answered, or it would not have got here.
				if radius > 0 and absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var cell: Vector2i = from + Vector2i(offset_x, offset_y)
				if _fits(source, cell, APRON_CELLS) and _in_shot(cell):
					return cell
				if not found_column and _fits(source, cell, 0) and _in_shot(cell):
					fallback = cell
					found_column = true
	return fallback


## Whether the shot this arena would be given can actually see both battlers.
##
## Answered against the canonical rig rather than wherever the player last left
## the camera: whether a fight can be staged somewhere is a fact about the
## ground, and reading it through a steered angle would pick a different arena
## depending on where the camera was swung an hour ago.
func _in_shot(cell: Vector2i) -> bool:
	if _heights == null:
		return true
	var mid: Vector3 = _centre(cell) + Vector3(0.0, 0.0, -GAP * 0.5)
	var seat: Vector3 = mid + Vector3(SIDE, HEIGHT, BACK)
	if seat.y <= float(_heights.height_at_position(seat)) + CLEARANCE:
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
		if at.y <= float(_heights.height_at_position(at)) + CLEARANCE:
			return false
	return true


## Whether the arena's column stands on walkable ground at [param cell], with
## [param apron] cells of walkable ground to each side of it. Collision is read
## here and never written.
func _fits(source: RefCounted, cell: Vector2i, apron: int) -> bool:
	for step: int in range(-apron, GAP_CELLS + 1 + apron):
		for across: int in range(-apron, apron + 1):
			var at := Vector2i(cell.x + across, cell.y - step)
			if source.permission_at(at) != Gen2WorldCollision.LAND_TILE:
				return false
	return true


func _centre(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)


## The foe stands at the north end of the axis and the player's own at the south.
func enemy_ground() -> Vector3:
	return _mid + Vector3(0.0, 0.0, -GAP * 0.5)


func player_ground() -> Vector3:
	return _mid + Vector3(0.0, 0.0, GAP * 0.5)


func enemy_trainer_ground() -> Vector3:
	return enemy_ground() + Vector3(TRAINER_ASIDE, 0.0, -TRAINER_BEHIND)


## What the lens is aimed at, which is also what the eye swings and climbs about.
func target() -> Vector3:
	return _mid + Vector3(LOOK_X, LOOK_Y, 0.0)


## The eye. Zero swing, zero climb and one zoom is exactly the shot the rig was
## solved for; the steer moves out from it and never past its stops.
func eye() -> Vector3:
	var yaw: float = -_swing * deg_to_rad(_swing_range())
	var seat: Vector3 = _mid + Vector3(
		SIDE * cos(yaw) - BACK * sin(yaw),
		HEIGHT,
		SIDE * sin(yaw) + BACK * cos(yaw)
	)
	if _climb <= 0.0:
		return seat

	# Climbed about the FOCUS at a constant radius, so the aim stays nailed to
	# the pair and only the seat moves. How big anything is is the lens's job,
	# and a rig doing both at once could do neither on purpose.
	var focus: Vector3 = target()
	var arm: Vector3 = seat - focus
	var flat: float = Vector2(arm.x, arm.z).length()
	var radius: float = arm.length()
	if flat < 0.001 or radius < 0.001:
		return seat
	# Short of straight down, always: the placed camera's up vector is world up,
	# which has no basis against a view looking along it.
	var angle: float = minf(
		atan2(arm.y, flat) + _climb * deg_to_rad(CLIMB_RANGE), deg_to_rad(85.0)
	)
	var reach: float = radius * cos(angle)
	return focus + Vector3(
		arm.x / flat * reach, radius * sin(angle), arm.z / flat * reach
	)


## The vertical field of view that frames FRAME_HEIGHT of world at the aim
## distance, which is the lens the anchors were solved with. The zoom is the
## lens rather than the distance, because the rig derives its field of view from
## the two together and moving the eye alone would change the perspective
## without changing the framing.
##
## [param frame_stretch] is how much taller the surface being drawn on is than
## the hardware screen the anchors are measured in. The stage fills the window
## and the panels are drawn at a whole-number scale in the middle of it, so the
## lens has to frame FRAME_HEIGHT across that middle rectangle rather than across
## the window, or the two layers agree only at the sizes where the letterbox
## happens to vanish.
func fov(frame_stretch: float = 1.0) -> float:
	var distance: float = (eye() - target()).length()
	if distance < 0.001:
		return 45.0
	return rad_to_deg(2.0 * atan((FRAME_HEIGHT * _zoom * frame_stretch * 0.5) / distance))


## How far round the eye may swing before the picture stops being a battle: to
## square-on with the axis, where both battlers stand at one distance.
func _swing_range() -> float:
	return 90.0 - rad_to_deg(atan2(SIDE, BACK))


## The events the battle screen does not claim. A Gen2Button never arrives here.
##
## The binding is `steering.gd`'s, shared with the overworld, so a wheel notch
## means one thing in the mod. A dolly is refused: this seat is solved against
## the hardware's own picture slots and moving it is what the zoom is for.
func handle_input(event: InputEvent) -> bool:
	match Steering.command(event, _wheel_sign):
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
		_:
			return false
	return true


func set_wheel_sign(sign_of_wheel: int) -> void:
	_wheel_sign = 1 if sign_of_wheel >= 0 else -1


## Real frame time, so a fast-forwarded battle never spins the camera.
func advance(delta: float) -> bool:
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
