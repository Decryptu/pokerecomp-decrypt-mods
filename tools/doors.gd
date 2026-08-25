extends SceneTree

## WHERE THE DOORS ARE, and the cartridge already says: every one is a WARP
## event on the map record, and `Gen2WorldMap.events["warps"]` carries them.
##
## A door is drawn on the wall face-on and is WALKABLE, so `tile_shape.at` calls
## its cell ground and the column stands at nothing: the doorway comes out as a
## slot cut through the whole house instead of as a door painted on it. This
## counts how much of the game that is.
##
##   Godot --headless --path <pokerecomp> -s tools/doors.gd -- <cache>

const MOD := "user://mods/voxel3d"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache")
		quit(1)
		return
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var warps: int = 0
	var in_wall: int = 0
	var maps_with: Dictionary = {}
	var by_tileset: Dictionary = {}
	var sample: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var cells: Vector2i = Vector2i(
			map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH,
			map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH
		)
		for event: Dictionary in map.events.get("warps", []) as Array:
			warps += 1
			var cell := Vector2i(int(event.get("x", -1)), int(event.get("y", -1)))
			if cell.x < 0 or cell.y < 0 or cell.x >= cells.x or cell.y >= cells.y:
				continue
			# A door in a wall: the cell itself is walkable, and the cell BESIDE it
			# is not. That is what makes the hole, and a warp on open ground, a
			# staircase or a cave mouth is not it.
			if source.permission_at(cell) != Gen2WorldCollision.LAND_TILE:
				continue
			var walled: bool = false
			for step: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0)]:
				var beside: Vector2i = cell + step
				if beside.x < 0 or beside.x >= cells.x:
					continue
				if source.permission_at(beside) == Gen2WorldCollision.LAND_TILE:
					continue
				var tile: int = source.tile_at(beside.x * 2, beside.y * 2)
				var klass: String = str(shape.at(tile, source.permission_at(beside)))
				if klass == "facade" or klass == "wall":
					walled = true
			if not walled:
				continue
			in_wall += 1
			maps_with["%d,%d" % [map.group, map.number]] = true
			by_tileset[map.tileset] = int(by_tileset.get(map.tileset, 0)) + 1
			if not sample.has(map.tileset):
				sample[map.tileset] = "%d,%d @ cell %d,%d" % [
					map.group, map.number, cell.x, cell.y
				]
	print(warps, " warps in the game")
	print(in_wall, " of them are a DOOR: a walkable cell with wall on one side, on ",
		maps_with.size(), " maps")
	var keys: Array = by_tileset.keys()
	keys.sort_custom(func(a: int, b: int) -> bool:
		return int(by_tileset[a]) > int(by_tileset[b]))
	for ts: int in keys:
		print("  ts%-3d %4d doors   %s" % [ts, by_tileset[ts], sample[ts]])
	quit()
