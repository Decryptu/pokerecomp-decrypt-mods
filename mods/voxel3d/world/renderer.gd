extends SubViewportContainer

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

## World pixels per walk cell, which is the unit the whole mod measures in.
const CELL: float = 16.0

## Light colour per time of day, in the order Gen2WorldPalette names them:
## morning, day, night, dark.
const DAY_LIGHT: Array[Color] = [
	Color(1.0, 0.94, 0.86), Color(1.0, 1.0, 0.98),
	Color(0.72, 0.76, 1.0), Color(0.45, 0.5, 0.7),
]
const DAY_ENERGY: Array[float] = [1.05, 1.15, 0.7, 0.5]
const DAY_AMBIENT: Array[Color] = [
	Color("#8b8298"), Color("#9aa2b4"), Color("#4a5478"), Color("#2b3350"),
]

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _environment: Environment = null
var _terrain: MeshInstance3D = null
var _actors: Node3D = null

var _atlas: RefCounted = null
var _mesher: RefCounted = null
var _rig: RefCounted = null
var _shape: RefCounted = null
var _profile: GDScript = null
var _tile_shape_script: GDScript = null

var _material: StandardMaterial3D = null
var _actor_textures: Dictionary = {}
## The tileset the current mesh was built from. A warp back to a map sharing it
## still rebuilds, because the block grid is what changed; this only says whether
## the shape resolver has to be replaced too.
var _shape_tileset: int = -1


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_modules()
	_build_scene()


## This view is not made of hardware pixels, so it asks for the layer that is not
## either. See Gen2ModHost.RENDERER_SURFACE_METHOD.
func uses_hardware_viewport() -> bool:
	return false


## A stretching SubViewportContainer owns its viewport's size and refuses a
## manual one, so setting the container is the whole of it.
func set_native_size(size_pixels: Vector2i) -> void:
	size = Vector2(size_pixels)


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_rebuild()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, DAY_LIGHT.size() - 1)
	_actor_textures.clear()
	_apply_daylight()
	# The atlas carries the palette rows, so the whole sheet moves with the
	# clock and the geometry does not have to be touched.
	if _atlas.build(_world, _time_of_day, _animation):
		_material.albedo_texture = _atlas.texture
		_apply_background()


## A tileset animation command rewrote one or two atlas slots. Repainting them
## moves every instance of that tile across the whole mesh at once, which is what
## the hardware does; the 2D view's per-cell overdraw is the port's answer to the
## same problem, not the cartridge's.
func refresh_animation() -> void:
	if _atlas.refresh_animation(_world, _time_of_day, _animation):
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
## player's position carries a fractional in-flight step and a camera that only
## moved when the world told it to would follow in whole cells.
func _process(delta: float) -> void:
	_rig.advance(delta)
	_frame_camera()


func _load_modules() -> void:
	var root: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	_profile = load("%s/shape/profile.gd" % root)
	_tile_shape_script = load("%s/shape/tile_shape.gd" % root)
	_atlas = (load("%s/shape/atlas.gd" % root) as GDScript).new()
	_mesher = (load("%s/shape/mesher.gd" % root) as GDScript).new()
	_rig = (load("%s/world/camera_rig.gd" % root) as GDScript).new()


func _build_scene() -> void:
	_viewport = SubViewport.new()
	# Its own 3D world, so this never shares a scene with whatever else the
	# screen has open.
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var holder := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_energy = 0.75
	holder.environment = _environment
	_viewport.add_child(holder)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	_viewport.add_child(_light)

	_camera = Camera3D.new()
	_camera.fov = 42.0
	# A route is a few thousand world pixels across and the camera sits a couple
	# of hundred back, so the default 4000 unit limit would clip the far edge.
	_camera.far = 8000.0
	_viewport.add_child(_camera)

	_material = StandardMaterial3D.new()
	# The atlas is 8 texels of art over 8 world pixels, one texel per pixel, so
	# any filtering at all smears the drawing the geometry is made of.
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Face shading arrives as vertex colour, multiplied into the texel.
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_terrain = MeshInstance3D.new()
	_terrain.material_override = _material
	_viewport.add_child(_terrain)

	_actors = Node3D.new()
	_viewport.add_child(_actors)

	_apply_daylight()


func _rebuild() -> void:
	if _world == null or _world.current_map == null or _world.current_tileset == null:
		_terrain.mesh = null
		return
	var tileset: int = _world.current_tileset.number
	if _shape == null or tileset != _shape_tileset:
		_shape = _tile_shape_script.new(_profile, tileset)
		_shape_tileset = tileset
	if _atlas.build(_world, _time_of_day, _animation):
		_material.albedo_texture = _atlas.texture
		_apply_background()
	_terrain.mesh = _mesher.build(_world, _shape, _atlas)
	refresh()


func _apply_daylight() -> void:
	if _light == null:
		return
	_light.light_color = DAY_LIGHT[_time_of_day]
	_light.light_energy = DAY_ENERGY[_time_of_day]
	_environment.ambient_light_color = DAY_AMBIENT[_time_of_day]


## The sky takes the palette's own background colour, which is the same colour
## the 2D view fills its margins with, so the two views end at the same place.
func _apply_background() -> void:
	if _environment == null:
		return
	_environment.background_color = _atlas.background().darkened(0.35)


func _frame_camera() -> void:
	if _world == null or _camera == null:
		return
	var here: Vector3 = _player_position()
	# look_at_from_position rather than position plus look_at: the host may hand
	# a world over before the node has entered the tree, and look_at refuses
	# outside it.
	_camera.look_at_from_position(here + _rig.offset(), here, Vector3.UP)


## The committed cell plus any in-flight step, so the view eases into a new cell
## instead of snapping. The logical cell still commits at the start of the step;
## the fraction is presentation only.
func _player_position() -> Vector3:
	var cells: Vector2 = _world.player_position_cells()
	return Vector3(cells.x * CELL + CELL * 0.5, 0.0, cells.y * CELL + CELL * 0.5)


## The map's live objects, rebuilt on each refresh because a script can hide,
## move or delete one between two steps.
func _rebuild_actors() -> void:
	if _actors == null:
		return
	for child: Node in _actors.get_children():
		_actors.remove_child(child)
		child.queue_free()
	for object: Gen2WorldObject in _world.visible_objects():
		var offset: Vector2 = object.step_offset_cells()
		_add_actor(
			object.sprite, object.palette, object.facing, object.frame,
			Vector2(object.cell) + offset
		)
	_add_actor(
		_world.player_sprite(), _world.player_palette(), _world.player_facing, 0,
		_world.player_position_cells()
	)


## One 16x16 overworld sprite standing on its cell.
##
## A card facing the camera, not a voxel model: the drawing is already a
## three-quarter view of a person, and standing it up flat keeps every frame the
## cartridge drew. Y is fixed so a card leans with the pitch rather than lying
## down when the camera goes overhead.
func _add_actor(
	sprite: Gen2WorldSprite, palette: int, facing: int, frame: int, cells: Vector2
) -> void:
	var texture: Texture2D = _actor_texture(sprite, palette, facing, frame)
	if texture == null:
		return
	var card := Sprite3D.new()
	card.texture = texture
	card.pixel_size = 1.0
	card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.shaded = false
	# Discard rather than blend, so two cards at the same depth cannot erase
	# each other's transparent corners.
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	card.position = Vector3(
		cells.x * CELL + CELL * 0.5, CELL * 0.5, cells.y * CELL + CELL * 0.5
	)
	_actors.add_child(card)


func _actor_texture(
	sprite: Gen2WorldSprite, palette_override: int, facing: int, frame: int
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	var key: String = "%d:%d:%d:%d:%d" % [sprite.number, palette, facing, frame, _time_of_day]
	if _actor_textures.has(key):
		return _actor_textures[key]
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
