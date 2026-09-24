extends SceneTree

## Photographs the Achievements mod's two surfaces, through the real world
## screen, with the mod itself raising them.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"achievements"
const DEFAULT_WINDOW := Vector2i(800, 720)

const THUMBNAIL_SIZE := Vector2i(1280, 720)

const JOHTO_MAP := Vector2i(10, 7)
const JOHTO_CELL := Vector2i(5, 2)
const KANTO_MAP := Vector2i(0, 54)
const KANTO_CELL := Vector2i(4, 2)
const DEFAULT_BADGES: int = 0
const REGION_BADGES: int = 8

const STAGE_ON: int = 6
const SHUTTER_WAIT: int = 18
const FRAME_CAP: int = 240
const SETTLE_FRAMES: int = 6

var _screen: Gen2WorldScreen = null
var _out: String = ""
var _kind: StringName = &"notice"
var _badges: int = DEFAULT_BADGES
var _thumbnail: bool = false
var _frames: int = 0
var _waited: int = 0
var _staged: bool = false
var _framed: bool = false
var _view: StringName = &""
var _map := JOHTO_MAP
var _cell := JOHTO_CELL
var _data: GameData = null
var _kanto: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <cartridge> <out.png> [kind] [badges] [group,number] [cell] [thumbnail]")
		quit(2)
		return
	_out = args[1]
	if PokeToolPath.refuses(_out):
		quit(2)
		return
	_kind = StringName(args[2]) if args.size() > 2 else &"notice"
	if _kind != &"notice" and _kind != &"page":
		print("kind is notice or page, not ", _kind)
		quit(2)
		return
	_badges = clampi(int(args[3]) if args.size() > 3 else DEFAULT_BADGES, 0, REGION_BADGES)
	for index: int in range(6, args.size()):
		match String(args[index]):
			"thumbnail":
				_thumbnail = true
			"framed":
				_framed = true
			_:
				if String(args[index]).begins_with("view="):
					_view = StringName(String(args[index]).substr(5))
					continue
				print("no flag called ", args[index])
				quit(2)
				return

	Gen2ModHost.reset()
	_data = GameData.open_argument(args[0])
	if _data == null:
		print("no cache for ", args[0])
		quit(1)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	if not Staging.mod_loaded(host, _data, MOD_ID):
		quit(1)
		return
	_kanto = host.generation() == RomRegistry.GEN1
	_map = _pair(args[4] if args.size() > 4 else "", KANTO_MAP if _kanto else JOHTO_MAP)
	_cell = _pair(args[5] if args.size() > 5 else "", KANTO_CELL if _kanto else JOHTO_CELL)
	if not _view.is_empty():
		print("view       ", String(_view), " ", str(host.select_view(_view)))

	if _framed:
		Gen2OptionsStore.current().screen_fill = false
	DisplayServer.window_set_size(DEFAULT_WINDOW)
	root.set_content_scale_size(DEFAULT_WINDOW)
	root.size = DEFAULT_WINDOW
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = _map.x
	_screen.map_number = _map.y
	_screen.start_cell = _cell
	_screen.encounter_seed = 1
	_screen.set_data(_data)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	if _screen == null:
		return true
	_screen.set_process(false)
	_frames += 1
	if _frames < STAGE_ON:
		return false
	if _frames == STAGE_ON:
		_stage()
		return false
	if not _staged:
		return false
	_waited += 1
	if _waited < SHUTTER_WAIT:
		return false
	var image: Image = PokeToolPath.capture(root)
	if image == null:
		quit(1)
		return true
	if not _write(image):
		quit(1)
		return true
	print("wrote ", _out, " (", image.get_width(), "x", image.get_height(),
		"), ", _kind, " over map ", _screen.map_group, ",", _screen.map_number)
	quit(0)
	return true


func _stage() -> void:
	_screen.hide_debug_readout()
	var save: Gen2SaveData = _screen.active_save()
	if save == null:
		save = Gen2SaveStore.create_development_save(_data, 0)
		_screen.set_save(save)
	Gen2ModHost.instance().activate_save(save)
	var world: Gen2WorldAPI = _screen.world()
	if world == null or world.state == null:
		print("the screen opened no world")
		quit(1)
		return
	if not _standable(world):
		return
	_face_the_leader()
	for badge: int in _badges:
		world.state.set_engine_flag(_badge_flag(badge))
	_spend_map_banner()
	if _kind == &"page":
		_screen.advance_frames(SETTLE_FRAMES)
		_screen.call("_open_mod_page", MOD_ID)
		_screen.advance_frame()
		_staged = true
		return
	world.state.set_engine_flag(_badge_flag(mini(_badges, REGION_BADGES - 1)))
	_staged = _raise_notice()


## The region's badge [param index], 0 to 7, as the engine flag it is on this
## cartridge.
func _badge_flag(index: int) -> int:
	if _kanto:
		return Gen2WorldState.gen1_badge_flag(index)
	return Gen2WorldState.badge_flag(index, Gen2WorldState.is_crystal_profile(_data))


func _standable(world: Gen2WorldAPI) -> bool:
	var map: Gen2WorldMap = world.current_map
	if map == null:
		print("the screen opened no map")
		quit(1)
		return false
	if _cell.x < 0 or _cell.y < 0 \
		or _cell.x >= map.collision_width or _cell.y >= map.collision_height:
		print("cell ", _cell, " is off map ", _screen.map_group, ",",
			_screen.map_number, ", which is ", map.collision_width, "x",
			map.collision_height, " cells")
		quit(1)
		return false
	if not Gen2WorldCollision.is_walkable(world.collision_code_at(_cell)):
		print("cell ", _cell, " on map ", _screen.map_group, ",",
			_screen.map_number, " is not a cell the player can stand on")
		quit(1)
		return false
	for object: Dictionary in map.events.get("objects", []):
		if Vector2i(int(object.get("x", -1)), int(object.get("y", -1))) == _cell:
			print("cell ", _cell, " is where one of the map's own people stands")
			quit(1)
			return false
	return true


func _face_the_leader() -> void:
	_screen.move_up()
	_screen.advance_frames(SETTLE_FRAMES)


func _spend_map_banner() -> void:
	for frame: int in FRAME_CAP:
		if frame >= SETTLE_FRAMES and _screen.map_name_sign_passes() <= 0:
			return
		_screen.advance_frame()


func _raise_notice() -> bool:
	for _frame: int in FRAME_CAP:
		_screen.advance_frame()
		var passes: int = _screen.map_name_sign_passes()
		if passes > 0 and passes < Gen2WorldAPI.MAP_NAME_SIGN_PASSES - 1:
			_screen.advance_frames(SETTLE_FRAMES)
			return true
	print("no banner was raised in ", FRAME_CAP, " frames")
	quit(1)
	return false


func _pair(text: String, fallback: Vector2i) -> Vector2i:
	var parts: PackedStringArray = text.split(",", false)
	if parts.size() != 2:
		return fallback
	return Vector2i(int(parts[0]), int(parts[1]))


func _write(image: Image) -> bool:
	if not _thumbnail:
		if image.save_png(_out) != OK:
			print("could not write ", _out)
			return false
		return true
	if image.get_width() > THUMBNAIL_SIZE.x or image.get_height() > THUMBNAIL_SIZE.y:
		print("a ", image.get_width(), "x", image.get_height(),
			" shot does not fit ", THUMBNAIL_SIZE)
		return false
	var canvas := Image.create(
		THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, false, image.get_format()
	)
	canvas.fill(Color.WHITE)
	@warning_ignore("integer_division")
	var at := Vector2i(
		int((THUMBNAIL_SIZE.x - image.get_width()) / 2),
		int((THUMBNAIL_SIZE.y - image.get_height()) / 2)
	)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	if canvas.save_webp(_out, true) != OK:
		print("could not write ", _out)
		return false
	return true
