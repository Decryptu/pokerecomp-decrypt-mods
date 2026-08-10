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
## METERED AGAINST THE DRAWING, not chosen for brightness.
##
## Flat ground carries vertex colour 1.0 and the cartridge's own texel, so what
## lands on it is exactly how far the picture is pushed past the art. At the
## first values it measured about 1.25, and a path texel is already white at 1.0:
## a third of the day frame came out pinned at 255 with nothing above it left to
## draw, which is what reads as a burnt, over-exposed screen.
##
## These put the brightest thing in the frame just under the top. They look like
## a large cut because the output is sRGB encoded, where halving the light
## darkens the picture by about a quarter; nothing here is dim, it is exposed.
const DAY_ENERGY: Array[float] = [0.47, 0.52, 0.32, 0.23]
const DAY_AMBIENT: Array[Color] = [
	Color("#8b8298"), Color("#9aa2b4"), Color("#4a5478"), Color("#2b3350"),
]
## The sky's share. Low on purpose: ambient lands on every face equally, so it is
## the term that flattens the shading and lifts the floor of the picture, and the
## sun is what should be paying for the light.
const AMBIENT_ENERGY: float = 0.28

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
	_environment.ambient_light_energy = AMBIENT_ENERGY
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


## What a drawing gives the sun: an upright card at its ground point, wearing the
## same picture at the same size, put into the depth pass and into nothing else.
##
## Everything drawn on this stage is a flat picture that cannot cast for itself.
## A battler is not even in the 3D scene, being hardware pixels on the layer
## above; an actor card is, but it turns to the camera, so its own shadow would
## be whichever way the shot happened to be pointing. This hands the sun a shape
## that is nobody's view, and one silhouette in the depth pass buys every case at
## once: the shadow lands on the floor, climbs a wall behind it and drapes over a
## ledge, from the same light the terrain already casts by, with no case in the
## code for any of it. A painted ellipse can do none of that, which is why the
## reference dropped its squashed decals for a real pass
## (`.references/DRAMATIC_SHAPE/lib/ShadowMap.lua`).
##
## [param pixel_size] is the caller's, because how big the card has to be is a
## question about where the picture over it was drawn, and only the caller knows
## that.
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


## Which way a caster stands: upright, turned so its face is square to the way
## the sunlight travels.
##
## Not billboarded, and not turned to the camera either. A card lying in the
## plane of the rays casts a LINE, and the shot is aimed from very near the sun's
## own bearing, so a card square to the camera is within a few degrees of exactly
## that: the first attempt drew a dark streak across the grass instead of a
## Pokemon. Square to the sun is the other extreme and the stable one, the whole
## silhouette laid down and stretched along the ground by however low the sun
## sits, at every angle the shot can be swung to. Nobody ever sees the card, so
## which way it faces is free.
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
	# Discarded rather than blended: a blended card writes its whole quad into the
	# depth pass and the battler's shadow is a rectangle. Discarding is what makes
	# the drawing's own outline the edge of the shadow.
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
	# A card turns to the camera, so what it casts is a fact about the shot rather
	# than about the sun, and swinging the camera round swells and pinches it. The
	# caster beside it is what stands in the sun's way instead.
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.shaded = false
	# Discard rather than blend, so two cards at the same depth cannot erase
	# each other's transparent corners.
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actors.add_child(card)
	_cards.append(card)
	_cards_used += 1
	return card
