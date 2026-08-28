extends SceneTree

## Photographs the host's own evolution sequence, one named phase at a time.

const FRAME_LIMIT: int = 1200

const SCREEN := Vector2i(160, 144)

const STAGE_ON: int = 2
const CAPTURE_ON: int = 4

var _out: String = ""
var _scale: int = 1
var _frame: SubViewport = null
var _screen: Gen2EvolutionScreen = null
var _wanted: int = -1
var _offset: int = 0
var _spent: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 5:
		print("usage: -- <game> <out.png> <old species> <new species> <phase>"
			+ " [offset frames] [scale]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	var old_species: int = int(args[2])
	var new_species: int = int(args[3])
	var old_record: Dictionary = data.species(old_species)
	if old_record.is_empty() or data.species(new_species).is_empty():
		print("no species %d or %d on %s" % [old_species, new_species, args[0]])
		quit(1)
		return
	_wanted = _phase_named(args[4])
	if _wanted < 0:
		print("no phase named %s" % args[4])
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	_offset = maxi(int(args[5]) if args.size() > 5 else 0, 0)
	_scale = maxi(int(args[6]) if args.size() > 6 else 1, 1)

	_frame = SubViewport.new()
	_frame.size = SCREEN
	_frame.transparent_bg = false
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)

	_screen = Gen2EvolutionScreen.new()
	_screen.set_context(data, [{
		"index": 0,
		"old_species": old_species,
		"new_species": new_species,
		"level": 30,
		"evolving_name": String(old_record.get("name", "")),
		"statused": false,
		"forced": true,
	}])
	_frame.add_child(_screen)


func _process(_delta: float) -> bool:
	_spent += 1
	if _spent == STAGE_ON and not _run():
		return true
	if _spent < CAPTURE_ON:
		return false
	var image: Image = _frame.get_texture().get_image()
	if _scale > 1:
		image.resize(SCREEN.x * _scale, SCREEN.y * _scale, Image.INTERPOLATE_NEAREST)
	if image.save_png(_out) != OK:
		print("could not write %s" % _out)
		quit(1)
		return true
	print("wrote %s" % _out)
	return true


func _run() -> bool:
	var reached: int = -1
	for frames: int in FRAME_LIMIT:
		if _screen.phase() == _wanted:
			if reached < 0:
				reached = frames
			if frames - reached >= _offset:
				print("phase %d reached at frame %d, held %d" % [_wanted, reached, _offset])
				return true
		_screen.advance_frame()
	print("phase %d never reached in %d frames" % [_wanted, FRAME_LIMIT])
	quit(1)
	return false


func _phase_named(name: String) -> int:
	var key: String = name.strip_edges().to_upper()
	var table: Dictionary = Gen2EvolutionScreen.Phase
	return int(table[key]) if table.has(key) else -1
