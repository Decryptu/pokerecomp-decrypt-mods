extends Control

const Options: GDScript = preload("../options.gd")
const Steering: GDScript = preload("../steering.gd")
const Frost: GDScript = preload("panel.gd")
const Anim: GDScript = preload("anim.gd")

const Profiles: GDScript = preload("../shape/profiles.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const MapSourceScript: GDScript = preload("../shape/map_source.gd")
const AtlasScript: GDScript = preload("../shape/atlas.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const ArenaScript: GDScript = preload("arena.gd")
const DioramaScript: GDScript = preload("../world/diorama.gd")

const CELL: float = 16.0

const FIELD_OPACITY: float = 0.75
const RASTER_WRAP: int = 256

var _data: GameData = null
var _view: Dictionary = {}
var _colors: Gen2BattleColors = null
var _context: Gen2BattleWorldContext = null

var _stage: RefCounted = null
var _arena: RefCounted = null
var _held := Steering.Glide.new()
var _atlas: RefCounted = null
var _mesher: RefCounted = null

const ENEMY_PANEL := Rect2i(1, 0, 11, 4)
const PLAYER_PANEL := Rect2i(9, 7, 11, 5)
const PANEL_PAD: int = 2

const PANEL_TINT := Color(1.0, 1.0, 1.0, 0.52)

var _hud: Gen2BattleHud = null
var _panels_backing: Array[ColorRect] = []
var _frost: RefCounted = null
var _hud_layers: Array[TextureRect] = []
var _hud_keys: Array = []
var _anim: RefCounted = null
var _anim_layer: TextureRect = null
var _anim_player_drift := Vector2.ZERO
var _anim_enemy_drift := Vector2.ZERO
var _anim_drawn_at := Vector4i(9999, 9999, 9999, 9999)
var _battlers: Array[TextureRect] = []
var _pic_textures: Dictionary = {}
var _native := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
var _screen_rect := Rect2i()
var _draw_cells: int = 0


func _init() -> void:
	_atlas = AtlasScript.new()
	_arena = ArenaScript.new()
	_stage = DioramaScript.new()
	add_child(_stage.container)
	_frost = Frost.new()
	for panel: Rect2i in [ENEMY_PANEL, PLAYER_PANEL]:
		var backing := ColorRect.new()
		backing.color = PANEL_TINT
		backing.material = _frost.material
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.set_meta(&"tiles", panel)
		add_child(backing)
		_panels_backing.append(backing)
	for index: int in HUD_LAYERS:
		var layer := TextureRect.new()
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_hud_layers.append(layer)
		_hud_keys.append(null)
	_anim_layer = TextureRect.new()
	_anim_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_anim_layer)
	_read_options()
	Options.listen(_on_option_changed)
	Options.listen_actions(_on_action_changed)


func uses_hardware_viewport() -> bool:
	return false


func interface_opacity() -> float:
	return FIELD_OPACITY


func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_stage.set_render_scale(int(Options.value(Options.SCALE, Options.default_scale())))
	_arena.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			_build_arena()
		Options.SCALE:
			_stage.set_render_scale(int(value))
		Options.WHEEL:
			_arena.set_wheel_sign(int(value))
		Options.RECENTRE:
			_arena.steer(Steering.RESET)


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != Options.MOD_ID or not pressed:
		return
	_arena.steer(key)


func _glide(delta: float) -> void:
	var held: Dictionary = _held.notches(delta, Options.strength)
	for command: StringName in held:
		_arena.steer_by(command, float(held[command]))


func set_native_size(size_pixels: Vector2i) -> void:
	_native = size_pixels
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)
	_layout_hud()


func set_screen_rect(rect: Rect2i) -> void:
	if rect == _screen_rect:
		return
	_screen_rect = rect
	_layout_hud()


func set_battle_data(data: GameData) -> bool:
	_data = data
	if data == null:
		return false
	_hud = Gen2BattleHud.from_data(data)
	_hud_keys.fill(null)
	_pic_textures.clear()
	_colors = Gen2BattleColors.new(data)
	_anim = Anim.new(data, _colors)
	return _hud != null


func set_world_context(context: Gen2BattleWorldContext) -> void:
	_context = context
	_build_arena()


func set_view(view: Dictionary) -> void:
	_view = view
	_colors.set_view(view)
	refresh()


func refresh() -> void:
	_frame_camera()
	_stage.set_flash(_view.get("bg_palette_maps", []))
	_stage.set_grayscale(bool(_view.get("grayscale", false)))
	_place_battlers()
	_measure_anim_drift()
	_draw_hud()
	_draw_anim()


func handle_battle_input(event: InputEvent) -> bool:
	return _arena.handle_input(event)


func _process(delta: float) -> void:
	_glide(delta)
	_arena.advance(delta)
	_frame_camera()
	_place_battlers()
	_measure_anim_drift()
	_follow_anim_drift()


func _build_arena() -> void:
	if _data == null or _context == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_arena.stage(null)
		return
	var map: Gen2WorldMap = _data.world_map(_context.map_group(), _context.map_number())
	var tileset: Gen2WorldTileset = _data.world_tileset(_context.tileset)
	if map == null or tileset == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_arena.stage(null)
		return

	var source: RefCounted = MapSourceScript.new(null, map, tileset, _data)
	source.set_map_as_it_stood(_context.changed_blocks, _context.written_tiles)
	_stage.set_time_of_day(_context.time_of_day)
	if _atlas.build(_data, map, tileset, _context.time_of_day):
		_stage.set_texture(_atlas.texture)
		if source.outside():
			_stage.set_background(_atlas.background(), true, _atlas.sky_ramp())
		else:
			_stage.set_background(_atlas.void_color(), false)
	_mesher = _resolved_for(map, tileset, source)
	_stage.set_view_distance(float(_draw_cells) * CELL)
	_stage.set_terrain(_mesher.emit(_atlas, _window(_context.player_cell)))
	_stage.set_water(_mesher.take_water())
	_bank()
	_stage.set_tufts(_mesher.take_tufts())
	_stage.set_models(_mesher.take_models())
	_arena.stage(_context, source, _mesher)
	_frame_camera()
	_place_battlers()

static var _resolved: Dictionary = {}
const RESOLVED_KEPT: int = 2


func _resolved_for(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, source: RefCounted
) -> RefCounted:
	var key: String = "%s,%d,%d,%d,%d" % [
		_data.id, map.group, map.number, tileset.number,
		hash([_context.changed_blocks, _context.written_tiles]),
	]
	if _resolved.has(key):
		return _resolved[key]
	var mesher: RefCounted = MesherScript.new()
	mesher.resolve(source, TileShapeScript.new(Profiles.of(_data), tileset.name))
	if _resolved.size() >= RESOLVED_KEPT:
		_resolved.erase(_resolved.keys()[0])
	_resolved[key] = mesher
	return mesher


func _window(cell: Vector2i) -> Rect2i:
	if _draw_cells <= 0:
		return Rect2i()
	var span: int = _draw_cells * 2 + 1
	return Rect2i(
		(cell - Vector2i(_draw_cells, _draw_cells)) * Gen2Layout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * Gen2Layout.MAP_BLOCK_CELL_WIDTH
	)


func _frame_camera() -> void:
	_arena.set_shake(_raster_shake())
	_stage.camera.fov = _arena.fov(_frame_stretch())
	_stage.aim_camera(_arena.eye(), _arena.target())


func _raster_shake() -> Vector2:
	if bool(_view.get("grayscale", false)):
		return Vector2.ZERO
	return Vector2(
		_raster_mean(_view.get("raster_scx", [])),
		_raster_mean(_view.get("raster_scy", []))
	)


func _raster_mean(supplied: Variant) -> float:
	var rows := PackedInt32Array(supplied)
	if rows.is_empty():
		return 0.0
	var total: int = 0
	for row: int in rows:
		total += row if row < RASTER_WRAP / 2 else row - RASTER_WRAP
	return -float(total) / float(rows.size())


func _frame_stretch() -> float:
	return float(_native.y) / float(Gen2Screen.HEIGHT * _hud_scale())


func _place_battlers() -> void:
	_stage.begin_shadow_casters()
	var slot: int = _place_pair(_battlers_block())
	for index: int in range(slot, _battlers.size()):
		_battlers[index].visible = false
	_stage.end_shadow_casters()


func _battlers_block() -> Dictionary:
	var supplied: Variant = _view.get("battlers", null)
	if supplied is Dictionary:
		return supplied
	return {
		"enemy": _settled_side(int(_view.get("enemy_species", 0))),
		"player": _settled_side(int(_view.get("player_species", 0))),
	}


func _settled_side(species: int) -> Dictionary:
	return {"kind": KIND_MON, "species": species, "visible": true}


func _place_pair(battlers: Dictionary) -> int:
	var enemy: Dictionary = battlers.get("enemy", {})
	var player: Dictionary = battlers.get("player", {})
	var slot: int = 0
	if StringName(enemy.get("kind", KIND_NONE)) == KIND_MON \
			and StringName(_view.get("battle_kind", &"wild")) == &"trainer":
		slot = _pin(
			slot, _trainer_pic(int(_view.get("trainer_class", 0))),
			_arena.enemy_trainer_ground()
		)
	slot = _pin_side(slot, enemy, false, _arena.enemy_ground())
	return _pin_side(slot, player, true, _arena.player_ground())


func _pin_side(slot: int, side: Dictionary, back: bool, ground: Vector3) -> int:
	if not bool(side.get("visible", true)):
		return slot
	return _pin(
		slot, _side_pic(side, back), ground,
		Vector2(side.get("offset_pixels", Vector2.ZERO)),
		Vector2(side.get("scale", Vector2.ONE))
	)

const KIND_NONE: StringName = &"none"
const KIND_MON: StringName = &"mon"


func _side_pic(side: Dictionary, back: bool) -> Texture2D:
	if StringName(side.get("kind", KIND_NONE)) == KIND_NONE:
		return null
	return _square_pic(back)


func _pin(
	slot: int, texture: Texture2D, ground: Vector3,
	offset: Vector2 = Vector2.ZERO, picture_scale: Vector2 = Vector2.ONE
) -> int:
	if texture == null:
		return slot
	var at: Vector2 = _stage.camera.unproject_position(ground)
	var drawn := Vector2(texture.get_size()) * float(_hud_scale()) * picture_scale
	if drawn.x < 1.0 or drawn.y < 1.0:
		return slot
	var rect: TextureRect = _battler(slot)
	rect.texture = texture
	rect.size = drawn
	rect.position = at - Vector2(drawn.x * 0.5, drawn.y) + offset * float(_hud_scale())
	rect.visible = true
	if _stands_on_its_square(offset, picture_scale):
		_stage.add_shadow_caster(texture, ground, _caster_scale(ground, texture.get_height()))
	return slot + 1

const SHADOW_OFFSET_LIMIT: float = float(PokeTiles.TILE_WIDTH)


func _stands_on_its_square(offset: Vector2, picture_scale: Vector2) -> bool:
	return offset.length() < SHADOW_OFFSET_LIMIT \
		and picture_scale.is_equal_approx(Vector2.ONE)


func _caster_scale(ground: Vector3, height: int) -> float:
	var wanted: float = float(height * _hud_scale())
	var per_pixel: float = 1.0
	for _step: int in 2:
		var top: Vector3 = ground + Vector3(0.0, float(height) * per_pixel, 0.0)
		var projected: float = _stage.camera.unproject_position(ground).y \
			- _stage.camera.unproject_position(top).y
		if projected < 0.001:
			return per_pixel
		per_pixel *= wanted / projected
	return per_pixel


func _battler(slot: int) -> TextureRect:
	while slot >= _battlers.size():
		var rect := TextureRect.new()
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		move_child(rect, 1 + _battlers.size())
		_battlers.append(rect)
	return _battlers[slot]


## What stands on one side's square, as the host's own renderer draws it.
func _square_pic(back: bool) -> Texture2D:
	if _data == null:
		return null
	var palette: PackedColorArray = _colors.pic_palette(back)
	var key: String = str([Gen2BattleRenderer.square_key(_view, back), back, palette])
	return _cached_texture(key, back, palette, func() -> PackedByteArray:
		return Gen2BattleRenderer.square_pixels(_data, _view, back)
	)


## The opponent standing behind their Pokemon, which only this view stages.
func _trainer_pic(trainer_class: int) -> Texture2D:
	if _data == null or trainer_class <= 0:
		return null
	var palette: PackedColorArray = _colors.pic_palette(false)
	var key: String = "t%d:%s" % [trainer_class, str(palette)]
	return _cached_texture(key, false, palette, func() -> PackedByteArray:
		return Gen2BattleRenderer.padded_pic(
			_data, _data.trainer_pic(trainer_class), Gen2BattleScreenMap.ENEMY_SIDE
		)
	)


func _cached_texture(
	key: String, back: bool, palette: PackedColorArray, pixels: Callable
) -> Texture2D:
	if _pic_textures.has(key):
		return _pic_textures[key]
	var box: int = Gen2BattleRenderer.square_side(_data.generation, back) * TILE
	var drawn: PackedByteArray = pixels.call()
	if drawn.size() < box * box:
		return null
	var image: Image = _image(drawn, box, box, palette)
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_pic_textures[key] = texture
	return texture


func _image(
	pixels: PackedByteArray, width: int, height: int, palette: PackedColorArray
) -> Image:
	var field: PackedByteArray = _field(pixels, width, height)
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y: int in height:
		for x: int in width:
			var at: int = y * width + x
			var index: int = int(pixels[at])
			var color: Color = palette[index] if index < palette.size() else Color.MAGENTA
			if field[at] == 1:
				color.a = 0.0
			image.set_pixel(x, y, color)

	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	return image.get_region(used)


func _field(pixels: PackedByteArray, width: int, height: int) -> PackedByteArray:
	var field := PackedByteArray()
	field.resize(width * height)
	var stack := PackedInt32Array()
	for x: int in width:
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y: int in height:
		stack.append(y * width)
		stack.append(y * width + width - 1)

	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if field[at] == 1 or pixels[at] != 0:
			continue
		field[at] = 1
		@warning_ignore("integer_division")
		var y: int = at / width
		var x: int = at % width
		if x > 0:
			stack.append(at - 1)
		if x < width - 1:
			stack.append(at + 1)
		if y > 0:
			stack.append(at - width)
		if y < height - 1:
			stack.append(at + width)
	return field

const HUD_PANELS: int = 0
const HUD_ENEMY_BAR: int = 1
const HUD_PLAYER_BAR: int = 2
const HUD_EXP_BAR: int = 3
const HUD_TRAINER_BALLS: int = 4
const HUD_LAYERS: int = 5
const TILE: int = 8


## The host draws both panels; the bars and the party balls each wear their
## own palette, so each is a layer, redrawn only when what it shows changes.
func _draw_hud() -> void:
	if _hud == null:
		return
	var up: bool = bool(_view.get("hud_visible", true))
	var enemy_up: bool = up and bool(_view.get("enemy_hud_visible", true))
	var player_up: bool = up and bool(_view.get("player_hud_visible", true))
	_panels_backing[0].visible = enemy_up
	_panels_backing[1].visible = player_up
	var ink: PackedColorArray = _colors.panel_palette()
	_layer(HUD_PANELS, up, [Gen2BattleHud.panels_key(_view), ink], ink,
		func(into: PackedByteArray) -> void: _hud.draw_panels(into, Gen2Screen.WIDTH, _view))
	_draw_hp_layer(HUD_ENEMY_BAR, enemy_up, "enemy_", Gen2BattleHud.ENEMY_BAR)
	_draw_hp_layer(HUD_PLAYER_BAR, player_up, "player_", Gen2BattleHud.PLAYER_BAR)
	var gained: int = int(_view.get("exp_pixels", 0))
	_layer(HUD_EXP_BAR, player_up and not _hud.gen1, [gained],
		_data.bar_palette(GameData.EXP_BAR_PALETTE),
		func(into: PackedByteArray) -> void: _hud.draw_exp_bar(into, Gen2Screen.WIDTH, gained))
	var balls: Array = _view.get("trainer_hud_balls", []) as Array
	_layer(HUD_TRAINER_BALLS, up and not balls.is_empty(), [balls],
		_colors.object_palette(Gen2BattleAnimBackground.PAL_OB_YELLOW),
		func(into: PackedByteArray) -> void:
			_hud.draw_party_balls(into, Gen2Screen.WIDTH, balls))


func _draw_hp_layer(index: int, shown: bool, side: String, bar: Vector2i) -> void:
	var hp: int = int(_view.get(side + "hp", 0))
	var max_hp: int = int(_view.get(side + "max_hp", 0))
	var ink: PackedColorArray = _colors.hp_palette(hp, max_hp)
	_layer(index, shown, [hp, max_hp, ink], ink,
		func(into: PackedByteArray) -> void:
			_hud.draw_hp_bar(into, Gen2Screen.WIDTH, bar, hp, max_hp))


func _layer(
	index: int, shown: bool, key: Array, palette: PackedColorArray, paint: Callable
) -> void:
	var keyed: Array = [shown] + key
	if _hud_keys[index] == keyed:
		return
	_hud_keys[index] = keyed
	if not shown:
		_hud_layers[index].texture = null
		return
	var into: PackedByteArray = _buffer()
	paint.call(into)
	_show(index, into, palette)


func _draw_anim() -> void:
	if _anim_layer == null:
		return
	var image: Image = null
	if _anim != null:
		image = _anim.image(_view, _anim_player_drift, _anim_enemy_drift)
	if image == null:
		_anim_layer.texture = null
		_anim_drawn_at = Vector4i(9999, 9999, 9999, 9999)
		return
	_anim_layer.texture = ImageTexture.create_from_image(image)
	_anim_drawn_at = _anim_rounded()
	_layout_anim()


func _layout_anim() -> void:
	if _anim_layer == null:
		return
	var factor: int = _hud_scale()
	_anim_layer.size = Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	_anim_layer.position = _hud_origin()


func _measure_anim_drift() -> void:
	if _arena == null or _stage == null or _stage.camera == null:
		return
	var factor: float = float(_hud_scale())
	var origin: Vector2 = _hud_origin()
	_anim_enemy_drift = (_stage.camera.unproject_position(_arena.enemy_ground()) - origin) \
		/ factor - _arena.ENEMY_MARK
	_anim_player_drift = (_stage.camera.unproject_position(_arena.player_ground()) - origin) \
		/ factor - _arena.PLAYER_MARK


func _follow_anim_drift() -> void:
	if _anim_layer == null or _anim_layer.texture == null:
		return
	if _anim_rounded() != _anim_drawn_at:
		_draw_anim()


func _anim_rounded() -> Vector4i:
	var player: Vector2 = _anim_player_drift.round()
	var enemy: Vector2 = _anim_enemy_drift.round()
	return Vector4i(int(player.x), int(player.y), int(enemy.x), int(enemy.y))


func _buffer() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	return out


func _show(index: int, indices: PackedByteArray, palette: PackedColorArray) -> void:
	_hud_layers[index].texture = ImageTexture.create_from_image(
		Gen2PicImage.from_indices(
			indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
		)
	)
	_layout_layer(_hud_layers[index])


func _layout_hud() -> void:
	for layer: TextureRect in _hud_layers:
		_layout_layer(layer)
	_layout_anim()
	if _frost != null:
		_frost.set_scale(_hud_scale())
	for backing: ColorRect in _panels_backing:
		var tiles: Rect2i = backing.get_meta(&"tiles")
		var factor: int = _hud_scale()
		var pad: float = float(PANEL_PAD * factor)
		backing.size = Vector2(tiles.size * Gen2BattleHud.TILE * factor) + Vector2(pad, pad) * 2.0
		backing.position = _hud_origin() \
			+ Vector2(tiles.position * Gen2BattleHud.TILE * factor) - Vector2(pad, pad)


func _layout_layer(layer: TextureRect) -> void:
	var factor: int = _hud_scale()
	layer.size = Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	layer.position = _hud_origin()


func _hud_scale() -> int:
	if _screen_rect.size.y >= Gen2Screen.HEIGHT:
		@warning_ignore("integer_division")
		return maxi(1, _screen_rect.size.y / Gen2Screen.HEIGHT)
	@warning_ignore("integer_division")
	return maxi(1, mini(
		_native.x / Gen2Screen.WIDTH, _native.y / Gen2Screen.HEIGHT
	))


func _hud_origin() -> Vector2:
	if _screen_rect.size.y >= Gen2Screen.HEIGHT:
		return Vector2(_screen_rect.position)
	var factor: int = _hud_scale()
	var drawn := Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	return ((Vector2(_native) - drawn) * 0.5).floor()


func _bank() -> void:
	var shore: PackedColorArray = _atlas.shore_colors()
	if shore.size() == 2:
		_stage.set_shore_colors(_atlas.background(), shore[0], shore[1])
	_stage.set_bank(
		_mesher.bank_field(), _mesher.bank_world(), _mesher.bank_origin(),
		_mesher.bank_span()
	)
