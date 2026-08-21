extends SceneTree

## Photographs the follower on a real map, through the game's own world screen.
##
## The probe beside this one proves the follower is where it should be; this is
## the other half, and the half three defects in this repository were only ever
## visible in. It drives the production screen: a save with a party is injected,
## the player is walked, and the picture is whatever the host drew, follower
## included.
##
## Rendering needs a display, so this cannot run headless, and mods only load
## when they are asked for, so `--mods` is not optional:
##
## A seventh argument is the view: the host's own `gen2` by default, or a
## registered renderer's id, which is how the same walk is photographed in the
## diorama. An eighth, `pet`, turns the player around at the end of the walk and
## presses A, which is the picture the heart is only ever in.
##
## The eighth is comma-separated: `clean` photographs the cartridge screen alone
## rather than the development harness around it, which is what a picture meant
## to be looked at rather than debugged wants, and `x4` enlarges it by whole
## pixels.
##
##   Godot --path <pokerecomp> --mods -s tools/follower_shot.gd -- \
##       crystal 26 1 <out.png> [species] [steps] [renderer id] [pet,clean,x4]

const WINDOW_SIZE := Vector2i(1152, 648)
## Hardware frames one plain step is drawn over, which is the host's own count.
const STEP_FRAMES: int = 8
## The frame the picture is taken on, counted from the start of the last step.
## Halfway, so the pair is caught mid-stride rather than standing still.
const CAUGHT_AT: int = 4
## Frames spent before anything is asked of the screen, so a map's own entry
## script has run and the player can be walked.
const SETTLE_FRAMES: int = 60
## A press in a direction the player is not already facing turns them and spends
## nothing else, which is the host's own STEP_FRAMES_TURN. It is the whole reason
## a trailing follower can be faced at all: a second press would step onto it.
const TURN_FRAMES: int = 4
## The real frame the picture is taken on, well past the one the walk was staged
## on. Long enough for a renderer that builds its view over several frames
## rather than in one, which the diorama does on purpose.
const CAPTURE_ON: int = 150
## Real frames between the press and the picture. THE PRESS IS STAGED LAST, not
## with the walk: a heart is up for sixty WORLD frames and this tool spends world
## frames by hand, so a press staged beside the walk is a hundred and forty real
## frames from the capture and what is photographed is whatever was painted
## last. Six frames is a settled renderer and a bubble that is certainly still
## up, and it makes the capture byte-identical run to run.
const PET_LEAD: int = 6

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _steps: int = 2
var _pet: bool = false
## Chrome off and the capture cropped to the cartridge frame, which is what a
## picture meant to be LOOKED AT wants and a debugging one does not.
var _clean: bool = false
## Whole-pixel enlargement of a clean capture, from an `x4` option.
var _scale: int = 1
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <game> <group> <map> <out.png> [species] [steps]")
		quit(2)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_output_path = args[3]
	var species: int = int(args[4]) if args.size() > 4 else 155
	_steps = int(args[5]) if args.size() > 5 else 2
	# Comma-separated, so `pet` alone still means what it always did.
	var options: PackedStringArray = args[7].split(",", false) if args.size() > 7 \
		else PackedStringArray()
	_pet = options.has("pet")
	_clean = options.has("clean")
	for option: String in options:
		if option.begins_with("x"):
			_scale = maxi(int(option.substr(1)), 1)

	# The screen collects the registered actors as it enters the tree, so the
	# mods have to be loaded before it is built. A tool run loads none by
	# itself: `--mods` is what puts them back, and this is where they land.
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host.world_actors().is_empty():
		host.discover()
		host.load_discovered()
	print("actors     %s, failures %s" % [
		str(host.world_actor_ids()), str(host.failures())
	])
	## R24 folded the two per-surface selectors into one view id, so this is
	## `select_view` and not the `select_world_renderer` that is gone.
	if args.size() > 6:
		print("view       %s" % str(host.select_view(StringName(args[6]))))

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = int(args[1])
	_screen.map_number = int(args[2])
	## Pinned so two captures of one map are one picture: the seed the screen
	## resolves is what a wandering NPC's own generator is built from.
	_screen.encounter_seed = 1
	_screen.set_data(data)
	_screen.set_save(_save(data, species))
	root.add_child(_screen)
	current_scene = _screen
	# The screen counts hardware frames off wall-clock delta. The frames below
	# are spent by hand, so what is photographed is a frame chosen here.
	_screen.set_process(false)


## A save carrying one Pokemon on its feet, which is all the follower reads:
## the world screen mirrors the party into `set_party_summary()` and the mod
## asks that for a species.
func _save(data: GameData, species: int) -> Gen2SaveData:
	var mon := Gen2SaveMon.new()
	mon.species = species
	mon.level = 5
	mon.hp = 20
	mon.nickname = String(data.species(species).get("name", ""))
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.player_name = "PROBE"
	save.party = [mon]
	return save


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	if _frames < 2:
		return false
	if _frames > 2:
		# Frames the engine spends drawing what the walk below left behind. The
		# screen's own frames are hardware frames and are spent by hand; these
		# are the real ones, and capturing before they are drawn photographs the
		# picture from before the walk.
		if _pet and _frames == CAPTURE_ON - PET_LEAD:
			_pet_the_follower()
		if _frames < CAPTURE_ON:
			return false
		return _capture()
	# The map's own entry script runs first, and the player cannot be walked
	# while one does, so the screen is settled before anything is asked of it.
	_screen.advance_frames(SETTLE_FRAMES)
	# Walk. The follower is under the player until the first step takes them
	# apart, so a picture of a standing player is a picture of nothing.
	for step: int in _steps:
		_screen.move_down()
		var last: bool = step == _steps - 1
		_screen.advance_frames(STEP_FRAMES if _pet or not last else CAUGHT_AT)
		print("step %d    player cell %s" % [
			step + 1, str((_screen.world_snapshot() as Dictionary).get("player_cell")),
		])
	return false


## The two presses petting is: one that turns the player to face the cell they
## just left, which is where the follower is standing, and one on A.
##
## The turn is what makes this reachable at all. A follower stands on a cell the
## player can always walk into, so a second press in that direction would step
## onto it rather than face it; `player_input_move`'s own turn branch spends four
## frames and a facing and nothing else.
func _pet_the_follower() -> void:
	_screen.move_up()
	_screen.advance_frames(TURN_FRAMES)
	print("petted    %s" % ("yes" if _screen.interact() else "NO, nothing answered"))
	_screen.advance_frames(CAUGHT_AT)


func _capture() -> bool:
	var image: Image = _chrome().capture(_screen, _scale) if _clean else null
	if image == null:
		image = root.get_texture().get_image()
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
