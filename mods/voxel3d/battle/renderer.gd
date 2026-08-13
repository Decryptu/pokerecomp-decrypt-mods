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

const Options: GDScript = preload("../options.gd")

const CELL: float = 16.0

## How opaque the screen draws the FIELD of its own text box over this view, and
## the same judgement the overworld makes: the frame's lines and the glyphs are
## ink and stay solid, so the prompt reads exactly as well and the fight is still
## visible behind it. Every prompt in a battle is that one box.
##
## The panels above it are this renderer's own and are tinted separately; see
## PANEL_TINT.
const FIELD_OPACITY: float = 0.75

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

## The two HUD blocks, in hardware tiles, and how far past the drawing their
## backing reaches. Derived from `Gen2BattleHud`'s own positions: the enemy's
## name, level and bar sit between column 1 and its edge tile, the player's
## between its bottom-left corner and the right edge, with the exp bar sunk into
## the last row.
const ENEMY_PANEL := Rect2i(1, 0, 11, 4)
const PLAYER_PANEL := Rect2i(9, 7, 11, 5)
const PANEL_PAD: int = 2

## How solid the backing is over the world behind it.
##
## The cartridge draws its panels as black glyphs straight onto the white field,
## with no box: the field IS the backing. Take the field away and put a route
## under it and the name, the level and the HP numbers are black on grass. So
## each block gets one, and deliberately a light one: the point of this view is
## seeing where you are standing, and an opaque slab in the corner of the frame
## is the white field back again under another name.
const PANEL_TINT := Color(1.0, 1.0, 1.0, 0.52)

var _hud: Gen2BattleHud = null
var _panels_backing: Array[ColorRect] = []
var _hud_layers: Array[TextureRect] = []
var _battlers: Array[TextureRect] = []
var _pic_textures: Dictionary = {}
var _native := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
## How far out from the fight the map is meshed, in walk cells. Zero is all of
## it. The player's own DISTANCE setting, shared with the overworld.
var _draw_cells: int = 0


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)
	# The backing goes in first, so both panels sit under every drawn layer.
	for panel: Rect2i in [ENEMY_PANEL, PLAYER_PANEL]:
		var backing := ColorRect.new()
		backing.color = PANEL_TINT
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.set_meta(&"tiles", panel)
		add_child(backing)
		_panels_backing.append(backing)
	for index: int in 4:
		var layer := TextureRect.new()
		# Nearest, or the hardware pixels stop being square on the last hop.
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_hud_layers.append(layer)
	_read_options()
	Options.listen(_on_option_changed)


func uses_hardware_viewport() -> bool:
	return false


## See FIELD_OPACITY. `set_text_box_rect` is deliberately not answered here: the
## rig pins each battler to its own hardware picture slot, which is what makes a
## collision with the box impossible, so there is nothing left for this view to
## compose around it.
func interface_opacity() -> float:
	return FIELD_OPACITY


## The fallback is the whole map, which is what a probe or a tool building this
## renderer outside the game wants.
func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_arena.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			_build_arena()
		Options.WHEEL:
			_arena.set_wheel_sign(int(value))


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
	_frame_camera()
	_place_battlers()
	_draw_hud()


## Steering the shot. The battle screen claims its own keys first, so what
## arrives here is what the fight has no use for.
func handle_battle_input(event: InputEvent) -> bool:
	return _arena.handle_input(event)


## Framed every frame rather than only when the tween is running, so no ordering
## between the context, the first view and the tree can leave the shot stale.
func _process(delta: float) -> void:
	_arena.advance(delta)
	_frame_camera()
	_place_battlers()


func _root() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()


func _load_modules() -> Dictionary:
	var root: String = _root()
	_profile = load("%s/shape/profile.gd" % root)
	_tile_shape_script = load("%s/shape/tile_shape.gd" % root)
	_map_source_script = load("%s/shape/map_source.gd" % root)
	_atlas = (load("%s/shape/atlas.gd" % root) as GDScript).new()
	_arena = (load("%s/battle/arena.gd" % root) as GDScript).new()
	return {"diorama": load("%s/world/diorama.gd" % root)}


## The map the battle started on, rebuilt from its records.
##
## The context names the map and its tileset by number and deliberately hands
## over no handle on the world, so this resolves them through the GameData it was
## already given and meshes them exactly as the overworld does.
func _build_arena() -> void:
	if _data == null or _context == null:
		_stage.set_terrain([])
		_arena.stage(null)
		return
	var map: Gen2WorldMap = _data.world_map(_context.map_group(), _context.map_number())
	var tileset: Gen2WorldTileset = _data.world_tileset(_context.tileset)
	if map == null or tileset == null:
		_stage.set_terrain([])
		_arena.stage(null)
		return

	var source: RefCounted = _map_source_script.new(null, map, tileset)
	_stage.set_time_of_day(_context.time_of_day)
	if _atlas.build(_data, map, tileset, _context.time_of_day):
		_stage.set_texture(_atlas.texture)
		# A fight indoors is shot against the room's own walls, not against sky.
		if source.outside():
			_stage.set_background(_atlas.background(), true)
		else:
			_stage.set_background(_atlas.void_color(), false)
	# Resolved whole and emitted around the fight. A fight does not move, so the
	# window is built once and never recentred; the sight lines the arena is
	# chosen by read the resolved heights, which are the whole map's whatever is
	# drawn of it.
	_mesher = _resolved_for(map, tileset, source)
	_stage.set_view_distance(float(_draw_cells) * CELL)
	_stage.set_terrain(_mesher.emit(_atlas, _window(_context.player_cell)))
	# Staged AFTER the mesh, because choosing where the fight goes asks how tall
	# the things around it turned out to be, and only the mesh knows that.
	_arena.stage(_context, source, _mesher)
	# The arena has just moved, so the shot has to. Waiting for the next view
	# leaves the camera wherever it was last framed, which before any battle is
	# the map's own origin: a corner of the map with the fight nowhere in it.
	_frame_camera()
	_place_battlers()


## The map resolved, from a fight earlier in the same session where there was
## one. Resolving is the third of a build that does not depend on where anything
## is standing, and a trainer battled on the same route twice pays it twice
## otherwise. Kept per installation of this script, so it survives the renderer
## being built again between fights.
##
## Only the battle caches. The overworld resolves from the LIVE world, which
## `changeblock` rewrites under the player, and a cache with no word from the
## host about that would draw a boulder that has been pushed away.
static var _resolved: Dictionary = {}
const RESOLVED_KEPT: int = 2


func _resolved_for(
	map: Gen2WorldMap, tileset: Gen2WorldTileset, source: RefCounted
) -> RefCounted:
	var key: String = "%d,%d,%d" % [map.group, map.number, tileset.number]
	if _resolved.has(key):
		return _resolved[key]
	var mesher: RefCounted = (load("%s/shape/mesher.gd" % _root()) as GDScript).new()
	mesher.resolve(source, _tile_shape_script.new(_profile, tileset.number))
	if _resolved.size() >= RESOLVED_KEPT:
		_resolved.erase(_resolved.keys()[0])
	_resolved[key] = mesher
	return mesher


## The rectangle of map the fight is drawn out of, in TILES, or empty for the
## whole of it at FULL distance.
##
## The battle's lens is a 23.6 degree cone across a 46 pixel frame, so what it
## can see of a map is a narrow wedge and a window costs the shot far less than
## it costs the overworld's wide one.
func _window(cell: Vector2i) -> Rect2i:
	if _draw_cells <= 0:
		return Rect2i()
	var span: int = _draw_cells * 2 + 1
	return Rect2i(
		(cell - Vector2i(_draw_cells, _draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	)


func _frame_camera() -> void:
	_stage.camera.fov = _arena.fov(_frame_stretch())
	_stage.aim_camera(_arena.eye(), _arena.target())


## How much taller the stage is than the hardware screen drawn over it.
##
## The stage fills the window; the panels fill a 160x144 rectangle at a whole
## number of window pixels per hardware pixel, centred in it. Stretching the lens
## by the difference is what makes one window pixel mean the same thing on both
## layers, so a battler pinned to its patch of ground lands in the hardware slot
## the rig was solved for at every window size instead of only at the ones where
## the two happen to coincide.
func _frame_stretch() -> float:
	return float(_native.y) / float(Gen2Screen.HEIGHT * _hud_scale())


## The two battlers, and the opposing trainer behind theirs.
##
## Each picture is PINNED to its patch of ground: it is drawn in hardware pixels
## at the place that patch projects to, at the size the cartridge drew it. That
## is what keeps a battler crisp, and it is what the rig was solved to land in
## the hardware's own picture slots, so nothing here can wander under a panel or
## the text box.
##
## `player_pic_visible` is the cartridge's own answer for the stretch before the
## back picture is placed. There is no intro slide out here, but honouring it is
## what keeps the player's Pokemon off the field until it has been sent out.
func _place_battlers() -> void:
	_stage.begin_shadow_casters()
	var slot: int = 0
	if StringName(_view.get("battle_kind", &"wild")) == &"trainer":
		slot = _pin(
			slot, _trainer_pic(int(_view.get("trainer_class", 0))),
			_arena.enemy_trainer_ground()
		)
	slot = _pin(slot, _pic(int(_view.get("enemy_species", 0)), false), _arena.enemy_ground())
	if bool(_view.get("player_pic_visible", true)):
		slot = _pin(slot, _pic(int(_view.get("player_species", 0)), true), _arena.player_ground())
	for index: int in range(slot, _battlers.size()):
		_battlers[index].visible = false
	_stage.end_shadow_casters()


## One picture standing on [param ground], its feet at that point and its middle
## over it, at a whole-number scale so a Game Boy pixel stays square.
##
## The place is the STAGE's, not the panels': a pinned picture belongs to the
## patch of ground under it, so it is drawn where that patch projects to in the
## 3D view. Both layers are centred on the same window and the rig frames the
## same world height, so a battler landing on its ground point is also landing in
## the hardware slot the rig was solved for.
func _pin(slot: int, texture: Texture2D, ground: Vector3) -> int:
	if texture == null:
		return slot
	var at: Vector2 = _stage.camera.unproject_position(ground)
	var drawn := Vector2(texture.get_size()) * float(_hud_scale())
	var rect: TextureRect = _battler(slot)
	rect.texture = texture
	rect.size = drawn
	rect.position = at - Vector2(drawn.x * 0.5, drawn.y)
	rect.visible = true
	_stage.add_shadow_caster(texture, ground, _caster_scale(ground, texture.get_height()))
	return slot + 1


## How big a card standing on [param ground] has to be for the sun to see the
## same silhouette the player does: the world height whose projection is the
## [param height] hardware pixels the picture is drawn at.
##
## Measured through the camera rather than derived, because the answer moves with
## every zoom, climb and swing, and solved twice because it is the card's OWN
## height that has to project correctly and a pitched camera changes depth up its
## length. One correction is enough at these sizes; the first pass is already
## within a few percent.
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
		# Under the panels, over the map: the hardware draws its pictures into
		# the same background layer the panels sit on top of.
		add_child(rect)
		move_child(rect, 1 + _battlers.size())
		_battlers.append(rect)
	return _battlers[slot]


## One battler's picture, cropped to what it fills and cut out of its field, so
## it stands on the map rather than in a white box.
func _pic(species: int, back: bool) -> Texture2D:
	if _data == null or species <= 0:
		return null
	return _texture(
		"%d:%d" % [species, 1 if back else 0],
		_data.species_pic(species, back),
		_data.palette(species),
	)


## The opposing trainer's own picture, in the cartridge's art. A class number is
## what the pic and the palette are both keyed on, and a wild battle carries
## class 0, which is what makes this answer nothing there.
func _trainer_pic(trainer_class: int) -> Texture2D:
	if _data == null or trainer_class <= 0:
		return null
	return _texture(
		"t%d" % trainer_class,
		_data.trainer_pic(trainer_class),
		_data.trainer_palette(trainer_class),
	)


func _texture(key: String, pic: Dictionary, palette: PackedColorArray) -> Texture2D:
	if _pic_textures.has(key):
		return _pic_textures[key]
	var image: Image = _cut_out(pic, palette)
	if image == null:
		return null
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_pic_textures[key] = texture
	return texture


## The pic with its FIELD removed, rather than its background colour.
##
## A battle pic is drawn on the white field, and the field is colour index 0. So
## is every white inside the drawing: an eye highlight, a tooth, a Marill's belly,
## the whole of a white Pokemon. Making index 0 transparent wherever it appears
## punches holes straight through the animal, which is what the cartridge never
## has to care about because it draws the field behind it.
##
## What is outside is not a colour, it is a REGION: the field is the index 0 that
## connects to the edge of the picture. Flooding in from the border through index
## 0 alone stops dead at the drawing's own black outline, so the highlights
## sealed inside it survive and only the field is cut away. A drawing whose
## silhouette touches the border simply keeps the corner the flood cannot reach,
## which is the safe way round.
func _cut_out(pic: Dictionary, palette: PackedColorArray) -> Image:
	if pic.is_empty() or not pic.has("atlas"):
		return null
	var name: String = String(pic["atlas"])
	var atlas: Dictionary = _data.atlas(name)
	var indices: PackedByteArray = _data.atlas_indices(name)
	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return null
	var width: int = mini(int(pic.get("width", cell)), cell)
	var height: int = mini(int(pic.get("height", cell)), cell)
	if width <= 0 or height <= 0:
		return null

	var left: int = (slot % columns) * cell
	@warning_ignore("integer_division")
	var top: int = (slot / columns) * cell
	var pixels := PackedByteArray()
	pixels.resize(width * height)
	for y: int in height:
		var from: int = (top + y) * atlas_width + left
		if from + width > indices.size():
			break
		for x: int in width:
			pixels[y * width + x] = indices[from + x]

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

	# Trimmed to what is actually drawn. A pic sits in the top-left of a cell
	# sized for the largest of its kind, and a trainer's own drawing rarely
	# reaches the bottom of one, so a card standing on its cell stands on blank
	# rows and the figure floats above the ground.
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	return image.get_region(used)


## The index 0 reachable from the border, four-connected: everything the drawing
## does not enclose.
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
		for backing: ColorRect in _panels_backing:
			backing.visible = false
		return
	for backing: ColorRect in _panels_backing:
		backing.visible = true

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
	@warning_ignore("integer_division")
	return maxi(1, mini(
		_native.x / Gen2Screen.WIDTH, _native.y / Gen2Screen.HEIGHT
	))


func _hud_origin() -> Vector2:
	var factor: int = _hud_scale()
	var drawn := Vector2(Gen2Screen.WIDTH * factor, Gen2Screen.HEIGHT * factor)
	return ((Vector2(_native) - drawn) * 0.5).floor()


## An HP bar is green, yellow or red by how much of it is lit rather than by the
## hit points behind it, which is the rule the games use.
func _hp_palette(hp: int, max_hp: int) -> PackedColorArray:
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE
	)
	return _data.bar_palette(GameData.hp_bar_palette_name(lit))
