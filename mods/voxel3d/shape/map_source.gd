extends RefCounted

## What the mesher reads a map through. Every question about a cell is answered
## here on both generations: a Generation 2 cell holds a permission byte, and a
## Generation 1 cell holds the tile it draws, which the tileset's own tables
## answer for.

var _world: Gen2WorldAPI = null
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
var _data: GameData = null
var _gen1: bool = false
var _carried_blocks: Dictionary = {}
var _records_placements: Dictionary = {}


func _init(
	world: Gen2WorldAPI = null,
	map_record: Gen2WorldMap = null,
	tileset_record: Gen2WorldTileset = null,
	data: GameData = null,
) -> void:
	_world = world
	_data = world.data if world != null else data
	_gen1 = _data != null and _data.generation == RomRegistry.GEN1
	if world != null:
		_map = world.current_map
		_tileset = world.current_tileset
	else:
		_map = map_record
		_tileset = tileset_record


func valid() -> bool:
	return _map != null and _tileset != null


func map() -> Gen2WorldMap:
	return _map


func tileset() -> Gen2WorldTileset:
	return _tileset


func size_cells() -> Vector2i:
	if _world != null:
		return _world.map_size_cells()
	if _map == null:
		return Vector2i.ZERO
	return Vector2i(_map.width_blocks, _map.height_blocks) * Gen2Layout.MAP_BLOCK_CELL_WIDTH


func tile_at(tile_x: int, tile_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	var block: int = _block_at(
		floori(float(tile_x) / float(Gen2Layout.MAP_BLOCK_TILE_WIDTH)),
		floori(float(tile_y) / float(Gen2Layout.MAP_BLOCK_TILE_WIDTH))
	)
	if block < 0:
		return -1
	return _tileset.tile_index(
		block,
		posmod(tile_y, Gen2Layout.MAP_BLOCK_TILE_WIDTH) * Gen2Layout.MAP_BLOCK_TILE_WIDTH
			+ posmod(tile_x, Gen2Layout.MAP_BLOCK_TILE_WIDTH),
	)


func block_at(block_x: int, block_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	return _block_at(block_x, block_y)


func _block_at(block_x: int, block_y: int) -> int:
	var key: int = block_y * 4096 + block_x
	if _carried_blocks.has(key):
		return _carried_blocks[key]
	var out: int = _carried(_drawn_block(block_x, block_y), block_x, block_y)
	_carried_blocks[key] = out
	return out


## The block a coordinate is drawn from, which is the host's answer inside the
## hardware buffer and a placed neighbour's own past it, the way
## `Gen2WorldAPI.expanded_block_at` walks, held to this map's tileset since the
## atlas is one tileset.
func _drawn_block(block_x: int, block_y: int) -> int:
	if Gen2WorldAPI.in_hardware_buffer(_map, block_x, block_y):
		if _world != null:
			return _world.drawn_block_at(block_x, block_y)
		return Gen2WorldAPI.drawn_block_for(_data, _map, block_x, block_y)
	for placement: Dictionary in _placed().values():
		var near: Gen2WorldMap = placement["map"]
		if near.tileset != _tileset.number:
			continue
		var origin: Vector2i = placement["origin"]
		var local := Vector2i(block_x - origin.x, block_y - origin.y)
		if local.x < 0 or local.y < 0 \
				or local.x >= near.width_blocks or local.y >= near.height_blocks:
			continue
		return Gen2WorldAPI.drawn_block_for(_data, near, local.x, local.y)
	return _map.border_block


func _placed() -> Dictionary:
	if _world != null:
		return _world.map_placements()
	if _records_placements.is_empty():
		_records_placements = Gen2WorldAPI.placements_around(_data, _map)
	return _records_placements


func _carried(drawn: int, block_x: int, block_y: int) -> int:
	if drawn != _map.border_block or _inside(block_x, block_y):
		return drawn
	if not Gen2WorldAPI.in_hardware_buffer(_map, block_x, block_y):
		return drawn
	var step := Vector2i(
		signi(mini(block_x, 0) if block_x < 0 else maxi(block_x - _map.width_blocks + 1, 0)),
		signi(mini(block_y, 0) if block_y < 0 else maxi(block_y - _map.height_blocks + 1, 0)),
	)
	var at := Vector2i(block_x, block_y)
	while step != Vector2i.ZERO:
		at -= step
		if _inside(at.x, at.y):
			return drawn
		var nearer: int = _drawn_block(at.x, at.y)
		if nearer != _map.border_block:
			return nearer
	return drawn


func _inside(block_x: int, block_y: int) -> bool:
	return block_x >= 0 and block_y >= 0 \
		and block_x < _map.width_blocks and block_y < _map.height_blocks


func outside() -> bool:
	if _map == null:
		return false
	if _gen1:
		return Gen1Layout.is_outside_tileset(_map.tileset)
	return Gen2WorldPhoneHost.is_outside_environment(_map.environment)


## The raw byte the cartridge tests at a cell, off the map from the block drawn
## there: a permission on Generation 2, the tile at the cell's foot on
## Generation 1.
func code_at(cell: Vector2i) -> int:
	if _map == null:
		return -1
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= _map.width_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH \
			or cell.y >= _map.height_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH:
		return _code_off_map(cell)
	if _world != null:
		return _world.collision_code_at(cell)
	return _map.collision_at(cell.x, cell.y)


func _code_off_map(cell: Vector2i) -> int:
	if _tileset == null:
		return -1
	return code_in_block(
		_data, _tileset,
		_block_at(
			floori(float(cell.x) / float(Gen2Layout.MAP_BLOCK_CELL_WIDTH)),
			floori(float(cell.y) / float(Gen2Layout.MAP_BLOCK_CELL_WIDTH))
		),
		posmod(cell.x, Gen2Layout.MAP_BLOCK_CELL_WIDTH),
		posmod(cell.y, Gen2Layout.MAP_BLOCK_CELL_WIDTH)
	)


## The code one of a block's four cells carries, off the tileset alone.
static func code_in_block(
	data: GameData, tileset: Gen2WorldTileset, block: int, cell_x: int, cell_y: int
) -> int:
	if data != null and data.generation == RomRegistry.GEN1:
		return tileset.tile_index(block, Gen1Layout.cell_tile_index(cell_x, cell_y))
	return tileset.collision_index(block, cell_x, cell_y)


static func permission_of(data: GameData, tileset: Gen2WorldTileset, code: int) -> int:
	if data != null and data.generation == RomRegistry.GEN1:
		return Gen2WorldCollision.gen1_permission(tileset, code)
	return Gen2WorldCollision.permission_for(code)


func permission_at(cell: Vector2i) -> int:
	if _map == null:
		return Gen2WorldCollision.WALL_TILE
	return permission_of(_data, _tileset, code_at(cell))


## `Gen2WorldCollision.grass_kind` on Generation 2; on Generation 1 the
## tileset's one grass tile under the cell, which is only ever tall.
func grass_at(cell: Vector2i) -> int:
	var code: int = code_at(cell)
	if not _gen1:
		return Gen2WorldCollision.grass_kind(code)
	if _tileset == null or _tileset.grass_tile == Gen1Layout.TILESET_NO_TILE:
		return Gen2WorldCollision.GRASS_NONE
	return Gen2WorldCollision.GRASS_TALL if code == _tileset.grass_tile \
		else Gen2WorldCollision.GRASS_NONE


## A doorway in a wall: the cell is walked through and stands as tall as what
## is around it. A warp carpet is a floor and is not one.
func is_door_at(cell: Vector2i) -> bool:
	var code: int = code_at(cell)
	if _gen1:
		return _tileset != null \
			and Gen2WorldCollision.gen1_is_door_tile(_tileset.number, code)
	return code == Gen2WorldCollision.COLL_DOOR \
		or code == Gen2WorldCollision.COLL_DOOR_79 \
		or code == Gen2WorldCollision.COLL_CAVE


## The directions a ledge hop crosses this cell in, empty for a cell that is
## not a ledge. Generation 2 says so on the ledge's own code; Generation 1 on
## the pair of tiles stood on and faced, so the cell before is read as well.
func ledge_steps_at(cell: Vector2i) -> Array:
	var code: int = code_at(cell)
	var out: Array = []
	if not _gen1 and (code & 0xF0) != Gen2WorldCollision.HI_NYBBLE_LEDGES:
		return out
	for step: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
		if _gen1:
			if _tileset != null and Gen2WorldCollision.gen1_allows_hop(
					_tileset.number, code_at(cell - step), code, step):
				out.append(step)
		elif Gen2WorldCollision.allows_hop(code, step):
			out.append(step)
	return out
