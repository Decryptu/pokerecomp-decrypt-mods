extends SceneTree

## What the DIORAMA costs to draw, per frame, with the camera walking.

const MOD := "user://mods/voxel3d"
const CELL: float = 16.0
const TILE: float = 8.0
const WINDOW_DEFAULT := Vector2i(2560, 1440)
const WARMUP_FRAMES: int = 120
const WALK_PIXELS_PER_SECOND: float = 16.0 * 60.0 / 16.0
const Staging: GDScript = preload("staging.gd")
const LEG_PIXELS: float = 16.0 * 12.0

var _stage: RefCounted = null
var _mesher: RefCounted = null
var _frame: SubViewport = null
var _out: String = ""
var _shot: String = ""
var _seconds: float = 8.0
var _frames: int = 0
var _started_usec: int = 0
var _samples: Array = []
var _origin := Vector3.ZERO
var _walked: float = 0.0
var _pitch: float = 50.0
var _walking: bool = true
var _back: float = 220.0
var _viewports: Array[Viewport] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <cache> <group> <number> [seconds=] [cell=x,y] [window=WxH]"
			+ " [distance=] [scale=] [pitch=] [dof=] [splits=] [shadow_far=]"
			+ " [wind=] [off=layer,...] [ring=] [walk=] [shot=]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var named: Dictionary = _named(args)
	var map: Gen2WorldMap = data.world_map(int(args[1]), int(args[2]))
	if map == null:
		print("no map %s,%s" % [args[1], args[2]])
		quit(1)
		return
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)

	_seconds = maxf(float(named.get("seconds", "8")), 1.0)
	_shot = String(named.get("shot", ""))
	_out = String(named.get("out", ""))
	for path: String in [_shot, _out]:
		if not path.is_empty() and Gen2ToolPath.refuses(path):
			quit(2)
			return
	_pitch = float(named.get("pitch", "50"))
	_walking = int(named.get("walk", "1")) != 0
	var window: Vector2i = _size(String(named.get("window", "")))
	var cell := Vector2i(map.collision_width / 2, map.collision_height / 2)
	if String(named.get("cell", "")).contains(","):
		var parts: PackedStringArray = String(named["cell"]).split(",")
		cell = Vector2i(int(parts[0]), int(parts[1]))
	var distance: int = int(named.get("distance", "16"))

	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	_mesher = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()

	_frame = SubViewport.new()
	_frame.size = window
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)
	var holder := Control.new()
	holder.size = Vector2(window)
	holder.add_child(_stage.container)
	_frame.add_child(holder)
	_stage.container.size = Vector2(window)
	root.set_content_scale_size(window)
	root.size = window
	DisplayServer.window_set_size(window)

	_stage.set_time_of_day(Gen2WorldPalette.TIME_DAY)
	var animation := Gen2WorldAnimation.new()
	animation.configure_tileset(data, tileset, Gen2WorldPalette.TIME_DAY)
	if atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY, animation):
		_stage.set_texture(atlas.texture)
		if source.outside():
			_stage.set_background(atlas.background(), true, atlas.sky_ramp())
		else:
			_stage.set_background(atlas.void_color(), false)
	_mesher.resolve(source, shape)
	_origin = Vector3((float(cell.x) + 0.5) * CELL, 0.0, (float(cell.y) + 0.5) * CELL)
	_mesher.set_detail_ring(_origin, _ring(named) * CELL)
	var window_tiles: Rect2i = _window_of(cell, distance)
	if distance > 0:
		_stage.set_view_distance(float(distance) * CELL, true)
	var reached: int = int(named.get("reached", "0"))
	var margin: int = maxi(4, distance / 3) + 1 if distance > 0 else 0
	for step: int in reached:
		var back: int = reached - step
		var away := Vector2i(0, -margin * back) if back % 2 == 0 \
			else Vector2i(-margin * back, 0)
		_mesher.emit(atlas, _window_of(cell + away, distance))
		_mesher.take_water()
		_mesher.take_tufts()
		_mesher.take_models()
	_stage.set_terrain(_mesher.emit(atlas, window_tiles))
	_stage.set_water(_mesher.take_water())
	var shore: PackedColorArray = atlas.shore_colors()
	if shore.size() == 2:
		_stage.set_shore_colors(atlas.background(), shore[0], shore[1])
	_stage.set_bank(
		_mesher.bank_field(), _mesher.bank_world(), _mesher.bank_origin(),
		_mesher.bank_span()
	)
	_stage.set_tufts(_mesher.take_tufts())
	_stage.set_models(_mesher.take_models())
	print("map        %s,%s at %s, window %s, distance %d" % [
		args[1], args[2], str(cell), str(window), distance,
	])
	_apply(named)


func _apply(named: Dictionary) -> void:
	_stage.set_render_scale(int(named.get("scale", "1")))
	var dof: int = int(named.get("dof", "1"))
	_stage.set_depth_of_field(dof, 4.0, 900.0, 2600.0)
	match int(named.get("splits", "0")):
		1:
			_stage._light.directional_shadow_mode = \
				DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			_stage._light.directional_shadow_mode = \
				DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		4:
			_stage._light.directional_shadow_mode = \
				DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if float(named.get("shadow_far", "0")) > 0.0:
		_stage._light.directional_shadow_max_distance = float(named["shadow_far"])
	_stage.set_wind_still(int(named.get("wind", "1")) == 0)
	print("stage      scale %s, dof %d, shadows %s splits over %.0f px, wind %s" % [
		named.get("scale", "1"), dof, _splits_taken(),
		_stage._light.directional_shadow_max_distance, named.get("wind", "1"),
	])
	print("off        %s" % str(
		Staging.hide_layers(_stage, String(named.get("off", "")))
	))


func _splits_taken() -> String:
	match _stage._light.directional_shadow_mode:
		DirectionalLight3D.SHADOW_ORTHOGONAL:
			return "1"
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return "2"
	return "4"


## How far a model keeps its solid mesh before it wears its impostor. The
## renderer owns the number; a run says `ring=` to price another one.
static func _ring(named: Dictionary) -> float:
	var script: GDScript = load(Staging.RENDERER)
	var fallback: float = script.solid_cells if script != null else 0.0
	return float(named.get("ring", str(fallback)))


func _window_of(cell: Vector2i, distance: int) -> Rect2i:
	if distance <= 0:
		return Rect2i()
	var span: int = distance * 2 + 1
	return Rect2i(
		(cell - Vector2i(distance, distance)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	)


func _named(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(3, args.size()):
		var pair: String = args[index]
		var at: int = pair.find("=")
		if at > 0:
			out[pair.substr(0, at)] = pair.substr(at + 1)
	return out


func _size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2 or int(parts[0]) <= 0 or int(parts[1]) <= 0:
		return WINDOW_DEFAULT
	return Vector2i(int(parts[0]), int(parts[1]))


func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_measure_viewports(root)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return false
	_walk(delta if _walking else 0.0)
	if _frames < WARMUP_FRAMES:
		return false
	if _started_usec == 0:
		_started_usec = Time.get_ticks_usec()
	_samples.append({
		"ms": delta * 1000.0,
		"render_cpu_ms": _render_time(),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	})
	if float(Time.get_ticks_usec() - _started_usec) / 1000000.0 < _seconds:
		return false
	_capture()
	_report()
	quit(0)
	return true


func _walk(delta: float) -> void:
	_walked += delta * WALK_PIXELS_PER_SECOND
	var leg: float = fmod(_walked, LEG_PIXELS * 2.0)
	var along: float = leg if leg < LEG_PIXELS else LEG_PIXELS * 2.0 - leg
	var here: Vector3 = _origin + Vector3(0.0, 0.0, along)
	here.y = float(_mesher.surface_height_at_position(here))
	var pitch: float = deg_to_rad(_pitch)
	_stage.aim_camera(
		here + Vector3(0.0, _back * sin(pitch), _back * cos(pitch)),
		here + Vector3(0.0, TILE, 0.0)
	)
	_stage.set_walker(here)


func _measure_viewports(node: Node) -> void:
	var viewport: Viewport = node as Viewport
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_viewports.append(viewport)
	for child: Node in node.get_children():
		_measure_viewports(child)


func _render_time() -> float:
	var total: float = 0.0
	for viewport: Viewport in _viewports:
		total += RenderingServer.viewport_get_measured_render_time_cpu(
			viewport.get_viewport_rid()
		)
	return total


func _capture() -> void:
	if _shot.is_empty():
		return
	var image: Image = _frame.get_texture().get_image()
	if image == null or image.save_png(_shot) != OK:
		print("could not write %s" % _shot)
		return
	print("shot       %s" % _shot)


func _report() -> void:
	var ms: Array = []
	for row: Dictionary in _samples:
		ms.append(float(row["ms"]))
	ms.sort()
	var count: int = ms.size()
	print("frames     %d over %.1f s" % [count, _seconds])
	print("vsync      %s" % (
		"disabled" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
		else "ON, every figure below is the monitor's"
	))
	print("frame ms   mean %.2f  median %.2f  p95 %.2f  max %.2f" % [
		_mean(ms), _at(ms, 0.5), _at(ms, 0.95), ms[count - 1],
	])
	print("render cpu mean %.2f" % _mean(_column("render_cpu_ms")))
	print("draws      mean %d" % int(_mean(_column("draws"))))
	print("triangles  mean %d" % int(_mean(_column("primitives"))))
	print("video MB   %.1f" % _column("video_mb").max())
	if _out.is_empty():
		return
	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"seconds": _seconds, "samples": _samples}, "  "))
		print("wrote %s" % _out)


func _column(key: String) -> Array:
	var out: Array = []
	for row: Dictionary in _samples:
		out.append(row[key])
	return out


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _at(sorted: Array, fraction: float) -> float:
	return float(sorted[clampi(int(float(sorted.size() - 1) * fraction), 0, sorted.size() - 1)])
