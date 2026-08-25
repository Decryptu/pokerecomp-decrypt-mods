extends SceneTree

## THE BLANK COURSE OF ONE TILESET, counted and then DRAWN so it can be looked at.
##
## `profile.gd:ROOM_WALL` is the wall this mod rings an interior with, and every
## entry in it was chosen the same way: count, over every indoor map on the
## tileset, the 2x2 tile quad standing at the top of a column whose lower half
## resolves upright, and take the commonest. The count picks the CANDIDATE and
## only the picture can choose between ties, which is not a maxim: three of the
## twenty-nine were wrong on the first build and each was caught by looking. A
## hedge ringed a station platform in greenery, a barred cellar door ringed an
## icy cavern, and tileset 21 took a window CORNER, which put the top left of a
## window round every room on it.
##
## The probe that did the counting was never checked in, so a wrong pin cost a
## rewrite before it cost a fix. This is that probe, with the picture beside it:
##
##   Godot --path <pokerecomp> -s tools/room_wall.gd -- <cache> <tileset> [out.png]
##
## Prints the ranking as text, and with an out path writes a sheet of the top
## candidates, each tiled THREE BY THREE with its arrangement written under it,
## because a course is a thing that repeats and one copy of it says nothing about
## whether it does. A blank wall is the plate with the least in it.
##
## Needs no display: it paints an Image and saves it.

const MOD := "user://mods/voxel3d"
const TILE: int = 8
const BLOCK_TILES: int = 4
## How many candidates the sheet draws, best first.
const SHOWN: int = 8
## The repeat that says whether a course is blank, in tiles each way.
const REPEAT: int = 3
const GUTTER: int = 12
const LABEL: int = 10
const BACK := Color(0.09, 0.09, 0.11)
const INK := Color(0.93, 0.93, 0.95)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <cache> <tileset> [out.png]")
		quit(1)
		return
	if args.size() > 2 and Gen2ToolPath.refuses(args[2]):
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var number: int = int(args[1])
	var tileset: Gen2WorldTileset = data.world_tileset(number)
	if tileset == null:
		print("no tileset ", number)
		quit(1)
		return

	var shape: RefCounted = (load("%s/shape/tile_shape.gd" % MOD) as GDScript).new(
		load("%s/shape/profile.gd" % MOD), number
	)
	var counts: Dictionary = {}
	# Per candidate, the map it was counted on MOST, which is the palette it is
	# drawn in. A tileset is not one palette: tileset 8 is the department store
	# and the offices over it, and the same wall is blue on one floor and green on
	# another, so a sheet painted in one map's table for the whole tileset says
	# nothing true about colour at all. The first cut of this did that and drew a
	# blue wall green.
	var homes: Dictionary = {}
	var maps: int = 0
	for map: Gen2WorldMap in data.world_maps():
		if map.tileset != number or _is_outside(map):
			continue
		maps += 1
		_count_map(map, tileset, shape, counts, homes)

	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a]) > int(counts[b]))
	print("tileset ", number, ", ", maps, " indoor maps, ",
		ranked.size(), " candidates")
	for index: int in mini(ranked.size(), SHOWN * 2):
		print("  %2d  %-24s %d" % [index, ranked[index], int(counts[ranked[index]])])
	if ranked.is_empty():
		print("NO CANDIDATE, which is the tell that the tileset must not have one.")
	elif args.size() > 2:
		_sheet(data, tileset, ranked, homes, args[2])
		print("sheet in ", args[2])
	quit()


## A map the host files as outdoors has no room to ring.
func _is_outside(map: Gen2WorldMap) -> bool:
	return map.environment == 1 or map.environment == 2


## THE QUAD AT THE TOP OF AN UPRIGHT COLUMN, per map.
##
## A wall is drawn as a run of tiles up a column and the blank course is the pair
## of rows above the run's own top, so what is counted is the 2x2 quad standing
## there: two ids across because a wall may alternate, two rows down because a
## course is two rows deep. Counted at BOTH alignments of the column, since a
## two-tile drawing read off the wrong one is the same wall out of phase.
func _count_map(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, shape: RefCounted,
	counts: Dictionary, homes: Dictionary
) -> void:
	var here: Dictionary = {}
	var across: int = map.width_blocks * BLOCK_TILES
	var down: int = map.height_blocks * BLOCK_TILES
	for ty: int in down - 1:
		for tx: int in across - 1:
			# The tile under the pair has to be part of a standing wall, or every
			# blank stretch of floor in the room counts as a course.
			var under: StringName = _class_at(map, tileset, shape, tx, ty + 2)
			if under != &"wall":
				continue
			var quad: Array = []
			var blank: bool = false
			for row: int in 2:
				for column: int in 2:
					quad.append(_tile_at(map, tileset, tx + column, ty + row))
					# AND NOT THE FILLER, which is the trap this probe was written
					# after walking into. `void` is the black block the cartridge pads
					# an interior out to its rectangle with, it lies above every wall
					# the map has, and it is a plate with nothing whatever in it: on
					# tileset 21 it wins the count outright and looks more like a blank
					# course than the blank course does.
					if _class_at(map, tileset, shape, tx + column, ty + row) == &"void":
						blank = true
			if blank or quad.has(-1):
				continue
			var key: String = str(quad)
			counts[key] = int(counts.get(key, 0)) + 1
			here[key] = int(here.get(key, 0)) + 1
			if int(here[key]) > int((homes.get(key, [null, 0]) as Array)[1]):
				homes[key] = [map, int(here[key])]


func _tile_at(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, tx: int, ty: int
) -> int:
	var across: int = map.width_blocks * BLOCK_TILES
	var down: int = map.height_blocks * BLOCK_TILES
	if tx < 0 or ty < 0 or tx >= across or ty >= down:
		return -1
	@warning_ignore("integer_division")
	var block: int = map.block_at(tx / BLOCK_TILES, ty / BLOCK_TILES)
	return tileset.tile_index(block, (ty & 3) * BLOCK_TILES + (tx & 3))


func _class_at(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, shape: RefCounted,
	tx: int, ty: int
) -> StringName:
	var tile: int = _tile_at(map, tileset, tx, ty)
	if tile < 0:
		return &""
	return shape.at(
		tile,
		Gen2WorldCollision.permission_for(map.collision_at(tx >> 1, ty >> 1))
	)


## Each candidate tiled three by three, in a row, best first.
func _sheet(
	data: GameData, tileset: Gen2WorldTileset, ranked: Array,
	homes: Dictionary, out: String
) -> void:
	var indices: PackedByteArray = data.world_tileset_indices(tileset.number)
	var shown: int = mini(ranked.size(), SHOWN)
	var plate: int = REPEAT * 2 * TILE
	var image: Image = Image.create(
		GUTTER + shown * (plate + GUTTER), GUTTER + plate + LABEL + GUTTER,
		false, Image.FORMAT_RGBA8
	)
	image.fill(BACK)
	for slot: int in shown:
		var quad: Array = str_to_var(ranked[slot]) as Array
		var palettes: Array = Gen2WorldPalette.tile_palettes(
			data, (homes[ranked[slot]] as Array)[0] as Gen2WorldMap, tileset,
			Gen2WorldPalette.TIME_DAY
		)
		var left: int = GUTTER + slot * (plate + GUTTER)
		for row: int in REPEAT * 2:
			for column: int in REPEAT * 2:
				_blit(
					image, indices, palettes, int(quad[(row & 1) * 2 + (column & 1)]),
					left + column * TILE, GUTTER + row * TILE, tileset.tile_count
				)
		# The rank alone, as a run of pixels, so the sheet needs no font: slot 0 is
		# one mark, slot 3 is four. The text ranking is what carries the ids.
		for mark: int in slot + 1:
			for y: int in 4:
				for x: int in 4:
					image.set_pixel(
						left + mark * 6 + x, GUTTER + plate + 3 + y, INK
					)
	image.save_png(out)


func _blit(
	image: Image, indices: PackedByteArray, palettes: Array,
	tile: int, at_x: int, at_y: int, tile_count: int
) -> void:
	var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
		else PackedColorArray()
	var stride: int = tile_count * TILE
	for y: int in TILE:
		var row: int = y * stride + tile * TILE
		for x: int in TILE:
			var index: int = int(indices[row + x]) if row + x < indices.size() else 0
			image.set_pixel(
				at_x + x, at_y + y,
				palette[index] if index < palette.size() else Color.MAGENTA
			)
