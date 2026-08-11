extends SceneTree

## Paints one map's own 2D art, the way the cartridge draws it, and writes it out.
##
## The survey tools crop this picture around a single tile. Reading a PLATEAU
## needs the opposite: the whole shape of a cliff at once, its front, its ends
## and whatever the ground does around it, which no 15-tile window shows.
##
##   Godot --path <pokerecomp> -s tools/map_art.gd -- <cache> <group> <number> \
##       <out.png> [scale]

const TILE: int = 8
const BLOCK_TILES: int = 4


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: <cache> <group> <number> <out.png> [scale]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
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
	if scale > 1:
		image.resize(
			image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST
		)
	image.save_png(args[3])
	print("map ", map.group, ",", map.number, " tileset ", map.tileset,
		" tiles ", map.width_blocks * BLOCK_TILES, "x", map.height_blocks * BLOCK_TILES)
	quit()


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
