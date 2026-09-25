extends SceneTree

## What the level page paints ON and what it starts FROM.

const MOD := "user://mods/voxel3d"
const CELL_TILES: int = 2
const BAND: int = 8
const ART_FLAT: int = 0
const ART_UPRIGHT: int = 2
const FACED: int = -1

## Tileset numbers differ between cartridges, so a cave is found by name.
const CAVE_TILESETS: Array[StringName] = [&"CAVE", &"ICE_PATH", &"DARK_CAVE", &"CAVERN"]


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
	if PokeToolPath.refuses(out):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)

	var profile: GDScript = (load("%s/shape/profiles.gd" % MOD) as GDScript).of(data)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var wanted: Array[Gen2WorldMap] = []
	var selector: String = args[2]
	for map: Gen2WorldMap in data.world_maps():
		if selector == "caves":
			if _is_cave(data, map):
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
		var shape: RefCounted = shape_script.new(profile, tileset.name)
		var source: RefCounted = source_script.new(null, map, tileset, data)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var size: Vector2i = mesher.size_tiles()
		if size == Vector2i.ZERO:
			continue
		var cells := Vector2i(
			map.width_blocks * CELL_TILES, map.height_blocks * CELL_TILES
		)
		var start: Array = _painted_start(map, tileset, cells)
		if start.is_empty():
			start = _measured_start(mesher, shape, cells)
		var levels: Array = start[0]
		var walls: Array = start[1]
		var waters: Array = []
		for cy: int in cells.y:
			var water_row: Array = []
			for cx: int in cells.x:
				water_row.append(
					1 if source.permission_at(Vector2i(cx, cy))
					== Gen2WorldCollision.WATER_TILE else 0
				)
			waters.append(water_row)

		var record: Dictionary = {
			"group": map.group,
			"number": map.number,
			"tileset": map.tileset,
			"drawing": (load("%s/shape/levels.gd" % MOD) as GDScript).drawing_of(map, tileset),
			"cells": [cells.x, cells.y],
			"unit": "band8",
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


## A map somebody painted starts from its painting, so a repaint changes what
## it means to and nothing else.
func _painted_start(map: Gen2WorldMap, tileset: Gen2WorldTileset, cells: Vector2i) -> Array:
	var painted: GDScript = load("%s/shape/levels.gd" % MOD)
	var rows: Array = painted.rows_of(map, tileset)
	if rows.is_empty():
		return []
	var levels: Array = []
	var walls: Array = []
	for cy: int in cells.y:
		var level_row: Array = []
		var wall_row: Array = []
		for cx: int in cells.x:
			var height: int = painted.height_in(rows, Vector2i(cx, cy))
			wall_row.append(1 if height == painted.WALLED else 0)
			level_row.append(_band_mark(height))
		levels.append(level_row)
		walls.append(wall_row)
	return [levels, walls]


## The floor under each walk cell as the mesher measures it; a cell holding a
## cliff face is a wall.
func _measured_start(mesher: RefCounted, shape: RefCounted, cells: Vector2i) -> Array:
	var levels: Array = []
	var walls: Array = []
	for cy: int in cells.y:
		var level_row: Array = []
		var wall_row: Array = []
		for cx: int in cells.x:
			var floor_px: int = _cell_floor(mesher, shape, cx, cy)
			wall_row.append(1 if floor_px == FACED else 0)
			level_row.append(_band_mark(floor_px))
		levels.append(level_row)
		walls.append(wall_row)
	return [levels, walls]


## A height in bands, or null for a cell with no floor of its own.
func _band_mark(height_px: int) -> Variant:
	if height_px < 0:
		return null
	return floori(float(height_px) / BAND)


## A cell's lowest flat floor in pixels, 0 where it has none, or `FACED`.
func _cell_floor(mesher: RefCounted, shape: RefCounted, cx: int, cy: int) -> int:
	var floor_px: int = 1 << 30
	for ty: int in range(cy * CELL_TILES, (cy + 1) * CELL_TILES):
		for tx: int in range(cx * CELL_TILES, (cx + 1) * CELL_TILES):
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			if at < 0:
				continue
			if shape.is_cliff(mesher._tiles[at]):
				return FACED
			if mesher._art[at] == ART_FLAT and mesher._heights[at] >= 0:
				floor_px = mini(floor_px, mesher._heights[at])
	return 0 if floor_px >= (1 << 30) else floor_px


func _is_cave(data: GameData, map: Gen2WorldMap) -> bool:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	return tileset != null and CAVE_TILESETS.has(tileset.name)


func _has_stairs(
	map: Gen2WorldMap, data: GameData, profile: GDScript,
	shape_script: GDScript, source_script: GDScript
) -> bool:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return false
	var shape: RefCounted = shape_script.new(profile, tileset.name)
	var source: RefCounted = source_script.new(null, map, tileset, data)
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
