extends SceneTree

## WHERE THE RING'S OUTER EDGE CUTS A DRAWING, and how much deeper the ring
## would have to reach to clear it. `mesher.gd:_ring_side` grows a side while its
## outermost row carries a wall or a roof and gives up past `RING_GROWTH`.

const MOD := "user://mods/voxel3d"
const SIDES: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]
const NAMES: Array[String] = ["west", "east", "north", "south"]

## Past this many tiles beyond the base a side is a town rather than a house, and
## the answer is how far it asked rather than how far it would have to go.
const CAP: int = 64


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [group,number]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var only := Vector2i(-1, -1)
	if args.size() > 1:
		var pair: PackedStringArray = args[1].split(",")
		only = Vector2i(int(pair[0]), int(pair[1] if pair.size() > 1 else "0"))

	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var grown: int = 0
	var refused: Array = []
	for map: Gen2WorldMap in data.world_maps():
		if only.x >= 0 and (map.group != only.x or map.number != only.y):
			continue
		grown += _read_map(mesher, data, map, refused)
	_report(mesher, grown, refused)
	quit()


## Every side of one map, growing it the way `_ring_side` does. Answers how many
## of its sides grew and cleared, and appends the ones that could not.
func _read_map(
	mesher: RefCounted, data: GameData, map: Gen2WorldMap, refused: Array
) -> int:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return 0
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript) \
		.new(profile, map.tileset)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript) \
		.new(null, map, tileset, data)
	mesher.resolve(source, shape)
	var base: int = mesher._ring_depth(source, shape) if mesher._outside else 0
	if base <= 0:
		return 0
	var grown: int = 0
	for index: int in SIDES.size():
		var asked: int = _asks(mesher, source, shape, base, SIDES[index])
		if asked == 0:
			continue
		if asked <= mesher.RING_GROWTH:
			grown += 1
			continue
		refused.append([
			"%d,%d" % [map.group, map.number], NAMES[index], asked,
			_cut_tiles(mesher, source, shape, base, SIDES[index]),
		])
	return grown


## How many tiles beyond the base this side would have to reach before its
## outermost row is clear, or 0 where the base is already clear.
func _asks(
	mesher: RefCounted, source: RefCounted, shape: RefCounted, base: int,
	out: Vector2i
) -> int:
	var depth: int = base
	while depth <= base + CAP \
			and mesher._ring_cuts(source, shape, base, depth, out):
		depth += mesher.CELL_TILES
	return depth - base


## How many tiles of the outermost row carry a wall or a roof.
func _cut_tiles(
	mesher: RefCounted, source: RefCounted, shape: RefCounted, base: int,
	out: Vector2i
) -> int:
	var size: Vector2i = mesher._map_size
	var count: int = 0
	if out.y != 0:
		var ty: int = -base if out.y < 0 else size.y + base - 1
		for tx: int in range(-base, size.x + base):
			count += int(mesher._ring_building(source, shape, tx, ty))
		return count
	var tx: int = -base if out.x < 0 else size.x + base - 1
	for ty: int in range(-base, size.y + base):
		count += int(mesher._ring_building(source, shape, tx, ty))
	return count


func _report(mesher: RefCounted, grown: int, refused: Array) -> void:
	print("RING_GROWTH is %d tiles and a side grows %d at a time" % [
		mesher.RING_GROWTH, mesher.CELL_TILES
	])
	print("%d sides grow and clear" % grown)
	var maps: Dictionary = {}
	var tiles: int = 0
	refused.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for row: Array in refused:
		maps[row[0]] = true
		tiles += int(row[3])
		print("  %-6s %-6s asks %3d more tiles, %2d cut" % [
			row[0], row[1], row[2], row[3]
		])
	print("%d maps hold a drawing the edge cuts, %d tiles over %d sides" % [
		maps.size(), tiles, refused.size()
	])
