extends SceneTree

## Photographs the follower on a real map, through the game's own world screen.

const WINDOW_SIZE := Vector2i(1152, 648)
const STEP_FRAMES: int = 8
const CAUGHT_AT: int = 4
const SETTLE_FRAMES: int = 60
const TURN_FRAMES: int = 4
const CAPTURE_ON: int = 150
const PET_LEAD: int = 6

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _steps: int = 2
var _pet: bool = false
var _clean: bool = false
var _scale: int = 1
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <game> <group> <map> <out.png> [species] [steps]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_output_path = args[3]
	if PokeToolPath.refuses(_output_path):
		quit(2)
		return
	var species: int = int(args[4]) if args.size() > 4 else 155
	_steps = int(args[5]) if args.size() > 5 else 2
	var options: PackedStringArray = args[7].split(",", false) if args.size() > 7 \
		else PackedStringArray()
	_pet = options.has("pet")
	_clean = options.has("clean")
	for option: String in options:
		if option.begins_with("x"):
			_scale = maxi(int(option.substr(1)), 1)

	var host: Gen2ModHost = Gen2ModHost.instance()
	if host.world_actors().is_empty():
		host.discover()
		host.load_discovered()
	print("actors     %s, failures %s" % [
		str(host.world_actor_ids()), str(host.failures())
	])
	if args.size() > 6:
		print("view       %s" % str(host.select_view(StringName(args[6]))))

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = int(args[1])
	_screen.map_number = int(args[2])
	_screen.encounter_seed = 1
	_screen.set_data(data)
	_screen.set_save(load(
		"%s/staging.gd" % (get_script() as Script).resource_path.get_base_dir()
	).party_save(data, str(species)))
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	if _clean:
		_chrome().hide_chrome(_screen)
	if _frames < 2:
		return false
	if _frames > 2:
		if _pet and _frames == CAPTURE_ON - PET_LEAD:
			_pet_the_follower()
		if _frames < CAPTURE_ON:
			return false
		return _capture()
	_screen.advance_frames(SETTLE_FRAMES)
	for step: int in _steps:
		_screen.move_down()
		var last: bool = step == _steps - 1
		_screen.advance_frames(STEP_FRAMES if _pet or not last else CAUGHT_AT)
		print("step %d    player cell %s" % [
			step + 1, str((_screen.world_snapshot() as Dictionary).get("player_cell")),
		])
	return false


func _pet_the_follower() -> void:
	_screen.move_up()
	_screen.advance_frames(TURN_FRAMES)
	print("petted    %s" % ("yes" if _screen.interact() else "NO, nothing answered"))
	_screen.advance_frames(CAUGHT_AT)


func _capture() -> bool:
	var image: Image = _chrome().capture(_screen, _scale) if _clean else null
	if image == null:
		image = root.get_texture().get_image()
		if _clean and _scale > 1:
			image.resize(
				image.get_width() * _scale, image.get_height() * _scale,
				Image.INTERPOLATE_NEAREST
			)
	var error: Error = image.save_png(_output_path)
	if error != OK:
		print("could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true


func _chrome() -> GDScript:
	return load("%s/clean_frame.gd" % (get_script() as Script).resource_path.get_base_dir())
