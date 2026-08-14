extends SceneTree

## Turns a painted `houses.json` into `shape/houses.gd`, and says what is wrong
## with it on the way.
##
## Which surface of a house a tile depicts is the one thing about these drawings
## that cannot be derived: a wall seen face-on, a roof seen from above and the
## front pitch of a roof drawn face-on are all just pixels, and reading them the
## same way makes every house either a barn or a block.
## `tools/house_page.py` is where that is painted and this is what makes it
## usable, exactly as `tools/level_pins.gd` does for the ground levels.
##
## ONLY A DRAWING THE PAINTING CORRECTED IS WRITTEN. The page arrives pre-filled
## with what the mod already resolves, so a drawing left as it came is a drawing
## the current reading got right, and writing it would put today's behaviour in a
## table for no reason. That is also what makes an empty table exactly today's
## game, triangle for triangle.
##
## THE PAINTING SAYS WHICH SURFACE EACH PIXEL IS AND NOTHING ELSE. How far a roof
## has fallen is not asked for, because it does not have to be: with the wall and
## the roof separated per pixel, the top of each column's wall IS that column's
## roof height, so a hipped end and a gable both fall out of the painting with no
## number in them anywhere.
##
##   Godot --path <pokerecomp> -s tools/house_pins.gd -- <cache> <houses.json> \
##       [--write]

const MOD := "user://mods/voxel3d"
## Written back into the INSTALLED mod, which is where every other tool here
## reads the mod from. On a development machine that path is a symlink to the
## checkout, so the generated file lands in the repository.
const OUT := "%s/shape/houses.gd" % MOD

## THE PIXEL, not the tile, is the unit. A hipped roof comes down as a DIAGONAL
## across its tiles, so a tile there is part roof and part wall and no answer at
## tile resolution is right.
const TILE: int = 8
const NONE := "."
const WALL := "W"
const ROOF := "R"
## The roof drawn FACE-ON rather than from above, so it leans back over the house
## instead of standing up like a wall.
const FRONT := "F"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <houses.json> [--write]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
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
		# The page counts DRAWINGS, flooded out of connected building tiles; the
		# mesher matches the ARRANGEMENT wherever it occurs, which is the same
		# thing plus any place the same rectangle is drawn without the flood
		# joining it up. The second is the number the painting will actually
		# reach, so it is worth saying and is not a fault.
		if found != int(record["placements"]):
			notes.append("%s: painted over %d, the arrangement occurs %d times"
				% [name, int(record["placements"]), found])
		corrected += 1
		placements += found
		# HOW MANY TILES THE PAINTING CUTS, which is the part of it the mesher
		# cannot build yet: a tile painted two ways at once wants the wall's top
		# read per pixel COLUMN, and until that emitter exists those tiles keep
		# the answer the passes gave them. Said out loud rather than left silent,
		# because it is the difference between what was painted and what stands.
		var cut: int = _cut(paint)
		if cut > 0:
			notes.append("%s: %d of its %d tiles are painted two ways and wait on the"
				% [name, cut, (record["tiles"] as Array).size()
					* ((record["tiles"][0] as Array).size())]
				+ " per-column emitter")
		entries.append(_entry(record))

	var out: String = _script(entries, corrected, placements, unchanged)
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


## How many tiles of a painting are cut rather than filled: the diagonals.
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


## How many times the game places this arrangement, which is what says whether a
## painting made against an older cache still describes anything.
func _count(data: GameData, tileset_number: int, tiles: Array) -> int:
	var across := Vector2i((tiles[0] as Array).size(), tiles.size())
	var found: int = 0
	for map: Gen2WorldMap in data.world_maps():
		if map.tileset != tileset_number:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var w: int = map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2
		var h: int = map.height_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH * 2
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


func _script(entries: Array[String], corrected: int, placements: int, unchanged: int) -> String:
	var body: String = "\n".join(entries)
	if not entries.is_empty():
		body = "\n%s\n" % body
	return """extends RefCounted

## The houses, painted by hand, one row of characters per row of graphics tiles.
##
## GENERATED by `tools/house_pins.gd` from a `houses.json` that
## `tools/house_page.py` saved. Do not edit here; paint and regenerate.
##
## A house packs different surfaces into one flat picture: the wall, which you
## are looking AT, and the roof, which you are either looking DOWN onto or seeing
## from the FRONT. Nothing measurable tells them apart, so a person says which is
## which.
##
## THE UNIT IS THE PIXEL AND IT HAS TO BE. A hipped roof comes down as a diagonal
## across its tiles, so a tile there is part roof and part wall: read at tile
## resolution, "roof" lifts the top of the wall onto the roof and "wall" cuts the
## corner off the roof. Painted per pixel there is no such choice to get wrong.
##
## THE ARRANGEMENT IS THE KEY, NEVER A TILE ID. One id is the awning course of
## one house and the eave of another, so a pin cannot reach one drawing without
## reaching the other. A drawing is its whole rectangle of tile ids INCLUDING its
## holes, and two placements of one house carry the same rectangle, so one
## painting serves every placement of it.
##
## THIS IS AN OVERRIDE, exactly as `levels.gd` is an override on the cliff pass.
## Only a drawing a person actually CORRECTED is in here: where the painting
## agreed with what the mod already resolved, nothing is written and the tile
## keeps the answer the passes gave it. %d drawings corrected, covering %d
## placements; %d were already right.

## What one painted character means. There is no character for a DOOR: a door is
## a wall the player walks through, and walking through is collision, which
## nothing here touches. There is none for a SLOPE either: with wall and roof
## separated per pixel, the top of a column's wall is that column's roof height.
const NONE := "."
const WALL := "W"
const ROOF := "R"
const FRONT := "F"

## One entry per corrected drawing:
##
##   tileset  the tileset its tile ids belong to
##   tiles    the rectangle of tile ids that identifies it, north row first
##   paint    one string per PIXEL row, a character per pixel, so eight rows and
##            eight characters per tile
const HOUSES: Array = [%s]


## The drawings painted on one tileset. A tile id means nothing without it.
static func of_tileset(number: int) -> Array:
	var out: Array = []
	for house: Dictionary in HOUSES:
		if int(house["tileset"]) == number:
			out.append(house)
	return out
""" % [corrected, placements, unchanged, body]
