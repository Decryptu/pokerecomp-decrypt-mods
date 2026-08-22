extends RefCounted

## THE GROUND THE MESH DOES NOT REACH, drawn flat from the same cartridge data.
##
## A voxel mesh is bounded twice over. The DISTANCE setting builds a window
## around the player and nothing outside it, and even at FULL the map ends at
## its border ring and the skirt past that, so the world stops a few hundred
## world pixels out and the sky begins. On a screen the size of a Game Boy's
## that edge was never in the frame. On a window-filling one, at a low camera,
## pulled back, it is.
##
## So past the mesh the ground carries on as one flat surface per map, folded on
## the GPU exactly as the host's own `Gen2WorldMapLayer` folds the 2D view:
## block byte, `$00` to the map's border block, metatile slot, tile, texel.
## Which maps go where is the host's `map_placements`, the same connection graph
## the 2D view is drawn from, so the two agree about what is over the hill.
##
## IT IS ALSO THE LEVEL OF DETAIL. Where the window cuts, what carries on is the
## same map with its height thrown away, which is what a Game Boy drew in the
## first place: the near ground is a diorama and the far ground is the page it
## was read off. Nothing is baked, so the strip the tile animation repaints is
## the one this samples.
##
## Out of doors only. A room ends at its walls and there is no horizon in it.

const AtlasScript: GDScript = preload("../shape/atlas.gd")
const FarFoliageScript: GDScript = preload("far_foliage.gd")

const TILE: float = 8.0
const BLOCK_PIXELS: float = 32.0
## Metatile slots in a block, and the row length of the metatile table.
const BLOCK_SLOTS: int = 16
## Tiles across the atlas sheet. `atlas.gd:TILES_PER_ROW`, restated because a
## shader needs it as a number rather than as a constant it cannot read.
const ATLAS_TILES_PER_ROW: float = 16.0

## How far under the ground plane each layer sits, in world pixels. The mesh
## owns everything from zero up; these are only ever seen where it drew nothing,
## and they are stacked rather than sorted so the depth buffer decides which is
## in front and no render priority has to.
const FILL_DEPTH: float = -6.0
const NEAR_DEPTH: float = -4.0
const HERE_DEPTH: float = -2.0

## How far past the camera's own reach the border fill is laid, as a multiple of
## it. The quad is centred on what the camera looks at rather than on the map,
## so it has to cover the far plane in every direction from there.
const FILL_SPAN: float = 2.4

## How many neighbouring maps' sheets are kept at once. Past it the lot is
## dropped and repainted as they are asked for again, one a frame.
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

varying highp vec3 ground;

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	highp vec2 world = floor(vec2(ground.x, ground.z));
	// The mesh owns its own window whole, holes in it included: a flat page
	// showing through a crack in the diorama standing on it is worse than the
	// crack.
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
	ALBEDO = texture(atlas, (sheet * 8.0 + pixel + 0.5)
		/ vec2(16.0 * 8.0, max(atlas_rows, 1.0) * 8.0)).rgb;
}
"""

## One compiled program for every layer: the uniforms differ per map, the code
## never does.
static var _shader: Shader = null

var root: Node3D = null

var _world: Gen2WorldAPI = null
var _time_of_day: int = 0
var _outside: bool = true
var _hole := Rect2()
## The layer pool, re-pointed rather than rebuilt: a recentre moves the hole and
## nothing else about what is drawn out there.
var _layers: Array[MeshInstance3D] = []
var _fill: MeshInstance3D = null
var _quad: PlaneMesh = null
## The trees standing on the pages. See `far_foliage.gd`.
var _foliage: RefCounted = null
## Per map, keyed "group:number": its coloured tile sheet, its block bytes.
## Built one a frame, because a sheet is a hundred tiles painted a pixel at a
## time and twenty four maps of them on the frame of a warp is the stop this
## whole view spends a build budget to avoid.
var _sheets: Dictionary = {}
var _blocks: Dictionary = {}
## The loaded map's sheet, handed over rather than painted. See [method configure].
var _here_sheet: RefCounted = null
## Per tileset: the metatile table as sixteen bytes a block.
var _tiles: Dictionary = {}
## The loaded map's own buffer, which `changeblock` moves, and the revision it
## was read at.
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
	# Nothing until a world says there is one: a battle shares this stage and
	# is staged inside the window it stands in.
	root.visible = false


## The cut-out drawing the maps on the horizon stand, and the material carrying
## it. Handing it null is what leaves the far ground bare, which is what shipped.
## See `far_foliage.gd`.
func set_far_tree(mesh: Mesh, material: ShaderMaterial) -> void:
	_foliage.set_tree(mesh, material)


## A new map, or none. Everything keyed on a map is dropped with it except the
## sheets, which are keyed by map and shared with whatever the next one connects
## to: walking from a route into the town at the end of it keeps the route's.
func configure(
	world: Gen2WorldAPI, time_of_day: int, outside: bool, here: RefCounted = null
) -> void:
	_world = world
	_time_of_day = time_of_day
	_outside = outside
	# The loaded map's sheet is the renderer's own, not a second copy of it: it
	# is already painted, and it is the one a tileset animation repaints, so the
	# flowers past the window open with the flowers inside it.
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
	# A sheet is the tileset coloured by the hour, so every one of them moves.
	_sheets.clear()


## The ground the mesh is drawing, in WORLD PIXELS, which this leaves alone.
func set_hole(rect: Rect2) -> void:
	_hole = rect


## Lays the layers out for this frame, and pays for at most one map's sheet.
##
## [param focus] is what the camera is looking at and [param reach] its far
## plane, which together are the whole of what decides which maps are worth
## drawing: one that cannot be in the frame is not placed and its sheet is never
## painted.
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
	_foliage.begin()
	for placement: Dictionary in _world.map_placements().values():
		var near: Gen2WorldMap = placement["map"]
		var origin: Vector2 = Vector2(placement["origin"] as Vector2i) * BLOCK_PIXELS
		var size := Vector2(near.width_blocks, near.height_blocks) * BLOCK_PIXELS
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
		# The skyline on the page. See `far_foliage.gd`; it draws nothing until
		# a tree has been handed to it.
		_foliage.place(_world.data, near, origin)

	# The loaded map LAST, over the neighbours, for the reason the host draws it
	# last too: inside `wOverworldMapBlocks` the connection strips are the
	# cartridge's own and stop where the macro stored, and a neighbour drawn
	# whole does not.
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
	_foliage.end()
	_hide_from(used)


## The border fill: one quad over everything the camera can reach, every pixel
## of it this map's own border block, which is what the cartridge surrounds a
## map with and what the host fills the far window with.
func _place_fill(map: Gen2WorldMap, tileset: Gen2WorldTileset, seen: Rect2) -> void:
	_dress(_fill, _sheet(map, true), _one_block(), _tile_texture(tileset),
		Vector2.ZERO, Vector2.ZERO, map.border_block, map.tileset, true)
	_stand(_fill, seen.position, seen.size, FILL_DEPTH)


func _instance() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad
	# Flat ground a long way off neither casts nor takes a shadow, and the sun's
	# own reach is held to the window the mesh was built for.
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


## A quad is one shared mesh, so where it goes and how big it is are the node's
## own scale and position rather than the mesh's size.
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


func _block_count(tileset_number: int) -> int:
	var tileset: Gen2WorldTileset = _world.data.world_tileset(tileset_number)
	return tileset.block_count if tileset != null else 1


## One map's coloured tile sheet, or null when it has not been painted yet and
## [param may_build] says this frame is not the one to pay for it.
func _sheet(map: Gen2WorldMap, may_build: bool) -> RefCounted:
	if _here_sheet != null and _world.current_map == map:
		return _here_sheet
	var key: String = "%d:%d" % [map.group, map.number]
	if _sheets.has(key):
		return _sheets[key]
	if not may_build:
		return null
	# Kept between maps, because walking a route and back should not repaint the
	# town at each end of it, and bounded because a long session walks a lot of
	# them: a sheet is 24 KB and this is the whole of what holds one.
	if _sheets.size() >= SHEET_LIMIT:
		_sheets.clear()
	var tileset: Gen2WorldTileset = _world.data.world_tileset(map.tileset)
	if tileset == null:
		return null
	var sheet: RefCounted = AtlasScript.new()
	# No animation handle: a map that is not the loaded one has no tile
	# animation running on it, and the loaded one's sheet is the renderer's own.
	if not sheet.build(_world.data, map, tileset, _time_of_day):
		return null
	_sheets[key] = sheet
	return sheet


## A map's own block list, which nothing a run does edits: only the loaded map
## takes `changeblock`, and that one goes through [method _here_texture].
func _block_texture(map: Gen2WorldMap) -> ImageTexture:
	var key: String = "%d:%d" % [map.group, map.number]
	if not _blocks.has(key):
		_blocks[key] = _bytes_texture(
			map.blocks, Vector2i(map.width_blocks, map.height_blocks)
		)
	return _blocks[key]


## `wOverworldMapBlocks`: the loaded map with the three-block margin around it,
## every byte through `drawn_block_at`, so the connection strips in it are the
## cartridge's own. Read again whenever a `changeblock` or a map load moves one.
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


## The tileset's metatile table as sixteen bytes a block, with anything past the
## tile strip folded to zero the way `Gen2WorldTileset.tile_index` does.
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


## A one-block stand-in for the fill quad's block sampler, which it never reads:
## every pixel of that quad declares itself outside the map it names.
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
