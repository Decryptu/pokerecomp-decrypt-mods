extends SceneTree

## Photographs a wild battle against a SHINY Pokemon, at the frame the
## cartridge's own sparkle is over it.

const THUMBNAIL_SIZE := Vector2i(1280, 720)
const SHINY_DVS: int = (2 << 12) | (10 << 8) | (10 << 4) | 10
const DEFAULT_SPECIES: int = 215
const DEFAULT_LEVEL: int = 30
const DEFAULT_FRAME: int = 80
const DEFAULT_PLAYER: int = 157
const SEED: int = 20250825
const SETTLE_FRAMES: int = 4
const DRAW_FRAMES: int = 3

var _screen: Gen2BattleScreen = null
var _out: String = ""
var _species: int = DEFAULT_SPECIES
var _level: int = DEFAULT_LEVEL
var _player: int = DEFAULT_PLAYER
var _at: int = DEFAULT_FRAME
var _lo: int = -1
var _hi: int = -1
var _cursor: int = 0
var _settle: int = 0
var _frames: int = 0
var _thumbnail: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: shiny_charm_shot.gd -- <game> <output.png> "
			+ "[species] [level] [frames] [player species] [thumbnail]"
		)
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	if args.size() > 2 and not args[2].is_empty():
		_species = int(args[2])
	if args.size() > 3 and not args[3].is_empty():
		_level = int(args[3])
	if args.size() > 4 and not args[4].is_empty():
		if args[4].contains("-"):
			var span: PackedStringArray = args[4].split("-", false)
			_lo = int(span[0])
			_hi = int(span[1]) if span.size() > 1 else _lo
		else:
			_at = int(args[4])
	if args.size() > 5 and not args[5].is_empty():
		_player = int(args[5])
	if args.size() > 6:
		if args[6] != "thumbnail":
			push_error("Unknown flag %s" % args[6])
			quit(1)
			return
		_thumbnail = true

	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(data)
	_screen.set_random_seed(SEED)
	root.add_child(_screen)
	current_scene = _screen
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
	if _lo >= 0:
		return _shoot_range()
	if _frames < SETTLE_FRAMES + DRAW_FRAMES:
		return false
	return _write(_out)


func _stage() -> bool:
	if not _screen.start_world_battle({"values": {
		"kind": &"wild",
		"pokemon": _species,
		"level": _level,
		"dvs": SHINY_DVS,
	}}):
		push_error("Could not stage a wild battle against species %d" % _species)
		return false
	while _screen.intro_running():
		_screen.advance_frame()
	if _lo >= 0:
		return true
	for _frame: int in _at:
		_screen.advance_frame()
	return true


func _shoot_range() -> bool:
	if _settle > 0:
		_settle -= 1
		return false
	if _cursor > _hi:
		print("Wrote %d frames to %s_f*.png" % [_hi - _lo + 1, _out.trim_suffix(".png")])
		quit(0)
		return true
	if _cursor >= _lo:
		RenderingServer.force_draw()
		var image: Image = root.get_texture().get_image()
		if image.save_png("%s_f%d.png" % [_out.trim_suffix(".png"), _cursor]) != OK:
			push_error("Could not write frame %d" % _cursor)
			quit(1)
			return true
	_cursor += 1
	_screen.advance_frame()
	_settle = DRAW_FRAMES
	return false


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
	if canvas.save_webp(out, false) != OK:
		push_error("Could not write %s" % out)
		return false
	print("Wrote %s (%dx%d)" % [out, THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y])
	return true
