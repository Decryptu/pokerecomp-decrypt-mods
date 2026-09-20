extends Control

## `DoBattleTransition`, drawn over the diorama in the cartridge's own 20x18
## cells. A cell is the map showing through, one of the two loaded tiles, or
## on Generation 1 a cell copied from elsewhere on the screen, which is how the
## shrink and the split squeeze the picture: that copy is cut from the finished
## picture the stage drew, since a screen cell of a diorama is what it shows.

const COLUMNS: int = Gen2BattleTransition.COLUMNS
const ROWS: int = Gen2BattleTransition.ROWS
const TILE: int = PokeTiles.TILE_WIDTH

const CLOSED := Color(0.0, 0.0, 0.0, 1.0)

var _cells := PackedByteArray()
var _sources := PackedInt32Array()
var _tiles := PackedByteArray()
var _palette := PackedColorArray()
var _square: ImageTexture = null
var _picture: Texture2D = null
var _picture_scale := Vector2.ONE


func _init() -> void:
	name = "Transition"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false


## [param picture] is the stage's finished frame and [param drawn] the rectangle
## it is shown in, so a screen cell can be found on it whatever the render scale.
func set_frame(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray,
	sources: PackedInt32Array, picture: Texture2D, drawn: Vector2
) -> void:
	if tiles != _tiles or palette != _palette:
		_tiles = tiles
		_palette = palette
		_square = _square_texture()
	_cells = cells
	_sources = sources
	_picture = picture
	if picture != null and drawn.x > 0.0 and drawn.y > 0.0:
		_picture_scale = picture.get_size() / drawn
	visible = _cells.size() >= COLUMNS * ROWS
	queue_redraw()


func clear() -> void:
	_cells = PackedByteArray()
	_sources = PackedInt32Array()
	_tiles = PackedByteArray()
	_palette = PackedColorArray()
	_square = null
	_picture = null
	visible = false


func place(rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	position = Vector2(rect.position)
	size = Vector2(rect.size)


func _draw() -> void:
	if _cells.size() < COLUMNS * ROWS:
		return
	var cell_size: Vector2 = size / Vector2(COLUMNS, ROWS)
	for at: int in COLUMNS * ROWS:
		@warning_ignore("integer_division")
		var box := Rect2(Vector2(at % COLUMNS, at / COLUMNS) * cell_size, cell_size)
		var cell: int = int(_cells[at])
		if cell == Gen2BattleTransition.CELL_NONE:
			_draw_copied(at, box)
		elif cell == Gen2BattleTransition.CELL_SQUARE and _square != null:
			draw_texture_rect(_square, box, false)
		else:
			draw_rect(box, _palette[3] if _palette.size() > 3 else CLOSED)


## The map another screen cell was showing, painted over this one.
func _draw_copied(at: int, box: Rect2) -> void:
	if _picture == null or at >= _sources.size():
		return
	var source: int = int(_sources[at])
	if source < 0 or source == at or source >= COLUMNS * ROWS:
		return
	@warning_ignore("integer_division")
	var from := Rect2(
		(position + Vector2(source % COLUMNS, source / COLUMNS) * box.size) * _picture_scale,
		box.size * _picture_scale
	)
	draw_texture_rect_region(_picture, box, from)


func _square_texture() -> ImageTexture:
	if _tiles.size() < TILE * TILE:
		return null
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y: int in TILE:
		for x: int in TILE:
			var index: int = int(_tiles[y * TILE + x])
			image.set_pixel(x, y, _palette[index] if index < _palette.size() else CLOSED)
	return ImageTexture.create_from_image(image)
