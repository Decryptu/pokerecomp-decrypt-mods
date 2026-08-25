extends SceneTree

## The flower as it stands in 3D seen FLAT FROM THE FRONT, exported for the page
## a person draws its stem on.
##
## The front elevation of a carved cutout is its own mask: every drawn pixel
## stands at the row it is drawn at, so what the eye meets face-on is the mask
## wearing the tile's own texels. That is what this writes, beside the greenest
## texel of the grass the flower grows out of, which is what the stem is painted
## in.
##
## The mask, the span box and the colours all come from the mesher and the atlas
## rather than being worked out again here: a page drawn against a different mask
## from the one the geometry is cut on is a page that lies.
##
##   Godot --headless --path <pokerecomp> -s tools/stem_export.gd -- <cache> \
##       <out.json> [group] [number]
##
## Then `tools/stem_page.py <out.json> <out.html>`.

const MOD := "user://mods/voxel3d"
## The class the page is for, and the tile it is pinned at on every tileset that
## draws it.
const CLASS_NAME := &"flower"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <out.json> [group] [number]")
		quit(1)
		return
	if Gen2ToolPath.refuses(args[1]):
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var want_group: int = int(args[2]) if args.size() > 2 else 10
	var want_number: int = int(args[3]) if args.size() > 3 else 5
	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if candidate.group == want_group and candidate.number == want_number:
			map = candidate
	if map == null:
		print("no map ", want_group, ",", want_number)
		quit(1)
		return

	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	atlas.build(data, map, tileset, 1)
	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		profile, map.tileset
	)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	mesher.build(source, shape, atlas)

	var found := Vector2i(-1, -1)
	for ty: int in mesher._size.y:
		for tx: int in mesher._size.x:
			var scan: int = ty * mesher._size.x + tx
			if mesher._stem[scan] > 0:
				found = Vector2i(tx, ty)
				break
		if found.x >= 0:
			break
	if found.x < 0:
		print("no ", CLASS_NAME, " placed on map ", want_group, ",", want_number)
		quit(1)
		return

	var at: int = found.y * mesher._size.x + found.x
	var box: Rect2i = mesher._span_box(at, found.x, found.y)
	var tiles: Array = []
	for row: int in box.size.y:
		for column: int in box.size.x:
			tiles.append(mesher._tile_at(box.position.x + column, box.position.y + row))
	var span: Vector2i = box.size * 8
	var mask: PackedByteArray = mesher._structure_mask(
		tiles, box.size, atlas, mesher._filled[at] == 1, int(mesher._outlined[at])
	)
	var origin: Vector2i = (found - box.position) * 8
	var tile: int = mesher._tiles[at]

	# The drawing's own 8x8, as it stands: a colour where the mask keeps the
	# pixel and null where the carve puts nothing.
	var rows: Array = []
	for py: int in 8:
		var row: Array = []
		for px: int in 8:
			if not mesher._drawn(mask, span, origin.x + px, origin.y + py):
				row.append(null)
				continue
			row.append(_hex(atlas.color_of(tile, atlas.pixel(tile, px, py))))
		rows.append(row)

	var ground: Vector2i = mesher._ground_art(found.x, found.y)
	var green: Vector2i = mesher._greenest(ground.x, atlas)
	var stem: Vector2i = shape.stem_of(CLASS_NAME)
	var out := {
		"map": "%d,%d" % [want_group, want_number],
		"tileset": map.tileset,
		"tile": tile,
		"class": String(CLASS_NAME),
		"bloom": rows,
		"stem_colour": _hex(atlas.color_of(ground.x, atlas.pixel(ground.x, green.x, green.y))),
		"rise": stem.y,
		"grass": _hex(atlas.color_of(ground.x, atlas.pixel(ground.x, 0, 0))),
	}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print(args[1], "  tileset ", map.tileset, " tile ", tile, " at ", found)
	quit()


func _hex(color: Color) -> String:
	return "#%02x%02x%02x" % [
		roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)
	]
