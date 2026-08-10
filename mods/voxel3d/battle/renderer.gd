extends Control

## The fight staged on the map it was started on, shot over the player's
## shoulder, with the Game Boy's own panels over the top.
##
## `Gen2BattleScreen` owns the battle, the events and the text box, and decides
## nothing about how any of it is drawn. It hands over display values and, once
## per battle, a `Gen2BattleWorldContext` saying where the encounter happened.
## That is the whole of what this needs: the same mesher the overworld uses
## rebuilds the map from its records, and the two battlers stand on it as cards.
##
## Two layers, because a battle is two different things at once. The map is
## geometry at window resolution; the panels, the bars and the text box are
## hardware pixels and stay that way, drawn at whole-number scale over the top so
## a Game Boy pixel is still a square. Answering `uses_hardware_viewport` false
## is what makes the first layer possible, and it makes the second this
## renderer's own job rather than the screen's.
##
## A battle started outside the world gets no context and is drawn on the flat
## field the panels already imply.

const CELL: float = 16.0
## Species pics are up to 56 pixels across and stand about three walk cells tall
## on the map, which is the scale that reads as a creature rather than a poster.
const PIC_SCALE: float = 0.86

var _data: GameData = null
var _view: Dictionary = {}
var _context: Gen2BattleWorldContext = null

var _stage: RefCounted = null
var _arena: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _profile: GDScript = null
var _tile_shape_script: GDScript = null
var _map_source_script: GDScript = null

var _hud: Gen2BattleHud = null
var _hud_layers: Array[TextureRect] = []
var _pic_textures: Dictionary = {}
var _native := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)
	for index: int in 4:
		var layer := TextureRect.new()
		# Nearest, or the hardware pixels stop being square on the last hop.
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_hud_layers.append(layer)


func uses_hardware_viewport() -> bool:
	return false


func set_native_size(size_pixels: Vector2i) -> void:
	_native = size_pixels
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)
	_layout_hud()


func set_battle_data(data: GameData) -> bool:
	_data = data
	if data == null:
		return false
	_hud = Gen2BattleHud.from_data(data)
	return _hud != null


## Where the battle is being fought, handed over once, after set_battle_data and
## before the first view. Optional on both sides: a battle with no world behind
## it never calls this and the arena stays the flat field.
func set_world_context(context: Gen2BattleWorldContext) -> void:
	_context = context
	_build_arena()


func set_view(view: Dictionary) -> void:
	_view = view
	refresh()


func refresh() -> void:
	_place_battlers()
	_frame_camera()
	_draw_hud()


## Steering the shot. The battle screen claims its own keys first, so what
## arrives here is what the fight has no use for.
func handle_battle_input(event: InputEvent) -> bool:
	return _arena.handle_input(event)


func _process(delta: float) -> void:
	if _arena.advance(delta):
		_frame_camera()


func _load_modules() -> Dictionary:
	var root: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	_profile = load("%s/shape/profile.gd" % root)
	_tile_shape_script = load("%s/shape/tile_shape.gd" % root)
	_map_source_script = load("%s/shape/map_source.gd" % root)
	_atlas = (load("%s/shape/atlas.gd" % root) as GDScript).new()
	_mesher = (load("%s/shape/mesher.gd" % root) as GDScript).new()
	_arena = (load("%s/battle/arena.gd" % root) as GDScript).new()
	return {"diorama": load("%s/world/diorama.gd" % root)}


## The map the battle started on, rebuilt from its records.
##
## The context names the map and its tileset by number and deliberately hands
## over no handle on the world, so this resolves them through the GameData it was
## already given and meshes them exactly as the overworld does.
func _build_arena() -> void:
	if _data == null or _context == null:
		_stage.set_terrain(null)
		_arena.stage(null)
		return
	var map: Gen2WorldMap = _data.world_map(_context.map_group(), _context.map_number())
	var tileset: Gen2WorldTileset = _data.world_tileset(_context.tileset)
	if map == null or tileset == null:
		_stage.set_terrain(null)
		_arena.stage(null)
		return

	var source: RefCounted = _map_source_script.new(null, map, tileset)
	# The arena is composed against the same collision the mesh is built from,
	# so the ground the two battlers stand on is ground in the geometry too.
	_arena.stage(_context, source)
	_stage.set_time_of_day(_context.time_of_day)
	if _atlas.build(_data, map, tileset, _context.time_of_day):
		_stage.set_texture(_atlas.texture)
		_stage.set_background(_atlas.background())
	_stage.set_terrain(_mesher.build(
		source, _tile_shape_script.new(_profile, tileset.number), _atlas
	))


## How the boom is shortened, in samples from the shot's own eye back toward the
## arena, and how far above a wall the eye has to clear to count as outside it.
const BOOM_SAMPLES: int = 14
const BOOM_CLEARANCE: float = 10.0
## Never closer to the arena than this, or the eye ends up inside a battler.
const BOOM_MINIMUM: float = 0.4


func _frame_camera() -> void:
	_stage.camera.fov = _arena.fov()
	var target: Vector3 = _arena.target()
	_stage.aim_camera(_boom(target, _arena.eye()), target)


## The eye pulled in until nothing stands between it and the arena.
##
## A fight is often started with a wall, a tree line or a house at the player's
## back, and an eye composed several cells behind them ends up looking at the
## inside of a facade. Walking OUT from the arena and stopping at the first
## sample the terrain rises through is what makes backing into a wall walk the
## camera up to the battlers' shoulders instead of through it.
##
## Testing the whole segment rather than the seat alone is the part that matters:
## an eye composed high enough clears every wall in the game and still has one
## between it and what it is looking at.
func _boom(target: Vector3, eye: Vector3) -> Vector3:
	if _mesher == null:
		return eye
	var clear: float = BOOM_MINIMUM
	for step: int in range(1, BOOM_SAMPLES + 1):
		var fraction: float = float(step) / float(BOOM_SAMPLES)
		if fraction < BOOM_MINIMUM:
			continue
		var at: Vector3 = target + (eye - target) * fraction
		if at.y <= float(_mesher.height_at_position(at)) + BOOM_CLEARANCE:
			break
		clear = fraction
	var seat: Vector3 = target + (eye - target) * clear
	# A fight started in a walled-in cell has nowhere for the boom to go, and the
	# minimum leaves the eye inside whatever is there. Lifting it clear of that
	# column turns the worst case into a shot from above rather than one from
	# inside a wall.
	seat.y = maxf(seat.y, float(_mesher.height_at_position(seat)) + BOOM_CLEARANCE)
	return seat


## The two battlers, as cards standing on the arena's ground.
##
## `player_pic_visible` is the cartridge's own answer for the stretch before the
## back pic is placed, which is the intro slide; there is no slide out here, but
## honouring it is what keeps the player's Pokemon off the field until it has
## been sent out.
func _place_battlers() -> void:
	_stage.begin_cards()
	var enemy: Texture2D = _pic(int(_view.get("enemy_species", 0)), false)
	if enemy != null:
		_stage.add_standing_card(enemy, _arena.enemy_ground(), PIC_SCALE)
	if bool(_view.get("player_pic_visible", true)):
		var player: Texture2D = _pic(int(_view.get("player_species", 0)), true)
		if player != null:
			_stage.add_standing_card(player, _arena.player_ground(), PIC_SCALE)
	_stage.end_cards()


## One battler's picture, cropped to what it actually fills and with the
## cartridge's own background index made transparent, so it stands on the map
## rather than in a white box.
func _pic(species: int, back: bool) -> Texture2D:
	if _data == null or species <= 0:
		return null
	var key: String = "%d:%d" % [species, 1 if back else 0]
	if _pic_textures.has(key):
		return _pic_textures[key]
	var pic: Dictionary = _data.species_pic(species, back)
	if pic.is_empty():
		return null
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(String(pic["atlas"])),
		_data.atlas(String(pic["atlas"])),
		pic,
		_data.palette(species),
		true,
	)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pic_textures[key] = texture
	return texture


## The panels and the three bars, each in its own palette because the hardware
## gives every background tile one: a green HP bar sits inside a panel of black
## text without either being a separate rectangle.
##
## `hud_visible` is false for the length of a move animation, which is
## `BattleAnimClearHud` taking all four off the map.
func _draw_hud() -> void:
	if _hud == null:
		return
	if not bool(_view.get("hud_visible", true)):
		for layer: TextureRect in _hud_layers:
			layer.texture = null
		return

	var enemy_hp: int = int(_view.get("enemy_hp", 0))
	var enemy_max_hp: int = int(_view.get("enemy_max_hp", 0))
	var player_hp: int = int(_view.get("player_hp", 0))
	var player_max_hp: int = int(_view.get("player_max_hp", 0))

	var panels: PackedByteArray = _buffer()
	_hud.draw_enemy(
		panels, Gen2Screen.WIDTH, String(_view.get("enemy_name", "")),
		int(_view.get("enemy_level", 0))
	)
	_hud.draw_player(
		panels, Gen2Screen.WIDTH, String(_view.get("player_name", "")),
		int(_view.get("player_level", 0)), player_hp, player_max_hp
	)
	_show(0, panels, Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])))

	var enemy_bar: PackedByteArray = _buffer()
	_hud.draw_hp_bar(
		enemy_bar, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, enemy_hp, enemy_max_hp
	)
	_show(1, enemy_bar, _hp_palette(enemy_hp, enemy_max_hp))

	var player_bar: PackedByteArray = _buffer()
	_hud.draw_hp_bar(
		player_bar, Gen2Screen.WIDTH, Gen2BattleHud.PLAYER_BAR, player_hp, player_max_hp
	)
	_show(2, player_bar, _hp_palette(player_hp, player_max_hp))

	var gained: PackedByteArray = _buffer()
	_hud.draw_exp_bar(gained, Gen2Screen.WIDTH, int(_view.get("exp_pixels", 0)))
	_show(3, gained, _data.bar_palette("exp"))


func _buffer() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	return out


## Index 0 is transparent on every layer: a panel is a shape over the map, not a
## rectangle of white across it.
func _show(index: int, indices: PackedByteArray, palette: PackedColorArray) -> void:
	_hud_layers[index].texture = ImageTexture.create_from_image(
		Gen2PicImage.from_indices(
			indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
		)
	)
	_layout_layer(_hud_layers[index])


## The hardware screen at the largest whole-number scale that fits, centred. A
## fractional scale would put a Game Boy pixel across a screen pixel boundary and
## the panels would shimmer as the window resized.
func _layout_hud() -> void:
	for layer: TextureRect in _hud_layers:
		_layout_layer(layer)


func _layout_layer(layer: TextureRect) -> void:
	var scale_factor: int = maxi(1, mini(
		_native.x / Gen2Screen.WIDTH, _native.y / Gen2Screen.HEIGHT
	))
	var drawn := Vector2(
		Gen2Screen.WIDTH * scale_factor, Gen2Screen.HEIGHT * scale_factor
	)
	layer.size = drawn
	layer.position = ((Vector2(_native) - drawn) * 0.5).floor()


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))
