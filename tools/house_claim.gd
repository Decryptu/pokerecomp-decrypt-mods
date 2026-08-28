extends SceneTree

## WHICH PAINTED BUILDING STANDS ON WHICH TILES, and what refused the rest.

const MOD := "user://mods/voxel3d"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [group number [tile x] [tile y]]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var only := Vector2i(-1, -1)
	if args.size() > 2:
		only = Vector2i(int(args[1]), int(args[2]))
	var target := Vector2i(-1, -1)
	if args.size() > 4:
		target = Vector2i(int(args[3]), int(args[4]))

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var houses: GDScript = load("%s/shape/houses.gd" % MOD)

	var placements: int = 0
	var buildings: int = 0
	var refused: int = 0
	var maps: int = 0
	var drawings: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		if only.x >= 0 and (map.group != only.x or map.number != only.y):
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset, data)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var margin: Vector2i = mesher._margin
		var here: Array = []
		for entry: Array in mesher._houses as Array:
			var house: Dictionary = entry[0]
			var start: Vector2i = entry[1] - margin
			var across: Vector2i = entry[2]
			var mine: PackedInt32Array = entry[4]
			var plans: Array = mesher._house_plan(house)
			placements += 1
			buildings += mine.size()
			refused += plans.size() - mine.size()
			drawings[int(house["id"])] = true
			for index: int in plans.size():
				if not mine.has(index):
					continue
				var rect: Rect2i = mesher._house_tile_rect(plans[index], across)
				rect.position += start
				here.append([int(house["id"]), index, rect])
		if not here.is_empty():
			maps += 1
		if only.x < 0:
			continue
		print("map %d,%d ts%d, %dx%d tiles" % [
			map.group, map.number, map.tileset,
			map.width_blocks * 4, map.height_blocks * 4
		])
		here.sort_custom(func(a: Array, b: Array) -> bool:
			return str(a[2]) + str(a[0]) < str(b[2]) + str(b[0]))
		for row: Array in here:
			var mark: String = "  <- holds the target" if target.x >= 0 \
				and (row[2] as Rect2i).has_point(target) else ""
			print("  BUILT #%-4d plan %d  %s%s" % [row[0], row[1], row[2], mark])
		if target.x < 0:
			continue
		print("every drawing whose rectangle holds tile %s:" % target)
		for house: Dictionary in houses.of_tileset(map.tileset):
			var pattern: Array = house["tiles"]
			var across := Vector2i((pattern[0] as Array).size(), pattern.size())
			for ty: int in maxi(map.height_blocks * 4 - across.y + 1, 0):
				for tx: int in maxi(map.width_blocks * 4 - across.x + 1, 0):
					if not Rect2i(Vector2i(tx, ty), across).has_point(target):
						continue
					if not mesher._pattern_at(
						pattern, across, tx + margin.x, ty + margin.y
					):
						continue
					print("  #%d at %d,%d:" % [int(house["id"]), tx, ty])
					for plan: Dictionary in mesher._house_plan(house):
						var rect: Rect2i = mesher._house_tile_rect(plan, across)
						rect.position += Vector2i(tx, ty)
						print("    wall px %d..%d  cover px %d..%d  %s%s" % [
							int(plan["left"]), int(plan["right"]),
							int(plan["cover_left"]), int(plan["cover_right"]),
							rect,
							"  <- holds the target" if rect.has_point(target) else ""
						])
	print("%d placements claimed on %d maps, %d buildings stood up, %d plans refused"
		% [placements, maps, buildings, refused])
	print("%d distinct drawings reach the game" % drawings.size())
	quit()
