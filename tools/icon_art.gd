extends SceneTree

## Paints ONE mod icon out of cartridge art, layer by layer.
##
## A mod's icon has to look like it came off the cartridge, so it is built from
## the cartridge's own pixels: a text box border around art the game already
## draws somewhere. Nothing here is a picture of a mod; it is the game's frame,
## the game's font and the game's sprites, arranged.
##
##   Godot --headless --path <pokerecomp> -s tools/icon_art.gd -- <cache> \
##       <out.png> <layer> [layer ...] [--tiles N] [--scale N]
##
## Layers paint in the order given, each centred unless it carries an `@x,y`
## offset in pixels from the icon's top left:
##
##   frame:<style>            a whole text box border, style counted from zero
##   text:<string>            the main font, one tile a character
##   effect:<name>[:pal]      an emote sheet: heart, question, shock, ...
##   species:<number>         a party menu icon, first frame
##   sprite:<number>[:pal]    an overworld sprite's first frame, 16x16
##   tiles:<sheet>:<a,b,c>[:cols]   tiles out of a 1bpp strip by index
##   world:<group>:<number>:<a,b,c>[:cols]  map tiles, in that map's own colours
##   art:<name>               `tools/icon_art/<name>.txt`, drawn by hand
##
## A hand drawing is four shades and a hole: `.` is transparent and `0` to `3`
## are the text palette's own colours, lightest first. It is there for what the
## cartridge has no picture of, and nothing else.
##
## Sprite layers keep colour 0 transparent, the way the hardware draws an
## object; the frame, the font and hand art treat it as the box's white.

const TILE: int = 8

var _data: GameData = null
var _font: Gen2Font = null
var _image: Image = null
var _bg: PackedColorArray = PackedColorArray()


func _initialize() -> void:
	var args: Array = Array(OS.get_cmdline_user_args())
	if args.size() < 3:
		print("usage: <cache> <out.png> <layer> [layer ...] [--tiles N] [--scale N]")
		quit(1)
		return

	var tiles: int = 4
	var scale: int = 6
	var layers: Array = []
	var i: int = 2
	while i < args.size():
		var arg: String = String(args[i])
		if arg == "--tiles" and i + 1 < args.size():
			tiles = int(args[i + 1])
			i += 2
		elif arg == "--scale" and i + 1 < args.size():
			scale = int(args[i + 1])
			i += 2
		else:
			layers.append(arg)
			i += 1

	_data = GameData.open_directory(String(args[0]))
	if _data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	_font = Gen2Font.from_data(_data)
	_bg = _data.text_bg_palette()
	if _bg.size() < 4:
		_bg = PackedColorArray([Color.WHITE, Color(0.6, 0.6, 0.6), Color(0.3, 0.3, 0.3), Color.BLACK])

	var side: int = tiles * TILE
	_image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))

	for layer: String in layers:
		if not _paint_layer(layer, side):
			print("bad layer ", layer)
			quit(1)
			return

	if scale > 1:
		_image.resize(side * scale, side * scale, Image.INTERPOLATE_NEAREST)
	var out: String = String(args[1])
	if Gen2ToolPath.refuses(out):
		quit(2)
		return
	if _image.save_png(out) != OK:
		print("cannot write ", out)
		quit(1)
		return
	print(out, "  ", side, "x", side, " x", scale)
	quit()


## Splits `<layer>@x,y` into the layer and an offset, or a null offset when the
## layer is centred.
func _split_offset(layer: String) -> Array:
	var at: int = layer.rfind("@")
	if at < 0:
		return [layer, null]
	var parts: PackedStringArray = layer.substr(at + 1).split(",")
	if parts.size() != 2:
		return [layer, null]
	return [layer.substr(0, at), Vector2i(int(parts[0]), int(parts[1]))]


func _paint_layer(layer: String, side: int) -> bool:
	var split: Array = _split_offset(layer)
	var spec: PackedStringArray = String(split[0]).split(":")
	var offset: Variant = split[1]
	var kind: String = spec[0]

	match kind:
		"frame":
			if _font == null or spec.size() < 2:
				return false
			var buffer := PackedByteArray()
			buffer.resize(side * side)
			@warning_ignore("integer_division")
			var across: int = side / TILE
			_font.draw_box(int(spec[1]), buffer, side, 0, 0, across, across)
			_blit_indices(buffer, side, side, Vector2i.ZERO, _bg, false)
			return true
		"text":
			if _font == null or spec.size() < 2:
				return false
			var text: String = String(split[0]).substr(5)
			var width: int = text.length() * TILE
			var buffer := PackedByteArray()
			buffer.resize(width * TILE)
			_font.draw_text(text, buffer, width, 0, 0)
			_blit_indices(buffer, width, TILE, _place(offset, side, width, TILE), _bg, true)
			return true
		"effect":
			if spec.size() < 2:
				return false
			var sheet: Dictionary = _data.overworld_effect(spec[1])
			if sheet.is_empty():
				return false
			var pal: int = int(spec[2]) if spec.size() > 2 else 0
			var colors: PackedColorArray = sheet.get("colors", PackedColorArray())
			if colors.is_empty():
				colors = _data.overworld_sprite_palette(pal, Gen2WorldPalette.TIME_DAY)
			return _paint_strip(
				sheet["indices"], int(sheet["tiles"]), colors, offset, side,
				String(spec[3]) if spec.size() > 3 else "row"
			)
		"species":
			if spec.size() < 2:
				return false
			var indices: PackedByteArray = _data.species_icon_indices(int(spec[1]))
			if indices.is_empty():
				return false
			return _paint_strip(
				indices, 4, _data.party_menu_icon_palette(0), offset, side,
				String(spec[2]) if spec.size() > 2 else "row"
			)
		"sprite":
			if spec.size() < 2:
				return false
			var sprite: Gen2WorldSprite = _data.overworld_sprite(int(spec[1]))
			if sprite == null:
				return false
			var pal: int = int(spec[2]) if spec.size() > 2 else sprite.default_palette
			return _paint_strip(
				_data.overworld_sprite_indices(int(spec[1])), 4,
				_data.overworld_sprite_palette(pal, Gen2WorldPalette.TIME_DAY),
				offset, side, String(spec[3]) if spec.size() > 3 else "row"
			)
		"tiles":
			if spec.size() < 3:
				return false
			var sheet: Dictionary = _data.tile_sheet(spec[1])
			if sheet.is_empty():
				return false
			var wanted: PackedStringArray = spec[2].split(",")
			var cols: int = int(spec[3]) if spec.size() > 3 else wanted.size()
			return _paint_picked(
				_data.tile_indices(spec[1]), int(sheet["width"]), wanted, cols,
				_bg, false, offset, side
			)
		"world":
			if spec.size() < 4:
				return false
			return _paint_world(spec, offset, side)
		"art":
			if spec.size() < 2:
				return false
			return _paint_art(spec[1], offset, side)
	return false


## Where a drawing of this size lands: its own offset, or the middle.
func _place(offset: Variant, side: int, width: int, height: int) -> Vector2i:
	if offset != null:
		return offset
	@warning_ignore("integer_division")
	return Vector2i(int((side - width) / 2), int((side - height) / 2))


## A 2x2 sprite out of a four-tile strip, in the hardware's own column order:
## an object is two 8x16 halves, so the left column is tiles 0 and 1.
func _paint_strip(
	indices: PackedByteArray, tiles: int, palette: PackedColorArray,
	offset: Variant, side: int, order: String = "row"
) -> bool:
	# A strip is as many tiles wide as it holds, and a sheet often holds more
	# than one frame: the row stride is the whole strip, not the four drawn.
	@warning_ignore("integer_division")
	var held: int = int(indices.size() / (TILE * TILE))
	if held < 4:
		return false
	var at: Vector2i = _place(offset, side, 16, 16)
	var stride: int = maxi(tiles, held) * TILE
	for tile: int in 4:
		@warning_ignore("integer_division")
		var corner := Vector2i(int(tile / 2) * TILE, (tile % 2) * TILE) if order == "col" \
			else Vector2i((tile % 2) * TILE, int(tile / 2) * TILE)
		for y: int in TILE:
			for x: int in TILE:
				var index: int = int(indices[y * stride + tile * TILE + x])
				if index == 0:
					continue
				_put(at + corner + Vector2i(x, y), palette, index)
	return true


func _paint_picked(
	indices: PackedByteArray, sheet_tiles: int, wanted: PackedStringArray, cols: int,
	palette: PackedColorArray, transparent: bool, offset: Variant, side: int
) -> bool:
	if indices.is_empty() or cols <= 0:
		return false
	var rows: int = int(ceil(float(wanted.size()) / float(cols)))
	var at: Vector2i = _place(offset, side, cols * TILE, rows * TILE)
	var stride: int = sheet_tiles * TILE
	for slot: int in wanted.size():
		var tile: int = int(wanted[slot])
		@warning_ignore("integer_division")
		var corner := Vector2i((slot % cols) * TILE, int(slot / cols) * TILE)
		for y: int in TILE:
			for x: int in TILE:
				var source: int = y * stride + tile * TILE + x
				if source >= indices.size():
					continue
				var index: int = int(indices[source])
				if transparent and index == 0:
					continue
				_put(at + corner + Vector2i(x, y), palette, index)
	return true


## Tiles of a map, wearing the palettes that map paints them with by day.
func _paint_world(spec: PackedStringArray, offset: Variant, side: int) -> bool:
	var map: Gen2WorldMap = _data.world_map(int(spec[1]), int(spec[2]))
	if map == null:
		return false
	var tileset: Gen2WorldTileset = _data.world_tileset(map.tileset)
	if tileset == null:
		return false
	var indices: PackedByteArray = _data.world_tileset_indices(map.tileset)
	var palettes: Array = Gen2WorldPalette.tile_palettes(
		_data, map, tileset, Gen2WorldPalette.TIME_DAY, -1, -1
	)
	var wanted: PackedStringArray = spec[3].split(",")
	var cols: int = int(spec[4]) if spec.size() > 4 else wanted.size()
	var rows: int = int(ceil(float(wanted.size()) / float(cols)))
	var at: Vector2i = _place(offset, side, cols * TILE, rows * TILE)
	var stride: int = tileset.tile_count * TILE
	for slot: int in wanted.size():
		var tile: int = int(wanted[slot])
		var palette: PackedColorArray = palettes[tile] if tile < palettes.size() \
			else PackedColorArray()
		@warning_ignore("integer_division")
		var corner := Vector2i((slot % cols) * TILE, int(slot / cols) * TILE)
		for y: int in TILE:
			for x: int in TILE:
				var source: int = y * stride + tile * TILE + x
				if source >= indices.size():
					continue
				_put(at + corner + Vector2i(x, y), palette, int(indices[source]))
	return true


func _paint_art(name: String, offset: Variant, side: int) -> bool:
	# The host project is what `--path` points at, so hand art is found through
	# the caller's own directory instead: `ICON_ART_DIR`, or `tools/icon_art`
	# under whatever the tool was run from.
	var here: String = OS.get_environment("ICON_ART_DIR")
	if here == "":
		here = "%s/tools/icon_art" % OS.get_environment("PWD")
	var text: String = FileAccess.get_file_as_string("%s/%s.txt" % [here, name])
	if text == "":
		print("no hand art at ", here, "/", name, ".txt")
		return false
	var lines: PackedStringArray = []
	for line: String in text.split("\n"):
		if line.strip_edges() != "" and not line.begins_with("#"):
			lines.append(line)
	if lines.is_empty():
		return false
	var width: int = 0
	for line: String in lines:
		width = maxi(width, line.length())
	var at: Vector2i = _place(offset, side, width, lines.size())
	for y: int in lines.size():
		for x: int in lines[y].length():
			var glyph: String = lines[y][x]
			if glyph == "." or glyph == " ":
				continue
			_put(at + Vector2i(x, y), _bg, int(glyph))
	return true


## Copies an index buffer straight over, colour 0 included or left as a hole.
func _blit_indices(
	buffer: PackedByteArray, width: int, height: int, at: Vector2i,
	palette: PackedColorArray, transparent: bool
) -> void:
	for y: int in height:
		for x: int in width:
			var index: int = int(buffer[y * width + x])
			if transparent and index == 0:
				continue
			_put(at + Vector2i(x, y), palette, index)


func _put(at: Vector2i, palette: PackedColorArray, index: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= _image.get_width() or at.y >= _image.get_height():
		return
	_image.set_pixel(
		at.x, at.y, palette[index] if index < palette.size() else Color.MAGENTA
	)
