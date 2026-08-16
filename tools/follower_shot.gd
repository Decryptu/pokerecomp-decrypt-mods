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
##   Godot --path <pokerecomp> --mods -s tools/follower_shot.gd -- \
##       crystal 26 1 <out.png> [species] [steps]

const WINDOW_SIZE := Vector2i(1152, 648)
## Hardware frames one plain step is drawn over, which is the host's own count.
const STEP_FRAMES: int = 8
## The frame the picture is taken on, counted from the start of the last step.
## Halfway, so the pair is caught mid-stride rather than standing still.
const CAUGHT_AT: int = 4
## Frames spent before anything is asked of the screen, so a map's own entry
## script has run and the player can be walked.
const SETTLE_FRAMES: int = 60
## The real frame the picture is taken on, well past the one the walk was staged
## on, so the renderer has drawn what the walk left.
const CAPTURE_ON: int = 18

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _steps: int = 2
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
		_screen.advance_frames(STEP_FRAMES if step < _steps - 1 else CAUGHT_AT)
		print("step %d    player cell %s" % [
			step + 1, str((_screen.world_snapshot() as Dictionary).get("player_cell")),
		])
	return false


func _capture() -> bool:
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		print("could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true
