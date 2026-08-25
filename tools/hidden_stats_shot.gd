extends SceneTree

## Photographs the fourth stats page, through the real party screen.
##
## The host's own `tools/preview_party.gd` can reach a mod page, but it
## registers the SHIPPED EXAMPLE's page to do it, so this mod's page lands fifth
## behind one that is not ours and the indicator row counts a page a player of
## this mod would never see. Here only this mod is loaded, so the page is the
## fourth and the indicators say four.
##
## The Pokemon is staged rather than taken from the development save, whose
## party is perfect fifteens and no training at all: a picture of a page whose
## whole subject is the numbers a player cannot otherwise see should have
## numbers in it.
##
##   Godot --path <pokerecomp> -s tools/hidden_stats_shot.gd -- \
##       <game> <out.png> [species] [level] [scale]
##
## Rendering needs a display.

## The party screen is a window-resolution panel, so the window is sized to a
## whole multiple of the hardware screen and the panel fills it exactly. Nothing
## is cropped afterwards and nothing is scaled by halves.
const SCREEN := Vector2i(160, 144)
const WINDOW_SCALE: int = 4

## STATS out of the party member's own submenu, then three page turns: pink,
## green, blue, and the fourth is this mod's.
const ROUTE: Array[int] = [
	Gen2Button.A, Gen2Button.A,
	Gen2Button.RIGHT, Gen2Button.RIGHT, Gen2Button.RIGHT,
]

## Frames before the shutter, which is `preview_party.gd`'s own count.
const CAPTURE_ON: int = 6

## Neither perfect nor flat, and shiny is avoided: a shiny DV set is four fixed
## numbers and reads as a bug in a screenshot rather than as a rarity.
const DVS: int = 0xB7D9
## Part-trained, so the column shows what training looks like partway rather
## than at nothing or at the cap.
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

	# The window itself, not just the viewport: this panel is drawn at window
	# resolution, so anything else letterboxes it inside a frame of project grey
	# that then has to be cropped back off.
	DisplayServer.window_set_size(SCREEN * WINDOW_SCALE)
	root.set_content_scale_size(SCREEN * WINDOW_SCALE)
	root.size = SCREEN * WINDOW_SCALE
	var party := Gen2PartyScreen.new()
	party.set_context(data, save, true)
	_screen = party
	root.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_scene = _screen


## One Pokemon the cartridge would accept, with hidden halves worth printing.
## Built through [Gen2BattleMon.create] so the stats, moves and HP are the
## cartridge's rather than invented here, then given the DVs and the training
## the page exists to show.
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
