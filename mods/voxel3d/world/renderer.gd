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

const CELL: float = 16.0

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


func _init() -> void:
	var modules: Dictionary = _load_modules()
	_stage = (modules["diorama"] as GDScript).new()
	add_child(_stage.container)


## This view is not made of hardware pixels, so it asks for the layer that is not
## either. See Gen2ModHost.RENDERER_SURFACE_METHOD.
func uses_hardware_viewport() -> bool:
	return false


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
		_stage.set_background(_atlas.background())


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
	_frame_camera()
	_rebuild_actors()


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
	_stage.set_background(_atlas.background())
	return true


func _rebuild() -> void:
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		_stage.set_terrain(null)
		return
	var tileset: int = _world.current_tileset.number
	if _shape == null or tileset != _shape_tileset:
		_shape = _tile_shape_script.new(_profile, tileset)
		_shape_tileset = tileset
	if _build_atlas():
		_stage.set_texture(_atlas.texture)
	_stage.set_time_of_day(_time_of_day)
	_stage.set_terrain(_mesher.build(_map_source_script.new(_world), _shape, _atlas))
	refresh()


func _frame_camera() -> void:
	if _world == null:
		return
	var here: Vector3 = _ground(_world.player_position_cells())
	_stage.aim_camera(here + _rig.offset(), here)


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


func _add_actor(
	sprite: Gen2WorldSprite, palette: int, facing: int, frame: int, cells: Vector2
) -> void:
	var texture: Texture2D = _actor_texture(sprite, palette, facing, frame)
	if texture != null:
		_stage.add_standing_card(texture, _ground(cells))


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
