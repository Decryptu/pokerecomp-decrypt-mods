extends RefCounted

## The texture the terrain samples: the map's tileset, coloured with the map's
## own palettes at the current time of day.
##
## Geometry is textured from the tileset, not from a rendered copy of the map: a
## map-space canvas covering the biggest route would be megabytes with several
## live at once, where the tileset is ninety-six tiles and 24 KB of the same art
## and palette rows the 2D view draws with.
##
## Animated tiles are the other thing this owns. The 2D path redraws those cells
## over the tile page each frame, which one static mesh has no equivalent of, so
## the texture is animated instead: rewrite the tile's slot here and every
## instance of it across the mesh moves at once, which is what the hardware does.

const TILE: int = 8
## Tiles per atlas row. A tileset is ninety-six tiles, so the atlas is 128x48.
const TILES_PER_ROW: int = 16

## The sky's two ends, and which of the hour's rows each is read from. See
## [method sky_ramp].
##
## Slot 6 is the only background slot holding a blue pair, and it holds one at
## every hour: #7bffff and #298cff by day, #6b63bd and #5a4aa5 at night, black in
## the dark. They must be read from the ROW, before `_LoadMapPals` hands those
## slots to the map group's roof colours, or the sky over a town is whatever that
## town's roofs are painted.
const SKY_SLOT: int = 6
## Morning's own, and why it takes neither of the above: see [method sky_ramp].
const SKY_WATER_SLOT: int = 3
const SKY_WARM_SLOT: int = 4
## How far each end is taken down from the colour the cartridge holds. The
## horizon barely, since the haze fades the far ground into it and both have to
## arrive at one colour; the zenith enough to leave the ramp somewhere to go.
const SKY_HORIZON_DARKEN: float = 0.10
const SKY_ZENITH_DARKEN: float = 0.30
## Morning's horizon is taken toward white rather than down: #ff8408 is the
## colour of a sun and not of the air around one, and at full strength it stops
## reading as sky.
const SKY_MORNING_LIGHTEN: float = 0.40
const SKY_MORNING_ZENITH_DARKEN: float = 0.34

var texture: ImageTexture = null
## Kept beside the texture so an animation frame can repaint the one or two
## tiles it rewrote instead of recolouring the whole sheet.
var _image: Image = null
var _tile_count: int = 0
## The tileset's own pixels, in palette indices, kept for the geometry that is
## cut per pixel rather than textured per tile.
var _source: PackedByteArray = PackedByteArray()
var _background: Color = Color("#f5f1d8")
## tile -> its drawn indices darkest first, worked out once. See `shade_order`.
var _shades: Dictionary = {}
## The sequence this sheet is following, kept so a mesh can ask what a tile is
## drawn as on the frames it is NOT showing. See [method frame_pixel].
var _animation: Gen2WorldAnimation = null
## tile -> `Gen2WorldAnimation.tile_frames`, which is a walk of the whole command
## list and so is asked once per tile and kept. Empty for a still tile.
var _frames: Dictionary = {}
## The hour's sky, horizon first, worked out with the palettes. Empty until a
## build has run, which is what leaves `sky.gd` on its background-only fallback.
var _sky_ramp: PackedColorArray = PackedColorArray()
## The water row's palest and deepest, worked out with the palettes. See
## [method shore_colors].
var _shore_colors: PackedColorArray = PackedColorArray()
## And the row those two came out of: see [method water_colors].
var _water_colors: PackedColorArray = PackedColorArray()


## Rebuilds the whole sheet. Called when the map, the palette or the time of day
## changes, which is the only time every tile's colour can move at once.
##
## Takes the records rather than a world, because a battle staged on the map has
## the map and its tileset by number and no world to read them through.
func build(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int,
	animation: Gen2WorldAnimation = null,
) -> bool:
	# The texture object is reused, and that is not a saving. A palette command
	# sends `refresh_animation` here to repaint the whole sheet, and a fresh
	# ImageTexture leaves every material holding the old one: every tile animation
	# in the view died about twenty-six frames into a map. The object survives, so
	# a holder cannot go stale.
	var kept: ImageTexture = texture
	texture = null
	_image = null
	_tile_count = 0
	_source = PackedByteArray()
	# Kept per tile and re-coloured by the hour, so it cannot outlive a rebuild.
	_shades.clear()
	# The frames are the tileset's own drawings and carry no colour, so they
	# survive an hour change; a different tileset is a different set of them.
	if _animation != animation:
		_frames.clear()
	_animation = animation
	if data == null or map == null or tileset == null:
		return false

	var indices: PackedByteArray = _indices(data, tileset, animation)
	_source = indices
	var palettes: Array = _palettes(data, map, tileset, time_of_day, animation)
	var count: int = tileset.tile_count
	if indices.size() < count * TILE * TILE:
		return false
	if not palettes.is_empty() and (palettes[0] as PackedColorArray).size() >= 1:
		_background = (palettes[0] as PackedColorArray)[0]
	_sky_ramp = _read_sky_ramp(data, map, time_of_day)
	_shore_colors = _read_shore_colors(data, map, time_of_day)

	_tile_count = count
	@warning_ignore("integer_division")
	var rows: int = (count + TILES_PER_ROW - 1) / TILES_PER_ROW
	_image = Image.create(TILES_PER_ROW * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for tile: int in count:
		_paint(indices, palettes, tile)
	if kept != null and kept.get_size() == Vector2(_image.get_size()):
		kept.set_image(_image)
		texture = kept
	else:
		texture = ImageTexture.create_from_image(_image)
	return true


## Repaints only the tiles the last animation frame rewrote. A palette command is
## the exception: it changes every tile drawn with that row, so the caller
## rebuilds instead.
func refresh_animation(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int,
	animation: Gen2WorldAnimation,
) -> bool:
	if _image == null or texture == null or animation == null:
		return false
	if animation.palette_changed():
		return build(data, map, tileset, time_of_day, animation)
	var changed: PackedInt32Array = animation.changed_tiles()
	if changed.is_empty():
		return false
	var indices: PackedByteArray = animation.current_indices()
	var palettes: Array = _palettes(data, map, tileset, time_of_day, animation)
	for tile: int in changed:
		if tile >= 0 and tile < _tile_count:
			_paint(indices, palettes, tile)
			_shades.erase(tile)
	texture.update(_image)
	return true


## The tile's rectangle in normalized texture coordinates, inset by a sliver.
##
## Without the inset the perspective rasteriser lands on a neighbouring tile's
## texel along a shared edge and stitches bright seams across the map. It has to
## stay a sliver: a tile is 8 texels over 8 world pixels exactly, so insetting by
## half a texel would squeeze the art into 7 and drift it off the pixel grid.
const INSET: float = 0.02


func uv(tile: int) -> Rect2:
	if _image == null or tile < 0 or tile >= _tile_count:
		return Rect2()
	var width: float = float(_image.get_width())
	var height: float = float(_image.get_height())
	@warning_ignore("integer_division")
	var origin := Vector2(
		float((tile % TILES_PER_ROW) * TILE), float((tile / TILES_PER_ROW) * TILE)
	)
	return Rect2(
		Vector2((origin.x + INSET) / width, (origin.y + INSET) / height),
		Vector2((TILE - INSET * 2.0) / width, (TILE - INSET * 2.0) / height)
	)


## The uv rectangle of a pixel box inside one tile, for geometry cut finer than a
## tile. Same sliver inset as [method uv] and for the same reason.
func uv_box(tile: int, box: Rect2i) -> Rect2:
	var whole: Rect2 = uv(tile)
	if whole.size == Vector2.ZERO:
		return whole
	var per_pixel: Vector2 = whole.size / float(TILE)
	return Rect2(
		whole.position + Vector2(box.position) * per_pixel,
		Vector2(box.size) * per_pixel
	)


## The palette index of one pixel of one tile, or -1 outside.
##
## The index rather than the colour, because a cutout has to answer whether a
## pixel is the drawing or the ground behind it, which is a question about which
## of the four entries the cartridge chose. Two palettes make the same index two
## colours and it is still the same drawing.
func pixel(tile: int, x: int, y: int) -> int:
	if _source.is_empty() or tile < 0 or tile >= _tile_count:
		return -1
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return -1
	var at: int = y * _tile_count * TILE + tile * TILE + x
	return int(_source[at]) if at < _source.size() else -1


## How many distinct drawings a run of tiles is ever shown as, which is one for
## anything the sequence does not touch.
##
## A billboard cut out of an animated tile is a mask of whichever frame the sheet
## was built on, so a row a later frame draws further out is missing and a row
## only an earlier frame drew stands empty. The union of the frames closes both,
## and the texture, which follows the sequence, trims the rest.
func frame_count(tiles: Array) -> int:
	var most: int = 1
	for tile: Variant in tiles:
		most = maxi(most, tile_frames(int(tile)).size())
	return most


## Every drawing one tile is shown as, each entry its sixty-four indices row by
## row. Empty for a tile no command touches.
func tile_frames(tile: int) -> Array[PackedByteArray]:
	if _frames.has(tile):
		return _frames[tile]
	var frames: Array[PackedByteArray] = []
	if _animation != null:
		frames = _animation.tile_frames(tile)
	_frames[tile] = frames
	return frames


## [method pixel] on one frame of the sequence rather than on the frame the sheet
## is showing. A still tile answers the same index whatever is asked for, and a
## frame past the end of a shorter cycle wraps, so tiles of unequal periods can
## be walked together.
func frame_pixel(tile: int, x: int, y: int, frame: int) -> int:
	var frames: Array[PackedByteArray] = tile_frames(tile)
	if frames.is_empty():
		return pixel(tile, x, y)
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return -1
	return int(frames[frame % frames.size()][y * TILE + x])


## The palette indices a tile is drawn with, darkest first. Which index is which
## cannot be assumed: the entries are in no brightness order, and a tile's palette
## is chosen per tile and re-coloured by the hour.
##
## It is for the one drawing a border flood cannot cut. A tree canopy is a ball of
## the same two greens the grass under it is dithered from, so no set of "ground"
## indices separates them; the drawing's own outline does, and an outline is its
## darkest shade. A dense thicket has no drawn ring, and there the two darkest
## together are the boundary. See `mesher.gd:_structure_mask`.
func shade_order(tile: int) -> PackedInt32Array:
	if _shades.has(tile):
		return _shades[tile]
	var found: Array = []
	for index: int in 4:
		var color: Color = color_of(tile, index)
		if color.a <= 0.0:
			continue
		found.append([
			color.r * 0.299 + color.g * 0.587 + color.b * 0.114, index
		])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var order := PackedInt32Array()
	for entry: Array in found:
		order.append(int(entry[1]))
	_shades[tile] = order
	return order


## Whether [param index] is among the [param count] darkest shades this tile is
## drawn with.
func is_dark(tile: int, index: int, count: int) -> bool:
	var order: PackedInt32Array = shade_order(tile)
	for rank: int in mini(count, order.size()):
		if order[rank] == index:
			return true
	return false


## The painted colour at one pixel of one tile, as the sheet holds it now.
##
## `color_of` answers for an index and has to hunt the tile for one wearing it;
## this is the pixel itself, which is what cutting a drawing out of the sheet
## wants. Follows the animation, since it reads the live sheet.
func texel(tile: int, x: int, y: int) -> Color:
	if _image == null or tile < 0 or tile >= _tile_count:
		return Color(0.0, 0.0, 0.0, 0.0)
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return Color(0.0, 0.0, 0.0, 0.0)
	@warning_ignore("integer_division")
	return _image.get_pixel(
		(tile % TILES_PER_ROW) * TILE + x, (tile / TILES_PER_ROW) * TILE + y
	)


## The colour one index paints in one tile, read off the sheet the tile was
## painted onto rather than kept a second time.
##
## Public because an authored model is coloured from the cartridge even though its
## geometry is not: see `model.gd`.
func color_of(tile: int, index: int) -> Color:
	if _image == null or _source.is_empty() or tile < 0 or tile >= _tile_count:
		return Color(0.0, 0.0, 0.0, 0.0)
	for y: int in TILE:
		for x: int in TILE:
			if pixel(tile, x, y) != index:
				continue
			@warning_ignore("integer_division")
			return _image.get_pixel(
				(tile % TILES_PER_ROW) * TILE + x, (tile / TILES_PER_ROW) * TILE + y
			)
	return Color(0.0, 0.0, 0.0, 0.0)


func background() -> Color:
	return _background


## The sky over this map at this hour, as the ramp's horizon and zenith.
##
## The cartridge has no sky palette. Taking the background colour down twice is
## what this view drew a sky out of at first, and it reads grey-green, because the
## background is the hardware's white and Generation II's white is #deffde by day
## and #e6ff84 in the morning.
##
## So both ends come out of the hour's own rows. [constant SKY_SLOT] is the blue
## pair and it differs at every hour, so the sky follows the clock without a table
## of hours here.
##
## Morning is the exception and has to be: its blue pair is byte for byte day's,
## so reading it would leave the two hours sharing one sky. Its horizon is
## [constant SKY_WARM_SLOT]'s sunrise colour and its deep end
## [constant SKY_WATER_SLOT], the blue the water is drawn with at that hour.
func sky_ramp() -> PackedColorArray:
	return _sky_ramp


## The two ends of the water's own row: its palest colour and its deepest, which
## is what `world/water.gd` shades a shallow and a deep with. The row is the same
## one the water tiles are drawn from, so a lake goes pale and deep in its own
## colours rather than in a tint. Empty until a build has run.
func shore_colors() -> PackedColorArray:
	return _shore_colors


## The water row whole, which `world/far_field.gd` matches a texel against: out
## there the ground is a drawing rather than a surface, so the only way to know a
## pixel is water is that the cartridge painted it one of these.
func water_colors() -> PackedColorArray:
	return _water_colors


func _read_shore_colors(
	data: GameData, map: Gen2WorldMap, time_of_day: int
) -> PackedColorArray:
	var slots: Array = Gen2WorldPalette.palette_slots(map.environment, time_of_day)
	if slots.size() <= SKY_WATER_SLOT:
		return PackedColorArray()
	var row: PackedColorArray = data.world_palette(int(slots[SKY_WATER_SLOT]))
	if row.size() < 3:
		return PackedColorArray()
	_water_colors = row
	return PackedColorArray([row[0], row[2]])


func _read_sky_ramp(
	data: GameData, map: Gen2WorldMap, time_of_day: int
) -> PackedColorArray:
	var slots: Array = Gen2WorldPalette.palette_slots(map.environment, time_of_day)
	if slots.size() <= SKY_SLOT:
		return PackedColorArray()
	if time_of_day == Gen2WorldPalette.TIME_MORNING:
		var warm: PackedColorArray = data.world_palette(int(slots[SKY_WARM_SLOT]))
		var water: PackedColorArray = data.world_palette(int(slots[SKY_WATER_SLOT]))
		if warm.size() >= 3 and water.size() >= 3:
			return PackedColorArray([
				warm[2].lightened(SKY_MORNING_LIGHTEN),
				water[2].darkened(SKY_MORNING_ZENITH_DARKEN),
			])
	var pair: PackedColorArray = data.world_palette(int(slots[SKY_SLOT]))
	if pair.size() < 3:
		return PackedColorArray()
	return PackedColorArray([
		pair[1].darkened(SKY_HORIZON_DARKEN), pair[2].darkened(SKY_ZENITH_DARKEN),
	])


## What is behind a wall indoors: the colour of the place itself, taken down.
##
## Out of doors the void past the map is sky. Inside there is none, and the same
## colour put a bright horizon above the rock in every cave. Nothing in the
## cartridge names "the colour of stone", so this takes the mean of every texel of
## the tileset, which is the colour of the place by construction. Darkened,
## because it stands for unlit rock behind the wall.
func void_color() -> Color:
	if _image == null:
		return _background.darkened(0.7)
	var total := Vector3.ZERO
	var counted: int = 0
	# Every fourth texel: a tileset is a few thousand pixels of the same handful
	# of palette entries and the mean does not move.
	for y: int in range(0, _image.get_height(), 4):
		for x: int in range(0, _image.get_width(), 4):
			var color: Color = _image.get_pixel(x, y)
			total += Vector3(color.r, color.g, color.b)
			counted += 1
	if counted == 0:
		return _background.darkened(0.7)
	total /= float(counted)
	return Color(total.x, total.y, total.z).darkened(0.45)


func _indices(
	data: GameData, tileset: Gen2WorldTileset, animation: Gen2WorldAnimation
) -> PackedByteArray:
	if animation != null and not animation.current_indices().is_empty():
		return animation.current_indices()
	return data.world_tileset_indices(tileset.number)


func _palettes(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int,
	animation: Gen2WorldAnimation,
) -> Array:
	return Gen2WorldPalette.tile_palettes(
		data,
		map,
		tileset,
		time_of_day,
		animation.water_palette_color() if animation != null else -1,
		animation.cave_palette_color() if animation != null else -1,
	)


## The source strip is one row of tiles, so a tile's pixels are contiguous in x
## and the destination is the same eight columns moved onto the atlas grid.
## Index 0 is a colour here rather than a hole: this is the background layer, and
## the cartridge's transparent index belongs to sprites.
func _paint(indices: PackedByteArray, palettes: Array, tile: int) -> void:
	var palette: PackedColorArray = palettes[tile] if tile < palettes.size() else PackedColorArray()
	var stride: int = _tile_count * TILE
	var source: int = tile * TILE
	@warning_ignore("integer_division")
	var target := Vector2i((tile % TILES_PER_ROW) * TILE, (tile / TILES_PER_ROW) * TILE)
	for y: int in TILE:
		var row: int = y * stride + source
		for x: int in TILE:
			var color_index: int = int(indices[row + x])
			_image.set_pixel(
				target.x + x, target.y + y,
				palette[color_index] if color_index < palette.size() else _background
			)
