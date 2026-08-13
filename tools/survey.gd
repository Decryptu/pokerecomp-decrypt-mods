extends SceneTree

## Lays out every block a tileset actually places, twice: as the cartridge draws
## it and as this mod builds it, on the same grid, so the two can be compared
## block by block.
##
## The survey's unit is the BLOCK, not a map location. A block is 4x4 tiles on
## 2x2 walk cells and it is the unit Generation II authors the world out of: a
## tree, a sign, a fence corner, a stretch of path is each one block. Walking a
## map to find them is the slow way round, misses everything the walk did not
## pass, and shows the same drawing over and over; every block of a tileset laid
## out at once is the whole vocabulary in a single picture, and 35 pictures is
## the whole game.
##
## Emits, per tileset, into the output directory:
##
##   ts<n>_2d.png    the cartridge's own art, one block per grid slot
##   ts<n>_3d.png    the same grid meshed and shot from a fixed orthographic eye
##   ts<n>.json      the grid, and per block: its id, its four permissions, the
##                   shapes resolved for its tiles and the heights measured
##
## `tools/survey_sheet.py` pairs them into the annotated sheet a reviewer marks
## up. Nothing here writes to the mod: a pin is a human's answer, and this only
## asks the question.
##
## Run with a display attached, since it renders:
##
##   Godot --path <pokerecomp> -s tools/survey.gd -- <cache> <tileset|all> <out>

const MOD := "user://mods/voxel3d"
const CELL: float = 16.0
const TILE: int = 8
## Tiles across a block, and cells across a block.
const BLOCK_TILES: int = 4
const BLOCK_CELLS: int = 2
const BLOCK_PIXELS: int = BLOCK_TILES * TILE

## Blocks across the sheet, and the gap between two of them, in blocks. The gap
## keeps a structure from measuring its height through its neighbour, which is
## the whole reason the blocks are not simply tiled edge to edge.
const COLUMNS: int = 12
const GAP: int = 1

## Screen pixels per world pixel in the 3D shot. Three keeps a 32px block on 96
## and the whole sheet inside one viewport.
const SCALE: float = 3.0
## The crop a reviewer sees around each block, in screen pixels, and where the
## block's own ground centre sits inside it. The headroom above is what holds a
## structure measured three cells tall.
const CROP := Vector2i(112, 152)
const CROP_GROUND := Vector2i(56, 118)
## The tallest thing the frame has to hold, in world pixels: the mesher caps a
## measured volume at three walk cells, and a pin could reach a little past it.
const TALLEST: float = 64.0

var _data: GameData = null
var _out: String = ""
var _queue: Array[int] = []
var _stage: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _profile: GDScript = null
var _tile_shape: GDScript = null
var _map_source: GDScript = null
var _frames: int = 0
var _pending: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: <cache> <tileset|all> <out dir>")
		quit(1)
		return
	_data = GameData.open_directory(args[0])
	if _data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_out = args[2]
	DirAccess.make_dir_recursive_absolute(_out)

	_profile = load("%s/shape/profile.gd" % MOD)
	_tile_shape = load("%s/shape/tile_shape.gd" % MOD)
	_map_source = load("%s/shape/map_source.gd" % MOD)
	_atlas = (load("%s/shape/atlas.gd" % MOD) as GDScript).new()
	_mesher = (load("%s/shape/mesher.gd" % MOD) as GDScript).new()
	_stage = (load("%s/world/diorama.gd" % MOD) as GDScript).new()

	var holder := Control.new()
	holder.add_child(_stage.container)
	root.add_child(holder)

	if args[1] == "all":
		for number: int in _placements().keys():
			_queue.append(number)
		_queue.sort()
	else:
		_queue.append(int(args[1]))


## tileset number -> block id -> how many times any map places it, and which map
## places the most of them.
func _placements() -> Dictionary:
	var out: Dictionary = {}
	for map: Gen2WorldMap in _data.world_maps():
		var entry: Dictionary = out.get(map.tileset, {"blocks": {}, "maps": {}})
		var blocks: Dictionary = entry["blocks"]
		for block: int in map.blocks:
			blocks[block] = int(blocks.get(block, 0)) + 1
		(entry["maps"] as Dictionary)[map] = map.blocks.size()
		out[map.tileset] = entry
	return out


## The block a gap is filled with: walkable on all four cells and drawn out of
## the fewest distinct tiles, which is what plain ground looks like from here.
func _filler(tileset: Gen2WorldTileset, blocks: Array) -> int:
	var best: int = -1
	var best_variety: int = 99
	for block: int in blocks:
		var walkable: bool = true
		for cell_y: int in BLOCK_CELLS:
			for cell_x: int in BLOCK_CELLS:
				var permission: int = Gen2WorldCollision.permission_for(
					tileset.collision_index(block, cell_x, cell_y)
				)
				if permission != Gen2WorldCollision.LAND_TILE:
					walkable = false
		if not walkable:
			continue
		var kinds: Dictionary = {}
		for tile: int in BLOCK_TILES * BLOCK_TILES:
			kinds[tileset.tile_index(block, tile)] = true
		if kinds.size() < best_variety:
			best_variety = kinds.size()
			best = block
	return best


## A map made of nothing but the blocks being surveyed, spaced out on filler.
##
## Synthesised rather than found: no real map places every block of its tileset,
## and the ones it does place sit against neighbours that change what a column
## measures. The grid is the only place each drawing is asked the question alone.
func _grid_map(source: Gen2WorldMap, tileset: Gen2WorldTileset, blocks: Array) -> Dictionary:
	var filler: int = _filler(tileset, blocks)
	var rows: int = int(ceil(float(blocks.size()) / float(COLUMNS)))
	var width: int = COLUMNS * (1 + GAP) + GAP
	var height: int = rows * (1 + GAP) + GAP

	var map := Gen2WorldMap.new()
	map.group = source.group
	map.number = source.number
	map.tileset = tileset.number
	map.palette = source.palette
	map.environment = source.environment
	map.width_blocks = width
	map.height_blocks = height
	map.blocks = PackedByteArray()
	map.blocks.resize(width * height)
	for at: int in map.blocks.size():
		map.blocks[at] = filler if filler >= 0 else 0

	var places: Dictionary = {}
	for index: int in blocks.size():
		@warning_ignore("integer_division")
		var slot := Vector2i(index % COLUMNS, index / COLUMNS)
		var at := Vector2i(GAP + slot.x * (1 + GAP), GAP + slot.y * (1 + GAP))
		map.blocks[at.y * width + at.x] = blocks[index]
		places[blocks[index]] = at

	map.collision_width = width * BLOCK_CELLS
	map.collision_height = height * BLOCK_CELLS
	map.collision = PackedByteArray()
	map.collision.resize(map.collision_width * map.collision_height)
	for block_y: int in height:
		for block_x: int in width:
			var block: int = map.block_at(block_x, block_y)
			for cell_y: int in BLOCK_CELLS:
				for cell_x: int in BLOCK_CELLS:
					var index: int = tileset.collision_index(block, cell_x, cell_y)
					map.collision[
						(block_y * BLOCK_CELLS + cell_y) * map.collision_width
						+ block_x * BLOCK_CELLS + cell_x
					] = maxi(index, 0)
	return {"map": map, "places": places, "rows": rows, "filler": filler}


## The cartridge's own drawing of every block, on the survey grid.
func _paint_2d(map: Gen2WorldMap, tileset: Gen2WorldTileset, places: Dictionary) -> Image:
	var indices: PackedByteArray = _data.world_tileset_indices(tileset.number)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_data, map, tileset, Gen2WorldPalette.TIME_DAY
	)
	var stride: int = tileset.tile_count * TILE
	var image: Image = Image.create(
		COLUMNS * BLOCK_PIXELS,
		int(ceil(float(places.size()) / float(COLUMNS))) * BLOCK_PIXELS,
		false, Image.FORMAT_RGBA8
	)
	var slot: int = 0
	for block: int in places:
		@warning_ignore("integer_division")
		var origin := Vector2i(
			(slot % COLUMNS) * BLOCK_PIXELS, (slot / COLUMNS) * BLOCK_PIXELS
		)
		for tile_index: int in BLOCK_TILES * BLOCK_TILES:
			var tile: int = tileset.tile_index(block, tile_index)
			var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
				else PackedColorArray()
			@warning_ignore("integer_division")
			var at := origin + Vector2i(
				(tile_index % BLOCK_TILES) * TILE, (tile_index / BLOCK_TILES) * TILE
			)
			for y: int in TILE:
				var row: int = y * stride + tile * TILE
				for x: int in TILE:
					var color_index: int = int(indices[row + x]) if row + x < indices.size() else 0
					image.set_pixel(
						at.x + x, at.y + y,
						palette[color_index] if color_index < palette.size() else Color.MAGENTA
					)
		slot += 1
	return image


## What the mod resolves each of a block's tiles to, and how tall it built them.
func _verdict(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, shape: RefCounted, at: Vector2i
) -> Dictionary:
	var classes: Dictionary = {}
	var permissions: Array = []
	var heights: Array = []
	var tiles: Array = []
	for cell_y: int in BLOCK_CELLS:
		for cell_x: int in BLOCK_CELLS:
			var cell := Vector2i(at.x * BLOCK_CELLS + cell_x, at.y * BLOCK_CELLS + cell_y)
			permissions.append(
				Gen2WorldCollision.permission_for(map.collision_at(cell.x, cell.y))
			)
			heights.append(_mesher.height_at_position(
				Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)
			))
	for tile_index: int in BLOCK_TILES * BLOCK_TILES:
		var tile_x: int = at.x * BLOCK_TILES + (tile_index % BLOCK_TILES)
		@warning_ignore("integer_division")
		var tile_y: int = at.y * BLOCK_TILES + (tile_index / BLOCK_TILES)
		@warning_ignore("integer_division")
		var permission: int = permissions[
			(tile_index / BLOCK_TILES / BLOCK_CELLS) * BLOCK_CELLS
			+ (tile_index % BLOCK_TILES) / BLOCK_CELLS
		]
		var tile: int = _map_tile(map, tileset, tile_x, tile_y)
		tiles.append(tile)
		var resolved: StringName = shape.at(tile, permission)
		classes[String(resolved)] = int(classes.get(String(resolved), 0)) + 1
	return {
		"permissions": permissions, "heights": heights,
		"classes": classes, "tiles": tiles,
	}


func _map_tile(map: Gen2WorldMap, tileset: Gen2WorldTileset, tile_x: int, tile_y: int) -> int:
	@warning_ignore("integer_division")
	var block: int = map.block_at(tile_x / BLOCK_TILES, tile_y / BLOCK_TILES)
	return tileset.tile_index(block, (tile_y & 3) * BLOCK_TILES + (tile_x & 3))


func _build(number: int) -> bool:
	var placements: Dictionary = _placements()
	if not placements.has(number):
		print("tileset %d places nothing" % number)
		return false
	var entry: Dictionary = placements[number]
	var blocks: Array = (entry["blocks"] as Dictionary).keys()
	blocks.sort()
	var source: Gen2WorldMap = null
	var most: int = -1
	for map: Gen2WorldMap in (entry["maps"] as Dictionary):
		if int((entry["maps"] as Dictionary)[map]) > most:
			most = int((entry["maps"] as Dictionary)[map])
			source = map
	var tileset: Gen2WorldTileset = _data.world_tileset(number)
	if tileset == null or source == null:
		return false

	var grid: Dictionary = _grid_map(source, tileset, blocks)
	var map: Gen2WorldMap = grid["map"]
	var places: Dictionary = grid["places"]

	_stage.set_time_of_day(Gen2WorldPalette.TIME_DAY)
	if _atlas.build(_data, map, tileset, Gen2WorldPalette.TIME_DAY):
		_stage.set_texture(_atlas.texture)
		_stage.set_background(Color(0.09, 0.09, 0.11))
	var shape: RefCounted = _tile_shape.new(_profile, number)
	_stage.set_terrain(_mesher.build(_map_source.new(null, map, tileset), shape, _atlas))
	_stage.set_water(_mesher.take_water())
	_stage.set_tufts(_mesher.take_tufts())
	# And the models, or every block built as one shows an empty patch of grass
	# and the sheet asks the reviewer to grade a hole.
	_stage.set_models(_mesher.take_models())

	_paint_2d(map, tileset, places).save_png("%s/ts%d_2d.png" % [_out, number])

	# One orthographic eye over the whole grid, so every slot is at the same
	# scale and a crop is a pure translation. A perspective camera would size
	# each block by where it happened to land on the sheet.
	#
	# The frame is sized from what the tilt PROJECTS, not from the map: a pitched
	# view lays the map's depth down by its sine and stands every structure up by
	# its cosine, so framing the raw extent cuts the last row off the bottom.
	var size: Vector2 = _mesher.size_pixels()
	var pitch: float = deg_to_rad(52.0)
	var framed: float = size.y * sin(pitch) + TALLEST * cos(pitch) + CELL
	# Into the stage's own SubViewport, at whatever size the grid needs. The
	# window is bounded by the display and a sheet is not: drawing through the
	# window clipped the last rows off every tileset with more than a screenful
	# of blocks, silently, because the image still came out looking like a sheet.
	var view := Vector2i(int(size.x * SCALE), int(framed * SCALE))
	_stage.container.size = Vector2(view)
	_stage.viewport.size = view
	_stage.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_stage.camera.size = framed
	var focus := Vector3(size.x * 0.5, TALLEST * 0.5, size.y * 0.5)
	_stage.aim_camera(
		focus + Vector3(0.0, sin(pitch), cos(pitch)) * maxf(size.x, size.y) * 2.0, focus
	)

	var records: Array = []
	var slot: int = 0
	for block: int in places:
		var at: Vector2i = places[block]
		var ground := Vector3(
			at.x * BLOCK_TILES * TILE + CELL, 0.0, at.y * BLOCK_TILES * TILE + CELL
		)
		var verdict: Dictionary = _verdict(map, tileset, shape, at)
		verdict["block"] = block
		verdict["slot"] = slot
		# Projected here rather than through the camera: the viewport has only
		# just been resized and does not carry its new size until it has drawn,
		# so `unproject_position` would answer for the frame before this one. An
		# orthographic eye is an affine map anyway, and this is that map.
		verdict["screen"] = [
			size.x * 0.5 * SCALE + (ground.x - focus.x) * SCALE,
			framed * 0.5 * SCALE - (
				(ground.y - focus.y) * cos(pitch) - (ground.z - focus.z) * sin(pitch)
			) * SCALE,
		]
		records.append(verdict)
		slot += 1

	_pending = {
		"tileset": number,
		"columns": COLUMNS,
		"block_pixels": BLOCK_PIXELS,
		"crop": [CROP.x, CROP.y],
		"crop_ground": [CROP_GROUND.x, CROP_GROUND.y],
		"map": [source.group, source.number],
		"maps_using": (entry["maps"] as Dictionary).size(),
		"filler_block": grid["filler"],
		"blocks": records,
	}
	return true


func _process(_delta: float) -> bool:
	if _pending.is_empty():
		if _queue.is_empty():
			print("done")
			return true
		var number: int = _queue.pop_front()
		if not _build(number):
			return false
		_frames = 0
		return false

	_frames += 1
	if _frames < 6:
		return false
	var number: int = int(_pending["tileset"])
	_stage.viewport.get_texture().get_image().save_png("%s/ts%d_3d.png" % [_out, number])
	var file: FileAccess = FileAccess.open("%s/ts%d.json" % [_out, number], FileAccess.WRITE)
	file.store_string(JSON.stringify(_pending, "  "))
	file.close()
	print("tileset %d: %d blocks" % [number, (_pending["blocks"] as Array).size()])
	_pending = {}
	return false
