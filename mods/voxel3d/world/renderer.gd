extends Control

## The world drawn as a voxel diorama instead of a tile page.
##
## Nothing about the world requires the view to be 2D. Maps are node-free
## records, each tileset is one addressable atlas, animated tiles replace atlas
## slots rather than map rectangles, and collision is a permission byte per walk
## cell. This reads exactly what the built-in renderer reads and builds geometry
## out of it, textured from the same tileset art and coloured with the same
## palette rows, so a Johto route looks like a Johto route with no art shipped
## here at all.
##
## It answers [code]uses_hardware_viewport[/code] false, so it gets the screen's
## rectangle at window resolution rather than a 160x144 buffer. Text boxes and
## menus stay hardware pixels over the top: the world gains resolution, the
## interface stays a Game Boy.
##
## It reads the world and never writes it. That is what lets `V` swap the two
## views mid-step without either one being able to tell the other what changed.

const Options: GDScript = preload("../options.gd")
const Steering: GDScript = preload("../steering.gd")

const CELL: float = 16.0

## How opaque the screen draws the FIELD of its own text box over this view.
##
## The cartridge draws that box opaque because the field behind it is opaque
## white; over a map it is a slab across the bottom third of the screen. The
## frame's lines and the glyphs are ink and stay solid whatever this asks for, so
## the text is exactly as readable and the map is still there behind it. See
## Gen2ModHost.RENDERER_INTERFACE_OPACITY_METHOD.
const FIELD_OPACITY: float = 0.75

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING

var _stage: RefCounted = null
var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _rig: RefCounted = null
var _shape: RefCounted = null
var _profile: GDScript = null
var _tile_shape_script: GDScript = null
var _map_source_script: GDScript = null

var _actor_textures: Dictionary = {}
## The tileset the shape resolver was built for. A warp to a map sharing it still
## rebuilds the mesh, because the block grid is what changed; this only says
## whether the resolver has to be replaced too.
var _shape_tileset: int = -1

## How far out the mesh is built, in walk cells, and the cell the built window is
## centred on. Zero cells is the whole map and no window at all;
## [constant Vector2i.MAX] is nothing built yet.
var _draw_cells: int = 0
var _window_centre := Vector2i.MAX
## Whether the map being drawn is out of doors, which decides both how far the
## ground runs past its edge and whether there is a sky behind it at all.
var _outside: bool = true

## How much of a frame the geometry may take while a build is in flight, in
## microseconds. A town is 200 ms whole, which is a visible stop on every warp
## and at the start of every fight; spread over a few frames at four milliseconds
## it is a build nobody can point at. What is already on screen keeps being drawn
## while it runs, so the cost of slicing is that the new map arrives a moment
## late rather than that anything flickers.
const BUILD_BUDGET_USEC: int = 4000
## Whether a slice is in flight, the chunks it has finished so far, and whether
## anything at all is on screen to keep drawing meanwhile. A warp has nothing, so
## a warp shows each chunk as it lands and the map fills in rather than showing a
## hole.
var _building: bool = false
var _standing: bool = false
var _chunks: Array = []
## The water chunks of the same slice, kept apart because they are drawn with
## their own material: see `mesher.gd:take_water`.
var _water: Array = []
var _tufts: Array = []


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)
	_read_options()
	# On the press rather than by polling: the host owns the surfaces the player
	# changes a setting on, and says so.
	Options.listen(_on_option_changed)
	Options.listen_actions(_on_action_changed)


## This view is not made of hardware pixels, so it asks for the layer that is not
## either. See Gen2ModHost.RENDERER_SURFACE_METHOD.
func uses_hardware_viewport() -> bool:
	return false


## The field of the screen's own text box, drawn through rather than over the
## map. See FIELD_OPACITY.
func interface_opacity() -> float:
	return FIELD_OPACITY


## Where that box is, in hardware pixels, on every change and empty when none is
## up. A box covers the bottom third of the screen and the player stands in the
## middle of it, so the shot is pushed up the frame by half of what the box takes
## and the player is in the middle of what is left. The pan eases like any other
## steer. See Gen2ModHost.RENDERER_TEXT_BOX_METHOD.
func set_text_box_rect(rect: Rect2i) -> void:
	_rig.pan_for_text_box(
		0 if rect.size.y <= 0 else rect.position.y, Gen2Screen.HEIGHT
	)


func set_native_size(size_pixels: Vector2i) -> void:
	size = Vector2(size_pixels)
	_stage.container.size = Vector2(size_pixels)


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_rebuild()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_actor_textures.clear()
	_stage.set_time_of_day(_time_of_day)
	# The atlas carries the palette rows, so the whole sheet moves with the clock
	# and the geometry is not touched.
	if _build_atlas():
		_stage.set_texture(_atlas.texture)


## A tileset animation command rewrote one or two atlas slots. Repainting them
## moves every instance of that tile across the whole mesh at once, which is what
## the hardware does; the 2D view's per-cell overdraw is the port's answer to the
## same problem, not the cartridge's.
func refresh_animation() -> void:
	if _world == null:
		return
	if _atlas.refresh_animation(
		_world.data, _world.current_map, _world.current_tileset,
		_time_of_day, _animation
	):
		_apply_background()


func refresh() -> void:
	_frame_camera()
	_rebuild_actors()


## Camera pitch and distance, which is input the world screen has no use for and
## therefore hands over. See Gen2ModHost.RENDERER_INPUT_METHOD.
##
## Implemented here rather than in `_input`: a node in the tree is offered events
## before the screen decides what it needs, so reading them directly would race
## the gameplay keys instead of taking what is left of them.
func handle_world_input(event: InputEvent) -> bool:
	return _rig.handle_input(event)


## The camera is framed every frame rather than only on refresh, because the
## player's position carries a fractional in-flight step, and the actors are
## rebuilt with it so a walk frame advances while a step is being drawn.
func _process(delta: float) -> void:
	_rig.advance(delta)
	_advance_build()
	_recentre_window()
	_frame_camera()
	_rebuild_actors()


## The fallbacks are what a renderer built outside the game gets: a probe or a
## survey tool never ran the entry script, and wants the whole map rather than a
## window around a player it does not have.
func _read_options() -> void:
	_draw_cells = int(Options.value(Options.DISTANCE, 0))
	_rig.set_wheel_sign(int(Options.value(Options.WHEEL, 1)))
	_rig.set_default_pitch(float(Options.value(Options.CAMERA, Options.CAMERA_VALUES[1])))


func _on_option_changed(id: StringName, key: StringName, value: Variant) -> void:
	if id != Options.MOD_ID:
		return
	match key:
		Options.DISTANCE:
			_draw_cells = int(value)
			# Straight to the emit: how far the mesh reaches is the only thing
			# that changed, and what a tile is was resolved once for this map.
			_window_centre = Vector2i.MAX
			_recentre_window()
		Options.WHEEL:
			_rig.set_wheel_sign(int(value))
		Options.CAMERA:
			_rig.set_default_pitch(float(value))
		Options.RECENTRE:
			# A button-kind setting carries no value: the press IS the message.
			_rig.steer(Steering.RESET)


## A control of this mod's own, arriving as the command it means rather than as
## an event. Whether a key, a pad button, a stick past its deadzone or a finger
## on the on-screen pad produced it is the host's business.
func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != Options.MOD_ID or not pressed:
		return
	_rig.steer(key)


func _load_modules() -> Dictionary:
	var root: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	_profile = load("%s/shape/profile.gd" % root)
	_tile_shape_script = load("%s/shape/tile_shape.gd" % root)
	_map_source_script = load("%s/shape/map_source.gd" % root)
	_atlas = (load("%s/shape/atlas.gd" % root) as GDScript).new()
	_mesher = (load("%s/shape/mesher.gd" % root) as GDScript).new()
	_rig = (load("%s/world/camera_rig.gd" % root) as GDScript).new()
	return {"diorama": load("%s/world/diorama.gd" % root)}


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


## Out of doors the void is sky, banded from the palette's own background. Inside
## it is what lies past a wall, which is not air: see `atlas.gd:void_color`.
func _apply_background() -> void:
	if _outside:
		_stage.set_background(_atlas.background(), true)
	else:
		_stage.set_background(_atlas.void_color(), false)


func _rebuild() -> void:
	# Whatever is on screen belongs to the map being left, so it is not something
	# to keep drawing over: the next build publishes each slice as it lands.
	_building = false
	_standing = false
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		return
	var tileset: int = _world.current_tileset.number
	if _shape == null or tileset != _shape_tileset:
		_shape = _tile_shape_script.new(_profile, tileset)
		_shape_tileset = tileset
	# Asked before the atlas, because what is behind a wall depends on it.
	var source: RefCounted = _map_source_script.new(_world)
	_outside = source.outside()
	if _build_atlas():
		_stage.set_texture(_atlas.texture)
	_stage.set_time_of_day(_time_of_day)
	# Resolved once per map, emitted per window: what a tile is and how tall it
	# stands is a fact about the map, and measuring it through the window would
	# make a structure's height depend on where the player was standing.
	_mesher.resolve(source, _shape)
	_window_centre = Vector2i.MAX
	_recentre_window()
	refresh()


## Rebuilds the mesh around the player when they have walked out of the middle of
## what was built, and does nothing at all at FULL distance.
##
## The margin is what keeps this off most steps: a window rebuilt every cell
## would cost more than the whole map does. Emitting is about two thirds of a
## build and resolving is the other third, so a recentre inside one map is the
## cheap part of it, and it is spread over frames on top of that: see
## `_advance_build`.
func _recentre_window() -> void:
	if _world == null or _building or _mesher.size_tiles() == Vector2i.ZERO:
		return
	if _draw_cells <= 0:
		if _window_centre == Vector2i.MAX:
			_window_centre = Vector2i.ZERO
			_stage.set_view_distance(0.0)
			_begin_terrain(Rect2i())
		return
	var at := Vector2i(_world.player_position_cells().floor())
	var margin: int = maxi(4, _draw_cells / 3)
	if _window_centre != Vector2i.MAX \
			and absi(at.x - _window_centre.x) <= margin \
			and absi(at.y - _window_centre.y) <= margin:
		return
	_window_centre = at
	var span: int = _draw_cells * 2 + 1
	_stage.set_view_distance(float(_draw_cells) * CELL)
	_begin_terrain(Rect2i(
		(at - Vector2i(_draw_cells, _draw_cells)) * RomLayout.MAP_BLOCK_CELL_WIDTH,
		Vector2i(span, span) * RomLayout.MAP_BLOCK_CELL_WIDTH
	))


## Starts a sliced build of [param window], and finishes it in `_process`.
func _begin_terrain(window: Rect2i) -> void:
	_chunks = []
	_water = []
	_tufts = []
	if not _mesher.begin_emit(_atlas, window):
		_stage.set_terrain([])
		_stage.set_water([])
		_stage.set_tufts([])
		_standing = false
		return
	_building = true
	_advance_build()


func _advance_build() -> void:
	if not _building:
		return
	var done: bool = _mesher.emit_step(BUILD_BUDGET_USEC)
	_chunks.append_array(_mesher.take_chunks())
	_water.append_array(_mesher.take_water())
	_tufts.append_array(_mesher.take_tufts())
	# Mid-build the new chunks are shown only when there is nothing else to look
	# at, because a half-built map swapped in over a whole one is a hole opening
	# in the middle of the frame rather than a map arriving.
	if done or not _standing:
		_stage.set_terrain(_chunks)
		_stage.set_water(_water)
		_stage.set_tufts(_tufts)
		_stage.set_models(_mesher.take_models())
	if done:
		_building = false
		_standing = true


func _frame_camera() -> void:
	if _world == null:
		return
	var here: Vector3 = _ground(_world.player_position_cells())
	_stage.camera.fov = _rig.fov()
	# A pan moves the eye and what it looks at together, so the picture slides up
	# the frame without the horizon swinging.
	var pan: Vector3 = _rig.pan()
	_stage.aim_camera(here + pan + _rig.offset(), here + pan)


## The committed cell plus any in-flight step, so the view eases into a new cell
## instead of snapping. The logical cell still commits at the start of the step;
## the fraction is presentation only.
##
## The offset is no longer bounded to one cell: an `applymovement` commits every
## cell of its path at once, so while the trail is being drawn an actor is as
## many cells behind as it has left to walk.
func _ground(cells: Vector2) -> Vector3:
	return Vector3(cells.x * CELL + CELL * 0.5, 0.0, cells.y * CELL + CELL * 0.5)


## The map's live objects, rebuilt on each frame because a script can hide, move
## or delete one between two steps, and because a walking actor changes frame
## four times a step.
func _rebuild_actors() -> void:
	if _world == null:
		return
	_stage.begin_cards()
	_stage.begin_shadow_casters()
	for object: Gen2WorldObject in _world.visible_objects():
		_add_actor(
			object.sprite, object.palette, object.facing, object.frame,
			Vector2(object.cell) + object.step_offset_cells()
		)
	_add_actor(
		_world.player_sprite(), _world.player_palette(),
		_world.player_facing, _world.player_walk_frame(),
		_world.player_position_cells()
	)
	_stage.end_cards()
	_stage.end_shadow_casters()


func _add_actor(
	sprite: Gen2WorldSprite, palette: int, facing: int, frame: int, cells: Vector2
) -> void:
	var texture: Texture2D = _actor_texture(sprite, palette, facing, frame)
	if texture != null:
		var ground: Vector3 = _ground(cells)
		_stage.add_standing_card(texture, ground)
		# The same drawing again, at the same size, for the sun alone: an actor
		# turns to the camera and cannot be its own caster.
		_stage.add_shadow_caster(texture, ground, 1.0)


func _actor_texture(
	sprite: Gen2WorldSprite, palette_override: int, facing: int, frame: int
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	var key: String = "%d:%d:%d:%d:%d" % [sprite.number, palette, facing, frame, _time_of_day]
	if _actor_textures.has(key):
		return _actor_textures[key]
	# image_for applies the mirror itself, including frame 3 of down and up,
	# which frame_is_mirrored is the public answer for.
	var image: Image = Gen2WorldSprite.image_for(
		sprite,
		_world.data.overworld_sprite_indices(sprite.number),
		_world.data.overworld_sprite_palette(palette, _time_of_day),
		facing,
		frame,
	)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture
