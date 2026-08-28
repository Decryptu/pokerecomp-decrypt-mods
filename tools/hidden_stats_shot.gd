extends SceneTree

## Photographs the fourth stats page, through the real party screen.

const SCREEN := Vector2i(160, 144)
const WINDOW_SCALE: int = 4

const ROUTE: Array[int] = [
	Gen2Button.A, Gen2Button.A,
	Gen2Button.RIGHT, Gen2Button.RIGHT, Gen2Button.RIGHT,
]

const CAPTURE_ON: int = 6

const DVS: int = 0xB7D9
const STAT_EXP: Dictionary = {
	"hp": 21760, "attack": 40960, "defense": 8704,
	"special": 15104, "speed": 33280,
}

var _out: String = ""
var _scale: int = 1
var _screen: Control = null
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [species] [level] [scale]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	var species: int = int(args[2]) if args.size() > 2 else 155
	var level: int = clampi(int(args[3]) if args.size() > 3 else 34, 1, 100)
	_scale = maxi(int(args[4]) if args.size() > 4 else 1, 1)

	Gen2ModHost.reset()
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(StringName(args[0]))
	host.discover()
	host.load_discovered()
	if not host.failures().is_empty():
		print("mods refused: %s" % str(host.failures()))
		quit(1)
		return

	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		print("no development save for %s" % args[0])
		quit(1)
		return
	var mon: Gen2SaveMon = _stage(data, species, level)
	if mon == null:
		print("no species %d on %s" % [species, args[0]])
		quit(1)
		return
	save.party = [mon]

	DisplayServer.window_set_size(SCREEN * WINDOW_SCALE)
	root.set_content_scale_size(SCREEN * WINDOW_SCALE)
	root.size = SCREEN * WINDOW_SCALE
	var party := Gen2PartyScreen.new()
	party.set_context(data, save, true)
	_screen = party
	root.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_scene = _screen


func _stage(data: GameData, species: int, level: int) -> Gen2SaveMon:
	var battle_mon: Gen2BattleMon = Gen2BattleMon.create(
		data, species, level, data.moves_at_level(species, level)
	)
	if battle_mon == null:
		return null
	var mon: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(battle_mon)
	mon.dvs = DVS
	mon.stat_exp = STAT_EXP.duplicate()
	return mon


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < CAPTURE_ON:
		return false
	if _frames == CAPTURE_ON:
		for button: int in ROUTE:
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
