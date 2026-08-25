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
## IT COUNTS THE CLASS AND NOT WHAT IS DRAWN, and that trips every reading of it:
## an OBJECT or a STAIRCASE is found by its tile arrangement afterwards and
## overrides the art, so a drawing already built correctly still resolves to its
## class here. Half the tail was that. So the covered tiles are MARKED `built`
## and counted separately, at the placement rather than by tile id, which is the
## check a reading of this used to have to do by hand against `profile.gd` and
## twice got wrong.
##
##   Godot --headless --path <pokerecomp> -s tools/class_tail.gd -- <cache> \
##       <class> [tileset]

const MOD := "user://mods/voxel3d"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: GameData = GameData.open_argument(args[0])
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
	var built_counts: Dictionary = {}
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
		var size := Vector2i(
			map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2,
			map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2
		)
		var covered: PackedByteArray = _covered(shape, source, size)
		for ty: int in size.y:
			for tx: int in size.x:
				var tile: int = source.tile_at(tx, ty)
				if tile < 0:
					continue
				if str(shape.at(
					tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))
				)) != want:
					continue
				var key: String = "ts%d %d" % [map.tileset, tile]
				counts[key] = int(counts.get(key, 0)) + 1
				if covered[ty * size.x + tx] == 1:
					built_counts[key] = int(built_counts.get(key, 0)) + 1
				var seen: Dictionary = maps_of.get(key, {})
				seen["%d,%d" % [map.group, map.number]] = true
				maps_of[key] = seen
				if not where.has(key):
					where[key] = "%d,%d @ %d,%d" % [map.group, map.number, tx, ty]
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a]) > int(counts[b]))
	var total: int = 0
	var total_built: int = 0
	var drawings_built: int = 0
	for key: String in keys:
		var tiles: int = int(counts[key])
		var built: int = int(built_counts.get(key, 0))
		total += tiles
		total_built += built
		if built > 0:
			drawings_built += 1
		print("%6d tiles  %3d maps  %-10s  %-16s %s" % [
			tiles, (maps_of[key] as Dictionary).size(), key, where[key],
			"built %d" % built if built > 0 else ""
		])
	print("total ", total, " tiles in ", keys.size(), " drawings")
	print(
		"of which ", total_built, " tiles in ", drawings_built,
		" drawings are already built as an object or a staircase"
	)
	quit()


## Which tiles of a map an OBJECT or a STAIRCASE already covers, found the way
## `mesher.gd:_measure_objects` finds them: by matching each declared arrangement
## everywhere in the grid, not by asking whether a tile id appears in one. A tile
## id can be a chair in one block and a wall in the next, and only the placement
## says which.
func _covered(
	shape: RefCounted, source: RefCounted, size: Vector2i
) -> PackedByteArray:
	var covered := PackedByteArray()
	covered.resize(size.x * size.y)
	covered.fill(0)
	var outside: int = shape.object_outside()
	var declared: Array = []
	declared.append_array(shape.objects())
	declared.append_array(shape.stairs())
	for thing: Dictionary in declared:
		var pattern: Array = thing[&"tiles"]
		var across := Vector2i((pattern[0] as Array).size(), pattern.size())
		for ty: int in size.y - across.y + 1:
			for tx: int in size.x - across.x + 1:
				if not _pattern_at(pattern, across, source, tx, ty):
					continue
				for row: int in across.y:
					for column: int in across.x:
						if int((pattern[row] as Array)[column]) == outside:
							continue
						covered[(ty + row) * size.x + tx + column] = 1
	return covered


## Whether the tile ids at [param tx],[param ty] are the arrangement
## [param pattern] draws. A -1 is a tile the thing covers and has no opinion
## about, which is `mesher.gd:_pattern_at`'s own rule.
func _pattern_at(
	pattern: Array, across: Vector2i, source: RefCounted, tx: int, ty: int
) -> bool:
	for row: int in across.y:
		var line: Array = pattern[row]
		for column: int in across.x:
			var want: int = int(line[column])
			if want >= 0 and source.tile_at(tx + column, ty + row) != want:
				return false
	return true
