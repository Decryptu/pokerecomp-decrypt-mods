extends RefCounted

## What the mesher reads a map through.
##
## The overworld builds from the live world, because `changeblock` replaces
## blocks under the player and the two views have to agree. A battle has no world
## to read: `Gen2BattleWorldContext` names the map and tileset by number and hands
## over no handle, so the same geometry is built from the records instead.
##
## Both answer the same three questions, which is all the mesher asks.

var _world: Gen2WorldAPI = null
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
## Only the records path needs it, and only to fold a connection into the border
## ring: reading past a map's edge can reach another map's records.
var _data: GameData = null
## `_carried`'s answer per block position, which nothing moves while a map is
## loaded.
var _carried_blocks: Dictionary = {}
## [method _placed] for a source holding records rather than a world, which is a
## battle and every tool here. A world holds its own and this stays empty.
var _records_placements: Dictionary = {}


## Pass a world to read it live, or a map and tileset to read the records. A
## world supplies its own two records, so those arguments are ignored.
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


## The graphics tile id at a tile position, past the map edge as well: the
## connection strip the cartridge pads with, the neighbouring map beyond it, and
## this map's border block where nothing covers the ground. [method _drawn_block]
## folds those three into one answer, and the 2D view takes the same one.
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


## The block drawn at a block position, inside the map or past its edge, which is
## what [method tile_at] resolves a tile through.
##
## Public for a caller reading a whole block rather than a tile: sixteen
## `tile_at` calls answer the same block sixteen times, and a walk over a map and
## its ring is ten thousand tiles. `shape/far_drawings.gd` is the caller.
func block_at(block_x: int, block_y: int) -> int:
	if _map == null or _tileset == null:
		return -1
	return _block_at(block_x, block_y)


## The same with the carry below spent on it.
##
## Where a map sits and what the cartridge pads a seam with are the host's: the
## strip geometry, its order at an overlapping corner, and the connection graph.
## A second copy of any of them here would be a second thing to keep right.
func _block_at(block_x: int, block_y: int) -> int:
	var drawn: int = _drawn_block(block_x, block_y)
	if drawn >= 0:
		# Asked per tile and answered per block: the ring alone is sixteen lookups
		# a block before `_carried` walks, and the walk is up to four more.
		# `changeblock` never reaches outside the map, which is where this runs.
		var key: int = block_y * 4096 + block_x
		if _carried_blocks.has(key):
			return _carried_blocks[key]
		var out: int = _carried(drawn, block_x, block_y)
		_carried_blocks[key] = out
		return out
	# No records but this map's own, which a probe or a tool may be holding.
	if block_x >= 0 and block_y >= 0 \
			and block_x < _map.width_blocks and block_y < _map.height_blocks:
		var block: int = _map.block_at(block_x, block_y)
		return _map.border_block if block == 0 else block
	return _map.border_block


## The block drawn at a block position, past the map's edge as well as inside it,
## or -1 where this source holds no records.
##
## The host places whole neighbouring maps past the three-block margin
## `ChangeMap` writes, so a ring four blocks deep reads a real map out there.
## Inside the margin nothing moves: that is `wOverworldMapBlocks` byte for byte,
## connection strips and all.
##
## Composed from `map_placements` rather than `expanded_block_at`, because a
## neighbour's block is numbered in the NEIGHBOUR's tileset. The 2D view draws
## each map on a quad with its own tile strip; this mesher resolves one grid
## against one atlas, so a block from another tileset would come out as whichever
## tiles that number happens to name here. Over Crystal, 1977 ring blocks come
## off a neighbour sharing the tileset and 68 off one that does not; those 68
## take the border block.
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


## The maps the connection graph places around this one. A world holds its own; a
## source holding records walks the same host static and keeps the answer, since
## nothing a run does moves a map.
func _placed() -> Dictionary:
	if _world != null:
		return _world.map_placements()
	if _records_placements.is_empty():
		_records_placements = Gen2WorldAPI.placements_around(_data, _map)
	return _records_placements


## A connection is narrower than this ring, so the last block it hands over is
## carried the rest of the way out.
##
## The cartridge pads a connection by three blocks, which is all a Game Boy screen
## could show past a seam. This ring is four deep wherever the border block is a
## stamped model, so its outermost ring came back as the map's own border block:
## a road running out of a city stopped one block short with a wall of hedge
## across it.
##
## So a block outside the map that came back the border block takes the nearest
## block between it and the map, if that one is outside the map too and is not the
## border block. Only a connection can put a non-border block out there, so a map
## without one does not move, and the map's own art is never reached.
##
## It stops at the buffer too. Inside `wOverworldMapBlocks` a strip ends at the
## `length` the macro stored, which is the truncation this was written for.
## Outside it, a border block is the host saying no map covers this, and carrying
## a neighbour's last block into that is inventing land.
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


## Whether the map is out of doors. `Gen2WorldPhoneHost.is_outside_environment`
## is what the game asks before letting a phone call through.
func outside() -> bool:
	return _map != null and Gen2WorldPhoneHost.is_outside_environment(_map.environment)


## The walk cell's whole collision byte, or -1 off the map.
##
## The permission is half of what the byte says. The other half is the ledges:
## which way one can be hopped is in the low bits, decoded by
## `Gen2WorldCollision.allows_hop`. Nothing in the tile layer says it.
func code_at(cell: Vector2i) -> int:
	if _map == null:
		return -1
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= _map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH \
			or cell.y >= _map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH:
		# Past the edge the drawn block carries its own collision, which says
		# whether the ring is walked on or stood up. A shape and nothing else:
		# the player never stands there.
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


## The walk cell's collision permission, which is what decides a shape.
func permission_at(cell: Vector2i) -> int:
	if _map == null:
		return Gen2WorldCollision.WALL_TILE
	return Gen2WorldCollision.permission_for(code_at(cell))
