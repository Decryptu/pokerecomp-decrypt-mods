extends SceneTree

## One drawing's PALETTE INDICES printed as text, and which of them the tileset
## calls its darkest shade.
##
## PRINT THE MASK BEFORE BELIEVING A MODELLING PROBLEM. It has settled four
## questions in a minute each and each of them looked like geometry first: the
## ship's border flood, the boulder's open ring, whether a stool wants FILLED,
## and whether the stone vessel fills its own cell. Every one of them was a fact
## about which pixels the flood can walk through, and none of them was visible in
## a render or in a triangle count.
##
##   Godot --headless --path <pokerecomp> -s tools/mask_print.gd -- <cache> \
##       <tileset> <tile> [tile ...] [--across N]
##
## The tiles are given in READING ORDER and laid out two across unless `--across`
## says otherwise, so a 2x2 drawing is `80 81 82 83`. What comes back is one
## character per pixel, the palette index the cartridge painted there.
##
## An index is not a colour: the same index is two colours under two palettes,
## which is exactly why a cutout asks about indices. `shade_order` is the tile's
## own indices ranked DARKEST FIRST, and the flags after it say which of the four
## the `OUTLINE` rule would close against.

const MOD := "user://mods/voxel3d"
const TILE: int = 8


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <tileset> <tile> [tile ...] [--across N]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
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

	# ANY map on the tileset will do: the atlas is the TILESET coloured by a map's
	# palettes, and the indices this prints are the same under every one of them.
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
