extends SceneTree

## A mesh window REACHED BY WALKING must be the window built cold.

const MOD := "user://mods/voxel3d"
const CELL: int = 16
const RING_CELLS: float = 35.0
const SMALLEST_CELLS: int = 8


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [draw cells] [tileset]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var draw_cells: int = int(args[1]) if args.size() > 1 else 16
	var only: int = int(args[2]) if args.size() > 2 else -1

	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var atlas_script: GDScript = load("%s/shape/atlas.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)

	var checked: int = 0
	var bad: int = 0
	var carried: RefCounted = mesher_script.new()
	for map: Gen2WorldMap in data.world_maps():
		if only >= 0 and map.tileset != only:
			continue
		if map.collision_width < SMALLEST_CELLS or map.collision_height < SMALLEST_CELLS:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var atlas: RefCounted = atlas_script.new()
		if not atlas.build(data, map, tileset, Gen2WorldPalette.TIME_DAY):
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset, data)

		var margin: int = maxi(4, draw_cells / 3) + 1
		var first := Vector2i(map.collision_width / 2, map.collision_height / 2)
		var second: Vector2i = first + Vector2i(0, margin)
		var third: Vector2i = second + Vector2i(margin, 0)

		var walked: RefCounted = mesher_script.new()
		walked.resolve(source, shape)
		_emit(walked, atlas, first, draw_cells)
		_emit(walked, atlas, second, draw_cells)
		var reached: Dictionary = _emit(walked, atlas, third, draw_cells)

		var cold: RefCounted = mesher_script.new()
		cold.resolve(source, shape)
		var fresh: Dictionary = _emit(cold, atlas, third, draw_cells)

		carried.resolve(source, shape)
		var warped: Dictionary = _emit(carried, atlas, third, draw_cells)

		checked += 1
		if reached != fresh:
			bad += 1
			print("%d,%d  walked %s" % [map.group, map.number, str(reached)])
			print("      cold   %s" % str(fresh))
		if warped != fresh:
			bad += 1
			print("%d,%d  warped %s" % [map.group, map.number, str(warped)])
			print("      cold   %s" % str(fresh))
	print("%d maps checked at %d cells, %d differ" % [checked, draw_cells, bad])
	quit(int(bad > 0))


func _emit(
	mesher: RefCounted, atlas: RefCounted, centre: Vector2i, draw_cells: int
) -> Dictionary:
	var span: int = draw_cells * 2 + 1
	var window := Rect2i(
		(centre - Vector2i(draw_cells, draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	)
	mesher.set_detail_ring(
		Vector3(float(centre.x * CELL), 0.0, float(centre.y * CELL)),
		RING_CELLS * float(CELL)
	)
	mesher.begin_emit(atlas, window)
	while not mesher.emit_step(0):
		pass
	var out: Dictionary = {
		"meshes": 0, "triangles": 0, "models": 0, "stamps": 0,
		"bounds": mesher.emitted_bounds_tiles(),
	}
	for group: Array in [mesher.take_chunks(), mesher.take_water(), mesher.take_tufts()]:
		out["meshes"] = int(out["meshes"]) + group.size()
		for mesh: ArrayMesh in group:
			for surface: int in mesh.get_surface_count():
				var vertices: PackedVector3Array = \
					mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				@warning_ignore("integer_division")
				out["triangles"] = int(out["triangles"]) + vertices.size() / 3
	for entry: Array in mesher.take_models():
		out["models"] = int(out["models"]) + 1
		out["stamps"] = int(out["stamps"]) + (entry[1] as Array).size()
	return out
