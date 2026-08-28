extends Control

## The world drawn as a voxel diorama instead of a tile page.

const Options: GDScript = preload("../options.gd")
const Steering: GDScript = preload("../steering.gd")

const Profile: GDScript = preload("../shape/profile.gd")
const TileShapeScript: GDScript = preload("../shape/tile_shape.gd")
const MapSourceScript: GDScript = preload("../shape/map_source.gd")
const AtlasScript: GDScript = preload("../shape/atlas.gd")
const MesherScript: GDScript = preload("../shape/mesher.gd")
const CameraRigScript: GDScript = preload("camera_rig.gd")
const DioramaScript: GDScript = preload("diorama.gd")
const TransitionScript: GDScript = preload("transition.gd")

const CELL: float = 16.0
const TILE: float = 8.0

const FIELD_OPACITY: float = 0.75

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING

var _stage: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _rig: RefCounted = null
var _held := Steering.Glide.new()
var _shape: RefCounted = null

var _actor_textures: Dictionary = {}
var _pulse_textures: Dictionary = {}
var _mod_actors: Gen2WorldActors = null
var _encounters: Gen2WorldEncounters = null
var _shape_tileset: int = -1

var _draw_cells: int = 0
var _window_centre := Vector2i.MAX
var _outside: bool = true

const BUILD_BUDGET_USEC: int = 4000
const FIRST_BUILD_BUDGET_USEC: int = 12000
var _building: bool = false
var _recolouring: bool = false
var _standing: bool = false
var _first_build: bool = true
var _chunks: Array = []
var _water: Array = []
var _tufts: Array = []
var _text_box := Rect2i()
var _screen_rect := Rect2i()
var _interface_masked: bool = false
var _transition: RefCounted = null
var _transition_sprites: int = Gen2BattleTransition.SPRITES_ALL
var _transition_opponent: int = -1
var _fade_order: int = Gen2WorldPalette.FADE_IDENTITY
var _transition_order: int = Gen2BattleTransition.IDENTITY
var _pending_hole := Rect2()


func _init() -> void:
	_atlas = AtlasScript.new()
	_mesher = MesherScript.new()
	_rig = CameraRigScript.new()
	_stage = DioramaScript.new()
	add_child(_stage.container)
	_transition = TransitionScript.new()
	add_child(_transition.layer)
	_read_options()
	Options.listen(_on_option_changed)
	Options.listen_actions(_on_action_changed)


func uses_hardware_viewport() -> bool:
	return false


func interface_opacity() -> float:
	return FIELD_OPACITY


func set_text_box_rect(rect: Rect2i) -> void:
	_text_box = rect
	_apply_text_box()


func set_screen_rect(rect: Rect2i) -> void:
	_screen_rect = rect
	_transition.place(_screen_place())
	_apply_text_box()
	_apply_interface_mask()


func set_transition(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray,
	sprites: int = Gen2BattleTransition.SPRITES_ALL, opponent: int = -1,
	order: int = Gen2BattleTransition.IDENTITY
) -> void:
	_transition_sprites = sprites
	_transition_opponent = opponent
	_transition.place(_screen_place())
	_transition.set_frame(
		cells, tiles, Gen2WorldPalette.fade_palette(palette, order)
	)
	_transition_order = order
	_apply_flash()


func clear_transition() -> void:
	_transition_sprites = Gen2BattleTransition.SPRITES_ALL
	_transition_opponent = -1
	_transition.clear()
	_transition_order = Gen2BattleTransition.IDENTITY
	_apply_flash()

@warning_ignore("unused_parameter")
func set_fade(order: int, white_fill: bool = false) -> void:
	if order == _fade_order:
		return
	_fade_order = order
	_apply_flash()


func _apply_flash() -> void:
	_stage.set_flash(_flash_bytes(_compose_orders(_fade_order, _transition_order)))


static func _compose_orders(first: int, second: int) -> int:
	if first == Gen2BattleTransition.IDENTITY:
		return second
	if second == Gen2BattleTransition.IDENTITY:
		return first
	var out: int = 0
	for level: int in 4:
		var through: int = (second >> (level * 2)) & 3
		out |= ((first >> (through * 2)) & 3) << (level * 2)
	return out


static func _flash_bytes(order: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(7)
	out.fill(order & 0xFF)
	return out


func set_interface_masked(masked: bool) -> void:
	_interface_masked = masked
	_apply_interface_mask()


func _apply_interface_mask() -> void:
	_stage.set_interface_mask(_screen_rect, _interface_masked)


func _screen_place() -> Rect2i:
	if _screen_rect.size.x > 0 and _screen_rect.size.y > 0:
		return _screen_rect
	return Rect2i(Vector2i.ZERO, Vector2i(_stage.container.size))


func _apply_text_box() -> void:
	var height: float = _stage.container.size.y
	if _text_box.size.y <= 0 or _text_box.position.y <= 0:
		_rig.pan_for_text_box(0.0, float(Gen2Screen.HEIGHT))
		return
	if _screen_rect.size.y <= 0 or height <= 0.0:
		_rig.pan_for_text_box(float(_text_box.position.y), float(Gen2Screen.HEIGHT))
		return
	var per_pixel: float = float(_screen_rect.size.y) / float(Gen2Screen.HEIGHT)
	_rig.pan_for_text_box(
		float(_screen_rect.position.y) + float(_text_box.position.y) * per_pixel,
		height, per_pixel
	)


func set_native_size(size_pixels: Vector2i) -> void:
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)
	_transition.place(_screen_place())
	_apply_text_box()
	_apply_interface_mask()


func set_actors(actors: Gen2WorldActors) -> void:
	_mod_actors = actors


func set_encounters(encounters: Gen2WorldEncounters) -> void:
	_encounters = encounters


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_pulse_textures.clear()
	_rebuild()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_actor_textures.clear()
	_stage.set_time_of_day(_time_of_day)
	_stage.far_field().set_time_of_day(_time_of_day)
	if _build_atlas():
		_stage.set_texture(_atlas.texture)
		_apply_background()
		if _mesher != null:
			_mesher.begin_recolour(_atlas)
			_recolouring = true
			_bank()


func refresh_animation() -> void:
	if _world == null:
		return
	if _atlas.refresh_animation(
		_world.data, _world.current_map, _world.current_tileset,
		_time_of_day, _animation
	):
		_stage.set_texture(_atlas.texture)
		_apply_background()


func refresh() -> void:
	_frame_camera()
	_rebuild_actors()


func handle_world_input(event: InputEvent) -> bool:
	return _rig.handle_input(event)


func _process(delta: float) -> void:
	_glide(delta)
	_rig.advance(delta)
	_advance_build()
	_advance_recolour()
	_recentre_window()
	_frame_camera()
	_rebuild_actors()


func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_stage.set_render_scale(int(Options.value(Options.SCALE, Options.default_scale())))
	_rig.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))
	_rig.set_default_pitch(float(Options.value(Options.CAMERA, Options.CAMERA_VALUES[1])))
	_stage.set_depth_of_field(dof_mode, dof_radius, dof_near, dof_far)


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			_window_centre = Vector2i.MAX
			_recentre_window()
		Options.SCALE:
			_stage.set_render_scale(int(value))
		Options.WHEEL:
			_rig.set_wheel_sign(int(value))
		Options.CAMERA:
			_rig.set_default_pitch(float(value))
		Options.RECENTRE:
			_rig.steer(Steering.RESET)


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != Options.MOD_ID or not pressed:
		return
	_rig.steer(key)


func _glide(delta: float) -> void:
	var held: Dictionary = _held.notches(delta, Options.strength)
	for command: StringName in held:
		_rig.steer_by(command, float(held[command]))


func _build_atlas() -> bool:
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		return false
	if not _atlas.build(
		_world.data, _world.current_map, _world.current_tileset,
		_time_of_day, _animation
	):
		return false
	_apply_background()
	return true


func _apply_background() -> void:
	if _outside:
		_stage.set_background(_atlas.background(), true, _atlas.sky_ramp())
	else:
		_stage.set_background(_atlas.void_color(), false)


func _rebuild() -> void:
	_building = false
	_standing = false
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_stage.far_field().configure(null, _time_of_day, true)
		return
	var tileset: int = _world.current_tileset.number
	if _shape == null or tileset != _shape_tileset:
		_shape = TileShapeScript.new(Profile, tileset)
		_shape_tileset = tileset
	var source: RefCounted = MapSourceScript.new(_world)
	_outside = source.outside()
	if _build_atlas():
		_stage.set_texture(_atlas.texture)
	_stage.far_field().configure(_world, _time_of_day, _outside, _atlas)
	_stage.set_time_of_day(_time_of_day)
	_mesher.resolve(source, _shape)
	_window_centre = Vector2i.MAX
	_recentre_window()
	refresh()


func _recentre_window() -> void:
	if _world == null or _building or _mesher.size_tiles() == Vector2i.ZERO:
		return
	if _draw_cells <= 0:
		if _window_centre == Vector2i.MAX:
			_window_centre = Vector2i.ZERO
			_stage.set_view_distance(0.0)
			_ring_on(_world.player_position_cells())
			_begin_terrain(Rect2i())
		return
	var at := Vector2i(_world.player_position_cells().floor())
	var margin: int = maxi(4, _draw_cells / 3)
	if _window_centre != Vector2i.MAX \
			and absi(at.x - _window_centre.x) <= margin \
			and absi(at.y - _window_centre.y) <= margin:
		return
	_window_centre = at
	_ring_on(_world.player_position_cells())
	var span: int = _draw_cells * 2 + 1
	_stage.set_view_distance(float(_draw_cells) * CELL, true)
	_begin_terrain(Rect2i(
		(at - Vector2i(_draw_cells, _draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	))

static var solid_cells: float = 35.0

static var far_trees: bool = true

static var dof_mode: int = 1
static var dof_radius: float = 4.0
static var dof_near: float = 900.0
static var dof_far: float = 2600.0


func _dress_far_field() -> void:
	var far: RefCounted = _stage.far_field()
	if far == null:
		return
	far.set_far_trees(far_trees)
	if not far_trees:
		return
	var tree: Array = _mesher.far_tree()
	if tree.size() == 2:
		far.set_far_tree(
			tree[0] as Mesh, _stage.foliage_material(tree[1] as Texture2D)
		)
	else:
		far.set_far_tree(null, null)


func _ring_on(cells: Vector2) -> void:
	var here := Vector3(cells.x * CELL, 0.0, cells.y * CELL)
	_mesher.set_detail_ring(here + _rig.offset(), solid_cells * CELL)


func _begin_terrain(window: Rect2i) -> void:
	_chunks = []
	_water = []
	_tufts = []
	_stage.far_field().set_stamped_bounds(_stamped_pixels())
	if not _mesher.begin_emit(_atlas, window):
		_pending_hole = Rect2()
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_stage.far_field().set_hole(Rect2())
		_standing = false
		return
	_pending_hole = _hole_pixels()
	_building = true
	_advance_build()


func _advance_build() -> void:
	if not _building:
		return
	var done: bool = false
	while true:
		done = _mesher.emit_step(
			BUILD_BUDGET_USEC if _standing else FIRST_BUILD_BUDGET_USEC
		)
		_chunks.append_array(_mesher.take_chunks())
		_water.append_array(_mesher.take_water())
		_tufts.append_array(_mesher.take_tufts())
		if done or not _first_build:
			break
	if done or not _standing:
		_stage.far_field().set_hole(_pending_hole)
		_stage.set_terrain(_chunks)
		_stage.set_water(_water)
		_bank()
		_stage.set_tufts(_tufts)
		_stage.set_models(_mesher.take_models())
	if done:
		_building = false
		_standing = true
		_first_build = false
		_dress_far_field()


func _advance_recolour() -> void:
	if not _recolouring:
		return
	if _mesher == null or _mesher.recolour_step(BUILD_BUDGET_USEC):
		_recolouring = false


func _frame_camera() -> void:
	if _world == null:
		return
	var here: Vector3 = _ground(_world.player_position_cells())
	_stage.set_walker(here)
	_stage.camera.fov = _rig.fov()
	var pan: Vector3 = _rig.pan()
	_stage.aim_camera(here + pan + _rig.offset(), here + pan)
	_stage.advance_far_field(here + pan)


func _stamped_pixels() -> Rect2:
	var bounds: Rect2i = _mesher.stamped_bounds_tiles()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Rect2()
	return Rect2(Vector2(bounds.position) * TILE, Vector2(bounds.size) * TILE)


func _hole_pixels() -> Rect2:
	var bounds: Rect2i = _mesher.emitted_bounds_tiles()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Rect2()
	return Rect2(Vector2(bounds.position) * TILE, Vector2(bounds.size) * TILE)


func _ground(cells: Vector2) -> Vector3:
	var at := Vector3(cells.x * CELL + CELL * 0.5, 0.0, cells.y * CELL + CELL * 0.5)
	if _mesher != null:
		at.y = float(_mesher.surface_height_at_position(at))
	return at


func _rebuild_actors() -> void:
	if _world == null:
		return
	_stage.begin_cards()
	_stage.begin_shadow_casters()
	if _transition_sprites == Gen2BattleTransition.SPRITES_NONE:
		_stage.end_cards()
		_stage.end_shadow_casters()
		return
	for object: Gen2WorldObject in _world.visible_objects():
		if not _drawn_in_transition(object.index):
			continue
		_add_actor(
			object.sprite, object.palette, object.facing, object.frame,
			Vector2(object.cell) + object.step_offset_cells(), PackedColorArray(),
			object.height_offset_pixels(),
			object.emote_id if object.emote_visible else Gen2WorldActors.EMOTE_NONE
		)
	_add_actor(
		_world.player_sprite(), _world.player_palette(),
		_world.player_facing, _world.player_walk_frame(),
		_world.player_position_cells(), PackedColorArray(),
		_world.player_height_offset_pixels()
	)
	if _mod_actors != null and _transition_sprites == Gen2BattleTransition.SPRITES_ALL:
		for entry: Dictionary in _mod_actors.sprites():
			_add_actor(
				entry["sprite"], 0, int(entry["facing"]), int(entry["frame"]),
				entry["position_cells"], entry.get("colors", PackedColorArray()),
				0.0, int(entry.get("emote", Gen2WorldActors.EMOTE_NONE))
			)
	if _transition_sprites == Gen2BattleTransition.SPRITES_ALL:
		_add_connected_actors()
	_add_encounter_pulse()
	_stage.end_cards()
	_stage.end_shadow_casters()


func _drawn_in_transition(index: int) -> bool:
	if _transition_sprites == Gen2BattleTransition.SPRITES_BATTLERS:
		return index == _transition_opponent
	return _transition_sprites != Gen2BattleTransition.SPRITES_NONE

const CONNECTED_REACH: float = 2400.0


func _add_connected_actors() -> void:
	if _world == null or not _outside \
			or not _world.has_method(&"connected_map_objects"):
		return
	var here: Vector2 = _world.player_position_cells() * CELL
	for entry: Dictionary in _world.connected_map_objects():
		var object: Gen2WorldObject = entry["object"]
		var cells := Vector2(object.cell + (entry["offset"] as Vector2i))
		if here.distance_squared_to(cells * CELL) > CONNECTED_REACH * CONNECTED_REACH:
			continue
		_add_actor(object.sprite, object.palette, object.facing, object.frame, cells)


func _add_actor(
	sprite: Gen2WorldSprite, palette: int, facing: int, frame: int, cells: Vector2,
	colors: PackedColorArray = PackedColorArray(), height_offset: float = 0.0,
	emote: int = Gen2WorldActors.EMOTE_NONE
) -> void:
	var texture: Texture2D = _actor_texture(sprite, palette, facing, frame, colors)
	if texture != null:
		var ground: Vector3 = _ground(cells)
		var stood: Vector3 = _actor_position(ground, height_offset)
		_stage.add_standing_card(texture, stood)
		_stage.add_shadow_caster(texture, ground, 1.0)
		_add_emote(emote, stood)

const EMOTE_SIDE: int = 2 * Gen2Tiles.TILE_WIDTH
const EMOTE_CENTRE: float = 1.5 * EMOTE_SIDE


func _add_emote(emote: int, stood: Vector3) -> void:
	if emote == Gen2WorldActors.EMOTE_NONE:
		return
	var texture: Texture2D = _emote_texture(emote)
	if texture == null:
		return
	_stage.add_centred_card(texture, stood + Vector3(0.0, EMOTE_CENTRE, 0.0))


func _emote_texture(emote: int) -> Texture2D:
	if _world == null or _world.data == null \
			or emote < 0 or emote >= RomLayout.EMOTE_NAMES.size():
		return null
	var key: String = "e%d:%d" % [emote, _time_of_day]
	if _actor_textures.has(key):
		return _actor_textures[key]
	var sheet: Dictionary = _world.data.overworld_effect(RomLayout.EMOTE_NAMES[emote])
	if sheet.is_empty():
		return null
	var tiles: int = int(sheet.get("tiles", 0))
	var indices: PackedByteArray = sheet.get("indices", PackedByteArray())
	if tiles < 4 or indices.size() < tiles * Gen2Tiles.TILE_PIXELS:
		return null
	var palette: PackedColorArray = sheet.get("colors", PackedColorArray())
	if palette.is_empty():
		palette = _world.data.overworld_sprite_palette(
			Gen2WorldEffects.PAL_OW_EMOTE, _time_of_day
		)
	var image := Image.create_empty(EMOTE_SIDE, EMOTE_SIDE, false, Image.FORMAT_RGBA8)
	var width: int = tiles * Gen2Tiles.TILE_WIDTH
	for tile: int in 4:
		var left: int = (tile & 1) * Gen2Tiles.TILE_WIDTH
		var top: int = (tile >> 1) * Gen2Tiles.TILE_HEIGHT
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var index: int = int(indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x])
				if index == 0:
					continue
				image.set_pixel(
					left + x, top + y,
					palette[index] if index < palette.size() else Color.MAGENTA
				)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture


func _actor_position(ground: Vector3, height_offset: float) -> Vector3:
	return ground + Vector3(0.0, height_offset, 0.0)


func _actor_texture(
	sprite: Gen2WorldSprite, palette_override: int, facing: int, frame: int,
	colors: PackedColorArray = PackedColorArray()
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	var key: String = "%d:%d:%d:%d:%d:%d:%s" % [
		sprite.sprite_type, sprite.number, palette, facing, frame, _time_of_day, str(colors),
	]
	if _actor_textures.has(key):
		return _actor_textures[key]
	var image: Image = Gen2WorldSprite.image_for(
		sprite,
		_world.data.overworld_icon_indices(sprite.icon_number) \
			if sprite.sprite_type == Gen2WorldSprite.TYPE_MON_ICON \
			else _world.data.overworld_sprite_indices(sprite.number),
		colors if colors.size() >= 4 \
		else _world.data.overworld_sprite_palette(palette, _time_of_day),
		facing,
		frame,
	)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture

const BATTLER_CENTRE := Vector2(
	(Gen2BattleScreenMap.ENEMY_AT.x + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_WIDTH,
	(Gen2BattleScreenMap.ENEMY_AT.y + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_HEIGHT
)


func _add_encounter_pulse() -> void:
	if _encounters == null or _world == null or _world.data == null:
		return
	var anchor: Variant = _encounters.pulse_anchor()
	if not anchor is Vector2:
		return
	var centre: Vector3 = _ground((anchor as Vector2) / CELL) + Vector3(0.0, CELL * 0.5, 0.0)
	var window: Array = _encounters.pulse_tiles()
	var pair: Array = _encounters.pulse_battler_pair()
	for value: Variant in _encounters.pulse_sprites():
		if not value is Dictionary:
			continue
		var sprite: Dictionary = value
		var at: int = int(sprite.get("tile", 0)) - Gen2BattleAnimObject.BASE_TILE
		if at < 0 or at >= window.size() or not window[at] is Dictionary:
			continue
		var slot: Dictionary = window[at]
		if not slot.has("gfx"):
			continue
		var attributes: int = int(sprite.get("attributes", 0))
		var texture: Texture2D = _pulse_texture(
			int(slot["gfx"]), int(slot["tile"]), attributes, pair
		)
		if texture == null:
			continue
		var offset := Vector2(
			float(int(sprite.get("x", 0)) - 8),
			float(int(sprite.get("y", 0)) - 16)
		) - BATTLER_CENTRE + Vector2(4.0, 4.0)
		_stage.add_centred_card(texture, centre + Vector3(offset.x, -offset.y, 0.0))


func _pulse_texture(
	gfx: int, tile: int, attributes: int, pair: Array
) -> Texture2D:
	var key: String = "%d:%d:%d:%s" % [
		gfx, tile, attributes & (Gen2BattleAnimObject.OAM_SHARED_FLAGS
			| Gen2BattleAnimObject.OAM_PALETTE), str(pair),
	]
	if _pulse_textures.has(key):
		return _pulse_textures[key]
	var strip: PackedByteArray = _world.data.battle_anim_gfx_indices(gfx)
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
		_world.data.battle_object_palette(
			attributes & Gen2BattleAnimObject.OAM_PALETTE, pair
		), true
	)
	if (attributes & Gen2BattleAnimObject.OAM_XFLIP) != 0:
		image.flip_x()
	if (attributes & Gen2BattleAnimObject.OAM_YFLIP) != 0:
		image.flip_y()
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pulse_textures[key] = texture
	return texture


func _bank() -> void:
	var shore: PackedColorArray = _atlas.shore_colors()
	if shore.size() == 2:
		_stage.set_shore_colors(_atlas.background(), shore[0], shore[1])
	_stage.set_bank(
		_mesher.bank_field(), _mesher.bank_world(), _mesher.bank_origin(),
		_mesher.bank_span()
	)
