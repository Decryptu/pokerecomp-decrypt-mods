extends SceneTree

## Turns a painted `levels.json` into `shape/levels.gd`, and says what is wrong
## with it on the way.

const MOD := "user://mods/voxel3d"
const OUT := "%s/shape/levels.gd" % MOD
const NONE := "."
const WALL := "#"
const MARKS := "0123456789abcdefghijklmnopqrstuvwxyz"
## The most a walk between two painted floors may climb: one 16 px storey.
const WALK_RISE: int = 2
const CELLS_PER_BLOCK: int = 2
const TILES_PER_CELL: int = 2

var _complaints: Array[String] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <levels.json> [--write]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var painted: Variant = _read(args[1])
	if painted == null:
		quit(1)
		return
	var levels: GDScript = load(OUT)
	var paintings: Dictionary = {}
	for record: Dictionary in (painted as Dictionary)["maps"]:
		var entry: Array = _painting(data, levels, record)
		if not entry.is_empty():
			paintings[entry[0]] = entry[1]
	print("%d maps" % paintings.size())
	for line: String in _complaints:
		print("  ! ", line)
	if _complaints.is_empty():
		print("  nothing to complain about")
	if not args.has("--write"):
		print("(dry run; pass --write to write shape/levels.gd)")
		quit()
		return
	quit(0 if _write(levels, paintings) else 1)


func _read(path: String) -> Variant:
	var painted: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not painted is Dictionary or not (painted as Dictionary).has("maps"):
		print("not a levels.json: ", path)
		return null
	if String((painted as Dictionary).get("unit", "")) != "band8":
		print("unexpected unit ", (painted as Dictionary).get("unit"),
			": this reads band8 only; export and paint the maps again")
		return null
	return painted


func _painting(data: GameData, levels: GDScript, record: Dictionary) -> Array:
	var map: Gen2WorldMap = data.world_map(int(record["group"]), int(record["number"]))
	var label: String = "%s %d,%d" % [data.id, int(record["group"]), int(record["number"])]
	if map == null:
		_complaints.append("%s: no such map" % label)
		return []
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var drawing: String = levels.drawing_of(map, tileset)
	if String(record.get("drawing", "")) != drawing:
		_complaints.append("%s draws something other than what was painted" % label)
		return []
	var rows: Array[String] = _rows(label, record)
	var source: RefCounted = (load("%s/shape/map_source.gd" % MOD) as GDScript).new(
		null, map, tileset, data
	)
	_check_walks(label, source, rows, _carried(data, map, tileset, source))
	if not rows.any(func(row: String) -> bool: return row.lstrip("0.#") != ""):
		_complaints.append("%s is all at 0 and pins nothing" % label)
	return [drawing, {"painted_on": label, "rows": rows}]


func _rows(label: String, record: Dictionary) -> Array[String]:
	var cells := Vector2i(int(record["cells"][0]), int(record["cells"][1]))
	var rows: Array[String] = []
	for cy: int in cells.y:
		var row: String = ""
		for cx: int in cells.x:
			row += _mark(label, Vector2i(cx, cy), record)
		rows.append(row)
	return rows


func _mark(label: String, cell: Vector2i, record: Dictionary) -> String:
	if int((record["walls"][cell.y] as Array)[cell.x]) == 1:
		return WALL
	var level: Variant = (record["levels"][cell.y] as Array)[cell.x]
	if level == null:
		return NONE
	var value: int = int(level)
	if value < 0 or value >= MARKS.length():
		_complaints.append("%s cell %d,%d band %d is off the scale" % [
			label, cell.x, cell.y, value
		])
		return NONE
	return MARKS[value]


## Cells a warp or a staircase carries across, which may climb any height.
func _carried(
	data: GameData, map: Gen2WorldMap, tileset: Gen2WorldTileset, source: RefCounted
) -> Dictionary:
	var carried: Dictionary = {}
	for event: Variant in map.events.get("warps", []):
		carried[Vector2i(int((event as Dictionary).get("x", -1)),
			int((event as Dictionary).get("y", -1)))] = true
	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		(load("%s/shape/profiles.gd" % MOD) as GDScript).of(data), tileset.name
	)
	var cells := Vector2i(map.width_blocks, map.height_blocks) * CELLS_PER_BLOCK
	for cy: int in cells.y:
		for cx: int in cells.x:
			if _has_stairs(shape, source, Vector2i(cx, cy)):
				carried[Vector2i(cx, cy)] = true
	return carried


func _has_stairs(shape: RefCounted, source: RefCounted, cell: Vector2i) -> bool:
	var permission: int = source.permission_at(cell)
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var at: Vector2i = cell * TILES_PER_CELL + tile
		if shape.at(source.tile_at(at.x, at.y), permission) == &"stairs":
			return true
	return false


## A walk between two painted floors that climbs more than a storey is a paint
## slip, unless a warp or a staircase carries the player across it.
func _check_walks(
	label: String, source: RefCounted, rows: Array[String], carried: Dictionary
) -> void:
	for cy: int in rows.size():
		for cx: int in rows[cy].length():
			var from := Vector2i(cx, cy)
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var rise: int = _rise(source, rows, from, from + step)
				if rise > WALK_RISE and not carried.has(from) \
						and not carried.has(from + step):
					_complaints.append("%s walk from %d,%d to %d,%d climbs %d bands" % [
						label, from.x, from.y, from.x + step.x, from.y + step.y, rise
					])


func _rise(source: RefCounted, rows: Array[String], from: Vector2i, to: Vector2i) -> int:
	if to.y >= rows.size() or to.x >= rows[to.y].length():
		return 0
	if not _walked(source, rows, from) or not _walked(source, rows, to):
		return 0
	return absi(MARKS.find(rows[from.y][from.x]) - MARKS.find(rows[to.y][to.x]))


func _walked(source: RefCounted, rows: Array[String], cell: Vector2i) -> bool:
	var mark: String = rows[cell.y][cell.x]
	return mark != NONE and mark != WALL \
		and source.permission_at(cell) == Gen2WorldCollision.LAND_TILE


func _write(levels: GDScript, paintings: Dictionary) -> bool:
	var kept: Dictionary = (levels.get("PAINTINGS") as Dictionary).duplicate() \
		if levels != null else {}
	kept.merge(paintings, true)
	var drawings: Array = kept.keys()
	drawings.sort_custom(func(a: String, b: String) -> bool:
		return "%s %s" % [kept[a]["painted_on"], a] < "%s %s" % [kept[b]["painted_on"], b])
	var entries: PackedStringArray = []
	for drawing: String in drawings:
		entries.append(_entry(drawing, kept[drawing]))
	var path: String = ProjectSettings.globalize_path(OUT)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("cannot write ", path)
		return false
	file.store_string(_header() + "\n".join(entries) + "\n" + _footer())
	file.close()
	print("wrote ", path)
	return true


func _entry(drawing: String, painting: Dictionary) -> String:
	var rows: PackedStringArray = []
	for row: String in painting["rows"]:
		rows.append('\t\t\t"%s",' % row)
	return '\t"%s": {\n\t\t"painted_on": "%s",\n\t\t"rows": [\n%s\n\t\t],\n\t},' % [
		drawing, painting["painted_on"], "\n".join(rows)
	]


func _header() -> String:
	return """extends RefCounted

## Painted ground heights, one row of characters per row of walk cells.
## GENERATED by `tools/level_pins.gd`. Paint and regenerate; do not edit here.
##
## A painting belongs to a drawing, not to a map number: the three Johto
## cartridges number their maps apart and redraw some. It holds wherever the
## drawing `drawing_of` names is drawn.
##
## A mark counts 8 px bands, base 36 so a cave's two storeys fit; `#` is a
## wall, which carries no height of its own; `.` is a cell the paint says
## nothing about.

const NONE := "."
const WALL := "#"
const MARKS := "0123456789abcdefghijklmnopqrstuvwxyz"
const BAND: int = 8
const CELLS_PER_BLOCK: int = 2
const TILES_PER_BLOCK: int = 16

## Answers of `height_in` that are not a height.
const NOTHING: int = -1
const WALLED: int = -2

## Drawing -> the map it was painted on, and one string per row of walk cells.
const PAINTINGS: Dictionary = {
"""


func _footer() -> String:
	return """}


## The painting of this map's drawing, or empty where nobody painted it.
static func rows_of(map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Array:
	if map == null or tileset == null:
		return []
	var cells := Vector2i(map.width_blocks, map.height_blocks) * CELLS_PER_BLOCK
	var drawing: String = ""
	for key: String in PAINTINGS:
		var rows: Array = PAINTINGS[key]["rows"]
		if rows.size() != cells.y or (rows[0] as String).length() != cells.x:
			continue
		if drawing.is_empty():
			drawing = drawing_of(map, tileset)
		if key == drawing:
			return rows
	return []


## The map's own record as its tileset draws it: every tile of every block. A
## block edited during play leaves it alone.
static func drawing_of(map: Gen2WorldMap, tileset: Gen2WorldTileset) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(String(tileset.name).to_utf8_buffer())
	var tiles := PackedInt32Array([map.width_blocks, map.height_blocks])
	for by: int in map.height_blocks:
		for bx: int in map.width_blocks:
			var block: int = map.block_at(bx, by)
			for tile: int in TILES_PER_BLOCK:
				tiles.append(tileset.tile_index(block, tile))
	context.update(tiles.to_byte_array())
	return context.finish().hex_encode()


## World pixels for a walk cell of a painting, `WALLED`, or `NOTHING` where the
## paint is silent.
static func height_in(rows: Array, cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= rows.size():
		return NOTHING
	var row: String = rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return NOTHING
	var mark: String = row[cell.x]
	if mark == WALL:
		return WALLED
	if mark == NONE:
		return NOTHING
	return MARKS.find(mark) * BAND
"""
