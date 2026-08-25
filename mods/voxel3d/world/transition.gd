extends RefCounted

## `DoBattleTransition`, drawn over the diorama.
##
## The one screen the cartridge draws with no world in it: twenty by eighteen
## cells blacked out a few at a time in one of the game's own patterns, with the
## trainer's Poke Ball stamped over the top. It runs between an encounter firing
## and the fight opening.
##
## It is hardware pixels and stays there: a 160x144 picture laid over the surface
## at the rectangle the host says the Game Boy screen occupies, at nearest
## filtering, as the panels and text box are. The surround outside it is closed by
## `world/frame.gd`, raised by the same `set_interface_masked`.
##
## Repainted per cell that moved. A transition is two hundred different pictures,
## and repainting 23040 pixels a frame in GDScript is most of a frame.

const COLUMNS: int = Gen2BattleTransition.COLUMNS
const ROWS: int = Gen2BattleTransition.ROWS
const TILE: int = Gen2Tiles.TILE_WIDTH

## What a blacked-out cell is drawn in where there is no flood. The 2D view takes
## the darkest colour of the palette the map tile under the cell was drawn with,
## which has no answer here: there is no tile page under it. Black is what the
## hardware left there and what the surround is closed with.
##
## `StartTrainerBattle_LoadPokeBallGraphics` IS a flood, and there the darkest
## entry of the palette it floods with is the answer, as in the 2D view.
const CLOSED := Color(0.0, 0.0, 0.0, 1.0)

var layer: TextureRect = null

var _cells := PackedByteArray()
## The cells the kept image was painted from, so only what moved is filled again.
var _drawn := PackedByteArray()
var _tiles := PackedByteArray()
var _palette := PackedColorArray()
var _image: Image = null
var _texture: ImageTexture = null


func _init() -> void:
	layer = TextureRect.new()
	layer.name = "Transition"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The cartridge's own 8x8 cells blown up whole, as every hardware-pixel
	# surface here is drawn.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.visible = false


## One frame of the transition. [param tiles] is the one 8x8 graphics tile the
## ball is stamped from and [param palette] the colours it is drawn in, both
## empty until `StartTrainerBattle_LoadPokeBallGraphics` has run.
func set_frame(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray
) -> void:
	if tiles != _tiles or palette != _palette:
		_tiles = tiles
		_palette = palette
		# Cells drawn in the old colours have to be drawn again, which is what
		# dropping the record says.
		_drawn = PackedByteArray()
	_cells = cells
	_repaint()


## Nothing on screen and nothing kept: the next transition starts blank.
func clear() -> void:
	_cells = PackedByteArray()
	_drawn = PackedByteArray()
	_tiles = PackedByteArray()
	_palette = PackedColorArray()
	layer.visible = false


## Where the hardware's own screen sits on this surface, which is where the
## twenty by eighteen cells go. See `Gen2ModHost.RENDERER_SCREEN_RECT_METHOD`.
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
		# The world is still there under an open cell, and this layer is over it.
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
