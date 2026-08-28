extends SceneTree

## What the level page paints ON and what it starts FROM.

const MOD := "user://mods/voxel3d"
const CELL_TILES: int = 2
const BAND: int = 16
const ART_FLAT: int = 0
const ART_UPRIGHT: int = 2

const CAVE_TILESETS: Array[int] = [24, 29, 30]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <out dir> <group>,<number>... | caves | stairs")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var out: String = args[1]
	if Gen2ToolPath.refuses(out):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var wanted: Array[Gen2WorldMap] = []
	var selector: String = args[2]
	for map: Gen2WorldMap in data.world_maps():
		if selector == "caves":
			if CAVE_TILESETS.has(map.tileset):
				wanted.append(map)
			continue
		if selector == "stairs":
			if _has_stairs(map, data, profile, shape_script, source_script):
				wanted.append(map)
			continue
		for index: int in range(2, args.size()):
			var pair: PackedStringArray = args[index].split(",")
			if pair.size() == 2 and map.group == int(pair[0]) and map.number == int(pair[1]):
				wanted.append(map)

	var written: int = 0
	for map: Gen2WorldMap in wanted:
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var size: Vector2i = mesher.size_tiles()
		if size == Vector2i.ZERO:
			continue
		var cells := Vector2i(
			map.width_blocks * CELL_TILES, map.height_blocks * CELL_TILES
		)
		var levels: Array = []
		var walls: Array = []
		var waters: Array = []
		for cy: int in cells.y:
			var level_row: Array = []
			var wall_row: Array = []
			var water_row: Array = []
			for cx: int in cells.x:
				water_row.append(
					1 if source.permission_at(Vector2i(cx, cy))
					== Gen2WorldCollision.WATER_TILE else 0
				)
				var floor_px: int = 1 << 30
				var faces: bool = false
				for ty: int in range(cy * CELL_TILES, (cy + 1) * CELL_TILES):
					for tx: int in range(cx * CELL_TILES, (cx + 1) * CELL_TILES):
						var at: int = mesher.grid_index(Vector2i(tx, ty))
						if at < 0:
							continue
						if shape.is_cliff(mesher._tiles[at]):
							faces = true
						if mesher._art[at] != ART_FLAT:
							continue
						var height: int = mesher._heights[at]
						if height >= 0:
							floor_px = mini(floor_px, height)
				if faces:
					level_row.append(null)
					wall_row.append(1)
					continue
				var height_px: int = 0 if floor_px >= (1 << 30) else floor_px
				level_row.append(floori(float(height_px) / float(BAND)))
				wall_row.append(0)
			levels.append(level_row)
			walls.append(wall_row)
			waters.append(water_row)

		var record: Dictionary = {
			"group": map.group,
			"number": map.number,
			"tileset": map.tileset,
			"cells": [cells.x, cells.y],
			"unit": "level16",
			"outside": Gen2WorldPhoneHost.is_outside_environment(map.environment),
			"art": "level_%d_%d.png" % [map.group, map.number],
			"levels": levels,
			"walls": walls,
			"water": waters,
		}
		var path: String = "%s/level_%d_%d.json" % [out, map.group, map.number]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("cannot write ", path)
			continue
		file.store_string(JSON.stringify(record))
		file.close()
		written += 1
		print("%d,%d ts%d  %dx%d cells" % [
			map.group, map.number, map.tileset, cells.x, cells.y
		])
	print("wrote ", written, " maps to ", out)
	quit()


func _has_stairs(
	map: Gen2WorldMap, data: GameData, profile: GDScript,
	shape_script: GDScript, source_script: GDScript
) -> bool:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return false
	var shape: RefCounted = shape_script.new(profile, map.tileset)
	var source: RefCounted = source_script.new(null, map, tileset)
	var width: int = map.width_blocks * 4
	var height: int = map.height_blocks * 4
	for ty: int in height:
		for tx: int in width:
			var tile: int = source.tile_at(tx, ty)
			if tile < 0:
				continue
			if shape.at(tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))) == &"stairs":
				return true
	return false
