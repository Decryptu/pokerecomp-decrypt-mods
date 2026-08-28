extends SceneTree

## Every map the cartridge holds, one to a line, with what a survey needs to
## choose between them.
##
## There was no such tool and the first thing a survey round wants is the list:
## which maps are towns, which tileset each is on, how big it is, and the tile to
## aim a camera at. Reading that off a probe written from scratch is ten minutes
## every round and it was written from scratch twice.
##
##   Godot --headless --path <pokerecomp> -s tools/maps.gd -- <cache> [filter]
##
## FILTER is `all`, `towns` for the maps the cartridge files as a town or city,
## `outside`, `inside`, or `ts<number>` for one tileset. Default `all`.
##
## The columns are group,number, tileset, environment, size in TILES, whether
## the host calls it outside, the CENTRE tile, which is what `tools/shot.gd` and
## `tools/map_grid.py` both take, how far BACK to stand to hold the whole of
## it, which `tools/pack.sh` reads so that a pack of a city and a pack of a
## village are framed the same way, and the map's own NAME. A constant cannot do
## the distance: 320 holds a village whole and shows one corner of Saffron.
##
## The name is the cartridge's landmark, off `map.location`, and it is last so
## that a reader adding a column does not move the ones a script counts. It is
## what a person calls the place, and a pack labelled `22,2` alone is a pack
## nobody can talk about.
##
## EVERY PATH QUITS, and that is not tidiness. A SceneTree script that errors
## before `quit()` never returns: the run hangs until something kills it, and
## nothing on the terminal says why. Two probes were written that way here and
## both looked like the cartridge cache had gone missing.

## `Gen2WorldMap.environment`, the cartridge's own byte. 1 is the towns.
const ENVIRONMENT_TOWN: int = 1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [all|towns|outside|inside|ts<number>]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var filter: String = args[1] if args.size() > 1 else "all"
	var only_tileset: int = -1
	if filter.begins_with("ts"):
		only_tileset = int(filter.substr(2))

	var rows: Array = []
	for map: Gen2WorldMap in data.world_maps():
		var wide: int = map.width_blocks * 4
		var high: int = map.height_blocks * 4
		# The source is what answers `outside`, and it is the host's own question
		# rather than a reading of the environment byte.
		var source: RefCounted = (
			load("user://mods/voxel3d/shape/map_source.gd") as GDScript
		).new(null, map, data.world_tileset(map.tileset), data)
		var outside: bool = source.outside()
		match filter:
			"towns":
				if map.environment != ENVIRONMENT_TOWN:
					continue
			"outside":
				if not outside:
					continue
			"inside":
				if outside:
					continue
			_:
				if only_tileset >= 0 and map.tileset != only_tileset:
					continue
		rows.append([map.group, map.number, map.tileset, map.environment,
			wide, high, outside, data.landmark_name(map.location)])

	# Biggest first, because a survey pack is read in that order: the maps worth
	# a picture are the ones with the most in them.
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[4] * a[5] > b[4] * b[5]
	)
	print("map\tts\tenv\ttiles\tplace\tcentre\tback\tname")
	for row: Array in rows:
		@warning_ignore("integer_division")
		var centre := Vector2i(row[4] / 2, row[5] / 2)
		# Seven eighths of the longer side in world pixels, read off map 11,2 at
		# three distances and chosen in the picture: the town fills the frame with
		# its edges still in it.
		@warning_ignore("integer_division")
		var back: int = maxi(row[4], row[5]) * 8 * 7 / 8
		print("%d,%d\t%d\t%d\t%dx%d\t%s\t%d,%d\t%d\t%s" % [
			row[0], row[1], row[2], row[3], row[4], row[5],
			"outside" if row[6] else "inside", centre.x, centre.y, back, row[7],
		])
	print(rows.size(), " maps")
	quit()
