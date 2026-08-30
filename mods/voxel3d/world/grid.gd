extends RefCounted

## One grid for the camera and every card, so the picture only ever moves in
## whole pixels of the surface it is drawn on. `README.md` says why.


static func step(frame_world_height: float, surface_pixels: float) -> float:
	if frame_world_height <= 0.0 or surface_pixels <= 0.0:
		return 0.0
	return frame_world_height / surface_pixels


static func axes(forward: Vector3) -> Array:
	if forward.length_squared() <= 0.0:
		return []
	var ahead: Vector3 = forward.normalized()
	if absf(ahead.dot(Vector3.UP)) > 0.999:
		return []
	var right: Vector3 = Vector3.UP.cross(ahead).normalized()
	return [right, ahead.cross(right)]


static func snapped(point: Vector3, screen_axes: Array, grid: float) -> Vector3:
	if grid <= 0.0 or screen_axes.size() != 2:
		return point
	var right: Vector3 = screen_axes[0]
	var up: Vector3 = screen_axes[1]
	var across: float = point.dot(right)
	var above: float = point.dot(up)
	return point + right * (snappedf(across, grid) - across) \
		+ up * (snappedf(above, grid) - above)
