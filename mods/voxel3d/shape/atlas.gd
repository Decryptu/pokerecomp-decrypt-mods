extends RefCounted

## The texture the terrain samples: the map's tileset, coloured with the map's
## own palettes at the current time of day.

const TILE: int = 8
const TILES_PER_ROW: int = 16

const SKY_SLOT: int = 6
const SKY_WATER_SLOT: int = 3
const SKY_WARM_SLOT: int = 4
const SKY_HORIZON_DARKEN: float = 0.10
const SKY_ZENITH_DARKEN: float = 0.30
const SKY_MORNING_LIGHTEN: float = 0.40
const SKY_MORNING_ZENITH_DARKEN: float = 0.34

var texture: ImageTexture = null
var _image: Image = null
var _tile_count: int = 0
var _source: PackedByteArray = PackedByteArray()
var _background: Color = Color("#f5f1d8")
var _shades: Dictionary = {}
var _animation: Gen2WorldAnimation = null
var _frames: Dictionary = {}
var _sky_ramp: PackedColorArray = PackedColorArray()
var _shore_colors: PackedColorArray = PackedColorArray()
var _water_colors: PackedColorArray = PackedColorArray()


func build(
	data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	time_of_day: int,
	animation: Gen2WorldAnimation = null,
) -> bool:
	var kept: ImageTexture = texture
	texture = null
	_image = null
	_tile_count = 0
	_source = PackedByteArray()
	_shades.clear()
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


func uv_box(tile: int, box: Rect2i) -> Rect2:
	var whole: Rect2 = uv(tile)
	if whole.size == Vector2.ZERO:
		return whole
	var per_pixel: Vector2 = whole.size / float(TILE)
	return Rect2(
		whole.position + Vector2(box.position) * per_pixel,
		Vector2(box.size) * per_pixel
	)


func pixel(tile: int, x: int, y: int) -> int:
	if _source.is_empty() or tile < 0 or tile >= _tile_count:
		return -1
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return -1
	var at: int = y * _tile_count * TILE + tile * TILE + x
	return int(_source[at]) if at < _source.size() else -1


func frame_count(tiles: Array) -> int:
	var most: int = 1
	for tile: Variant in tiles:
		most = maxi(most, tile_frames(int(tile)).size())
	return most


func tile_frames(tile: int) -> Array[PackedByteArray]:
	if _frames.has(tile):
		return _frames[tile]
	var frames: Array[PackedByteArray] = []
	if _animation != null:
		frames = _animation.tile_frames(tile)
	_frames[tile] = frames
	return frames


func frame_pixel(tile: int, x: int, y: int, frame: int) -> int:
	var frames: Array[PackedByteArray] = tile_frames(tile)
	if frames.is_empty():
		return pixel(tile, x, y)
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return -1
	return int(frames[frame % frames.size()][y * TILE + x])


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


func is_dark(tile: int, index: int, count: int) -> bool:
	var order: PackedInt32Array = shade_order(tile)
	for rank: int in mini(count, order.size()):
		if order[rank] == index:
			return true
	return false


func texel(tile: int, x: int, y: int) -> Color:
	if _image == null or tile < 0 or tile >= _tile_count:
		return Color(0.0, 0.0, 0.0, 0.0)
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return Color(0.0, 0.0, 0.0, 0.0)
	@warning_ignore("integer_division")
	return _image.get_pixel(
		(tile % TILES_PER_ROW) * TILE + x, (tile / TILES_PER_ROW) * TILE + y
	)


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


func sky_ramp() -> PackedColorArray:
	return _sky_ramp


func shore_colors() -> PackedColorArray:
	return _shore_colors


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


func void_color() -> Color:
	if _image == null:
		return _background.darkened(0.7)
	var total := Vector3.ZERO
	var counted: int = 0
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
