extends SceneTree

## How many TILES in the whole game resolve to each shape class, and on how many
## maps. Which classes are worth fixing is a question about how much of the game
## wears them, and nothing answered it before.

const MOD := "user://mods/voxel3d"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache")
		quit(1)
		return
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var tiles: Dictionary = {}
	var maps: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var here: Dictionary = {}
		for ty: int in map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2:
			for tx: int in map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2:
				var tile: int = source.tile_at(tx, ty)
				if tile < 0:
					continue
				var klass: String = str(shape.at(
					tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))
				))
				tiles[klass] = int(tiles.get(klass, 0)) + 1
				here[klass] = true
		for klass: String in here:
			maps[klass] = int(maps.get(klass, 0)) + 1
	var keys: Array = tiles.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(tiles[a]) > int(tiles[b]))
	for klass: String in keys:
		print("%-14s %8d tiles  %3d maps" % [klass, tiles[klass], maps[klass]])
	quit()
