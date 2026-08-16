extends SceneTree

## Photographs the host's forced shiny visible encounter through either world
## renderer. This exercises the production palette and pulse paths on a real
## cartridge without waiting for a natural shiny roll.
##
##   Godot --path <pokerecomp> --mods -s tools/overworld_encounters_shot.gd -- \
##       crystal 24 3 <out.png> [gen2|voxel3d] [cell x] [cell y] [pulse frames]

const WINDOW_SIZE := Vector2i(1152, 648)
const SETTLE_FRAMES: int = 60
const CAPTURE_ON: int = 120

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <game> <group> <map> <out.png> [renderer] [cell x] [cell y]")
		quit(2)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_output_path = args[3]
	var host: Gen2ModHost = Gen2ModHost.instance()
	if not host.world_renderer_ids().has(&"voxel3d"):
		host.discover()
		host.load_discovered()
	var renderer: StringName = StringName(args[4]) if args.size() > 4 else &"gen2"
	if renderer != &"gen2":
		var selected: Dictionary = host.select_world_renderer(renderer)
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
	if args.size() > 6:
		_screen.start_cell = Vector2i(int(args[5]), int(args[6]))
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	if _frames == 2:
		_screen.advance_frames(SETTLE_FRAMES)
		_screen.preview_visible_encounter()
		var args: PackedStringArray = OS.get_cmdline_user_args()
		var pulse_frames: int = int(args[7]) if args.size() > 7 else 0
		for pulse_frame: int in pulse_frames:
			_screen.advance_frame()
			var encounters: Variant = _screen.get("_encounters")
			if encounters != null and not encounters.pulse_sprites().is_empty():
				print("pulse frame %d: %d sprites" % [
					pulse_frame + 1, encounters.pulse_sprites().size(),
				])
	if _frames < CAPTURE_ON:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		print("could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true
