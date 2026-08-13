extends SceneTree

## Turns a painted `levels.json` into `shape/levels.gd`, and says what is wrong
## with it on the way.
##
## The painting is the one thing in this project that cannot be derived: how many
## floors a place has, and which. `tools/level_page.py` is where it is done and
## this is what makes it usable, exactly as `tools/pass_pins.py` does for the
## tile survey.
##
## ONLY A WALKABLE CELL CARRIES A LEVEL. The cartridge's own collision says which
## cells those are, and a blocked one is rock: it has no floor, its painted value
## is whatever the brush happened to cross, and reading it would put a floor
## inside a mountain. A wall cell is the same and says so itself.
##
##   Godot --path <pokerecomp> -s tools/level_pins.gd -- <cache> <levels.json> \
##       [--write]

const MOD := "user://mods/voxel3d"
const OUT := "res://../../GitHub/pokerecomp-decrypt-mods/mods/voxel3d/shape/levels.gd"
## A cell with no level: rock, a wall, or anything off the walk grid.
const NONE := "."


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <levels.json> [--write]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var painted: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if painted == null or not (painted as Dictionary).has("maps"):
		print("not a levels.json: ", args[1])
		quit(1)
		return
	if String((painted as Dictionary).get("unit", "")) != "level16":
		print("unexpected unit ", (painted as Dictionary).get("unit"),
			": this reads level16 only")
		quit(1)
		return

	var entries: Array[String] = []
	var complaints: Array[String] = []
	var total_cells: int = 0
	for record: Dictionary in (painted as Dictionary)["maps"]:
		var map: Gen2WorldMap = null
		for candidate: Gen2WorldMap in data.world_maps():
			if candidate.group == int(record["group"]) \
					and candidate.number == int(record["number"]):
				map = candidate
		if map == null:
			complaints.append("no map %s,%s in the cartridge" % [
				record["group"], record["number"]
			])
			continue
		var cells := Vector2i(int(record["cells"][0]), int(record["cells"][1]))
		var levels: Array = record["levels"]
		var walls: Array = record["walls"]

		var rows: Array[String] = []
		var walkable := PackedByteArray()
		walkable.resize(cells.x * cells.y)
		var used: bool = false
		for cy: int in cells.y:
			var row: String = ""
			for cx: int in cells.x:
				var permission: int = Gen2WorldCollision.permission_for(
					map.collision_at(cx, cy)
				)
				# WATER PINS NOTHING. A lake's surface is one level by definition
				# and the mesher already works it out from the shore it touches
				# (`mesher.gd:_settle_ponds`), so a painted level on water is at
				# best a restatement and at worst a contradiction: in Mt Mortar
				# the cave lake sat at 0 beside a floor painted 3, which read as a
				# 48px drop into the water and was only ever the default showing
				# through. Let the shore say it.
				var can_stand: bool = permission == Gen2WorldCollision.LAND_TILE
				walkable[cy * cells.x + cx] = 1 if can_stand else 0
				var level: Variant = (levels[cy] as Array)[cx]
				if not can_stand or int((walls[cy] as Array)[cx]) == 1 or level == null:
					row += NONE
					continue
				var value: int = int(level)
				if value < 0 or value > 9:
					complaints.append("%d,%d cell %d,%d level %d is off the scale" % [
						map.group, map.number, cx, cy, value
					])
					row += NONE
					continue
				if value > 0:
					used = true
				row += str(value)
			rows.append(row)
		total_cells += cells.x * cells.y

		# Where the cartridge itself moves you between places. A ladder in a cave
		# is a warp, and the two levels it joins are MEANT to be a storey apart:
		# you climb it, you do not walk it, so a step there is the thing working
		# rather than a fault. Every complaint left in Mt Mortar was one of these.
		var warped: Dictionary = {}
		for event: Variant in map.events.get("warps", []):
			warped[Vector2i(int((event as Dictionary).get("x", -1)),
				int((event as Dictionary).get("y", -1)))] = true

		# A step of more than one level between two cells you can WALK between is
		# a cliff in the middle of a path. It is worth reporting rather than
		# building: either the painting is a cell out, or the map really is one of
		# the impossible ones and a person has to choose.
		for cy: int in cells.y:
			for cx: int in cells.x:
				if walkable[cy * cells.x + cx] == 0 or rows[cy][cx] == NONE:
					continue
				for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var to := Vector2i(cx + step.x, cy + step.y)
					if to.x >= cells.x or to.y >= cells.y:
						continue
					if walkable[to.y * cells.x + to.x] == 0 or rows[to.y][to.x] == NONE:
						continue
					var rise: int = absi(
						int(rows[cy][cx]) - int(rows[to.y][to.x])
					)
					if rise > 1 and not warped.has(Vector2i(cx, cy)) \
							and not warped.has(to):
						complaints.append(
							"%d,%d walk from %d,%d to %d,%d steps %d levels" % [
								map.group, map.number, cx, cy, to.x, to.y, rise
							]
						)
		if not used:
			complaints.append("%d,%d is all level 0 and pins nothing" % [
				map.group, map.number
			])
		entries.append('\t"%d,%d": [\n%s\n\t],' % [
			map.group, map.number,
			"\n".join(rows.map(func(r: String) -> String: return '\t\t"%s",' % r))
		])

	print("%d maps, %d cells" % [entries.size(), total_cells])
	for line: String in complaints:
		print("  ! ", line)
	if complaints.is_empty():
		print("  nothing to complain about")
	if not args.has("--write"):
		print("(dry run; pass --write to write shape/levels.gd)")
		quit()
		return

	var text: String = _header() + "\n".join(entries) + "\n" + _footer()
	var path: String = ProjectSettings.globalize_path(OUT)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("cannot write ", path)
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("wrote ", path)
	quit()


func _header() -> String:
	return """extends RefCounted

## Ground levels, painted by hand, one row of characters per row of walk cells.
##
## GENERATED by `tools/level_pins.gd` from a `levels.json` that
## `tools/level_page.py` saved. Do not edit here; paint and regenerate.
##
## How many floors a place has is the one thing about these maps that cannot be
## derived. Out of doors a cliff face gives it away and the mesher reads it, but
## a cave draws its rock the same whether the floor behind it is a storey up or
## the same floor carrying on, and no measurement settles that. So it is asked.
##
## A character is one walk cell: a digit is that cell's floor level, and each
## level is 16 world pixels. A dot is a cell with NO floor, which is rock, a
## transition, or anything the cartridge does not let you stand on. Only cells
## the collision calls walkable ever carry a digit, because a level painted on
## rock is a floor inside a mountain.

const NONE := "."
## World pixels per level, which is one walk cell.
const LEVEL: int = 16

## "<group>,<number>" -> one string per row of walk cells.
const MAPS: Dictionary = {
"""


func _footer() -> String:
	return """}


## The floor height in world pixels for a walk cell, or -1 where this table says
## nothing: an unpainted map, rock, or a transition whose height belongs to the
## floors either side of it.
static func height_at(group: int, number: int, cell: Vector2i) -> int:
	var rows: Variant = MAPS.get("%d,%d" % [group, number], null)
	if not (rows is Array) or cell.y < 0 or cell.y >= (rows as Array).size():
		return -1
	var row: String = (rows as Array)[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return -1
	var mark: String = row[cell.x]
	if mark == NONE:
		return -1
	return int(mark) * LEVEL


## Whether any level was painted for this map at all.
static func has(group: int, number: int) -> bool:
	return MAPS.has("%d,%d" % [group, number])
"""
