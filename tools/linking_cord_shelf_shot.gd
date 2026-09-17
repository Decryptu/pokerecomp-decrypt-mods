extends SceneTree

## Photographs the cord on its shelf, through the world screen's own counter:
## Goldenrod Dept Store 2F's gadget clerk or Celadon Dept Store 4F's stone
## clerk, BUY chosen and the cursor walked down to the cord.
##   -- <cartridge> <out.png> [downs]

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"linking_cord"
const WINDOW := Vector2i(640, 576)
const BOX_PRESSES: int = 8
const SETTLE_FRAMES: int = 6
const SHUTTER_ON: int = 18

## Map, the cell in front of the counter, the way the clerk lies from it, and
## how many rows down the cord sits after the cartridge's own shelf.
const COUNTERS: Dictionary = {
	RomRegistry.GEN1: {
		"map": Vector2i(0, 125), "cell": Vector2i(5, 5),
		"facing": Gen2WorldSprite.FACING_DOWN, "downs": 5,
	},
	RomRegistry.GEN2: {
		"map": Vector2i(11, 12), "cell": Vector2i(11, 6),
		"facing": Gen2WorldSprite.FACING_RIGHT, "downs": 8,
	},
}

var _screen: Gen2WorldScreen = null
var _counter: Dictionary = {}
var _out: String = ""
var _downs: int = 0
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <cartridge> <out.png> [downs]")
		quit(2)
		return
	if PokeToolPath.refuses(args[1]):
		quit(2)
		return
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	if not Staging.mod_loaded(Gen2ModHost.instance(), data, MOD_ID):
		quit(1)
		return
	_out = args[1]
	_counter = COUNTERS[data.generation]
	_downs = int(args[2]) if args.size() > 2 else int(_counter["downs"])
	DisplayServer.window_set_size(WINDOW)
	root.set_content_scale_size(WINDOW)
	root.size = WINDOW
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = (_counter["map"] as Vector2i).x
	_screen.map_number = (_counter["map"] as Vector2i).y
	_screen.start_cell = _counter["cell"]
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	_frames += 1
	_screen.set_process(false)
	if _frames == 2:
		_stage()
	if _frames < SHUTTER_ON:
		return false
	_screen.hide_debug_readout()
	var image: Image = PokeToolPath.capture(root)
	if image == null or image.save_png(_out) != OK:
		print("could not write %s" % _out)
		quit(1)
		return true
	print("wrote %s" % _out)
	quit(0)
	return true


## Talk across the counter, take BUY, walk down the shelf.
func _stage() -> void:
	_screen._world.player_facing = int(_counter["facing"])
	_screen.interact()
	_clear_boxes()
	_screen.press_button(PokeButton.A)
	_clear_boxes()
	for _down: int in _downs:
		_screen.press_button(PokeButton.DOWN)
	_screen.advance_frames(SETTLE_FRAMES)


## `MartDialog`'s welcome and the BUY/SELL/QUIT loop, pressed through.
func _clear_boxes() -> void:
	for _press: int in BOX_PRESSES:
		var service: Gen2WorldServiceScreen = _screen.get("_service_host")
		if service == null or StringName(service.get("_mart_stage")) \
			!= Gen2WorldServiceScreen.MART_MESSAGE:
			return
		_screen.press_button(PokeButton.A)
