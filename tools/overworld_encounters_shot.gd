extends SceneTree

## Photographs the host's forced shiny visible encounter through either world
## renderer. This exercises the production palette and pulse paths on a real
## cartridge without waiting for a natural shiny roll.
##
## A ninth argument is comma-separated options: `clean` photographs the
## cartridge screen alone rather than the development harness around it, `x4`
## enlarges it by whole pixels, `natural` leaves the population to the mod
## instead of forcing the shiny preview, which is the only way to see the map as
## a player meets it, and `glow` forces the host's glowing preview instead of
## the shiny one, which is how the excellent-DV mark is looked at without
## waiting for a wild in the top one and a half percent of DV rolls.
##
##   Godot --path <pokerecomp> --mods -s tools/overworld_encounters_shot.gd -- \
##       crystal 24 3 <out.png> [gen2|voxel3d] [cell x] [cell y] [pulse frames] \
##
## A negative cell keeps the map's own start, which is how a later argument is
## reached without moving the player.
##       [clean,x4,natural]

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
		## R24 folded the two per-surface selectors into one view id, so this is
		## `select_view` and not the `select_world_renderer` that is gone.
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
	## A negative cell leaves the map's own start alone, which is how the later
	## arguments are reached without teleporting the player: `0 0` is a real cell
	## and on most maps it is inside the border, so passing it as a placeholder
	## put the player in a wall and the preview had nowhere to stand.
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
	# EVERY FRAME, because the screen puts its own caption and hint back as the
	# walk moves the player: hiding them once at setup left both in the picture.
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
		# A PICTURE WITH NO POKEMON IN IT IS OTHERWISE SILENT, and twice the map
		# rather than the population was what was wrong.
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
		# A map is left to turn over by spending frames here, and a route that
		# emptied instead of refilling would photograph as an ordinary picture of
		# grass. So the count is printed again after the walk, on the same rule
		# the one above it exists for.
		if pulse_frames > 0:
			var after: Variant = _screen.get("_encounters")
			print("population after %d frames: %d entries" % [
				pulse_frames, after.entries().size() if after != null else -1,
			])
	if _frames < CAPTURE_ON:
		return false
	var image: Image = _chrome().capture(_screen, _scale) if _clean else null
	if image == null:
		# The window, which is where a view drawing at window resolution is, and
		# where the whole harness is when this is not a clean capture.
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


## The sibling helper, loaded by this script's own directory rather than by an
## absolute path, since no path from one machine belongs in a tracked file.
func _chrome() -> GDScript:
	return load("%s/clean_frame.gd" % (get_script() as Script).resource_path.get_base_dir())
