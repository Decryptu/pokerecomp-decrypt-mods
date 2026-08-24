extends SceneTree

## Photographs a wild battle against a SHINY Pokemon, at the frame the
## cartridge's own sparkle is over it.
##
##   godot --path <pokerecomp> -s tools/shiny_charm_shot.gd -- \
##       <game> <output.png> [species] [level] [frames] [player species]
##
## The host's `tools/preview_battle_anim.gd` photographs an entrance but stages
## it with `show_matchup`, which has no DVs to give: a fixture wild is always
## the perfect-DV word and can therefore never be shiny. `start_world_battle`
## takes the same request the overworld builds, and that request carries `dvs`,
## so a shiny is staged by asking for one rather than by reaching into the
## battle.
##
## A wild entrance has no ball in it (`BattleStartMessage`'s wild branch), so
## `ANIM_SEND_OUT_MON` with the shiny parameter is the first thing that happens
## once the pics stop sliding. `frames` may be a range, `lo-hi`, which writes one
## `<output>_f<N>.png` per frame instead of one file: that is how the frame worth
## keeping is chosen, by looking rather than by counting.
##
## Needs a display, since it renders.

const WINDOW_SIZE := Vector2i(1280, 720)
## `Gen2Stats.is_shiny`'s own word: ATTACK 2, and 10 in each of the other three.
const SHINY_DVS: int = (2 << 12) | (10 << 8) | (10 << 4) | 10
## The red GYARADOS, which is the one shiny the cartridge itself puts in front of
## a player.
const DEFAULT_SPECIES: int = 130
const DEFAULT_LEVEL: int = 30
const DEFAULT_PLAYER: int = 157
## Enough frames for the scene to lay out before anything is driven, and enough
## after it for the viewport to draw what was driven.
const SETTLE_FRAMES: int = 4
const DRAW_FRAMES: int = 3

var _screen: Gen2BattleScreen = null
var _out: String = ""
var _species: int = DEFAULT_SPECIES
var _level: int = DEFAULT_LEVEL
var _player: int = DEFAULT_PLAYER
var _at: int = 0
var _lo: int = -1
var _hi: int = -1
var _cursor: int = 0
var _settle: int = 0
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: shiny_charm_shot.gd -- <game> <output.png> "
			+ "[species] [level] [frames] [player species]"
		)
		quit(1)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	if args.size() > 2:
		_species = int(args[2])
	if args.size() > 3:
		_level = int(args[3])
	if args.size() > 4:
		if args[4].contains("-"):
			var span: PackedStringArray = args[4].split("-", false)
			_lo = int(span[0])
			_hi = int(span[1]) if span.size() > 1 else _lo
		else:
			_at = int(args[4])
	if args.size() > 5:
		_player = int(args[5])

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	# The screen counts hardware frames off its own `_process` deltas, and every
	# frame here is counted rather than timed so two runs are the same run.
	_screen.set_process(false)


func _process(_delta: float) -> bool:
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


## The wild battle the overworld would have asked for, with the shiny word in
## the request. No save, so the player's side is the host's own fallback party
## with its lead replaced by the species asked for.
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
	_screen.set_process(false)
	if _settle > 0:
		_settle -= 1
		return false
	if _cursor > _hi:
		print("Wrote %d frames to %s_f*.png" % [_hi - _lo + 1, _out.trim_suffix(".png")])
		quit(0)
		return true
	if _cursor >= _lo:
		# A window that has not been composited between two driven frames hands
		# back the last picture that was, so a whole range can come out as one
		# frame repeated. Drawing on demand is what makes a run reproducible.
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
	quit(0)
	return true
