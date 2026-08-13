extends SceneTree

## What the level page paints ON and what it starts FROM.
##
## Height is the one thing this mod cannot read off a drawing on its own. A rock
## wall's face says there is a step, but nothing in the tile layer says which
## side of it is up, how many levels a cave has, or where a flight of stairs
## arrives. Outdoors a cliff pass guesses it from the drawn faces and gets 41
## maps right; indoors there is no cliff to read and every cave comes out flat.
##
## So it is asked. The unit is the WALK CELL, 16x16 pixels, because that is what
## a level step is: one level is one cell of height, and a wall or a flight is
## drawn 2x2 tiles, which is one cell. Painting per graphics tile would ask for
## four answers where the world only has one.
##
## Emits per map, beside the map's own art from `tools/map_art.gd`:
##
##   level_<group>_<number>.json   size in cells, and per cell the height this
##                                 mod currently measures and whether anything
##                                 in it stands up
##
## The guess is exported so the page can PRE-FILL it. A person correcting a
## proposal is doing a different and much smaller job than a person painting a
## map from blank, and the outdoor maps are mostly already right.
##
##   Godot --path <pokerecomp> -s tools/level_export.gd -- <cache> <out dir> \
##       <group>,<number> [<group>,<number> ...]
##   Godot ... -- <cache> <out dir> caves      every map on a cave tileset
##   Godot ... -- <cache> <out dir> stairs     every map holding a staircase

const MOD := "user://mods/voxel3d"
const CELL_TILES: int = 2
## THE UNIT IS THE WHOLE LEVEL, one walk cell, 16px. There are no half levels
## and there deliberately cannot be.
##
## Half a level was offered and withdrawn within the hour, for a reason worth
## keeping: these maps are not consistent three-dimensional spaces. The reviewer
## put it exactly, having gone looking: one lake has ground at different half
## heights all the way round it, which no single water surface can meet. A 2D
## tile map never had to answer for that and a diorama does, so the half step is
## the wrong tool. It let a person write down an impossibility one cell at a
## time; whole levels make them choose, which is the only thing that can be
## built.
##
## The 8px things that are real are not levels at all: water is recessed and a
## jumping ledge is a wedge, both per TILE and both the mesher's own business.
const BAND: int = 16
## `mesher.gd`'s own art modes, which are what say whether a tile is floor.
const ART_FLAT: int = 0
const ART_UPRIGHT: int = 2

## The tilesets whose rock walls are unpinned, which is where the question is
## open. See HANDOFF open work 5.
const CAVE_TILESETS: Array[int] = [24, 29, 30]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <out dir> <group>,<number>... | caves | stairs")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var out: String = args[1]
	DirAccess.make_dir_recursive_absolute(out)

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var wanted: Array[Gen2WorldMap] = []
	var selector: String = args[2]
	for map: Gen2WorldMap in data.world_maps():
		if selector == "caves":
			if CAVE_TILESETS.has(map.tileset):
				wanted.append(map)
			continue
		if selector == "stairs":
			if _has_stairs(map, data, profile, shape_script, source_script):
				wanted.append(map)
			continue
		for index: int in range(2, args.size()):
			var pair: PackedStringArray = args[index].split(",")
			if pair.size() == 2 and map.group == int(pair[0]) and map.number == int(pair[1]):
				wanted.append(map)

	var written: int = 0
	for map: Gen2WorldMap in wanted:
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var size: Vector2i = mesher.size_tiles()
		if size == Vector2i.ZERO:
			continue
		var cells := Vector2i(
			map.width_blocks * CELL_TILES, map.height_blocks * CELL_TILES
		)
		var levels: Array = []
		var walls: Array = []
		for cy: int in cells.y:
			var level_row: Array = []
			var wall_row: Array = []
			for cx: int in cells.x:
				# A cell's LEVEL is the GROUND in it and nothing else. Only flat art
				# standing at or above the plane counts: a bed, a counter and a
				# ledge are `top` art and are furniture on a floor rather than a
				# floor, and water is recessed on purpose and is not a level down.
				# Reading either of those put levels 2 and 3 through the middle of
				# a cave and made the guess worse than no guess at all.
				#
				# A WALL here means a TRANSITION between two levels, and the only
				# thing that draws one is a cliff FACE, which the profile names.
				# Flagging everything that stands up was the first version and it
				# was plainly wrong: it made a wall of every tree and every house,
				# neither of which is a change of level. A tree is a thing on a
				# floor and the floor under it is what gets painted.
				var floor_px: int = 1 << 30
				var faces: bool = false
				for ty: int in range(cy * CELL_TILES, (cy + 1) * CELL_TILES):
					for tx: int in range(cx * CELL_TILES, (cx + 1) * CELL_TILES):
						var at: int = ty * size.x + tx
						if shape.is_cliff(mesher._tiles[at]):
							faces = true
						if mesher._art[at] != ART_FLAT:
							continue
						var height: int = mesher._heights[at]
						if height >= 0:
							floor_px = mini(floor_px, height)
				# A wall carries no level at all, because its height comes from the
				# floors either side of it. Writing one anyway is a number that
				# means nothing and reads as though it does.
				if faces:
					level_row.append(null)
					wall_row.append(1)
					continue
				var height_px: int = 0 if floor_px >= (1 << 30) else floor_px
				level_row.append(floori(float(height_px) / float(BAND)))
				wall_row.append(0)
			levels.append(level_row)
			walls.append(wall_row)

		var record: Dictionary = {
			"group": map.group,
			"number": map.number,
			"tileset": map.tileset,
			"cells": [cells.x, cells.y],
			# Named, so nothing downstream has to guess what a 2 counts.
			"unit": "level16",
			"outside": Gen2WorldPhoneHost.is_outside_environment(map.environment),
			"art": "level_%d_%d.png" % [map.group, map.number],
			"levels": levels,
			"walls": walls,
		}
		var path: String = "%s/level_%d_%d.json" % [out, map.group, map.number]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("cannot write ", path)
			continue
		file.store_string(JSON.stringify(record))
		file.close()
		written += 1
		print("%d,%d ts%d  %dx%d cells" % [
			map.group, map.number, map.tileset, cells.x, cells.y
		])
	print("wrote ", written, " maps to ", out)
	quit()


func _has_stairs(
	map: Gen2WorldMap, data: GameData, profile: GDScript,
	shape_script: GDScript, source_script: GDScript
) -> bool:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return false
	var shape: RefCounted = shape_script.new(profile, map.tileset)
	var source: RefCounted = source_script.new(null, map, tileset)
	var width: int = map.width_blocks * 4
	var height: int = map.height_blocks * 4
	for ty: int in height:
		for tx: int in width:
			var tile: int = source.tile_at(tx, ty)
			if tile < 0:
				continue
			if shape.at(tile, source.permission_at(Vector2i(tx >> 1, ty >> 1))) == &"stairs":
				return true
	return false
