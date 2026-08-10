extends RefCounted

## The 3D stage both views are built on: a viewport of its own, the daylight, the
## terrain mesh and the material it is drawn with.
##
## Owning this in one place is what lets a battle be staged on the map. The
## overworld and the fight are the same geometry, the same tileset texture and
## the same time of day; what differs is where the camera stands and what else is
## in the scene, and that is all the two renderers hold themselves.

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

var container: SubViewportContainer = null
var viewport: SubViewport = null
var camera: Camera3D = null
var actors: Node3D = null

var _light: DirectionalLight3D = null
var _environment: Environment = null
var _terrain: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING


func _init() -> void:
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport = SubViewport.new()
	# Its own 3D world, so this never shares a scene with whatever else the
	# screen has open.
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var holder := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_energy = 0.75
	holder.environment = _environment
	viewport.add_child(holder)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	# A diorama with no shadows reads as flat colour: the whole point of standing
	# the drawings up is that they sit ON something.
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 600.0
	# The geometry is axis-aligned boxes on a flat plane, which is the shape that
	# shows shadow acne worst; a normal bias rather than a depth one keeps the
	# contact edge where the box meets the ground.
	_light.shadow_normal_bias = 1.5
	viewport.add_child(_light)

	camera = Camera3D.new()
	camera.fov = 42.0
	# A route is a couple of thousand world pixels across, so the default 4000
	# unit limit would clip its far edge.
	camera.far = 8000.0
	viewport.add_child(camera)

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
	viewport.add_child(_terrain)

	actors = Node3D.new()
	viewport.add_child(actors)

	set_time_of_day(_time_of_day)


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, DAY_LIGHT.size() - 1)
	_light.light_color = DAY_LIGHT[_time_of_day]
	_light.light_energy = DAY_ENERGY[_time_of_day]
	_environment.ambient_light_color = DAY_AMBIENT[_time_of_day]


func time_of_day() -> int:
	return _time_of_day


func set_terrain(mesh: ArrayMesh) -> void:
	_terrain.mesh = mesh


func set_texture(texture: Texture2D) -> void:
	_material.albedo_texture = texture


## The sky takes the palette's own background, which is the colour the 2D view
## fills its margins with, so the two end at the same place.
func set_background(color: Color) -> void:
	_environment.background_color = color.darkened(0.35)


## look_at_from_position rather than a position plus look_at: a renderer may be
## handed its world before the node has entered the tree, and look_at refuses
## outside it.
##
## An up vector parallel to the view has no basis to build, which a camera driven
## almost straight down reaches; north stands in for it there, so a near-overhead
## shot rolls to a stop rather than spinning.
func aim_camera(eye: Vector3, target: Vector3) -> void:
	var direction: Vector3 = target - eye
	if direction.length_squared() < 0.001:
		return
	var up := Vector3.UP
	if absf(direction.normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	camera.look_at_from_position(eye, target, up)


## Cards are POOLED rather than rebuilt. The overworld re-places every actor each
## frame, because a walking one changes drawing four times a step, and building a
## node per actor per frame churns a few thousand nodes a second for a scene that
## only ever moves the same dozen.
var _cards: Array[Sprite3D] = []
var _cards_used: int = 0


func begin_cards() -> void:
	_cards_used = 0


## One flat drawing standing on the map, its feet on [param ground] rather than
## its centre, which is what every drawing in the game wants.
##
## A card facing the camera, not a voxel model: a Game Boy drawing of a person or
## a Pokemon is already a three-quarter view of one, and standing it up flat
## keeps every frame the cartridge drew. Y is fixed so a card leans with the
## camera's pitch rather than lying down when the camera goes overhead.
func add_standing_card(
	texture: Texture2D, ground: Vector3, pixel_size: float = 1.0
) -> Sprite3D:
	var card: Sprite3D = _card()
	card.texture = texture
	card.pixel_size = pixel_size
	card.position = ground + Vector3(0.0, texture.get_height() * pixel_size * 0.5, 0.0)
	card.visible = true
	return card


func end_cards() -> void:
	for index: int in range(_cards_used, _cards.size()):
		_cards[index].visible = false


## A soft blob on the ground under something that is drawn rather than modelled.
##
## A battler is a flat picture pinned to the ground it stands on, so it casts no
## shadow of its own and reads as pasted onto the map. One dark ellipse under it
## is what puts it back on the floor, and it is what the eye actually reads a
## contact shadow as anyway.
func add_blob_shadow(at: Vector3, radius: float) -> void:
	var blob: Sprite3D = _blob()
	blob.pixel_size = radius * 2.0 / float(BLOB_PIXELS)
	# A whisker above the ground: coplanar with it, the two z-fight.
	blob.position = at + Vector3(0.0, 0.05, 0.0)
	blob.visible = true


func end_blob_shadows() -> void:
	for index: int in range(_blobs_used, _blobs.size()):
		_blobs[index].visible = false


func begin_blob_shadows() -> void:
	_blobs_used = 0


const BLOB_PIXELS: int = 32
var _blobs: Array[Sprite3D] = []
var _blobs_used: int = 0
var _blob_texture: Texture2D = null


func _blob() -> Sprite3D:
	if _blobs_used < _blobs.size():
		var existing: Sprite3D = _blobs[_blobs_used]
		_blobs_used += 1
		return existing
	var blob := Sprite3D.new()
	blob.texture = _blob_art()
	# Laid flat on the ground rather than billboarded, so it is a shadow on the
	# floor and not a disc following the camera.
	blob.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	blob.shaded = false
	blob.transparent = true
	blob.modulate = Color(0.0, 0.0, 0.0, 0.34)
	# Blended rather than discarded, and never written to depth: a hard-edged
	# cut-out would read as a painted disc, and a shadow that occludes is not a
	# shadow.
	blob.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	blob.no_depth_test = false
	actors.add_child(blob)
	_blobs.append(blob)
	_blobs_used += 1
	return blob


func _blob_art() -> Texture2D:
	if _blob_texture != null:
		return _blob_texture
	var image: Image = Image.create(BLOB_PIXELS, BLOB_PIXELS, false, Image.FORMAT_RGBA8)
	var middle: float = float(BLOB_PIXELS - 1) * 0.5
	for y: int in BLOB_PIXELS:
		for x: int in BLOB_PIXELS:
			var away: float = Vector2(x - middle, y - middle).length() / middle
			# Squared falloff: a linear one has a visible rim where it reaches
			# zero, which reads as an outline rather than as a shadow.
			var strength: float = clampf(1.0 - away, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, strength * strength))
	_blob_texture = ImageTexture.create_from_image(image)
	return _blob_texture


func _card() -> Sprite3D:
	if _cards_used < _cards.size():
		var existing: Sprite3D = _cards[_cards_used]
		_cards_used += 1
		return existing
	var card := Sprite3D.new()
	card.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.shaded = false
	# Discard rather than blend, so two cards at the same depth cannot erase
	# each other's transparent corners.
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actors.add_child(card)
	_cards.append(card)
	_cards_used += 1
	return card
