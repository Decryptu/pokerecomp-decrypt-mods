extends RefCounted

## The ground the mesh does not reach, drawn flat from the same cartridge data.

const AtlasScript: GDScript = preload("../shape/atlas.gd")
const FarFoliageScript: GDScript = preload("far_foliage.gd")
const FarHousesScript: GDScript = preload("far_houses.gd")
const FarDrawings: GDScript = preload("../shape/far_drawings.gd")
const Profile: GDScript = preload("../shape/profile.gd")

const TILE: float = 8.0
const BLOCK_PIXELS: float = 32.0
const BLOCK_SLOTS: int = 16

const FILL_DEPTH: float = -6.0
const NEAR_DEPTH: float = -4.0
const HERE_DEPTH: float = 0.0

const FILL_SPAN: float = 2.4

const SHEET_LIMIT: int = 32

const CODE: String = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D blocks : filter_nearest, repeat_disable;
uniform sampler2D block_tiles : filter_nearest, repeat_disable;
uniform highp vec2 map_blocks = vec2(0.0, 0.0);
uniform highp vec2 quad_origin = vec2(0.0, 0.0);
uniform highp vec4 hole = vec4(0.0, 0.0, 0.0, 0.0);
uniform highp float border_block = 0.0;
uniform highp float block_count = 1.0;
uniform highp float atlas_rows = 1.0;
uniform bool fill_border = false;
// The water out here is the same water. A far map is a drawing rather than a
// surface, so it has no swell, glint or bank; what it can have is the sky in it,
// which is why the near sea and the far sea used to meet at a hard line. The
// three are that map's own water row: see `atlas.gd:water_colors`.
uniform vec3 water_one : source_color = vec3(0.0);
uniform vec3 water_two : source_color = vec3(0.0);
uniform vec3 water_three : source_color = vec3(0.0);
uniform vec3 sky_horizon : source_color = vec3(0.0);
uniform float water_mix = 0.0;

varying highp vec3 ground;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	highp vec2 world = floor(vec2(ground.x, ground.z));
	// The mesh owns its window whole, holes included: a flat page showing
	// through a crack in the diorama is worse than the crack.
	if (world.x >= hole.x && world.y >= hole.y
		&& world.x < hole.x + hole.z && world.y < hole.y + hole.w) {
		discard;
	}
	highp vec2 local = world - quad_origin;
	highp vec2 at = floor(local / 32.0);
	highp float block = border_block;
	if (at.x >= 0.0 && at.y >= 0.0 && at.x < map_blocks.x && at.y < map_blocks.y) {
		block = floor(texture(blocks, (at + 0.5) / max(map_blocks, vec2(1.0))).r * 255.0 + 0.5);
		if (block < 0.5) {
			block = border_block;
		}
	} else if (!fill_border) {
		discard;
	}
	highp vec2 inside = local - at * 32.0;
	highp vec2 cell = floor(inside / 8.0);
	highp float slot = cell.y * 4.0 + cell.x;
	highp float tile = floor(texture(block_tiles,
		vec2((slot + 0.5) / 16.0, (block + 0.5) / max(block_count, 1.0))).r * 255.0 + 0.5);
	highp vec2 pixel = inside - cell * 8.0;
	highp vec2 sheet = vec2(mod(tile, 16.0), floor(tile / 16.0));
	vec3 texel = texture(atlas, (sheet * 8.0 + pixel + 0.5)
		/ vec2(16.0 * 8.0, max(atlas_rows, 1.0) * 8.0)).rgb;
	// A palette colour is exact, so this is an equality test with room for the
	// last bit of an 8 bit channel and nothing more.
	if (water_mix > 0.0 && (distance(texel, water_one) < 0.01
		|| distance(texel, water_two) < 0.01
		|| distance(texel, water_three) < 0.01)) {
		// The far sea is seen at a grazing angle and nowhere else, which is the
		// one place `water.gd`'s Fresnel has a single answer: its most.
		texel = mix(texel, sky_horizon, water_mix);
	}
	ALBEDO = texel;
}
"""

static var _shader: Shader = null

var root: Node3D = null

var _world: Gen2WorldAPI = null
var _time_of_day: int = 0
var _outside: bool = true
var _hole := Rect2()
var _layers: Array[MeshInstance3D] = []
var _sky_horizon: Color = Color.BLACK
var _water_mix: float = 0.0
var _fill: MeshInstance3D = null
var _quad: PlaneMesh = null
var _foliage: RefCounted = null
var _houses: RefCounted = null
var _walked: Dictionary = {}
var _walk_owed: bool = false
var _stamped := Rect2()
var _sheets: Dictionary = {}
var _blocks: Dictionary = {}
var _here_sheet: RefCounted = null
var _tiles: Dictionary = {}
var _here_blocks: ImageTexture = null
var _here_revision: int = -1


func _init() -> void:
	root = Node3D.new()
	root.name = "FarField"
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	_quad = PlaneMesh.new()
	_quad.orientation = PlaneMesh.FACE_Y
	_fill = _instance()
	root.add_child(_fill)
	_foliage = FarFoliageScript.new()
	root.add_child(_foliage.root)
	_houses = FarHousesScript.new()
	root.add_child(_houses.root)
	root.visible = false


func set_far_tree(mesh: Mesh, material: ShaderMaterial) -> void:
	_foliage.set_tree(mesh, material)


func set_far_trees(on: bool) -> void:
	_foliage.set_enabled(on)
	_houses.set_enabled(on)


func set_foliage_material_maker(maker: Callable) -> void:
	_foliage.set_material_maker(maker)


func configure(
	world: Gen2WorldAPI, time_of_day: int, outside: bool, here: RefCounted = null
) -> void:
	_world = world
	_time_of_day = time_of_day
	_outside = outside
	_here_sheet = here
	_here_blocks = null
	_here_revision = -1
	_hole = Rect2()
	root.visible = outside and world != null and world.current_map != null
	_hide_from(0)


func set_time_of_day(time_of_day: int) -> void:
	if time_of_day == _time_of_day:
		return
	_time_of_day = time_of_day
	_sheets.clear()
	_foliage.forget_cards()
	_houses.forget()


func set_sky(horizon: Color, share: float) -> void:
	_sky_horizon = horizon
	_water_mix = share
	for node: MeshInstance3D in _layers:
		var material := node.material_override as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter(
			&"sky_horizon", Vector3(horizon.r, horizon.g, horizon.b)
		)
		material.set_shader_parameter(&"water_mix", share)


func set_hole(rect: Rect2) -> void:
	_hole = rect


func set_stamped_bounds(rect: Rect2) -> void:
	_stamped = rect


func advance(focus: Vector3, reach: float) -> void:
	if not root.visible or _world == null:
		return
	var map: Gen2WorldMap = _world.current_map
	var tileset: Gen2WorldTileset = _world.current_tileset
	if map == null or tileset == null:
		_hide_from(0)
		return
	var span: float = maxf(reach, BLOCK_PIXELS) * FILL_SPAN
	var seen := Rect2(
		Vector2(focus.x, focus.z) - Vector2(span, span) * 0.5, Vector2(span, span)
	)
	_place_fill(map, tileset, seen)

	var used: int = 0
	var owed: bool = false
	var taken: Array = [_stamped]
	_foliage.begin()
	_houses.begin()
	_walk_owed = false
	for placement: Dictionary in _world.map_placements().values():
		var near: Gen2WorldMap = placement["map"]
		var origin: Vector2 = Vector2(placement["origin"] as Vector2i) * BLOCK_PIXELS
		var size := Vector2(near.width_blocks, near.height_blocks) * BLOCK_PIXELS
		taken.append(Rect2(origin, size))
		if not Rect2(origin, size).intersects(seen):
			continue
		var sheet: RefCounted = _sheet(near, not owed)
		if sheet == null:
			owed = true
			continue
		var layer: MeshInstance3D = _layer(used)
		used += 1
		_dress(layer, sheet, _block_texture(near), _tile_texture(
			_world.data.world_tileset(near.tileset)
		), Vector2(near.width_blocks, near.height_blocks), origin,
			near.border_block, near.tileset, false)
		_stand(layer, origin, size, NEAR_DEPTH)
		var found: Dictionary = _walk_of(near, 0)
		_foliage.place(near, origin, sheet, found.get("drawings", {}), _stamped)
		_houses.place(near, origin, sheet, found.get("buildings", []), _stamped)

	var here: ImageTexture = _here_texture(map)
	if here != null:
		var buffer: float = float(Gen2WorldAPI.BUFFER_BLOCKS)
		var blocks := Vector2(
			map.width_blocks + buffer * 2.0, map.height_blocks + buffer * 2.0
		)
		var origin: Vector2 = Vector2(-buffer, -buffer) * BLOCK_PIXELS
		var layer: MeshInstance3D = _layer(used)
		used += 1
		_dress(layer, _sheet(map, true), here, _tile_texture(tileset), blocks,
			origin, map.border_block, map.tileset, false)
		_stand(layer, origin, blocks * BLOCK_PIXELS, HERE_DEPTH)
		var here_found: Dictionary = _walk_of(map, _ring_tiles())
		_foliage.place(
			map, Vector2.ZERO, _sheet(map, true), here_found.get("drawings", {}), _hole
		)
		_houses.place(
			map, Vector2.ZERO, _sheet(map, true), here_found.get("buildings", []), _hole
		)
	_foliage.place_border(
		_world.data, map, _sheet(map, true), Vector2(focus.x, focus.z), taken
	)
	_foliage.end()
	_houses.end()
	_hide_from(used)


func _walk_of(map: Gen2WorldMap, margin: int) -> Dictionary:
	var key: String = "%d:%d:%d" % [map.group, map.number, margin]
	if _walked.has(key):
		return _walked[key]
	if _walk_owed:
		return {}
	_walk_owed = true
	if _walked.size() >= SHEET_LIMIT:
		_walked.clear()
	_walked[key] = FarDrawings.of_map(_world.data, map, Profile, margin)
	return _walked[key]


func _ring_tiles() -> int:
	if not _stamped.has_area():
		return 0
	return int(-_stamped.position.x / TILE)


func _place_fill(map: Gen2WorldMap, tileset: Gen2WorldTileset, seen: Rect2) -> void:
	_dress(_fill, _sheet(map, true), _one_block(), _tile_texture(tileset),
		Vector2.ZERO, Vector2.ZERO, map.border_block, map.tileset, true)
	_stand(_fill, seen.position, seen.size, FILL_DEPTH)


func _instance() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = _shader
	node.material_override = material
	node.visible = false
	return node


func _layer(index: int) -> MeshInstance3D:
	while _layers.size() <= index:
		var node: MeshInstance3D = _instance()
		_layers.append(node)
		root.add_child(node)
	return _layers[index]


func _hide_from(index: int) -> void:
	for at: int in range(index, _layers.size()):
		_layers[at].visible = false


func _stand(node: MeshInstance3D, at: Vector2, size: Vector2, depth: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		node.visible = false
		return
	node.scale = Vector3(size.x, 1.0, size.y)
	node.position = Vector3(at.x + size.x * 0.5, depth, at.y + size.y * 0.5)
	node.visible = true
	(node.material_override as ShaderMaterial).set_shader_parameter(
		&"hole", Vector4(_hole.position.x, _hole.position.y, _hole.size.x, _hole.size.y)
	)


func _dress(
	node: MeshInstance3D, sheet: RefCounted, blocks: ImageTexture,
	tiles: ImageTexture, map_blocks: Vector2, origin: Vector2,
	border_block: int, tileset_number: int, fill_border: bool
) -> void:
	if sheet == null or blocks == null or tiles == null:
		node.visible = false
		return
	var material := node.material_override as ShaderMaterial
	material.set_shader_parameter(&"atlas", sheet.texture)
	material.set_shader_parameter(&"blocks", blocks)
	material.set_shader_parameter(&"block_tiles", tiles)
	material.set_shader_parameter(&"map_blocks", map_blocks)
	material.set_shader_parameter(&"quad_origin", origin)
	material.set_shader_parameter(&"border_block", float(border_block))
	material.set_shader_parameter(&"block_count", float(maxi(
		_block_count(tileset_number), 1
	)))
	material.set_shader_parameter(&"atlas_rows", float(maxi(
		sheet.texture.get_height() / int(TILE), 1
	)))
	material.set_shader_parameter(&"fill_border", fill_border)
	var water: PackedColorArray = sheet.water_colors()
	for index: int in 3:
		var colour: Color = water[index] if index < water.size() else Color.BLACK
		material.set_shader_parameter(
			[&"water_one", &"water_two", &"water_three"][index],
			Vector3(colour.r, colour.g, colour.b)
		)
	material.set_shader_parameter(
		&"sky_horizon", Vector3(_sky_horizon.r, _sky_horizon.g, _sky_horizon.b)
	)
	material.set_shader_parameter(&"water_mix", _water_mix)


func _block_count(tileset_number: int) -> int:
	var tileset: Gen2WorldTileset = _world.data.world_tileset(tileset_number)
	return tileset.block_count if tileset != null else 1


func _sheet(map: Gen2WorldMap, may_build: bool) -> RefCounted:
	if _here_sheet != null and _world.current_map == map:
		return _here_sheet
	var key: String = "%d:%d" % [map.group, map.number]
	if _sheets.has(key):
		return _sheets[key]
	if not may_build:
		return null
	if _sheets.size() >= SHEET_LIMIT:
		_sheets.clear()
	var tileset: Gen2WorldTileset = _world.data.world_tileset(map.tileset)
	if tileset == null:
		return null
	var sheet: RefCounted = AtlasScript.new()
	if not sheet.build(_world.data, map, tileset, _time_of_day):
		return null
	_sheets[key] = sheet
	return sheet


func _block_texture(map: Gen2WorldMap) -> ImageTexture:
	var key: String = "%d:%d" % [map.group, map.number]
	if not _blocks.has(key):
		_blocks[key] = _bytes_texture(
			map.blocks, Vector2i(map.width_blocks, map.height_blocks)
		)
	return _blocks[key]


func _here_texture(map: Gen2WorldMap) -> ImageTexture:
	if _here_blocks != null and _here_revision == _world.block_revision:
		return _here_blocks
	var buffer: int = Gen2WorldAPI.BUFFER_BLOCKS
	var span := Vector2i(
		map.width_blocks + buffer * 2, map.height_blocks + buffer * 2
	)
	if span.x <= 0 or span.y <= 0:
		return null
	var bytes := PackedByteArray()
	bytes.resize(span.x * span.y)
	for y: int in span.y:
		var row: int = y * span.x
		for x: int in span.x:
			bytes[row + x] = _world.drawn_block_at(x - buffer, y - buffer) & 0xFF
	_here_blocks = _bytes_texture(bytes, span)
	_here_revision = _world.block_revision
	return _here_blocks


func _tile_texture(tileset: Gen2WorldTileset) -> ImageTexture:
	if tileset == null:
		return null
	if _tiles.has(tileset.number):
		return _tiles[tileset.number]
	var count: int = maxi(tileset.block_count, 1)
	var bytes := PackedByteArray()
	bytes.resize(BLOCK_SLOTS * count)
	for at: int in bytes.size():
		var index: int = tileset.meta[at] if at < tileset.meta.size() else 0
		bytes[at] = index if index < tileset.tile_count else 0
	_tiles[tileset.number] = _bytes_texture(bytes, Vector2i(BLOCK_SLOTS, count))
	return _tiles[tileset.number]


func _one_block() -> ImageTexture:
	if not _blocks.has("void"):
		_blocks["void"] = _bytes_texture(PackedByteArray([0]), Vector2i.ONE)
	return _blocks["void"]


static func _bytes_texture(bytes: PackedByteArray, size: Vector2i) -> ImageTexture:
	if size.x <= 0 or size.y <= 0:
		return null
	var padded: PackedByteArray = bytes
	if padded.size() != size.x * size.y:
		padded = bytes.duplicate()
		padded.resize(size.x * size.y)
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, padded)
	)
