extends SceneTree

## The draw list's edits under the sprites, as Voxel 3D takes them: a written
## tile and the S.S. Anne's band through `MapSource`, the band's own sliding
## pieces and the risers beside them, a Headbutt tree's model footprint, and the
## poison flash's flood.
##
##   -- <cartridge>

const MOD := "user://mods/voxel3d"
const DOCK := Vector2i(0, 94)
## Vermilion Dock's screen corner in world pixels with the player on the
## gangway at cell 14,2, and the water tile `EraseSSAnne` writes.
const DOCK_CORNER := Vector2i(160, -32)
const WATER_TILE: int = 0x14
const GANGWAY_FOOT := Rect2(224.0, 48.0, 16.0, 0.0)

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


func _source(data: GameData, map: Gen2WorldMap) -> RefCounted:
	return (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, data.world_tileset(map.tileset), data
	)


func _dock(data: GameData) -> void:
	var map: Gen2WorldMap = data.world_map(DOCK.x, DOCK.y)
	if map == null:
		_report("Vermilion Dock is in the cache", false)
		return
	var source: RefCounted = _source(data, map)
	var plain: RefCounted = _source(data, map)
	source.set_screen_edits({Vector2i(28, 7): WATER_TILE})
	_report("a written tile is drawn", source.tile_at(28, 7) == WATER_TILE)
	_report("a written foot tile is its cell's code", source.code_at(Vector2i(14, 3)) == WATER_TILE)
	var band: Dictionary = source.band_of(
		{"top": Gen1Layout.SS_ANNE_BAND_TOP, "bottom": Gen1Layout.SS_ANNE_BAND_BOTTOM, "offset": 1},
		DOCK_CORNER
	)
	source.set_screen_edits({}, band)
	_report("the band covers tile rows 6 to 11", source.band_rows() == Vector2i(6, 12))
	_report("the band past the screen copies its last two columns",
		source.tile_at(45, 8) == plain.tile_at(39, 8)
			and source.tile_at(44, 8) == plain.tile_at(38, 8))
	_report("the band inside the screen is the map", source.tile_at(30, 8) == plain.tile_at(30, 8))
	_band_pieces(data, map, source)


func _band_pieces(data: GameData, map: Gen2WorldMap, source: RefCounted) -> void:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		(load("%s/shape/profiles.gd" % MOD) as GDScript).of(data), tileset.name
	)
	var meshes: Array = mesher.build(source, shape, atlas) + mesher.take_water()
	var width: float = float(map.width_blocks * 32)
	var inside: bool = true
	var reached: bool = false
	var still_past: bool = false
	for mesh: ArrayMesh in meshes:
		var box: AABB = mesh.get_aabb()
		if mesh.has_meta(&"scrolled"):
			inside = inside and box.position.z >= 48.0 and box.end.z <= 96.0
			reached = reached or box.end.x > width
		else:
			still_past = still_past or box.end.x > width
	_report("scrolled pieces stay in the band's rows", inside)
	_report("the band reaches past the map to stand behind the ship", reached)
	_report("nothing else reaches past the map", not still_past)
	_report("the gangway has a riser down to the water", _has_riser(meshes))


func _has_riser(meshes: Array) -> bool:
	for mesh: ArrayMesh in meshes:
		if mesh.has_meta(&"scrolled"):
			continue
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if vertex.z == GANGWAY_FOOT.position.y and vertex.y < 0.0 \
					and vertex.x >= GANGWAY_FOOT.position.x \
					and vertex.x <= GANGWAY_FOOT.end.x:
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
	mesher.build(_source(data, map), shape, atlas)
	var tiles := Rect2i(cell * 2, Vector2i(2, 2))
	var covered: bool = false
	for model: Array in mesher.take_models():
		for footprint: Rect2i in model[4] as Array:
			covered = covered or footprint.intersects(tiles)
	_report("map %d,%d's Headbutt tree at %s has a model to take away" % [
		map.group, map.number, str(cell)], covered)


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
