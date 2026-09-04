extends SceneTree

## How much a 3D view's picture MOVES per drawn frame while the player walks,
## through the game's own screen. A frame that moves nothing is a still, and a
## row of stills is what SMOOTH SCROLL exists to replace.

const Staging: GDScript = preload("staging.gd")
const SETTLE_FRAMES: int = 60
const WARMUP_FRAMES: int = 60
const DEFAULT_FRAMES: int = 500
const DEFAULT_FPS: int = 120
const STILL: float = 0.0001

var _screen: Gen2WorldScreen = null
var _renderer: Node = null
var _camera: Camera3D = null
var _frames: int = 0
var _wanted: int = DEFAULT_FRAMES
var _last := Vector3.INF
var _moves: Array[float] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <cache> <group> <map> [cell=x,y] [view=voxel3d] [fps=]"
			+ " [frames=] [hardware=1] [mods=all|none|<id>,...] [set=key:value,...]")
		quit(2)
		return
	var named: Dictionary = Staging.named(args)
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return
	var group: int = int(args[1])
	var map: Gen2WorldMap = data.world_map(group, int(args[2]))
	if map == null:
		print("no map %s,%s" % [args[1], args[2]])
		quit(1)
		return

	_wanted = maxi(int(named.get("frames", str(DEFAULT_FRAMES))), 1)
	var smooth: bool = not named.has("hardware")
	Gen2OptionsStore.current().smooth_scroll = smooth
	var host: Gen2ModHost = Gen2ModHost.instance()
	print("mods       %s" % str(Staging.load_mods(host, String(named.get("mods", "all")))))
	var view := StringName(named.get("view", "voxel3d"))
	print("view       %s %s" % [String(view), str(host.select_view(view))])
	print("scrolling  %s" % ("SMOOTH" if smooth else "hardware pixels"))

	var start: Vector2i = Staging.open_ground(map, _wanted_cell(named, map))
	if start == Vector2i.MAX:
		print("no walkable room on map %s,%s" % [args[1], args[2]])
		quit(1)
		return
	print("map        %s,%s at %s" % [args[1], args[2], str(start)])
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = group
	_screen.map_number = map.number
	_screen.start_cell = start
	_screen.set_data(data)
	_screen.set_save(_save(data, group, map.number, start))
	root.add_child(_screen)
	current_scene = _screen
	Engine.max_fps = maxi(int(named.get("fps", str(DEFAULT_FPS))), 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


static func _wanted_cell(named: Dictionary, map: Gen2WorldMap) -> Vector2i:
	var text: String = String(named.get("cell", ""))
	if not text.contains(","):
		return Vector2i(map.collision_width / 2, map.collision_height / 2)
	var parts: PackedStringArray = text.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


## Neither a wild nor a sighting: both stop the walk, and every frame after one
## measures a text box standing still rather than a map moving.
func _save(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2SaveData:
	var mon := Gen2SaveMon.new()
	mon.species = 155
	mon.level = 5
	mon.hp = 20
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.player_name = "BENCH"
	save.party = [mon]
	var snapshot := Gen2WorldSnapshot.new()
	snapshot.map_id = Vector2i(group, number)
	snapshot.player_cell = cell
	snapshot.world_state.set_wild_encounters_off(true)
	snapshot.world_state.set_trainer_sightings_off(true)
	save.world = snapshot
	return save


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _frames == SETTLE_FRAMES:
		return _begin()
	if _frames < SETTLE_FRAMES + WARMUP_FRAMES:
		return false
	var here: Vector3 = _camera.global_position
	if _last != Vector3.INF:
		_moves.append(_last.distance_to(here))
	_last = here
	if _moves.size() < _wanted:
		return false
	_report()
	quit(0)
	return true


## The walk is one held direction, since what is measured is the picture between
## two frames and not where it got to. Enough frames for it are queued at once.
func _begin() -> bool:
	_renderer = Staging.find_renderer(_screen)
	if _renderer == null or not _renderer.has_method("stage"):
		print("the view draws no 3D stage; there is no camera to measure")
		quit(2)
		return true
	_camera = _renderer.stage().camera
	_screen.advance_frames(SETTLE_FRAMES)
	var entries: Array = []
	for spent: int in _wanted:
		entries.append({"frame": spent, "kind": "hold", "button": PokeButton.RIGHT})
	_screen.replay_input(entries)
	return false


func _report() -> void:
	var still: int = 0
	var total: float = 0.0
	var most: float = 0.0
	for move: float in _moves:
		still += 1 if move < STILL else 0
		total += move
		most = maxf(most, move)
	print("")
	print("drawn      %d frames at %d fps" % [_moves.size(), Engine.max_fps])
	print("still      %d of them moved the picture not at all" % still)
	print("moved      mean %.3f world pixels, worst %.3f" % [
		total / float(_moves.size()), most,
	])
