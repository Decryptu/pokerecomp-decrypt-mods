extends SceneTree

## WHICH BLOCKS OF A TILESET HOLD A TILE, and how often the game places each.

const BLOCK_TILES: int = 4


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <tileset> <tile id> [tile id...]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var number: int = int(args[1])
	var wanted: Dictionary = {}
	for at: int in range(2, args.size()):
		wanted[int(args[at])] = true
	var tileset: Gen2WorldTileset = data.world_tileset(number)
	if tileset == null:
		print("no tileset ", number)
		quit(1)
		return

	var holds: Dictionary = {}
	for block: int in tileset.block_count:
		var found: Array[String] = []
		for slot: int in BLOCK_TILES * BLOCK_TILES:
			if wanted.has(tileset.tile_index(block, slot)):
				@warning_ignore("integer_division")
				found.append("%d at %d,%d" % [
					tileset.tile_index(block, slot),
					slot % BLOCK_TILES, slot / BLOCK_TILES
				])
		if not found.is_empty():
			holds[block] = found

	var placed: Dictionary = {}
	var maps_of: Dictionary = {}
	var where: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if map.tileset != number:
			continue
		for by: int in map.height_blocks:
			for bx: int in map.width_blocks:
				var block: int = map.block_at(bx, by)
				if not holds.has(block):
					continue
				placed[block] = int(placed.get(block, 0)) + 1
				var key: String = "%d,%d" % [map.group, map.number]
				if not maps_of.has(block):
					maps_of[block] = {}
					where[block] = "%s @ block %d,%d" % [key, bx, by]
				(maps_of[block] as Dictionary)[key] = true

	var order: Array = holds.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		return int(placed.get(a, 0)) > int(placed.get(b, 0)))
	print("tileset %d, %d blocks hold %s" % [number, holds.size(), wanted.keys()])
	for block: int in order:
		print("  block %-3d placed %4d times on %2d maps   %s" % [
			block, int(placed.get(block, 0)),
			(maps_of.get(block, {}) as Dictionary).size(),
			where.get(block, "nowhere")
		])
		for row: int in BLOCK_TILES:
			var line: Array[String] = []
			for column: int in BLOCK_TILES:
				var id: int = tileset.tile_index(block, row * BLOCK_TILES + column)
				line.append("%s%3d%s" % [
					"[" if wanted.has(id) else " ", id, "]" if wanted.has(id) else " "
				])
			print("      ", "".join(line))
	quit()
