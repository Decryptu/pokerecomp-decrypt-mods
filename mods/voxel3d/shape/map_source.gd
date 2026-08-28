extends RefCounted

## What the mesher reads a map through.

var _world: Gen2WorldAPI = null
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
var _data: GameData = null
var _carried_blocks: Dictionary = {}
var _records_placements: Dictionary = {}


func _init(
	world: Gen2WorldAPI = null,
	map_record: Gen2WorldMap = null,
	tileset_record: Gen2WorldTileset = null,
	data: GameData = null,
) -> void:
	_world = world
	_data = data
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
	return Vector2i(_map.width_blocks, _map.height_blocks) * RomLayout.MAP_BLOCK_CELL_WIDTH


func tile_at(tile_x: int, tile_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	var block: int = _block_at(
		floori(float(tile_x) / float(RomLayout.MAP_BLOCK_TILE_WIDTH)),
		floori(float(tile_y) / float(RomLayout.MAP_BLOCK_TILE_WIDTH))
	)
	if block < 0:
		return -1
	return _tileset.tile_index(
		block,
		posmod(tile_y, RomLayout.MAP_BLOCK_TILE_WIDTH) * RomLayout.MAP_BLOCK_TILE_WIDTH
			+ posmod(tile_x, RomLayout.MAP_BLOCK_TILE_WIDTH),
	)


func block_at(block_x: int, block_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	return _block_at(block_x, block_y)


func _block_at(block_x: int, block_y: int) -> int:
	var drawn: int = _drawn_block(block_x, block_y)
	if drawn >= 0:
		var key: int = block_y * 4096 + block_x
		if _carried_blocks.has(key):
			return _carried_blocks[key]
		var out: int = _carried(drawn, block_x, block_y)
		_carried_blocks[key] = out
		return out
	if block_x >= 0 and block_y >= 0 \
			and block_x < _map.width_blocks and block_y < _map.height_blocks:
		var block: int = _map.block_at(block_x, block_y)
		return _map.border_block if block == 0 else block
	return _map.border_block


func _drawn_block(block_x: int, block_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	if Gen2WorldAPI.in_hardware_buffer(_map, block_x, block_y):
		if _world != null:
			return _world.drawn_block_at(block_x, block_y)
		if _data != null:
			return Gen2WorldAPI.drawn_block_for(_data, _map, block_x, block_y)
		return -1
	if _world == null and _data == null:
		return -1
	for placement: Dictionary in _placed().values():
		var near: Gen2WorldMap = placement["map"]
		if near.tileset != _tileset.number:
			continue
		var origin: Vector2i = placement["origin"]
		var local := Vector2i(block_x - origin.x, block_y - origin.y)
		if local.x < 0 or local.y < 0 \
				or local.x >= near.width_blocks or local.y >= near.height_blocks:
			continue
		var block: int = near.block_at(local.x, local.y)
		return near.border_block if block == 0 else block
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
	return _map != null and Gen2WorldPhoneHost.is_outside_environment(_map.environment)


func code_at(cell: Vector2i) -> int:
	if _map == null:
		return -1
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= _map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH \
			or cell.y >= _map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH:
		if _tileset == null:
			return -1
		return _tileset.collision_index(
			_block_at(
				floori(float(cell.x) / float(RomLayout.MAP_BLOCK_CELL_WIDTH)),
				floori(float(cell.y) / float(RomLayout.MAP_BLOCK_CELL_WIDTH))
			),
			posmod(cell.x, RomLayout.MAP_BLOCK_CELL_WIDTH),
			posmod(cell.y, RomLayout.MAP_BLOCK_CELL_WIDTH)
		)
	if _world != null:
		return _world.collision_code_at(cell)
	return _map.collision_at(cell.x, cell.y)


func permission_at(cell: Vector2i) -> int:
	if _map == null:
		return Gen2WorldCollision.WALL_TILE
	return Gen2WorldCollision.permission_for(code_at(cell))
