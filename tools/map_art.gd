extends SceneTree

## Paints one map's own 2D art, the way the cartridge draws it, and writes it
## out.

const TILE: int = 8
const BLOCK_TILES: int = 4
const RING_OUTER := Color(1.0, 0.0, 1.0)
const RING_INNER := Color(1.0, 1.0, 1.0)
const WINDOW: int = 22


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: <cache> <group> <number> <out.png> [scale]")
		quit(1)
		return
	if PokeToolPath.refuses(args[3]):
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.group == int(args[1]) and candidate.number == int(args[2]):
			map = candidate
	if map == null:
		print("no map ", args[1], ",", args[2])
		quit(1)
		return
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var image: Image = _paint(data, map, tileset)
	var scale: int = int(args[4]) if args.size() > 4 else 1
	var origin := Vector2i.ZERO
	if args.size() > 8:
		var ring := Rect2i(int(args[5]), int(args[6]), int(args[7]), int(args[8]))
		var window: int = int(args[9]) if args.size() > 9 else WINDOW
		origin = Vector2i(maxi(ring.position.x - window, 0),
			maxi(ring.position.y - window, 0))
		image = _ringed(image, ring, window)
	if scale > 1:
		image.resize(
			image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST
		)
	image.save_png(args[3])
	print("map ", map.group, ",", map.number, " tileset ", map.tileset,
		" tiles ", map.width_blocks * BLOCK_TILES, "x", map.height_blocks * BLOCK_TILES,
		" origin ", origin.x, ",", origin.y)
	quit()


func _ringed(image: Image, ring: Rect2i, window: int) -> Image:
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

	var margin: int = window * TILE
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
