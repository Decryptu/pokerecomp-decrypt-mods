extends SceneTree

## Finds each tile somewhere in the real world and photographs it there.

const MOD := "user://mods/voxel3d"
const TILE: int = 8
const BLOCK_TILES: int = 4
const BLOCK_CELLS: int = 2

const WINDOW: int = 15
const RING_OUTER := Color(1.0, 0.0, 1.0)
const RING_INNER := Color(1.0, 1.0, 1.0)
const SCALE: int = 4

var _data: GameData = null
var _out: String = ""
var _every: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <tileset|all> <out dir> [unpinned|all]")
		quit(1)
		return
	_data = GameData.open_argument(args[0])
	if _data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[2]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	_every = args.size() > 3 and args[3] == "all"
	DirAccess.make_dir_recursive_absolute(_out)

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var numbers: Array[int] = []
	if args[1] == "all":
		for map: Gen2WorldMap in _data.world_maps():
			if not numbers.has(map.tileset):
				numbers.append(map.tileset)
		numbers.sort()
	else:
		numbers.append(int(args[1]))
	for number: int in numbers:
		_ask(number, profile)
	quit()


func _busiest(number: int) -> Gen2WorldMap:
	var best: Gen2WorldMap = null
	var most: int = -1
	for map: Gen2WorldMap in _data.world_maps():
		if map.tileset == number and map.blocks.size() > most:
			most = map.blocks.size()
			best = map
	return best


func _ask(number: int, profile: GDScript) -> void:
	var tileset: Gen2WorldTileset = _data.world_tileset(number)
	if tileset == null:
		return

	var seen: Dictionary = {}
	var maps: Array = []
	for map: Gen2WorldMap in _data.world_maps():
		if map.tileset == number:
			maps.append(map)
	maps.sort_custom(func(a: Gen2WorldMap, b: Gen2WorldMap) -> bool:
		return a.blocks.size() > b.blocks.size())

	for map: Gen2WorldMap in maps:
		var tiles := Vector2i(map.width_blocks, map.height_blocks) * BLOCK_TILES
		for ty: int in tiles.y:
			for tx: int in tiles.x:
				@warning_ignore("integer_division")
				var block: int = map.block_at(tx / BLOCK_TILES, ty / BLOCK_TILES)
				var tile: int = tileset.tile_index(
					block, (ty & 3) * BLOCK_TILES + (tx & 3)
				)
				var permission: int = Gen2WorldCollision.permission_for(
					map.collision_at(tx >> 1, ty >> 1)
				)
				if not _every:
					if permission != Gen2WorldCollision.WALL_TILE:
						continue
					if profile.pinned_class(number, tile) != &"":
						continue
				var entry: Dictionary = seen.get(tile, {
					"count": 0, "blocked": 0, "walkable": 0, "water": 0,
				})
				entry["count"] = int(entry["count"]) + 1
				match permission:
					Gen2WorldCollision.WALL_TILE:
						entry["blocked"] = int(entry["blocked"]) + 1
					Gen2WorldCollision.WATER_TILE:
						entry["water"] = int(entry["water"]) + 1
					Gen2WorldCollision.LAND_TILE:
						entry["walkable"] = int(entry["walkable"]) + 1
				if _every and permission == Gen2WorldCollision.WALL_TILE \
						and not entry.has("blocked_at"):
					entry["blocked_at"] = Vector2i(tx, ty)
					entry["blocked_map"] = map
				var away: float = (
					Vector2(tx, ty) - Vector2(tiles) * 0.5
				).length() / maxf(float(tiles.x), 1.0)
				if not entry.has("away") or away < float(entry["away"]):
					entry["away"] = away
					entry["at"] = Vector2i(tx, ty)
					entry["map"] = map
				seen[tile] = entry

	if seen.is_empty():
		return
	var painted: Dictionary = {}
	var records: Array = []
	for tile: int in seen:
		var entry: Dictionary = seen[tile]
		var map: Gen2WorldMap = entry["map"]
		var key: String = "%d,%d" % [map.group, map.number]
		if not painted.has(key):
			painted[key] = _paint(map, tileset)
		var record: Dictionary = {
			"tile": tile,
			"count": entry["count"],
			"map": [map.group, map.number],
			"file": _crop(painted[key], entry["at"], number, tile),
		}
		if _every:
			record["blocked"] = entry["blocked"]
			record["walkable"] = entry["walkable"]
			record["water"] = entry["water"]
			record["pinned"] = String(profile.pinned_class(number, tile))
		records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["count"]) > int(b["count"]))

	var file: FileAccess = FileAccess.open(
		"%s/%s_ts%d.json" % [_out, "pass" if _every else "ask", number], FileAccess.WRITE
	)
	file.store_string(JSON.stringify({
		"tileset": number, "window": WINDOW, "tile": TILE, "tiles": records
	}, "  "))
	file.close()
	print("tileset %d: %d tiles to ask about" % [number, records.size()])


func _paint(map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Image:
	var indices: PackedByteArray = _data.world_tileset_indices(tileset.number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_data, map, tileset, Gen2WorldPalette.TIME_DAY
	)
	var stride: int = tileset.tile_count * TILE
	var tiles := Vector2i(map.width_blocks, map.height_blocks) * BLOCK_TILES
	var image: Image = Image.create(tiles.x * TILE, tiles.y * TILE, false, Image.FORMAT_RGBA8)
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


func _crop(map_image: Image, at: Vector2i, number: int, tile: int) -> String:
	var half: int = WINDOW / 2
	var tiles := Vector2i(map_image.get_width() / TILE, map_image.get_height() / TILE)
	var origin := Vector2i(
		clampi(at.x - half, 0, maxi(tiles.x - WINDOW, 0)),
		clampi(at.y - half, 0, maxi(tiles.y - WINDOW, 0))
	)
	var box := Rect2i(origin * TILE, Vector2i(
		mini(WINDOW * TILE, map_image.get_width()),
		mini(WINDOW * TILE, map_image.get_height())
	))
	var out: Image = map_image.get_region(box)

	for step: int in 2:
		var color: Color = RING_INNER if step == 0 else RING_OUTER
		var inset: int = step + 1
		var ring := Rect2i(
			(at - origin) * TILE - Vector2i(inset, inset),
			Vector2i(TILE + inset * 2, TILE + inset * 2)
		)
		for x: int in range(ring.position.x, ring.end.x):
			for y: int in [ring.position.y, ring.end.y - 1]:
				if x >= 0 and y >= 0 and x < out.get_width() and y < out.get_height():
					out.set_pixel(x, y, color)
		for y: int in range(ring.position.y, ring.end.y):
			for x: int in [ring.position.x, ring.end.x - 1]:
				if x >= 0 and y >= 0 and x < out.get_width() and y < out.get_height():
					out.set_pixel(x, y, color)

	if _every:
		out.resize(out.get_width() * SCALE, out.get_height() * SCALE, Image.INTERPOLATE_NEAREST)

	var name: String = "ctx_ts%d_%d.png" % [number, tile]
	out.save_png("%s/%s" % [_out, name])
	return name
