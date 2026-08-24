extends SceneTree

## What a frame COSTS while the player is walking, through the game's own screen.
##
## Every performance figure this repository carried before this was taken from a
## still: `tools/cost.gd` resolves and emits with nothing rendering, and
## `tools/shot.gd` holds six frames and photographs one. Neither can see what a
## walk costs, and a walk is where the cost is: the actors are rebuilt every
## frame, the atlas animates, and the mesh window recentres out from under the
## player every few cells.
##
## Drives the production world screen with a held direction, lets it run at the
## real frame rate with the vertical sync off, and records one row per drawn
## frame. Prints the distribution rather than a mean, because a walk's problem is
## the frames at the top of it: a 4 ms mean with a 40 ms ninety-ninth percentile
## is a stutter every second and reads as smooth in an average.
##
## Rendering needs a display, so this cannot run headless, and mods only load
## when they are asked for, so `--mods` is not optional:
##
##   Godot --path <pokerecomp> --mods -s tools/walk_bench.gd -- \
##       <game> <group> <map> [key=value ...]
##
## Everything after the map is named, because a benchmark grows arguments and a
## run is worth being able to read six months later:
##
##   seconds=10      how long to record for, after the warmup
##   view=voxel3d    the registered view, or the host's own `gen2`
##   cell=19,33      where the walk starts, in walk cells
##   span=8          how many cells one heading covers before the walk turns
##   window=1920x1080  the window the picture is drawn at
##   out=walk.json   every sample, one row per frame
##   shot=walk.png   the last frame, saved
##   encounters=1    wild encounters on
##   refresh=1       time the renderer's own `refresh()` as well
##   set=distance:24,scale:3   the view's own settings, for the length of the run
##   static=far_trees:0,dof_mode:0   the view's own tuning statics
##
## SHOOT THE RUN. A benchmark reports numbers and nothing in them says what was
## in the frame: a run that reads as expensive geometry can be a city with no
## trees in it, or a lake, and the cell was picked by a search rather than by
## anyone looking. `shot=` saves the last frame beside the figures.
##
## THE CELL IS PICKED when none is named: the map's centre is a building on most
## towns and a wall on several routes, and a run started inside one records a
## player who never moves with every other line of the report intact. See
## [method _open_ground].
##
## WILD ENCOUNTERS ARE OFF unless `encounters=1`, and that is
## not a convenience: a battle owns the world for as long as it lasts, so a run
## through grass measures the battle screen for a third of its frames and reports
## it as a walk. The flag is `Gen2WorldState.set_wild_encounters_off`, the
## cartridge's own, so a run with them on is a plain walk with nothing suppressed.
## The report names how many frames a battle took either way.
##
## THE RENDER TIMES ARE THE MEASUREMENT AND THE FRAME TIME IS NOT, on a machine
## whose compositor paces what it presents: macOS hands back a flat 6.94 ms for
## every frame that fits inside a 144 Hz refresh, with the vertical sync reported
## DISABLED, so a mean frame time there is a count of how often a frame missed
## rather than what one cost. `viewport_set_measure_render_time` is the renderer
## own stopwatch, one for the CPU spent building the frame and one for the GPU
## spent drawing it, and neither is paced by anything. Both are summed over the
## root and every SubViewport under it, which is where a 3D view draws.
##
## `Performance.TIME_PROCESS` IS NOT READ HERE and the omission is deliberate:
## against 1.4 ms frames in the flat view it answers around 10 ms, and against
## 5.5 ms frames in this one around 12, which is neither the frame nor any part
## of it. What a script costs is measured by calling it, which is what the
## REFRESH option below does.
##
## REFRESH adds a column: the renderer's own `refresh()` timed once more per
## sampled frame, which is the per-frame CPU a view spends standing the actors up
## and framing the camera, apart from everything the engine does around it. It is
## an EXTRA call, so the frame times of a run carrying it are its own and must
## not be compared with a run without it.
##
## `static` is the other half of the same idea and reaches the rungs that are not
## settings yet: `renderer.gd` carries `solid_cells`, `far_trees`, `dof_mode` and
## `dof_radius` as static vars while they are being tuned, and turning one off
## for a run is how a subsystem's share of the frame is priced. The name is the
## static's own, on `world/renderer.gd`, and the value is a number.
##
## `set` puts the view's own settings where the run wants them,
## `distance:24,scale:3` and so on, by key and VALUE as `options.gd` declares
## them. It is how a cost is attributed rather than guessed at: the same walk at
## two render scales says whether a frame is bound by what it draws or by how
## much of it there is. The settings are the player's own file, so whatever was
## there is put back when the run ends, including after a failure.
##
## The view id is the host's own `gen2` when it is left out, which is the
## baseline every voxel figure should be read against.

const WINDOW_SIZE := Vector2i(1280, 720)
## Frames spent before anything is asked of the screen, so a map's own entry
## script has run and the player can be walked.
const SETTLE_FRAMES: int = 60
## Seconds spent walking before the first row is recorded.
##
## SECONDS AND NOT FRAMES, because the plan is spent in world time: a warmup of
## 180 drawn frames is 1.8 seconds of the walk in a view drawing at a hundred and
## 0.9 in one drawing at two hundred, so the two runs start recording at
## different places on the same path and are comparing different pictures.
##
## Three of them, because a fresh process pays for its own shader compilation and
## for whatever the driver caches: three consecutive runs of one configuration
## measured 9.72, 4.55 and 4.17 ms at the median before this was raised, in that
## order, which is a process warming up and not a difference in the view.
const WARMUP_SECONDS: float = 3.0
## How far the walk runs before it turns round, in walk cells. Wide enough that
## the mesh window recentres inside it (`renderer.gd:_recentre_window` allows a
## third of the draw distance) and short enough to stay on one map.
const SPAN_CELLS_DEFAULT: int = 24

var _screen: Gen2WorldScreen = null
var _out: String = ""
## Where the last frame is saved, if anywhere. See the `shot` option.
var _shot: String = ""
var _seconds: float = 10.0
var _frames: int = 0
var _samples: Array = []
var _started_usec: int = 0
## When the warmup began. See [constant WARMUP_SECONDS].
var _warmup_usec: int = 0
var _maps: Dictionary = {}
var _span: int = SPAN_CELLS_DEFAULT
## Frames drawn while a battle owned the world, which is a walk that stopped.
var _battle_frames: int = 0
## The active renderer, found in the tree rather than asked of the screen, and
## whether its `refresh()` is being timed. See the REFRESH option above.
var _renderer: Node = null
var _time_refresh: bool = false
## Every viewport whose render time is being measured, root first.
var _viewports: Array[Viewport] = []
## The map and the cell the plan is built from. See [method _plan].
var _map: Gen2WorldMap = null
var _start := Vector2i.ZERO


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <game> <group> <map> [seconds=] [view=] [cell=x,y] [span=]"
			+ " [window=WxH] [out=] [encounters=1] [refresh=1] [set=key:value,...]")
		quit(2)
		return
	var named: Dictionary = _named(args)
	var data: GameData = GameData.open(StringName(args[0]))
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
	var guard: GDScript = load("%s/out_path.gd"
		% (get_script() as Script).resource_path.get_base_dir())
	for path: String in [_out, _shot]:
		if not path.is_empty() and guard.refuses(path):
			quit(2)
			return
	_span = int(named.get("span", str(SPAN_CELLS_DEFAULT)))
	_time_refresh = named.has("refresh")
	var window: Vector2i = _size(String(named.get("window", "")))
	var wanted := Vector2i(map.collision_width / 2, map.collision_height / 2)
	if String(named.get("cell", "")).contains(","):
		var parts: PackedStringArray = String(named["cell"]).split(",")
		wanted = Vector2i(int(parts[0]), int(parts[1]))
	var start: Vector2i = _open_ground(map, wanted)
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
		_apply_statics(String(named["static"]))
	if named.has("set"):
		_apply_options(host, view, String(named["set"]))
	if not host.failures().is_empty():
		print("failures   %s" % str(host.failures()))

	root.set_content_scale_size(window)
	root.size = window
	DisplayServer.window_set_size(window)
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = group
	_screen.map_number = number
	_screen.start_cell = start
	## Pinned so two runs walk past the same wandering people.
	_screen.encounter_seed = 1
	_screen.set_data(data)
	_screen.set_save(_save(data, group, number, start, named.has("encounters")))
	root.add_child(_screen)
	current_scene = _screen
	## The settle is spent by hand and the walk is not: the screen counts its own
	## hardware frames off wall-clock delta from here on, which is what makes the
	## drawn frames below the ones a player would get.
	_screen.set_process(false)


## The `key=value` arguments past the map, which is every argument this tool has
## but the three that name a place. Positional beyond that was ten slots deep and
## three of them were flags whose meaning could not be read off a command line.
func _named(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(3, args.size()):
		var pair: String = args[index]
		var at: int = pair.find("=")
		if at <= 0:
			continue
		out[pair.substr(0, at)] = pair.substr(at + 1)
	return out


## A `WxH` window, or the default.
##
## THE WINDOW IS PART OF THE RESULT on a machine whose compositor paces what it
## presents: at 1280x720 this view finishes inside a 144 Hz refresh and every
## frame reads as exactly 6.94 ms whatever it actually cost. A window big enough
## to miss the refresh is the only way a wall clock says anything here, and it is
## also the window the cost was always going to be argued at.
func _size(text: String) -> Vector2i:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2 or int(parts[0]) <= 0 or int(parts[1]) <= 0:
		return WINDOW_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))


## The mod script the tuning statics live on. Loaded by path rather than reached
## through the host, which hands back an instance and not the script.
const RENDERER := "user://mods/voxel3d/world/renderer.gd"


## Sets each `name:value` static on the renderer script for the length of the
## process. Statics are per script rather than per instance, so this is set once
## and reaches the renderer the screen goes on to build.
func _apply_statics(spec: String) -> void:
	var script: GDScript = load(RENDERER)
	if script == null:
		print("no renderer script at %s" % RENDERER)
		return
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var name: String = parts[0].strip_edges()
		var text: String = parts[1].strip_edges()
		var value: Variant = float(text) if text.contains(".") else int(text)
		if script.get(name) is bool:
			value = bool(value)
		script.set(name, value)
		print("static     %s = %s" % [name, str(script.get(name))])


## The settings this run changed and what they were, so the player's own file is
## what it was when the run is over. `set_option` writes it: a benchmark that
## leaves a draw distance behind is a benchmark that changed the game.
var _restore: Dictionary = {}


## Sets each `key=value` for the length of the run, on the mod the view names.
## The value is parsed as a number, which every setting this view has is.
func _apply_options(host: Gen2ModHost, id: StringName, spec: String) -> void:
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var key := StringName(parts[0].strip_edges())
		var text: String = parts[1].strip_edges()
		var value: Variant = float(text) if text.contains(".") else int(text)
		_restore[key] = host.option(id, key)
		print("option     %s = %s %s" % [
			String(key), str(value), str(host.set_option(id, key, value)),
		])
	_restore_id = id


var _restore_id: StringName = &""


## Puts the settings back. Called on every exit from the run, since a tool that
## only tidies up when it succeeds is a tool that leaves the file wrong on the
## run that failed.
func _finalize() -> void:
	if _restore.is_empty():
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	for key: StringName in _restore:
		if _restore[key] != null:
			host.set_option(_restore_id, key, _restore[key])


## How many walkable cells a start has to be able to reach for the walk to be
## worth measuring. Under this the player paces a doorway and every figure in the
## report is a still's.
const ROOM_CELLS: int = 24
## How far the search for one reaches from the cell that was asked for.
const SEARCH_CELLS: int = 40


## The nearest cell to [param wanted] standing in a room the walk can cover.
##
## PICKED RATHER THAN TAKEN, because a map's centre is a building on most towns
## and a wall on several routes, and a run started inside one reports a walk that
## never moved with every other line intact. Nearest first, and a region under
## [constant ROOM_CELLS] is refused so the answer is not the inside of a shed.
func _open_ground(map: Gen2WorldMap, wanted: Vector2i) -> Vector2i:
	var refused: Dictionary = {}
	for radius: int in SEARCH_CELLS:
		for offset: Vector2i in _ring(radius):
			var cell: Vector2i = wanted + offset
			if refused.has(cell) or not _walkable(map, cell):
				continue
			var region: Dictionary = _region(map, cell)
			if region.size() >= ROOM_CELLS:
				return cell
			refused.merge(region)
	return Vector2i.MAX


## The cells exactly [param radius] from the origin, which is what makes the
## search above nearest-first without sorting the whole map.
func _ring(radius: int) -> Array:
	if radius == 0:
		return [Vector2i.ZERO]
	var out: Array = []
	for step: int in radius * 2 + 1:
		var at: int = step - radius
		out.append(Vector2i(at, -radius))
		out.append(Vector2i(at, radius))
		if absi(at) != radius:
			out.append(Vector2i(-radius, at))
			out.append(Vector2i(radius, at))
	return out


## The walkable cells reachable from one, capped: the answer only has to be
## bigger than [constant ROOM_CELLS] and a route is thousands of cells.
func _region(map: Gen2WorldMap, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty() and seen.size() < ROOM_CELLS * 4:
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = at + step
			if seen.has(next) or not _walkable(map, next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


## The map's own permission byte, which is a fact about the map rather than about
## a live world: no world has to be opened to read it.
func _walkable(map: Gen2WorldMap, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.collision_width \
			or cell.y >= map.collision_height:
		return false
	return Gen2WorldCollision.is_walkable(map.collision_at(cell.x, cell.y))


## A save carrying one Pokemon, which is what the screen needs to open at all,
## and a world snapshot, which is the only way to hand the world a state of this
## tool's choosing: a screen given a save without one builds its own.
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


## Hardware frames one plain step is drawn over, which is the host's own count:
## `MaxOverworldDelay` is two frames a pass and a step is eight passes.
const STEP_FRAMES: int = 16
## The four directions a plan may take, in the order it prefers them.
const HEADINGS: Array[int] = [Gen2Button.DOWN, Gen2Button.RIGHT, Gen2Button.UP, Gen2Button.LEFT]

## How many times the plan changed direction, which is how boxed in the walk was.
var _turns: int = 0


## THE WALK IS PLANNED OFF THE MAP AND REPLAYED PER WORLD FRAME, and both halves
## of that are what make two runs comparable.
##
## Steering per DRAWN frame, which this tool did first, is not reproducible: the
## screen banks hardware frames off wall-clock delta, so a poll on a drawn frame
## lands on a different world frame in a view that draws at 300 fps and one that
## draws at 100, and the two walks are somewhere else within a second. Measured
## on map 7,17: three runs of one configuration covered (22,18) to (30,27),
## (24,7) to (24,17) and (23,12) to (33,22), which is three different pictures
## and three unrelated frame times.
##
## `replay_input` applies its log from INSIDE the frame pump, one entry per world
## frame, so a plan is spent identically whatever the frame rate. And the plan
## itself comes off the collision permissions rather than off what the run
## discovers, so it is the same before a change and after one.
func _plan(map: Gen2WorldMap, from: Vector2i, frames: int) -> void:
	var entries: Array = []
	var at: Vector2i = from
	var heading: int = 0
	var leg: int = 0
	var frame: int = SETTLE_FRAMES + 1
	while frame < frames:
		var step: Vector2i = Gen2Button.vector(HEADINGS[heading])
		if leg >= _span or not _walkable(map, at + step):
			# The next heading that has anywhere to go, and the same one again if
			# none of them has: a plan that stands still is still a plan, and the
			# report's own cell count is what says so.
			for turn: int in HEADINGS.size():
				heading = (heading + 1) % HEADINGS.size()
				if _walkable(map, at + Gen2Button.vector(HEADINGS[heading])):
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
		## A cell outside the map's own collision grid is refused by
		## `open_snapshot`, and the screen answers with a load failure rather than
		## a world: every line of the report below would then be measuring an
		## error page. `tools/maps.gd` prints each map's size in TILES, which is
		## twice the cell.
		if Vector2i(_screen.world_snapshot().get("map", Vector2i(-1, -1))) == Vector2i(-1, -1):
			print("no world: is the starting cell inside the map?")
			quit(1)
			return true
		# The map's own entry script runs first, and the player cannot be walked
		# while one does.
		_screen.advance_frames(SETTLE_FRAMES)
		## Asserted here as well as at startup: the window does not exist when
		## `_initialize` runs, and a vertical sync set on a window that is not
		## there yet is silently the platform's default on the one that arrives.
		## Half the runs of this tool were locked to the monitor's refresh, which
		## reads as a flat 6.94 ms in every column and looks like a result.
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


## The last frame of the run, which is what says the walk was through a wood
## rather than across a car park.
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
		_renderer = _find_renderer(_screen)
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
		# Whether the view was rebuilding its mesh on this frame, which is the one
		# thing about a spike a wall clock cannot say. `_building` is this
		# repository's own field on this repository's own renderer.
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
	## THE CELLS ARE PART OF THE RESULT, not a diagnostic: a run whose player was
	## walled in after two steps is a run measuring a still, and it reads exactly
	## like a good one in every other line.
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
	# THE FRAMES AT THE TOP ARE THE FINDING, so they are named rather than
	# summarised: a walk's stutter is a rebuild landing on one frame, and the
	# cell it landed on is what says which rebuild it was.
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


## The registered renderer, which is a node in the screen's own tree carrying a
## script out of `user://mods/`. Found by that rather than asked of the screen:
## which node holds it is the host's business and there is no accessor for it,
## and a tool has no business reaching into a private field to find out.
## Turns the renderer's own stopwatch on for every viewport in the tree. Kept as
## a list because the answer has to be re-read each frame and walking the tree
## per frame would be a cost of the tool's own.
func _measure_viewports(node: Node) -> void:
	var viewport: Viewport = node as Viewport
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_viewports.append(viewport)
	for child: Node in node.get_children():
		_measure_viewports(child)


## The whole frame's render time, in milliseconds, summed over every viewport.
## A 3D view draws into a SubViewport and the window only composites it, so the
## root's own number alone is nearly zero however dear the picture is.
func _render_time(gpu: bool) -> float:
	var total: float = 0.0
	for viewport: Viewport in _viewports:
		var rid: RID = viewport.get_viewport_rid()
		total += RenderingServer.viewport_get_measured_render_time_gpu(rid) if gpu \
			else RenderingServer.viewport_get_measured_render_time_cpu(rid)
	return total


func _find_renderer(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.begins_with("user://mods/") \
			and node.has_method("refresh"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_renderer(child)
		if found != null:
			return found
	return null


## How many of the frames spent rebuilding the mesh cost more than a median one,
## which is the whole question a sliced build asks: a slice inside the budget is
## invisible and one over it is the stutter.
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


## The value at a fraction of the sorted run, which is a percentile taken off the
## nearest sample rather than interpolated: the run is thousands of frames and
## the difference is under a tenth of a millisecond.
func _at(sorted: Array, fraction: float) -> float:
	return float(sorted[clampi(int(float(sorted.size() - 1) * fraction), 0, sorted.size() - 1)])


## The dearest frames, each as the millisecond it cost and the cell the player
## stood on while it was drawn.
func _worst(count: int) -> Array:
	var order: Array = _samples.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ms"]) > float(b["ms"]))
	var out: Array = []
	for index: int in mini(count, order.size()):
		out.append("%.1fms at %s" % [float(order[index]["ms"]), str(order[index]["cell"])])
	return out
