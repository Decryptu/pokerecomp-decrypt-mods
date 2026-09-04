extends SceneTree

## What the border ring is made of, over the whole game.

const RING_BLOCKS: int = 4
const WORST: int = 10


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [ring tiles] [worst count]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var ring: int = RING_BLOCKS
	if args.size() > 1:
		ring = maxi(1, ceili(float(int(args[1])) / float(Gen2Layout.MAP_BLOCK_TILE_WIDTH)))
	var worst_count: int = int(args[2]) if args.size() > 2 else WORST

	var maps: int = 0
	var moved_maps: int = 0
	var blocks: int = 0
	var moved: int = 0
	var off_tileset: int = 0
	var rows: Array = []
	for map: Gen2WorldMap in data.world_maps():
		if map == null or map.width_blocks <= 0 or map.height_blocks <= 0:
			continue
		if not Gen2WorldPhoneHost.is_outside_environment(map.environment):
			continue
		maps += 1
		var placements: Dictionary = Gen2WorldAPI.placements_around(data, map)
		var here: int = 0
		var refused: int = 0
		var seen: int = 0
		for by: int in range(-ring, map.height_blocks + ring):
			for bx: int in range(-ring, map.width_blocks + ring):
				if bx >= 0 and by >= 0 \
						and bx < map.width_blocks and by < map.height_blocks:
					continue
				seen += 1
				if Gen2WorldAPI.in_hardware_buffer(map, bx, by):
					continue
				var near: Gen2WorldMap = _neighbour_at(placements, bx, by)
				if near == null:
					continue
				if near.tileset == map.tileset:
					here += 1
				else:
					refused += 1
		blocks += seen
		moved += here
		off_tileset += refused
		if here > 0 or refused > 0:
			moved_maps += int(here > 0)
			rows.append({"map": "%d,%d" % [map.group, map.number], "moved": here,
				"refused": refused, "ring": seen, "ways": map.connections.size()})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["moved"]) > int(b["moved"]))
	print("ring       %d blocks deep, outdoor maps only" % ring)
	print("maps       %d swept, %d have a neighbour in the ring" % [maps, moved_maps])
	print("blocks     %d in the rings, %d off a real neighbour (%.1f%%)" % [
		blocks, moved, 100.0 * float(moved) / float(maxi(blocks, 1)),
	])
	print("refused    %d more on a neighbour with ANOTHER TILESET" % off_tileset)
	print("")
	print("map\tneighbour\trefused\tring\tways")
	for row: Dictionary in rows.slice(0, worst_count):
		print("%s\t%d\t%d\t%d\t%d" % [
			row["map"], row["moved"], row["refused"], row["ring"], row["ways"],
		])
	quit(0)


static func _neighbour_at(
	placements: Dictionary, block_x: int, block_y: int
) -> Gen2WorldMap:
	for placement: Dictionary in placements.values():
		var near: Gen2WorldMap = placement["map"]
		var origin: Vector2i = placement["origin"]
		var local := Vector2i(block_x - origin.x, block_y - origin.y)
		if local.x >= 0 and local.y >= 0 \
				and local.x < near.width_blocks and local.y < near.height_blocks:
			return near
	return null
