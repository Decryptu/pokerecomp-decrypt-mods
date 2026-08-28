extends SceneTree

## One drawing's PALETTE INDICES printed as text, and which of them the tileset
## calls its darkest shade.

const MOD := "user://mods/voxel3d"
const TILE: int = 8


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <tileset> <tile> [tile ...] [--across N]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var want: int = int(args[1])
	var across: int = 2
	var tiles: Array = []
	var index: int = 2
	while index < args.size():
		if args[index] == "--across" and index + 1 < args.size():
			across = maxi(int(args[index + 1]), 1)
			index += 2
			continue
		tiles.append(int(args[index]))
		index += 1
	if tiles.is_empty():
		print("no tiles given")
		quit(1)
		return

	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.tileset == want:
			map = candidate
			break
	if map == null:
		print("no map on tileset ", want)
		quit(1)
		return
	var tileset: Gen2WorldTileset = data.world_tileset(want)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	if not atlas.build(data, map, tileset, 1):
		print("no atlas for tileset ", want)
		quit(1)
		return

	print("tileset ", want, " read on map ", map.group, ",", map.number)
	@warning_ignore("integer_division")
	var rows: int = (tiles.size() + across - 1) / across
	for row: int in rows:
		for y: int in TILE:
			var line: String = ""
			for column: int in across:
				var at: int = row * across + column
				if at >= tiles.size():
					continue
				for x: int in TILE:
					line += "%d" % atlas.pixel(int(tiles[at]), x, y)
			print("  ", line)
	for tile: int in tiles:
		var order: PackedInt32Array = atlas.shade_order(tile)
		var closed: Array = []
		for entry: int in 4:
			closed.append(1 if atlas.is_dark(tile, entry, 1) else 0)
		print("  tile %3d  darkest first %s  closed under OUTLINE 1: %s"
			% [tile, order, closed])
	quit()
