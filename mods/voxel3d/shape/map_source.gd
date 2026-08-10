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


## Pass a world to read it live, or a map and tileset to read the records. A
## world supplies its own two records, so the later arguments are ignored.
func _init(
	world: Gen2WorldAPI = null,
	map: Gen2WorldMap = null,
	tileset: Gen2WorldTileset = null,
) -> void:
	_world = world
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


## The graphics tile id at a tile position, or -1 outside the map.
func tile_at(tile_x: int, tile_y: int) -> int:
	if _world != null:
		return _world.tile_index_at(tile_x, tile_y)
	if _map == null or _tileset == null:
		return -1
	var width: int = _map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH
	var height: int = _map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH
	if tile_x < 0 or tile_y < 0 or tile_x >= width or tile_y >= height:
		return -1
	@warning_ignore("integer_division")
	var block: int = _map.block_at(
		tile_x / RomLayout.MAP_BLOCK_TILE_WIDTH, tile_y / RomLayout.MAP_BLOCK_TILE_WIDTH
	)
	return _tileset.tile_index(
		block,
		(tile_y & 3) * RomLayout.MAP_BLOCK_TILE_WIDTH + (tile_x & 3),
	)


## Whether the map is out of doors, which is the host's own question to answer:
## `Gen2WorldPhoneHost.is_outside_environment` is what the game asks before it
## lets a phone call through or clears a Flash.
func outside() -> bool:
	return _map != null and Gen2WorldPhoneHost.is_outside_environment(_map.environment)


## The walk cell's collision permission, which is what decides a shape.
func permission_at(cell: Vector2i) -> int:
	if _world != null:
		return _world.collision_permission_at(cell)
	if _map == null:
		return Gen2WorldCollision.WALL_TILE
	return Gen2WorldCollision.permission_for(_map.collision_at(cell.x, cell.y))
