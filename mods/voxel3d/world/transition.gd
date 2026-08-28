extends RefCounted

## `DoBattleTransition`, drawn over the diorama.

const COLUMNS: int = Gen2BattleTransition.COLUMNS
const ROWS: int = Gen2BattleTransition.ROWS
const TILE: int = Gen2Tiles.TILE_WIDTH

const CLOSED := Color(0.0, 0.0, 0.0, 1.0)

var layer: TextureRect = null

var _cells := PackedByteArray()
var _drawn := PackedByteArray()
var _tiles := PackedByteArray()
var _palette := PackedColorArray()
var _image: Image = null
var _texture: ImageTexture = null


func _init() -> void:
	layer = TextureRect.new()
	layer.name = "Transition"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.visible = false


func set_frame(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray
) -> void:
	if tiles != _tiles or palette != _palette:
		_tiles = tiles
		_palette = palette
		_drawn = PackedByteArray()
	_cells = cells
	_repaint()


func clear() -> void:
	_cells = PackedByteArray()
	_drawn = PackedByteArray()
	_tiles = PackedByteArray()
	_palette = PackedColorArray()
	layer.visible = false


func place(rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	layer.position = Vector2(rect.position)
	layer.size = Vector2(rect.size)


func _repaint() -> void:
	if _cells.size() < COLUMNS * ROWS:
		layer.visible = false
		return
	var fresh: bool = _image == null or _drawn.size() != _cells.size()
	if _image == null:
		_image = Image.create(
			COLUMNS * TILE, ROWS * TILE, false, Image.FORMAT_RGBA8
		)
	var moved: bool = fresh
	for at: int in COLUMNS * ROWS:
		var cell: int = int(_cells[at])
		if not fresh and int(_drawn[at]) == cell:
			continue
		moved = true
		@warning_ignore("integer_division")
		_paint(at % COLUMNS, at / COLUMNS, cell)
	if moved:
		_drawn = _cells.duplicate()
		if _texture == null:
			_texture = ImageTexture.create_from_image(_image)
			layer.texture = _texture
		else:
			_texture.update(_image)
	layer.visible = true


func _paint(column: int, row: int, cell: int) -> void:
	var box := Rect2i(column * TILE, row * TILE, TILE, TILE)
	if cell == Gen2BattleTransition.CELL_NONE:
		_image.fill_rect(box, Color(0.0, 0.0, 0.0, 0.0))
		return
	if cell != Gen2BattleTransition.CELL_SQUARE or _tiles.size() < TILE * TILE:
		_image.fill_rect(box, _palette[3] if _palette.size() > 3 else CLOSED)
		return
	for y: int in TILE:
		for x: int in TILE:
			var index: int = int(_tiles[y * TILE + x])
			_image.set_pixel(box.position.x + x, box.position.y + y,
				_palette[index] if index < _palette.size() else CLOSED)
