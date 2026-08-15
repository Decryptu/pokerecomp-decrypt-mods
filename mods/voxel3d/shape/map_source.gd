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
## `_carried`'s answer per block position, which is a fact about the records and
## about nothing that changes while a map is loaded.
var _carried_blocks: Dictionary = {}


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
	var drawn: int = _drawn_block(block_x, block_y)
	if drawn >= 0:
		# Asked once per TILE and answered once per BLOCK: the ring alone is sixteen
		# lookups a block before `_carried` walks anything, and the walk is up to
		# four more. `changeblock` is the only thing that moves an answer and it
		# never reaches outside the map, which is the only place this is consulted.
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


## The host's own answer, or -1 where this source is holding no records.
func _drawn_block(block_x: int, block_y: int) -> int:
	if _world != null:
		return _world.drawn_block_at(block_x, block_y)
	if _data != null:
		return Gen2WorldAPI.drawn_block_for(_data, _map, block_x, block_y)
	return -1


## A CONNECTION IS NARROWER THAN THIS RING, and the last block it hands over is
## carried the rest of the way out.
##
## The cartridge pads a connection by three blocks, which is what a Game Boy
## screen can ever show past a seam. This ring is four deep wherever the border
## block is a stamped model, so its outermost ring came back as the map's own
## border block: on a city with a road running out of it, the road stopped dead
## one block short of the edge and a wall of hedge stood across it.
##
## So a block OUTSIDE the map that came back the border block takes the nearest
## block between it and the map, if that one is outside the map too and is not
## the border block. Only the connection can put a non-border block out there, so
## nothing on a map without one moves by a tile, and the map's own art is never
## reached: the walk stops at the seam.
func _carried(drawn: int, block_x: int, block_y: int) -> int:
	if drawn != _map.border_block or _inside(block_x, block_y):
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
