extends SceneTree

## Every tile in the game that RESOLVES to one shape class, PER DRAWING, with how
## many maps place it and where the first one is.
##
## `census.gd` says how much of the game wears each class and this says what is
## inside one, which is the question that actually chooses the next piece of
## work: `stand` is the full pass's fallback for something standing, and looking
## at its contents drawing by drawing is what found the boulders, the railing,
## the notice board, the statues, the stools and the fence, each of them cheaper
## to build right than to leave wrong.
##
## IT COUNTS THE CLASS AND NOT WHAT IS DRAWN, which trips every reading of it: an
## OBJECT or a STAIRCASE is found by its tile arrangement afterwards and
## overrides the art, so a drawing already built correctly is still counted here.
## Six hundred of `stand`'s tiles are that. Check a group against `OBJECTS`
## before believing it is a fault.
##
##   Godot --headless --path <pokerecomp> -s tools/class_tail.gd -- <cache> \
##       <class> [tileset]

const MOD := "user://mods/voxel3d"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache")
		quit(1)
		return
	var want: String = args[1]
	var only: int = int(args[2]) if args.size() > 2 else -1
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var counts: Dictionary = {}
	var maps_of: Dictionary = {}
	var where: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		for ty: int in map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2:
			for tx: int in map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2:
				var tile: int = source.tile_at(tx, ty)
				if tile < 0:
					continue
				if str(shape.at(
					tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))
				)) != want:
					continue
				var key: String = "ts%d %d" % [map.tileset, tile]
				counts[key] = int(counts.get(key, 0)) + 1
				var seen: Dictionary = maps_of.get(key, {})
				seen["%d,%d" % [map.group, map.number]] = true
				maps_of[key] = seen
				if not where.has(key):
					where[key] = "%d,%d @ %d,%d" % [map.group, map.number, tx, ty]
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a]) > int(counts[b]))
	var total: int = 0
	for key: String in keys:
		total += int(counts[key])
		print("%6d tiles  %3d maps  %-10s  %s" % [
			counts[key], (maps_of[key] as Dictionary).size(), key, where[key]
		])
	print("total ", total, " tiles in ", keys.size(), " drawings")
	quit()
