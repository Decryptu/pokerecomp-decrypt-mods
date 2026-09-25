extends SceneTree

## The draw list's edits under the sprites, as Voxel 3D takes them: a written
## tile and the S.S. Anne's band through `MapSource`, the band's own sliding
## pieces and the risers beside them, a battle staged on the map as it stood, a
## Headbutt tree's model footprint, and the poison flash's flood.
##
##   -- <cartridge>

const MOD := "user://mods/voxel3d"
const DOCK := Vector2i(0, 94)
## Where the player stands on Vermilion Dock while the ship leaves.
const GANGWAY := Vector2i(14, 2)
const CELL_PIXELS: float = 16.0

var _failed: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cartridge>")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return
	if data.generation == RomRegistry.GEN1:
		_dock(data)
	else:
		_headbutt(data)
	_flood()
	print("%s" % ("all passed" if _failed == 0 else "%d FAILED" % _failed))
	quit(0 if _failed == 0 else 1)


func _report(what: String, passed: bool) -> void:
	print("%s  %s" % ["ok  " if passed else "FAIL", what])
	if not passed:
		_failed += 1


func _source(world: Gen2WorldAPI) -> RefCounted:
	return (load("%s/shape/map_source.gd" % MOD) as GDScript).new(world)


func _staged(data: GameData, map: Gen2WorldMap, cell: Vector2i) -> Gen2WorldAPI:
	return Gen2WorldAPI.new(data, map, data.world_tileset(map.tileset), cell)


func _dock(data: GameData) -> void:
	var map: Gen2WorldMap = data.world_map(DOCK.x, DOCK.y)
	if map == null:
		_report("Vermilion Dock is in the cache", false)
		return
	_written(data, map)
	_band(data, map)
	_battle(_staged(data, map, GANGWAY), Gen1Layout.SS_ANNE_ERASE_AT, Gen1Layout.SS_ANNE_WATER_BLOCK)


func _written(data: GameData, map: Gen2WorldMap) -> void:
	var world: Gen2WorldAPI = _staged(data, map, GANGWAY)
	var list := Gen2WorldDrawList.new(world, Gen2WorldEffects.new())
	var foot := Vector2i(world.screen_origin_tile().x + 8, GANGWAY.y * 2 + 1)
	_write_row(world, foot.y)
	var source: RefCounted = _source(world)
	source.set_draw_list(list)
	_report("a written tile is drawn",
		source.tile_at(foot.x, foot.y) == Gen1Layout.SS_ANNE_WATER_TILE)
	_report("a written foot tile is its cell's code",
		source.code_at(Vector2i(foot.x / 2, GANGWAY.y)) == Gen1Layout.SS_ANNE_WATER_TILE)


func _write_row(world: Gen2WorldAPI, tile_y: int) -> void:
	world.erase_screen_rows(tile_y - world.screen_origin_tile().y, 1, Gen1Layout.SS_ANNE_WATER_TILE)


func _band(data: GameData, map: Gen2WorldMap) -> void:
	var world: Gen2WorldAPI = _staged(data, map, GANGWAY)
	var effects := Gen2WorldEffects.new()
	var list := Gen2WorldDrawList.new(world, effects)
	effects.start_gen1_ss_anne()
	while effects.ss_anne_band_offset() == 0:
		effects.advance_frame()
	var source: RefCounted = _source(world)
	source.set_draw_list(list)
	var band: Dictionary = list.band()
	var rows: Vector2i = band["rows"]
	var same: bool = true
	for y: int in range(rows.x - 1, rows.y + 1):
		for x: int in map.width_blocks * 4 + source.band_reach_tiles():
			same = same and source.tile_at(x, y) == list.drawn_tile_at(Vector2i(x, y))
	_report("the map around and inside the band is the tile the host draws", same)
	_band_pieces(data, map, source, rows)


func _band_pieces(data: GameData, map: Gen2WorldMap, source: RefCounted, rows: Vector2i) -> void:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		(load("%s/shape/profiles.gd" % MOD) as GDScript).of(data), tileset.name
	)
	var meshes: Array = mesher.build(source, shape, atlas) + mesher.take_water()
	var width: float = float(map.width_blocks * 32)
	var band := Vector2(rows) * float(PokeTiles.TILE_HEIGHT)
	var inside: bool = true
	var reached: bool = false
	var still_past: bool = false
	for mesh: ArrayMesh in meshes:
		var box: AABB = mesh.get_aabb()
		if mesh.has_meta(&"scrolled"):
			inside = inside and box.position.z >= band.x and box.end.z <= band.y
			reached = reached or box.end.x > width
		else:
			still_past = still_past or box.end.x > width
	_report("scrolled pieces stay in the band's rows", inside)
	_report("the band reaches past the map to stand behind the ship", reached)
	_report("nothing else reaches past the map", not still_past)
	_report("the gangway has a riser down to the water", _has_riser(
		meshes, Rect2(float(GANGWAY.x) * CELL_PIXELS, band.x, CELL_PIXELS, 0.0)
	))


## A battle staged from `Gen2BattleWorldContext` sees the map as it stood: a
## changed block, and on Generation 1 a written tile.
func _battle(world: Gen2WorldAPI, at: Vector2i, block: int) -> void:
	var gen1: bool = world.data.generation == RomRegistry.GEN1
	var tileset: Gen2WorldTileset = world.current_tileset
	world.change_block(at.x, at.y, block)
	var written := Vector2i(world.screen_origin_tile().x, GANGWAY.y * 2 + 1)
	if gen1:
		_write_row(world, written.y)
	var context: Gen2BattleWorldContext = Gen2BattleWorldContext.capture(world)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, world.current_map, tileset, world.data
	)
	source.set_map_as_it_stood(context.changed_blocks, context.written_tiles)
	var tile: Vector2i = at * Gen2Layout.MAP_BLOCK_TILE_WIDTH
	_report("a battle's arena has the changed block",
		source.tile_at(tile.x, tile.y) == tileset.tile_index(block, 0)
			and source.code_at(at * Gen2Layout.MAP_BLOCK_CELL_WIDTH)
				== source.code_in_block(world.data, tileset, block, 0, 0))
	if gen1:
		_report("a battle's arena has the written tile",
			source.tile_at(written.x, written.y) == Gen1Layout.SS_ANNE_WATER_TILE)


func _has_riser(meshes: Array, foot: Rect2) -> bool:
	for mesh: ArrayMesh in meshes:
		if mesh.has_meta(&"scrolled"):
			continue
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if vertex.z == foot.position.y and vertex.y < 0.0 \
					and vertex.x >= foot.position.x and vertex.x <= foot.end.x:
				return true
	return false


func _headbutt(data: GameData) -> void:
	var found: Array = _headbutt_tree(data)
	if found.is_empty():
		_report("a Headbutt tree is in the cache", false)
		return
	var map: Gen2WorldMap = found[0]
	var cell: Vector2i = found[1]
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		(load("%s/shape/profiles.gd" % MOD) as GDScript).of(data), tileset.name
	)
	mesher.build((load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	), shape, atlas)
	var tiles := Rect2i(cell * 2, Vector2i(2, 2))
	var covered: bool = false
	for model: Array in mesher.take_models():
		for footprint: Rect2i in model[4] as Array:
			covered = covered or footprint.intersects(tiles)
	_report("map %d,%d's Headbutt tree at %s has a model to take away" % [
		map.group, map.number, str(cell)], covered)
	_hidden_tree(data, map, cell)
	var block: Vector2i = cell / Gen2Layout.MAP_BLOCK_CELL_WIDTH
	_battle(
		_staged(data, map, cell + Vector2i.DOWN), block,
		maxi((map.block_at(block.x, block.y) + 1) % tileset.block_count, 1)
	)


## A hidden tree is the model's to take away: the map is not built again and
## reads the tree where it stands.
func _hidden_tree(data: GameData, map: Gen2WorldMap, cell: Vector2i) -> void:
	var world: Gen2WorldAPI = _staged(data, map, cell + Vector2i.DOWN)
	var effects := Gen2WorldEffects.new()
	var list := Gen2WorldDrawList.new(world, effects)
	var revision: int = list.drawn_revision()
	var tile: Vector2i = cell * 2
	var standing: int = list.drawn_tile_at(tile)
	effects.start_headbutt_tree(cell)
	var source: RefCounted = _source(world)
	source.set_draw_list(list)
	_report("a hidden tree builds nothing again",
		not list.hidden_tree_cells().is_empty() and list.drawn_revision() == revision
			and source.tile_at(tile.x, tile.y) == standing)


## The first `COLL_HEADBUTT_TREE` with open ground south of it, the cell a
## player headbutts from.
func _headbutt_tree(data: GameData) -> Array:
	for map: Gen2WorldMap in data.world_maps():
		for y: int in map.height_blocks * 2 - 1:
			for x: int in map.width_blocks * 2:
				if map.collision_at(x, y) == Gen2WorldCollision.COLL_HEADBUTT_TREE \
						and map.collision_at(x, y + 1) == 0:
					return [map, Vector2i(x, y)]
	return []


func _flood() -> void:
	var stage: RefCounted = (load("%s/world/diorama.gd" % MOD) as GDScript).new()
	var sheet := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	stage.set_texture(sheet)
	var colour: Color = Gen2WorldPalette.poison_flash_palette()[0]
	stage.set_flood(colour)
	var flooded: Texture2D = stage._material.albedo_texture
	_report("the flood paints the ground one colour",
		flooded != sheet and flooded.get_size() == Vector2.ONE)
	_report("the flood reaches the models and the far field",
		stage._wind.foliage.get_shader_parameter("flood") == colour
			and stage._far._flood == colour)
	stage.set_flood(Color(0, 0, 0, 0))
	_report("the flood gives the ground back", stage._material.albedo_texture == sheet)
	stage.container.free()
