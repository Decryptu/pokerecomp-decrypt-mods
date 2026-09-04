extends SceneTree

## What a drawn window COSTS in triangles, split by layer and by model drawing.
## `stage_bench.gd` prices a layer by its absence; this says what is inside one.

const MOD := "user://mods/voxel3d"
const WORST: int = 14


static func _triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		var indices: int = mesh.surface_get_array_index_len(surface)
		total += indices if indices > 0 else mesh.surface_get_array_len(surface)
	return total / 3


static func _layer(name: String, meshes: Array) -> int:
	var total: int = 0
	for mesh: Mesh in meshes:
		total += _triangles(mesh)
	print("%-10s %8d triangles over %d meshes" % [name, total, meshes.size()])
	return total


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <group> <number> [cell=x,y] [distance=16] [ring=]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var map: Gen2WorldMap = data.world_map(int(args[1]), int(args[2]))
	if map == null:
		print("no map %s,%s" % [args[1], args[2]])
		quit(1)
		return
	_report(data, map, _named(args))
	quit(0)


func _named(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(3, args.size()):
		var at: int = args[index].find("=")
		if at > 0:
			out[args[index].substr(0, at)] = args[index].substr(at + 1)
	return out


static func _cell(map: Gen2WorldMap, named: Dictionary) -> Vector2i:
	if not String(named.get("cell", "")).contains(","):
		return Vector2i(map.collision_width / 2, map.collision_height / 2)
	var parts: PackedStringArray = String(named["cell"]).split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func _window(map: Gen2WorldMap, named: Dictionary) -> Rect2i:
	var cell: Vector2i = _cell(map, named)
	var distance: int = int(named.get("distance", "16"))
	if distance <= 0:
		return Rect2i()
	var span: int = distance * 2 + 1
	return Rect2i(
		(cell - Vector2i(distance, distance)) * Gen2Layout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * Gen2Layout.MAP_BLOCK_CELL_WIDTH
	)


func _report(data: GameData, map: Gen2WorldMap, named: Dictionary) -> void:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		load("%s/shape/profile.gd" % MOD), map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	var animation := Gen2WorldAnimation.new()
	animation.configure_tileset(data, tileset, Gen2WorldPalette.TIME_DAY)
	atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY, animation)
	mesher.resolve(source, shape)
	var ring: float = float(named.get("ring", "0"))
	if ring > 0.0:
		var at: Vector2i = _cell(map, named)
		mesher.set_detail_ring(Vector3(
			(float(at.x) + 0.5) * 16.0, 0.0, (float(at.y) + 0.5) * 16.0
		), ring * 16.0)
	var window: Rect2i = _window(map, named)
	var terrain: int = _layer("terrain", mesher.emit(atlas, window))
	var water: int = _layer("water", mesher.take_water())
	var tufts: int = _layer("tufts", mesher.take_tufts())
	var models: int = _models(mesher)
	print("total    %8d triangles, models %.0f%% of them" % [
		terrain + water + tufts + models,
		100.0 * float(models) / float(maxi(terrain + water + tufts + models, 1)),
	])


func _models(mesher: RefCounted) -> int:
	var rows: Array = []
	var total: int = 0
	for key: String in mesher._model_meshes:
		var spots: Dictionary = mesher._model_spots.get(key, {})
		if spots.is_empty():
			continue
		var each: int = _triangles(mesher._model_meshes[key])
		total += each * spots.size()
		rows.append([each * spots.size(), key, each, spots.size(),
			_impostor_of(mesher, key), _chunks(spots)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("models   %8d triangles over %d drawings placed" % [total, rows.size()])
	print("  %-26s %8s   %5s x %4s  %8s %6s" % [
		"drawing", "total", "each", "spots", "impostor", "chunks",
	])
	for index: int in mini(WORST, rows.size()):
		var row: Array = rows[index]
		print("  %-26s %8d = %5d x %4d  %8d %6d" % [
			row[1], row[0], row[2], row[3], row[4], row[5],
		])
	return total


static func _chunks(spots: Dictionary) -> int:
	var seen: Dictionary = {}
	for entry: Array in spots.values():
		seen[entry[2]] = true
	return seen.size()


func _impostor_of(mesher: RefCounted, key: String) -> int:
	var measured: RefCounted = mesher._model_measures.get(key)
	if measured == null:
		return 0
	var model: RefCounted = (load("%s/shape/model.gd" % MOD) as GDScript).new()
	return _triangles(model.impostor(measured))
