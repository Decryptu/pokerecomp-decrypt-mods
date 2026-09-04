extends SceneTree

## Paints ONE block of a tileset, repeated, the way the cartridge draws it.

const TILE: int = 8
const BLOCK_TILES: int = 4


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: <cache> <tileset|map> <block|group> <out.png|number> [repeat] [scale]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return

	var map: Gen2WorldMap = null
	var tileset_number: int = 0
	var block: int = 0
	var rest: int = 0
	if args[1] == "map":
		for candidate: Gen2WorldMap in data.world_maps():
			if candidate.group == int(args[2]) and candidate.number == int(args[3]):
				map = candidate
		if map == null:
			print("no map ", args[2], ",", args[3])
			quit(1)
			return
		tileset_number = map.tileset
		block = map.border_block
		rest = 4
	else:
		tileset_number = int(args[1])
		block = int(args[2])
		rest = 3
	var tileset: Gen2WorldTileset = data.world_tileset(tileset_number)
	if tileset == null:
		print("no tileset ", tileset_number)
		quit(1)
		return

	var out: String = args[rest]
	if PokeToolPath.refuses(out):
		quit(2)
		return
	var repeat: int = int(args[rest + 1]) if args.size() > rest + 1 else 4
	var scale: int = int(args[rest + 2]) if args.size() > rest + 2 else 4

	if map == null:
		for candidate: Gen2WorldMap in data.world_maps():
			if candidate.tileset == tileset_number:
				map = candidate
				break
	var indices: PackedByteArray = data.world_tileset_indices(tileset_number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		data, map, tileset, Gen2WorldPalette.TIME_DAY, -1, -1
	)

	var side: int = repeat * BLOCK_TILES * TILE
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	for copy_y: int in repeat:
		for copy_x: int in repeat:
			for index: int in BLOCK_TILES * BLOCK_TILES:
				var tile: int = tileset.tile_index(block, index)
				@warning_ignore("integer_division")
				var at := Vector2i(
					(copy_x * BLOCK_TILES + (index % BLOCK_TILES)) * TILE,
					(copy_y * BLOCK_TILES + (index / BLOCK_TILES)) * TILE
				)
				_paint(image, indices, palettes, tile, at, tileset.tile_count)
	if scale > 1:
		image.resize(side * scale, side * scale, Image.INTERPOLATE_NEAREST)
	image.save_png(out)
	print("tileset ", tileset_number, " block ", block, " -> ", out)
	quit()


func _paint(
	image: Image, indices: PackedByteArray, palettes: Array,
	tile: int, at: Vector2i, count: int
) -> void:
	var palette: PackedColorArray = palettes[tile] if tile < palettes.size() else PackedColorArray()
	var stride: int = count * TILE
	for y: int in TILE:
		for x: int in TILE:
			var source: int = y * stride + tile * TILE + x
			if source >= indices.size():
				continue
			var color_index: int = int(indices[source])
			image.set_pixel(
				at.x + x, at.y + y,
				palette[color_index] if color_index < palette.size() else Color.BLACK
			)
