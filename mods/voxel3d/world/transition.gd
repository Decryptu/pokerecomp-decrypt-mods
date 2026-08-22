extends RefCounted

## `DoBattleTransition`, drawn over the diorama.
##
## The one screen the cartridge draws that has no world in it at all: twenty by
## eighteen cells, blacked out a few at a time in one of the game's own patterns,
## with the trainer's Poke Ball stamped in graphics tiles over the top. It runs
## on the frames between an encounter firing and the fight opening, and until now
## this view drew none of it, which is the host's own allowance for a renderer
## that does not take the seam and is still an encounter cutting straight from
## the map to the battle.
##
## IT IS HARDWARE PIXELS AND STAYS THERE. Everything about the pattern is
## authored in the cartridge's own cells, so this is a 160x144 picture laid over
## the surface at the rectangle the host says the Game Boy screen occupies, at
## nearest filtering, exactly as the panels and the text box are. The surround
## outside that rectangle is closed by the pass over the frame, which the same
## `set_interface_masked` raises: see `world/frame.gd`.
##
## REPAINTED PER CELL THAT MOVED. A transition is two hundred frames and every
## one is a different picture, and repainting 23040 pixels a frame in GDScript is
## most of a frame on its own. A step writes a handful of cells, so the image is
## kept and only the cells whose value changed are filled again.

const COLUMNS: int = Gen2BattleTransition.COLUMNS
const ROWS: int = Gen2BattleTransition.ROWS
const TILE: int = Gen2Tiles.TILE_WIDTH

## What a blacked-out cell is drawn in WHERE THERE IS NO FLOOD. The 2D view takes
## the darkest colour of whichever palette the map tile under the cell was drawn
## with, which on this view is a question with no answer: there is no tile page
## under it, and the thing it is closing over is a lit 3D picture. Black is what
## the hardware left there, what the surround is closed with, and what a Game Boy
## palette's fourth entry is on every one of the maps this runs over.
##
## `StartTrainerBattle_LoadPokeBallGraphics` IS a flood, and there the darkest
## entry of the palette it floods with is the answer, exactly as in the 2D view.
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
	# The picture is the cartridge's own 8x8 cells blown up whole, which is the
	# rule every other hardware-pixel surface in this mod is drawn under.
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
		# A cell already drawn in the old colours has to be drawn again in the
		# new ones, which is what dropping the record of what was painted says.
		_drawn = PackedByteArray()
	_cells = cells
	_repaint()


## Nothing on screen, and nothing kept: a transition is over and the next one
## starts from a blank field.
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
