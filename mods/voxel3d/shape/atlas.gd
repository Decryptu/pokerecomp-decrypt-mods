extends RefCounted

## The texture the terrain samples: the map's tileset, coloured with the map's
## own palettes at the current time of day.
##
## Geometry is textured from the TILESET, not from a rendered copy of the map. A
## map-space canvas covering the biggest route would be megabytes with several
## live at once; the tileset is ninety-six tiles and costs 24 KB, and costs
## nothing in fidelity because it is the same art and the same palette rows the
## 2D view draws with.
##
## ANIMATED TILES are the other thing this owns. The 2D path animates water and
## flowers by redrawing those cells over the tile page each frame, which a single
## static mesh has no equivalent of. So animate the texture instead: rewrite the
## animated tile's slot here and every instance of it across the whole mesh moves
## at once. Which is what the hardware does in the first place; the overdraw is
## the port's answer, not the cartridge's.

const TILE: int = 8
## Tiles per atlas row. A tileset is ninety-six tiles, so the atlas is 128x48.
const TILES_PER_ROW: int = 16

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
	texture = null
	_image = null
	_tile_count = 0
	_source = PackedByteArray()
	# Kept per tile and re-coloured by the hour, so it cannot outlive a rebuild.
	_shades.clear()
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

	_tile_count = count
	@warning_ignore("integer_division")
	var rows: int = (count + TILES_PER_ROW - 1) / TILES_PER_ROW
	_image = Image.create(TILES_PER_ROW * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for tile: int in count:
		_paint(indices, palettes, tile)
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
## Without the inset the perspective rasteriser lands on a NEIGHBOURING tile's
## texel along a shared edge and stitches bright seams across the whole map. It
## has to stay a sliver: a tile is 8 texels of art over 8 world pixels, one texel
## per pixel exactly, and insetting by half a texel would squeeze that art into a
## 7-texel range while the quad still covers 8 pixels, drifting the art off the
## pixel grid.
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
	var texel: Vector2 = whole.size / float(TILE)
	return Rect2(whole.position + Vector2(box.position) * texel, Vector2(box.size) * texel)


## The palette index of one pixel of one tile, or -1 outside.
##
## The INDEX rather than the colour, because what a cutout has to answer is
## whether a pixel is part of the drawing or part of the ground behind it, and
## that is a question about which of the four entries the cartridge chose. Two
## palettes make the same index two different colours and it is still the same
## drawing.
func pixel(tile: int, x: int, y: int) -> int:
	if _source.is_empty() or tile < 0 or tile >= _tile_count:
		return -1
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return -1
	var at: int = y * _tile_count * TILE + tile * TILE + x
	return int(_source[at]) if at < _source.size() else -1


## The palette indices a tile is drawn with, DARKEST FIRST.
##
## Which index is which cannot be assumed: an index means one of four entries,
## the entries are in no brightness order, and a tile's palette is chosen per
## tile and re-coloured by the hour.
##
## What it is for is the one drawing a border flood cannot cut. A tree canopy is
## a ball of the SAME two greens the grass under it is dithered from, so no set
## of "ground" indices separates them; what does separate them is the drawing's
## own outline, and an outline is its darkest shade. A dense thicket has no drawn
## ring at all, and there the two darkest together are the boundary. See
## `mesher.gd:_structure_mask`.
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


## The colour one index paints in one tile, read off the sheet the tile was
## painted onto rather than kept a second time.
##
## Public because an authored MODEL is coloured from the cartridge even though
## its geometry is not: see `model.gd`.
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


## What is behind a wall INDOORS: the colour of the place itself, taken down.
##
## Out of doors the void past the map is sky and `background()` is what the 2D
## view fills its margins with. Inside there is no sky, and using the same colour
## put a bright horizon above the rock in every cave. Nothing in the cartridge
## names "the colour of stone", so this takes the mean of every texel of the
## tileset, which is the colour of the place by construction: brown for a cave,
## whatever a room is made of for a room. Darkened, because it stands for
## unlit rock BEHIND the wall rather than for the wall's own lit face.
func void_color() -> Color:
	if _image == null:
		return _background.darkened(0.7)
	var total := Vector3.ZERO
	var counted: int = 0
	# Every fourth texel in each direction: a tileset is a few thousand pixels of
	# the same handful of palette entries and the mean does not move.
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
