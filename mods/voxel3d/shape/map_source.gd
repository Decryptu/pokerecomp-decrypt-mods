extends RefCounted

## What the mesher reads a map through, live or recorded. The host's
## `Gen2WorldCollision` answers what a cell's code means on either generation.
## Each tile, cell code and code's meaning is read once, so a resolve sliced
## over frames reads one state of the map.

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

const UNREAD: int = -2
const CODES: int = 256
## How far past the map a read is held; the mesher's border ring stays inside.
const HELD_PAD_CELLS: int = 24
var _held_from := Vector2i.ZERO
var _held_cells := Vector2i.ZERO
var _held_codes := PackedInt32Array()
var _held_tiles := PackedInt32Array()
var _permission_of := PackedInt32Array()
var _door_of := PackedInt32Array()
var _hops_of: Dictionary = {}


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
	for table: PackedInt32Array in [_permission_of, _door_of]:
		table.resize(CODES)
		table.fill(UNREAD)


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
	_forget_held()


## A recorded map as it stood: `Gen2BattleWorldContext.changed_blocks` and
## `written_tiles`.
func set_map_as_it_stood(changed_blocks: Dictionary, written_tiles: Dictionary) -> void:
	_changed = changed_blocks
	_written = written_tiles
	_carried_blocks = {}
	_edited_any = not _written.is_empty()
	_forget_held()


func _forget_held() -> void:
	_held_cells = Vector2i.ZERO
	_held_codes = PackedInt32Array()
	_held_tiles = PackedInt32Array()


func _hold() -> void:
	var size: Vector2i = size_cells()
	if size == Vector2i.ZERO:
		return
	_held_from = -Vector2i(HELD_PAD_CELLS, HELD_PAD_CELLS)
	_held_cells = size + Vector2i(HELD_PAD_CELLS, HELD_PAD_CELLS) * 2
	_held_codes.resize(_held_cells.x * _held_cells.y)
	_held_codes.fill(UNREAD)
	_held_tiles.resize(_held_codes.size() * CELL_TILES * CELL_TILES)
	_held_tiles.fill(UNREAD)


## The slot a cell's reads are held in, or -1 past the held border.
func _cell_slot(cell: Vector2i) -> int:
	if _held_cells == Vector2i.ZERO:
		_hold()
	var local: Vector2i = cell - _held_from
	if local.x < 0 or local.y < 0 or local.x >= _held_cells.x or local.y >= _held_cells.y:
		return -1
	return local.y * _held_cells.x + local.x


func _tile_slot(tile_x: int, tile_y: int) -> int:
	if _held_cells == Vector2i.ZERO:
		_hold()
	var width: int = _held_cells.x * CELL_TILES
	var local := Vector2i(tile_x, tile_y) - _held_from * CELL_TILES
	if local.x < 0 or local.y < 0 or local.x >= width \
			or local.y >= _held_cells.y * CELL_TILES:
		return -1
	return local.y * width + local.x


func band_rows() -> Vector2i:
	return _band_rows


## The most tiles the band slides west in this run.
func band_reach_tiles() -> int:
	return _band_reach


const CELL_TILES: int = Gen2Layout.MAP_BLOCK_CELL_WIDTH


func tile_at(tile_x: int, tile_y: int) -> int:
	var slot: int = _tile_slot(tile_x, tile_y)
	if slot < 0:
		return _read_tile(tile_x, tile_y)
	if _held_tiles[slot] == UNREAD:
		_held_tiles[slot] = _read_tile(tile_x, tile_y)
	return _held_tiles[slot]


func _read_tile(tile_x: int, tile_y: int) -> int:
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


## Everything a resolve of this map reads that can differ between two visits:
## the blocks the hardware buffer draws and the tiles the screen wrote. Two
## readings of one map that compare equal resolve alike. A scrolling band moves
## what its rows draw under any reading, so a map with one has none.
func live_state() -> Array:
	if not valid() or _band_rows != Vector2i.ZERO:
		return []
	var blocks := PackedInt32Array()
	var reach: int = Gen2WorldAPI.BUFFER_BLOCKS
	for block_y: int in range(-reach, _map.height_blocks + reach):
		for block_x: int in range(-reach, _map.width_blocks + reach):
			blocks.append(_block_at(block_x, block_y))
	return [_map.group, _map.number, _tileset.number, blocks, _written]


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
	var slot: int = _cell_slot(cell)
	if slot < 0:
		return _read_code(cell)
	if _held_codes[slot] == UNREAD:
		_held_codes[slot] = _read_code(cell)
	return _held_codes[slot]


func _read_code(cell: Vector2i) -> int:
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
	var code: int = code_at(cell)
	if code < 0 or code >= CODES:
		return Gen2WorldCollision.cell_permission(_data, _tileset, code)
	if _permission_of[code] == UNREAD:
		_permission_of[code] = Gen2WorldCollision.cell_permission(_data, _tileset, code)
	return _permission_of[code]


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
	if code < 0 or code >= CODES:
		return Gen2WorldCollision.cell_is_door(_data, _tileset, code)
	if _door_of[code] == UNREAD:
		_door_of[code] = int(Gen2WorldCollision.cell_is_door(_data, _tileset, code))
	return _door_of[code] == 1


const HOPS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]


## The directions a ledge hop leaves this cell in, over the ledge in the next.
func ledge_steps_at(cell: Vector2i) -> Array:
	var out: Array = []
	var here: int = code_at(cell)
	for side: int in HOPS.size():
		if _hops(here, code_at(cell + HOPS[side]), side):
			out.append(HOPS[side])
	return out


func _hops(here: int, over: int, side: int) -> bool:
	var key: int = ((here + 1) * (CODES + 1) + over + 1) * HOPS.size() + side
	if not _hops_of.has(key):
		_hops_of[key] = Gen2WorldCollision.cell_hops(_data, _tileset, here, over, HOPS[side])
	return _hops_of[key]
