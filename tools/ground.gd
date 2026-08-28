extends SceneTree

## Prints `shape/profile.gd`'s GROUND table: the floor a standing drawing is
## painted with where there is none beside it.
## GENERATED, NEVER TRANSCRIBED. Eighteen tilesets of one number each read off a

const MOD := "user://mods/voxel3d"
const ART_FLAT: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache>")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
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
		mesher.resolve(source, shape)
		var size: Vector2i = mesher.get("_size")
		if size.x == 0:
			continue
		var art: PackedByteArray = mesher.get("_art")
		var tiles: PackedInt32Array = mesher.get("_tiles")
		var heights: PackedInt32Array = mesher.get("_heights")
		var modelled: PackedByteArray = mesher.get("_modelled")
		var klass: PackedInt32Array = mesher.get("_klass")
		var counts: Dictionary = beside.get(map.tileset, {})
		for ty: int in size.y:
			for tx: int in size.x:
				var at: int = ty * size.x + tx
				if modelled[at] != 1:
					continue
				var key: int = klass[at]
				var per: Variant = counts.get(key)
				if per == null:
					per = {}
					counts[key] = per
				for step: Vector2i in [
					Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
				]:
					var next := Vector2i(tx + step.x, ty + step.y)
					if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
						continue
					var index: int = next.y * size.x + next.x
					if art[index] == ART_FLAT and heights[index] >= 0 and tiles[index] >= 0:
						var tile: int = tiles[index]
						per[tile] = int(per.get(tile, 0)) + 1
		beside[map.tileset] = counts

	var names: Dictionary = {}
	for shape_class: StringName in mesher.get("_class_ids") as Dictionary:
		names[int((mesher.get("_class_ids") as Dictionary)[shape_class])] = shape_class
	var sets: Array = beside.keys()
	sets.sort()
	print("const GROUND: Dictionary = {")
	for tileset_number: int in sets:
		var counts: Dictionary = beside[tileset_number]
		if counts.is_empty():
			continue
		var classes: Array = counts.keys()
		classes.sort()
		print("\t%d: {" % tileset_number)
		for id: int in classes:
			var shape_class: StringName = names.get(id, &"?")
			var per: Dictionary = counts[id]
			var keys: Array = per.keys()
			keys.sort()
			var best: int = keys[0]
			var total: int = 0
			for tile: int in keys:
				total += int(per[tile])
				if int(per[tile]) > int(per[best]):
					best = tile
			print("\t\t&\"%s\": %d,  # %d of %d" % [shape_class, best, int(per[best]), total])
		print("\t},")
	print("}")
	quit()
