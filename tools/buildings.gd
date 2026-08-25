extends SceneTree

## HOW MANY DISTINCT BUILDINGS THE GAME DRAWS, which is what says whether a
## painting tool is a finite job.
##
## A building is a connected group of `facade` and `roof` tiles, flooded four
## ways. Two placements of one drawing carry the same rectangle of tile ids, so
## the ARRANGEMENT is the identity, exactly as the reference keys its band table
## by the building's tile grid rather than by tile id. What comes back is a
## catalogue: how many drawings, how often each is placed, and on how many maps.
##
## Written for the house tool: a person can paint 112 drawings and cannot paint
## 243 placements, and until this was run nobody knew which number it was.
##
##   Godot --headless --path <pokerecomp> -s tools/buildings.gd -- <cache> \
##       [tileset]

const MOD := "user://mods/voxel3d"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache")
		quit(1)
		return
	var only: int = int(args[1]) if args.size() > 1 else -1
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var placements: Dictionary = {}
	var maps_of: Dictionary = {}
	var where: Dictionary = {}
	var size_of: Dictionary = {}
	var per_tileset: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var w: int = map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2
		var h: int = map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2
		var part := PackedByteArray()
		var ids := PackedInt32Array()
		part.resize(w * h)
		ids.resize(w * h)
		for ty: int in h:
			for tx: int in w:
				var tile: int = source.tile_at(tx, ty)
				ids[ty * w + tx] = tile
				if tile < 0:
					continue
				var klass: String = str(shape.at(
					tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))
				))
				if klass == "facade" or klass.begins_with("roof"):
					part[ty * w + tx] = 1
		var seen := PackedByteArray()
		seen.resize(w * h)
		for ty: int in h:
			for tx: int in w:
				if part[ty * w + tx] == 0 or seen[ty * w + tx] == 1:
					continue
				var stack: Array[Vector2i] = [Vector2i(tx, ty)]
				var box := Rect2i(tx, ty, 1, 1)
				seen[ty * w + tx] = 1
				while not stack.is_empty():
					var at: Vector2i = stack.pop_back()
					box = box.expand(at).expand(at + Vector2i.ONE)
					for step: Vector2i in [
						Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
					]:
						var next: Vector2i = at + step
						if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
							continue
						var index: int = next.y * w + next.x
						if part[index] == 0 or seen[index] == 1:
							continue
						seen[index] = 1
						stack.append(next)
				# The whole rectangle, holes and all, is the drawing's identity.
				var rows: Array = []
				for row: int in box.size.y:
					var line: Array = []
					for column: int in box.size.x:
						line.append(ids[(box.position.y + row) * w + box.position.x + column])
					rows.append(line)
				var key: String = "ts%d %s" % [map.tileset, str(rows)]
				placements[key] = int(placements.get(key, 0)) + 1
				var seen_maps: Dictionary = maps_of.get(key, {})
				seen_maps["%d,%d" % [map.group, map.number]] = true
				maps_of[key] = seen_maps
				size_of[key] = box.size
				per_tileset[map.tileset] = int(per_tileset.get(map.tileset, 0)) + 1
				if not where.has(key):
					where[key] = "%d,%d @ %d,%d" % [map.group, map.number, box.position.x, box.position.y]
	var keys: Array = placements.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(placements[a]) > int(placements[b]))
	var total: int = 0
	for key: String in keys:
		total += int(placements[key])
	print(keys.size(), " DISTINCT building drawings, placed ", total, " times")
	print("the twenty most placed:")
	for index: int in mini(20, keys.size()):
		var key: String = keys[index]
		var box: Vector2i = size_of[key]
		print("  %4d placements  %3d maps  %2dx%-2d tiles  %-14s  %s" % [
			placements[key], (maps_of[key] as Dictionary).size(),
			box.x, box.y, key.split(" ")[0], where[key]
		])
	print("placements per tileset:")
	var tilesets: Array = per_tileset.keys()
	tilesets.sort_custom(func(a: int, b: int) -> bool:
		return int(per_tileset[a]) > int(per_tileset[b]))
	for ts: int in tilesets:
		print("  ts%-3d %5d" % [ts, per_tileset[ts]])
	quit()
