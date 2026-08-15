extends SceneTree

## What one rectangle of a map RESOLVES to, tile by tile, as text.
##
## The pictures say a shape is wrong and this says why: `map_grid.py` names a
## tile, `mask_print.gd` prints the pixels inside one, and between the two there
## was nothing that answered what the mesher decided about it. Every question in
## this round started as "what class did that tan rock get, and how tall did the
## column measure it".
##
## Three grids over the same rectangle, in MAP tile coordinates, the ones the
## numbered art is ruled in: the graphics TILE id, the resolved CLASS, and the
## measured HEIGHT in world pixels. The height is what `_measure_columns`,
## `_apply_levels` and `_measure_plateaus` left behind, so it is the answer the
## geometry is actually built from rather than the class's own constant.
##
##   Godot --headless --path <pokerecomp> -s tools/tile_read.gd -- <cache> \
##       <group> <number> <tile x> <tile y> <width> <height>

const MOD := "user://mods/voxel3d"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 7:
		print("usage: <cache> <group> <number> <tile x> <tile y> <width> <height>")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.group == int(args[1]) and candidate.number == int(args[2]):
			map = candidate
	if map == null:
		print("no map ", args[1], ",", args[2])
		quit(1)
		return
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	mesher.resolve(source, shape)

	var box := Rect2i(int(args[3]), int(args[4]), int(args[5]), int(args[6]))
	var names: Dictionary = {}
	for klass: StringName in mesher._class_ids:
		names[int(mesher._class_ids[klass])] = String(klass)
	print("map ", map.group, ",", map.number, " tileset ", map.tileset,
		" tiles ", mesher._map_size.x, "x", mesher._map_size.y,
		"  rectangle ", box)

	_grid(mesher, box, "TILE id", func(at: int) -> String:
		return str(mesher._tiles[at]))
	_grid(mesher, box, "CLASS", func(at: int) -> String:
		return String(names.get(int(mesher._klass[at]), "?")).substr(0, 4))
	_grid(mesher, box, "HEIGHT, world pixels", func(at: int) -> String:
		return str(int(mesher._heights[at])))
	# THE CORNERS ARE WHAT A SLOPE IS. A height is one number per tile and says
	# nothing about a rim that ramps, so a patch built as a box and one built as a
	# frustum print the same height grid: the four corners are what tell them
	# apart, and a flat tile prints its own height four times.
	_grid(mesher, box, "CORNERS nw/ne/sw/se, world pixels", func(at: int) -> String:
		var corners: PackedStringArray = PackedStringArray()
		for corner: int in 4:
			corners.append(str(int(mesher._corners[at * 4 + corner])))
		return "/".join(corners)
	, 12)
	quit()


## One grid, five columns wide a cell, with the map's own tile numbers on the
## top and the left: a reading of it has to be pointable at in the same words
## the numbered art uses.
func _grid(
	mesher: RefCounted, box: Rect2i, title: String, cell: Callable, wide: int = 5
) -> void:
	print("\n", title)
	var header: String = "     "
	for tx: int in range(box.position.x, box.end.x):
		header += ("%" + str(wide) + "d") % tx
	print(header)
	for ty: int in range(box.position.y, box.end.y):
		var line: String = "%4d " % ty
		for tx: int in range(box.position.x, box.end.x):
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			line += ("%" + str(wide) + "s") % (cell.call(at) if at >= 0 else "-")
		print(line)
