extends SceneTree

## Every map the cartridge holds, one to a line, with what a survey needs to
## choose between them.

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

	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[4] * a[5] > b[4] * b[5]
	)
	print("map\tts\tenv\ttiles\tplace\tcentre\tback\tname")
	for row: Array in rows:
		@warning_ignore("integer_division")
		var centre := Vector2i(row[4] / 2, row[5] / 2)
		@warning_ignore("integer_division")
		var back: int = maxi(row[4], row[5]) * 8 * 7 / 8
		print("%d,%d\t%d\t%d\t%dx%d\t%s\t%d,%d\t%d\t%s" % [
			row[0], row[1], row[2], row[3], row[4], row[5],
			"outside" if row[6] else "inside", centre.x, centre.y, back, row[7],
		])
	print(rows.size(), " maps")
	quit()
