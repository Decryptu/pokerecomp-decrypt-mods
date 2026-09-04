extends SceneTree

## Turns a painted `houses.json` into `shape/houses.gd`, and says what is wrong
## with it on the way.

const MOD := "user://mods/voxel3d"
const OUT := "%s/shape/houses.gd" % MOD

const TILE: int = 8
const NONE := "."
const WALL := "W"
const ROOF := "R"
const FRONT := "F"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <houses.json> [--write]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var painted: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if painted == null or not (painted as Dictionary).has("houses"):
		print("not a houses.json: ", args[1])
		quit(1)
		return
	if String((painted as Dictionary).get("unit", "")) != "pixel":
		print("unexpected unit ", (painted as Dictionary).get("unit"),
			": this reads pixel only. A tile8 painting is from the older page and"
			+ " cannot say what a half-roof tile is, which is why the page moved")
		quit(1)
		return

	var entries: Array[String] = []
	var complaints: Array[String] = []
	var notes: Array[String] = []
	var corrected: int = 0
	var placements: int = 0
	var unchanged: int = 0
	for record: Dictionary in (painted as Dictionary)["houses"]:
		var paint: Array = record["paint"]
		var guess: Array = record.get("guess", [])
		var tiles: Array = record["tiles"]
		var name: String = "#%d ts%d" % [int(record["id"]), int(record["tileset"])]
		var across: int = (tiles[0] as Array).size() * TILE
		var down: int = (tiles as Array).size() * TILE
		if paint.size() != down or String(paint[0]).length() != across:
			complaints.append("%s: painted %dx%d px over a %dx%d px drawing" % [
				name, String(paint[0]).length(), paint.size(), across, down
			])
			continue
		if guess.size() > 0 and _same(paint, guess):
			unchanged += 1
			continue
		var found: int = _count(data, int(record["tileset"]), tiles)
		if found == 0:
			complaints.append("%s: its arrangement is nowhere in the game any more"
				% name)
			continue
		if found != int(record["placements"]):
			notes.append("%s: painted over %d, the arrangement occurs %d times"
				% [name, int(record["placements"]), found])
		corrected += 1
		placements += found
		if _rows_of(paint, WALL) > 0 and _rows_of(paint, ROOF) > 0 \
				and _rows_of(paint, FRONT) == 0:
			notes.append("%s: a wall and a roof but no roof-from-the-front, so its"
				% name + " roof has no thickness. Look at the rows just above the"
				+ " wall")
		var cut: int = _cut(paint)
		if cut > 0:
			notes.append("%s: %d of its %d tiles are painted two ways, so it is read"
				% [name, cut, (record["tiles"] as Array).size()
					* ((record["tiles"][0] as Array).size())]
				+ " per pixel column")
		entries.append(_entry(record))

	var out: String = _script(entries)
	if args.size() > 2 and args[2] == "--write":
		var file: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
		if file == null:
			print("cannot write ", OUT)
			quit(1)
			return
		file.store_string(out)
		file.close()
		print("wrote ", OUT)
	else:
		print(out)
	print("%d drawings corrected, %d placements, %d left as they came" % [
		corrected, placements, unchanged
	])
	for note: String in notes:
		print("  . ", note)
	for complaint: String in complaints:
		print("  ! ", complaint)
	quit()


func _same(paint: Array, guess: Array) -> bool:
	if paint.size() != guess.size():
		return false
	for row: int in paint.size():
		if String(paint[row]) != String(guess[row]):
			return false
	return true


func _rows_of(paint: Array, word: String) -> int:
	var count: int = 0
	for row: String in paint:
		if row.contains(word):
			count += 1
	return count


func _cut(paint: Array) -> int:
	var down: int = paint.size() / TILE
	var across: int = String(paint[0]).length() / TILE
	var cut: int = 0
	for row: int in down:
		for column: int in across:
			var first: String = ""
			var mixed: bool = false
			for y: int in TILE:
				var line: String = paint[row * TILE + y]
				for x: int in TILE:
					var stroke: String = line[column * TILE + x]
					if first == "":
						first = stroke
					elif stroke != first:
						mixed = true
			if mixed:
				cut += 1
	return cut


func _count(data: GameData, tileset_number: int, tiles: Array) -> int:
	var across := Vector2i((tiles[0] as Array).size(), tiles.size())
	var found: int = 0
	for map: Gen2WorldMap in data.world_maps():
		if map.tileset != tileset_number:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var w: int = map.width_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH * 2
		var h: int = map.height_blocks * Gen2Layout.MAP_BLOCK_CELL_WIDTH * 2
		var ids := PackedInt32Array()
		ids.resize(w * h)
		for ty: int in h:
			for tx: int in w:
				@warning_ignore("integer_division")
				var block: int = map.block_at(tx / 4, ty / 4)
				ids[ty * w + tx] = tileset.tile_index(block, (ty & 3) * 4 + (tx & 3))
		for ty: int in h - across.y + 1:
			for tx: int in w - across.x + 1:
				var matched: bool = true
				for row: int in across.y:
					var line: Array = tiles[row]
					for column: int in across.x:
						if ids[(ty + row) * w + tx + column] != int(line[column]):
							matched = false
							break
					if not matched:
						break
				if matched:
					found += 1
	return found


func _entry(record: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("\t{")
	lines.append("\t\t# %s, placed %d times on %d maps, first at %s" % [
		"drawing %d" % int(record["id"]), int(record["placements"]),
		(record["maps"] as Array).size(), record["where"]
	])
	lines.append("\t\t\"id\": %d," % int(record["id"]))
	lines.append("\t\t\"tileset\": %d," % int(record["tileset"]))
	lines.append("\t\t\"tiles\": [")
	for row: Array in record["tiles"] as Array:
		var ids: Array[String] = []
		for id: float in row:
			ids.append("%d" % int(id))
		lines.append("\t\t\t[%s]," % ", ".join(ids))
	lines.append("\t\t],")
	lines.append("\t\t# one row per PIXEL row, %d of them" % (record["paint"] as Array).size())
	lines.append("\t\t\"paint\": [")
	for row: String in record["paint"] as Array:
		lines.append("\t\t\t\"%s\"," % row)
	lines.append("\t\t],")
	lines.append("\t},")
	return "\n".join(lines)


func _script(entries: Array[String]) -> String:
	var body: String = "\n".join(entries)
	if not entries.is_empty():
		body = "\n%s\n" % body
	return """extends RefCounted

## Painted houses, one row of characters per row of graphics tiles.
## GENERATED by `tools/house_pins.gd`. Paint and regenerate; do not edit here.

## There is no character for a DOOR: a door is a wall you walk through, and
## walking through is collision, which nothing here touches. None for a SLOPE
## either: the top of a column's wall is that column's roof height.
const NONE := "."
const WALL := "W"
const ROOF := "R"
const FRONT := "F"

## Per drawing: `id`, `tileset`, the `tiles` rectangle that identifies it north
## row first, and `paint`, one string per pixel row.
const HOUSES: Array = [%s]


static func of_tileset(number: int) -> Array:
	var out: Array = []
	for house: Dictionary in HOUSES:
		if int(house["tileset"]) == number:
			out.append(house)
	return out
""" % body
