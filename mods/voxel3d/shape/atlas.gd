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


func background() -> Color:
	return _background


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
