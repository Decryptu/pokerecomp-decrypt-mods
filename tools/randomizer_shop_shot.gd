extends SceneTree

## Photographs one shop's shelf through the world screen's own counter, under
## the randomizer's run for a seed, or vanilla for a seed below zero: the way a
## patched site is seen rather than counted.
##   -- <cartridge> <out.png> [seed|-1] [map_group,map_number] [cell_x,cell_y] [facing]

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"randomizer"
const WINDOW := Vector2i(640, 576)
const BOX_PRESSES: int = 8
const SETTLE_FRAMES: int = 6
const SHUTTER_ON: int = 18

## Pewter's mart on Kanto and Cherrygrove's on Johto, the cell across the
## counter from the clerk, and the way the clerk lies from it.
const COUNTERS: Dictionary = {
	RomRegistry.GEN1: {
		"map": Vector2i(0, 56), "cell": Vector2i(2, 5), "facing": Gen2WorldSprite.FACING_LEFT,
	},
	RomRegistry.GEN2: {
		"map": Vector2i(26, 3), "cell": Vector2i(2, 5), "facing": Gen2WorldSprite.FACING_LEFT,
	},
}

var _screen: Gen2WorldScreen = null
var _facing: int = 0
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <cartridge> <out.png> [seed|-1] [group,number] [x,y] [facing]")
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
	_activate(data, int(args[2]) if args.size() > 2 else -1)
	var counter: Dictionary = COUNTERS[data.generation]
	var map: Vector2i = _pair(args, 3, counter["map"])
	var cell: Vector2i = _pair(args, 4, counter["cell"])
	_facing = int(args[5]) if args.size() > 5 else int(counter["facing"])
	DisplayServer.window_set_size(WINDOW)
	root.set_content_scale_size(WINDOW)
	root.size = WINDOW
	_screen = (load("res://game/world/world_screen.tscn") as PackedScene).instantiate()
	_screen.map_group = map.x
	_screen.map_number = map.y
	_screen.start_cell = cell
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


## A development save carrying the run, activated so the shared overlay holds
## the seed's patches before the map opens. A seed below zero activates none.
func _activate(data: GameData, seed_value: int) -> void:
	if seed_value < 0:
		return
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	var options: GDScript = load("user://mods/randomizer/options.gd")
	var spec: PackedStringArray = ["seed:%d" % seed_value]
	for key: StringName in options.TOGGLES:
		spec.append("%s:1" % key)
	Staging.new().create_save(Gen2ModHost.instance(), MOD_ID, ",".join(spec), save)
	Gen2ModHost.instance().activate_save(save)


func _pair(args: PackedStringArray, index: int, fallback: Vector2i) -> Vector2i:
	if args.size() <= index:
		return fallback
	var parts: PackedStringArray = args[index].split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else fallback


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


## Talk across the counter and take BUY.
func _stage() -> void:
	_screen._world.player_facing = _facing
	_screen.interact()
	_clear_boxes()
	_screen.press_button(PokeButton.A)
	_clear_boxes()
	_screen.advance_frames(SETTLE_FRAMES)


## `MartDialog`'s welcome and the BUY/SELL/QUIT loop, pressed through.
func _clear_boxes() -> void:
	for _press: int in BOX_PRESSES:
		var service: Gen2WorldServiceScreen = _screen.get("_service_host")
		if service == null or StringName(service.get("_mart_stage")) \
			!= Gen2WorldServiceScreen.MART_MESSAGE:
			return
		_screen.press_button(PokeButton.A)
