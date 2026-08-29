extends SceneTree

## The voxel view's own arithmetic, checked without a display: the grid the
## camera and every card are put on. See `mods/voxel3d/world/grid.gd`.

const BEARINGS: Array[float] = [0.0, 17.0, 45.0, -45.0, 123.0, 180.0]
const PITCHES: Array[float] = [20.0, 35.0, 60.0, 80.0]
const SURFACE_PIXELS: float = 540.0
const FRAME_WORLD: float = 92.0
const WANDER: Array[float] = [0.0, 0.013, 0.37, 0.5, 0.9, 3.25, -7.125]

var _failures: int = 0


func _initialize() -> void:
	var grid: GDScript = load("%s/world/grid.gd" % _mod())
	if grid == null:
		print("no grid.gd under %s" % _mod())
		quit(1)
		return
	var step: float = grid.step(FRAME_WORLD, SURFACE_PIXELS)
	print("grid       %.4f world units to a surface pixel" % step)
	_report("a surface with no height has no grid", grid.step(FRAME_WORLD, 0.0) == 0.0)
	_report("a point is left alone where there is no grid",
		grid.snapped(Vector3(1.234, 5.0, -9.87), [Vector3.RIGHT, Vector3.UP], 0.0)
			== Vector3(1.234, 5.0, -9.87))
	_report("a camera looking straight down has no right", grid.axes(Vector3.UP).is_empty())
	_report("a point is left alone where there are no axes",
		grid.snapped(Vector3.ONE, [], step) == Vector3.ONE)
	for pitch: float in PITCHES:
		for bearing: float in BEARINGS:
			_check(grid, step, pitch, bearing)
	quit(int(_failures > 0))


func _mod() -> String:
	return (get_script() as Script).resource_path.get_base_dir() \
		.get_base_dir().path_join("mods/voxel3d")


## The camera's own offset, as `camera_rig.gd:offset` builds it, turned by a
## bearing so the grid is checked in every direction the view can be steered to.
func _forward(pitch: float, bearing: float) -> Vector3:
	var above: float = deg_to_rad(pitch)
	var ahead := Vector3(0.0, sin(above), cos(above))
	return ahead.rotated(Vector3.UP, deg_to_rad(bearing))


func _check(grid: GDScript, step: float, pitch: float, bearing: float) -> void:
	var axes: Array = grid.axes(_forward(pitch, bearing))
	var where: String = "pitch %.0f bearing %.0f" % [pitch, bearing]
	if axes.size() != 2:
		_report("%s has two screen axes" % where, false)
		return
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	_report("%s: the axes are square and unit" % where,
		is_equal_approx(right.length(), 1.0) and is_equal_approx(up.length(), 1.0)
			and is_zero_approx(right.dot(up)))
	_whole_steps(grid, step, axes, where)
	_one_cell(grid, step, axes, where)


## Every snapped point stands a whole number of steps from every other, which is
## the whole of the claim: the picture can only move in whole surface pixels.
func _whole_steps(grid: GDScript, step: float, axes: Array, where: String) -> void:
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var whole: bool = true
	var first: Vector3 = grid.snapped(Vector3(3.0, 11.0, -5.0), axes, step)
	for across: float in WANDER:
		for above: float in WANDER:
			var point := Vector3(3.0 + across, 11.0 + above, -5.0 - across)
			var moved: Vector3 = grid.snapped(point, axes, step) - first
			for along: Vector3 in [right, up]:
				var steps: float = moved.dot(along) / step
				whole = whole and is_equal_approx(steps, roundf(steps))
	_report("%s: a snapped point is a whole number of steps away" % where, whole)


## Two positions inside one surface pixel are one drawn frame, which is what a
## drifting phase costs and what SMOOTH SCROLL hands this view between passes.
func _one_cell(grid: GDScript, step: float, axes: Array, where: String) -> void:
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var same: bool = true
	var apart: bool = false
	var base := Vector3(-40.0, 8.0, 17.5)
	var settled: Vector3 = grid.snapped(base, axes, step)
	for part: float in [0.0, 0.1, 0.24, 0.49]:
		for along: Vector3 in [right, up, (right + up).normalized()]:
			same = same and grid.snapped(
				settled + along * part * step, axes, step
			).is_equal_approx(settled)
	for along: Vector3 in [right, up]:
		apart = apart or not grid.snapped(
			settled + along * step, axes, step
		).is_equal_approx(settled)
	_report("%s: a move inside one pixel draws the same frame" % where, same)
	_report("%s: a move of a whole pixel draws a new one" % where, apart)


func _report(what: String, passed: bool) -> void:
	if not passed:
		_failures += 1
		print("FAIL  %s" % what)
		return
	print("ok    %s" % what)
