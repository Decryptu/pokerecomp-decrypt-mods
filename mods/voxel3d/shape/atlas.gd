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
var _background: Color = Color("#f5f1d8")


## Rebuilds the whole sheet. Called when the map, the palette or the time of day
## changes, which is the only time every tile's colour can move at once.
func build(world: Gen2WorldAPI, time_of_day: int, animation: Gen2WorldAnimation) -> bool:
	texture = null
	_image = null
	_tile_count = 0
	if world == null or world.data == null or world.current_tileset == null:
		return false

	var indices: PackedByteArray = _indices(world, animation)
	var palettes: Array = _palettes(world, time_of_day, animation)
	var count: int = world.current_tileset.tile_count
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
	world: Gen2WorldAPI, time_of_day: int, animation: Gen2WorldAnimation
) -> bool:
	if _image == null or texture == null or animation == null:
		return false
	if animation.palette_changed():
		return build(world, time_of_day, animation)
	var changed: PackedInt32Array = animation.changed_tiles()
	if changed.is_empty():
		return false
	var indices: PackedByteArray = animation.current_indices()
	var palettes: Array = _palettes(world, time_of_day, animation)
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


func background() -> Color:
	return _background


func _indices(world: Gen2WorldAPI, animation: Gen2WorldAnimation) -> PackedByteArray:
	if animation != null and not animation.current_indices().is_empty():
		return animation.current_indices()
	return world.data.world_tileset_indices(world.current_tileset.number)


func _palettes(
	world: Gen2WorldAPI, time_of_day: int, animation: Gen2WorldAnimation
) -> Array:
	return Gen2WorldPalette.tile_palettes(
		world.data,
		world.current_map,
		world.current_tileset,
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
