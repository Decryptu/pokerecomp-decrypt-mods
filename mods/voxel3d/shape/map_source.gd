extends RefCounted

## What the mesher reads a map through, live or recorded. The host's
## `Gen2WorldCollision` answers what a cell's code means on either generation.

var _world: Gen2WorldAPI = null
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
var _data: GameData = null
var _gen1: bool = false
var _carried_blocks: Dictionary = {}
var _records_placements: Dictionary = {}
var _draw_list: Gen2WorldDrawList = null
var _changed: Dictionary = {}
var _written: Dictionary = {}
var _band_rows := Vector2i.ZERO
var _band_reach: int = 0
var _edited_any: bool = false


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


## The live map's edits under the sprites: the tiles the screen wrote and the
## band's rows are read back through `Gen2WorldDrawList.drawn_tile_at`.
func set_draw_list(draw_list: Gen2WorldDrawList) -> void:
	_draw_list = draw_list
	var band: Dictionary = draw_list.band() if draw_list != null else {}
	_band_rows = band.get("rows", Vector2i.ZERO)
	_band_reach = ceili(float(band.get("reach", 0)) / float(PokeTiles.TILE_WIDTH))
	_written = draw_list.tile_overrides().duplicate() if draw_list != null else {}
	_edited_any = not _written.is_empty() or _band_rows != Vector2i.ZERO


## A recorded map as it stood: `Gen2BattleWorldContext.changed_blocks` and
## `written_tiles`.
func set_map_as_it_stood(changed_blocks: Dictionary, written_tiles: Dictionary) -> void:
	_changed = changed_blocks
	_written = written_tiles
	_carried_blocks = {}
	_edited_any = not _written.is_empty()


func band_rows() -> Vector2i:
	return _band_rows


## The most tiles the band slides west in this run.
func band_reach_tiles() -> int:
	return _band_reach


func tile_at(tile_x: int, tile_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	if _edited_any and _edited(Vector2i(tile_x, tile_y)):
		return _drawn_edit(Vector2i(tile_x, tile_y))
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


func _in_band(tile_y: int) -> bool:
	return tile_y >= _band_rows.x and tile_y < _band_rows.y


func _edited(tile: Vector2i) -> bool:
	return _in_band(tile.y) or _written.has(tile)


func _drawn_edit(tile: Vector2i) -> int:
	if _draw_list != null:
		return _draw_list.drawn_tile_at(tile)
	return int(_written[tile])


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
		if _changed.has(Vector2i(block_x, block_y)):
			return Gen2WorldAPI.drawn_block_of(_data, _map, int(_changed[Vector2i(block_x, block_y)]))
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
	return _map != null and _map.is_outside()


## The byte the cartridge tests at a cell, off the map from the block drawn
## there, with the screen's writes and a recorded map's changed blocks.
func code_at(cell: Vector2i) -> int:
	if _map == null:
		return -1
	if _gen1 and _edited_any and _edited(Vector2i(cell.x * 2, cell.y * 2 + 1)):
		return _drawn_edit(Vector2i(cell.x * 2, cell.y * 2 + 1))
	if _off_the_records(cell):
		return _code_in_drawn_block(cell)
	if _world != null:
		return _world.collision_code_at(cell)
	return _map.collision_at(cell.x, cell.y)


## A cell the map's own collision grid does not answer for: off the map, or on
## a recorded map's changed block.
func _off_the_records(cell: Vector2i) -> bool:
	return cell.x < 0 or cell.y < 0 \
		or cell.x >= _map.width_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH \
		or cell.y >= _map.height_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH \
		or (not _changed.is_empty() and _changed.has(_block_of(cell)))


func _code_in_drawn_block(cell: Vector2i) -> int:
	if _tileset == null:
		return -1
	var block: Vector2i = _block_of(cell)
	return Gen2WorldCollision.cell_code(
		_data, _tileset, _block_at(block.x, block.y),
		posmod(cell.x, Gen2Layout.MAP_BLOCK_CELL_WIDTH),
		posmod(cell.y, Gen2Layout.MAP_BLOCK_CELL_WIDTH)
	)


static func _block_of(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(Gen2Layout.MAP_BLOCK_CELL_WIDTH)),
		floori(float(cell.y) / float(Gen2Layout.MAP_BLOCK_CELL_WIDTH))
	)


func permission_at(cell: Vector2i) -> int:
	if _map == null:
		return Gen2WorldCollision.WALL_TILE
	return Gen2WorldCollision.cell_permission(_data, _tileset, code_at(cell))


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
	return Gen2WorldCollision.cell_is_door(_data, _tileset, code_at(cell))


const HOPS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]


## The directions a ledge hop leaves this cell in, over the ledge in the next.
func ledge_steps_at(cell: Vector2i) -> Array:
	var out: Array = []
	var here: int = code_at(cell)
	for step: Vector2i in HOPS:
		if Gen2WorldCollision.cell_hops(_data, _tileset, here, code_at(cell + step), step):
			out.append(step)
	return out
