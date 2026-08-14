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
## THE ARROWS BECOME BANDS HERE and nobody is ever asked for a number. A tile
## painted with an arrow stands one band below the tile it points away from, so
## its fall is how far it is from the top of its own slope; a slope with no flat
## tile at the top of it is levelled so its ridge stands at zero.
##
##   Godot --path <pokerecomp> -s tools/house_pins.gd -- <cache> <houses.json> \
##       [--write]

const MOD := "user://mods/voxel3d"
## Written back into the INSTALLED mod, which is where every other tool here
## reads the mod from. On a development machine that path is a symlink to the
## checkout, so the generated file lands in the repository.
const OUT := "%s/shape/houses.gd" % MOD

const NONE := "."
const WALL := "W"
const PITCH := "P"
const ROOF := "R"
const DOOR := "D"
## Each falling arrow, and the step from a tile toward the top of its own slope,
## which is the direction the arrow points AWAY from.
const RISE: Dictionary = {
	"<": Vector2i(1, 0),
	">": Vector2i(-1, 0),
	"^": Vector2i(0, 1),
	"v": Vector2i(0, -1),
}


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
	if String((painted as Dictionary).get("unit", "")) != "tile8":
		print("unexpected unit ", (painted as Dictionary).get("unit"),
			": this reads tile8 only")
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
		if paint.size() != tiles.size() \
				or (paint[0] as Array).size() != (tiles[0] as Array).size():
			complaints.append("%s: painted %dx%d over a %dx%d drawing" % [
				name, (paint[0] as Array).size(), paint.size(),
				(tiles[0] as Array).size(), tiles.size()
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
		entries.append(_entry(record, _falls(paint)))

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
	for row: int in paint.size():
		for column: int in (paint[row] as Array).size():
			if (paint[row] as Array)[column] != (guess[row] as Array)[column]:
				return false
	return true


## HOW MANY BANDS BELOW ITS OWN RIDGE each painted roof tile stands.
##
## An arrow says which way the water runs off, so the top of the slope is the way
## the arrow points AWAY from: walk that way while the tiles carry the same
## arrow, and how far you get is how far this tile has fallen. A tile beside a
## flat one has fallen one band, which is the gable this mod already measures;
## the far corner of a two-tile gable end has fallen two, which is what the
## reviewer measured tileset 3's own roof at.
##
## THEN THE SLOPE IS LEVELLED. A roof with a flat section already has a zero in
## it to fall from. A roof that is slope the whole way across, which is what a
## great roof is, has none, so every tile of it would stand below a ridge that is
## not drawn anywhere. Subtracting the lowest fall in each connected roof puts
## the ridge back at zero and leaves every difference exactly as painted.
func _falls(paint: Array) -> Array:
	var height: int = paint.size()
	var width: int = (paint[0] as Array).size()
	var fall: Array = []
	for row: int in height:
		var line: Array = []
		for column: int in width:
			var stroke: String = (paint[row] as Array)[column]
			if not RISE.has(stroke):
				line.append(0)
				continue
			var step: Vector2i = RISE[stroke]
			var at := Vector2i(column, row) + step
			var far: int = 1
			while at.x >= 0 and at.y >= 0 and at.x < width and at.y < height \
					and (paint[at.y] as Array)[at.x] == stroke:
				far += 1
				at += step
			line.append(far)
		fall.append(line)

	var seen: Dictionary = {}
	for row: int in height:
		for column: int in width:
			if seen.has(row * width + column) or not _is_roof(paint, row, column):
				continue
			var region: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(column, row)]
			seen[row * width + column] = true
			var lowest: int = 0x7fffffff
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				region.append(at)
				lowest = mini(lowest, int((fall[at.y] as Array)[at.x]))
				for step: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var next: Vector2i = at + step
					if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
						continue
					if seen.has(next.y * width + next.x) \
							or not _is_roof(paint, next.y, next.x):
						continue
					seen[next.y * width + next.x] = true
					stack.append(next)
			if lowest <= 0:
				continue
			for at: Vector2i in region:
				(fall[at.y] as Array)[at.x] = int((fall[at.y] as Array)[at.x]) - lowest
	return fall


func _is_roof(paint: Array, row: int, column: int) -> bool:
	var stroke: String = (paint[row] as Array)[column]
	return stroke == ROOF or RISE.has(stroke)


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


func _entry(record: Dictionary, fall: Array) -> String:
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
	lines.append("\t\t\"paint\": [")
	for row: Array in record["paint"] as Array:
		lines.append("\t\t\t\"%s\"," % "".join(row))
	lines.append("\t\t],")
	lines.append("\t\t\"fall\": [")
	for row: Array in fall:
		var bands: Array[String] = []
		for band: int in row:
			bands.append("%d" % band)
		lines.append("\t\t\t[%s]," % ", ".join(bands))
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
## A house is the one drawing in Generation II that packs three different
## surfaces into one flat picture: the wall seen face-on, the roof seen from
## above, and on some tilesets the front PITCH of that roof drawn face-on as
## well. Nothing measurable tells them apart, so a person says which is which.
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

## What one painted character means.
const NONE := "."
const WALL := "W"
const PITCH := "P"
const ROOF := "R"
const DOOR := "D"
const FALL_WEST := "<"
const FALL_EAST := ">"
const FALL_NORTH := "^"
const FALL_SOUTH := "v"

## One entry per corrected drawing:
##
##   tileset  the tileset its tile ids belong to
##   tiles    the rectangle of tile ids that identifies it, north row first
##   paint    one string per tile row, a character per tile
##   fall     per tile, how many 8px bands a roof tile stands below the ridge of
##            its own roof. Counted from the painted arrows at generation time,
##            so nobody is ever asked for a number: an arrow and the tiles it
##            covers are the whole of a slope.
const HOUSES: Array = [%s]


## The drawings painted on one tileset. A tile id means nothing without it.
static func of_tileset(number: int) -> Array:
	var out: Array = []
	for house: Dictionary in HOUSES:
		if int(house["tileset"]) == number:
			out.append(house)
	return out
""" % [corrected, placements, unchanged, body]
