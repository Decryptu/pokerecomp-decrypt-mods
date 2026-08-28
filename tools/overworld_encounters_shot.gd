extends SceneTree

## Photographs the host's forced shiny visible encounter through either world
## renderer.

const WINDOW_SIZE := Vector2i(1152, 648)
const SETTLE_FRAMES: int = 60
const CAPTURE_ON: int = 120

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0
var _clean: bool = false
var _scale: int = 1
var _natural: bool = false
var _glow: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <game> <group> <map> <out.png> [renderer] [cell x] [cell y]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_output_path = args[3]
	if Gen2ToolPath.refuses(_output_path):
		quit(2)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	if not host.world_renderer_ids().has(&"voxel3d"):
		host.discover()
		host.load_discovered()
	var renderer: StringName = StringName(args[4]) if args.size() > 4 else &"gen2"
	if renderer != &"gen2":
		var selected: Dictionary = host.select_view(renderer)
		if not bool(selected.get("ok", false)):
			print("could not select renderer %s: %s" % [renderer, selected])
			quit(1)
			return
	print("renderer %s, failures %s" % [renderer, host.failures()])
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = int(args[1])
	_screen.map_number = int(args[2])
	if args.size() > 6 and int(args[5]) >= 0 and int(args[6]) >= 0:
		_screen.start_cell = Vector2i(int(args[5]), int(args[6]))
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)
	var options: PackedStringArray = args[8].split(",", false) if args.size() > 8 \
		else PackedStringArray()
	_clean = options.has("clean")
	_natural = options.has("natural")
	_glow = options.has("glow")
	for option: String in options:
		if option.begins_with("x"):
			_scale = maxi(int(option.substr(1)), 1)


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	if _clean:
		_chrome().hide_chrome(_screen)
	if _frames == 2:
		_screen.advance_frames(SETTLE_FRAMES)
		if not _natural:
			if _glow:
				_screen.preview_visible_encounter_glow()
			else:
				_screen.preview_visible_encounter()
		var args: PackedStringArray = OS.get_cmdline_user_args()
		var population: Variant = _screen.get("_encounters")
		print("population: %d entries" % [
			population.entries().size() if population != null else -1,
		])
		var pulse_frames: int = int(args[7]) if args.size() > 7 else 0
		for pulse_frame: int in pulse_frames:
			_screen.advance_frame()
			var encounters: Variant = _screen.get("_encounters")
			if encounters != null and not encounters.pulse_sprites().is_empty():
				print("pulse frame %d: %d sprites" % [
					pulse_frame + 1, encounters.pulse_sprites().size(),
				])
		if pulse_frames > 0:
			var after: Variant = _screen.get("_encounters")
			print("population after %d frames: %d entries" % [
				pulse_frames, after.entries().size() if after != null else -1,
			])
	if _frames < CAPTURE_ON:
		return false
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
