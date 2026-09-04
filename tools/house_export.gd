extends SceneTree

## What the house page paints ON and what it starts FROM.
## from blank. The generated pass already names `facade` and `roof` on ten

const MOD := "user://mods/voxel3d"
const TILE: int = 8
const BLOCK_TILES: int = Gen2Layout.MAP_BLOCK_CELL_WIDTH * 2

const WINDOW: int = 20
const RING_OUTER := Color(1.0, 0.0, 1.0)
const RING_INNER := Color(1.0, 1.0, 1.0)

const PAINT_NONE := "."
const PAINT_WALL := "W"
const PAINT_PITCH := "P"
const PAINT_ROOF := "R"
const PAINT_FALL_WEST := "<"
const PAINT_FALL_EAST := ">"
const PAINT_DOOR := "D"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <out dir> [tileset]")
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
	var only: int = int(args[2]) if args.size() > 2 else -1
	DirAccess.make_dir_recursive_absolute(out)

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var drawings: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		_walk(map, tileset, profile, shape_script, source_script, drawings)

	var keys: Array = drawings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int((drawings[a] as Dictionary)["placements"]) \
			> int((drawings[b] as Dictionary)["placements"]))

	var painted: Dictionary = {}
	var written: int = 0
	for index: int in keys.size():
		var record: Dictionary = drawings[keys[index]]
		record["id"] = index + 1
		var name: String = "house_%03d" % (index + 1)
		record["art"] = "%s.png" % name
		record["context"] = "%s_where.png" % name
		record["maps"] = (record["maps"] as Dictionary).keys()
		var map: Gen2WorldMap = record["map"]
		record.erase("map")
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var image: Image = _paint(data, map, tileset)
		var box := Rect2i(
			Vector2i(record["at"][0], record["at"][1]),
			Vector2i(record["size"][0], record["size"][1])
		)
		image.get_region(Rect2i(box.position * TILE, box.size * TILE)) \
			.save_png("%s/%s.png" % [out, name])
		_ringed(image, box).save_png("%s/%s_where.png" % [out, name])
		var file: FileAccess = FileAccess.open("%s/%s.json" % [out, name], FileAccess.WRITE)
		if file == null:
			print("cannot write ", name)
			continue
		file.store_string(JSON.stringify(record))
		file.close()
		written += 1
		for row: Array in record["paint"] as Array:
			for symbol: String in row:
				painted[symbol] = int(painted.get(symbol, 0)) + 1

	var total: int = 0
	for key: String in keys:
		total += int((drawings[key] as Dictionary)["placements"])
	print(written, " drawings, placed ", total, " times, into ", out)
	print("pre-filled tiles:")
	for symbol: String in painted.keys():
		print("  %s  %5d" % [symbol, painted[symbol]])
	quit()


func _walk(
	map: Gen2WorldMap, tileset: Gen2WorldTileset,
	profile: GDScript, shape_script: GDScript, source_script: GDScript,
	drawings: Dictionary
) -> void:
	var shape: RefCounted = shape_script.new(profile, map.tileset)
	var source: RefCounted = source_script.new(null, map, tileset)
	var w: int = map.width_blocks * BLOCK_TILES
	var h: int = map.height_blocks * BLOCK_TILES
	var warps: Dictionary = {}
	for event: Dictionary in map.events.get("warps", []) as Array:
		warps["%d,%d" % [int(event.get("x", -1)), int(event.get("y", -1))]] = true

	var part := PackedByteArray()
	var ids := PackedInt32Array()
	var guess: Array = []
	part.resize(w * h)
	ids.resize(w * h)
	guess.resize(w * h)
	for ty: int in h:
		for tx: int in w:
			var at: int = ty * w + tx
			var tile: int = source.tile_at(tx, ty)
			ids[at] = tile
			guess[at] = PAINT_NONE
			if tile < 0:
				continue
			if warps.has("%d,%d" % [tx >> 1, ty >> 1]):
				guess[at] = PAINT_DOOR
				continue
			var klass: StringName = shape.at(
				tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))
			)
			if klass == &"facade":
				part[at] = 1
				guess[at] = PAINT_PITCH if shape.is_facade_slope(tile) else PAINT_WALL
			elif String(klass).begins_with("roof"):
				part[at] = 1
				guess[at] = PAINT_ROOF if shape.roof_drop(klass) == 0 else ""

	var seen := PackedByteArray()
	seen.resize(w * h)
	for ty: int in h:
		for tx: int in w:
			if part[ty * w + tx] == 0 or seen[ty * w + tx] == 1:
				continue
			var box: Rect2i = _flood(part, seen, w, h, Vector2i(tx, ty))
			var rows: Array = []
			var paint: Array = []
			for row: int in box.size.y:
				var line: Array = []
				var strokes: Array = []
				for column: int in box.size.x:
					var at: int = (box.position.y + row) * w + box.position.x + column
					line.append(ids[at])
					strokes.append(guess[at])
				rows.append(line)
				paint.append(strokes)
			_fill_falls(paint)
			var key: String = "ts%d %s" % [map.tileset, str(rows)]
			if not drawings.has(key):
				drawings[key] = {
						"tileset": map.tileset,
					"tiles": rows,
					"size": [box.size.x, box.size.y],
					"cells": [box.size.x / 2.0, box.size.y / 2.0],
					"placements": 0,
					"maps": {},
					"at": [box.position.x, box.position.y],
					"map": map,
					"where": "%d,%d @ tile %d,%d" % [
						map.group, map.number, box.position.x, box.position.y
					],
					"paint": paint,
				}
			var record: Dictionary = drawings[key]
			record["placements"] = int(record["placements"]) + 1
			(record["maps"] as Dictionary)["%d,%d" % [map.group, map.number]] = true
			var kept: Array = record["paint"]
			for row: int in box.size.y:
				for column: int in box.size.x:
					if paint[row][column] == PAINT_DOOR:
						kept[row][column] = PAINT_DOOR


func _flood(
	part: PackedByteArray, seen: PackedByteArray, w: int, h: int, from: Vector2i
) -> Rect2i:
	var stack: Array[Vector2i] = [from]
	var box := Rect2i(from, Vector2i.ONE)
	seen[from.y * w + from.x] = 1
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		box = box.expand(at).expand(at + Vector2i.ONE)
		for step: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]:
			var next: Vector2i = at + step
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			var index: int = next.y * w + next.x
			if part[index] == 0 or seen[index] == 1:
				continue
			seen[index] = 1
			stack.append(next)
	return box


func _fill_falls(paint: Array) -> void:
	var width: int = (paint[0] as Array).size()
	for row: Array in paint:
		for column: int in width:
			if row[column] != "":
				continue
			row[column] = PAINT_FALL_WEST if column * 2 < width else PAINT_FALL_EAST


func _ringed(image: Image, ring: Rect2i) -> Image:
	var box := Rect2i(ring.position * TILE, ring.size * TILE)
	for pass_index: int in 2:
		var inset: int = 1 + pass_index
		var color: Color = RING_INNER if pass_index == 0 else RING_OUTER
		var edge := Rect2i(
			box.position - Vector2i(inset, inset), box.size + Vector2i(inset, inset) * 2
		)
		for x: int in range(edge.position.x, edge.end.x):
			_dot(image, x, edge.position.y, color)
			_dot(image, x, edge.end.y - 1, color)
		for y: int in range(edge.position.y, edge.end.y):
			_dot(image, edge.position.x, y, color)
			_dot(image, edge.end.x - 1, y, color)
	var margin: int = WINDOW * TILE
	var crop := Rect2i(box.position - Vector2i(margin, margin),
		box.size + Vector2i(margin, margin) * 2)
	crop.position = Vector2i(maxi(crop.position.x, 0), maxi(crop.position.y, 0))
	crop.size = Vector2i(
		mini(crop.size.x, image.get_width() - crop.position.x),
		mini(crop.size.y, image.get_height() - crop.position.y)
	)
	return image.get_region(crop)


func _dot(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, color)


func _paint(data: GameData, map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Image:
	var indices: PackedByteArray = data.world_tileset_indices(tileset.number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		data, map, tileset, Gen2WorldPalette.TIME_DAY
	)
	var stride: int = tileset.tile_count * TILE
	var tiles := Vector2i(map.width_blocks, map.height_blocks) * BLOCK_TILES
	var image: Image = Image.create(
		tiles.x * TILE, tiles.y * TILE, false, Image.FORMAT_RGBA8
	)
	for ty: int in tiles.y:
		for tx: int in tiles.x:
			@warning_ignore("integer_division")
			var block: int = map.block_at(tx / BLOCK_TILES, ty / BLOCK_TILES)
			var tile: int = tileset.tile_index(block, (ty & 3) * BLOCK_TILES + (tx & 3))
			var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
				else PackedColorArray()
			for y: int in TILE:
				var row: int = y * stride + tile * TILE
				for x: int in TILE:
					var index: int = int(indices[row + x]) if row + x < indices.size() else 0
					image.set_pixel(
						tx * TILE + x, ty * TILE + y,
						palette[index] if index < palette.size() else Color.MAGENTA
					)
	return image
