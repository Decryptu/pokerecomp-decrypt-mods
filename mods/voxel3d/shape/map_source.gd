extends RefCounted

## What the mesher reads a map through.
##
## The overworld builds from the LIVE world, because `changeblock` replaces
## blocks under the player and the two views have to agree. A battle staged on
## the map has no world to read: `Gen2BattleWorldContext` names the map and its
## tileset by number and deliberately hands over no handle, so the same geometry
## is built from the records instead.
##
## Both answer the same three questions, which is all the mesher ever asks.

var _world: Gen2WorldAPI = null
var _map: Gen2WorldMap = null
var _tileset: Gen2WorldTileset = null
## Only the records path needs it, and only to fold a CONNECTION into the border
## ring: reading past a map's edge can reach the neighbouring map, which means
## reaching another map's records.
var _data: GameData = null


## Pass a world to read it live, or a map and tileset to read the records. A
## world supplies its own two records, so those arguments are ignored.
func _init(
	world: Gen2WorldAPI = null,
	map: Gen2WorldMap = null,
	tileset: Gen2WorldTileset = null,
	data: GameData = null,
) -> void:
	_world = world
	_data = data
	if world != null:
		_map = world.current_map
		_tileset = world.current_tileset
	else:
		_map = map
		_tileset = tileset


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


## The graphics tile id at a tile position, PAST THE MAP EDGE AS WELL.
##
## Past the edge the cartridge draws the map's own border block, or the
## neighbouring map's art where there is a connection, and it is the same answer
## the 2D view is drawn from: `drawn_block_at` is the host's own fold of the two
## and `visible_tile_indices` goes through it for every tile of every frame.
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


## The block drawn at a block position, inside the map or past its edge.
##
## The host folds in the map's border block AND its CONNECTIONS, which is what
## makes a neighbouring route's own art carry on past the seam. Both paths ask
## the same code for it: `drawn_block_at` reads the live world, including any
## `changeblock` the player has caused, and `drawn_block_for` answers for a map
## record, which is what a battle has. The connection padding's strip geometry
## and its north/south/west/east order at an overlapping corner are the host's,
## and a second copy of them here would be a second thing to keep right.
func _block_at(block_x: int, block_y: int) -> int:
	if _world != null:
		return _world.drawn_block_at(block_x, block_y)
	if _data != null:
		return Gen2WorldAPI.drawn_block_for(_data, _map, block_x, block_y)
	# No records but this map's own, which a probe or a tool may be holding.
	if block_x >= 0 and block_y >= 0 \
			and block_x < _map.width_blocks and block_y < _map.height_blocks:
		var block: int = _map.block_at(block_x, block_y)
		return _map.border_block if block == 0 else block
	return _map.border_block


## Whether the map is out of doors, which is the host's own question to answer:
## `Gen2WorldPhoneHost.is_outside_environment` is what the game asks before it
## lets a phone call through or clears a Flash.
func outside() -> bool:
	return _map != null and Gen2WorldPhoneHost.is_outside_environment(_map.environment)


## The walk cell's WHOLE collision byte, or -1 off the map.
##
## The permission is only half of what that byte says. The other half is the
## jumping ledges: which way one can be hopped over is in the low bits, and
## `Gen2WorldCollision.allows_hop` decodes them against the cartridge's own
## .TryJump. Nothing in the tile layer says it.
func code_at(cell: Vector2i) -> int:
	if _map == null:
		return -1
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= _map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH \
			or cell.y >= _map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH:
		# Past the edge the drawn block carries its own collision, which is what
		# says whether the ring is walked on or stood up. It decides a SHAPE and
		# nothing else: the player never stands there.
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
