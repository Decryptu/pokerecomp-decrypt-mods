extends SceneTree

## Photographs one party member's stats page through the real party screen,
## under the randomizer's run for a seed, or vanilla for a seed below zero.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"randomizer"
const SCREEN := Vector2i(160, 144)
const WINDOW_SCALE: int = 4

const OPEN_STATS: Array[int] = [PokeButton.A, PokeButton.A]
const TURN_PAGE: int = PokeButton.A
const GEN1_TURN: int = PokeButton.A
const GEN2_TURN: int = PokeButton.RIGHT
const DEFAULT_SPECIES: int = 4
const DEFAULT_LEVEL: int = 10
const CAPTURE_ON: int = 6
const ALGORITHM: int = 2

var _out: String = ""
var _scale: int = 1
var _route: Array[int] = []
var _screen: Control = null
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [seed|-1] [page] [species] [level] [scale]")
		quit(2)
		return
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_out = args[1]
	if PokeToolPath.refuses(_out):
		quit(2)
		return
	_scale = maxi(int(args[6]) if args.size() > 6 else 1, 1)
	var save: Gen2SaveData = _run(data, args)
	if save == null:
		quit(1)
		return
	_route = OPEN_STATS.duplicate()
	var turn: int = GEN1_TURN if data.generation == RomRegistry.GEN1 else GEN2_TURN
	for _page: int in maxi(int(args[3]) if args.size() > 3 else 1, 1) - 1:
		_route.append(turn)
	DisplayServer.window_set_size(SCREEN * WINDOW_SCALE)
	root.set_content_scale_size(SCREEN * WINDOW_SCALE)
	root.size = SCREEN * WINDOW_SCALE
	var party := Gen2PartyScreen.new()
	party.set_context(data, save, true)
	_screen = party
	root.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_scene = _screen


## The mod loaded and a save activated under it, holding the one staged mon,
## built AFTER the run is applied so it comes off the randomized row the game
## would build it from. Null with a reason printed.
func _run(data: GameData, args: PackedStringArray) -> Gen2SaveData:
	if not Staging.mod_loaded(Gen2ModHost.instance(), data, MOD_ID):
		return null
	var seed_value: int = int(args[2]) if args.size() > 2 else -1
	var species: int = int(args[4]) if args.size() > 4 else DEFAULT_SPECIES
	var level: int = clampi(int(args[5]) if args.size() > 5 else DEFAULT_LEVEL, 1, 100)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		print("no development save for %s" % data.id)
		return null
	if seed_value >= 0:
		save.set_mod_data(MOD_ID, {"algorithm": ALGORITHM, "settings": _settings(seed_value)})
	Gen2ModHost.instance().activate_save(save)
	var mon: Gen2SaveMon = _stage(data, species, level)
	if mon == null:
		print("no species %d on %s" % [species, data.id])
		return null
	save.party = [mon]
	return save


func _settings(seed_value: int) -> Dictionary:
	var options: GDScript = load("user://mods/randomizer/options.gd")
	var out: Dictionary = options.settings(null)
	out["seed"] = seed_value
	return out


func _stage(data: GameData, species: int, level: int) -> Gen2SaveMon:
	var battle_mon: Gen2BattleMon = Gen2BattleMon.create(
		data, species, level, data.moves_at_level(species, level)
	)
	if battle_mon == null:
		return null
	return Gen2SaveBattleAdapter.from_battle_mon(battle_mon)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < CAPTURE_ON:
		return false
	if _frames == CAPTURE_ON:
		for button: int in _route:
			_screen.handle_button(button)
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	if _scale != WINDOW_SCALE:
		image.resize(
			SCREEN.x * _scale, SCREEN.y * _scale, Image.INTERPOLATE_NEAREST
		)
	if image.save_png(_out) != OK:
		print("could not write %s" % _out)
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [_out, image.get_width(), image.get_height()])
	quit(0)
	return true
