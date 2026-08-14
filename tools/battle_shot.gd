extends SceneTree

## Photographs a BATTLE staged on a real map, the way the mod builds one.
##
## `tools/shot.gd` is the overworld's camera and there was no equivalent for the
## fight, so every claim about the arena, the panels, the bars and the battlers
## was argued from the code. Three open items want a picture of one: the frosted
## panels, the shot's drift, and the move animations.
##
## `Gen2BattleWorldContext` is a copy of where the fight started, with public
## fields and no handle on the world, so a tool fills one in exactly as the world
## screen does. The view is the display dictionary `Gen2BattleScreen` hands over,
## and only the keys the renderer reads are set here.
##
##   Godot --path <pokerecomp> -s tools/battle_shot.gd -- <cache> <group> \
##       <number> <cell x> <cell y> <out.png> [facing 0-3] [time 0-3] \
##       [player species] [enemy species] [hold frames] [hp 0-1]
##
## THE SHUTTER IS ON THE COMPOSITE and the reason is in `tools/shot.gd`: a pass
## over the finished picture lives on the stage container's material and only
## runs when that container is drawn into something else. The renderer is put
## inside a viewport of this tool's own and THAT is what is saved.
##
## Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const VIEW := Vector2i(880, 600)

var _frame: SubViewport = null
var _renderer: Control = null
## Handed over on the first FRAME rather than during setup. `set_view` frames the
## camera and pins both battlers, and `unproject_position` on a camera whose
## viewport has not drawn yet answers with an engine error per call. Nothing is
## lost by waiting: `_process` re-frames and re-pins every frame anyway.
var _view: Dictionary = {}
var _out: String = ""
var _frames: int = 0
## Enough for the viewport to have drawn, the atlas to have landed and the
## arena's ease to have settled on its solved seat.
var _hold: int = 12


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <group> <number> <cell x> <cell y> <out.png>"
			+ " [facing 0-3] [time 0-3] [player species] [enemy species]"
			+ " [hold frames] [hp 0-1]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[5]

	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.group == int(args[1]) and candidate.number == int(args[2]):
			map = candidate
	if map == null:
		print("no map ", args[1], ",", args[2])
		quit(1)
		return

	var context := Gen2BattleWorldContext.new()
	context.map_id = Vector2i(map.group, map.number)
	context.tileset = map.tileset
	context.player_cell = Vector2i(int(args[3]), int(args[4]))
	context.player_facing = clampi(int(args[6]) if args.size() > 6 else 0, 0, 3)
	context.time_of_day = clampi(int(args[7]) if args.size() > 7 else 1, 0, 3)

	_frame = SubViewport.new()
	_frame.size = VIEW
	_frame.transparent_bg = false
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)

	_renderer = (load("%s/battle/renderer.gd" % MOD) as GDScript).new()
	_frame.add_child(_renderer)
	_renderer.set_native_size(VIEW)
	if not _renderer.set_battle_data(data):
		print("no battle hud in ", args[0])
		quit(1)
		return
	_renderer.set_world_context(context)

	# The health is an argument because the bars are drawn from it and their
	# palette turns on how much of the bar is lit, so a full bar and a red one are
	# two different pictures of the same panel.
	var share: float = clampf(float(args[11]) if args.size() > 11 else 1.0, 0.0, 1.0)
	_view = {
		"battle_kind": &"wild",
		"enemy_species": int(args[9]) if args.size() > 9 else 16,
		"enemy_name": "PIDGEY",
		"enemy_level": 7,
		"enemy_hp": int(round(22.0 * share)),
		"enemy_max_hp": 22,
		"player_species": int(args[8]) if args.size() > 8 else 155,
		"player_name": "CYNDAQUIL",
		"player_level": 9,
		"player_hp": int(round(27.0 * share)),
		"player_max_hp": 27,
		"player_pic_visible": true,
		"hud_visible": true,
		"exp_pixels": 20,
	}
	_hold = maxi(int(args[10]) if args.size() > 10 else 12, 2)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_renderer.set_view(_view)
	if _frames < _hold:
		return false
	_frame.get_texture().get_image().save_png(_out)
	print(_out)
	return true
