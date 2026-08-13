extends SceneTree

## Photographs one place on one map, the way the mod builds it.
##
## Every visual claim in this mod is checked with a picture, and several
## confident ones were wrong. This is the cheapest way to take one: no game, no
## save, no walking there.
##
##   Godot --path <pokerecomp> -s tools/shot.gd -- <cache> <group> <number> \
##       <tile x> <tile y> <out.png> [pitch] [back]
##
## Needs a display, since it renders.

const MOD := "user://mods/voxel3d"
const TILE: float = 8.0
const VIEW := Vector2i(880, 600)

var _stage: RefCounted = null
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		print("usage: <cache> <group> <number> <tile x> <tile y> <out.png>"
			+ " [pitch] [back] [time 0-3] [sky #rrggbb]")
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

	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset
	)
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)
	_stage.container.size = Vector2(VIEW)
	_stage.viewport.size = VIEW

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
		_stage.set_background(
			Color(args[9]) if args.size() > 9 else atlas.background()
		)
	_stage.set_terrain(mesher.build(source, shape, atlas))

	var focus := Vector3((float(args[3]) + 0.5) * TILE, 0.0, (float(args[4]) + 0.5) * TILE)
	var pitch: float = deg_to_rad(float(args[6]) if args.size() > 6 else 32.0)
	var back: float = float(args[7]) if args.size() > 7 else 220.0
	_stage.aim_camera(
		focus + Vector3(back * cos(pitch) * 0.35, back * sin(pitch), back * cos(pitch) * 0.94),
		focus + Vector3(0.0, TILE, 0.0)
	)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	_stage.viewport.get_texture().get_image().save_png(_out)
	print(_out)
	return true
