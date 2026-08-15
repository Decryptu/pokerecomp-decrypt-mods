extends SceneTree

## Photographs one place on one map, the way the mod builds it.
##
## Every visual claim in this mod is checked with a picture, and several
## confident ones were wrong. This is the cheapest way to take one: no game, no
## save, no walking there.
##
##   Godot --path <pokerecomp> -s tools/shot.gd -- <cache> <group> <number> \
##       <tile x> <tile y> <out.png> [pitch] [back] [time 0-3] [sky] [hold]
##       [bearing] [colour style]
##
## The STYLE is `shape/model.gd`'s own switch, by name, and it is here for the
## same reason `tools/foliage.gd` has it: a model judged on a plain floor is not
## judged, and this is what puts a proposition in the wood it will be seen in.
##
## HOLD is how many frames to run before the shutter, and it is how MOTION is
## photographed: everything that moves in this view moves on the shader clock, so
## the same shot held for a different number of frames is the same place a moment
## later. Two of them side by side is the only still picture of a moving thing.
##
## Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const TILE: float = 8.0
const VIEW := Vector2i(880, 600)

var _stage: RefCounted = null
## The viewport the composited stage is drawn into, which is what is saved.
var _frame: SubViewport = null
var _out: String = ""
var _frames: int = 0
## Six is enough for the viewport to have drawn and for the atlas to have landed.
var _hold: int = 6


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <group> <number> <tile x> <tile y> <out.png>"
			+ " [pitch] [back] [time 0-3] [sky #rrggbb] [hold frames]"
			+ " [bearing east of south]")
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
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)

	if args.size() > 12:
		var model_script: GDScript = load("%s/shape/model.gd" % MOD)
		var style: String = args[12].to_upper()
		if model_script.get(style) == null:
			print("no colour style ", style)
			quit(1)
			return
		model_script.style = int(model_script.get(style))

	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	# THE CARTRIDGE IS PASSED, and without it this tool photographs a different
	# world from the one the game builds. `map_source.gd` folds a map's
	# CONNECTIONS into everything past its edge, and it can only do that with the
	# records in hand; given none it answers the map's own border block instead.
	# So a building that straddles a map boundary, which is how the cartridge
	# draws several of them, loses everything on the far side and every render of
	# it here is wrong in a way no probe reports.
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	# THE SHUTTER IS ON THE COMPOSITE, not on the stage's own viewport.
	#
	# Anything this view does as a pass over the FINISHED picture, which today is
	# the hour's tint and tomorrow the frosted panels, lives on the container's
	# MATERIAL, and a material only runs when the container draws its viewport into
	# something else. Reading the stage's SubViewport straight off, which this tool
	# did until 2026-08-13, photographs the world one step before that pass: a tint
	# that was working perfectly measured as doing nothing at all, twice, and the
	# second time it was nearly written off as redundant.
	#
	# So the container is drawn into a viewport of this tool's own and THAT is what
	# is saved. Not the window: the window applies a content scale of its own and
	# the picture came back at 76% in the corner of a grey frame.
	_frame = SubViewport.new()
	_frame.size = VIEW
	_frame.transparent_bg = false
	_frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_frame)
	var holder := Control.new()
	holder.size = Vector2(VIEW)
	holder.add_child(_stage.container)
	_frame.add_child(holder)
	# Only the container is sized: it stretches, so it owns its SubViewport.
	_stage.container.size = Vector2(VIEW)

	# The hour is an argument because the light now MOVES with it: the sun's
	# bearing is what a shot at one time says and a shot at another cannot.
	var time_of_day: int = clampi(int(args[8]) if args.size() > 8 else 1, 0, 3)
	_stage.set_time_of_day(time_of_day)
	if atlas.build(data, map, tileset, time_of_day):
		_stage.set_texture(atlas.texture)
		# The map's own background, so a shot shows the sky the player would see
		# rather than a fixed blue that belongs to no map. Overridable, because
		# what the void behind an INTERIOR should be is an open question and the
		# only way to put two answers in front of a person is to shoot both.
		# An EMPTY sky argument means the map's own, not black. The arguments are
		# positional, so asking for a HOLD without an override needs a placeholder,
		# and `Color("")` is black: the trap costs a render and looks like the sky
		# has broken.
		if args.size() > 9 and not args[9].is_empty():
			_stage.set_background(Color(args[9]))
		elif source.outside():
			_stage.set_background(atlas.background(), true)
		else:
			_stage.set_background(atlas.void_color(), false)
	_stage.set_terrain(mesher.build(source, shape, atlas))
	_stage.set_water(mesher.take_water())
	_stage.set_tufts(mesher.take_tufts())
	_stage.set_models(mesher.take_models())

	var focus := Vector3((float(args[3]) + 0.5) * TILE, 0.0, (float(args[4]) + 0.5) * TILE)
	_hold = maxi(int(args[10]) if args.size() > 10 else 6, 1)
	var pitch: float = deg_to_rad(float(args[6]) if args.size() > 6 else 32.0)
	var back: float = float(args[7]) if args.size() > 7 else 220.0
	# BEARING, east of due south, and it is an argument because the two things a
	# shot is for want opposite answers. Standing the eye off to one side is what
	# shows a face and a flank at once, which is how a shape is judged; DUE SOUTH,
	# 0, is where the game's own overworld camera always stands, and it is also
	# the only bearing whose picture lines up column for column with the map's own
	# 2D art, so a tile can be pointed at in one picture and found in the other.
	# The default is the angle every shot before this was taken at.
	var bearing: float = deg_to_rad(float(args[11]) if args.size() > 11 else 20.4)
	_stage.aim_camera(
		focus + Vector3(
			back * cos(pitch) * sin(bearing), back * sin(pitch), back * cos(pitch) * cos(bearing)
		),
		focus + Vector3(0.0, TILE, 0.0)
	)
	# Someone is standing where the shot is aimed, because that is where the
	# overworld's own camera is always aimed. The grass parts around them.
	_stage.set_walker(focus)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _hold:
		return false
	_frame.get_texture().get_image().save_png(_out)
	print(_out)
	return true
