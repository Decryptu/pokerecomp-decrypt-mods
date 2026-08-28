extends RefCounted

## The 3D stage both views are built on: a viewport of its own, the daylight,
## the terrain mesh and the material it is drawn with.

const Sky3D: GDScript = preload("sky.gd")
const Water3D: GDScript = preload("water.gd")
const Wind3D: GDScript = preload("wind.gd")
const Frame3D: GDScript = preload("frame.gd")
const Motes3D: GDScript = preload("motes.gd")
const FarField3D: GDScript = preload("far_field.gd")

const CELL: float = 16.0

const DAY_LIGHT: Array[Color] = [
	Color(1.0, 0.94, 0.86), Color(1.0, 1.0, 0.98),
	Color(0.72, 0.76, 1.0), Color(0.45, 0.5, 0.7),
]
const DAY_ENERGY: Array[float] = [0.58, 0.52, 0.38, 0.29]
const DAY_AMBIENT: Array[Color] = [
	Color("#8b8298"), Color("#9aa2b4"), Color("#4a5478"), Color("#2b3350"),
]
const SUN_ROTATION: Array[Vector3] = [
	Vector3(-40.0, 42.0, 0.0), Vector3(-58.0, -35.0, 0.0),
	Vector3(-46.0, -62.0, 0.0), Vector3(-42.0, -62.0, 0.0),
]
const AMBIENT_ENERGY: float = 0.28

const FAR_DEFAULT: float = 8000.0
const SHADOW_DISTANCE_DEFAULT: float = 600.0

const ONE_SPLIT_REACH: float = 256.0

const HAZE_BEGIN: float = 1400.0
const HAZE_END: float = 5200.0
const HAZE_CURVE: float = 2.0
const HAZE_DENSITY: float = 0.85

var container: SubViewportContainer = null
var viewport: SubViewport = null
var _pass_viewport: SubViewport = null
var _pass_screen: TextureRect = null
var camera: Camera3D = null
var actors: Node3D = null

var _light: DirectionalLight3D = null
var _environment: Environment = null
var _sky: RefCounted = null
var _terrain: Array[MeshInstance3D] = []
var _material: StandardMaterial3D = null
var _water: Array[MeshInstance3D] = []
var _water_shader: RefCounted = null
var _tufts: Array[MeshInstance3D] = []
var _wind: RefCounted = null
var _frame: RefCounted = null
var _models: Array[MultiMeshInstance3D] = []
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _motes: RefCounted = null
var _motes_node: MultiMeshInstance3D = null
var _far: RefCounted = null
var _reach: float = FAR_DEFAULT


func _init() -> void:
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_pass_viewport = SubViewport.new()
	_pass_viewport.transparent_bg = false
	_pass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_pass_viewport)

	_pass_screen = TextureRect.new()
	_pass_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pass_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_viewport.add_child(_pass_screen)
	_pass_viewport.size_changed.connect(_on_pass_resized)

	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pass_screen.add_child(viewport)

	var holder := WorldEnvironment.new()
	_environment = Environment.new()
	_sky = Sky3D.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = _sky.sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.ambient_light_energy = AMBIENT_ENERGY
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = HAZE_BEGIN
	_environment.fog_depth_end = HAZE_END
	_environment.fog_depth_curve = HAZE_CURVE
	_environment.fog_density = HAZE_DENSITY
	_environment.fog_sky_affect = 0.0
	holder.environment = _environment
	viewport.add_child(holder)
	viewport.size_changed.connect(_on_viewport_resized)

	_light = DirectionalLight3D.new()
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = SHADOW_DISTANCE_DEFAULT
	_light.shadow_normal_bias = 1.5
	viewport.add_child(_light)

	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = FAR_DEFAULT
	viewport.add_child(camera)

	_material = StandardMaterial3D.new()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_water_shader = Water3D.new()
	_wind = Wind3D.new()
	_frame = Frame3D.new()
	_pass_screen.material = _frame.material

	actors = Node3D.new()
	viewport.add_child(actors)

	_far = FarField3D.new()
	_far.set_foliage_material_maker(foliage_material)
	viewport.add_child(_far.root)

	_motes = Motes3D.new()
	_motes_node = MultiMeshInstance3D.new()
	_motes_node.multimesh = _motes.mesh
	_motes_node.material_override = _motes.material
	_motes_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(_motes_node)

	set_time_of_day(_time_of_day)


func set_time_of_day(row: int) -> void:
	_time_of_day = clampi(row, 0, DAY_LIGHT.size() - 1)
	_light.light_color = DAY_LIGHT[_time_of_day]
	_light.light_energy = DAY_ENERGY[_time_of_day]
	_light.rotation_degrees = SUN_ROTATION[_time_of_day]
	_water_shader.set_sun(
		-_light.global_transform.basis.z if _light.is_inside_tree()
			else -_light.transform.basis.z,
		DAY_LIGHT[_time_of_day] * DAY_ENERGY[_time_of_day]
	)
	_environment.ambient_light_color = DAY_AMBIENT[_time_of_day]
	_motes.set_time_of_day(_time_of_day)
	_motes_node.visible = _motes.drifting()
	_frame.set_time_of_day(_time_of_day)


func time_of_day() -> int:
	return _time_of_day


func set_flash(maps: Variant) -> void:
	_frame.set_flash(maps)


func set_grayscale(graying: bool) -> void:
	_frame.set_grayscale(graying)


func set_interface_mask(screen: Rect2i, masked: bool) -> void:
	var whole: Vector2 = container.size
	if not masked or screen.size.x <= 0 or screen.size.y <= 0 \
			or whole.x <= 0.0 or whole.y <= 0.0:
		_frame.set_interface_mask(Vector4(0.0, 0.0, 1.0, 1.0), false)
		return
	_frame.set_interface_mask(Vector4(
		float(screen.position.x) / whole.x, float(screen.position.y) / whole.y,
		float(screen.end.x) / whole.x, float(screen.end.y) / whole.y
	), true)


func set_view_distance(pixels: float, horizon: bool = false) -> void:
	if pixels <= 0.0:
		camera.far = FAR_DEFAULT
		_set_shadow_reach(SHADOW_DISTANCE_DEFAULT)
		_reach = FAR_DEFAULT
		return
	camera.far = FAR_DEFAULT if horizon else minf(FAR_DEFAULT, pixels * 2.0)
	_set_shadow_reach(minf(SHADOW_DISTANCE_DEFAULT, pixels))
	_reach = camera.far


func _set_shadow_reach(pixels: float) -> void:
	_light.directional_shadow_max_distance = pixels
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL \
		if pixels <= ONE_SPLIT_REACH else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func set_render_scale(divisor: int) -> void:
	container.stretch_shrink = clampi(divisor, 1, 4)


func set_pass_enabled(enabled: bool) -> void:
	_pass_screen.material = _frame.material if enabled else null


func set_depth_of_field(
	mode: int, radius: float, near: float = 900.0, far: float = 2600.0
) -> void:
	_frame.set_depth_of_field(mode, radius, near, far)


func set_eye_for_depth_of_field(eye: Vector3, focus: Vector3) -> void:
	var reach: Vector3 = focus - eye
	var flat: float = Vector2(reach.x, reach.z).length()
	_frame.set_eye(
		maxf(eye.y - focus.y, 1.0),
		atan2(maxf(eye.y - focus.y, 0.001), maxf(flat, 0.001)),
		deg_to_rad(camera.fov)
	)


func foliage_material(cutout: Texture2D) -> ShaderMaterial:
	return _wind.sprite_material(cutout) if cutout != null else _wind.foliage


func far_field() -> RefCounted:
	return _far


func advance_far_field(focus: Vector3) -> void:
	_far.advance(focus, _reach)


func set_terrain(meshes: Array) -> void:
	for index: int in meshes.size():
		if index >= _terrain.size():
			var instance := MeshInstance3D.new()
			instance.material_override = _material
			viewport.add_child(instance)
			_terrain.append(instance)
		_terrain[index].mesh = meshes[index]
		_terrain[index].visible = true
	for index: int in range(meshes.size(), _terrain.size()):
		_terrain[index].mesh = null
		_terrain[index].visible = false


func set_models(models: Array) -> void:
	for index: int in models.size():
		if index >= _models.size():
			var instance := MultiMeshInstance3D.new()
			viewport.add_child(instance)
			_models.append(instance)
		var cutout: Texture2D = models[index][3] as Texture2D \
			if models[index].size() > 3 else null
		_models[index].material_override = _wind.sprite_material(cutout) \
			if cutout != null else _wind.foliage
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.use_colors = true
		multi.mesh = models[index][0]
		var placements: Array[Transform3D] = models[index][1]
		var phases: PackedFloat32Array = models[index][2]
		multi.instance_count = placements.size()
		for spot: int in placements.size():
			multi.set_instance_transform(spot, placements[spot])
			multi.set_instance_custom_data(spot, Color(phases[spot], 0.0, 0.0, 0.0))
			multi.set_instance_color(spot, Color.WHITE)
		_models[index].multimesh = multi
		_models[index].visible = true
	for index: int in range(models.size(), _models.size()):
		_models[index].multimesh = null
		_models[index].visible = false


func set_bank(field: Texture2D, world: Vector2, origin: Vector2, span: float) -> void:
	_water_shader.set_bank(field, world, origin, span)


func set_shore_colors(foam: Color, shallow: Color, deep: Color) -> void:
	_water_shader.set_shore_colors(foam, shallow, deep)


func set_water(meshes: Array) -> void:
	for index: int in meshes.size():
		if index >= _water.size():
			var instance := MeshInstance3D.new()
			instance.material_override = _water_shader.material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			viewport.add_child(instance)
			_water.append(instance)
		_water[index].mesh = meshes[index]
		_water[index].visible = true
	for index: int in range(meshes.size(), _water.size()):
		_water[index].mesh = null
		_water[index].visible = false


func set_tufts(meshes: Array) -> void:
	for index: int in meshes.size():
		if index >= _tufts.size():
			var instance := MeshInstance3D.new()
			instance.material_override = _wind.grass
			viewport.add_child(instance)
			_tufts.append(instance)
		_tufts[index].mesh = meshes[index]
		_tufts[index].visible = true
	for index: int in range(meshes.size(), _tufts.size()):
		_tufts[index].mesh = null
		_tufts[index].visible = false


func set_walker(at: Vector3) -> void:
	_wind.set_walker(at)


func set_texture(texture: Texture2D) -> void:
	if _material.albedo_texture == texture:
		return
	_material.albedo_texture = texture
	_water_shader.set_atlas(texture)
	_wind.set_atlas(texture)


func set_background(
	color: Color, outside: bool = true, ramp: PackedColorArray = PackedColorArray()
) -> void:
	_sky.set_background(color, outside, ramp)
	_environment.fog_enabled = outside
	_environment.fog_light_color = _sky.horizon
	_frame.set_outside(outside)
	_water_shader.set_sky(_sky.horizon, _sky.zenith)
	if _far != null:
		_far.set_sky(_sky.horizon, Water3D.REFLECT_MOST if outside else 0.0)
	_motes.set_outside(outside)
	_motes_node.visible = _motes.drifting()


func _on_pass_resized() -> void:
	var size: Vector2i = _pass_viewport.size
	if size.x <= 0 or size.y <= 0:
		return
	viewport.size = size
	_pass_screen.size = Vector2(size)
	_pass_screen.texture = viewport.get_texture()


func _on_viewport_resized() -> void:
	_sky.set_frame(Vector2(viewport.size))


func aim_camera(eye: Vector3, target: Vector3) -> void:
	_motes_node.position = target
	var direction: Vector3 = target - eye
	if direction.length_squared() < 0.001:
		return
	var up := Vector3.UP
	if absf(direction.normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	camera.look_at_from_position(eye, target, up)
	if _frame.wants_eye():
		set_eye_for_depth_of_field(eye, target)

var _cards: Array[Sprite3D] = []
var _cards_used: int = 0


func begin_cards() -> void:
	_cards_used = 0


func add_standing_card(
	texture: Texture2D, ground: Vector3, pixel_size: float = 1.0
) -> Sprite3D:
	var card: Sprite3D = _card()
	card.texture = texture
	card.pixel_size = pixel_size
	card.position = ground + Vector3(0.0, texture.get_height() * pixel_size * 0.5, 0.0)
	card.visible = true
	return card


func add_centred_card(
	texture: Texture2D, centre: Vector3, pixel_size: float = 1.0
) -> Sprite3D:
	var card: Sprite3D = _card()
	card.texture = texture
	card.pixel_size = pixel_size
	card.position = centre
	card.visible = true
	return card


func end_cards() -> void:
	for index: int in range(_cards_used, _cards.size()):
		_cards[index].visible = false


func add_shadow_caster(texture: Texture2D, ground: Vector3, pixel_size: float) -> void:
	var caster: Sprite3D = _caster()
	caster.texture = texture
	caster.pixel_size = pixel_size
	caster.position = ground + Vector3(0.0, texture.get_height() * pixel_size * 0.5, 0.0)
	caster.rotation.y = _sun_bearing()
	caster.visible = true


func begin_shadow_casters() -> void:
	_casters_used = 0


func end_shadow_casters() -> void:
	for index: int in range(_casters_used, _casters.size()):
		_casters[index].visible = false

var _casters: Array[Sprite3D] = []
var _casters_used: int = 0


func _sun_bearing() -> float:
	var toward: Vector3 = -_light.transform.basis.z
	return atan2(toward.x, toward.z)


func _caster() -> Sprite3D:
	if _casters_used < _casters.size():
		var existing: Sprite3D = _casters[_casters_used]
		_casters_used += 1
		return existing
	var caster := Sprite3D.new()
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	caster.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	caster.shaded = false
	actors.add_child(caster)
	_casters.append(caster)
	_casters_used += 1
	return caster


func _card() -> Sprite3D:
	if _cards_used < _cards.size():
		var existing: Sprite3D = _cards[_cards_used]
		_cards_used += 1
		return existing
	var card := Sprite3D.new()
	card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.shaded = false
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actors.add_child(card)
	_cards.append(card)
	_cards_used += 1
	return card
