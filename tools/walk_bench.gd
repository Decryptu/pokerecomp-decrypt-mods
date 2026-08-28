extends SceneTree

## What a frame COSTS while the player is walking, through the game's own
## screen.

const WINDOW_SIZE := Vector2i(1280, 720)
const SETTLE_FRAMES: int = 60
const WARMUP_SECONDS: float = 3.0
const SPAN_CELLS_DEFAULT: int = 24
const Staging: GDScript = preload("staging.gd")

var _staging: RefCounted = Staging.new()
var _screen: Gen2WorldScreen = null
var _out: String = ""
var _shot: String = ""
var _seconds: float = 10.0
var _frames: int = 0
var _samples: Array = []
var _started_usec: int = 0
var _warmup_usec: int = 0
var _maps: Dictionary = {}
var _span: int = SPAN_CELLS_DEFAULT
var _battle_frames: int = 0
var _renderer: Node = null
var _time_refresh: bool = false
var _viewports: Array[Viewport] = []
var _map: Gen2WorldMap = null
var _start := Vector2i.ZERO


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <game> <group> <map> [seconds=] [view=] [cell=x,y] [span=]"
			+ " [window=WxH] [out=] [encounters=1] [refresh=1] [set=key:value,...]")
		quit(2)
		return
	var named: Dictionary = Staging.named(args)
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	var group: int = int(args[1])
	var number: int = int(args[2])
	var map: Gen2WorldMap = data.world_map(group, number)
	if map == null:
		print("no map %d,%d" % [group, number])
		quit(1)
		return

	_seconds = maxf(float(named.get("seconds", "10")), 1.0)
	_out = String(named.get("out", ""))
	_shot = String(named.get("shot", ""))
	for path: String in [_out, _shot]:
		if not path.is_empty() and Gen2ToolPath.refuses(path):
			quit(2)
			return
	_span = int(named.get("span", str(SPAN_CELLS_DEFAULT)))
	_time_refresh = named.has("refresh")
	var window: Vector2i = Staging.window_size(
		String(named.get("window", "")), WINDOW_SIZE
	)
	var wanted := Vector2i(map.collision_width / 2, map.collision_height / 2)
	if String(named.get("cell", "")).contains(","):
		var parts: PackedStringArray = String(named["cell"]).split(",")
		wanted = Vector2i(int(parts[0]), int(parts[1]))
	var start: Vector2i = Staging.open_ground(map, wanted)
	if start == Vector2i.MAX:
		print("no walkable room on map %d,%d" % [group, number])
		quit(1)
		return
	_map = map
	_start = start
	print("map        %d,%d at %s (asked %s), window %s" % [
		group, number, str(start), str(wanted), str(window),
	])

	var host: Gen2ModHost = Gen2ModHost.instance()
	if host.world_actors().is_empty():
		host.discover()
		host.load_discovered()
	var view := StringName(named.get("view", "gen2"))
	print("view       %s %s" % [String(view), str(host.select_view(view))])
	if named.has("static"):
		Staging.apply_statics(String(named["static"]))
	if named.has("set"):
		_staging.apply_options(host, view, String(named["set"]))
	if not host.failures().is_empty():
		print("failures   %s" % str(host.failures()))

	root.set_content_scale_size(window)
	root.size = window
	DisplayServer.window_set_size(window)
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = group
	_screen.map_number = number
	_screen.start_cell = start
	_screen.encounter_seed = 1
	_screen.set_data(data)
	_screen.set_save(_save(data, group, number, start, named.has("encounters")))
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


func _finalize() -> void:
	_staging.restore()


func _save(
	data: GameData, group: int, number: int, cell: Vector2i, encounters: bool
) -> Gen2SaveData:
	var mon := Gen2SaveMon.new()
	mon.species = 155
	mon.level = 5
	mon.hp = 20
	mon.nickname = String(data.species(155).get("name", ""))
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.player_name = "BENCH"
	save.party = [mon]
	var snapshot := Gen2WorldSnapshot.new()
	snapshot.map_id = Vector2i(group, number)
	snapshot.player_cell = cell
	snapshot.world_state.set_wild_encounters_off(not encounters)
	save.world = snapshot
	return save

const STEP_FRAMES: int = 16
const HEADINGS: Array[int] = [Gen2Button.DOWN, Gen2Button.RIGHT, Gen2Button.UP, Gen2Button.LEFT]

var _turns: int = 0


func _plan(map: Gen2WorldMap, from: Vector2i, frames: int) -> void:
	var entries: Array = []
	var at: Vector2i = from
	var heading: int = 0
	var leg: int = 0
	var frame: int = SETTLE_FRAMES + 1
	while frame < frames:
		var step: Vector2i = Gen2Button.vector(HEADINGS[heading])
		if leg >= _span or not Staging.walkable(map, at + step):
			for turn: int in HEADINGS.size():
				heading = (heading + 1) % HEADINGS.size()
				if Staging.walkable(map, at + Gen2Button.vector(HEADINGS[heading])):
					break
			_turns += 1
			leg = 0
			continue
		at += step
		leg += 1
		for spent: int in STEP_FRAMES:
			entries.append({
				"frame": frame, "kind": "hold", "button": HEADINGS[heading],
			})
			frame += 1
	_screen.replay_input(entries)


func _process(delta: float) -> bool:
	if _screen == null:
		return true
	_frames += 1
	if _frames == 1:
		return false
	if _frames == 2:
		if Vector2i(_screen.world_snapshot().get("map", Vector2i(-1, -1))) == Vector2i(-1, -1):
			print("no world: is the starting cell inside the map?")
			quit(1)
			return true
		_screen.advance_frames(SETTLE_FRAMES)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_measure_viewports(root)
		_plan(_map, _start, int((_seconds + WARMUP_SECONDS + 20.0) * 60.0))
		_screen.set_process(true)
		return false
	if _warmup_usec == 0:
		_warmup_usec = Time.get_ticks_usec()
	if float(Time.get_ticks_usec() - _warmup_usec) / 1000000.0 < WARMUP_SECONDS:
		return false
	if _started_usec == 0:
		_started_usec = Time.get_ticks_usec()
	_sample(delta)
	if float(Time.get_ticks_usec() - _started_usec) / 1000000.0 < _seconds:
		return false
	_capture()
	_report()
	quit(0)
	return true


func _capture() -> void:
	if _shot.is_empty():
		return
	var image: Image = root.get_texture().get_image()
	if image == null or image.save_png(_shot) != OK:
		print("could not write %s" % _shot)
		return
	print("shot       %s" % _shot)


func _sample(delta: float) -> void:
	if _renderer == null:
		_renderer = Staging.find_renderer(_screen)
	var refresh_ms: float = 0.0
	if _time_refresh:
		if _renderer != null:
			var at: int = Time.get_ticks_usec()
			_renderer.refresh()
			refresh_ms = float(Time.get_ticks_usec() - at) / 1000.0
	var snapshot: Dictionary = _screen.world_snapshot()
	var map: Vector2i = snapshot.get("map", Vector2i(-1, -1))
	if bool(snapshot.get("battle_active", false)):
		_battle_frames += 1
	_maps[map] = int(_maps.get(map, 0)) + 1
	_samples.append({
		"ms": delta * 1000.0,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"render_cpu_ms": _render_time(false),
		"render_gpu_ms": _render_time(true),
		"refresh_ms": refresh_ms,
		"cell": snapshot.get("player_cell", Vector2i.ZERO),
		"map": map,
		"building": _renderer != null and bool(_renderer.get("_building")),
	})


func _report() -> void:
	var ms: Array = []
	for row: Dictionary in _samples:
		ms.append(float(row["ms"]))
	ms.sort()
	var count: int = ms.size()
	print("")
	print("frames     %d over %.1f s" % [count, _seconds])
	print("maps       %s" % str(_maps))
	var visited: Dictionary = {}
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-1, -1)
	for row: Dictionary in _samples:
		var cell: Vector2i = row["cell"]
		visited[cell] = true
		low = low.min(cell)
		high = high.max(cell)
	print("turns      %d planned" % _turns)
	print("battles    %d frames of %d" % [_battle_frames, count])
	print("cells      %d visited, %s to %s" % [visited.size(), str(low), str(high)])
	print("vsync      %s" % (
		"DISABLED" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
		else "ON, every figure below is the monitor's"
	))
	print("fps        %.1f mean" % (1000.0 / _mean(ms)))
	print("frame ms   mean %.2f  median %.2f  p95 %.2f  p99 %.2f  max %.2f" % [
		_mean(ms), _at(ms, 0.5), _at(ms, 0.95), _at(ms, 0.99), ms[count - 1],
	])
	if _time_refresh:
		var refreshes: Array = _column("refresh_ms")
		refreshes.sort()
		print("refresh ms mean %.3f  median %.3f  p95 %.3f  max %.3f" % [
			_mean(refreshes), _at(refreshes, 0.5), _at(refreshes, 0.95),
			refreshes[refreshes.size() - 1],
		])
	var render_cpu: Array = _column("render_cpu_ms")
	var render_gpu: Array = _column("render_gpu_ms")
	render_cpu.sort()
	render_gpu.sort()
	print("render cpu mean %.2f  median %.2f  p95 %.2f  max %.2f" % [
		_mean(render_cpu), _at(render_cpu, 0.5), _at(render_cpu, 0.95),
		render_cpu[render_cpu.size() - 1],
	])
	print("render gpu mean %.2f  median %.2f  p95 %.2f  max %.2f" % [
		_mean(render_gpu), _at(render_gpu, 0.5), _at(render_gpu, 0.95),
		render_gpu[render_gpu.size() - 1],
	])
	print("draws      mean %d  max %d" % [
		int(_mean(_column("draws"))), int(_column("draws").max()),
	])
	print("triangles  mean %d  max %d" % [
		int(_mean(_column("primitives"))), int(_column("primitives").max()),
	])
	print("objects    mean %d  max %d" % [
		int(_mean(_column("objects"))), int(_column("objects").max()),
	])
	print("video MB   %.1f" % _column("video_mb").max())
	print("static MB  %.1f" % _column("static_mb").max())
	var building: int = 0
	for row: Dictionary in _samples:
		if bool(row["building"]):
			building += 1
	print("building   %d frames of %d, %.0f%% of them over the median" % [
		building, count, 100.0 * float(_over_median_while_building()) / float(maxi(building, 1)),
	])
	print("worst      %s" % str(_worst(6)))
	if not _out.is_empty():
		var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		if file == null:
			print("could not write %s" % _out)
			return
		file.store_string(JSON.stringify({
			"seconds": _seconds, "samples": _samples,
		}, "  "))
		print("wrote %s" % _out)


func _measure_viewports(node: Node) -> void:
	var viewport: Viewport = node as Viewport
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_viewports.append(viewport)
	for child: Node in node.get_children():
		_measure_viewports(child)


func _render_time(gpu: bool) -> float:
	var total: float = 0.0
	for viewport: Viewport in _viewports:
		var rid: RID = viewport.get_viewport_rid()
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid) if gpu \
			else RenderingServer.viewport_get_measured_render_time_cpu(rid)
	return total


func _over_median_while_building() -> int:
	var ms: Array = _column("ms")
	ms.sort()
	var median: float = _at(ms, 0.5)
	var out: int = 0
	for row: Dictionary in _samples:
		if bool(row["building"]) and float(row["ms"]) > median:
			out += 1
	return out


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


func _worst(count: int) -> Array:
	var order: Array = _samples.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ms"]) > float(b["ms"]))
	var out: Array = []
	for index: int in mini(count, order.size()):
		out.append("%.1fms at %s" % [float(order[index]["ms"]), str(order[index]["cell"])])
	return out
