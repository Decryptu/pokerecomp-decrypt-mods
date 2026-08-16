extends SceneTree

## Prints `shape/profile.gd`'s GROUND table: the floor a standing drawing is
## painted with where there is none beside it.
##
## `mesher.gd:_ground_art` asks the two tiles around a cutout what it stands on
## and is right whenever anything flat is there. Inside a wood, a hedge or a
## border ring nothing is, and four in five of the game's modelled tiles are in
## one, so the answer has to come from the tileset rather than from the
## neighbourhood.
##
## WHAT A PLANT STANDS NEXT TO, over every map at once. Counted per MAP it is the
## wrong answer and New Bark Town is the proof: its forest ring hugs the town
## square, so the pavement wins 145 to 85 and the wood comes out paved. Counted
## over the whole of tileset 1, where the routes dwarf the towns, the grass wins
## 4599 to 2307. The rule is the same one either way and only the population is
## different, which is why this is a table and not a pass.
##
## GENERATED, NEVER TRANSCRIBED. Eighteen tilesets of one number each read off a
## listing is where a session puts a 6 where it meant a 5 and never finds it.
##
##   Godot --headless --path <pokerecomp> -s tools/ground.gd -- <cache>

const MOD := "user://mods/voxel3d"
const ART_FLAT: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache>")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var beside: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
			profile, map.tileset
		)
		var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
			null, map, tileset, data
		)
		atlas.build(data, map, tileset, 1)
		# RESOLVE ONLY. The counts are a fact about what each tile became, and
		# emitting the mesh as well costs twelve seconds a run and answers nothing.
		mesher.resolve(source, shape)
		var size: Vector2i = mesher.get("_size")
		if size.x == 0:
			continue
		var art: PackedByteArray = mesher.get("_art")
		var tiles: PackedInt32Array = mesher.get("_tiles")
		var heights: PackedInt32Array = mesher.get("_heights")
		var modelled: PackedByteArray = mesher.get("_modelled")
		var counts: Dictionary = beside.get(map.tileset, {})
		for ty: int in size.y:
			for tx: int in size.x:
				var at: int = ty * size.x + tx
				if modelled[at] != 1:
					continue
				for step: Vector2i in [
					Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
				]:
					var next := Vector2i(tx + step.x, ty + step.y)
					if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
						continue
					var index: int = next.y * size.x + next.x
					if art[index] == ART_FLAT and heights[index] >= 0 and tiles[index] >= 0:
						counts[tiles[index]] = int(counts.get(tiles[index], 0)) + 1
		beside[map.tileset] = counts

	var sets: Array = beside.keys()
	sets.sort()
	print("const GROUND: Dictionary = {")
	for tileset_number: int in sets:
		var counts: Dictionary = beside[tileset_number]
		if counts.is_empty():
			continue
		var keys: Array = counts.keys()
		keys.sort()
		var best: int = keys[0]
		for tile: int in keys:
			if int(counts[tile]) > int(counts[best]):
				best = tile
		var total: int = 0
		for tile: int in keys:
			total += int(counts[tile])
		print("\t%d: %d,  # %d of %d" % [tileset_number, best, int(counts[best]), total])
	print("}")
	quit()
