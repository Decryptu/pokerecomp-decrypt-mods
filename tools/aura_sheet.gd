extends SceneTree

## A contact sheet of candidate marks for a high-DV wild Pokemon on the map,
## drawn from one cartridge's own art.

const WINDOW_SIZE := Vector2i(780, 830)
const SHEET_SIZE := Vector2i(764, 820)
const PLATE := 48
const SCALE: int = 3
const COLUMNS: int = 4
const CAPTURE_ON: int = 8
const BATTLER_CENTRE := Vector2(
	(Gen2BattleScreenMap.ENEMY_AT.x + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_WIDTH,
	(Gen2BattleScreenMap.ENEMY_AT.y + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_HEIGHT
)
const EMOTE_CANDIDATES: Array[int] = [
	Gen2WorldActors.EMOTE_BOLT,
	Gen2WorldActors.EMOTE_HAPPY,
	Gen2WorldActors.EMOTE_HEART,
	Gen2WorldActors.EMOTE_SHOCK,
]
const LOOP_ANIM: int = 0x10A
const LOOP_FRAMES: Array[int] = [12, 24, 36]
const TWINKLE_FRAMES: Array[int] = [32, 40, 48]
const GLOW_STEPS: Array[float] = [0.0, 0.2, 0.4, 0.6]
const PULSE_STEPS: int = 4
const PULSE_PEAK: float = 0.45
const GLOW_RUNGS: int = 4
const PAD_LIFTS: Array[int] = [10, 12, 14]
const GLOW_LIGHTS: Array = [
	{"name": "WHITE", "color": Color(1.0, 1.0, 1.0)},
	{"name": "GOLD", "color": Color(1.0, 0.87, 0.35)},
	{"name": "CYAN", "color": Color(0.55, 0.95, 1.0)},
]

var _output_path: String = ""
var _sheet: Node2D = null
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [species] [anim frame]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_output_path = args[1]
	if Gen2ToolPath.refuses(_output_path):
		quit(2)
		return
	var species: int = int(args[2]) if args.size() > 2 else 21
	if args.size() > 4 and args[4] == "frames":
		_write_frames(data, species, args[5] if args.size() > 5 else "")
		return
	var anim_frame: int = int(args[3]) if args.size() > 3 else 24
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_sheet = Sheet.new()
	_sheet.set("data", data)
	_sheet.set("species", species)
	_sheet.set("anim_frame", anim_frame)
	_sheet.set("mode", args[4] if args.size() > 4 else "marks")
	_sheet.set("sweep", args[5] if args.size() > 5 else "")
	root.add_child(_sheet)
	current_scene = _sheet


func _write_frames(data: GameData, species: int, options: String) -> void:
	var parts: PackedStringArray = options.split(",", false)
	var light: int = clampi(int(parts[0]) if parts.size() > 0 else 1, 0, GLOW_LIGHTS.size() - 1)
	var peak: float = float(parts[1]) if parts.size() > 1 else PULSE_PEAK
	var count: int = maxi(int(parts[2]) if parts.size() > 2 else 30, 2)
	var rungs: int = maxi(int(parts[3]) if parts.size() > 3 else GLOW_RUNGS, 1)
	var sheet := Sheet.new()
	sheet.data = data
	sheet.species = species
	DirAccess.make_dir_recursive_absolute(_output_path)
	for step: int in count:
		var amount: float = peak * 0.5 * (1.0 - cos(TAU * float(step) / float(count)))
		amount = roundf(amount / peak * float(rungs)) / float(rungs) * peak
		var image: Image = sheet._mark(GLOW_LIGHTS[light]["color"], false, false, amount)
		image.save_png("%s/%03d.png" % [_output_path, step])
	print("wrote %d frames to %s" % [count, _output_path])
	quit(0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < CAPTURE_ON:
		return false
	var image: Image = root.get_texture().get_image()
	image = image.get_region(Rect2i(Vector2i.ZERO, SHEET_SIZE))
	var error: Error = image.save_png(_output_path)
	if error != OK:
		print("could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true


class Sheet extends Node2D:
	var data: GameData = null
	var species: int = 21
	var anim_frame: int = 24
	var mode: String = "marks"
	var sweep: String = ""
	var _built: Array = []

	func _ready() -> void:
		match mode:
			"anims": _built = _sweep_cells()
			"glow": _built = _glow_cells()
			"ground": _built = _ground_cells()
			"pad": _built = _pad_cells()
			"round2": _built = _round_two_cells()
			"pulse": _built = _pulse_cells()
			_: _built = _cells()
		for index: int in _built.size():
			var cell: Dictionary = _built[index]
			cell["texture"] = ImageTexture.create_from_image(cell["image"])
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE)), Color(0.09, 0.09, 0.11))
		for index: int in _built.size():
			_draw_cell(_built[index], index)

	func _sweep_cells() -> Array:
		var out: Array = []
		for pair: String in sweep.split(",", false):
			var parts: PackedStringArray = pair.split(":")
			if parts.size() < 2:
				continue
			var plate: Image = _plate(false)
			var ran: int = _blit_anim(plate, int(parts[1]), anim_frame)
			out.append({"name": "%s f%d" % [parts[0], ran], "image": plate})
		return out

	func _glow_cells() -> Array:
		var out: Array = []
		for light: Dictionary in GLOW_LIGHTS:
			for step: int in GLOW_STEPS.size():
				out.append({
					"name": "%s %d%%" % [light["name"], roundi(GLOW_STEPS[step] * 100.0)],
					"image": _glow_plate(light["color"], GLOW_STEPS[step]),
				})
		return out

	func _glow_plate(light: Color, amount: float) -> Image:
		var image := Image.create(PLATE, PLATE, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.16, 0.22, 0.16))
		var sprite: Gen2WorldSprite = data.overworld_icon(data.mon_menu_icon(species))
		if sprite == null:
			return image
		var colors: PackedColorArray = data.palette(species, false)
		var lit := PackedColorArray()
		for index: int in colors.size():
			lit.append(colors[index] if index == 0 else colors[index].lerp(light, amount))
		_blend(image, Gen2WorldSprite.image_for(
			sprite, data.overworld_icon_indices(sprite.icon_number),
			lit, Gen2WorldSprite.FACING_DOWN, 0
		), _mon_at())
		return image

	func _ground_cells() -> Array:
		var out: Array = []
		for effect: String in ["shadow", "boulder_dust", "grass_rustle", "rod"]:
			var sheet: Dictionary = data.overworld_effect(effect)
			if sheet.is_empty():
				continue
			var plate := Image.create(PLATE, PLATE, false, Image.FORMAT_RGBA8)
			plate.fill(Color(0.16, 0.22, 0.16))
			var palette: PackedColorArray = data.overworld_sprite_palette(
				Gen2WorldEffects.PAL_OW_EMOTE, Gen2WorldPalette.TIME_DAY
			)
			for tile: int in int(sheet["tiles"]):
				var image: Image = _sheet_tile(sheet, tile, palette)
				if image == null:
					continue
				_blend(plate, image, Vector2i(4 + (tile % 5) * 9, 4 + (tile / 5) * 9))
			out.append({"name": "%s, %d tiles" % [name, int(sheet["tiles"])], "image": plate})
		return out

	func _pad_cells() -> Array:
		var out: Array = []
		var sheet: Dictionary = data.overworld_effect("shadow")
		if sheet.is_empty():
			return out
		for light: Dictionary in GLOW_LIGHTS:
			for lift: int in PAD_LIFTS:
				var plate := Image.create(PLATE, PLATE, false, Image.FORMAT_RGBA8)
				plate.fill(Color(0.16, 0.22, 0.16))
				_blit_pad(plate, sheet, light["color"], lift)
				_blend(plate, _mon_image(), _mon_at())
				out.append({"name": "PAD %s at %d" % [light["name"], lift], "image": plate})
		return out

	func _blit_pad(plate: Image, sheet: Dictionary, light: Color, lift: int) -> void:
		var palette := PackedColorArray([
			Color(0, 0, 0, 0), light, light.darkened(0.25), light.darkened(0.5),
		])
		var tile: Image = _sheet_tile(sheet, 0, palette)
		if tile == null:
			return
		var flipped: Image = tile.duplicate()
		flipped.flip_x()
		var base: Vector2i = _mon_at() + Vector2i(0, lift)
		_blend(plate, tile, base)
		_blend(plate, flipped, base + Vector2i(8, 0))

	func _mon_image() -> Image:
		var sprite: Gen2WorldSprite = data.overworld_icon(data.mon_menu_icon(species))
		if sprite == null:
			return Image.create(16, 16, false, Image.FORMAT_RGBA8)
		return Gen2WorldSprite.image_for(
			sprite, data.overworld_icon_indices(sprite.icon_number),
			data.palette(species, false), Gen2WorldSprite.FACING_DOWN, 0
		)

	func _round_two_cells() -> Array:
		var gold: Color = GLOW_LIGHTS[1]["color"]
		return [
			{"name": "PLAIN, no mark", "image": _plate(false)},
			{"name": "SHINY sparkle, taken", "image": _sparkle()},
			{"name": "PAD gold", "image": _mark(gold, true, false, 0.0)},
			{"name": "PAD white", "image": _mark(GLOW_LIGHTS[0]["color"], true, false, 0.0)},
			{"name": "PAD cyan", "image": _mark(GLOW_LIGHTS[2]["color"], true, false, 0.0)},
			{"name": "MOTES gold", "image": _mark(gold, false, true, 0.0)},
			{"name": "PAD and MOTES", "image": _mark(gold, true, true, 0.0)},
			{"name": "GLOW gold, 20%", "image": _mark(gold, false, false, 0.2)},
		]

	func _mark(light: Color, pad: bool, motes: bool, glow: float) -> Image:
		var plate := Image.create(PLATE, PLATE, false, Image.FORMAT_RGBA8)
		plate.fill(Color(0.16, 0.22, 0.16))
		if pad:
			var sheet: Dictionary = data.overworld_effect("shadow")
			if not sheet.is_empty():
				_blit_pad(plate, sheet, light, PAD_LIFTS[1])
		_blend(plate, _glow_image(light, glow), _mon_at())
		if motes:
			_blit_motes(plate, light)
		return plate

	func _blit_motes(plate: Image, light: Color) -> void:
		var sheet: Dictionary = data.overworld_effect("boulder_dust")
		if sheet.is_empty():
			return
		var palette := PackedColorArray([
			Color(0, 0, 0, 0), light, light.darkened(0.25), light.darkened(0.5),
		])
		var at: Vector2i = _mon_at()
		var places: Array[Vector2i] = [
			at + Vector2i(-6, 2), at + Vector2i(14, 0), at + Vector2i(4, -7),
		]
		for index: int in places.size():
			var tile: Image = _sheet_tile(sheet, index % int(sheet["tiles"]), palette)
			if tile != null:
				_blend(plate, tile, places[index])

	func _glow_image(light: Color, amount: float) -> Image:
		var sprite: Gen2WorldSprite = data.overworld_icon(data.mon_menu_icon(species))
		if sprite == null:
			return Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var colors: PackedColorArray = data.palette(species, false)
		var lit := PackedColorArray()
		for index: int in colors.size():
			lit.append(colors[index] if index == 0 else colors[index].lerp(light, amount))
		return Gen2WorldSprite.image_for(
			sprite, data.overworld_icon_indices(sprite.icon_number),
			lit, Gen2WorldSprite.FACING_DOWN, 0
		)

	func _pulse_cells() -> Array:
		var out: Array = []
		for light: Dictionary in GLOW_LIGHTS:
			for step: int in PULSE_STEPS:
				var amount: float = PULSE_PEAK * 0.5 \
					* (1.0 - cos(TAU * float(step) / float(PULSE_STEPS)))
				out.append({
					"name": "%s %d%%" % [light["name"], roundi(amount * 100.0)],
					"image": _mark(light["color"], false, false, amount),
				})
		return out

	func _cells() -> Array:
		var out: Array = [
			{"name": "PLAIN, no mark", "image": _plate(false)},
			{"name": "SHINY palette", "image": _plate(true)},
			{"name": "SHINY sparkle, taken", "image": _sparkle()},
			{"name": "", "image": _plate(false)},
		]
		for emote: int in EMOTE_CANDIDATES:
			var plate: Image = _plate(false)
			_blit_emote(plate, emote)
			out.append({
				"name": "EMOTE %s" % RomLayout.EMOTE_NAMES[emote].to_upper(),
				"image": plate,
			})
		for at: int in LOOP_FRAMES:
			var plate: Image = _plate(false)
			_blit_anim(plate, LOOP_ANIM, at)
			out.append({"name": "IN LOVE, frame %d" % at, "image": plate})
		for at: int in TWINKLE_FRAMES:
			var plate: Image = _plate(false)
			_blit_anim(plate, 0x101, at)
			out.append({"name": "SPARKLE, frame %d" % at, "image": plate})
		return out

	func _draw_cell(cell: Dictionary, index: int) -> void:
		@warning_ignore("integer_division")
		var at := Vector2(
			40 + (index % COLUMNS) * (PLATE * SCALE + 32),
			24 + (index / COLUMNS) * (PLATE * SCALE + 52)
		)
		draw_texture_rect(
			cell["texture"], Rect2(at, Vector2(PLATE, PLATE) * SCALE), false
		)
		if String(cell["name"]).is_empty():
			return
		draw_string(
			ThemeDB.fallback_font, at + Vector2(0, PLATE * SCALE + 22),
			cell["name"], HORIZONTAL_ALIGNMENT_LEFT, PLATE * SCALE + 28, 17
		)

	func _sparkle() -> Image:
		var plate: Image = _plate(true)
		_blit_anim(plate, 0x101, anim_frame)
		return plate

	func _plate(shiny: bool) -> Image:
		var image := Image.create(PLATE, PLATE, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.16, 0.22, 0.16))
		var icon: int = data.mon_menu_icon(species)
		var sprite: Gen2WorldSprite = data.overworld_icon(icon)
		if sprite == null:
			return image
		var mon: Image = Gen2WorldSprite.image_for(
			sprite, data.overworld_icon_indices(sprite.icon_number),
			data.palette(species, shiny), Gen2WorldSprite.FACING_DOWN, 0
		)
		_blend(image, mon, _mon_at())
		return image

	func _mon_at() -> Vector2i:
		return Vector2i((PLATE - 16) / 2, (PLATE - 16) / 2)

	func _blit_emote(plate: Image, emote: int) -> void:
		var sheet: Dictionary = data.overworld_effect(RomLayout.EMOTE_NAMES[emote])
		if sheet.is_empty():
			return
		var palette: PackedColorArray = data.overworld_sprite_palette(
			Gen2WorldEffects.PAL_OW_EMOTE, Gen2WorldPalette.TIME_DAY
		)
		for index: int in 4:
			var tile: Image = _sheet_tile(sheet, index, palette)
			if tile == null:
				continue
			_blend(plate, tile, _mon_at() + Vector2i(
				(index & 1) * 8, (index >> 1) * 8 - 16
			))

	func _blit_anim(plate: Image, anim: int, until: int) -> int:
		var anim_data: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
		var player: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
			anim_data, anim, true, int(anim == 0x101)
		)
		if player == null:
			return -1
		var reached: int = 0
		for step: int in until:
			if player.finished():
				break
			player.advance_frame()
			reached = step + 1
		var pair: Array = _battler_pair()
		var window: Array = player.tiles()
		var origin := Vector2(_mon_at()) + Vector2(8, 8) - BATTLER_CENTRE
		for entry: Variant in player.sprites():
			if entry is Dictionary:
				_blit_anim_sprite(plate, entry as Dictionary, window, pair, origin)
		return reached

	func _blit_anim_sprite(
		plate: Image, sprite: Dictionary, window: Array, pair: Array, origin: Vector2
	) -> void:
		var at: int = int(sprite.get("tile", 0)) - Gen2BattleAnimObject.BASE_TILE
		if at < 0 or at >= window.size() or not window[at] is Dictionary:
			return
		var slot: Dictionary = window[at]
		if not slot.has("gfx"):
			return
		var attributes: int = int(sprite.get("attributes", 0))
		var tile: Image = _anim_tile(int(slot["gfx"]), int(slot["tile"]), attributes, pair)
		if tile == null:
			return
		_blend(plate, tile, Vector2i(origin + Vector2(
			float(int(sprite.get("x", 0)) - 8), float(int(sprite.get("y", 0)) - 16)
		)))

	func _battler_pair() -> Array:
		var row: Dictionary = data.species(species)
		if row.is_empty():
			return []
		return (row["palette"] as Dictionary)["normal"]

	func _anim_tile(gfx: int, tile: int, attributes: int, pair: Array) -> Image:
		var strip: PackedByteArray = data.battle_anim_gfx_indices(gfx)
		@warning_ignore("integer_division")
		var width: int = strip.size() / Gen2Tiles.TILE_HEIGHT
		if width <= 0 or (tile + 1) * Gen2Tiles.TILE_WIDTH > width:
			return null
		var pixels := PackedByteArray()
		pixels.resize(Gen2Tiles.TILE_PIXELS)
		for row: int in Gen2Tiles.TILE_HEIGHT:
			var from: int = row * width + tile * Gen2Tiles.TILE_WIDTH
			for column: int in Gen2Tiles.TILE_WIDTH:
				pixels[row * Gen2Tiles.TILE_WIDTH + column] = strip[from + column]
		var image: Image = Gen2PicImage.from_indices(
			pixels, Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT,
			data.battle_object_palette(
				attributes & Gen2BattleAnimObject.OAM_PALETTE, pair
			),
			true
		)
		if (attributes & Gen2BattleAnimObject.OAM_XFLIP) != 0:
			image.flip_x()
		if (attributes & Gen2BattleAnimObject.OAM_YFLIP) != 0:
			image.flip_y()
		return image

	func _sheet_tile(sheet: Dictionary, tile: int, palette: PackedColorArray) -> Image:
		var indices: PackedByteArray = sheet["indices"]
		var tiles: int = int(sheet["tiles"])
		if tile < 0 or tile >= tiles or indices.size() < tiles * Gen2Tiles.TILE_PIXELS:
			return null
		var image := Image.create(
			Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8
		)
		var width: int = tiles * Gen2Tiles.TILE_WIDTH
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var index: int = int(indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x])
				var color: Color = palette[index] if index < palette.size() else Color.MAGENTA
				if index == 0:
					color.a = 0.0
				image.set_pixel(x, y, color)
		return image

	func _blend(destination: Image, source: Image, at: Vector2i) -> void:
		for y: int in source.get_height():
			for x: int in source.get_width():
				var to: Vector2i = at + Vector2i(x, y)
				if to.x < 0 or to.y < 0 \
					or to.x >= destination.get_width() or to.y >= destination.get_height():
					continue
				var color: Color = source.get_pixel(x, y)
				if color.a <= 0.0:
					continue
				destination.set_pixel(to.x, to.y, color)
