extends SceneTree

## Photographs the line a Catch Combo adds, in the place the mod adds it: the
## battle box, after `Gotcha!` and before the nickname prompt.
##
##   godot --path <pokerecomp> --resolution 800x720 \
##       -s tools/catch_combo_shot.gd -- \
##       <game> <output.png> [species] [level] [presses] [thumbnail]
##
## THE RESOLUTION IS PART OF THE COMMAND, for the reason
## `tools/shiny_charm_shot.gd` gives: 800x720 is the hardware's 160x144 at a
## whole times five and any other size shears the art.
##
## Nothing in the picture is staged but the throw. The tool loads the installed
## mods, stands a wild battle up, hands the screen a ball and the resolved throw
## the world host would have handed it, and presses A through the shakes. The
## capture then publishes `caught` on the battle channel, the mod counts it and
## asks for its line, and the host prints it in the box the battle owns. So the
## wording, the pacing and the place it lands are the mod's and the host's.
##
## The eleven catches in front of it are published before the battle is up,
## where a requested line is dropped rather than queued, so the combo the box
## reads is a combo of twelve and the box is only ever printed once.
##
## `presses` is how many A presses walk the capture's own run. Seven leaves the
## mod's box up: six reach the Gotcha line and one more takes it away. It is an
## argument because that count is a fact about the host's message run rather
## than about this mod, and one press past it opens the naming prompt.
##
## Needs a display, since it renders.

## The white field a mod's thumbnail is, the hardware picture centred on it
## rather than stretched to fill.
const THUMBNAIL_SIZE := Vector2i(1280, 720)
## RATTATA on an early route: the Pokemon somebody actually ends up with a dozen
## of, which is what a combo is.
const DEFAULT_SPECIES: int = 19
const DEFAULT_LEVEL: int = 4
const DEFAULT_PRESSES: int = 7
## The catches in front of the one photographed. Long enough that the box reads
## a combo past the first rung, so the picture is of one worth something.
const CATCHES_BEFORE: int = 11
## Three shakes and a click, which is `GetPokeBallWobble`'s own best answer.
const WOBBLES: int = 3
const BALLS: int = 5
## Any fixed number, for the reason `shiny_charm_shot.gd` fixes its own: the
## picture must not move between two runs of one command.
const SEED: int = 20260827
## A ceiling on the frames one stage of the sequence is walked for, so a change
## in the host's pacing costs a picture rather than a hang.
const MAX_STEPS: int = 4096
const SETTLE_FRAMES: int = 4
const DRAW_FRAMES: int = 3

var _screen: Gen2BattleScreen = null
var _out: String = ""
var _species: int = DEFAULT_SPECIES
var _level: int = DEFAULT_LEVEL
var _presses: int = DEFAULT_PRESSES
var _thumbnail: bool = false
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: catch_combo_shot.gd -- <game> <output.png> "
			+ "[species] [level] [presses] [thumbnail]"
		)
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	# An EMPTY argument keeps the default, so a later one is reachable without
	# restating the ones in front of it.
	if args.size() > 2 and not args[2].is_empty():
		_species = int(args[2])
	if args.size() > 3 and not args[3].is_empty():
		_level = int(args[3])
	if args.size() > 4 and not args[4].is_empty():
		_presses = int(args[4])
	if args.size() > 5:
		if args[5] != "thumbnail":
			push_error("Unknown flag %s" % args[5])
			quit(1)
			return
		_thumbnail = true

	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(data.id)
	host.discover()
	host.load_discovered()
	for _catch: int in CATCHES_BEFORE:
		_publish_catch()

	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(data)
	_screen.set_random_seed(SEED)
	root.add_child(_screen)
	current_scene = _screen
	# Taken away every frame, not once: Godot turns processing back on for a node
	# whose script has a `_process`, and the screen counts hardware frames off its
	# own deltas, so a frame this driver did not drive is a frame that depends on
	# how fast the machine ran.
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	_screen.set_process(false)
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _frames == SETTLE_FRAMES:
		if not _stage():
			quit(1)
			return true
		return false
	if _frames < SETTLE_FRAMES + DRAW_FRAMES:
		return false
	return _write(_out)


## The wild battle, the throw, and the box left holding the line the mod adds.
func _stage() -> bool:
	if not _screen.start_world_battle({"values": {
		"kind": &"wild",
		"pokemon": _species,
		"level": _level,
	}}):
		push_error("Could not stage a wild battle against species %d" % _species)
		return false
	while _screen.intro_running():
		_screen.advance_frame()
	_settle_entrance()
	var ball: int = Gen2WorldPartyHost.ITEM_POKE_BALL
	_screen.set_capture_balls([ball], {ball: BALLS})
	if not bool(_screen.begin_capture().get("ok", false)):
		push_error("The ball selector would not open")
		return false
	if not bool(_screen.throw_capture_ball().get("ok", false)):
		push_error("The ball was not thrown")
		return false
	# The world host's own answer: the catch is resolved in front of the
	# animation, which reads the wobbles back rather than rolling them.
	_screen.complete_capture({
		"ok": true,
		"caught": true,
		"ball": ball,
		"quantity": BALLS - 1,
		"wobbles": WOBBLES,
		"destination": {"destination": &"party"},
	})
	# The shakes and the click are the box's own messages, so they are walked the
	# way the player walks them: whatever is animating is spent, and then one
	# page is taken away. Stopping on the last leaves the Gotcha line up, which
	# is the one frame the naming prompt has not opened over.
	var left: int = _presses
	for _step: int in MAX_STEPS:
		if _screen.frames_running():
			_screen.advance_frame()
			continue
		if left <= 0:
			break
		_screen.finish()
		_screen.advance()
		left -= 1
	_screen.finish()
	return true


## The capture the battle publishes, which is what the mod counts. Spent before
## the battle exists, so the eleven in front of the photographed one cost no box.
func _publish_catch() -> void:
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {
		"type": Gen2Battle.CAUGHT,
		"species": _species, "level": _level, "dvs": 0, "shiny": false,
		"ball": Gen2WorldPartyHost.ITEM_POKE_BALL, "method": &"grass",
		"map_group": -1, "map_number": -1, "battle_type": 0,
		"destination": &"party", "tutorial": false, "contest": false,
	})


## Everything `DoBattle` spends before its first menu, so a throw driven after
## this is a throw rather than the entrance still running.
func _settle_entrance() -> void:
	for _step: int in MAX_STEPS:
		if not _screen.frames_running() and not _screen.entrance_running():
			return
		if _screen.frames_running():
			_screen.advance_frame()
			continue
		_screen.finish()
		_screen.advance()


func _write(path: String) -> bool:
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	if _thumbnail and not _write_thumbnail(image, path):
		quit(1)
		return true
	quit(0)
	return true


## The picture centred on the white field at the size it was taken. A grab
## bigger than the field is refused rather than scaled: the fix is the window.
func _write_thumbnail(image: Image, path: String) -> bool:
	if image.get_width() > THUMBNAIL_SIZE.x or image.get_height() > THUMBNAIL_SIZE.y:
		push_error("A %dx%d picture does not fit %s. Run at --resolution 800x720." % [
			image.get_width(), image.get_height(), str(THUMBNAIL_SIZE),
		])
		return false
	var canvas := Image.create(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, false, image.get_format())
	canvas.fill(Color.WHITE)
	@warning_ignore("integer_division")
	var at := Vector2i(
		int((THUMBNAIL_SIZE.x - image.get_width()) / 2),
		int((THUMBNAIL_SIZE.y - image.get_height()) / 2)
	)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	var out: String = path.trim_suffix(".png") + ".webp"
	# Lossless: a WebP that guessed at these colours would be a picture of the
	# cartridge's palette rather than the palette.
	if canvas.save_webp(out, false) != OK:
		push_error("Could not write %s" % out)
		return false
	print("Wrote %s (%dx%d)" % [out, THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y])
	return true
