extends RefCounted

## Turns a map's tile layer into one static mesh.
##
## Units are WORLD PIXELS: a graphics tile is 8 across, a walk cell 16, and a
## height is a whole number of 8px bands. Keeping the mesh in the same units the
## drawing is measured in is what lets a shape height be read off the art.
##
## Three models come out of `tile_shape.gd`:
##
##   flat     one quad at the class height. Ground, and water recessed so the
##            shoreline shows a lip.
##   top art  a box wearing its own art on the TOP face: a drawing that depicts
##            a surface seen from above.
##   volume   a box whose SOUTH face folds the artwork upright, 8px band by band,
##            band k sampling the map row k tiles north. That is what most of
##            Generation II's art is: a wall, a canopy or a facade is drawn
##            face-on, so standing it up is the whole trick.
##
## An unpinned volume's height is MEASURED rather than assumed: the run of solid
## tiles up the column is how tall the thing is drawn, capped so a border forest
## comes out as trees rather than as one cliff. A pinned tile takes its class
## height and skips the measurement entirely.
##
## Side faces are never stretched. Every side is 8px bands with the art tiled per
## band, and a band below a neighbour's own height is not emitted at all.

const Houses: GDScript = preload("houses.gd")
const Levels: GDScript = preload("levels.gd")
const Model: GDScript = preload("model.gd")

const TILE: float = 8.0
## The same eight as a whole number, which is what a painted mask is indexed in.
const TILE_PX: int = 8
const BAND: int = 8

## Volume height cap, in walk cells. Three is 48 world pixels: tall enough for a
## house drawn three cells deep, short enough that nothing measured wrong can
## become a tower.
const MAX_CELLS: int = 3
const CELL_TILES: int = RomLayout.MAP_BLOCK_CELL_WIDTH

## Per-face brightness, multiplied into the sampled texel. The south face is the
## artwork itself and draws untouched; the top of a volume darkens so the
## plateau behind a standing drawing reads as depth rather than as the same art
## repeated at full strength.
const SHADE_SOUTH: Color = Color(1.0, 1.0, 1.0)
const SHADE_SIDE: Color = Color(0.80, 0.80, 0.80)
const SHADE_NORTH: Color = Color(0.64, 0.64, 0.64)
const SHADE_TOP_FLAT: Color = Color(1.0, 1.0, 1.0)
const SHADE_TOP_VOLUME: Color = Color(0.86, 0.86, 0.86)

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()

## TWO SURFACES ARE LIFTED OUT OF THE TERRAIN MESH, water and the standing tufts
## of grass, which is the reference's own arrangement (`lib/Water.lua` and the
## grass shader in `lib/Voxel3D.lua`) and for its reason: the terrain is opaque
## paint that never moves, and neither of these is. Each wants its own material,
## so each wants its own mesh, and the cheapest place to separate them is where
## the geometry is made rather than afterwards.
##
## Only the water's TOP quad goes to the water sink. The faces around a recess
## are the BANK, they wear the shore's own art and they are terrain like any
## other side. Only the STANDING part of tall grass goes to the tuft sink; the
## floor it is drawn on keeps the drawing and stays terrain.
const SINK_TERRAIN: int = 0
const SINK_WATER: int = 1
const SINK_TUFT: int = 2
var _water_vertices := PackedVector3Array()
var _water_normals := PackedVector3Array()
var _water_uvs := PackedVector2Array()
var _water_colors := PackedColorArray()
var _tuft_vertices := PackedVector3Array()
var _tuft_normals := PackedVector3Array()
var _tuft_uvs := PackedVector2Array()
var _tuft_colors := PackedColorArray()
## Per tuft vertex: how far up its own clump it stands, 0 at the root and 1 at
## the tip, and the clump's own phase. The shader needs both and nothing else:
## the root is pinned and the bend goes by the SQUARE of the height, so a clump
## leans rather than sliding, and the phase is what stops a field moving as one
## sheet. `Mesh.ARRAY_TEX_UV2`, since UV is already the atlas.
var _tuft_uv2s := PackedVector2Array()
## Which sink the next `_push` goes to, and what to write into UV2 there. Set
## around the faces that belong to one, and cleared straight after.
var _sink: int = SINK_TERRAIN
var _sink_uv2 := Vector2.ZERO

## Art modes, kept per tile as a byte because every tile of every map carries one.
const ART_FLAT: int = 0
const ART_TOP: int = 1
const ART_UPRIGHT: int = 2
const ART_CUTOUT: int = 3
## Not a class's art but a shape the COLLISION asks for: see `_measure_ledges`.
const ART_LEDGE: int = 4
## A LINE seen from above: see `_railing`.
const ART_RAILING: int = 5
## POSTS AND RAILS, modelled from the drawing and stood on the cell's own centre
## line: see `_fence`.
const ART_FENCE: int = 6
## How thick a fence is, in world pixels. The one authored number in it, because
## a drawing seen face-on states its width and its height honestly and says
## nothing at all about its depth. Three is the wooden sign's own thickness and a
## fence is the same kind of thing: a plank on a post.
const FENCE_THICK: float = 3.0

## The RESOLVED grid, which is the map plus the border ring around it, and the
## MAP's own size inside it. Every array below is indexed on the grid; the world
## is measured from the map's own corner, so a vertex is emitted at
## `(tile - _margin) * TILE` and everything outside this file goes on speaking
## map coordinates.
var _size := Vector2i.ZERO
var _map_size := Vector2i.ZERO
var _margin := Vector2i.ZERO
var _tiles := PackedInt32Array()
var _art := PackedByteArray()
var _depths := PackedByteArray()
## Per tile: whether its cutout is round in plan, and whether its drawing is a
## solid body the border flood cannot be trusted with.
var _round := PackedByteArray()
var _filled := PackedByteArray()
## Per tile: which drawn stem stands under it, as one more than its index in
## `_stem_shapes`, and 0 for the drawings that stand on their own foot, which is
## all but the flower. `_stem_rise` is how far that stem lifts the drawing, which
## is the shape's own row count. See `profile.gd:STEMS` and `shape/stems.gd`.
var _stem := PackedByteArray()
var _stem_rise := PackedByteArray()
## The distinct stems this map draws, each the painted rows top first.
var _stem_shapes: Array = []
## Per tile: how many of its darkest shades bound the drawing, 0 for a mask cut
## from the ground's colours instead.
var _outlined := PackedByteArray()
## Per tile: whether an authored MODEL stands here rather than carved geometry,
## whether that model sits on the ground rather than standing on a trunk, and
## whether it is stone rather than a plant.
var _modelled := PackedByteArray()
var _shrub := PackedByteArray()
var _rock := PackedByteArray()
## And whether it is a straight COLUMN rather than a turned silhouette.
var _column := PackedByteArray()
## Per tile: how tall a modelled class stands against how tall it is drawn, or
## zero for the class's own default. See `profile.gd:STRETCH`.
var _stretch := PackedFloat32Array()
## Per tile: whether a slab of its own drawing stands up out of the floor, and
## whether the collision calls it LONG grass rather than tall.
var _tufted := PackedByteArray()
var _long_grass := PackedByteArray()
## Per tile: how many cells across and down the drawing this cutout belongs to
## is, which is what the mask is cut over, and which class it is.
var _span_x := PackedByteArray()
var _span_y := PackedByteArray()
## Per tile: how many TILE rows of that box the drawing actually uses, where it
## is fewer than the box holds, or zero for the whole box. A cell is two tiles
## and a drawing is a whole number of TILES, so a plant three tiles tall fills
## one cell and half of the next. See `_measure_cutouts`.
var _span_cut := PackedByteArray()
var _lying := PackedByteArray()
## Per tile: whether the drawing stands on FURNITURE rather than on the ground.
var _on_furniture := PackedByteArray()
var _klass := PackedInt32Array()
var _class_ids: Dictionary = {}

## THE OBJECTS, which are the one thing here that is not resolved per tile. See
## `_measure_objects` and `profile.gd:OBJECTS`. Per tile: whether an object covers
## it, so the tile itself extrudes nothing; and which objects those are, since a
## tile may carry two.
var _object_covered := PackedByteArray()
var _object_over: Dictionary = {}
## One entry per object found on this map: its declaration, the tile its
## arrangement starts at, and how many tiles across and down that is.
var _objects: Array = []
## THE STAIRCASES, found the same way. Per tile, which flight stands there; and
## per flight, its declaration, its first tile and the floor it starts from.
var _stair_at := PackedInt32Array()
var _stairs: Array = []
var _stair_done: Dictionary = {}
## Which of them this emit has already stood up. An object is asked for from every
## one of its tiles, so that a window cutting off its top-left corner cannot
## delete it, and built from whichever asks first.
var _object_done: Dictionary = {}
## Per tile: which surface of a building it depicts, and how many bands a sloped
## roof tile has fallen from the flat section beside it.
const PART_NONE: int = 0
const PART_WALL: int = 1
const PART_ROOF: int = 2
var _part := PackedByteArray()
var _drop := PackedByteArray()
## Per tile: whether a PART_WALL tile draws the front SLOPE of a roof rather than
## a wall, which is what leans it back over the footprint. See `_facade_pitch`.
var _slope := PackedByteArray()
## Per tile: whether the measurement actually LEANED it, which is a narrower
## question than whether its drawing is a slope. A pitch is refused wherever the
## column turns out to be a stack of storeys, and those tiles keep every face a
## wall has. Only a leaned tile is tilted and only two of them share an edge with
## no riser between: see `_face_roof`.
var _pitched := PackedByteArray()
## THE HOUSES A PERSON PAINTED. Per tile: which surface of a painted drawing it
## depicts, and how many bands a painted roof tile stands below its own ridge.
## See `_match_houses` and `shape/houses.gd`.
const HOUSE_NONE: int = 0
const HOUSE_GROUND: int = 1
const HOUSE_WALL: int = 2
const HOUSE_ROOF: int = 3
var _house := PackedByteArray()
## One entry per placement of a built drawing: the drawing, the tile it starts
## at, how many tiles it runs, and the pixel columns its DOORS occupy.
var _houses: Array = []
var _house_covered := PackedByteArray()
var _house_over: Dictionary = {}
var _house_done: Dictionary = {}
## What one painting measures, keyed by drawing id. It is a fact about the
## painting alone, so it is read once rather than once per placement.
var _house_plans: Dictionary = {}
## Per tile: whether it is the VOID past the edge of the world rather than ground.
## Both draw one flat quad at the same height and nothing else in the mesh has had
## to tell them apart. A great roof does: it falls away from the floor a person
## stands on and it falls TOWARD the void, and the two ends of its run are
## otherwise identical. See `_roof_fall`.
var _void := PackedByteArray()
## How many pixels off each facade tile's left and right edges are ground rather
## than wall. See `profile.gd:FACADE_MARGIN`.
var _margin_left := PackedByteArray()
var _margin_right := PackedByteArray()
var _heights := PackedInt32Array()
var _volume := PackedByteArray()
## Per tile: whether it draws the face of a terrain CLIFF, and whether that face
## is the FRONT of one, which together are the only thing that says the ground
## behind a wall is a plateau standing on top of it.
var _cliff := PackedByteArray()
var _front := PackedByteArray()
## Per tile: whether it draws the plateau's far EDGE, which ends one and then
## stands at the height of what lies south of it.
var _lip := PackedByteArray()
## Per tile: which arms of a fence stand in its walk cell, as a pair of bits,
## and which cells this emit has already built one for.
const FENCE_ACROSS: int = 1
const FENCE_AWAY: int = 2
var _fence_arms := PackedByteArray()
var _fence_done: Dictionary = {}
## The fence's own profile, cut once per map from the tiles that draw it
## face-on: as wide as the drawing's own period by however many rows stand above
## the shadow. `_fence_tiles` is the rows of tile ids it was read from.
var _fence_mask := PackedByteArray()
var _fence_tall: int = 0
var _fence_wide: int = 0
var _fence_tiles: Array = []
## Per tile: whether it is rock a plateau is made of, face or floor. It is the
## set the RAMP is cut out of and nothing else reads it.
var _shelf := PackedByteArray()
## Per tile: whether its top face SLOPES, and the height of each of its four
## corners in world pixels, north-west, north-east, south-west, south-east.
## Written only for a rim, and read only by `_emit`.
var _ramp := PackedByteArray()
var _corners := PackedInt32Array()
## The southernmost map row of the structure each tile belongs to. The fold reads
## north from there rather than from the tile itself, so every column of one
## structure shows the same drawing standing up and a face exposed at its back
## does not sample the ground behind it.
var _bases := PackedInt32Array()
## Per tile: which way a jumping ledge's drop faces, as a step, packed one to a
## byte. Zero everywhere else.
const LEDGE_NONE: int = 0
const LEDGE_SOUTH: int = 1
const LEDGE_NORTH: int = 2
const LEDGE_EAST: int = 3
const LEDGE_WEST: int = 4
## How far the wedge rises: one band, which is what the lip is drawn as.
const LEDGE_RISE: int = BAND
var _ledge := PackedByteArray()


## Resolves a map and builds it, as one mesh per chunk. Empty when there is
## nothing to draw.
## [param source] is a `map_source.gd`, over the live world or over records.
## [param window] is a rectangle in TILES, empty for the whole map.
func build(
	source: RefCounted, shape: RefCounted, atlas: RefCounted, window: Rect2i = Rect2i()
) -> Array:
	resolve(source, shape)
	return emit(atlas, window)


## The geometry for [param window], out of what [method resolve] already worked
## out. Nothing is measured again: what a tile is and how tall it stands is a
## fact about the MAP, and reading it through the window would make a structure's
## height depend on where the player was standing when the mesh was built.
##
## An empty window is the whole map; anything else is clipped to it.
##
## The answer is a LIST of meshes, one per chunk, because the engine culls per
## instance: one mesh for a whole map means the frustum test can only accept or
## reject all of it at once.
func emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> Array:
	if not begin_emit(atlas, window):
		return []
	while not emit_step(0):
		pass
	return take_chunks()


## The three calls below, taken one chunk at a time, so a caller with a frame to
## keep can spend part of it here and the rest on drawing. A whole town is 200 ms
## of geometry and that used to land on every warp and at the start of every
## fight.
##
## The chunk is the unit of both jobs at once: it is what the engine can cull,
## and it is a bounded piece of work, where a row grew with the map and one row
## of a big route took three times the whole frame budget on its own.
const CHUNK_TILES: int = 16

var _emit_atlas: RefCounted = null
var _chunks: Array[Rect2i] = []
var _chunk_at: int = 0
var _chunk_cursor := Vector2i.ZERO
var _ready: Array = []
var _water_ready: Array = []
var _tuft_ready: Array = []


## False when there is nothing to draw at all.
func begin_emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> bool:
	_emit_atlas = null
	_chunks = []
	_chunk_at = 0
	_ready = []
	_water_ready = []
	_tuft_ready = []
	if _size == Vector2i.ZERO:
		return false
	# The window arrives in MAP tiles and the emit walks the GRID, which is the map
	# inside its border ring, so the window is carried across by the margin. The
	# SKIRT lies outside the grid on every side and is walked with it, since it is
	# emitted per tile and belongs to the same chunks.
	var reach: int = maxi(BORDER_TILES - _margin.x, 0) if _outside else 0
	var box := Rect2i(-Vector2i(reach, reach), _size + Vector2i(reach, reach) * 2)
	if window.size.x > 0 and window.size.y > 0:
		box = box.intersection(Rect2i(window.position + _margin, window.size))
	if box.size.x <= 0 or box.size.y <= 0:
		return false
	_emit_atlas = atlas
	# EMPTIED, NOT DROPPED. A spot is per emit and a mesh is per map, so the two
	# dictionaries are cleared on different clocks, and `_model_bodies` short
	# circuits before either is rebuilt: a drawing already measured returns its
	# body list without touching `_model_spots`, so dropping the keys here left
	# `_place_model` writing into a dictionary that was not there and
	# `take_models` reading one. Both threw, per tile, for as long as the player
	# walked. Keeping the key and emptying its value is what makes a mesh built
	# for an earlier window survive the next one.
	for key: String in _model_spots:
		_model_spots[key] = {}
	_object_done.clear()
	_house_done.clear()
	_stair_done.clear()
	_fence_done.clear()
	_built_model = false
	# Chunks are cut on the world's own grid rather than on the window's corner,
	# so walking one cell east recentres the window onto the SAME chunks and the
	# ones already built come out identical.
	var first := Vector2i(
		floori(float(box.position.x) / CHUNK_TILES), floori(float(box.position.y) / CHUNK_TILES)
	)
	var last := Vector2i(
		floori(float(box.end.x - 1) / CHUNK_TILES), floori(float(box.end.y - 1) / CHUNK_TILES)
	)
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var chunk := Rect2i(
				Vector2i(cx, cy) * CHUNK_TILES, Vector2i(CHUNK_TILES, CHUNK_TILES)
			).intersection(box)
			if chunk.size.x > 0 and chunk.size.y > 0:
				_chunks.append(chunk)
	if _chunks.is_empty():
		return false
	_open_chunk()
	return true


## One slice, up to [param budget_usec] of work, or the whole window at zero.
## True once the window is finished, and true forever after that. What the slice
## finished is waiting in [method take_chunks].
func emit_step(budget_usec: int) -> bool:
	if _emit_atlas == null:
		return true
	var until: int = Time.get_ticks_usec() + budget_usec
	var done_tiles: int = 0
	while _chunk_at < _chunks.size():
		var box: Rect2i = _chunks[_chunk_at]
		while _chunk_cursor.y < box.end.y:
			while _chunk_cursor.x < box.end.x:
				if _chunk_cursor.x < 0 or _chunk_cursor.y < 0 \
						or _chunk_cursor.x >= _size.x or _chunk_cursor.y >= _size.y:
					_emit_skirt(_chunk_cursor.x, _chunk_cursor.y, _emit_atlas)
				else:
					_emit(_chunk_cursor.x, _chunk_cursor.y, _emit_atlas)
				_chunk_cursor.x += 1
				# A chunk is 256 tiles and a dense one is thirty milliseconds of
				# them the first time its cutout masks are cut, so the slice has
				# to be able to stop INSIDE a chunk. Counted over the slice rather
				# than off the column, which inside a 16 wide chunk would come
				# round about once a chunk and never stop anything. Sixteen holds
				# the worst slice to 6 ms where sixty four let it reach ten: a
				# stretch of cutouts is milliseconds of work either way.
				done_tiles += 1
				# A MODEL BUILD ENDS THE SLICE, whatever is left of the budget.
				# Turning one drawing into a voxel solid is 2 ms for the small fir
				# and 10 for the round tree, which is the budget over twice on its
				# own, and it is atomic: there is no stopping half way through a
				# tree. Spending the rest of the slice on top of it is what turns
				# an overrun into a dropped frame, and the first tree of a map is
				# the only tile that ever pays it.
				if budget_usec > 0 and _built_model:
					_built_model = false
					return false
				if budget_usec > 0 and (done_tiles & 15) == 0 \
						and Time.get_ticks_usec() >= until:
					return false
			_chunk_cursor.x = box.position.x
			_chunk_cursor.y += 1
		_close_chunk()
		_chunk_at += 1
		if _chunk_at < _chunks.size():
			_open_chunk()
		if budget_usec > 0 and Time.get_ticks_usec() >= until:
			return _chunk_at >= _chunks.size()
	return true


## The chunks finished since this was last asked, and each is asked for once.
func take_chunks() -> Array:
	var out: Array = _ready
	_ready = []
	return out


## The WATER chunks finished since this was last asked. Same contract, own list,
## because water is drawn with its own material: see `_close_chunk`.
func take_water() -> Array:
	var out: Array = _water_ready
	_water_ready = []
	return out


## The standing GRASS chunks, on their own list for the same reason: they sway,
## and swaying is a vertex shader.
func take_tufts() -> Array:
	var out: Array = _tuft_ready
	_tuft_ready = []
	return out


func _open_chunk() -> void:
	_chunk_cursor = _chunks[_chunk_at].position
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_colors = PackedColorArray()
	_water_vertices = PackedVector3Array()
	_water_normals = PackedVector3Array()
	_water_uvs = PackedVector2Array()
	_water_colors = PackedColorArray()
	_tuft_vertices = PackedVector3Array()
	_tuft_normals = PackedVector3Array()
	_tuft_uvs = PackedVector2Array()
	_tuft_colors = PackedColorArray()
	_tuft_uv2s = PackedVector2Array()


## The two sinks close into two SEPARATE meshes, on two lists, and not into two
## surfaces of one. A chunk in the middle of a lake has no terrain in it at all,
## which one mesh cannot say: a surface with no vertices is not a surface, so the
## water would slide down to index 0 and arrive wearing the terrain's material.
func _close_chunk() -> void:
	# A chunk of nothing is most of the sky above a route edge and all of a map's
	# void; an empty mesh is an instance the engine still has to cull.
	if not _vertices.is_empty():
		_ready.append(_mesh_of(_vertices, _normals, _uvs, _colors))
	if not _water_vertices.is_empty():
		_water_ready.append(
			_mesh_of(_water_vertices, _water_normals, _water_uvs, _water_colors)
		)
	if not _tuft_vertices.is_empty():
		_tuft_ready.append(_mesh_of(
			_tuft_vertices, _tuft_normals, _tuft_uvs, _tuft_colors, _tuft_uv2s
		))


func _mesh_of(
	vertices: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray,
	uv2s: PackedVector2Array = PackedVector2Array()
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func size_pixels() -> Vector2:
	return Vector2(_map_size) * TILE


func size_tiles() -> Vector2i:
	return _map_size


## The world x and z of a GRID tile's own corner. The grid is the map inside its
## border ring and the world is measured from the map's corner, so this is the
## one place the ring is subtracted and nothing outside this file ever sees it.
func _world_x(tx: int) -> float:
	return float(tx - _margin.x) * TILE


func _world_z(ty: int) -> float:
	return float(ty - _margin.y) * TILE


## Where a MAP tile sits in the resolved arrays, which are the map inside its
## border ring and so are neither the same size nor the same origin.
func grid_index(map_tile: Vector2i) -> int:
	var at: Vector2i = map_tile + _margin
	if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
		return -1
	return at.y * _size.x + at.x


## The same offset in walk cells, which is what the collision is asked in.
func _margin_cells() -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(_margin.x / CELL_TILES, _margin.y / CELL_TILES)


## Resolves every tile to a class and a height, in two passes.
##
## The first pass reads the shape of each tile: collision is per walk cell, so
## the four tiles of a cell all see the same permission and only a pin can split
## them. The second measures each unpinned volume column, because how tall a
## thing is drawn is not a property of one tile.
func resolve(source: RefCounted, shape: RefCounted) -> void:
	_size = Vector2i.ZERO
	# Both are keyed by tile id, which means nothing without the tileset it came
	# from, so a warp to a map on another tileset has to drop them.
	_masks.clear()
	_hulls.clear()
	_border.clear()
	_edge_floor = Vector2i(-2, 0)
	# Keyed on tile ids, which mean nothing without the tileset they came from.
	# All three go together: a body list outliving its meshes is a drawing that
	# resolves to a model nothing built.
	_model_meshes.clear()
	_model_spots.clear()
	_model_bodies.clear()
	_commonest_index.clear()
	if source == null or not source.valid():
		return
	_outside = source.outside()
	# The border RING is resolved as part of the map, not painted on afterwards.
	# Past its edge the cartridge repeats the map's own border block, which is a
	# tree line on eighteen maps, a hedge on sixteen and open sea on twenty, and
	# every pass here has to see it: a tree in the ring is measured, masked,
	# modelled and stamped by exactly the code that does it inside the map, and
	# the seam between the two is skirted by the code that skirts every other
	# height change. A room ends at its walls and gets none.
	var ring: int = _ring_depth(source, shape) if _outside else 0
	_margin = Vector2i(ring, ring)
	_map_size = source.size_cells() * RomLayout.MAP_BLOCK_CELL_WIDTH
	_size = _map_size + _margin * 2
	var count: int = _size.x * _size.y
	_tiles.resize(count)
	_art.resize(count)
	_depths.resize(count)
	_round.resize(count)
	_filled.resize(count)
	_stem.resize(count)
	_stem_rise.resize(count)
	_outlined.resize(count)
	_modelled.resize(count)
	_shrub.resize(count)
	_rock.resize(count)
	_column.resize(count)
	_stretch.resize(count)
	_tufted.resize(count)
	_long_grass.resize(count)
	_span_x.resize(count)
	_span_y.resize(count)
	_span_cut.resize(count)
	_lying.resize(count)
	_on_furniture.resize(count)
	_klass.resize(count)
	_part.resize(count)
	_drop.resize(count)
	_slope.resize(count)
	_pitched.resize(count)
	_void.resize(count)
	_margin_left.resize(count)
	_margin_right.resize(count)
	_heights.resize(count)
	_volume.resize(count)
	_cliff.resize(count)
	_front.resize(count)
	_lip.resize(count)
	_bases.resize(count)
	# Written only where there is a ledge, so it is the one array that has to be
	# cleared rather than filled in by the pass below.
	_ledge.resize(count)
	_ledge.fill(LEDGE_NONE)
	_shelf.resize(count)
	_shelf.fill(0)

	for ty: int in _size.y:
		var cell_y: int = (ty - _margin.y) >> 1
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			var tile: int = source.tile_at(tx - _margin.x, ty - _margin.y)
			_tiles[at] = tile
			_bases[at] = ty
			_cliff[at] = 0
			_front[at] = 0
			_lip[at] = 0
			if tile < 0:
				_heights[at] = 0
				_volume[at] = 0
				_art[at] = ART_FLAT
				_part[at] = PART_NONE
				continue
			var permission: int = source.permission_at(
				Vector2i((tx - _margin.x) >> 1, cell_y)
			)
			var shape_class: StringName = shape.at(tile, permission)
			var art: StringName = shape.art(shape_class)
			_art[at] = _art_mode(art)
			_depths[at] = clampi(shape.depth(shape_class), 1, 16)
			_round[at] = 1 if shape.is_round(shape_class) else 0
			_filled[at] = 1 if shape.is_filled(shape_class) else 0
			var stem: Array = shape.stem_rows(shape_class)
			_stem[at] = 0
			_stem_rise[at] = 0
			if not stem.is_empty():
				var found: int = _stem_shapes.find(stem)
				if found < 0:
					found = _stem_shapes.size()
					_stem_shapes.append(stem)
				_stem[at] = found + 1
				_stem_rise[at] = clampi(stem.size(), 0, 32)
			_outlined[at] = shape.outline_shades(shape_class)
			_modelled[at] = 1 if shape.is_model(shape_class) else 0
			_shrub[at] = 1 if shape.is_shrub(shape_class) else 0
			_rock[at] = 1 if shape.is_rock(shape_class) else 0
			_column[at] = 1 if shape.is_column(shape_class) else 0
			_stretch[at] = shape.model_stretch(shape_class)
			# WHICH CELLS ARE GRASS IS THE CARTRIDGE'S OWN ANSWER, and it is in
			# the collision byte rather than in the drawing. `grass_kind` is the
			# host's decode of SetTallGrassFlags, so this covers every map in the
			# game instead of the four tilesets whose grass tile anyone had got
			# round to naming. The pin stays as an override, for a drawing that
			# should stand up where no collision code says so.
			var grass_code: int = source.code_at(
				Vector2i((tx - _margin.x) >> 1, cell_y)
			)
			_tufted[at] = 1 if shape.is_tufted(shape_class) \
				or Gen2WorldCollision.is_grass(grass_code) else 0
			# LONG grass is the cartridge's own distinction and it draws its own
			# tile for it: taller, denser and with a ground line under it, where
			# tall grass is a sparse tuft. See `_tufts`.
			_long_grass[at] = 1 if Gen2WorldCollision.is_long_grass(grass_code) else 0
			_lying[at] = 1 if shape.is_lying(shape_class) else 0
			_on_furniture[at] = 1 if shape_class == &"on_furniture" else 0
			var span: Vector2i = shape.span_cells(shape_class)
			_span_x[at] = maxi(span.x, 1)
			_span_y[at] = maxi(span.y, 1)
			_span_cut[at] = 0
			if not _class_ids.has(shape_class):
				_class_ids[shape_class] = _class_ids.size()
			_klass[at] = int(_class_ids[shape_class])
			match shape.building_part(shape_class):
				&"wall":
					_part[at] = PART_WALL
				&"roof":
					_part[at] = PART_ROOF
				_:
					_part[at] = PART_NONE
			_drop[at] = shape.roof_drop(shape_class)
			_slope[at] = 1 if _part[at] == PART_WALL and shape.is_facade_slope(tile) \
				else 0
			_void[at] = 1 if shape_class == &"void" else 0
			# How much of this tile is the ground beside the house rather than the
			# house. Nearly always nothing, which is why it is stored per tile and
			# read at emit rather than being another pass.
			var margin: Vector2i = shape.facade_margin(tile) \
				if _part[at] == PART_WALL else Vector2i.ZERO
			_margin_left[at] = margin.x
			_margin_right[at] = margin.y
			var is_volume: bool = art == &"upright"
			_volume[at] = 1 if is_volume else 0
			_cliff[at] = 1 if is_volume and shape.is_cliff(tile) else 0
			_front[at] = 1 if _cliff[at] == 1 and shape.is_cliff_front(tile) else 0
			_lip[at] = 1 if not is_volume and shape.is_cliff_lip(tile) else 0
			# A pin is authority: it names the height too, and the column
			# measurement below leaves it alone.
			if is_volume and not shape.is_pinned(tile):
				_heights[at] = -1
			else:
				_heights[at] = shape.height(shape_class)

	# Before every measurement, because a painting corrects what a tile IS: the
	# passes below then read a painted door as the wall it is drawn on, exactly as
	# they read a pinned one.
	var painted_map: Gen2WorldMap = source.map()
	if painted_map != null:
		_match_houses(shape, painted_map.tileset)
	_measure_columns()
	# Before the plateau pass reads a cliff's height off it, and after the column
	# pass, whose cell-granular answer it replaces wherever a face is drawn.
	_measure_cliffs()
	# Before the plateau pass, which is the automatic reading of the same thing:
	# where a person has said what the levels are, the cliff pass has nothing left
	# to work out and its flood would only fight the answer.
	_apply_levels(source)
	_measure_plateaus()
	_measure_buildings()
	# After the buildings, which is the one pass that can put a floor below the
	# ground plane and so the only one the void has anything to follow.
	_settle_void()
	# Before the furniture, which asks what the height of the thing under it came
	# to and would read an unsettled -1 as standing on the floor.
	_settle_unmeasured()
	_measure_furniture()
	_measure_cutouts()
	# After the cutouts, because an object overrides whatever class its tiles were
	# given, and after the heights, because every tile it covers goes back to
	# standing at the floor of its own cell.
	_measure_objects(shape)
	# With the objects, and for the same reason: a boxed house covers its tiles
	# and hands them back to the floor of their own cell.
	_measure_house_boxes(source)
	_measure_stairs(shape)
	# Last, because it overrides whatever the passes above made of a ledge tile
	# and reads the ground they settled either side of it.
	_measure_ledges(source)
	# The fence's own drawing is read at emit, where the atlas is; what resolve
	# owns is which cells carry one and which way each run goes.
	_fence_tiles = shape.fence_face()
	_fence_mask = PackedByteArray()
	_measure_fences()
	# After every one of them, since each can still move a height and a ramp is
	# cut from the heights as they finally stand.
	_measure_ramps()


## The floors a PERSON painted, where they painted any.
##
## How many storeys a place has is the one thing about these maps that cannot be
## derived. A cliff face gives it away out of doors and `_measure_plateaus` reads
## it, but a cave draws its rock the same whether the floor behind it is a storey
## up or the same floor carrying on, and the answer came back that caves do carry
## storeys: Mt Mortar has five. So it is asked, painted on
## `tools/level_page.py`, and pinned in `shape/levels.gd`.
##
## FLAT GROUND ONLY, and only where the table names a level. A painted level says
## where the FLOOR is; what stands on that floor was measured off its own drawing
## and is raised WITH it, so a tree on a shelf goes up by the shelf rather than
## being flattened to it. Rock and transitions carry no level at all and are left
## to the passes that measure them.
func _apply_levels(source: RefCounted) -> void:
	var map: Gen2WorldMap = source.map()
	if map == null or not Levels.has(map.group, map.number):
		return
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _tiles[at] < 0:
				continue
			var height: int = Levels.height_at(
				map.group, map.number,
				Vector2i((tx - _margin.x) >> 1, (ty - _margin.y) >> 1)
			)
			if height <= 0:
				continue
			if _art[at] == ART_FLAT:
				# Water keeps its own recess and rides up on the floor it is cut
				# into, which is what `_settle_ponds` does for a measured one.
				_heights[at] = height if _heights[at] >= 0 else _heights[at] + height
			elif _heights[at] >= 0:
				_heights[at] += height


## THE HOUSES A PERSON PAINTED, found by their own arrangement of tile ids.
##
## A house packs different surfaces into one flat drawing: the wall, which you
## are looking AT, and the roof, which you are either looking DOWN onto or seeing
## from the FRONT. No measurement separates them, so a person paints which is
## which on `tools/house_page.py` and `shape/houses.gd` is what comes back. This
## is the same authority `levels.gd` has over the cliff pass: where a painting
## exists it wins, and where none does nothing changes.
##
## THE ARRANGEMENT IS THE KEY, matched by `_pattern_at` exactly as an object or a
## staircase is, so one painting serves every placement of the drawing.
##
## THE PAINTING IS PER PIXEL AND THIS PASS IS PER TILE, which is the whole of
## what is not finished yet. A tile painted all one way takes that word now; a
## tile the painting CUTS, which is how every hipped roof comes down, is left
## exactly as the passes made it, because reading it either way is the fault the
## pixel painting exists to stop. What those tiles want is the wall's top read per
## pixel COLUMN, which makes a house a heightfield and needs its own emitter, and
## `tools/house_pins.gd` counts how many tiles of a painting are waiting on it.
##
## A DOOR STANDS UP WITH THE WALL AROUND IT, and needs no word of its own. Its
## cell is walkable, so `at()` calls it ground and the column stood at nothing:
## the doorway came out as a slot cut clean through the house. Painted wall, it is
## a wall wearing the door's own drawing, and the player still walks through it,
## because a pin is presentational and nothing here touches collision.
func _match_houses(shape: RefCounted, tileset_number: int) -> void:
	var count: int = _size.x * _size.y
	_house.resize(count)
	_house.fill(HOUSE_NONE)
	_houses.clear()
	# BIGGEST FIRST, AND FIRST CLAIM WINS, which is the reference's own rule for
	# the same table. One house's rectangle can hold a smaller one's, and a small
	# drawing repainting the middle of a big one would leave a building painted
	# two ways.
	var painted: Array = Houses.of_tileset(tileset_number)
	painted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["tiles"] as Array).size() * ((a["tiles"][0] as Array).size()) \
			> (b["tiles"] as Array).size() * ((b["tiles"][0] as Array).size()))
	for house: Dictionary in painted:
		var pattern: Array = house["tiles"]
		var paint: Array = house["paint"]
		var across := Vector2i((pattern[0] as Array).size(), pattern.size())
		if across.x > _size.x or across.y > _size.y:
			continue
		for ty: int in _size.y - across.y + 1:
			for tx: int in _size.x - across.x + 1:
				if not _pattern_at(pattern, across, tx, ty):
					continue
				# A BUILT DRAWING IS NOT RESOLVED A TILE AT A TIME. Everything
				# about it waits for `_measure_house_boxes`, which runs late enough
				# to know what floor each of its cells stands on.
				#
				# A painting the plan finds NO BUILDING IN is left to the passes
				# below, and that is the safety on doing this to every drawing: a
				# rectangle with no wall in it is a roof cut off by a map edge or a
				# scrap the page flooded on its own, and claiming it would hand its
				# tiles to the floor with nothing left standing on them.
				#
				# THE CLAIM IS PER BUILDING, NOT PER RECTANGLE, and that is what
				# lets two paintings of the same street coexist. The page flooded
				# overlapping rectangles: Goldenrod's Pokemon Centre sits in #96,
				# and #99 is bigger, overlaps its top four tile rows and holds no
				# building there at all. Refusing #96 for the collision left that
				# building to the passes below, which cut the door out of its face
				# as a hole and stood its roof halfway down the wall. Marking only
				# what a building actually stands on, and testing the same, lets
				# #96 take the part #99 never used.
				var plans: Array = _house_plan(house)
				if not plans.is_empty():
					var mine := PackedInt32Array()
					for index: int in plans.size():
						var rect: Rect2i = _house_tile_rect(plans[index], across)
						rect.position += Vector2i(tx, ty)
						if _house_claimed(rect):
							continue
						mine.append(index)
						for row: int in rect.size.y:
							for column: int in rect.size.x:
								_house[(rect.position.y + row) * _size.x
									+ rect.position.x + column] = HOUSE_WALL
					if not mine.is_empty():
						_houses.append([house, Vector2i(tx, ty), across, [], mine])
					continue
				for row: int in across.y:
					for column: int in across.x:
						var at: int = (ty + row) * _size.x + tx + column
						var stroke: String = _house_word(paint, row, column)
						if stroke == "":
							continue
						if stroke == Houses.NONE:
							# NOT THE HOUSE only takes a tile the pass had called
							# one. The rectangle holds the pavement, the shadow and
							# whatever tree stands beside the door, and flattening
							# those would be a painting nobody made.
							if _part[at] == PART_NONE:
								continue
							_house[at] = HOUSE_GROUND
						elif stroke == Houses.ROOF:
							_house[at] = HOUSE_ROOF
						else:
							_house[at] = HOUSE_WALL
						_house_tile(shape, at, stroke)


## The one word a whole tile is painted, or "" where the painting cuts it.
##
## A tile is eight pixels square and the painting is per pixel, so this is where
## the two meet. Only a tile that agrees with itself can be handed to a pass that
## works a tile at a time.
func _house_word(paint: Array, row: int, column: int) -> String:
	var first: String = ""
	for y: int in TILE_PX:
		var line: String = paint[row * TILE_PX + y]
		for x: int in TILE_PX:
			var stroke: String = line[column * TILE_PX + x]
			if first == "":
				first = stroke
			elif stroke != first:
				return ""
	return first


## Whether any pixel of one tile of a painting is the house at all.
## WHICH TILES OF A DRAWING A BUILDING ACTUALLY STANDS ON.
##
## Not every tile the painting draws on: a rectangle can hold a piece with no
## wall under it, and a piece with no wall is not a building this can stand up.
## Covering it anyway hands it to the floor and nothing replaces it, which is a
## roof that vanishes. Only the tiles a planned building occupies are claimed and
## the rest keep whatever the passes made of them.
func _house_footprint(plans: Array, across: Vector2i) -> PackedByteArray:
	var covered := PackedByteArray()
	covered.resize(across.x * across.y)
	for plan: Dictionary in plans:
		@warning_ignore("integer_division")
		var first := Vector2i(
			int(plan["cover_left"]) / TILE_PX, int(plan["top_row"]) / TILE_PX
		)
		@warning_ignore("integer_division")
		var last := Vector2i(
			int(plan["cover_right"]) / TILE_PX, int(plan["south_row"]) / TILE_PX
		)
		for row: int in range(maxi(first.y, 0), mini(last.y, across.y - 1) + 1):
			for column: int in range(maxi(first.x, 0), mini(last.x, across.x - 1) + 1):
				covered[row * across.x + column] = 1
	return covered


## THE PAINTED HOUSES THAT ARE STOOD UP AS BOXES, given back to the FLOOR.
##
## Every tile a boxed drawing covers becomes a cutout standing at its own cell's
## floor, which is the same three words an object's tiles are given and already
## means "the ground beside me, with whatever stands on it drawn separately": the
## seam stops extruding, the floor runs under the house and every neighbour skirts
## to it. `_emit_house` then stands the whole building up in one piece.
##
## LATE, for the reason `_measure_objects` is late: `_cell_floor` reads the
## highest flat tile of a cell, and a house asked before the ground is settled
## would take a floor nothing had measured yet.
##
## THE DOORS ARE NAMED BY THE CARTRIDGE and are read here rather than painted. A
## door is a WARP, `Gen2WorldMap.events` carries them, and the three sides the
## drawing does not draw wear the facade with those pixel columns taken out.
func _measure_house_boxes(source: RefCounted) -> void:
	_house_covered.resize(_size.x * _size.y)
	_house_covered.fill(0)
	_house_over.clear()
	if _houses.is_empty():
		return
	var warps: Array = []
	var map: Gen2WorldMap = source.map()
	if map != null:
		warps = map.events.get("warps", []) as Array
	for index: int in _houses.size():
		var entry: Array = _houses[index]
		var start: Vector2i = entry[1]
		var across: Vector2i = entry[2]
		var doors: Array = []
		for event: Dictionary in warps:
			var tile := Vector2i(
				int(event.get("x", -1)) * CELL_TILES + _margin.x,
				int(event.get("y", -1)) * CELL_TILES + _margin.y
			)
			if tile.x < start.x or tile.x >= start.x + across.x:
				continue
			if tile.y < start.y or tile.y >= start.y + across.y:
				continue
			var from: int = (tile.x - start.x) * TILE_PX
			doors.append(Vector2i(from, from + CELL_TILES * TILE_PX))
		entry[3] = doors
		# EVERY FLOOR IS READ BEFORE ANY TILE IS MARKED, which is the trap
		# `_measure_objects` records: marking a tile a cutout takes it out of
		# `_cell_floor`'s own answer for the next one.
		var floors := PackedInt32Array()
		for row: int in across.y:
			for column: int in across.x:
				floors.append(_cell_floor((start.x + column) >> 1, (start.y + row) >> 1))
		var footprint: PackedByteArray = _house_footprint(
			_house_chosen(entry), across
		)
		for row: int in across.y:
			for column: int in across.x:
				if footprint[row * across.x + column] == 0:
					continue
				var at: int = (start.y + row) * _size.x + start.x + column
				# WATER IS NOT A FLOOR AND NOT A WALL, and a drawing's rectangle
				# reaches over it: drawing 95 holds a corner of the canal. Handing
				# that tile back to the floor takes its recess away, and the whole
				# body of water stands up level with the pavement as a blue slab
				# with a face down one side. Left alone it stays water.
				if _is_water(at):
					continue
				_house_covered[at] = 1
				_art[at] = ART_CUTOUT
				_part[at] = PART_NONE
				_modelled[at] = 0
				_volume[at] = 0
				_tufted[at] = 0
				_cliff[at] = 0
				_front[at] = 0
				_lip[at] = 0
				_pitched[at] = 0
				_margin_left[at] = 0
				_margin_right[at] = 0
				_heights[at] = floors[row * across.x + column]
				var over: PackedInt32Array = _house_over.get(at, PackedInt32Array())
				over.append(index)
				_house_over[at] = over


## The tiles of a drawing that one of its buildings stands on.
func _house_tile_rect(plan: Dictionary, across: Vector2i) -> Rect2i:
	@warning_ignore("integer_division")
	var first := Vector2i(
		int(plan["cover_left"]) / TILE_PX, int(plan["top_row"]) / TILE_PX
	).clamp(Vector2i.ZERO, across - Vector2i.ONE)
	@warning_ignore("integer_division")
	var last := Vector2i(
		int(plan["cover_right"]) / TILE_PX, int(plan["south_row"]) / TILE_PX
	).clamp(Vector2i.ZERO, across - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)


## Whether another building already stands on any of these tiles.
func _house_claimed(rect: Rect2i) -> bool:
	for row: int in rect.size.y:
		for column: int in rect.size.x:
			var ty: int = rect.position.y + row
			var tx: int = rect.position.x + column
			if ty < 0 or tx < 0 or ty >= _size.y or tx >= _size.x:
				continue
			if _house[ty * _size.x + tx] != HOUSE_NONE:
				return true
	return false


## One painted tile, given the class the painting says it is.
##
## The painting overrides which SHAPE CLASS the tile resolved to and nothing
## else, so every pass below this reads it exactly as it reads a pinned tile.
func _house_tile(shape: RefCounted, at: int, stroke: String) -> void:
	var painted: StringName = &"roof"
	if stroke == Houses.WALL or stroke == Houses.FRONT:
		painted = &"facade"
	elif stroke == Houses.NONE:
		painted = &"ground"
	_art[at] = _art_mode(shape.art(painted))
	_depths[at] = clampi(shape.depth(painted), 1, 16)
	_heights[at] = shape.height(painted)
	_volume[at] = 1 if _art[at] == ART_UPRIGHT else 0
	match painted:
		&"facade":
			_part[at] = PART_WALL
		&"roof":
			_part[at] = PART_ROOF
		_:
			_part[at] = PART_NONE
	# HOW FAR A ROOF HAS FALLEN IS NOT THE PAINTING'S TO SAY and it is not asked
	# for: the drop the profile already measured stands, and on tileset 3 that is
	# the reviewer's own round-two reading of every roof tile.
	_slope[at] = 1 if stroke == Houses.FRONT else 0
	# Whatever else the tile was resolved as, it is a building surface now: a
	# drawing cannot be a wall and a turned model at the same time.
	_round[at] = 0
	_filled[at] = 0
	_stem[at] = 0
	_stem_rise[at] = 0
	_outlined[at] = 0
	_modelled[at] = 0
	_shrub[at] = 0
	_rock[at] = 0
	_column[at] = 0
	_tufted[at] = 0
	_long_grass[at] = 0
	_lying[at] = 0
	_on_furniture[at] = 0
	_span_x[at] = 1
	_span_y[at] = 1
	_span_cut[at] = 0
	_cliff[at] = 0
	_front[at] = 0
	_lip[at] = 0
	_void[at] = 0
	if not _class_ids.has(painted):
		_class_ids[painted] = _class_ids.size()
	_klass[at] = int(_class_ids[painted])


## A cutout stands on the ground rather than raising it, so it measures zero and
## its neighbours are never skirted up to meet it.
func _art_mode(art: StringName) -> int:
	match art:
		&"top":
			return ART_TOP
		&"upright":
			return ART_UPRIGHT
		&"cutout":
			return ART_CUTOUT
		&"railing":
			return ART_RAILING
		&"fence":
			return ART_FENCE
		_:
			return ART_FLAT


## Every run of unmeasured volume cells in a column takes one height, measured
## off the drawing rather than guessed per tile.
##
## Measured in WALK CELLS, because that is the granularity the world is built at:
## collision is one permission byte per cell, so an unpinned structure is always
## a whole number of them and a period counted in 8px tiles would find halves of
## things.
##
## The run's length is only the answer when the run is one thing. A route's
## border forest is one canopy cell repeated for twenty rows, and reading that as
## a twenty-cell structure builds a cliff where there are trees; so is a fence
## line running north, which is what turned a town into a maze before this. So
## take the run's PERIOD: the shortest stretch at the run's southern end that the
## cells behind it immediately repeat. A house of three different cells has no
## repeat and stands three cells tall; a fence has period one and stands one cell
## tall however far it runs.
##
## Then the REGION agrees. A period is a fact about one column, and a structure
## is not: a fence meeting another fence at a T-junction has no repeat in the
## column through the junction, so that one column measured three cells where
## every column beside it measured one, and the fence grew a tower. So connected
## unmeasured cells are flooded into one region and the region votes: each run
## casts as many votes as it has cells, and the height most of the region's cells
## agree on is what the region stands at. A tie goes to the shorter, because a
## structure that is too tall hides what is behind it and one that is too short
## does not.
##
## The vote can only bring a column DOWN, never up. A column that measured too
## tall is the fault being fixed: it is a column the run has no repeat in, and
## the repeat is what the height was supposed to come from. A column that
## measured short measured short off its own drawing, and that is evidence, not
## an accident. Letting the vote raise as well put a blank three-cell slab where
## a low structure joined a tall one, which is visible in a picture and is what
## settled this.
func _measure_columns() -> void:
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	var region := _regions(cells)

	# One run at a time, as before, but the height is banked against the run's
	# region rather than written straight out.
	var runs: Array[Vector4i] = []
	var periods := PackedInt32Array()
	var votes: Dictionary = {}
	for cell_x: int in cells.x:
		var cell_y: int = 0
		while cell_y < cells.y:
			if not _cell_unmeasured(cell_x, cell_y):
				cell_y += 1
				continue
			var run: int = 0
			while cell_y + run < cells.y and _cell_unmeasured(cell_x, cell_y + run):
				run += 1
			var period: int = mini(_period(cell_x, cell_y, run), MAX_CELLS)
			var group: int = region[cell_y * cells.x + cell_x]
			runs.append(Vector4i(cell_x, cell_y, run, group))
			periods.append(period)
			var tally: Dictionary = votes.get(group, {})
			tally[period] = int(tally.get(period, 0)) + run
			votes[group] = tally
			cell_y += run

	var agreed: Dictionary = {}
	for group: int in votes:
		var tally: Dictionary = votes[group]
		var best: int = 0
		for period: int in tally:
			var count: int = int(tally[period])
			var top: int = int(tally.get(best, -1))
			if count > top or (count == top and period < best):
				best = period
		agreed[group] = best

	for index: int in runs.size():
		var entry: Vector4i = runs[index]
		var height: int = mini(periods[index], int(agreed[entry.w])) * CELL_TILES * BAND
		var base: int = (entry.y + entry.z) * CELL_TILES - 1
		for step: int in entry.z:
			for row: int in CELL_TILES:
				var ty: int = (entry.y + step) * CELL_TILES + row
				for column: int in CELL_TILES:
					var at: int = ty * _size.x + entry.x * CELL_TILES + column
					# A pinned tile inside an otherwise unmeasured cell keeps
					# the height its pin gave it.
					if _heights[at] == -1:
						_heights[at] = height
						_bases[at] = base


## ONE FENCE, on the centre line of its walk cell.
##
## The profile is 8 px of drawing and a cell is 16, so an arm is TWO copies of it
## laid end to end, which is a post every tile exactly as the cartridge draws
## one. Each is cut into maximal rectangles the way `_cutout` cuts a drawing, for
## its reason: a rectangle of pixels maps onto a rectangle of texels exactly, so
## the picture is the drawing's and a fence is a few dozen boxes rather than a
## few hundred.
##
## THE ARMS RUN HALF A CELL EACH WAY FROM THE CENTRE, so a straight run is
## continuous and a corner is two arms crossing. A cell with no fence beside it
## keeps the drawing's own axis.
func _fence(tx: int, ty: int, ground: float, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	if _fence_mask.is_empty():
		_fence_profile(atlas)
	if _fence_mask.is_empty():
		return
	var arms: int = int(_fence_arms[at])
	var cell := Vector2i((tx - _margin.x) >> 1, (ty - _margin.y) >> 1)
	var middle := Vector2(
		_world_x(_margin.x + cell.x * CELL_TILES) + TILE,
		_world_z(_margin.y + cell.y * CELL_TILES) + TILE
	)
	if arms & FENCE_ACROSS:
		_fence_arm(middle, ground, true, atlas)
	if arms & FENCE_AWAY:
		_fence_arm(middle, ground, false, atlas)


## One arm, a whole cell long, centred on [param middle].
##
## [param across] runs it east to west and lays the drawing's own x along the
## world's; otherwise it runs north to south and the same drawing is turned a
## quarter, which is what the reviewer asked for rather than reading the second
## run's own tile, that tile being a line seen from above and no portrait of
## anything.
func _fence_arm(
	middle: Vector2, ground: float, across: bool, atlas: RefCounted
) -> void:
	var along: float = middle.x if across else middle.y
	var half_cell: float = float(CELL_TILES) * TILE * 0.5
	@warning_ignore("integer_division")
	var copies: int = maxi(1, CELL_TILES * TILE_PX / _fence_wide)
	for copy: int in copies:
		var start: float = along - half_cell + float(_fence_wide * copy)
		var taken := PackedByteArray()
		taken.resize(_fence_wide * _fence_tall)
		for py: int in _fence_tall:
			# A RECTANGLE MAY NOT CROSS A TILE, because a texel is only sampled out
			# of the tile it was drawn in, and the profile is a grid of them.
			@warning_ignore("integer_division")
			var stop: int = mini((py / TILE_PX + 1) * TILE_PX, _fence_tall)
			var px: int = 0
			while px < _fence_wide:
				if taken[py * _fence_wide + px] == 1 or _fence_mask[py * _fence_wide + px] == 0:
					px += 1
					continue
				@warning_ignore("integer_division")
				var edge: int = (px / TILE_PX + 1) * TILE_PX
				var run: int = px
				while run < edge and taken[py * _fence_wide + run] == 0 \
						and _fence_mask[py * _fence_wide + run] == 1:
					run += 1
				var deep: int = 1
				while py + deep < stop:
					var whole: bool = true
					for step: int in run - px:
						if taken[(py + deep) * _fence_wide + px + step] == 1 \
								or _fence_mask[(py + deep) * _fence_wide + px + step] == 0:
							whole = false
							break
					if not whole:
						break
					deep += 1
				for down: int in deep:
					for step: int in run - px:
						taken[(py + down) * _fence_wide + px + step] = 1
				# The profile's bottom row stands ON the ground and its top row
				# `_fence_tall` above it.
				var low: float = ground + float(_fence_tall - py - deep)
				var high: float = ground + float(_fence_tall - py)
				var tile: int = _profile_tile(px, py)
				var sub := Rect2i(px % TILE_PX, py % TILE_PX, run - px, deep)
				var half: float = FENCE_THICK * 0.5
				var box := AABB(
					Vector3(start + float(px), low, middle.y - half),
					Vector3(float(run - px), high - low, FENCE_THICK)
				) if across else AABB(
					Vector3(middle.x - half, low, start + float(px)),
					Vector3(FENCE_THICK, high - low, float(run - px))
				)
				# INTERIOR FACES ARE NOT DRAWN. A fence is a few dozen boxes and
				# most of the faces between two of them are inside the wood: the
				# lid under the piece above it, and the end against the piece
				# beside it. Checked against the profile rather than against the
				# boxes, which is the same answer and needs no bookkeeping.
				var cap: bool = _fence_open(px, run, py - 1, py)
				var west: bool = px == 0 or _fence_open(px - 1, px, py, py + deep)
				var east: bool = run == _fence_wide or _fence_open(run, run + 1, py, py + deep)
				_fence_box(box, atlas.uv_box(tile, sub),
					atlas.uv_box(tile, Rect2i(sub.position, Vector2i.ONE)),
					across, cap, west, east)
				px = run


## Whether any pixel of the profile in this box is NOT drawn, which is what says
## a face of it can be seen. Off the profile, so it is out of range at the top
## and the bottom and open there.
func _fence_open(from_x: int, to_x: int, from_y: int, to_y: int) -> bool:
	for py: int in range(from_y, to_y):
		if py < 0 or py >= _fence_tall:
			return true
		for px: int in range(from_x, to_x):
			if px < 0 or px >= _fence_wide or _fence_mask[py * _fence_wide + px] == 0:
				return true
	return false


## One box of the fence, wearing the drawing on the two faces that show it and
## one texel of the same rectangle on the four edges that do not.
func _fence_box(
	box: AABB, face: Rect2, edge: Rect2, across: bool,
	cap: bool, west: bool, east: bool
) -> void:
	var a: Vector3 = box.position
	var b: Vector3 = box.position + box.size
	if across:
		_quad(
			Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z),
			Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
			Vector3(0.0, 0.0, 1.0), face, SHADE_SOUTH
		)
		_quad(
			Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z),
			Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
			Vector3(0.0, 0.0, -1.0), face, SHADE_NORTH
		)
	else:
		_quad(
			Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z),
			Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z),
			Vector3(1.0, 0.0, 0.0), face, SHADE_SIDE
		)
		_quad(
			Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z),
			Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z),
			Vector3(-1.0, 0.0, 0.0), face, SHADE_SIDE
		)
	if cap:
		_quad(
			Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z),
			Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
			Vector3.UP, edge, SHADE_TOP_FLAT
		)
	if across:
		if east:
			_quad(
				Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z),
				Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z),
				Vector3(1.0, 0.0, 0.0), edge, SHADE_SIDE
			)
		if west:
			_quad(
				Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z),
				Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z),
				Vector3(-1.0, 0.0, 0.0), edge, SHADE_SIDE
			)
	else:
		if east:
			_quad(
				Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z),
				Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
				Vector3(0.0, 0.0, 1.0), edge, SHADE_SOUTH
			)
		if west:
			_quad(
				Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z),
				Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
				Vector3(0.0, 0.0, -1.0), edge, SHADE_NORTH
			)


## A FENCE IS POSTS AND RAILS, and both runs of it are the same model turned.
##
## What stood here before was the drawing extruded into a box a walk cell deep,
## which is a wall with a fence painted on it. The reviewer asked for the thing
## itself, centred, and for the two runs to be joined: "just do the same normal
## fence model, and then you try to do something to automate them so they are
## properly done and attached to eachother".
##
## THE UNIT IS THE WALK CELL AND THAT IS WHAT JOINS THEM. A fence going across is
## drawn over two tile rows and a fence going away over one tile column, so no
## tile is a whole fence and neighbouring TILES cannot say which way a run goes:
## the tile under a face-on fence is a fence tile too, and read per tile every
## straight run would come out a corner. Per cell there is no such confusion, and
## the arms of two neighbouring cells meet on their shared edge because each is
## on its own cell's centre line, which is the same line along a run.
func _measure_fences() -> void:
	_fence_arms.resize(_size.x * _size.y)
	_fence_arms.fill(0)
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	var here := PackedByteArray()
	here.resize(cells.x * cells.y)
	var any: bool = false
	for ty: int in _size.y:
		for tx: int in _size.x:
			if _art[ty * _size.x + tx] != ART_FENCE:
				continue
			any = true
			@warning_ignore("integer_division")
			here[(ty / CELL_TILES) * cells.x + tx / CELL_TILES] = 1
	if not any:
		return
	for cell_y: int in cells.y:
		for cell_x: int in cells.x:
			if here[cell_y * cells.x + cell_x] == 0:
				continue
			var arms: int = 0
			if (cell_x > 0 and here[cell_y * cells.x + cell_x - 1] == 1) \
					or (cell_x + 1 < cells.x and here[cell_y * cells.x + cell_x + 1] == 1):
				arms |= FENCE_ACROSS
			if (cell_y > 0 and here[(cell_y - 1) * cells.x + cell_x] == 1) \
					or (cell_y + 1 < cells.y and here[(cell_y + 1) * cells.x + cell_x] == 1):
				arms |= FENCE_AWAY
			# A fence cell on its own is a post and nothing else, and a stub of the
			# run it is drawn as reads better than nothing: take the drawing's own
			# axis, which is across wherever the face-on pair is what is drawn.
			if arms == 0:
				arms = FENCE_ACROSS
			for row: int in CELL_TILES:
				for column: int in CELL_TILES:
					var at: int = (cell_y * CELL_TILES + row) * _size.x \
						+ cell_x * CELL_TILES + column
					if _art[at] != ART_FENCE:
						continue
					_fence_arms[at] = arms
					# The fence stands ON the floor rather than being it, exactly as
					# a cutout does, so the tile keeps the ground of its own cell.
					_heights[at] = 0
					_volume[at] = 0


## THE FENCE'S OWN SHAPE, read off the tiles that draw it face-on.
##
## Three rules and the drawing answers everything else. THE SHADOW IS NOT THE
## FENCE: it is drawn under the foot in the middle shade, so every row below the
## last one carrying the DARKEST shade is dropped, which is the reviewer's own
## warning that "its not as dark as the outline". THE FLOOD MAY NOT COME IN FROM
## THE SIDES: a fence is a run, its rails cross the tile edge to edge and carry on
## into the next tile, so seeding the left and right borders the way every other
## mask here does eats every rail in the game. It comes in from the TOP alone,
## which is the one edge a fence really has, and a pocket the outside cannot
## reach is wood: the post's shaft, the rail's body and the inside of an arch are
## all drawn in the middle shades and all stand.
##
## AND THE GROUND SHOWS THROUGH BELOW THE DRAWING. What opens the gaps between
## the posts is the drawing stopping: every pixel below a column's lowest dark
## one is ground, so the rail carries on over a gap and the gap goes to the
## floor. That is why the flood needs no second seed under the foot, and it is
## the rule that lets an arched fence keep its arch: a seed under the foot has to
## be undone by filling each column between its topmost and bottommost pixel, and
## a fill like that closes any opening with drawing above and below it.
func _fence_profile(atlas: RefCounted) -> void:
	_fence_mask = PackedByteArray()
	_fence_tall = 0
	if _fence_tiles.size() < 2:
		return
	var across: int = (_fence_tiles[0] as Array).size()
	_fence_wide = across * TILE_PX
	var rows: int = _fence_tiles.size() * TILE_PX
	var dark := PackedByteArray()
	dark.resize(_fence_wide * rows)
	var foot: int = -1
	for py: int in rows:
		for px: int in _fence_wide:
			var index: int = atlas.pixel(_profile_tile(px, py), px % TILE_PX, py % TILE_PX)
			if atlas.is_dark(_profile_tile(px, py), index, 1):
				dark[py * _fence_wide + px] = 1
				foot = py
	if foot < 0:
		return
	_fence_tall = foot + 1
	var mask := PackedByteArray()
	mask.resize(_fence_wide * _fence_tall)
	mask.fill(1)
	var stack := PackedInt32Array()
	for px: int in _fence_wide:
		stack.append(px)
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if mask[at] == 0 or dark[at] == 1:
			continue
		mask[at] = 0
		@warning_ignore("integer_division")
		var py: int = at / _fence_wide
		var px: int = at % _fence_wide
		if px > 0:
			stack.append(at - 1)
		if px < _fence_wide - 1:
			stack.append(at + 1)
		if py > 0:
			stack.append(at - _fence_wide)
		if py < _fence_tall - 1:
			stack.append(at + _fence_wide)
	for px: int in _fence_wide:
		var foot_row: int = -1
		for py: int in _fence_tall:
			if dark[py * _fence_wide + px] == 1:
				foot_row = py
		for py: int in range(foot_row + 1, _fence_tall):
			mask[py * _fence_wide + px] = 0
	_fence_mask = mask


## Which tile of the fence's own drawing a pixel of the profile was painted in.
func _profile_tile(px: int, py: int) -> int:
	@warning_ignore("integer_division")
	var row: Array = _fence_tiles[py / TILE_PX] as Array
	@warning_ignore("integer_division")
	return int(row[px / TILE_PX])


## A ROCK RIM IS A 45 DEGREE SLOPE, not a step.
##
## The reviewer's own reading of the four-tile patches: "the outer ring would be
## all the small rock walls at 45 degree going from the floor to the upper rock
## floor". One tile of run per band, so an 8 px shelf ramps over one tile and a
## 16 px one over two, and the drawing says which tiles those are: the ring the
## cartridge draws round every patch IS the ramp.
##
## HOW FAR IN A TILE LIES is the whole measurement, and it is one flood: the low
## ground is 0, a tile touching it is 1, and a tile's corner stands at its own
## distance in bands, capped at the shelf's height. A 2 tile ring comes out 0 to
## 8 on its outer row and 8 to 16 on its inner one with nothing authored, and the
## flat top is every tile far enough in for the cap to bite.
##
## THE CORNER IS THE UNIT AND NOT THE TILE, which is what makes it watertight and
## what turns a corner of the ring into a real diagonal: two tiles sharing an
## edge read the same distance at the two corners of it, so the two slopes meet
## exactly and no skirt is needed between them. A rim tile only skirts where it
## meets something that is not shelf.
##
## LAST OF THE PASSES, because every one of them can still move a height: an
## object covering a rock hands it back to the floor, and a ramp measured before
## that would slope into a tile that is no longer there.
func _measure_ramps() -> void:
	var count: int = _size.x * _size.y
	_ramp.resize(count)
	_ramp.fill(0)
	_corners.resize(count * 4)
	for at: int in count:
		for corner: int in 4:
			_corners[at * 4 + corner] = _heights[at]
	var distance := PackedInt32Array()
	distance.resize(count)
	distance.fill(-1)
	var stack := PackedInt32Array()
	for at: int in count:
		if _shelf[at] == 0 or _heights[at] <= 0:
			continue
		var tx: int = at % _size.x
		@warning_ignore("integer_division")
		var ty: int = at / _size.x
		for step: Vector2i in [
			Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
		]:
			var to := Vector2i(tx + step.x, ty + step.y)
			if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
				continue
			var index: int = to.y * _size.x + to.x
			if _shelf[index] == 1 or _heights[index] >= _heights[at]:
				continue
			distance[at] = 1
			stack.append(at)
			break
	var head: int = 0
	while head < stack.size():
		var at: int = stack[head]
		head += 1
		var tx: int = at % _size.x
		@warning_ignore("integer_division")
		var ty: int = at / _size.x
		for step: Vector2i in [
			Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
		]:
			var to := Vector2i(tx + step.x, ty + step.y)
			if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
				continue
			var index: int = to.y * _size.x + to.x
			if distance[index] >= 0 or _shelf[index] == 0 or _heights[index] <= 0:
				continue
			distance[index] = distance[at] + 1
			stack.append(index)

	for at: int in count:
		if distance[at] < 0:
			continue
		var tx: int = at % _size.x
		@warning_ignore("integer_division")
		var ty: int = at / _size.x
		var sloped: bool = false
		for corner: int in 4:
			var step := Vector2i(-1 if corner % 2 == 0 else 1, -1 if corner < 2 else 1)
			# The four tiles that meet at this corner, the nearest of them to the
			# low ground being what the corner stands at.
			var near: int = distance[at]
			for reach: Vector2i in [
				Vector2i(step.x, 0), Vector2i(0, step.y), step
			]:
				var to := Vector2i(tx + reach.x, ty + reach.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					near = 0
					continue
				var index: int = to.y * _size.x + to.x
				# Anything that is not shelf and stands no higher is the ground the
				# rim comes down to; anything standing on the shelf is not.
				if _shelf[index] == 0:
					if _heights[index] < _heights[at]:
						near = 0
					continue
				near = mini(near, maxi(distance[index], 0))
			var high: int = mini(near * BAND, _heights[at])
			_corners[at * 4 + corner] = high
			sloped = sloped or high < _heights[at]
		if sloped:
			_ramp[at] = 1
			# A ramp is a floor with a slope on it, not a box: whatever the tile was
			# resolved as, its drawing is now the surface the player walks up.
			_art[at] = ART_FLAT
			_volume[at] = 0


## A CLIFF IS AS TALL AS ITS FACE IS DRAWN, in 8px bands.
##
## Every other height here is measured per COLUMN OF WALK CELLS, so the smallest
## thing it can say is 16 px, and it says it by the PERIOD of the run: a rock
## patch four tiles square is one cell of face over one cell of top and measures
## two cells, which is 32 px of stone round an 8 px shelf. Ecruteak's pond patches
## were exactly that, and the reviewer's reading of the same drawing is the one
## this pass takes: "in 2D you can see they are 8px high".
##
## THE FACE ITSELF IS THE HONEST STATEMENT and `profile.gd:FRONTS` is the tile
## that draws it, so the run of front tiles up a column IS the height in bands.
## One row of face is 8, two rows is 16, and nothing has to be authored per
## tileset that the survey has not already named.
##
## Read per STRUCTURE and not per column, which is the region rule again and for
## its reason: a rim column draws no front at all, and what says how tall a rim
## stands is the rock it belongs to. Each column votes with the length of its own
## front run and the commonest wins, so a face that is two tiles nearly
## everywhere is not lifted by the one column where a cave mouth is cut into it.
## A structure with no front anywhere keeps what the column pass measured: only
## the front knows which side of a wall is up, and a rim seen from its end says
## nothing at all.
func _measure_cliffs() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	for start: int in seen.size():
		if seen[start] == 1 or _cliff[start] == 0:
			continue
		var members := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var at: int = stack.pop_back()
			members.append(at)
			var tx: int = at % _size.x
			@warning_ignore("integer_division")
			var ty: int = at / _size.x
			for step: Vector2i in [
				Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
			]:
				var to := Vector2i(tx + step.x, ty + step.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					continue
				var index: int = to.y * _size.x + to.x
				if seen[index] == 1 or _cliff[index] == 0:
					continue
				seen[index] = 1
				stack.append(index)
		var bands: int = _face_bands(members)
		if bands <= 0:
			continue
		for at: int in members:
			_heights[at] = bands * BAND
			_bases[at] = _cliff_base(at)
			_shelf[at] = 1


## How many bands of face one structure draws: every column's own run of FRONT
## tiles votes with its length, and the commonest run wins. A tie goes to the
## shorter, which is this file's standing rule that a structure too tall is worse
## than one too short.
func _face_bands(members: PackedInt32Array) -> int:
	var runs: Dictionary = {}
	for at: int in members:
		if _front[at] == 0:
			continue
		# Counted once per run, off its topmost tile, so a two-tile face is one
		# vote of two rather than two votes of two and one.
		if at >= _size.x and _front[at - _size.x] == 1:
			continue
		var run: int = 0
		var walk: int = at
		while walk < _front.size() and _front[walk] == 1:
			run += 1
			walk += _size.x
		runs[run] = int(runs.get(run, 0)) + run
	var best: int = 0
	for run: int in runs:
		var count: int = int(runs[run])
		var top: int = int(runs.get(best, -1))
		if count > top or (count == top and run < best):
			best = run
	return best


## The bottom row of the cliff run this tile sits in, which is the row its bands
## are sampled up from. A face folds its own drawing upward, so a two-band wall
## reads its lower tile at the bottom and the tile above it at the top.
func _cliff_base(at: int) -> int:
	var walk: int = at
	while walk + _size.x < _cliff.size() and _cliff[walk + _size.x] == 1:
		walk += _size.x
	@warning_ignore("integer_division")
	return walk / _size.x


## The ground BEHIND a cliff stands on top of it.
##
## Every other height in this mesher is a fact about one column, and a plateau is
## the case where one column is not enough: a rock wall is 16 px of drawn face
## and the stone floor north of it is a second surface at the top of that face,
## with nothing in the column of either one to say so. The reviewer's words:
## "rock walls are two tiles high, and then its the higher flat floor".
##
## What says which floor is up there is the cliff itself, and only the cliff.
## Its face is pinned in `profile.gd:CLIFFS`; the connected structure is read as
## a whole, so each column of it gives two pieces of evidence about the flat
## ground it touches:
##
##   north of its topmost row  the ground up there, at that column's height
##   south of its bottom row   the ground in front, which is where 0 is
##
## Both are then carried across the flat ground by flooding it, because a plateau
## is a REGION and not a strip: only the rim column knows the height and the
## whole enclosed floor stands at it.
##
## A region carrying both kinds of evidence is left alone. That is not a
## compromise, it is the whole safety of this pass: the ground north of a
## diagonal end tile is the LOW ground wrapping round the corner, the two sides
## of a cliff meet wherever a map lets the player walk up, and a leak through any
## of that reaches a region the front of the cliff is already standing on. Raise
## on unanimous evidence and a leak costs nothing; raise on a majority and one
## leak lifts a whole town by a cell. The reviewer's own rule elsewhere in this
## file, that a structure too tall is worse than one too short, is the same rule.
##
## Water is not flat ground for this: it bounds a region rather than joining one,
## so a pond up on a shelf stays a pond rather than dragging the shelf down to it.
func _measure_plateaus() -> void:
	var seeds: Dictionary = {}
	var fronts: Dictionary = {}
	if not _cliff_evidence(seeds, fronts):
		return

	var region := PackedInt32Array()
	region.resize(_size.x * _size.y)
	region.fill(-1)
	# Per region: the lowest height the evidence above it agrees on, and whether
	# any of its tiles is ground the cliff stands ON.
	var lift: Dictionary = {}
	var blocked: Dictionary = {}
	var next: int = 0
	var stack: Array[int] = []
	for start: int in region.size():
		if region[start] != -1 or not _is_plateau_floor(start):
			continue
		region[start] = next
		stack.append(start)
		var members := PackedInt32Array()
		while not stack.is_empty():
			var at: int = stack.pop_back()
			members.append(at)
			if seeds.has(at):
				var height: int = int(seeds[at])
				lift[next] = mini(int(lift.get(next, height)), height)
			if fronts.has(at):
				blocked[next] = true
			var tx: int = at % _size.x
			@warning_ignore("integer_division")
			var ty: int = at / _size.x
			for step: Vector2i in [
				Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
			]:
				var to := Vector2i(tx + step.x, ty + step.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					continue
				var index: int = to.y * _size.x + to.x
				if region[index] != -1 or not _is_plateau_floor(index):
					continue
				region[index] = next
				stack.append(index)
		if not blocked.has(next) and lift.has(next):
			var height: int = int(lift[next])
			for at: int in members:
				_heights[at] = height
				_shelf[at] = 1
		next += 1
	_settle_lips()
	_settle_ponds()


## The plateau's far edge belongs to the plateau, so it takes the height of the
## ground on its own SOUTH side once that ground has been settled. It is left out
## of the regions themselves because it is where one ends: the low ground north
## of a lip is a different surface, with nothing between the two but the seam
## drawn along the lip's own top row.
func _settle_lips() -> void:
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _lip[at] == 0 or ty + 1 >= _size.y:
				continue
			var under: int = _heights[(ty + 1) * _size.x + tx]
			if _art[(ty + 1) * _size.x + tx] == ART_FLAT and under > 0:
				_heights[at] = under
				# A LIP STANDING ON A SHELF IS THAT SHELF'S RIM, which is what lets
				# it ramp with the other three sides. It is the one side of a rock
				# a face cannot be drawn on, so the cliff pass never reaches it and
				# nothing else marks it: without this a patch slopes on the sides
				# the cartridge draws face-on and steps on the side it draws from
				# above.
				_shelf[at] = 1


## Water lying ON a plateau goes up with it.
##
## Water is not ground and is deliberately no part of a plateau region: a lake is
## drawn recessed and joining one to the floor around it would let a shoreline
## carry a height across a whole map. But a pool with nothing but raised floor
## around it is a pool up on the shelf, and leaving it behind cuts a hole through
## the rock down to the plain. So a body of water every one of whose neighbours
## stands at the same raised height rises by it and keeps its own recess, which
## is what still puts the lip on its shore.
func _settle_ponds() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var stack: Array[int] = []
	for start: int in seen.size():
		if seen[start] == 1 or not _is_water(start):
			continue
		seen[start] = 1
		stack.append(start)
		var members := PackedInt32Array()
		# The one height every shore of it agrees on, or -1 for no agreement.
		var shore: int = 0
		while not stack.is_empty():
			var at: int = stack.pop_back()
			members.append(at)
			var tx: int = at % _size.x
			@warning_ignore("integer_division")
			var ty: int = at / _size.x
			for step: Vector2i in [
				Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
			]:
				var to := Vector2i(tx + step.x, ty + step.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					# A map edge is not a shore that can vouch for anything.
					shore = -1
					continue
				var index: int = to.y * _size.x + to.x
				if _is_water(index):
					if seen[index] == 0:
						seen[index] = 1
						stack.append(index)
					continue
				var height: int = maxi(_heights[index], 0)
				if shore == 0:
					shore = height
				elif shore != height:
					shore = -1
		if shore > 0:
			for at: int in members:
				_heights[at] += shore


func _is_water(at: int) -> bool:
	return _tiles[at] >= 0 and _art[at] == ART_FLAT and _heights[at] < 0


## What each run of cliff face says about the flat ground it touches, as tile
## index -> height for the ground above one and tile index -> true for the ground
## it stands on. False when the map holds no cliff at all, which is all but a
## handful of them.
##
## The unit is the RUN: one column's own uninterrupted band of cliff face, and
## not the connected structure. A cliff rings its plateau, so the structure is
## the rim of a bowl, and its topmost row in a column on the west rim has nothing
## to say about what stands above the face on the south rim.
##
## A run speaks only if it holds a FRONT band, which is the drawing that faces
## the screen with the raised floor immediately above it. That is what makes
## either answer mean anything: the west rim of the same cliff has the plateau on
## one side of it and the low ground on the other, and reading it as a front
## calls the plateau the ground the wall stands on.
func _cliff_evidence(seeds: Dictionary, fronts: Dictionary) -> bool:
	var any: bool = false
	for tx: int in _size.x:
		var ty: int = 0
		while ty < _size.y:
			if _cliff[ty * _size.x + tx] == 0:
				ty += 1
				continue
			any = true
			var run: int = 0
			var faces_front: bool = false
			while ty + run < _size.y and _cliff[(ty + run) * _size.x + tx] == 1:
				faces_front = faces_front or _front[(ty + run) * _size.x + tx] == 1
				run += 1
			if faces_front:
				var above: int = ty - 1
				if above >= 0 and _is_plateau_floor(above * _size.x + tx):
					var height: int = _cliff_height(tx, ty)
					if height > 0:
						var index: int = above * _size.x + tx
						seeds[index] = mini(int(seeds.get(index, height)), height)
				var below: int = ty + run
				if below < _size.y and _is_plateau_floor(below * _size.x + tx):
					fronts[below * _size.x + tx] = true
			ty += run
	return any


## How tall the cliff stands in one column: the tallest band any of its tiles in
## that column was measured at. A column can hold a tile the cell pass left
## unsettled at -1, which is a real case wherever a pin and an unpinned tile
## share a walk cell, so the reading is taken over the run rather than off the
## one row.
func _cliff_height(tx: int, top_row: int) -> int:
	var height: int = 0
	var ty: int = top_row
	while ty < _size.y and _cliff[ty * _size.x + tx] == 1:
		height = maxi(height, _heights[ty * _size.x + tx])
		ty += 1
	return height


## The ground a plateau is made of: flat art standing on the ground plane. Water
## is flat too and is deliberately not this, and anything already raised has been
## measured off its own drawing and is not a floor to be lifted.
func _is_plateau_floor(at: int) -> bool:
	return (
		_tiles[at] >= 0 and _art[at] == ART_FLAT and _heights[at] == 0
		and _lip[at] == 0
	)


## Connected unmeasured cells, four ways, numbered. -1 is a cell that is not part
## of any structure.
func _regions(cells: Vector2i) -> PackedInt32Array:
	var region := PackedInt32Array()
	region.resize(cells.x * cells.y)
	region.fill(-1)
	var next: int = 0
	var stack: Array[Vector2i] = []
	for start_y: int in cells.y:
		for start_x: int in cells.x:
			if region[start_y * cells.x + start_x] != -1:
				continue
			if not _cell_unmeasured(start_x, start_y):
				continue
			region[start_y * cells.x + start_x] = next
			stack.append(Vector2i(start_x, start_y))
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				for step: Vector2i in [
					Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
				]:
					var to: Vector2i = at + step
					if to.x < 0 or to.y < 0 or to.x >= cells.x or to.y >= cells.y:
						continue
					if region[to.y * cells.x + to.x] != -1:
						continue
					if not _cell_unmeasured(to.x, to.y):
						continue
					region[to.y * cells.x + to.x] = next
					stack.append(to)
			next += 1
	return region


## THE VOID HAS NO HEIGHT OF ITS OWN, and until a roof fell below the ground
## plane nothing in the game could tell.
##
## Past the edge of the world the cartridge draws a flat colour and this view
## lays it down as one quad at 0, which is right everywhere it borders ordinary
## ground and wrong the moment it borders anything lower: the great roof of a
## building falls a walk cell a tile from its ridge to its eaves, and a void
## standing at 0 round it walls the whole roof into a grey pit, which is what the
## first picture of it showed.
##
## So a connected field of void takes the LOWEST floor it touches anywhere. Lowest
## and not nearest, so the whole field lies flat and no seam runs through it; and
## a FLOOR rather than any neighbour, so a cave's void, which touches nothing but
## the faces of walls, is left exactly where it was. It can only ever come down,
## which is what makes it safe: measured over every map, one map moves.
func _settle_void() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var region := PackedInt32Array()
	for start: int in _size.x * _size.y:
		if _void[start] == 0 or seen[start] == 1:
			continue
		region.clear()
		region.append(start)
		seen[start] = 1
		var floor_height: int = 0
		var head: int = 0
		while head < region.size():
			var at: int = region[head]
			head += 1
			var tx: int = at % _size.x
			var ty: int = at / _size.x
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var to := Vector2i(tx + step.x, ty + step.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					continue
				var index: int = to.y * _size.x + to.x
				if _void[index] == 1:
					if seen[index] == 0:
						seen[index] = 1
						region.append(index)
					continue
				# A wall's face says nothing about where the ground behind it is,
				# and an unmeasured tile says nothing at all yet. A NEGATIVE height
				# is not unmeasured: -1 is the sentinel and every real height is a
				# whole number of bands, so testing for "below zero" here skipped
				# the one floor this pass exists to follow.
				if _volume[index] == 1 or _heights[index] == -1:
					continue
				floor_height = mini(floor_height, _heights[index])
		if floor_height == 0:
			continue
		for at: int in region:
			_heights[at] = floor_height


## Anything the measuring passes never reached, given a height at last.
##
## `_measure_columns` works in whole CELLS and reads one tile to decide whether a
## cell is unmeasured, so a cell holding a pin and an unpinned tile together is
## skipped and the unpinned one keeps the -1 it was marked with. That was rare
## while the profile held a handful of pins by hand and is common now that a pass
## over the game has written a thousand: a -1 is a face drawn a pixel below the
## floor, which reads as a seam of black around the furniture.
##
## The cell it sits in is the answer: whatever else in that cell did get
## measured, and one cell tall when nothing did.
func _settle_unmeasured() -> void:
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _heights[at] != -1:
				continue
			var settled: int = -1
			var cell := Vector2i((tx >> 1) * CELL_TILES, (ty >> 1) * CELL_TILES)
			for row: int in CELL_TILES:
				for column: int in CELL_TILES:
					var here: int = (cell.y + row) * _size.x + cell.x + column
					if here < _heights.size() and _heights[here] > settled:
						settled = _heights[here]
			_heights[at] = settled if settled > 0 else CELL_TILES * BAND


## A thing standing ON furniture starts at the furniture's own top.
##
## A radio, a television, a computer, a statue, a book: the reviewer named a
## dozen of them and every one is drawn sitting on a desk or a table. Every class
## carries a height off the GROUND, so all of them stood up through the desk from
## the floor instead.
##
## What they stand on is whatever the mesher already resolved for the cell in
## front, which for a table is its top: the run of them takes that as its base
## and stacks its own rows above it. The same shape of answer as a facade
## standing on a porch roof, and for the same reason.
func _measure_furniture() -> void:
	var placed := PackedByteArray()
	placed.resize(_size.x * _size.y)
	for ty: int in range(_size.y - 1, -1, -1):
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _on_furniture[at] == 0 or placed[at] == 1:
				continue
			# The bottom of the run is this tile, since rows are walked upward.
			# What it stands on is the cell in front of it, whatever the rest of
			# the resolve made that: a table top, a counter, the floor.
			var under: int = 0
			if ty + 1 < _size.y:
				under = maxi(_heights[(ty + 1) * _size.x + tx], 0)
			var run: int = 1
			while ty - run >= 0 and _on_furniture[(ty - run) * _size.x + tx] == 1:
				run += 1
			# One height for the whole object, or a television comes out as a
			# staircase of its own rows.
			var top: int = under + run * BAND
			for step: int in run:
				var index: int = at - step * _size.x
				_heights[index] = top
				@warning_ignore("integer_division")
				_bases[index] = ty + under / BAND
				_volume[index] = 1
				placed[index] = 1


## THE BOX one drawing is cut over, in tiles: where it starts on the block grid
## and how much of it the drawing uses.
##
## The start is always the grid box, whatever `_measure_cutouts` cut the height
## back to, or a drawing three tiles tall would be read modulo three and every
## box below the first would start in the middle of the one above it.
func _span_box(at: int, tx: int, ty: int) -> Rect2i:
	var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
	var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
	if _span_cut[at] > 0:
		across.y = int(_span_cut[at])
	return Rect2i(start, across)


## How big each cutout's drawing actually is where it is PLACED.
##
## A class declares the largest its drawing gets, and the placement is what says
## whether this one is that big: the small brick flower bed and the tall one are
## drawn out of the same top and bottom tiles, one cell of them and two, and no
## tile id can tell those apart. So the class's own box is taken where every cell
## in it carries that class, and one cell otherwise.
##
## Carrying the class is not enough on its own, because a thing standing next to
## another of itself carries it twice. A DRAWING THAT REPEATS IS NOT ONE DRAWING:
## where a cell of the box draws exactly what another cell of it draws, the box
## is a row of small things rather than one large one. Tileset 1 is the case and
## it is 4542 trees: a tall conifer is a pointed cell over a footed cell and the
## two differ, where a pair of short ones is the same cell twice.
##
## Except where the extra cells are DEPTH, because there a repeat is the drawing:
## the long flower bed is the same bed carrying on away from the eye and draws
## the identical cell twice on purpose. `LYING` is that distinction and it is
## already made.
##
## AND A DRAWING IS A WHOLE NUMBER OF TILES, not of cells, which is what the box
## cannot say on its own. A cell is two tiles, so a potted plant three tiles tall
## fills one cell and the top half of the next, and its box's bottom row is the
## floor it stands on. Requiring the whole box collapsed that to one cell each
## way and stood the leaves on the ground BESIDE the pot, which is the fault the
## box exists to fix. So the box is cut back to the last tile row that carries
## the class, and the rows above it must all carry it: `_span_cut` is how many
## rows are left, and `_cutout` reads it as the drawing's own height.
##
## Only where the extra cells are height. A LYING drawing's rows are depth and
## half a cell of depth is not something the cartridge draws.
func _measure_cutouts() -> void:
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _art[at] != ART_CUTOUT or (_span_x[at] == 1 and _span_y[at] == 1):
				continue
			var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
			var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
			var rows: int = across.y
			if _lying[at] == 0:
				while rows > CELL_TILES \
						and not _row_carries(start, rows - 1, across.x, _klass[at]):
					rows -= 1
			var whole: bool = true
			for row: int in rows:
				if not _row_carries(start, row, across.x, _klass[at]):
					whole = false
					break
			if whole and _lying[at] == 0:
				whole = not _repeats(start, Vector2i(int(_span_x[at]), int(_span_y[at])))
			if not whole:
				_span_x[at] = 1
				_span_y[at] = 1
			else:
				_span_cut[at] = rows if rows < across.y else 0


## Whether ANY tile of one ROW of the box at [param start] is [param klass],
## which is what says the row is part of the drawing at all. `_row_carries` next
## to it asks whether the row is WHOLLY the drawing, which is a different
## question and answers a different one: see `_cutout`.
func _row_holds(start: Vector2i, row: int, wide: int, klass: int) -> bool:
	var ty: int = start.y + row
	if ty >= _size.y:
		return false
	for column: int in wide:
		var tx: int = start.x + column
		if tx < _size.x and _klass[ty * _size.x + tx] == klass:
			return true
	return false


## Whether every tile of one ROW of the box at [param start] carries
## [param klass].
func _row_carries(start: Vector2i, row: int, wide: int, klass: int) -> bool:
	var ty: int = start.y + row
	if ty >= _size.y:
		return false
	for column: int in wide:
		var tx: int = start.x + column
		if tx >= _size.x or _klass[ty * _size.x + tx] != klass:
			return false
	return true


## Whether any cell of the box at [param start] draws exactly what another cell
## of it draws, in walk cells.
func _repeats(start: Vector2i, span: Vector2i) -> bool:
	var seen: Dictionary = {}
	for row: int in span.y:
		for column: int in span.x:
			var cell: Array = []
			for down: int in CELL_TILES:
				for right: int in CELL_TILES:
					cell.append(_tile_at(
						start.x + column * CELL_TILES + right,
						start.y + row * CELL_TILES + down
					))
			var key: String = str(cell)
			if seen.has(key):
				return true
			seen[key] = true
	return false


## Whether the tile ids at [param tx],[param ty] are the arrangement
## [param pattern] draws. A -1 in the pattern is a tile the object covers and has
## no opinion about.
func _pattern_at(pattern: Array, across: Vector2i, tx: int, ty: int) -> bool:
	for row: int in across.y:
		var line: Array = pattern[row]
		for column: int in across.x:
			var want: int = int(line[column])
			if want >= 0 and _tile_at(tx + column, ty + row) != want:
				return false
	return true


## AN OBJECT IS NOT A TILE, and this is what finds one.
##
## Every other pass here resolves a tile and stands it up where that tile sits,
## and for a wall or a canopy that is right, because the cartridge draws those
## tile by tile. A CHAIR is drawn as four corners across four tiles and no one of
## them is a chair: tileset 13's tile 74 is the desk's bottom-left leg, the
## chair's top-left corner and the floor between the two, so every possible pin
## for it is wrong. The reviewer raised it and named the fix: detect the tiles of
## each object, then place ONE thing of the whole object's size at its own
## position.
##
## The ARRANGEMENT OF TILE IDS is what identifies it, and it is exact: a pattern
## found anywhere in the grid is that object, wherever the map places it and
## whatever block boundary it straddles. The desk's drawing crosses one.
##
## EVERY TILE IT COVERS GOES BACK TO BEING FLOOR. That is the third thing this
## needed and it is free here: a covered tile is marked as a cutout, which already
## means "the ground beside me, with whatever stands on it drawn separately", so
## the seam beside the object stops extruding and the floor runs under it. What
## stands on it is then the object, emitted whole from any one of its tiles.
##
## Two objects may cover the same tile and both are drawn, which is the desk and
## the chair below it.
##
## A RECTANGLE IS NOT A FOOTPRINT once an object is bigger than a stick of
## furniture. The ship's box holds open sea at all four corners, and handing that
## sea to the floor lays a still slab across the harbour, so those tiles are
## declared OUTSIDE: matched against nothing, covered by nothing, left as they
## were. They stay in the rectangle the MASK is cut over, which is what makes
## them worth naming rather than cropping away: a border flood needs a border of
## open water to read, and the ship reaches the edge of its own hull.
func _measure_objects(shape: RefCounted) -> void:
	_object_covered.resize(_size.x * _size.y)
	_object_covered.fill(0)
	_object_over.clear()
	_objects.clear()
	var outside: int = shape.object_outside()
	var declared: Array = shape.objects()
	for object: Dictionary in declared:
		var pattern: Array = object[&"tiles"]
		var across := Vector2i((pattern[0] as Array).size(), pattern.size())
		for ty: int in _size.y - across.y + 1:
			for tx: int in _size.x - across.x + 1:
				if not _pattern_at(pattern, across, tx, ty):
					continue
				var index: int = _objects.size()
				_objects.append([object, Vector2i(tx, ty), across])
				# EVERY FLOOR IS READ BEFORE ANY TILE IS MARKED. `_cell_floor` takes
				# the highest FLAT tile in the cell, and marking a tile a cutout takes
				# it out of that answer, so reading and writing in one pass lets the
				# first tile of an object change what the next three measure. Flat
				# rooms hide it; a raised one would tilt the object.
				var floors := PackedInt32Array()
				for row: int in across.y:
					for column: int in across.x:
						floors.append(_cell_floor((tx + column) >> 1, (ty + row) >> 1))
				for row: int in across.y:
					for column: int in across.x:
						if int((pattern[row] as Array)[column]) == outside:
							continue
						var at: int = (ty + row) * _size.x + tx + column
						_object_covered[at] = 1
						_art[at] = ART_CUTOUT
						_modelled[at] = 0
						_volume[at] = 0
						_tufted[at] = 0
						_cliff[at] = 0
						_front[at] = 0
						_lip[at] = 0
						_heights[at] = floors[row * across.x + column]
						var over: PackedInt32Array = _object_over.get(
							at, PackedInt32Array()
						)
						over.append(index)
						_object_over[at] = over


## How far a flight rises or falls, in world pixels. One walk cell each way, on a
## 45 degree ramp, which is the reviewer's own reading of the drawing.
##
## HOW MANY STEPS is the drawing's own business and they counted them one by one:
## most are four, several are three and the grand staircases are five. So it is
## declared per flight and the tread is the rise divided by it.
const STAIR_RISE: int = 16
const STAIR_STEPS: int = 4


## THE STAIRCASES, found exactly as an object is and marked as a floor that is
## somewhere other than zero.
##
## A DOWN flight is a HOLE, which is the reviewer's own word for it, and the mesh
## already knows how to draw one: put the cell's floor a walk cell BELOW the
## ground and every neighbour skirts down to it, because `_side` draws a face
## wherever a neighbour stands lower and does not care whether that is a cliff or
## a stairwell. So the pit's four walls, its floor and the seam around it all come
## from the passes that were already there, and `_emit_stairs` adds only the steps
## standing in it.
func _measure_stairs(shape: RefCounted) -> void:
	_stair_at.resize(_size.x * _size.y)
	_stair_at.fill(-1)
	_stairs.clear()
	for flight: Dictionary in shape.stairs():
		var pattern: Array = flight[&"tiles"]
		var across := Vector2i((pattern[0] as Array).size(), pattern.size())
		for ty: int in _size.y - across.y + 1:
			for tx: int in _size.x - across.x + 1:
				if not _pattern_at(pattern, across, tx, ty):
					continue
				var base: int = _cell_floor(tx >> 1, ty >> 1)
				var index: int = _stairs.size()
				_stairs.append([flight, Vector2i(tx, ty), base, across])
				var rise: int = int(flight.get(&"rise", STAIR_RISE))
				var fall: int = -rise if bool(flight[&"down"]) else 0
				for row: int in across.y:
					for column: int in across.x:
						var at: int = (ty + row) * _size.x + tx + column
						_stair_at[at] = index
						_art[at] = ART_FLAT
						_volume[at] = 0
						_tufted[at] = 0
						_cliff[at] = 0
						_front[at] = 0
						_lip[at] = 0
						_heights[at] = base + fall


## The jumping ledges, taken from the COLLISION byte rather than from a drawing.
##
## Which way a ledge faces is not a judgement and must not be read off the art:
## `Gen2WorldCollision.allows_hop` decodes it bit for bit against the cartridge's
## own .TryJump. The code sits on the cell the player STANDS on, so the ledge
## itself is the blocked cell the hop passes over, and the lip is drawn in the
## FAR HALF of that cell, one tile deep, with the near half plain floor. Measured
## over every map: 1380 cells hopped over, 2760 lip tiles, 72 maps, and not one
## tile is claimed by two facings, so a wedge never has to choose. Only south,
## east and west occur; nothing in the game is hopped northward.
##
## They stood a full walk cell tall before this, which is a wall you cannot see
## over: 2298 of the 2760 measured 16px up the column, because a blocked cell
## with no pin resolves to `wall` like everything else. The wedge is one band,
## which is what the cartridge draws the lip as.
##
## The foot of the ramp is the ground the player hops FROM, not the tile beside
## it. In 240 cases the near half of the cell is itself a structure, and taking
## its height would stand the ledge on top of the wall it is cut into.
##
## The height written here is the foot, so every neighbour sees the wedge at the
## ground it rises from and skirts down to it as it would to any floor. Nothing
## else in the mesh has to know about the slope.
func _measure_ledges(source: RefCounted) -> void:
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	for cy: int in cells.y:
		for cx: int in cells.x:
			var code: int = source.code_at(Vector2i(cx, cy) - _margin_cells())
			if (code & 0xF0) != Gen2WorldCollision.HI_NYBBLE_LEDGES:
				continue
			var base: int = _cell_floor(cx, cy)
			for step: Vector2i in [
				Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT
			]:
				if not Gen2WorldCollision.allows_hop(code, step):
					continue
				var over := Vector2i(cx, cy) + step
				if over.x < 0 or over.y < 0 or over.x >= cells.x or over.y >= cells.y:
					continue
				for tile: Vector2i in _far_half(over, step):
					var at: int = tile.y * _size.x + tile.x
					if _tiles[at] < 0:
						continue
					_ledge[at] = _ledge_facing(step)
					_heights[at] = base
					_art[at] = ART_LEDGE
					_volume[at] = 0
					_cliff[at] = 0
					_front[at] = 0
					_lip[at] = 0
					# The drop wears the lip's own drawing rather than folding in
					# whatever structure the column pass had put this tile in.
					_bases[at] = tile.y


## The two tiles of [param cell] on the far side of [param step].
func _far_half(cell: Vector2i, step: Vector2i) -> Array:
	var base: Vector2i = cell * CELL_TILES
	if step.y > 0:
		return [Vector2i(base.x, base.y + 1), Vector2i(base.x + 1, base.y + 1)]
	if step.y < 0:
		return [Vector2i(base.x, base.y), Vector2i(base.x + 1, base.y)]
	if step.x > 0:
		return [Vector2i(base.x + 1, base.y), Vector2i(base.x + 1, base.y + 1)]
	return [Vector2i(base.x, base.y), Vector2i(base.x, base.y + 1)]


func _ledge_facing(step: Vector2i) -> int:
	if step.y > 0:
		return LEDGE_SOUTH
	if step.y < 0:
		return LEDGE_NORTH
	if step.x > 0:
		return LEDGE_EAST
	return LEDGE_WEST


func _ledge_step(facing: int) -> Vector2i:
	match facing:
		LEDGE_SOUTH:
			return Vector2i(0, 1)
		LEDGE_NORTH:
			return Vector2i(0, -1)
		LEDGE_EAST:
			return Vector2i(1, 0)
	return Vector2i(-1, 0)


## The floor of one walk cell: the highest flat tile in it, and zero where the
## cell holds none.
func _cell_floor(cell_x: int, cell_y: int) -> int:
	var best: int = 0
	for ty: int in range(cell_y * CELL_TILES, (cell_y + 1) * CELL_TILES):
		for tx: int in range(cell_x * CELL_TILES, (cell_x + 1) * CELL_TILES):
			if tx >= _size.x or ty >= _size.y:
				continue
			var at: int = ty * _size.x + tx
			if _art[at] == ART_FLAT and _heights[at] > best:
				best = _heights[at]
	return best


## A building is measured off its own drawing's GRID, not off its tile ids.
##
## One Generation II drawing packs several surfaces at once: the bottom rows are
## the facade seen face-on, the rows above them are the roof seen from above, and
## a taller section behind can put another facade above that roof again. So the
## height of a tile is decided by what is UNDER it in the same column, and the
## profile only says which of the two surfaces each drawing is.
##
## Rows run from the bottom of the map up, so every column knows what it is
## standing on before it is asked how high it reaches:
##
##   a wall run  folds face-on the way any volume does. The whole run is one
##               height, so a facade is a wall and not a staircase, and its fold
##               starts at the run's own bottom row lifted by what is beneath it.
##               Where its top bands are a roof drawn face-on they LEAN BACK over
##               the footprint instead of standing square: see `_facade_pitch`.
##   a roof row  lies flat at the height its own row agrees on, and passes that
##               height up to whatever stands on it.
##
## The row agrees rather than the column, because the columns carrying a gable
## have no wall under them at all: the flat section is what knows how high the
## roof is, and a sloped tile is that height less the band or two the drawing
## says it has fallen. A run is broken at every column that is not roof, so two
## buildings in one map row never agree with each other. A roof never falls below
## what its own column already stands at, or a gable meeting a low wing would
## drive its corner into the ground.
func _measure_buildings() -> void:
	var column := PackedInt32Array()
	column.resize(_size.x)
	var placed := PackedByteArray()
	placed.resize(_size.x * _size.y)
	# Written only where a pitch leans, and a mesher resolves map after map, so a
	# grid the same size as the last one would carry its roofs across.
	_pitched.fill(0)

	for ty: int in range(_size.y - 1, -1, -1):
		var wall: int = 0
		while wall < _size.x:
			var at: int = ty * _size.x + wall
			if _part[at] != PART_WALL or placed[at] == 1:
				wall += 1
				continue
			var last: int = wall
			while last + 1 < _size.x and _part[ty * _size.x + last + 1] == PART_WALL \
					and placed[ty * _size.x + last + 1] == 0:
				last += 1
			# The stretch agrees on one height, or a facade whose columns measure
			# differently comes out as a staircase rather than as a wall.
			var runs: PackedInt32Array = PackedInt32Array()
			var bands: int = 0
			# THE STRETCH AGREES ON ITS PITCH TOO, and on the SHALLOWEST of them,
			# for the reason it agrees on one height: a roof is one plane across
			# the whole building. One column of the stretch whose top is a wall
			# rather than a roof says the roof does not reach along here at all,
			# and leaning the rest would notch a corner off the tower whose end
			# board alternates with its gallery post for seven storeys.
			var pitch: int = 0x7fffffff
			for tx: int in range(wall, last + 1):
				var run: int = 1
				while ty - run >= 0 and _part[(ty - run) * _size.x + tx] == PART_WALL:
					run += 1
				runs.append(run)
				pitch = mini(pitch, _facade_pitch(tx, ty, run))
				bands = maxi(bands, _facade_period(tx, ty, run))
			# A PITCH DEEPER THAN THE DRAWING IS TALL is two readings of the same
			# column contradicting each other, and the period is the older one:
			# where a run repeats, the stretch stands as many bands as the repeat
			# and there are not enough of them for the roof the tiles claim. The
			# storeyed houses are where that happens, and taking the pitch anyway
			# leaves the wall at nothing.
			if pitch > bands:
				pitch = 0
			for tx: int in range(wall, last + 1):
				var under: int = column[tx]
				var top: int = under + bands * BAND
				# A FACE-ON ROOF SLOPE LEANS BACK, a tile of depth per band of
				# height, and the run's total height does not move: the topmost
				# band still stands at `top` and every band below it steps down
				# and forward until the wall, which keeps the drawing's own bands.
				# So the pitch is redistributed inside the footprint the fold
				# already gave the building and nothing outside it sees a change.
				var flat: int = runs[tx - wall] - pitch
				for step: int in runs[tx - wall]:
					var index: int = (ty - step) * _size.x + tx
					var climbed: int = clampi(step - flat + 1, 0, pitch)
					_heights[index] = top - (pitch - climbed) * BAND
					_pitched[index] = 1 if climbed > 0 else 0
					@warning_ignore("integer_division")
					_bases[index] = ty + under / BAND
					_volume[index] = 1
					placed[index] = 1
				column[tx] = top
			wall = last + 1

		var tx: int = 0
		while tx < _size.x:
			if _part[ty * _size.x + tx] != PART_ROOF:
				tx += 1
				continue
			var last: int = tx
			while last + 1 < _size.x and _part[ty * _size.x + last + 1] == PART_ROOF:
				last += 1
			_roof_row(ty, tx, last, column)
			tx = last + 1

		for reset: int in _size.x:
			if _part[ty * _size.x + reset] == PART_NONE:
				column[reset] = 0



## How many bands of a facade run are the drawing, in tile rows.
##
## The same question `_period` answers for a volume, and it has to be asked here
## too: a plaza's brick pavement is eight rows of the one tile and reading its
## length would stand a monolith where there is a low wall. A house facade of
## four different rows has no repeat in it and is four bands tall.
func _facade_period(tx: int, bottom: int, run: int) -> int:
	@warning_ignore("integer_division")
	for length: int in range(1, run / 2 + 1):
		var repeats: bool = true
		for step: int in range(length, length * 2):
			if _tiles[(bottom - step) * _size.x + tx] \
					!= _tiles[(bottom - step + length) * _size.x + tx]:
				repeats = false
				break
		if repeats:
			return length
	return run


## HOW MANY BANDS AT THE TOP OF A FACADE RUN ARE A ROOF SLOPE rather than a wall.
##
## Tileset 1's houses draw the front PITCH of their roof face-on, so the fold
## stood every one of them up square and a house came out a barn: a tall box with
## plank texture down its upper half and a flat lid. `profile.gd:FACADE_SLOPE`
## names those tiles and this counts them off the top of the run, which is where
## a roof is: the wall below keeps the drawing's own bands and the pitch leans
## back over the footprint, a tile of depth per band of height.
##
## TWO THINGS STOP THE COUNT and both are real drawings rather than caution.
##
## A ROOF DECK STANDING ON THE RUN is not this. Five columns in the game put a
## face-on eave band under a roof seen from above: there the band is the fascia
## at the front of that deck, standing on the wall exactly where it is drawn, and
## leaning it would step the wall's top back from under its own roof.
##
## AND A COLUMN THAT DRAWS ROOF MORE THAN ONCE IS A STACK OF STOREYS rather than
## one building with a pitch on top. Ecruteak's dance hall is seven storeys of
## gallery each carrying its own plank roof band, and its two-storey houses are
## the same thing twice: read as one run their roof reaches the ground. That is
## the file's rule that A DRAWING WHICH REPEATS IS NOT ONE DRAWING, asked of the
## roof, and it is read twice because the repeat shows up two ways. The count
## stops where a slope band RETURNS to a tile the column has already left, a tile
## repeated straight away being the same face carrying on; and if any slope band
## is left below the count, there is no single pitch and the run has none.
func _facade_pitch(tx: int, bottom: int, run: int) -> int:
	var top: int = bottom - run + 1
	if top > 0 and _part[(top - 1) * _size.x + tx] == PART_ROOF:
		return 0
	var pitch: int = 0
	var seen: Dictionary = {}
	var last: int = -1
	while pitch < run:
		var at: int = (top + pitch) * _size.x + tx
		if _slope[at] == 0:
			break
		var tile: int = _tiles[at]
		if tile != last and seen.has(tile):
			break
		seen[tile] = true
		last = tile
		pitch += 1
	for step: int in range(pitch, run):
		if _slope[(top + step) * _size.x + tx] == 1:
			return 0
	return pitch


## HOW FAR EACH TILE OF A ROOF RUN HAS FALLEN, in bands.
##
## `ROOF_DROP` is a fall FROM THE FLAT SECTION of the same roof, which is what the
## reviewer measured tileset 3's gable in: one band down beside the flat, two at
## the corner of the house. Read that way it is exact, and it is the answer
## wherever a run has a flat section in it to fall from.
##
## A GREAT ROOF HAS NONE. Its whole width is the pitch, twelve tiles of it, every
## tile drawn the same, falling the entire way from the ridge to the eaves. There
## is no flat tile in the run to measure an absolute fall against, so the drop is
## read the other way, as a RATE: each tile falls its own drop further than the
## tile before it, and the eave ends a walk cell and a half below the ridge.
##
## WHICH END IS THE RIDGE is the only thing here a drawing cannot say. Both ends
## are the same picture and what tells them apart is what lies beyond: a roof
## falls away from the floor a person stands on and it falls toward the VOID past
## the edge of the world. A run with void at both ends, or floor at both, has no
## reference at all and every tile keeps its own drop.
const ROOF_RIDGE_NONE: int = 0
const ROOF_RIDGE_FLAT: int = 1
const ROOF_RIDGE_LEFT: int = 2
const ROOF_RIDGE_RIGHT: int = 3


## Where one roof run's fall is measured from.
func _roof_ridge(ty: int, from: int, to: int) -> int:
	var row: int = ty * _size.x
	for tx: int in range(from, to + 1):
		if _drop[row + tx] == 0:
			return ROOF_RIDGE_FLAT
	var left_void: bool = from == 0 or _void[row + from - 1] == 1
	var right_void: bool = to == _size.x - 1 or _void[row + to + 1] == 1
	if left_void == right_void:
		return ROOF_RIDGE_NONE
	return ROOF_RIDGE_RIGHT if left_void else ROOF_RIDGE_LEFT


func _roof_fall(ty: int, from: int, to: int, ridge: int) -> PackedInt32Array:
	var fall := PackedInt32Array()
	fall.resize(to - from + 1)
	var row: int = ty * _size.x
	if ridge == ROOF_RIDGE_FLAT or ridge == ROOF_RIDGE_NONE:
		for tx: int in range(from, to + 1):
			fall[tx - from] = int(_drop[row + tx])
		return fall
	var carried: int = 0
	if ridge == ROOF_RIDGE_LEFT:
		for tx: int in range(from, to + 1):
			carried += int(_drop[row + tx])
			fall[tx - from] = carried
	else:
		for tx: int in range(to, from - 1, -1):
			carried += int(_drop[row + tx])
			fall[tx - from] = carried
	return fall


## One unbroken stretch of roof across one map row.
func _roof_row(ty: int, from: int, to: int, column: PackedInt32Array) -> void:
	var flat: int = -1
	var anywhere: int = 0
	for tx: int in range(from, to + 1):
		var at: int = ty * _size.x + tx
		anywhere = maxi(anywhere, column[tx])
		if _drop[at] == 0:
			flat = maxi(flat, column[tx])
	var agreed: int = flat if flat >= 0 else anywhere
	var ridge: int = _roof_ridge(ty, from, to)
	var fall: PackedInt32Array = _roof_fall(ty, from, to, ridge)
	# A ROOF NEVER FALLS BELOW WHAT ITS OWN COLUMN STANDS ON, or a gable meeting a
	# low wing drives its corner into the ground. A HANGING run is the exception
	# and the only one: it is the top of a building whose walls are off the map, so
	# a column carrying nothing carries nothing to be driven into, and clamping it
	# to the ground plane is what laid the whole of the great roof out flat.
	# Anything else keeps the clamp, or a lone roof tile the pass named in a room
	# sinks through the floor, which eleven Pokemon Centers did.
	var hanging: bool = ridge == ROOF_RIDGE_LEFT or ridge == ROOF_RIDGE_RIGHT
	for tx: int in range(from, to + 1):
		var at: int = ty * _size.x + tx
		var height: int = agreed - fall[tx - from] * BAND
		if column[tx] > 0 or not hanging:
			height = maxi(height, column[tx])
		_heights[at] = height
		_volume[at] = 0
		# The exposed side of a roof step is one band tall, so the row it folds
		# is the roof tile's own.
		@warning_ignore("integer_division")
		_bases[at] = ty + maxi(height / BAND - 1, 0)
		column[tx] = height


func _cell_unmeasured(cell_x: int, cell_y: int) -> bool:
	return _heights[cell_y * CELL_TILES * _size.x + cell_x * CELL_TILES] == -1


## The shortest stretch at the base of the run that the run repeats immediately
## behind it, which needs twice its own length of run to be visible at all. A run
## with no repeat in it is one structure and its length is the answer.
##
## Only the first repetition is checked, and deliberately: the far end of a run
## is where a structure caps off, and a tree wall that ends in a different corner
## cell is still a tree wall.
func _period(cell_x: int, cell_y: int, run: int) -> int:
	var base: int = cell_y + run - 1
	@warning_ignore("integer_division")
	for length: int in range(1, run / 2 + 1):
		var repeats: bool = true
		for step: int in range(length, length * 2):
			if not _cells_match(cell_x, base - step, base - step + length):
				repeats = false
				break
		if repeats:
			return length
	return run


func _cells_match(cell_x: int, first_y: int, second_y: int) -> bool:
	for row: int in CELL_TILES:
		var first: int = (first_y * CELL_TILES + row) * _size.x + cell_x * CELL_TILES
		var second: int = (second_y * CELL_TILES + row) * _size.x + cell_x * CELL_TILES
		for column: int in CELL_TILES:
			if _tiles[first + column] != _tiles[second + column]:
				return false
	return true


## The resolved top of the column at a world position, in world pixels. Outside
## the map the ground plane is the answer, which is what a camera looking past a
## map edge should clear.
func height_at_position(position: Vector3) -> int:
	return _height_at(
		floori(position.x / TILE) + _margin.x, floori(position.z / TILE) + _margin.y
	)


func _height_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	return _heights[ty * _size.x + tx]


## The art a side band shows: band k up from the ground is the map row k tiles
## NORTH OF THE STRUCTURE'S BASE, which is the fold that stands the 2D drawing
## up. Counting from the base rather than from the tile is what makes every
## column of one structure wear the same drawing, so the row exposed at its back
## shows the structure and not the ground behind it.
func _band_tile(tx: int, ty: int, band: int) -> int:
	var row: int = _bases[ty * _size.x + tx] - band
	if row < 0:
		row = 0
	var tile: int = _tiles[row * _size.x + tx]
	return tile if tile >= 0 else _tiles[ty * _size.x + tx]


## The pixels of one STRUCTURE that belong to the drawing rather than to the
## ground behind it, as a mask of its own size, keyed on its tiles.
##
## A structure is as many cells as the class says its drawing is: one for a
## bollard or a bush, one by two for the potted plant and the tall flower bed,
## which are two tiles wide and four tall. Cutting the mask over the whole thing
## is what puts the leaves on top of the pot: cut cell by cell, the flood runs
## along the seam between them and each half stands on the floor by itself.
##
## A cutout has to answer where the drawing ENDS, and colour cannot say: a
## bollard is white on a pale path, and a bush is green on grass. What can say it
## is the border. The ground runs to the edge of the cell and the drawing does
## not, so the indices making up most of the cell's border ring are the ground,
## and everything the flood cannot reach through them is the drawing.
##
## Most of the ring rather than all of it, because the one place a drawing DOES
## touch the border is where it stands: a bollard's shadow reaches the bottom
## edge, and letting its index into the ground set would flood the post away from
## underneath.
##
## THIS RULE HAS A LIMIT AND IT IS WORTH KNOWING WHERE. Widening it was tried
## first: an index that shows on three or more of the ring's four SIDES is
## surely floor, since ground surrounds a drawing and a drawing does not
## surround itself. It does fix a speckled tree. It also eats half the cutouts
## in the game, because a small drawing DOES reach three sides of a 16px cell:
## measured, 47 of the 82 distinct cutout drawings moved and eight of them
## vanished outright. Share alone is the rule, and the way past it is below.
##
## FOR ONE FAMILY OF DRAWINGS NO SET OF INDICES CAN WORK AT ALL. A tree
## canopy is a ball drawn in the SAME two greens the grass under it is dithered
## from: put those greens in the ground set and the flood eats the lit half of
## the tree, leave them out and it keeps half the lawn. Looked at as a picture
## rather than as a count, which is the only way it shows.
##
## What bounds such a drawing is its own OUTLINE, and an outline is the darkest
## shade in the tile. So an `outline` mask floods through every pixel that is not
## that shade, and what it cannot reach is the drawing. The cast shadow under a
## canopy is dark but is not enclosed by the outline, so it floods away with the
## grass, which is what should happen to it. This is the reference's own rule for
## the same problem (`Structures.lua`, "the darkest-shade outline plus everything
## it encloses").
##
## HOW MANY shades bound it is the drawing's own business, which is why the flag
## is a COUNT. A tree draws a ring and one shade is the ring. A thicket draws no
## ring at all, and there the two darkest together are the boundary, which is the
## reference's second reading of the same rule.
const RING_SHARE: float = 0.7
var _masks: Dictionary = {}


## The name a cut mask is remembered under. One drawing is cut once however many
## of its tiles ask, and the depths carved from it are remembered the same way.
func _mask_key(tiles: Array, filled: bool, outline: int) -> String:
	return "%s,%d,%d" % [str(tiles), 1 if filled else 0, outline]


func _structure_mask(
	tiles: Array, across: Vector2i, atlas: RefCounted, filled: bool,
	outline: int = 0
) -> PackedByteArray:
	var key: String = _mask_key(tiles, filled, outline)
	if _masks.has(key):
		return _masks[key]

	var size := Vector2i(across.x * int(TILE), across.y * int(TILE))
	var indices := PackedInt32Array()
	indices.resize(size.x * size.y)
	# Whether the flood may pass through each pixel. Two rules, and which one a
	# drawing wants is a fact about the drawing: see the header.
	var open := PackedByteArray()
	open.resize(size.x * size.y)
	for py: int in size.y:
		for px: int in size.x:
			@warning_ignore("integer_division")
			var tile: int = tiles[(py / int(TILE)) * across.x + px / int(TILE)]
			var index: int = atlas.pixel(tile, px % int(TILE), py % int(TILE))
			indices[py * size.x + px] = index
			if outline > 0:
				open[py * size.x + px] = 0 if atlas.is_dark(tile, index, outline) else 1

	if outline > 0:
		return _flood(size, open, filled, key)

	var ring: Dictionary = {}
	var ring_count: int = 0
	for px: int in size.x:
		_ring_pixel(ring, indices, px)
		_ring_pixel(ring, indices, (size.y - 1) * size.x + px)
		ring_count += 2
	for py: int in size.y:
		_ring_pixel(ring, indices, py * size.x)
		_ring_pixel(ring, indices, py * size.x + size.x - 1)
		ring_count += 2
	var ranked: Array = ring.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return ring[a] > ring[b])
	var ground: Dictionary = {}
	var covered: int = 0
	for index: int in ranked:
		if covered >= float(ring_count) * RING_SHARE:
			break
		ground[index] = true
		covered += int(ring[index])

	for at: int in indices.size():
		open[at] = 1 if ground.has(indices[at]) else 0
	return _flood(size, open, filled, key)


## What the flood cannot reach from the border, as a mask of the drawing.
##
## [param open] says which pixels it may pass through, which is the whole of the
## difference between the two rules above.
func _flood(
	size: Vector2i, open: PackedByteArray, filled: bool, key: String
) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	mask.fill(1)
	var stack := PackedInt32Array()
	for px: int in size.x:
		stack.append(px)
		stack.append((size.y - 1) * size.x + px)
	for py: int in size.y:
		stack.append(py * size.x)
		stack.append(py * size.x + size.x - 1)
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if mask[at] == 0 or open[at] == 0:
			continue
		mask[at] = 0
		@warning_ignore("integer_division")
		var py: int = at / size.x
		var px: int = at % size.x
		if px > 0:
			stack.append(at - 1)
		if px < size.x - 1:
			stack.append(at + 1)
		if py > 0:
			stack.append(at - size.x)
		if py < size.y - 1:
			stack.append(at + size.x)

	# A drawing whose body is painted the ground's own index defeats the flood:
	# the wooden sign's board is exactly the floor's colour, so the flood walks
	# through the board and leaves the letters standing in mid air. Filling each
	# column between its topmost and bottommost drawn pixel puts the body back.
	if filled:
		for px: int in size.x:
			var first: int = -1
			var last: int = -1
			for py: int in size.y:
				if mask[py * size.x + px] == 1:
					if first < 0:
						first = py
					last = py
			for py: int in range(first, last + 1):
				if first >= 0:
					mask[py * size.x + px] = 1

	_masks[key] = mask
	return mask


func _ring_pixel(ring: Dictionary, indices: PackedInt32Array, at: int) -> void:
	ring[indices[at]] = int(ring.get(indices[at], 0)) + 1


## How deep each drawn pixel stands, IN WHOLE PIXELS.
##
## A slab of a bollard or a bush reads as a sheet of paper from above, so a round
## class takes a carved plan: each row's own run of pixels is a circle seen from
## above, deepest at the middle of the run and pinched to one pixel at its ends.
##
## ONE SPAN PER ROW OF ONE BODY, and a BODY is a connected piece of the mask.
##
## Not one span per contiguous RUN: these drawings are dithered, so a row of one
## bush is half a dozen short runs with floor showing between them, and revolving
## each separately makes one dome into six little cylinders in a line.
##
## And not one span per ROW of the cell either, which is what this did until the
## bollards were looked at. A cell is 16 px and Goldenrod draws TWO wooden
## bollards in one, eight pixels apart; taking the row whole spanned both of them
## and revolved the pair into a single black mushroom fourteen pixels deep. The
## picture is `sheet_post_defect.png` in the survey directory, and `post` is
## 10178 tiles on 54 maps, so it was not a corner.
##
## The reference does not have this fault because it never works on a rectangle:
## it hulls FLOOD-FILLED REGIONS (`Structures.lua`), and two bollards are two
## regions. `_bodies` is that flood, and eight-connected on purpose: a dither is
## a chain of pixels touching at their corners, so four-connectivity would break
## a bush into the very specks the row-wide rule existed to prevent.
##
## A ROUND CLASS IS AS DEEP AS IT IS WIDE, and its own DEPTH does not cap it.
## That is the reference's rule stated plainly: "the canvas is NX wide and NX
## DEEP, a hull is round in plan, so its depth is its width", and its canopy is
## carved with no cap and no squash at all (`Structures.lua:roundTemplate`, and
## its call at `|g32|`). The chord is therefore in PIXELS off the row's own
## width, `n = 2 * sqrt(hw^2 - dx^2)`, and nothing trims it.
##
## Capping it at the class's DEPTH was the fault: it holds the middle of every
## row at the same few pixels and only lets the ends taper, which is a flat
## drawing extruded and rounded off at the edges rather than a body. The reviewer
## caught it from the picture in one line: still a 2D extruded flat model. A bush
## sixteen pixels wide is now sixteen deep at its widest row and is a ball.
##
## DEPTHS still governs the classes that are NOT round, and those are the ones it
## was measured for: a sign is a plate on a stick and a tombstone a slab. The
## hedge measurement that chose seven belongs to that older shape and is not a
## cap on a hull.
##
## It is paid for in geometry and the bill is known: 8.30M triangles over every
## map in the game against 6.07M for the slab, and the worst map's emit goes from
## 399 ms to 531 ms. The emit is sliced under a frame budget, so what that buys is
## a map arriving a little later rather than a frame being dropped.
##
## Every face still wears the FRONT drawing's texel at its own column, which is
## the reviewer's call and the right one: the outline of these drawings is dark,
## and a naive revolve would paint the whole object its own outline colour.
func _cell_levels(
	mask: PackedByteArray, span: Vector2i, round_plan: bool, depth: int,
	key: String = ""
) -> PackedByteArray:
	if not key.is_empty() and _hulls.has(key):
		return _hulls[key]
	var levels := PackedByteArray()
	levels.resize(mask.size())
	var deepest: int = clampi(depth, 1, 255)
	if not round_plan:
		for at: int in mask.size():
			levels[at] = deepest if mask[at] == 1 else 0
		if not key.is_empty():
			_hulls[key] = levels
		return levels
	# THE ROW'S EXTENT WITHIN ONE BODY, not within the cell. See the header.
	var body := _bodies(mask, span)
	# Per row, the leftmost and rightmost pixel of each body that reaches it.
	var first: Dictionary = {}
	var last: Dictionary = {}
	for py: int in span.y:
		first.clear()
		last.clear()
		for px: int in span.x:
			var group: int = body[py * span.x + px]
			if group < 0:
				continue
			if not first.has(group):
				first[group] = px
			last[group] = px
		for group: int in first:
			var from: int = int(first[group])
			var to: int = int(last[group])
			var middle: float = (float(from) + float(to) + 1.0) * 0.5
			var radius: float = maxf((float(to) + 1.0 - float(from)) * 0.5, 0.5)
			for step: int in range(from, to + 1):
				if body[py * span.x + step] != group:
					continue
				var away: float = float(step) + 0.5 - middle
				var chord: float = 2.0 * sqrt(maxf(radius * radius - away * away, 0.0))
				levels[py * span.x + step] = clampi(roundi(chord), 1, 255)
	if not key.is_empty():
		_hulls[key] = levels
	return levels


## The depths carved from each cut mask, remembered like the masks themselves:
## one drawing is one answer however many of its tiles ask for it. Named for the
## HULL rather than for the levels, which in this file are what a person paints
## on a map.
var _hulls: Dictionary = {}


## WHICH PIXELS BELONG TO THE SAME BODY, as a group number per pixel and -1 where
## the mask is empty.
##
## EIGHT-CONNECTED, and that is the whole rule. A Game Boy artist shades with a
## CHECKERBOARD, so a dithered bush is a chain of pixels touching only at their
## corners: under four-connectivity it falls apart into a cloud of specks and
## every one becomes its own little dome, which is the fault the row-wide reading
## was protecting against. Diagonals hold the dither together and still leave two
## things a clear pixel apart in separate bodies, which is what a cell holding two
## drawings needs.
func _bodies(mask: PackedByteArray, span: Vector2i) -> PackedInt32Array:
	var body := PackedInt32Array()
	body.resize(mask.size())
	body.fill(-1)
	var groups: int = 0
	var stack := PackedInt32Array()
	for start: int in mask.size():
		if mask[start] == 0 or body[start] >= 0:
			continue
		var group: int = groups
		groups += 1
		body[start] = group
		stack.push_back(start)
		while not stack.is_empty():
			var at: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			@warning_ignore("integer_division")
			var ax: int = at % span.x
			@warning_ignore("integer_division")
			var ay: int = at / span.x
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					var nx: int = ax + dx
					var ny: int = ay + dy
					if nx < 0 or ny < 0 or nx >= span.x or ny >= span.y:
						continue
					var next: int = ny * span.x + nx
					if mask[next] == 0 or body[next] >= 0:
						continue
					body[next] = group
					stack.push_back(next)
	return body


## Where an authored model stands, gathered per DRAWING rather than per tile.
##
## Every tile of the drawing asks, and the anchor is what dedupes them: a tree is
## sixteen tiles and is one tree. Asking from every tile rather than only from
## the anchor is deliberate, because a draw-distance window can cut the anchor
## off while the rest of the drawing is still in frame, and a tree that vanishes
## because its top-left corner is out of view is worse than one built twice.
##
## The mesh is built ONCE per drawing and stamped at each spot, which is what
## makes this cheap where carving was not: one tree of geometry for a whole
## forest, and the engine culls the lot as one instance.
var _model_meshes: Dictionary = {}
var _model_spots: Dictionary = {}
## Per drawing: the BODIES it holds, each a mesh key and where in the drawing's
## own footprint that body is centred, in world pixels. See `_model_bodies_of`.
var _model_bodies: Dictionary = {}
## Whether this slice has just turned a drawing into a solid, which is dear
## enough to end the slice on its own. See `emit_step`.
var _built_model: bool = false


func _place_model(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var box: Rect2i = _span_box(at, tx, ty)
	var across: Vector2i = box.size
	var start: Vector2i = box.position
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var ground: float = float(_ground_art(tx, ty).y)
	for body: Array in _model_bodies_of(tiles, across, at, atlas):
		var key: String = body[0]
		var middle: Vector2 = body[1]
		# WHERE THE BODY IS DRAWN, on the ground beside it, TURNED AND NUDGED off
		# the grid it was authored on. The cartridge places its trees on a 16px
		# lattice and one mesh stamped at every lattice point reads as an orchard:
		# the eye finds the rows immediately, and the rows are the one thing about a
		# forest that is an artefact of the tile map rather than of the world.
		# A quarter turn costs nothing and keeps every voxel axis-aligned, which is
		# what a rotation of any other angle would throw away, and it shows a
		# different side of the same baked leaf noise. The nudge is a couple of
		# pixels on a 16px cell, enough to break the line and too little to leave
		# the cell. Both come off the body's own anchor, so nothing walks when the
		# window rebuilds and two stones in one cell do not turn together.
		#
		# AND THE NUDGE STOPS AT THE EDGE OF THE DRAWING'S OWN KIND. A wobble that
		# is nothing inside a wood is a bush standing on the pavement at the edge of
		# one, which is what the border ring does wherever a connection carries a
		# road out of the map: the last row of the hedge nudged onto it. So an axis
		# takes the wobble only where the drawing CARRIES ON both ways along it,
		# which is every stamp in a forest and no stamp on its edge. A single row
		# back on its lattice reads as nothing, because that row IS the edge.
		var wander := Vector2(
			MODEL_NUDGE if _same_class_across(at, box, Vector2i.RIGHT) else 0.0,
			MODEL_NUDGE if _same_class_across(at, box, Vector2i.DOWN) else 0.0
		)
		var anchor := Vector2i(
			start.x * int(TILE) + int(middle.x), start.y * int(TILE) + int(middle.y)
		)
		var spot := Vector3(
			_world_x(start.x) + middle.x + (_hash_spot(anchor) - 0.5) * wander.x,
			ground,
			_world_z(start.y) + middle.y
				+ (_hash_spot(anchor + Vector2i(37, 0)) - 0.5) * wander.y
		)
		var turn: float = floorf(_hash_spot(anchor + Vector2i(0, 91)) * 4.0) * PI * 0.5
		# The stamp carries its own WIND PHASE with it, off the same anchor, so a
		# tree bends at the same moment every time the window is rebuilt and no two
		# neighbours bend together. See `world/wind.gd`.
		(_model_spots[key] as Dictionary)[str(start)] = [
			Transform3D(Basis(Vector3(0.0, 1.0, 0.0), turn), spot),
			_hash_spot(anchor + Vector2i(0, 53)),
		]


## Whether the drawing CARRIES ON both ways along [param step], which is the test
## for "more of this" a nudge is allowed inside.
##
## The tile sampled each side is the one beside the box's own first row or first
## column, which is enough: a run of one drawing is a run of whole boxes, so
## either the neighbouring box is that drawing or it is not.
##
## The CLASS rather than the tile id, because a hedge alternates its two rows and
## a wood its two cells, so a tile match calls a forest's own interior an edge.
## Past the mesh entirely counts as different: the window's own rim is an edge
## like any other.
func _same_class_across(at: int, box: Rect2i, step: Vector2i) -> bool:
	var mine: int = _klass[at]
	for side: Vector2i in [
		box.position - step,
		box.position + Vector2i(box.size.x - 1, box.size.y - 1) + step,
	]:
		var beside := Vector2i(
			side.x if step.x != 0 else box.position.x,
			side.y if step.y != 0 else box.position.y,
		)
		if beside.x < 0 or beside.y < 0 or beside.x >= _size.x or beside.y >= _size.y:
			return false
		if _klass[beside.y * _size.x + beside.x] != mine:
			return false
	return true


## ONE MODEL PER BODY OF THE DRAWING, not one per drawing.
##
## A drawing is cut over a whole cell and a cell is 16 px, which is room for more
## than one thing: the sea rock is an 8 px stone and a cell of them draws FOUR.
## Turning that cell as one silhouette revolves the four into a single mushroom,
## which is exactly the fault the carved path met with Goldenrod's paired
## bollards and answers the same way, by flooding the mask into bodies first.
##
## A drawing holding one thing, which is every tree and every bush, comes back as
## one body and nothing about it moves. Specks smaller than a voxel or two are
## dropped rather than turned: a dither's stray corner is not a thing.
##
## Each mesh is built ONCE and stamped at every spot, which is what makes this
## cheap where carving was not: one tree of geometry for a whole forest, and the
## engine culls the lot as one instance.
func _model_bodies_of(
	tiles: Array, across: Vector2i, at: int, atlas: RefCounted
) -> Array:
	var drawing: String = str(tiles)
	if _model_bodies.has(drawing):
		return _model_bodies[drawing]
	var span: Vector2i = across * int(TILE)
	var mask: PackedByteArray = _structure_mask(
		tiles, across, atlas, _filled[at] == 1, int(_outlined[at])
	)
	var body: PackedInt32Array = _bodies(mask, span)
	var counts: Dictionary = {}
	var bounds: Dictionary = {}
	for pixel: int in body.size():
		var group: int = body[pixel]
		if group < 0:
			continue
		@warning_ignore("integer_division")
		var py: int = pixel / span.x
		var px: int = pixel % span.x
		counts[group] = int(counts.get(group, 0)) + 1
		var box: Rect2i = bounds.get(group, Rect2i(px, py, 1, 1))
		bounds[group] = box.expand(Vector2i(px, py)).expand(Vector2i(px + 1, py + 1))
	var out: Array = []
	for group: int in counts:
		if int(counts[group]) < MODEL_BODY_MIN:
			continue
		var key: String = "%s#%d" % [drawing, group]
		if not _model_meshes.has(key):
			var only := PackedByteArray()
			only.resize(mask.size())
			for pixel: int in body.size():
				only[pixel] = 1 if body[pixel] == group else 0
			var measured: RefCounted = Model.measure(only, span, tiles, across, atlas)
			measured.shrub = _shrub[at] == 1
			measured.rock = _rock[at] == 1
			measured.column = _column[at] == 1
			measured.stretch = _stretch[at]
			_model_meshes[key] = (Model.new() as RefCounted).tree(measured)
			_model_spots[key] = {}
			_built_model = true
		var box: Rect2i = bounds[group]
		out.append([key, Vector2(box.position) + Vector2(box.size) * 0.5])
	_model_bodies[drawing] = out
	return out


## The fewest pixels a body may hold and still be turned into a model. Below a
## voxel or two there is no silhouette to read.
const MODEL_BODY_MIN: int = 8


## How far a stamped model is nudged off its lattice point, in world pixels,
## across the whole span of the wobble.
const MODEL_NUDGE: float = 5.0


## A settled number in 0 to 1 for a placement, so a forest is varied and a tree
## is still in the same place every time the window is rebuilt.
func _hash_spot(anchor: Vector2i) -> float:
	var value: float = sin(float(anchor.x) * 127.1 + float(anchor.y) * 311.7) * 43758.5453
	return value - floorf(value)


## The models this emit placed: a list of [mesh, placements], one per distinct
## drawing, each placement a `Transform3D`. Empty until an emit has run.
func take_models() -> Array:
	var out: Array = []
	for key: String in _model_meshes:
		var placed: Array[Transform3D] = []
		var phases := PackedFloat32Array()
		# A mesh with no spots is a drawing built for an earlier window and not
		# stamped in this one, which is ordinary once a window moves.
		for entry: Array in (_model_spots.get(key, {}) as Dictionary).values():
			placed.append(entry[0] as Transform3D)
			phases.append(float(entry[1]))
		if not placed.is_empty():
			out.append([_model_meshes[key], placed, phases])
	return out


## One texel of the object's own body, as a uv box, for the faces the drawing does
## not depict: its back and its two sides. Taken from INSIDE the drawing between
## the two rows given, the way a cutout's top faces are, because the edge column
## of a silhouette is its outline all the way down and a face wearing that comes
## out solid black.
func _object_texel(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, from_row: int, to_row: int
) -> Rect2:
	var fallback: Rect2 = atlas.uv(int(tiles[0]))
	var found: Rect2 = fallback
	var any: bool = false
	for py: int in range(from_row, to_row):
		for px: int in range(window.position.x, window.position.x + window.size.x):
			if not _drawn(mask, span, px, py):
				continue
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(py / int(TILE)) * across.x + px / int(TILE)])
			var box: Rect2 = atlas.uv_box(
				tile, Rect2i(px % int(TILE), py % int(TILE), 1, 1)
			)
			if _interior(mask, span, px, py):
				return box
			if not any:
				found = box
				any = true
	return found


## ONE OBJECT, STOOD UP AT ITS OWN SIZE AND POSITION.
##
## The drawing is a top and a front stacked, which is the whole of what a 2.5D
## picture of a thing is: the window's first `top` rows are the surface seen from
## above and are laid across the object's DEPTH, and the rest are the face seen
## face-on and are hung down its HEIGHT. Where a drawing has no top band at all,
## which is the chair, the cap is one texel of the drawing's own colour and the
## depth is the number a person gave.
##
## Every row is cut per TILE, because a texel can only be sampled out of the tile
## it was drawn in, and within a tile into the runs the mask actually draws. The
## back and the two sides wear one interior texel each rather than the drawing,
## since the drawing says nothing about them.
func _emit_object(index: int, atlas: RefCounted) -> void:
	var entry: Array = _objects[index]
	var object: Dictionary = entry[0]
	var start: Vector2i = entry[1]
	var across: Vector2i = entry[2]
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var span: Vector2i = across * int(TILE)
	var mask: PackedByteArray = _structure_mask(
		tiles, across, atlas, bool(object.get(&"filled", false)),
		int(object.get(&"outline", 1))
	)
	var window: Rect2i = object[&"window"]
	# AN OBJECT MAY BE TURNED RATHER THAN STOOD UP, which is the one thing this
	# path could not do and the reason two round drawings sat unbuilt. See
	# `_object_model`.
	if bool(object.get(&"model", false)):
		_object_model(object, start, across, tiles, mask, span, window, atlas)
		return
	var top_rows: int = clampi(int(object.get(&"top", 0)), 0, window.size.y)
	var face_rows: int = window.size.y - top_rows
	var deep: float = float(object[&"depth"])
	var tall: float = float(object[&"height"])
	# ONE ground for the whole thing, taken at the drawing's own foot. Reading it
	# per tile would tilt an object that stands across two of them.
	var base: float = float(_ground_art(start.x, start.y + across.y - 1).y)
	# The drawing's bottom row is where the thing meets the floor, so it is also
	# its NEAR edge in plan: a 2.5D drawing puts the front-bottom corner there and
	# everything else behind it.
	var front: float = _world_z(start.y) + float(window.position.y + window.size.y)
	var back: float = front - deep
	var left: float = _world_x(start.x) + float(window.position.x)
	var right: float = left + float(window.size.x)
	var high: float = base + tall

	# THE DRAWING IS CUT INTO RECTANGLES, not into a quad per row-run, and it is
	# the same greedy cut `_cutout` makes for the same reason: a rectangle of
	# pixels maps onto a rectangle of texels exactly, so the picture is identical
	# and the ship stops costing nine hundred quads. A rectangle may not cross a
	# TILE, because a texel can only be sampled out of the tile it was drawn in,
	# and it may not cross the top band's last row, because that is where the
	# drawing stops lying down and starts standing up.
	var taken := PackedByteArray()
	taken.resize(window.size.x * window.size.y)
	for row: int in window.size.y:
		var py: int = window.position.y + row
		var above: bool = row < top_rows
		var down_stop: int = mini(
			((py / int(TILE)) + 1) * int(TILE) - window.position.y,
			top_rows if above else window.size.y
		)
		var px: int = window.position.x
		while px < window.position.x + window.size.x:
			var column: int = px - window.position.x
			if taken[row * window.size.x + column] == 1 \
					or not _drawn(mask, span, px, py):
				px += 1
				continue
			var stop: int = mini(
				(px / int(TILE) + 1) * int(TILE),
				window.position.x + window.size.x
			)
			var run: int = px
			while run < stop and taken[row * window.size.x + run - window.position.x] == 0 \
					and _drawn(mask, span, run, py):
				run += 1
			var deep_rows: int = 1
			while row + deep_rows < down_stop:
				var whole: bool = true
				for step: int in run - px:
					if taken[(row + deep_rows) * window.size.x + column + step] == 1 \
							or not _drawn(mask, span, px + step, py + deep_rows):
						whole = false
						break
				if not whole:
					break
				deep_rows += 1
			for down: int in deep_rows:
				for step: int in run - px:
					taken[(row + down) * window.size.x + column + step] = 1
			# Where these rows of the drawing go: back to front across the cap, or
			# top to bottom down the face.
			var far: float = 0.0
			var near: float = 0.0
			if above:
				far = back + deep * float(row) / float(top_rows)
				near = back + deep * float(row + deep_rows) / float(top_rows)
			else:
				far = high - tall * float(row - top_rows) / float(face_rows)
				near = high - tall * float(row - top_rows + deep_rows) / float(face_rows)
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(py / int(TILE)) * across.x + px / int(TILE)])
			var uv: Rect2 = atlas.uv_box(
				tile, Rect2i(px % int(TILE), py % int(TILE), run - px, deep_rows)
			)
			var x0: float = _world_x(start.x) + float(px)
			var x1: float = _world_x(start.x) + float(run)
			if above:
				_quad(
					Vector3(x0, high, near), Vector3(x1, high, near),
					Vector3(x1, high, far), Vector3(x0, high, far),
					Vector3.UP, uv, SHADE_TOP_FLAT
				)
			else:
				_quad(
					Vector3(x0, near, front), Vector3(x1, near, front),
					Vector3(x1, far, front), Vector3(x0, far, front),
					Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
				)
			px = run

	var side: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y + top_rows, window.position.y + window.size.y
	)
	_quad(
		Vector3(right, base, back), Vector3(left, base, back),
		Vector3(left, high, back), Vector3(right, high, back),
		Vector3(0.0, 0.0, -1.0), side, SHADE_NORTH
	)
	_quad(
		Vector3(right, base, front), Vector3(right, base, back),
		Vector3(right, high, back), Vector3(right, high, front),
		Vector3(1.0, 0.0, 0.0), side, SHADE_SIDE
	)
	_quad(
		Vector3(left, base, back), Vector3(left, base, front),
		Vector3(left, high, front), Vector3(left, high, back),
		Vector3(-1.0, 0.0, 0.0), side, SHADE_SIDE
	)
	if top_rows == 0:
		_quad(
			Vector3(left, high, front), Vector3(right, high, front),
			Vector3(right, high, back), Vector3(left, high, back),
			Vector3.UP,
			_object_texel(
				atlas, tiles, across, mask, span, window,
				window.position.y, window.position.y + window.size.y
			),
			SHADE_TOP_FLAT
		)


## ONE OBJECT, TURNED RATHER THAN STOOD UP.
##
## The declaration is the same one everything else in `OBJECTS` uses and what it
## gains is a shape: a drawing that is ROUND is a body of revolution and a slab
## of it is a card, which is the whole of what `shape/model.gd` exists for. Two
## drawings in the game are both, and both sat unbuilt for it. The National
## Park's tiered fountain is 18 px across THREE tiles and centred on the seam
## between two of them, so `SPANS`, whose box starts at `tx - posmod(tx,
## across.x)`, cannot reach it at any size; the arrangement of tile ids reaches
## it wherever the map puts it.
##
## WHAT THE OBJECT SUPPLIES THAT A PINNED CLASS CANNOT is the WINDOW. A mask is
## cut over the arrangement's whole rectangle, and here that rectangle holds the
## paving either side of the drawing; everything outside the window is dropped
## before the body flood, so a neighbour cannot widen the profile the turn is
## read from.
##
## HOW TALL IT STANDS IS THE DECLARATION'S, not the drawing's, and it goes in as
## the model's own `stretch`: a turned thing is as deep as it is wide, so `depth`
## says nothing here, and `height` against the drawn rows is exactly the ratio
## `profile.gd:STRETCH` states for a pinned class.
##
## Placed where the drawing is and NOT where a lattice is: no quarter turn, no
## nudge and no wind phase. Those exist to break the rows out of a forest of
## stamps of one tree, and an object is one thing at one place that a person
## named.
func _object_model(
	object: Dictionary, start: Vector2i, across: Vector2i, tiles: Array,
	mask: PackedByteArray, span: Vector2i, window: Rect2i, atlas: RefCounted
) -> void:
	var body := PackedInt32Array()
	body.resize(mask.size())
	var inside := PackedByteArray()
	inside.resize(mask.size())
	for py: int in span.y:
		for px: int in span.x:
			inside[py * span.x + px] = mask[py * span.x + px] \
				if window.has_point(Vector2i(px, py)) else 0
	body = _bodies(inside, span)
	var counts: Dictionary = {}
	var bounds: Dictionary = {}
	for pixel: int in body.size():
		var group: int = body[pixel]
		if group < 0:
			continue
		@warning_ignore("integer_division")
		var py: int = pixel / span.x
		var px: int = pixel % span.x
		counts[group] = int(counts.get(group, 0)) + 1
		var box: Rect2i = bounds.get(group, Rect2i(px, py, 1, 1))
		bounds[group] = box.expand(Vector2i(px, py)).expand(Vector2i(px + 1, py + 1))
	var ground: float = float(_ground_art(start.x, start.y + across.y - 1).y)
	for group: int in counts:
		if int(counts[group]) < MODEL_BODY_MIN:
			continue
		var key: String = "%s:%s#%d" % [str(object[&"name"]), str(tiles), group]
		if not _model_meshes.has(key):
			var only := PackedByteArray()
			only.resize(mask.size())
			for pixel: int in body.size():
				only[pixel] = 1 if body[pixel] == group else 0
			var measured: RefCounted = Model.measure(only, span, tiles, across, atlas)
			measured.shrub = bool(object.get(&"shrub", true))
			measured.rock = bool(object.get(&"rock", true))
			var drawn_rows: int = int((bounds[group] as Rect2i).size.y)
			if drawn_rows > 0:
				measured.stretch = float(object[&"height"]) / float(drawn_rows)
			_model_meshes[key] = (Model.new() as RefCounted).tree(measured)
			_model_spots[key] = {}
			_built_model = true
		var middle: Vector2 = Vector2((bounds[group] as Rect2i).get_center())
		(_model_spots[key] as Dictionary)[str(start)] = [
			Transform3D(Basis(), Vector3(
				_world_x(start.x) + middle.x, ground, _world_z(start.y) + middle.y
			)),
			0.0,
		]


## How much wall a body needs before it is a building rather than a speck.
const HOUSE_BODY_MIN: int = 32


## WHAT ONE PAINTING MEASURES, READ PER PIXEL COLUMN, ONE BUILDING AT A TIME.
##
## Everything a house needs comes off the painting and there is no number in this
## file that a person has to author.
##
## A DRAWING IS NOT ONE BUILDING. Its rectangle is whatever the page flooded
## together, and on the city tilesets that is a terrace: drawing 95 holds three
## houses with a canal in one corner. So the painting is split first and each
## piece is planned on its own.
##
## SPLIT ON THE WALLS, NOT ON THE WHOLE DRAWING, which is the reviewer's own
## reading of that drawing and the only split that works: two houses standing
## side by side have their ROOFS touching, so flooding the whole painting merges
## them, and the gap the cartridge draws between their WALLS is what says they
## are two.
##
## A COLUMN OF THE DRAWING IS A SECTION THROUGH THE BUILDING, read from the
## bottom up: wall, then the roof seen from the FRONT, then the roof seen from
## ABOVE. So every column carries its own wall height, its own eave and its own
## roof art, and a hipped end falls out of the painting with no angle in it
## anywhere. Per column of one building:
##
##   tops       the topmost WALL row, so how high the wall stands there
##   eave_*     the run painted `roof, from the front` immediately above the
##              wall, which is the roof slab's own face at that column
##   cap_*      the run painted `roof` above that, which is the top surface
##
## And for the building as a whole:
##
##   left, right   the outermost columns carrying its wall
##   cover_*       how far its roof reaches. See `_house_reach`.
##   foot          its wall's bottom row. The rows below are the shadow the house
##                 casts on the pavement, and the few pixels of that row that ARE
##                 the house are the door's own posts standing proud of the face.
##                 So a row is thrown away from the bottom up while it carries
##                 less than HALF the wall of the row above it.
##
##                 AGAINST THE ROW ABOVE, NOT AGAINST THE WIDEST ROW, and that is
##                 what makes it general. Measured over the paintings that carry a
##                 wall: read against the widest row, seven drawings whose widest
##                 course is a storey above their foot come back with gaps of 9,
##                 33 and 65 rows, which takes most of their depth away.
##   north_row,    where its footprint starts and ends down the page, which is the
##   south_row     only thing a flat drawing says about DEPTH. A terrace stacked
##                 down the page therefore stands as buildings one behind another
##                 rather than as one slab.
##   *_rise, m0,   the roof line, in `_house_rise`'s own terms.
##   m1
func _house_plan(house: Dictionary) -> Array:
	var id: int = int(house.get("id", -1))
	if _house_plans.has(id):
		return _house_plans[id]
	var paint: Array = house["paint"]
	var rows: int = paint.size()
	var cols: int = String(paint[0]).length()
	# The walls flood into buildings, and everything the drawing holds floods into
	# TERRACES, which is what says whose roof a shared eave column belongs to.
	var owner: PackedInt32Array = _house_flood(paint, rows, cols, Houses.WALL)
	var terrace: PackedInt32Array = _house_flood(paint, rows, cols, "")
	var count: int = 0
	for at: int in owner.size():
		count = maxi(count, owner[at] + 1)
	var area := PackedInt32Array()
	area.resize(count)
	for at: int in owner.size():
		if owner[at] >= 0:
			area[owner[at]] += 1

	var plans: Array = []
	for body: int in count:
		if area[body] < HOUSE_BODY_MIN:
			continue
		var plan: Dictionary = _house_body(paint, rows, cols, owner, terrace, body)
		if not plan.is_empty():
			plans.append(plan)
	_house_plans[id] = plans
	return plans


## Every pixel's connected body, or -1 where the painting draws nothing.
##
## [param word] floods that one word alone; an empty one floods everything the
## painting calls the house at all.
func _house_flood(
	paint: Array, rows: int, cols: int, word: String
) -> PackedInt32Array:
	var owner := PackedInt32Array()
	owner.resize(rows * cols)
	owner.fill(-1)
	var bodies: int = 0
	var stack := PackedInt32Array()
	for start: int in rows * cols:
		if owner[start] >= 0:
			continue
		@warning_ignore("integer_division")
		if not _house_is(paint[start / cols][start % cols], word):
			continue
		owner[start] = bodies
		stack.push_back(start)
		while not stack.is_empty():
			var at: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			@warning_ignore("integer_division")
			var y: int = at / cols
			var x: int = at % cols
			for step: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var nx: int = x + step.x
				var ny: int = y + step.y
				if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
					continue
				var next: int = ny * cols + nx
				if owner[next] >= 0 or not _house_is(paint[ny][nx], word):
					continue
				owner[next] = bodies
				stack.push_back(next)
		bodies += 1
	return owner


func _house_is(stroke: String, word: String) -> bool:
	return stroke != Houses.NONE if word.is_empty() else stroke == word


## HOW FAR ONE BUILDING'S ROOF REACHES ACROSS THE DRAWING IT STANDS IN.
##
## A roof column goes to the NEAREST wall, so two houses sharing an eave split it
## down the middle and a free end keeps the whole overhang. [param rival] carries
## each column's distance to the nearest wall belonging to a DIFFERENT building,
## so that test is one comparison and the reach stays contiguous with the wall it
## hangs off.
##
## AND IT STOPS WHERE THE ROOF FALLS A STOREY, which nearness alone cannot do. A
## rectangle can hold a roof whose own wall is outside it, cut off by the
## rectangle's edge: Goldenrod's #99 holds the Pokemon Centre's roof and not its
## wall, so the nearest wall to that roof is the house next door, which swallowed
## the whole thing and blocked the painting that does hold the building.
##
## So the reach walks a CHAIN, column by column, carrying the SECTION it is
## walking along: the run of painted pixels that the last column's run overlaps.
## A column drawing nothing there ends it, and so does a column whose section
## FALLS more than a row below the last one's, because that is a different roof.
##
## A ROW IS THE MEASURED LIMIT AND NOT A CHOSEN ONE. Over the 1087 columns the
## reach walks in the whole game, 1082 fall by one row or none: a roof's own
## profile is a staircase, so its section steps a row at a time however steep it
## is drawn. The only fall of more than a row anywhere is the column where the
## Pokemon Centre's roof starts, and it is 16, a whole walk cell.
##
## THE FALL IS MEASURED FROM THE OUTERMOST WALL COLUMN'S OWN EAVE, which is not
## the same course as the building's peak: on a hipped end the eave at the corner
## is a storey below the ridge, and measuring the first step from the ridge reads
## the overhang as a fall. The rows the run is SEARCHED for are the band as
## before, so this test can only ever stop the reach earlier and never carry it
## further, which is what keeps it to the one building it was written for.
const HOUSE_ROOF_STEP: int = 1


func _house_reach(
	paint: Array, rows: int, cols: int, rival: PackedInt32Array,
	tops: PackedInt32Array, left: int, right: int, band: Vector2i
) -> Vector2i:
	var reach := Vector2i(left, right)
	var run: Vector2i = band
	var eave: int = tops[left] - 1
	while reach.x > 0 and left - (reach.x - 1) < rival[reach.x - 1]:
		var next: Vector2i = _house_run(paint, rows, reach.x - 1, run)
		if next.x < 0 or next.y > eave + HOUSE_ROOF_STEP:
			break
		reach.x -= 1
		eave = next.y
		run = Vector2i(next.x, run.y)
	run = band
	eave = tops[right] - 1
	while reach.y < cols - 1 and (reach.y + 1) - right < rival[reach.y + 1]:
		var next: Vector2i = _house_run(paint, rows, reach.y + 1, run)
		if next.x < 0 or next.y > eave + HOUSE_ROOF_STEP:
			break
		reach.y += 1
		eave = next.y
		run = Vector2i(next.x, run.y)
	return reach


## The whole run of painted pixels in one column that overlaps a band of rows: a
## roof walks sideways along its own section, and how far that section reaches
## DOWN is what says whether it is still the same roof.
func _house_run(paint: Array, rows: int, x: int, band: Vector2i) -> Vector2i:
	for y: int in range(band.x, band.y + 1):
		if y < 0 or y >= rows or paint[y][x] == Houses.NONE:
			continue
		var top: int = y
		while top > 0 and paint[top - 1][x] != Houses.NONE:
			top -= 1
		var bottom: int = y
		while bottom + 1 < rows and paint[bottom + 1][x] != Houses.NONE:
			bottom += 1
		return Vector2i(top, bottom)
	return Vector2i(-1, -1)


## One building out of a painting, planned on its own.
func _house_body(
	paint: Array, rows: int, cols: int,
	owner: PackedInt32Array, terrace: PackedInt32Array, body: int
) -> Dictionary:
	var tops := PackedInt32Array()
	var eave_from := PackedInt32Array()
	var eave_to := PackedInt32Array()
	var cap_from := PackedInt32Array()
	var cap_to := PackedInt32Array()
	for array: PackedInt32Array in [tops, eave_from, eave_to, cap_from, cap_to]:
		array.resize(cols)
		array.fill(-1)
	var walls := PackedInt32Array()
	walls.resize(rows)
	var left: int = cols
	var right: int = -1
	var bottom: int = -1
	var group: int = -1
	for y: int in rows:
		for x: int in cols:
			if owner[y * cols + x] != body:
				continue
			walls[y] += 1
			if tops[x] < 0:
				tops[x] = y
			left = mini(left, x)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
			group = terrace[y * cols + x]
	if right < 0:
		return {}
	# See the header: the shadow and the door's posts are not the wall's bottom.
	var foot: int = bottom
	while foot > 0 and (walls[foot] == 0 or walls[foot] * 2 < walls[foot - 1]):
		foot -= 1
	var gap: int = 0
	if foot + 1 < rows and walls[foot + 1] * 2 < walls[foot]:
		gap = 1
	# The section above each of this building's own wall columns.
	var peak: int = rows
	var top_row: int = rows
	for x: int in range(left, right + 1):
		if tops[x] < 0:
			continue
		peak = mini(peak, tops[x])
		top_row = mini(top_row, tops[x])
		var y: int = tops[x] - 1
		while y >= 0 and paint[y][x] == Houses.FRONT:
			eave_from[x] = y
			if eave_to[x] < 0:
				eave_to[x] = y
			y -= 1
		while y >= 0 and paint[y][x] == Houses.ROOF:
			cap_from[x] = y
			if cap_to[x] < 0:
				cap_to[x] = y
			y -= 1
		if cap_from[x] >= 0:
			top_row = mini(top_row, cap_from[x])
		elif eave_from[x] >= 0:
			top_row = mini(top_row, eave_from[x])
	var rival := PackedInt32Array()
	rival.resize(cols)
	rival.fill(cols * 2)
	for x: int in cols:
		for y: int in rows:
			var at: int = y * cols + x
			if terrace[at] != group:
				continue
			if owner[at] >= 0 and owner[at] != body:
				rival[x] = 0
	for x: int in range(1, cols):
		rival[x] = mini(rival[x], rival[x - 1] + 1)
	for x: int in range(cols - 2, -1, -1):
		rival[x] = mini(rival[x], rival[x + 1] + 1)
	# The section the reach walks along: this building's own roof, from its top
	# down to the course its wall starts at.
	var cover: Vector2i = _house_reach(
		paint, rows, cols, rival, tops, left, right, Vector2i(top_row, peak - 1)
	)
	# SEEDED OUTSIDE THE BUILDING, not at its own edges: seeded at `left` and
	# `right` the run can only ever come out the whole wall, every roof reads flat
	# and a hipped end comes back a box.
	var m0: int = cols
	var m1: int = -1
	for x: int in range(left, right + 1):
		if tops[x] == peak:
			m0 = mini(m0, x)
			m1 = maxi(m1, x)
	if m1 < 0:
		m0 = left
		m1 = right
	var plan: Dictionary = {
		"rows": rows, "cols": cols, "foot": foot, "gap": gap,
		"left": left, "right": right,
		"cover_left": cover.x, "cover_right": cover.y,
		"top_row": top_row, "north_row": top_row + gap, "south_row": foot + 1,
		"tops": tops, "eave_from": eave_from, "eave_to": eave_to,
		"cap_from": cap_from, "cap_to": cap_to, "m0": m0, "m1": m1,
		"peak_rise": float(foot + 1 - peak),
		"left_rise": float(foot + 1 - tops[left]),
		"right_rise": float(foot + 1 - tops[right]),
		"thick": 0,
	}
	# HOW THICK THE SLAB IS, read at the tallest course and then anywhere.
	#
	# A ROOF CUT OFF BY THE TOP OF THE DRAWING HAS NO EAVE AT ITS OWN PEAK, and
	# read only there the whole building loses its slab. The Radio Tower is that:
	# 20 tiles square, its wings' wall starting at row 32 with three rows of eave
	# above them, and its glass column running to row 0 with nothing above it at
	# all, so the tallest column measured no thickness and neither wing was roofed.
	# The reviewer's answer in round twenty-two is a flat cap over the whole of it,
	# each column at the top of its own wall, so the thickness is taken from the
	# courses that DO draw one: the commonest eave over the building's columns,
	# which is the same rule the atlas reads a tile's ground with, and a tie goes
	# to the thicker since an eave is never thinner than it is drawn.
	if eave_to[m0] >= 0:
		plan["thick"] = eave_to[m0] - eave_from[m0] + 1
	else:
		var seen: Dictionary = {}
		for x: int in range(left, right + 1):
			if eave_to[x] < 0:
				continue
			var band: int = eave_to[x] - eave_from[x] + 1
			seen[band] = int(seen.get(band, 0)) + 1
		var best: int = 0
		for band: int in seen:
			if seen[band] > int(seen.get(best, 0)) or (
				seen[band] == int(seen.get(best, 0)) and band > best
			):
				best = band
		plan["thick"] = best
	return plan


## THE ROOF LINE: how high the wall stands, and so where the roof sits, at any
## point across the building.
##
## THE ROOF HAS THREE PARTS, which is the reviewer's own reading of drawing 4:
## the middle is flat and the left and right go downwards. All three fall out of
## the painting with no angle authored anywhere. The flat part is the run of
## columns whose wall reaches the drawing's topmost wall row; each side is a
## straight line from the end of that run down to the outermost wall column, and
## it CARRIES ON past the wall at the same slope, which is what keeps the roof's
## overhang in the plane of the slope it hangs off. Drawing 4 reads 15 px in the
## middle, 9 at both ends and 6 px over 12 columns, which is 27 degrees.
##
## THE WALL AND THE ROOF READ THE SAME LINE, and that is not tidiness. The
## painting's own profile is a staircase two pixels at a time; a wall standing on
## the staircase under a roof lying on the straight line pokes through it, which
## the reviewer warned about before it was built.
##
## A drawing whose wall is one height throughout has its flat part spanning the
## whole building and no sides at all, so this answers one number everywhere and
## the house comes out the pair of boxes drawing 1 already is.
func _house_rise(plan: Dictionary, x: float) -> float:
	var peak: float = float(plan["peak_rise"])
	var m0: float = float(plan["m0"])
	var m1: float = float(plan["m1"]) + 1.0
	if x >= m0 and x <= m1:
		return peak
	if x < m0:
		var edge: float = float(plan["left"])
		if m0 - edge < 1.0:
			return peak
		var rise: float = float(plan["left_rise"])
		return rise + (peak - rise) * (x - edge) / (m0 - edge)
	var far: float = float(plan["right"]) + 1.0
	if far - m1 < 1.0:
		return peak
	var drop: float = float(plan["right_rise"])
	return peak + (drop - peak) * (x - m1) / (far - m1)


## ONE VERTICAL FACE OF A HOUSE, whose top edge follows the roof line.
##
## Everything standing up on a house is this shape: the wall runs from the ground
## to the roof line, and the roof's own slab runs from there to the line plus its
## thickness. Both slope wherever the line does.
##
## [param source] is the drawing COLUMN each position along the face wears, which
## is separate from where the position IS: the front wears its own columns once
## where the other three wear the front's columns with the doors taken out,
## repeated all the way round, and that is the only statement a flat drawing makes
## about the three sides it does not draw.
##
## [param low] and [param high] are the world heights at each position BOUNDARY,
## so they carry one more entry than the face is long and a sloping edge comes out
## a straight line across a run rather than a step per pixel.
##
## [param origin] is the face's bottom corner on the LEFT as seen from outside and
## [param step] the unit pixel along it, so one routine serves all four faces and
## the winding cannot be got wrong once per face. Cut per TILE both ways, because
## a texel is only samplable out of the tile it was drawn in.
func _house_face(
	tiles: Array, across: Vector2i, source: PackedInt32Array,
	from_row: PackedInt32Array, to_row: PackedInt32Array,
	low: PackedFloat32Array, high: PackedFloat32Array,
	origin: Vector3, step: Vector3, length: int,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	var at: int = 0
	while at < length:
		var first: int = source[at]
		var top: int = from_row[at]
		var bottom: int = to_row[at]
		if top < 0 or bottom < top:
			at += 1
			continue
		var run: int = 1
		while at + run < length:
			var next: int = source[at + run]
			if next != first + run or next / TILE_PX != first / TILE_PX:
				break
			if from_row[at + run] != top or to_row[at + run] != bottom:
				break
			run += 1
		var span: int = bottom - top + 1
		var a: Vector3 = origin + step * float(at)
		var b: Vector3 = origin + step * float(at + run)
		var a_high: float = high[at]
		var a_fall: float = high[at] - low[at]
		var b_high: float = high[at + run]
		var b_fall: float = high[at + run] - low[at + run]
		var row: int = top
		while row <= bottom:
			var stop: int = mini((row / TILE_PX + 1) * TILE_PX - 1, bottom)
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(row / TILE_PX) * across.x + first / TILE_PX])
			var uv: Rect2 = atlas.uv_box(
				tile, Rect2i(first % TILE_PX, row % TILE_PX, run, stop - row + 1)
			)
			var upper: float = float(row - top) / float(span)
			var lower: float = float(stop + 1 - top) / float(span)
			_quad(
				Vector3(a.x, a_high - a_fall * lower, a.z),
				Vector3(b.x, b_high - b_fall * lower, b.z),
				Vector3(b.x, b_high - b_fall * upper, b.z),
				Vector3(a.x, a_high - a_fall * upper, a.z),
				normal, uv, shade
			)
			row = stop + 1
		at += run


## One face of the wall, or the one above it that is the roof slab's own edge.
##
## [param over_first] and [param over_step] say which BUILDING column each
## position stands over, which is what decides the rows it wears and how high it
## is; [param edge_first] and [param edge_step] say the same at each position
## BOUNDARY, in the roof line's own coordinate, so a face running along the depth
## can hold one column while a face running across the front walks them all.
func _house_side(
	tiles: Array, across: Vector2i, plan: Dictionary, source: PackedInt32Array,
	over_first: int, over_step: int, edge_first: float, edge_step: float,
	slab: bool, base: float, thick: float,
	origin: Vector3, step: Vector3, length: int,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	if length <= 0 or source.is_empty():
		return
	var tops: PackedInt32Array = plan["tops"]
	var eave_from: PackedInt32Array = plan["eave_from"]
	var eave_to: PackedInt32Array = plan["eave_to"]
	var left: int = int(plan["left"])
	var right: int = int(plan["right"])
	var foot: int = int(plan["foot"])
	var from_row := PackedInt32Array()
	var to_row := PackedInt32Array()
	var low := PackedFloat32Array()
	var high := PackedFloat32Array()
	for at: int in length:
		var over: int = clampi(over_first + over_step * at, left, right)
		from_row.append(eave_from[over] if slab else tops[over])
		to_row.append(eave_to[over] if slab else foot)
	for at: int in length + 1:
		var rise: float = _house_rise(plan, edge_first + edge_step * float(at))
		low.append(base + rise if slab else base)
		high.append(base + rise + thick if slab else base + rise)
	_house_face(
		tiles, across, source, from_row, to_row, low, high,
		origin, step, length, normal, shade, atlas
	)


## THE ROOF'S OWN TOP SURFACE, laid back across its depth and following the roof
## line across its width.
##
## The rows painted `roof` are what you are looking DOWN onto: they are depth on
## the page and no height at all, so each column's own run of them is stretched
## over the slab rather than stacked. Stretching each column's OWN run is what
## puts the flat middle's art on the flat middle and the sloping end's art on the
## slope, where one run stretched over the whole roof would drag the pavement the
## drawing's corners hold onto the roof's corners.
##
## A whole tile row of the drawing goes down as ONE band: a linear stretch inside
## a band is the same picture as one strip per row and a fraction of the
## triangles. [param under] turns it over into the slab's soffit, which is what a
## low eye sees under the eave and what closes the top of the wall.
func _house_cap(
	tiles: Array, across: Vector2i, plan: Dictionary, origin_x: float,
	base: float, thick: float, near: float, far: float, under: bool,
	atlas: RefCounted
) -> void:
	var cap_from: PackedInt32Array = plan["cap_from"]
	var cap_to: PackedInt32Array = plan["cap_to"]
	var eave_to: PackedInt32Array = plan["eave_to"]
	var left: int = int(plan["left"])
	var right: int = int(plan["right"])
	var column: int = int(plan["cover_left"])
	var last_column: int = int(plan["cover_right"])
	while column <= last_column:
		var read: int = clampi(column, left, right)
		var top: int = eave_to[read] if under else cap_from[read]
		var bottom: int = eave_to[read] if under else cap_to[read]
		if top < 0 or bottom < top:
			column += 1
			continue
		var run: int = 1
		while column + run <= last_column:
			if (column + run) / TILE_PX != column / TILE_PX:
				break
			var next: int = clampi(column + run, left, right)
			if under:
				if eave_to[next] != top:
					break
			elif cap_from[next] != top or cap_to[next] != bottom:
				break
			run += 1
		var y_west: float = base + _house_rise(plan, float(column)) + thick
		var y_east: float = base + _house_rise(plan, float(column + run)) + thick
		var x0: float = origin_x + float(column)
		var x1: float = origin_x + float(column + run)
		var span: int = bottom - top + 1
		var row: int = top
		while row <= bottom:
			var stop: int = mini((row / TILE_PX + 1) * TILE_PX - 1, bottom)
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(row / TILE_PX) * across.x + column / TILE_PX])
			var uv: Rect2 = atlas.uv_box(
				tile, Rect2i(column % TILE_PX, row % TILE_PX, run, stop - row + 1)
			)
			var z_far: float = far + (near - far) * float(row - top) / float(span)
			var z_near: float = far + (near - far) * float(stop + 1 - top) / float(span)
			if under:
				_quad(
					Vector3(x1, y_east, z_near), Vector3(x0, y_west, z_near),
					Vector3(x0, y_west, z_far), Vector3(x1, y_east, z_far),
					Vector3.DOWN, uv, SHADE_NORTH
				)
			else:
				_quad(
					Vector3(x0, y_west, z_near), Vector3(x1, y_east, z_near),
					Vector3(x1, y_east, z_far), Vector3(x0, y_west, z_far),
					Vector3.UP, uv, SHADE_TOP_FLAT
				)
			row = stop + 1
		column += run


## ONE PAINTED HOUSE, STOOD UP. The reviewer's own reading, taken in round
## twenty-one over drawings 1 and 4, and every number in it is measured off the
## painting.
##
## A HOUSE IS A WALL WITH A ROOF SLAB SITTING ON IT, and the slab stands out past
## the wall on all four sides, which is the eave the cartridge draws overhanging
## the facade. Where the wall is one height throughout that is two boxes, and it
## is drawing 1. Where it is not, the roof line has a flat middle and a straight
## slope down each side and the wall follows it, which is drawing 4's hipped end.
## See `_house_rise`.
##
## THE FRONT WALL IS A FLAT VERTICAL PICTURE AND SO IS THE DOOR. A door is not a
## hole and not a recess: the player walks through it because walking through is
## collision, and nothing here touches collision. It faces the same way as the
## wall it is drawn on.
##
## THE THREE SIDES A DRAWING DOES NOT DRAW wear the front wall with the door
## columns taken out, repeated all the way round. The doors are the cartridge's
## own warps rather than anything painted.
func _emit_house(index: int, atlas: RefCounted) -> void:
	var entry: Array = _houses[index]
	var start: Vector2i = entry[1]
	var across: Vector2i = entry[2]
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	# ONE DRAWING IS SEVERAL BUILDINGS, so each is stood up on its own footprint,
	# and only the ones this placement actually claimed.
	for plan: Dictionary in _house_chosen(entry):
		_emit_house_body(plan, tiles, start, across, entry[3], atlas)


## The buildings this placement claimed, which on a street of overlapping
## paintings is not all of the drawing's. See `_match_houses`.
func _house_chosen(entry: Array) -> Array:
	var plans: Array = _house_plan(entry[0])
	var out: Array = []
	for index: int in entry[4] as PackedInt32Array:
		if index >= 0 and index < plans.size():
			out.append(plans[index])
	return out


## One of a drawing's buildings, stood up where the painting puts it.
func _emit_house_body(
	plan: Dictionary, tiles: Array, start: Vector2i, across: Vector2i,
	doors: Array, atlas: RefCounted
) -> void:
	var left: int = int(plan["left"])
	var right: int = int(plan["right"])
	if right < 0:
		return
	var cover_left: int = int(plan["cover_left"])
	var cover_right: int = int(plan["cover_right"])
	var thick: float = float(plan["thick"])
	var foot: int = int(plan["foot"])
	# ONE ground for the whole building, taken beside its own foot. Reading it per
	# tile would tilt one standing across two of them, and reading it at the
	# drawing's own bottom row would take another building's ground on a terrace.
	@warning_ignore("integer_division")
	var base: float = float(_ground_art(
		start.x + left / TILE_PX,
		start.y + mini(foot / TILE_PX, across.y - 1)
	).y)
	var origin_x: float = _world_x(start.x)
	var west: float = origin_x + float(left)
	var east: float = origin_x + float(right + 1)
	var north: float = _world_z(start.y) + float(plan["north_row"])
	var south: float = _world_z(start.y) + float(plan["south_row"])

	# THE COLUMNS THE THREE UNDRAWN SIDES WEAR: the facade with its doors removed.
	var wrapped := PackedInt32Array()
	for column: int in range(left, right + 1):
		var is_door: bool = false
		for door: Vector2i in doors:
			if column >= door.x and column < door.y:
				is_door = true
		if not is_door:
			wrapped.append(column)
	if wrapped.is_empty():
		for column: int in range(left, right + 1):
			wrapped.append(column)

	var wide: int = right + 1 - left
	var deep: int = int(south - north)
	var facade := PackedInt32Array()
	for column: int in range(left, right + 1):
		facade.append(column)
	var wrap_wide := PackedInt32Array()
	var wrap_deep := PackedInt32Array()
	for at: int in wide:
		wrap_wide.append(wrapped[at % wrapped.size()])
	for at: int in deep:
		wrap_deep.append(wrapped[at % wrapped.size()])

	_house_side(
		tiles, across, plan, facade, left, 1, float(left), 1.0, false, base, thick,
		Vector3(west, 0.0, south), Vector3(1.0, 0.0, 0.0), wide,
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas
	)
	_house_side(
		tiles, across, plan, wrap_wide, right, -1, float(right + 1), -1.0,
		false, base, thick,
		Vector3(east, 0.0, north), Vector3(-1.0, 0.0, 0.0), wide,
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas
	)
	_house_side(
		tiles, across, plan, wrap_deep, right, 0, float(right + 1), 0.0,
		false, base, thick,
		Vector3(east, 0.0, south), Vector3(0.0, 0.0, -1.0), deep,
		Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas
	)
	_house_side(
		tiles, across, plan, wrap_deep, left, 0, float(left), 0.0,
		false, base, thick,
		Vector3(west, 0.0, north), Vector3(0.0, 0.0, 1.0), deep,
		Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas
	)
	if thick <= 0.0:
		return

	# THE ROOF STANDS OUT PAST THE WALL, by exactly what the drawing puts either
	# side of its own facade. Nothing draws the overhang front and back, so the
	# side's own measurement is carried round; the reviewer took that in round
	# twenty-one over the flush alternative, both built and photographed.
	@warning_ignore("integer_division")
	var out_deep: int = ((left - cover_left) + (cover_right - right)) / 2
	var slab_west: float = origin_x + float(cover_left)
	var slab_east: float = origin_x + float(cover_right + 1)
	var slab_north: float = north - float(out_deep)
	var slab_south: float = south + float(out_deep)
	var slab_wide: int = cover_right + 1 - cover_left
	var slab_deep: int = int(slab_south - slab_north)
	var eaves := PackedInt32Array()
	for column: int in range(cover_left, cover_right + 1):
		eaves.append(column)
	var eave_wide := PackedInt32Array()
	var eave_deep := PackedInt32Array()
	for at: int in slab_wide:
		eave_wide.append(wrapped[at % wrapped.size()])
	for at: int in slab_deep:
		eave_deep.append(wrapped[at % wrapped.size()])

	_house_side(
		tiles, across, plan, eaves, cover_left, 1, float(cover_left), 1.0,
		true, base, thick,
		Vector3(slab_west, 0.0, slab_south), Vector3(1.0, 0.0, 0.0), slab_wide,
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas
	)
	_house_side(
		tiles, across, plan, eave_wide, cover_right, -1, float(cover_right + 1), -1.0,
		true, base, thick,
		Vector3(slab_east, 0.0, slab_north), Vector3(-1.0, 0.0, 0.0), slab_wide,
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas
	)
	_house_side(
		tiles, across, plan, eave_deep, cover_right, 0, float(cover_right + 1), 0.0,
		true, base, thick,
		Vector3(slab_east, 0.0, slab_south), Vector3(0.0, 0.0, -1.0), slab_deep,
		Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas
	)
	_house_side(
		tiles, across, plan, eave_deep, cover_left, 0, float(cover_left), 0.0,
		true, base, thick,
		Vector3(slab_west, 0.0, slab_north), Vector3(0.0, 0.0, 1.0), slab_deep,
		Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas
	)
	_house_cap(
		tiles, across, plan, origin_x, base, thick,
		slab_south, slab_north, false, atlas
	)
	_house_cap(
		tiles, across, plan, origin_x, base, 0.0,
		slab_south, slab_north, true, atlas
	)


## One flight of stairs: four treads and four risers inside one walk cell.
##
## The drawing is a picture of the flight from above, so the cell's own pixels
## are what the treads and the risers wear, each step taking the four pixel rows
## of the cell it stands under. Cut per TILE like everything else that samples the
## atlas, which for a 16 px cell is two pieces across each step.
##
## The DEEPEST tread is not emitted: for a down flight the cell's floor is already
## a walk cell below the ground and `_face_top` has drawn it, and the steps above
## close over the rest of it. Emitting it again would be two coincident quads.
func _emit_stairs(index: int, atlas: RefCounted) -> void:
	var entry: Array = _stairs[index]
	var flight: Dictionary = entry[0]
	var start: Vector2i = entry[1]
	var base: float = float(entry[2])
	var down: bool = bool(flight[&"down"])
	var across: Vector2i = entry[3]
	var steps: int = int(flight.get(&"steps", STAIR_STEPS))
	var climb: int = int(flight.get(&"rise", STAIR_RISE))
	# A LANDING TURNS and has no single step direction, so it is its own shape.
	if flight.has(&"corner"):
		_emit_stair_corner(
			start, base, flight[&"corner"], across, steps, climb, atlas
		)
		return
	var step: Vector2i = flight[&"step"]
	# HOW LONG THE FLIGHT IS is the pattern's own width, not a walk cell: the grand
	# staircase of tileset 15 is four tiles by four and climbs two levels in eight
	# steps, and every other one in the game is two by two and climbs one in four.
	# The tread stays four pixels either way, which is what keeps them all at 45
	# degrees.
	var run: int = (across.x if step.x != 0 else across.y) * int(TILE)
	var rise: float = float(climb) / float(steps)
	var tread_deep: float = float(run) / float(steps)
	if not down:
		_stair_head(start, base, step, across, climb, atlas)
	for tread: int in steps:
		# Where this step sits inside the cell, in the cell's own pixels. The
		# descent runs along whichever axis `step` names, from the edge the flight
		# is entered by, and the step is the full width of the cell across it.
		var from: int = int(float(tread) * tread_deep)
		var deep: int = roundi(tread_deep)
		var wide: int = (across.y if step.x != 0 else across.x) * int(TILE)
		var box := Rect2i(0, 0, wide, wide)
		if step.x != 0:
			box = Rect2i(from if step.x > 0 else run - from - deep, 0, deep, wide)
		else:
			box = Rect2i(0, from if step.y > 0 else run - from - deep, wide, deep)
		var height: float = base + float(tread + 1) * rise * (-1.0 if down else 1.0)
		var above: float = height + rise * (1.0 if down else -1.0)
		# The riser stands at the step's own entry edge, facing back the way the
		# flight is walked into.
		var riser: int = box.position.x + (0 if step.x > 0 else box.size.x) \
			if step.x != 0 else box.position.y + (0 if step.y > 0 else box.size.y)
		for piece: Rect2i in _tile_pieces(box):
			var tile: int = _tile_at(
				start.x + piece.position.x / int(TILE), start.y + piece.position.y / int(TILE)
			)
			var uv: Rect2 = atlas.uv_box(tile, Rect2i(
				piece.position.x % int(TILE), piece.position.y % int(TILE),
				piece.size.x, piece.size.y
			))
			var x0: float = _world_x(start.x) + float(piece.position.x)
			var x1: float = x0 + float(piece.size.x)
			var z0: float = _world_z(start.y) + float(piece.position.y)
			var z1: float = z0 + float(piece.size.y)
			if tread < steps - 1 or not down:
				_quad(
					Vector3(x0, height, z1), Vector3(x1, height, z1),
					Vector3(x1, height, z0), Vector3(x0, height, z0),
					Vector3.UP, uv, SHADE_TOP_FLAT
				)
			# THE FLANKS, and ONLY AN UP FLIGHT NEEDS THEM. A flight cut into the
			# floor stands inside a pit whose four walls the neighbours have already
			# skirted, full depth, exactly where these would go; drawing them again
			# would be two coincident faces. A flight standing ON the floor has no
			# such walls, so without these you see under its own treads.
			if not down:
				_stair_flank(
					step, base, height, piece, box,
					Vector2(x0, z0), Vector2(x1, z1), uv
				)
			# The riser is the same strip of drawing stood on end, and only the
			# piece of it that this tile actually carries.
			var low: float = minf(height, above)
			var high: float = maxf(height, above)
			if step.x != 0:
				var rx: float = _world_x(start.x) + float(riser)
				if step.x > 0:
					_quad(
						Vector3(rx, low, z0), Vector3(rx, low, z1),
						Vector3(rx, high, z1), Vector3(rx, high, z0),
						Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
					)
				else:
					_quad(
						Vector3(rx, low, z1), Vector3(rx, low, z0),
						Vector3(rx, high, z0), Vector3(rx, high, z1),
						Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
					)
			else:
				var rz: float = _world_z(start.y) + float(riser)
				if step.y > 0:
					_quad(
						Vector3(x1, low, rz), Vector3(x0, low, rz),
						Vector3(x0, high, rz), Vector3(x1, high, rz),
						Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
					)
				else:
					_quad(
						Vector3(x0, low, rz), Vector3(x1, low, rz),
						Vector3(x1, high, rz), Vector3(x0, high, rz),
						Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
					)


## A FLIGHT THAT TURNS: the corner landing where two runs of steps meet, which is
## the League platform's own and the only geometry of its kind in the game.
##
## The reviewer's words are the specification: "both horizontal and vertical
## steps are meeting, so to go up you walk from bottom left to top right". So a
## tread here is not a strip across a cell, it is an L wrapping the corner, and
## the whole of the shape falls out of one line: how high a point stands is how
## far it has come in the direction it has come LEAST far.
##
##     tier = floor(min(u, v) / tread)
##
## with u and v measured in from the two OUTER edges. Far along one face that is
## the flight beside it, tread for tread, so the two join without a seam; at the
## corner itself it mitres at 45 degrees, which is what the cartridge draws.
##
## [param corner] names both climb directions at once, so (1, -1) is a landing
## climbing east and north, which is a platform's bottom-left corner.
##
## Each tier is emitted as TWO rectangles, the arm along v including the corner
## square and the arm along u without it, so the L is covered exactly once.
func _emit_stair_corner(
	start: Vector2i, base: float, corner: Vector2i, across: Vector2i,
	steps: int, climb: int, atlas: RefCounted
) -> void:
	var span: int = mini(across.x, across.y) * int(TILE)
	var rise: float = float(climb) / float(steps)
	# Whole-pixel tread boundaries, so the tiers tile the cell exactly rather
	# than leaving the last fraction of a pixel bare the way a fixed tread would.
	var edge := PackedInt32Array()
	for tier: int in steps + 1:
		edge.append(roundi(float(tier * span) / float(steps)))

	for tier: int in steps:
		var low: int = edge[tier]
		var high: int = edge[tier + 1]
		if high <= low:
			continue
		var top: float = base + float(tier + 1) * rise
		for arm: Rect2i in [
			Rect2i(low, low, high - low, span - low),
			Rect2i(high, low, span - high, high - low),
		]:
			if arm.size.x <= 0 or arm.size.y <= 0:
				continue
			_stair_corner_top(start, corner, span, arm, top, atlas)
		# The two risers, each the full outer boundary of the L at this tier, so
		# the corner square gets one on both of its outer sides.
		_stair_corner_riser(
			start, corner, span, true, low, span, top - rise, top, atlas
		)
		_stair_corner_riser(
			start, corner, span, false, low, span, top - rise, top, atlas
		)


## One arm of a tier, laid flat, cut per tile so each piece wears its own art.
##
## [param arm] is in (u, v), which is why it is turned into world coordinates
## here and nowhere else: the four corners differ only by which way those two
## axes point.
func _stair_corner_top(
	start: Vector2i, corner: Vector2i, span: int, arm: Rect2i, top: float,
	atlas: RefCounted
) -> void:
	var box := Rect2i(
		arm.position.x if corner.x > 0 else span - arm.end.x,
		arm.position.y if corner.y > 0 else span - arm.end.y,
		arm.size.x, arm.size.y
	)
	for piece: Rect2i in _tile_pieces(box):
		var tile: int = _tile_at(
			start.x + piece.position.x / int(TILE), start.y + piece.position.y / int(TILE)
		)
		var uv: Rect2 = atlas.uv_box(tile, Rect2i(
			piece.position.x % int(TILE), piece.position.y % int(TILE),
			piece.size.x, piece.size.y
		))
		var x0: float = _world_x(start.x) + float(piece.position.x)
		var x1: float = x0 + float(piece.size.x)
		var z0: float = _world_z(start.y) + float(piece.position.y)
		var z1: float = z0 + float(piece.size.y)
		_quad(
			Vector3(x0, top, z1), Vector3(x1, top, z1),
			Vector3(x1, top, z0), Vector3(x0, top, z0),
			Vector3.UP, uv, SHADE_TOP_FLAT
		)


## One tier's riser along one of the two faces, standing at [param at] measured
## in from that face's outer edge and reaching to [param until].
##
## [param along_u] picks which face: the one whose steps run in the x direction,
## or the one whose steps run in z.
func _stair_corner_riser(
	start: Vector2i, corner: Vector2i, span: int, along_u: bool,
	at: int, until: int, low: float, high: float, atlas: RefCounted
) -> void:
	# Where the riser's plane sits, and which side of it the tread is on: the tile
	# whose drawing the riser wears is the one it is holding up.
	var plane: int = at if (corner.x > 0 if along_u else corner.y > 0) else span - at
	var inward: int = plane if (corner.x > 0 if along_u else corner.y > 0) else plane - 1
	# The strip the riser runs along, as a one-pixel box in local pixels, so the
	# same per-tile cut a tread gets applies to it.
	var lo: int = at if (corner.y > 0 if along_u else corner.x > 0) else span - until
	var hi: int = until if (corner.y > 0 if along_u else corner.x > 0) else span - at
	var box := Rect2i(inward, lo, 1, hi - lo) if along_u \
		else Rect2i(lo, inward, hi - lo, 1)
	for piece: Rect2i in _tile_pieces(box):
		var tile: int = _tile_at(
			start.x + piece.position.x / int(TILE),
			start.y + piece.position.y / int(TILE)
		)
		var uv: Rect2 = atlas.uv_box(tile, Rect2i(
			piece.position.x % int(TILE), piece.position.y % int(TILE),
			piece.size.x, piece.size.y
		))
		var x0: float = _world_x(start.x) + float(piece.position.x)
		var z0: float = _world_z(start.y) + float(piece.position.y)
		if along_u:
			var rx: float = _world_x(start.x) + float(plane)
			var z1: float = z0 + float(piece.size.y)
			if corner.x > 0:
				_quad(
					Vector3(rx, low, z0), Vector3(rx, low, z1),
					Vector3(rx, high, z1), Vector3(rx, high, z0),
					Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
				)
			else:
				_quad(
					Vector3(rx, low, z1), Vector3(rx, low, z0),
					Vector3(rx, high, z0), Vector3(rx, high, z1),
					Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
				)
		else:
			var rz: float = _world_z(start.y) + float(plane)
			var x1: float = x0 + float(piece.size.x)
			if corner.y > 0:
				_quad(
					Vector3(x1, low, rz), Vector3(x0, low, rz),
					Vector3(x0, high, rz), Vector3(x1, high, rz),
					Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
				)
			else:
				_quad(
					Vector3(x0, low, rz), Vector3(x1, low, rz),
					Vector3(x1, high, rz), Vector3(x0, high, rz),
					Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
				)


## The head of a flight that stands on the floor: the wall under its topmost
## tread, at the edge of the cell the climb ends at. A pit needs none, its
## neighbours having skirted every side of it already.
func _stair_head(
	start: Vector2i, base: float, step: Vector2i, across: Vector2i, climb: int,
	atlas: RefCounted
) -> void:
	var edge: int = int(TILE)
	# ALONG the climb and ACROSS it, which are the same only because every flight
	# in the game happens to be square. Keeping them apart costs nothing and a
	# staircase wider than it is long would otherwise put its head in mid air.
	var run: int = (across.x if step.x != 0 else across.y) * edge
	var wide: int = (across.y if step.x != 0 else across.x)
	var high: float = base + float(climb)
	for piece: int in wide:
		var along: int = piece * edge
		var tile: int = _tile_at(
			start.x + (across.x - 1 if step.x > 0 else (0 if step.x < 0 else piece)),
			start.y + (across.y - 1 if step.y > 0 else (0 if step.y < 0 else piece))
		)
		var uv: Rect2 = atlas.uv_box(tile, Rect2i(0, 0, edge, edge))
		if step.x != 0:
			var x: float = _world_x(start.x) + float(run if step.x > 0 else 0)
			var z0: float = _world_z(start.y) + float(along)
			var z1: float = z0 + float(edge)
			if step.x > 0:
				_quad(
					Vector3(x, base, z1), Vector3(x, base, z0),
					Vector3(x, high, z0), Vector3(x, high, z1),
					Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
				)
			else:
				_quad(
					Vector3(x, base, z0), Vector3(x, base, z1),
					Vector3(x, high, z1), Vector3(x, high, z0),
					Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
				)
			continue
		var z: float = _world_z(start.y) + float(run if step.y > 0 else 0)
		var x0: float = _world_x(start.x) + float(along)
		var x1: float = x0 + float(edge)
		if step.y > 0:
			_quad(
				Vector3(x0, base, z), Vector3(x1, base, z),
				Vector3(x1, high, z), Vector3(x0, high, z),
				Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
			)
		else:
			_quad(
				Vector3(x1, base, z), Vector3(x0, base, z),
				Vector3(x0, high, z), Vector3(x1, high, z),
				Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
			)


## The two sides of one step of a flight that stands on the floor, from the floor
## up to that step's own tread, and only where the step reaches the edge of its
## cell. Nothing sees the sides of the steps in between.
func _stair_flank(
	step: Vector2i, base: float, height: float, piece: Rect2i, box: Rect2i,
	near: Vector2, far: Vector2, uv: Rect2
) -> void:
	var low: float = minf(base, height)
	var high: float = maxf(base, height)
	if step.x != 0:
		if piece.position.y == box.position.y:
			_quad(
				Vector3(far.x, low, near.y), Vector3(near.x, low, near.y),
				Vector3(near.x, high, near.y), Vector3(far.x, high, near.y),
				Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
			)
		if piece.end.y == box.end.y:
			_quad(
				Vector3(near.x, low, far.y), Vector3(far.x, low, far.y),
				Vector3(far.x, high, far.y), Vector3(near.x, high, far.y),
				Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
			)
		return
	if piece.position.x == box.position.x:
		_quad(
			Vector3(near.x, low, near.y), Vector3(near.x, low, far.y),
			Vector3(near.x, high, far.y), Vector3(near.x, high, near.y),
			Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
		)
	if piece.end.x == box.end.x:
		_quad(
			Vector3(far.x, low, far.y), Vector3(far.x, low, near.y),
			Vector3(far.x, high, near.y), Vector3(far.x, high, far.y),
			Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
		)


## [param box] cut on the 8 px tile grid, since a texel can only be sampled out
## of the tile it was drawn in.
func _tile_pieces(box: Rect2i) -> Array:
	var out: Array = []
	var y: int = box.position.y
	while y < box.end.y:
		var tall: int = mini((y / int(TILE) + 1) * int(TILE), box.end.y) - y
		var x: int = box.position.x
		while x < box.end.x:
			var wide: int = mini((x / int(TILE) + 1) * int(TILE), box.end.x) - x
			out.append(Rect2i(x, y, wide, tall))
			x += wide
		y += tall
	return out


## One tile's share of a standing cutout: the drawing's own pixels, standing up.
##
## Not a quad per pixel and not a quad per row. The mask is cut into the largest
## RECTANGLES that fit inside it, greedily from the top left, and each rectangle
## is one box: a front, a back, and a face along each edge the drawing does not
## continue past. A bush is a dozen boxes rather than sixteen rows of runs, which
## is the difference between a town costing 107k triangles and costing a quarter
## of that, and the picture is identical because a rectangle of pixels maps onto
## a rectangle of texels exactly.
##
## The cell's sixteen rows stand from the ground up, so the drawing's bottom row
## is the ground contact and its top row is the top of the object. Counting the
## height off the art is the whole point: a bollard came out 15 px and a sign 14,
## and no class constant would have found either.
func _cutout(
	tx: int, ty: int, depth: float, round_plan: bool, filled: bool, outline: int,
	base: float, ground_tile: int, atlas: RefCounted
) -> void:
	var at: int = ty * _size.x + tx
	# The structure's own grid, which is the block grid: a drawing one cell wide
	# and two tall fills half a block across and the whole of it down.
	var box: Rect2i = _span_box(at, tx, ty)
	var across: Vector2i = box.size
	var start: Vector2i = box.position
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var span := across * int(TILE)
	var key: String = _mask_key(tiles, filled, outline)
	var mask: PackedByteArray = _structure_mask(tiles, across, atlas, filled, outline)
	var levels: PackedByteArray = _cell_levels(
		mask, span, round_plan, roundi(depth),
		"%s,%d,%d" % [key, 1 if round_plan else 0, roundi(depth)]
	)

	var edge: int = int(TILE)
	var tile: int = _tiles[at]
	var origin := Vector2i(tx - start.x, ty - start.y) * edge

	# Where the drawing's own rows GO in three dimensions, which is the whole
	# difference between the two drawings this size.
	#
	# The potted plant STANDS: its four rows are leaves above a pot, so the
	# structure is one column of art as tall as the drawing, and every tile of it
	# sits at the depth of the foot. Giving each row its own cell's depth is what
	# left the leaves beside the pot rather than over it.
	#
	# The long flower bed LIES: its four rows are the same bed carrying on away
	# from the eye, so it is no taller than the small one, and each cell stands
	# its own two rows at its own depth. Only the mask is cut over the whole
	# thing, because a cell in the middle of the bed has no ground on its border
	# for the flood to come in through.
	#
	# THROUGH `_world_z`, WHICH IS WHERE A CARVED DRAWING USED TO GO MISSING. The
	# depth axis is world pixels, exactly as `x` is, and the cell row is a GRID
	# row: the grid is the map inside its border ring, so a row of it stands
	# `_margin` tiles north of the same row of the map. Multiplying the grid row
	# out directly stood every carved cutout on an outdoor map 32 world pixels
	# south of its own cell, and 128 wherever the ring is a stamped model. The
	# ground under it, its skirt and every stamped model beside it all measure
	# through `_world_z` and stayed where they belong, which is why this read as a
	# drawing that was not being built rather than as one standing in the wrong
	# place.
	var mid: float = 0.0
	var top: float = 0.0
	if _lying[at] == 1:
		mid = _world_z((ty >> 1) * CELL_TILES) + CELL_TILES * TILE * 0.5
		top = CELL_TILES * TILE - float((ty & 1) * edge)
	else:
		mid = _world_z(((start.y + across.y - 1) >> 1) * CELL_TILES) \
			+ CELL_TILES * TILE * 0.5
		# THE DRAWING'S FOOT IS ITS OWN LOWEST TILE ROW, NOT THE BOX'S.
		#
		# A span box is snapped to the walk-cell grid, and a cell is TWO tiles. A
		# drawing one tile tall therefore lands in the top half of its cell as
		# often as in the bottom, and measuring its rows from the bottom of the
		# BOX stood every one of those a whole tile up in the air. Both were
		# built, so a field of them came out as two crops at two heights: measured
		# over map 10,5, eight flowers standing y 10 to 18 and eight standing y 18
		# to 26, same ground, same stem. The reviewer read it off a screenshot as
		# one tile drawing two flowers with one higher than the other.
		#
		# The foot is the last row of the box that HOLDS this class. Not the same
		# test `_measure_cutouts` cuts a box's bottom with, and the difference is
		# the whole of it: that one asks whether EVERY tile of the row carries the
		# class, which is right for a drawing that fills its box and is never true
		# of a drawing one tile wide inside a cell two tiles across. Asked that
		# way the flower's foot came out above its own tile and the bloom sank
		# into the ground.
		var foot: int = across.y
		while foot > 1 and not _row_holds(start, foot - 1, across.x, _klass[at]):
			foot -= 1
		top = float(foot * int(TILE) - origin.y)

	# The ground and the stretch every height in this carve is measured through.
	# See `_carve_y`. Unlisted classes take 1.0 and stand exactly as they are
	# drawn, which is every carved drawing in the game but the potted plants.
	# A STEM LIFTS THE WHOLE DRAWING, which is what makes it a stem rather than a
	# peg beside one. The bloom is drawn looked down on, so its own bottom row is
	# the near edge of the petals and not a foot: standing it on the floor puts the
	# flower head in the grass, and the post has to hold it up.
	_carve_base = base + float(_stem_rise[at])
	_carve_lift = _stretch[at] if _stretch[at] > 0.0 else 1.0

	var taken := PackedByteArray()
	taken.resize(edge * edge)
	for row: int in edge:
		for column: int in edge:
			if taken[row * edge + column] == 1 \
					or not _drawn(mask, span, origin.x + column, origin.y + row):
				continue
			var level: int = levels[(origin.y + row) * span.x + origin.x + column]
			var wide: int = 1
			while column + wide < edge and taken[row * edge + column + wide] == 0 \
					and _drawn(mask, span, origin.x + column + wide, origin.y + row) \
					and levels[(origin.y + row) * span.x + origin.x + column + wide] == level:
				wide += 1
			var tall: int = 1
			while row + tall < edge:
				var whole: bool = true
				for step: int in wide:
					if taken[(row + tall) * edge + column + step] == 1 \
							or not _drawn(mask, span, origin.x + column + step, origin.y + row + tall) \
							or levels[(origin.y + row + tall) * span.x + origin.x + column + step] != level:
						whole = false
						break
				if not whole:
					break
				tall += 1
			for down: int in tall:
				for across_step: int in wide:
					taken[(row + down) * edge + column + across_step] = 1
			var half: float = float(level) * 0.5
			_cutout_box(
				tx, tile, atlas, mask, origin, span, top,
				Rect2i(column, row, wide, tall), mid - half, mid + half,
				levels, level
			)

	if _stem[at] > 0:
		_stem_post(tx, mask, span, origin, mid, base, ground_tile,
			_stem_shapes[int(_stem[at]) - 1] as Array, atlas)


## THE STEM UNDER A FLOWER, and it is the one piece of geometry in this mod that
## the cartridge does not draw. See `profile.gd:STEMS` for why it is owed one.
##
## THE SHAPE IS DRAWN AND NOT COMPUTED. `shape/stems.gd` carries the rows a
## person painted on `tools/stem_page.py`, one world pixel a character, and this
## stands one box per painted pixel. A stem is a single pixel thick and it bends,
## and neither is a number a rule could have produced.
##
## IT TOUCHES BOTH ENDS. The shape's row count is what `_cutout` lifted the
## drawing by, so the top row of the stem meets the bloom's own bottom row and
## the bottom row meets the ground: nothing floats at either end, whatever is
## drawn between them.
##
## AND IT IS CENTRED UNDER THE BLOOM. What the page cannot know is where in its
## own tile a given clump is drawn, so the stem's own middle is put under the
## middle of the drawing's BOTTOM ROW, which is where the two actually meet. A
## clump sitting off to one side of its tile is therefore held up under itself
## rather than beside itself, and the page's own column means nothing.
##
## IT WEARS THE GRASS, DARK AT THE FOOT AND LIGHT AT THE HEAD. `_ground_art` has
## already found the flat tile the flower grows out of, and `_greens` ranks that
## tile's own greens by how light they are: the stem walks up the ramp, so it is
## in shadow where it meets the ground and catches the light where it meets the
## bloom, which is how the cartridge shades everything else in this file. Every
## texel of it is one the cartridge painted on that map at that hour, and no
## value here says what green is.
##
## NOTHING IS DRAWN WHERE NOTHING IS OWED: a mask with no pixel in it at all is a
## tile the flood ate, and a post standing on its own in the grass is worse than
## the gap it was meant to close.
func _stem_post(
	tx: int, mask: PackedByteArray, span: Vector2i, origin: Vector2i,
	mid: float, base: float, ground_tile: int, rows: Array, atlas: RefCounted
) -> void:
	var edge: int = int(TILE)
	var lowest: int = -1
	var from: int = 0
	var to: int = 0
	for row: int in range(edge - 1, -1, -1):
		for column: int in edge:
			if not _drawn(mask, span, origin.x + column, origin.y + row):
				continue
			if lowest < 0:
				lowest = row
				from = column
			to = column
		if lowest >= 0:
			break
	if lowest < 0:
		return

	# Where the drawn shape's own pixels sit, so its middle can be put under the
	# bloom's. Taken over the whole shape rather than over one row, or a stem that
	# leans would hang its foot out from under the flower.
	var left: int = -1
	var right: int = -1
	for row: int in rows.size():
		var line: String = rows[row]
		for column: int in line.length():
			if line[column] != "#":
				continue
			if left < 0 or column < left:
				left = column
			if column > right:
				right = column
	if left < 0:
		return

	var greens: Array = _greens(ground_tile, atlas)
	var shift: float = _world_x(tx) + (float(from) + float(to) + 1.0) * 0.5 \
		- (float(left) + float(right) + 1.0) * 0.5
	var tall: int = rows.size()
	# ROWS THAT AGREE ARE ONE BOX. A drawn stem is mostly a straight column, so
	# emitting a box per painted pixel spent ten of them on what two describe.
	# Merged only where the run AND the shade band both carry on, so the picture
	# is the same texel for texel and the ramp keeps its steps.
	var row: int = 0
	while row < tall:
		var line: String = String(rows[row])
		var shade: int = _stem_shade(row, tall, greens.size())
		var deep: int = 1
		while row + deep < tall and String(rows[row + deep]) == line \
				and _stem_shade(row + deep, tall, greens.size()) == shade:
			deep += 1
		var uv: Rect2 = atlas.uv_box(ground_tile, Rect2i(greens[shade], Vector2i.ONE))
		var column: int = 0
		while column < line.length():
			if line[column] != "#":
				column += 1
				continue
			var run: int = column
			while run < line.length() and line[run] == "#":
				run += 1
			_fence_box(
				AABB(
					Vector3(
						shift + float(column),
						base + float(tall - row - deep),
						mid - 0.5
					),
					Vector3(float(run - column), float(deep), 1.0)
				),
				uv, uv, true, true, true, true
			)
			column = run
		row += deep


## Which of the grass's greens a row of the stem is painted in: dark at the foot
## and light at the head, which is how the cartridge shades everything else here.
func _stem_shade(row: int, tall: int, greens: int) -> int:
	var up: float = float(tall - 1 - row) / float(maxi(tall - 1, 1))
	return clampi(int(up * float(greens)), 0, greens - 1)


## THE GREENS A TILE IS DRAWN IN, as the pixel each is drawn at, darkest first.
##
## What is wanted is the colours of the grass, so the tile's distinct indices are
## ranked by how far green stands over the other two channels and everything that
## is not green at all is dropped. Sorted by luminance, so walking the array is
## walking from shadow to light.
##
## A tile with no green in it answers with its least unsuitable pixel rather than
## with nothing: a flower on a paving stone still needs a stem.
func _greens(tile: int, atlas: RefCounted) -> Array:
	var seen: Dictionary = {}
	var found: Array = []
	for py: int in int(TILE):
		for px: int in int(TILE):
			var index: int = atlas.pixel(tile, px, py)
			if seen.has(index):
				continue
			seen[index] = true
			var color: Color = atlas.color_of(tile, index)
			if color.g - maxf(color.r, color.b) <= 0.0:
				continue
			found.append([color.get_luminance(), Vector2i(px, py)])
	if found.is_empty():
		return [_greenest(tile, atlas)]
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for entry: Array in found:
		out.append(entry[1])
	return out


## The greenest texel of a tile, as the pixel it is drawn at. The fallback for a
## tile `_greens` finds no green in at all.
func _greenest(tile: int, atlas: RefCounted) -> Vector2i:
	var best := Vector2i.ZERO
	var score: float = -2.0
	for py: int in int(TILE):
		for px: int in int(TILE):
			var color: Color = atlas.color_of(tile, atlas.pixel(tile, px, py))
			var green: float = color.g - maxf(color.r, color.b)
			if green > score:
				score = green
				best = Vector2i(px, py)
	return best


## WHERE A CARVED ROW STANDS, given how many rows of the drawing are under it.
##
## The ground it sits on and how far the drawing is STRETCHED getting there, both
## set by `_cutout` for the length of one carve. Every height in a carved cutout
## goes through here, which is what makes a class able to say it is shorter than
## it is drawn.
##
## HOW TALL A THING IS DRAWN IS NOT HOW TALL IT IS, and this file has now had to
## say that four times: the long flower bed, the school chair, the round stool
## and the potted plant. The first three were answered by giving the drawing to a
## path that could scale it, an object or a model. A CARVED cutout could not be
## scaled at all, so a potted plant carved over its own two cells stood the full
## 32 px of its drawing and read as a black column as tall as the bookcase beside
## it, which is what killed that build. `profile.gd:STRETCH` is the same table the
## models read and it means the same thing on both paths now.
func _carve_y(rows: float) -> float:
	return _carve_base + rows * _carve_lift


## The ground the carve in hand stands on, and its stretch. Members rather than
## arguments because they are constant over one drawing and the three functions
## that need them are the hottest in the mesher.
var _carve_base: float = 0.0
var _carve_lift: float = 1.0


## One rectangle of a cutout, as a box wearing its own texels.
##
## Every face along an edge the drawing continues past is left out, and the ones
## along an edge it does not are cut into the RUNS that are actually exposed. A
## face emitted whole where the drawing continues under half of it would be
## hidden anyway; cutting it is what keeps a silhouette's edge exactly the
## drawing's, and what lets the end walls wear their own end pixel's colour so a
## cut edge is never a foreign one.
func _drawn(mask: PackedByteArray, span: Vector2i, px: int, py: int) -> bool:
	if px < 0 or py < 0 or px >= span.x or py >= span.y:
		return false
	return mask[py * span.x + px] == 1


## How far a top face may look into the body for a texel that is not outline.
## Three is half a bush's crown; further and the cap wears the middle of the
## drawing, which is a different lie from the one being fixed.
const INTERIOR_REACH: int = 3


## A drawn pixel with every neighbour drawn: body rather than silhouette. The
## drawing's outline is exactly the drawn pixels that fail this.
func _interior(mask: PackedByteArray, span: Vector2i, px: int, py: int) -> bool:
	return (
		_drawn(mask, span, px, py)
		and _drawn(mask, span, px - 1, py) and _drawn(mask, span, px + 1, py)
		and _drawn(mask, span, px, py - 1) and _drawn(mask, span, px, py + 1)
	)


## A NEIGHBOUR THAT IS DRAWN IS NOT A NEIGHBOUR THAT CLOSES THE HOLE, and that is
## what made a round carve see-through.
##
## A box is emitted per run of pixels standing at ONE depth, and the edge faces
## round it were drawn only where the pixel beyond was not drawn at all. In a
## flat slab every pixel stands at the same depth, so that test is right and this
## never showed. A ROUND plan gives every row its own chord, so the drawn pixel
## above a wide row is a NARROW row standing several pixels shallower: the step
## between the two had no face on it, and the view went in through the gap,
## through the hollow the two boxes leave between them and out of the back of the
## drawing. The bloom of a flower changes radius on nearly every row and was
## therefore more hole than flower, but every round cutout in the game had it.
##
## So a neighbour closes the edge only where it stands AS DEEP or deeper. The
## face is then laid across this box's whole depth rather than across the
## difference, since the part of it that overlaps the neighbour is buried inside
## the neighbour's own solid and cannot be seen: a few triangles rather than a
## second set of bounds to get wrong.
func _cutout_box(
	tx: int, tile: int, atlas: RefCounted, mask: PackedByteArray,
	origin: Vector2i, span: Vector2i, top: float, box: Rect2i, back: float, front: float,
	levels: PackedByteArray, level: int
) -> void:
	var x0: float = _world_x(tx) + float(box.position.x)
	var x1: float = x0 + float(box.size.x)
	var high: float = _carve_y(top - float(box.position.y))
	var low: float = _carve_y(top - float(box.position.y) - float(box.size.y))
	var uv: Rect2 = atlas.uv_box(tile, box)

	_quad(
		Vector3(x0, low, front), Vector3(x1, low, front),
		Vector3(x1, high, front), Vector3(x0, high, front),
		Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
	)
	_quad(
		Vector3(x1, low, back), Vector3(x0, low, back),
		Vector3(x0, high, back), Vector3(x1, high, back),
		Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
	)

	# Along the top and the bottom, in columns; along the sides, in rows.
	for horizontal: bool in [true, false]:
		for near: bool in [true, false]:
			var run: int = -1
			var length: int = box.size.x if horizontal else box.size.y
			for step: int in length + 1:
				var open: bool = false
				if step < length:
					var at := Vector2i(
						origin.x + box.position.x + (step if horizontal else (0 if near else box.size.x - 1)),
						origin.y + box.position.y + ((0 if near else box.size.y - 1) if horizontal else step)
					)
					var beyond := Vector2i(
						at.x + (0 if horizontal else (-1 if near else 1)),
						at.y + ((-1 if near else 1) if horizontal else 0)
					)
					open = not _drawn(mask, span, beyond.x, beyond.y) \
						or int(levels[beyond.y * span.x + beyond.x]) < level
				if open and run < 0:
					run = step
				elif not open and run >= 0:
					_cutout_edge(
						tx, tile, atlas, mask, origin, span, top, box, back, front,
						horizontal, near, run, step
					)
					run = -1


func _cutout_edge(
	tx: int, tile: int, atlas: RefCounted, mask: PackedByteArray,
	origin: Vector2i, span: Vector2i, top: float,
	box: Rect2i, back: float, front: float, horizontal: bool, near: bool, from: int, to: int
) -> void:
	if horizontal:
		var x0: float = _world_x(tx) + float(box.position.x + from)
		var x1: float = _world_x(tx) + float(box.position.x + to)
		var y: float = _carve_y(
			top - float(box.position.y) - (0.0 if near else float(box.size.y))
		)
		# Rows INSIDE the body. The drawing's own outline is what an upward face
		# would otherwise wear, and a bush whose every top face is its black
		# outline reads as a lump of coal.
		#
		# One row in was enough for a shallow slab and is not enough for a hull:
		# a round crown shows a top face at every row of its upper half, and the
		# whole of that half is within a pixel of the silhouette. So walk in
		# until the pixel is INTERIOR, meaning all four of its neighbours are
		# drawn too, which is the mask's own definition of what is not outline.
		var sample: int = box.position.y + (0 if near else box.size.y - 1)
		if box.size.y > 1:
			sample += 1 if near else -1
		if near:
			var column: int = box.position.x + from
			for _step: int in INTERIOR_REACH:
				if _interior(mask, span, origin.x + column, origin.y + sample):
					break
				if not _drawn(mask, span, origin.x + column, origin.y + sample + 1):
					break
				sample += 1
		var uv: Rect2 = atlas.uv_box(tile, Rect2i(box.position.x + from, sample, to - from, 1))
		if near:
			_quad(
				Vector3(x0, y, front), Vector3(x1, y, front),
				Vector3(x1, y, back), Vector3(x0, y, back),
				Vector3.UP, uv, SHADE_TOP_VOLUME
			)
		else:
			_quad(
				Vector3(x0, y, back), Vector3(x1, y, back),
				Vector3(x1, y, front), Vector3(x0, y, front),
				Vector3.DOWN, uv, SHADE_NORTH
			)
		return

	var x: float = _world_x(tx) + float(box.position.x + (0 if near else box.size.x))
	var high: float = _carve_y(top - float(box.position.y + from))
	var low: float = _carve_y(top - float(box.position.y + to))
	# The same de-outlining the horizontal faces get, and for the same reason: a
	# silhouette's edge COLUMN is outline all the way down, so a flank sampling it
	# comes out solid black. Walk inward until the pixel is interior, testing the
	# middle of the run because that is the row the face mostly shows.
	@warning_ignore("integer_division")
	var middle: int = box.position.y + from + (to - from) / 2
	var column: int = box.position.x + (0 if near else box.size.x - 1)
	var inward: int = 1 if near else -1
	for _step: int in INTERIOR_REACH:
		if _interior(mask, span, origin.x + column, origin.y + middle):
			break
		if not _drawn(mask, span, origin.x + column + inward, origin.y + middle):
			break
		column += inward
	var uv: Rect2 = atlas.uv_box(
		tile, Rect2i(column, box.position.y + from, 1, to - from)
	)
	if near:
		_quad(
			Vector3(x, low, back), Vector3(x, low, front),
			Vector3(x, high, front), Vector3(x, high, back),
			Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
		)
	else:
		_quad(
			Vector3(x, low, front), Vector3(x, low, back),
			Vector3(x, high, back), Vector3(x, high, front),
			Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
		)


## A RAILING: a LINE seen from above, which is a fourth thing a drawing can be.
##
## The three the pipeline knows are a surface seen from above, the face of a flat
## thing, and a portrait of a symmetric one. Goldenrod's metal railing is none of
## them: it is drawn from ABOVE as a thin grey line along the edge of a lawn, with
## a round white cap where two runs meet. Stood up as a cutout, which is what the
## full pass's `stand` fallback did to 2200 tiles of it, the runs going away from
## the eye come out as posts and the runs going across come out as a kerb.
##
## What the drawing states is the LINE: which way it runs, and where across the
## tile it lies. How tall it stands it cannot state, and the reviewer gave it:
## about half a cell, posts and a rail you see over.
##
## So the drawing is read as a plan and the fence is built on it. The one thing
## authored beyond the height is the post SPACING, because a rail with a post only
## where the cartridge draws a cap is a rail floating between corners: one post
## per walk cell, which is the lattice everything else in this world sits on.
const RAIL_HIGH: float = 8.0
const RAIL_TALL: float = 3.0
const RAIL_THICK: float = 3.0
const POST_THICK: float = 4.0


func _railing(tx: int, ty: int, ground: float, atlas: RefCounted) -> void:
	var tile: int = _tile_at(tx, ty)
	var plan: Array = _plan_line(tile, atlas)
	var axis: int = plan[0]
	var middle: float = plan[1]
	var box: Rect2i = plan[2]
	var uv: Rect2 = atlas.uv_box(tile, box)
	var top: float = ground + RAIL_HIGH
	if axis == RAIL_POST:
		_rail_box(
			Vector2(middle - POST_THICK * 0.5, middle - POST_THICK * 0.5),
			Vector2(middle + POST_THICK * 0.5, middle + POST_THICK * 0.5),
			tx, ty, ground, top, uv
		)
		return
	# The rail itself, the width of the tile along its own run, and a post under it
	# at the cell's corner. The rail carries no end cap where the run carries on
	# into the next tile, which is most of them.
	var half: float = RAIL_THICK * 0.5
	if axis == RAIL_EAST:
		_rail_box(
			Vector2(0.0, middle - half), Vector2(TILE, middle + half),
			tx, ty, top - RAIL_TALL, top, uv
		)
	else:
		_rail_box(
			Vector2(middle - half, 0.0), Vector2(middle + half, TILE),
			tx, ty, top - RAIL_TALL, top, uv
		)
	if posmod(tx, CELL_TILES) != 0 or posmod(ty, CELL_TILES) != 0:
		return
	var post: float = POST_THICK * 0.5
	var along: float = TILE * 0.5
	var across: float = middle
	_rail_box(
		Vector2(along - post, across - post) if axis == RAIL_EAST
			else Vector2(across - post, along - post),
		Vector2(along + post, across + post) if axis == RAIL_EAST
			else Vector2(across + post, along + post),
		tx, ty, ground, top - RAIL_TALL, uv
	)


const RAIL_EAST: int = 0
const RAIL_NORTH: int = 1
const RAIL_POST: int = 2
## How many of a row's eight pixels must be drawn for it to count as a run of the
## line rather than as a pixel of one crossing it.
const RAIL_RUN: int = 6


## Which way the line runs, where across the tile it lies, and which pixels of the
## drawing the geometry wears.
##
## Read against the tile's own GROUND, which is whatever index the border ring is
## mostly painted in: a rail is drawn on a lawn and what is not lawn is rail.
func _plan_line(tile: int, atlas: RefCounted) -> Array:
	var ring: Dictionary = {}
	for step: int in int(TILE):
		for index: int in [
			atlas.pixel(tile, step, 0), atlas.pixel(tile, step, int(TILE) - 1),
			atlas.pixel(tile, 0, step), atlas.pixel(tile, int(TILE) - 1, step),
		]:
			ring[index] = int(ring.get(index, 0)) + 1
	var ground: int = -1
	var most: int = 0
	for index: int in ring:
		if int(ring[index]) > most:
			most = int(ring[index])
			ground = index
	var rows := PackedInt32Array()
	var columns := PackedInt32Array()
	rows.resize(int(TILE))
	columns.resize(int(TILE))
	for py: int in int(TILE):
		for px: int in int(TILE):
			if atlas.pixel(tile, px, py) == ground:
				continue
			rows[py] += 1
			columns[px] += 1
	var row_runs: Vector2i = _rail_extent(rows)
	var column_runs: Vector2i = _rail_extent(columns)
	# A run of the line fills its whole tile ACROSS the way it goes, so the axis
	# with the fuller rows is the axis it runs along. A post fills neither.
	if row_runs.y > 0 and row_runs.y >= column_runs.y:
		return [
			RAIL_EAST, float(row_runs.x) + float(row_runs.y) * 0.5,
			Rect2i(0, row_runs.x, int(TILE), row_runs.y),
		]
	if column_runs.y > 0:
		return [
			RAIL_NORTH, float(column_runs.x) + float(column_runs.y) * 0.5,
			Rect2i(column_runs.x, 0, column_runs.y, int(TILE)),
		]
	return [RAIL_POST, TILE * 0.5, Rect2i(0, 0, int(TILE), int(TILE))]


## The first row of the line and how many rows it is, or a zero count where no row
## of this axis is filled enough to be one.
func _rail_extent(counts: PackedInt32Array) -> Vector2i:
	var from: int = -1
	var to: int = -1
	for at: int in counts.size():
		if counts[at] < RAIL_RUN:
			continue
		if from < 0:
			from = at
		to = at
	if from < 0:
		return Vector2i(0, 0)
	return Vector2i(from, to + 1 - from)


## One box of the railing, in tile pixels across the tile and world pixels up.
## Every face wears the same patch of the drawing, which is the rule a cutout's
## faces already follow.
func _rail_box(
	from: Vector2, to: Vector2, tx: int, ty: int, low: float, high: float, uv: Rect2
) -> void:
	var x0: float = _world_x(tx) + from.x
	var x1: float = _world_x(tx) + to.x
	var z0: float = _world_z(ty) + from.y
	var z1: float = _world_z(ty) + to.y
	_quad(
		Vector3(x0, high, z1), Vector3(x1, high, z1), Vector3(x1, high, z0),
		Vector3(x0, high, z0), Vector3.UP, uv, SHADE_TOP_FLAT
	)
	_quad(
		Vector3(x0, low, z1), Vector3(x1, low, z1),
		Vector3(x1, high, z1), Vector3(x0, high, z1),
		Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
	)
	_quad(
		Vector3(x1, low, z0), Vector3(x0, low, z0),
		Vector3(x0, high, z0), Vector3(x1, high, z0),
		Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
	)
	_quad(
		Vector3(x1, low, z1), Vector3(x1, low, z0),
		Vector3(x1, high, z0), Vector3(x1, high, z1),
		Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
	)
	_quad(
		Vector3(x0, low, z0), Vector3(x0, low, z1),
		Vector3(x0, high, z1), Vector3(x0, high, z0),
		Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
	)


func _tile_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	return maxi(_tiles[ty * _size.x + tx], 0)


## The ground a cutout stands ON: the nearest neighbouring tile that is flat
## ground, as its art and its own height. The art, because a cutout's drawing is
## the object and painting it on the floor as well would leave a bollard lying
## under itself; the height, because that ground is what the thing stands on, and
## a bush beside a plateau that stood at zero instead would sink into the rock
## and take the floor around it with it.
##
## A STAIRCASE IS NOT THE GROUND BESIDE ANYTHING, and it has to be refused here.
## A flight marks its cells flat at the height its climb STARTS from, which is a
## walk cell below the floor for a stairwell and the bottom of the run for a
## flight, so a cutout that took it would stand at the foot of the stairs while
## its own cell stands at the top. The League's platform is the case: the
## banister end at its south-east corner sat beside the east flight, took that
## flight's zero, and opened a hole in the platform floor.
##
## AND A RAMP IS FLAT ART AND IS NOT A FLOOR EITHER, which is the same sentence
## `_commonest_edge_floor` already carries and the same reason: a rock rim
## resolves FLAT so its drawing can lie on the slope, and its height is the
## height of the shelf ABOVE it rather than of any ground a thing stands on. The
## notice board at the foot of Violet City's rock is what found it. Its drawing is
## two tile rows, and a cutout takes its ground per TILE: the bottom row looked
## south at the pavement and took 0, the top row looked north at the rim, took
## 16, and the board hung a whole walk cell over its own posts. Measured rather
## than argued, with `_ground_art` printed over the rock: every tile of the rim is
## flat, and the only two tiles in the rectangle that read 16 with 0 under them
## are the sign's.
func _ground_art(tx: int, ty: int) -> Vector2i:
	for step: Vector2i in [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
	]:
		var at := Vector2i(tx + step.x, ty + step.y)
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			continue
		var index: int = at.y * _size.x + at.x
		if _stair_at[index] >= 0 or _ramp[index] == 1:
			continue
		if _art[index] == ART_FLAT and _heights[index] >= 0:
			return Vector2i(maxi(_tiles[index], 0), _heights[index])
	return Vector2i(maxi(_tiles[ty * _size.x + tx], 0), 0)


func _emit(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var tile: int = _tiles[at]
	if tile < 0:
		return
	if _art[at] == ART_CUTOUT or _art[at] == ART_RAILING or _art[at] == ART_FENCE:
		var ground: Vector2i = _ground_art(tx, ty)
		_face_top(tx, ty, float(ground.y), atlas.uv(ground.x), SHADE_TOP_FLAT)
		_side(tx, ty, ground.y, _height_at(tx, ty + 1), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
		_side(tx, ty, ground.y, _height_at(tx, ty - 1), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
		_side(tx, ty, ground.y, _height_at(tx + 1, ty), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
		_side(tx, ty, ground.y, _height_at(tx - 1, ty), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
		# The ground under it is drawn either way; what stands ON it is a whole
		# OBJECT stood up beside its neighbours, the drawing carved out, an authored
		# model stamped there, or a rail on its posts.
		if _house_covered[at] == 1:
			for index: int in _house_over.get(at, PackedInt32Array()) as PackedInt32Array:
				if _house_done.has(index):
					continue
				_house_done[index] = true
				_emit_house(index, atlas)
		elif _object_covered[at] == 1:
			for index: int in _object_over.get(at, PackedInt32Array()) as PackedInt32Array:
				if _object_done.has(index):
					continue
				_object_done[index] = true
				_emit_object(index, atlas)
		elif _art[at] == ART_RAILING:
			_railing(tx, ty, float(ground.y), atlas)
		elif _art[at] == ART_FENCE:
			# ONE FENCE PER WALK CELL, built by whichever of its tiles is emitted
			# first: the model spans the cell and the run's two arms cross at its
			# centre, so a tile is a quarter of it and not a thing of its own.
			var cell: int = ((ty - _margin.y) >> 1) * _size.x + ((tx - _margin.x) >> 1)
			if not _fence_done.has(cell):
				_fence_done[cell] = true
				_fence(tx, ty, float(ground.y), atlas)
		elif _modelled[at] == 1:
			_place_model(tx, ty, atlas)
		else:
			_cutout(
				tx, ty, float(_depths[at]), _round[at] == 1, _filled[at] == 1,
				int(_outlined[at]), float(ground.y), ground.x, atlas
			)
		return
	if _art[at] == ART_LEDGE:
		_wedge(tx, ty, atlas)
		return
	if _ramp[at] == 1:
		_ramp_tile(tx, ty, atlas)
		return
	var here: int = _heights[at]
	var is_volume: bool = _volume[at] == 1

	# A volume wears its structure's TOP row on its cap, so the plateau behind a
	# standing drawing is the top of that drawing rather than whatever tile the
	# column happens to sit on.
	@warning_ignore("integer_division")
	var cap: int = _band_tile(tx, ty, maxi(here / BAND - 1, 0)) if is_volume else tile
	# The one quad that is the water's own surface. The bank around it is not: the
	# faces below are the shore, they wear the shore's art, and they are terrain.
	_sink = SINK_WATER if _is_water(at) else SINK_TERRAIN
	# A facade tile whose drawing is part ground: narrower box, floor beside it.
	if _margin_left[at] > 0 or _margin_right[at] > 0:
		_emit_margined(
			tx, ty, here, cap, int(_margin_left[at]), int(_margin_right[at]), atlas
		)
		_sink = SINK_TERRAIN
		return
	var tilted: bool = _tilted(at)
	if tilted:
		_face_roof(tx, ty, atlas.uv(cap), SHADE_TOP_FLAT)
	else:
		_face_top(
			tx, ty, float(here), atlas.uv(cap),
			SHADE_TOP_VOLUME if is_volume else SHADE_TOP_FLAT
		)
	_sink = SINK_TERRAIN

	# NO RISER BETWEEN TWO TILTED TILES. The tilt already carries one into the next
	# along a shared edge both of them computed the same way, so a face here would
	# be a wall standing out of the slope. Everything else keeps its skirt: where a
	# roof meets anything that is not one, its outermost corners are its own
	# height and the face below still reaches them, which is what puts the eave
	# band on the wall under a leaning pitch.
	_roof_side(tx, ty, tilted, here, Vector2i(0, 1), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(0, -1), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(1, 0), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(-1, 0), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	if _tufted[at] == 1:
		_tufts(tx, ty, float(here), atlas, _long_grass[at] == 1)
	# The flight standing in the cell whose floor this is. Asked for from every one
	# of its four tiles and built by whichever asks first, as an object is.
	if _stair_at[at] >= 0 and not _stair_done.has(_stair_at[at]):
		_stair_done[_stair_at[at]] = true
		_emit_stairs(_stair_at[at], atlas)


## TALL GRASS: the floor keeps the drawing and the tufts stand up out of it.
##
## The cartridge draws the tufts on the ground and then draws them AGAIN over the
## player as they walk through, and that overdraw is the whole statement: the
## grass is taller than they are. Standing a slab of the same drawing up says it
## in geometry, and because each TILE stands at its own depth the player walks
## between the two rows of a cell exactly as the 2D view meant.
##
## Only the tufts stand. The commonest index in the tile is the ground it is
## drawn on, and everything else is a blade; runs of blade along a row become one
## box each, which is what keeps a field of it affordable.
##
## One tile is ONE piece at full height. The reference split each tile again into
## its top and bottom halves and stood those at two depths, which cuts every
## blade in half and reads as two stubs rather than a clump.
const TUFT_THICK: float = 2.0
## How much taller LONG grass stands than tall grass, as a multiple of the rows
## its own drawing has.
##
## The cartridge separates the two in the collision byte and draws its own tile
## for each, and the long one is already the taller drawing: dense blades over a
## ground line, filling its tile where tall grass is a sparse tuft. So most of
## the difference arrives for nothing, because a tuft stands at the pixel row the
## artist put it on. What the drawing CANNOT say is that the long grass reaches
## past the player, and the cartridge says that elsewhere: it doubles the
## encounter rate there, which is the same statement in the only other language
## the hardware had. Eight pixels of art becomes fourteen, which is under a walk
## cell and over the head of a sprite drawn sixteen tall.
const LONG_GRASS_STRETCH: float = 1.75


func _tufts(
	tx: int, ty: int, base: float, atlas: RefCounted, long: bool = false
) -> void:
	var tile: int = _tiles[ty * _size.x + tx]
	if tile < 0:
		return
	var stretch: float = LONG_GRASS_STRETCH if long else 1.0
	var ground: int = _commonest(tile, atlas)
	var edge: int = int(TILE)
	var middle: float = _world_z(ty) + TILE * 0.5
	var back: float = middle - TUFT_THICK * 0.5
	var front: float = middle + TUFT_THICK * 0.5
	# ONE PHASE PER CLUMP, off the tile's own position, so a field bends in
	# patches rather than as one sheet. Per tile rather than per cell, which is
	# what makes the two rows of a cell move against each other the way the 2D
	# view's overdraw implies they are separate.
	var phase: float = _hash_spot(Vector2i(tx, ty))
	_sink = SINK_TUFT
	_sink_uv2 = Vector2(0.0, phase)
	_tuft_foot = base
	_tuft_span = float(edge) * stretch
	# THE BLADES ARE CUT INTO RECTANGLES, not into one box per row of pixels, and
	# it is the same greedy cut `_cutout` makes for exactly the same reason: a
	# blade is a VERTICAL thing, so the pixels above and below each other are the
	# same run over and over and were being stood up as eight stacked boxes with
	# six faces each. The picture is identical texel for texel, because a
	# rectangle of pixels maps onto a rectangle of texels exactly.
	var blade := PackedByteArray()
	blade.resize(edge * edge)
	for py: int in edge:
		for px: int in edge:
			blade[py * edge + px] = 1 if atlas.pixel(tile, px, py) != ground else 0
	var taken := PackedByteArray()
	taken.resize(edge * edge)
	for py: int in edge:
		for px: int in edge:
			if taken[py * edge + px] == 1 or blade[py * edge + px] == 0:
				continue
			# DOWN THE COLUMN FIRST AND THEN ACROSS, which is the opposite of the
			# order a cutout is cut in and is what the drawing asks for: a blade is
			# a vertical thing. Taking the row's run first and extending it down
			# only while every column of it continues fragments a dithered tuft
			# into more boxes than it started with, measured at 85534 triangles
			# WORSE over the game.
			var tall: int = 1
			while py + tall < edge and taken[(py + tall) * edge + px] == 0 \
					and blade[(py + tall) * edge + px] == 1:
				tall += 1
			var wide: int = 1
			while px + wide < edge:
				var whole: bool = true
				for step: int in tall:
					if taken[(py + step) * edge + px + wide] == 1 \
							or blade[(py + step) * edge + px + wide] == 0:
						whole = false
						break
				if not whole:
					break
				wide += 1
			for down: int in tall:
				for step: int in wide:
					taken[(py + down) * edge + px + step] = 1
			_tuft_box(
				tx, tile, atlas, px, px + wide, py, py + tall, base, back, front,
				blade, stretch
			)
	_sink = SINK_TERRAIN


## The clump in hand: where its foot is and how tall it stands, so a vertex can
## be asked how far up it is. See `_push`.
var _tuft_foot: float = 0.0
var _tuft_span: float = 8.0


## One RECTANGLE of blade, stood up as a box.
##
## The drawing's top row is the top of the thing, which is how every upright face
## in this mod is read. Front and back are the drawing; the lid and the two ends
## are cut into the RUNS that are actually exposed, which is the rule `_cutout`
## follows and which the row-at-a-time version could not: it sampled ONE pixel
## above the run to decide the whole lid, and stood both ends of every row
## whether or not the blade carried on beside it.
func _tuft_box(
	tx: int, tile: int, atlas: RefCounted, from: int, to: int,
	from_row: int, to_row: int, base: float, back: float, front: float,
	blade: PackedByteArray, stretch: float
) -> void:
	var edge: int = int(TILE)
	var x0: float = _world_x(tx) + float(from)
	var x1: float = _world_x(tx) + float(to)
	# The whole clump is stretched, not each row, so the drawing keeps its own
	# proportions and only stands taller: a row scaled on its own leaves gaps.
	var low: float = base + float(edge - to_row) * stretch
	var high: float = base + float(edge - from_row) * stretch
	var uv: Rect2 = atlas.uv_box(
		tile, Rect2i(from, from_row, to - from, to_row - from_row)
	)
	_quad(
		Vector3(x0, low, front), Vector3(x1, low, front),
		Vector3(x1, high, front), Vector3(x0, high, front),
		Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
	)
	_quad(
		Vector3(x1, low, back), Vector3(x0, low, back),
		Vector3(x0, high, back), Vector3(x1, high, back),
		Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
	)
	# The lid, over the columns with nothing standing on them.
	var run: int = -1
	for step: int in to - from + 1:
		var open: bool = step < to - from and (
			from_row == 0 or blade[(from_row - 1) * edge + from + step] == 0
		)
		if open and run < 0:
			run = step
		elif not open and run >= 0:
			var lid: Rect2 = atlas.uv_box(
				tile, Rect2i(from + run, from_row, step - run, 1)
			)
			_quad(
				Vector3(_world_x(tx) + float(from + run), high, front),
				Vector3(_world_x(tx) + float(from + step), high, front),
				Vector3(_world_x(tx) + float(from + step), high, back),
				Vector3(_world_x(tx) + float(from + run), high, back),
				Vector3.UP, lid, SHADE_TOP_FLAT
			)
			run = -1
	# The two ends, over the rows where the blade does not carry on beside them.
	for near: bool in [true, false]:
		var column: int = from - 1 if near else to
		run = -1
		for step: int in to_row - from_row + 1:
			var row: int = from_row + step
			var open: bool = step < to_row - from_row and (
				column < 0 or column >= edge or blade[row * edge + column] == 0
			)
			if open and run < 0:
				run = step
			elif not open and run >= 0:
				var y0: float = base + float(edge - from_row - step) * stretch
				var y1: float = base + float(edge - from_row - run) * stretch
				var side: Rect2 = atlas.uv_box(
					tile, Rect2i(from if near else to - 1, from_row + run, 1, step - run)
				)
				if near:
					_quad(
						Vector3(x0, y0, back), Vector3(x0, y0, front),
						Vector3(x0, y1, front), Vector3(x0, y1, back),
						Vector3(-1.0, 0.0, 0.0), side, SHADE_SIDE
					)
				else:
					_quad(
						Vector3(x1, y0, front), Vector3(x1, y0, back),
						Vector3(x1, y1, back), Vector3(x1, y1, front),
						Vector3(1.0, 0.0, 0.0), side, SHADE_SIDE
					)
				run = -1


## The index a tile spends most of itself on, which for tall grass is the ground
## the blades are drawn on.
var _commonest_index: Dictionary = {}


func _commonest(tile: int, atlas: RefCounted) -> int:
	if _commonest_index.has(tile):
		return int(_commonest_index[tile])
	var counts: Dictionary = {}
	var best: int = -1
	var most: int = -1
	for py: int in int(TILE):
		for px: int in int(TILE):
			var index: int = atlas.pixel(tile, px, py)
			counts[index] = int(counts.get(index, 0)) + 1
			if int(counts[index]) > most:
				most = int(counts[index])
				best = index
	_commonest_index[tile] = best
	return best


## One jumping ledge, as an extruded triangle: a ramp rising toward the drop and
## a vertical face at the drop itself.
##
## Which is the collision rule drawn as a shape. Going the way the hop goes, the
## ground rises a band and falls away under you; coming back the other way there
## is a small wall in front of you, which is exactly what the cartridge allows
## and refuses. Nothing about the facing is guessed: see `_measure_ledges`.
func _wedge(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var step: Vector2i = _ledge_step(_ledge[at])
	var base: int = _heights[at]
	var top: int = base + LEDGE_RISE
	var uv: Rect2 = atlas.uv(maxi(_tiles[at], 0))
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	# The ramp, cornered in `_face_top`'s own order so the drawing keeps its
	# north-up orientation, each corner lifted by how far along the slope it is.
	_quad(
		Vector3(x0, _wedge_y(base, step, 0, 1), z1),
		Vector3(x1, _wedge_y(base, step, 1, 1), z1),
		Vector3(x1, _wedge_y(base, step, 1, 0), z0),
		Vector3(x0, _wedge_y(base, step, 0, 0), z0),
		Vector3(-float(step.x), 1.0, -float(step.y)).normalized(), uv, SHADE_TOP_FLAT
	)
	# The drop is the one side standing at the top of the ramp. The other three
	# skirt from the foot down to whatever is beside them, as any tile does.
	_side(tx, ty, top if step.y > 0 else base, _height_at(tx, ty + 1),
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_side(tx, ty, top if step.y < 0 else base, _height_at(tx, ty - 1),
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	_side(tx, ty, top if step.x > 0 else base, _height_at(tx + 1, ty),
		Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_side(tx, ty, top if step.x < 0 else base, _height_at(tx - 1, ty),
		Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	# The slope's own profile closes the two ends of a run of them.
	var across := Vector2i(step.y, step.x)
	_wedge_end(tx, ty, across, step, base, top, uv)
	_wedge_end(tx, ty, -across, step, base, top, uv)


## The triangle that ends a ledge sideways. A neighbour facing the same way
## carries the ramp on and needs none, and one standing at the top of it buries
## it.
func _wedge_end(
	tx: int, ty: int, side: Vector2i, step: Vector2i,
	base: int, top: int, uv: Rect2
) -> void:
	var nx: int = tx + side.x
	var ny: int = ty + side.y
	if _ledge_at(nx, ny) == _ledge[ty * _size.x + tx]:
		return
	if _height_at(nx, ny) >= top:
		return
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var low: float = float(base)
	# The face's own bottom edge, read left to right from outside the way `_quad`
	# reads every side, so the drawing lands the same way up as it does on a wall.
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var normal := Vector3.ZERO
	var shade: Color = SHADE_SIDE
	if side.y > 0:
		a = Vector3(x0, low, z1)
		b = Vector3(x1, low, z1)
		normal = Vector3(0.0, 0.0, 1.0)
		shade = SHADE_SOUTH
	elif side.y < 0:
		a = Vector3(x1, low, z0)
		b = Vector3(x0, low, z0)
		normal = Vector3(0.0, 0.0, -1.0)
		shade = SHADE_NORTH
	elif side.x > 0:
		a = Vector3(x1, low, z1)
		b = Vector3(x1, low, z0)
		normal = Vector3(1.0, 0.0, 0.0)
	else:
		a = Vector3(x0, low, z0)
		b = Vector3(x0, low, z1)
		normal = Vector3(-1.0, 0.0, 0.0)
	# The apex stands over whichever end of that edge the ramp climbs toward.
	var over_a: bool = (a - b).dot(Vector3(float(step.x), 0.0, float(step.y))) > 0.0
	var apex: Vector3 = (a if over_a else b) + Vector3(0.0, float(top - base), 0.0)
	_tri(
		a, b, apex, normal,
		Vector2(uv.position.x, uv.position.y + uv.size.y),
		Vector2(uv.position.x + uv.size.x, uv.position.y + uv.size.y),
		Vector2(uv.position.x if over_a else uv.position.x + uv.size.x, uv.position.y),
		shade
	)


## How high one corner of the ramp stands: the foot on the side the player hops
## from, a band higher on the side it drops. [param u] and [param v] are the
## corner, 0 or 1 along x and along z.
func _wedge_y(base: int, step: Vector2i, u: int, v: int) -> float:
	var along: int = 0
	if step.x > 0:
		along = u
	elif step.x < 0:
		along = 1 - u
	elif step.y > 0:
		along = v
	else:
		along = 1 - v
	return float(base + LEDGE_RISE * along)


func _ledge_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return LEDGE_NONE
	return _ledge[ty * _size.x + tx]


## What lies past the edge of the map, in two parts: the RING, which is the
## border block STOOD UP, and the SKIRT beyond it, which is that ring's own floor
## carried out to the horizon.
##
## The ring is the cartridge's own answer and there was none before: eighteen maps
## end in a tree line, sixteen in a hedge, twenty in open sea. The skirt is what
## keeps the world from stopping dead a few cells out, which is the one thing a
## perspective view shows that a tile page never had to answer for.
##
## HOW DEEP the ring goes is decided by WHAT IT BUYS, and for most maps that is
## one block. A border block that lies FLAT, which is open ground on sixteen maps
## and open sea on twenty, is drawn to the horizon by the skirt already: one
## block of ring is enough to put the border block's own floor under it, and the
## skirt finds that floor rather than the map's own edge, so a coast now runs out
## as sea instead of as beach. A CARVED drawing stops at one block for a
## different reason, which is the bill: a hedge bush is about 170 triangles a
## tile, and a ring eight blocks deep of it put 2.3M triangles round one town
## against the 246k the town itself costs, and took the game from 9.3M to 37M.
##
## A STAMPED MODEL is the one thing worth repeating. A tree emits no geometry at
## all, only an instance, so eighteen maps that end in a tree line can really end
## in a wood four blocks deep. Deeper again is free to draw and is not free to
## RESOLVE: the ring is resolved with the map and that pass is not sliced over
## frames, so eight blocks put the largest map's resolve from 78 ms to 186.
##
## Both depths are a whole number of BLOCKS on purpose: the ring is the border
## block repeated, and a drawing anchored to the block grid inside the map has to
## stay anchored to it outside.
##
## OUT OF DOORS ONLY. A room ends at its walls and there is nothing past them:
## carrying anything out of a house would lay its lino across the void it is
## drawn against. The host is what says which a map is.
const RING_TILES: int = 4
const RING_TILES_MODELLED: int = 16
const BORDER_TILES: int = 32
var _border: Dictionary = {}
var _outside: bool = false


## How deep this map's ring goes, read off the block that fills it.
##
## Asked of the block ONE past the map's north-west corner, which is the ring
## wherever the map has no connection there, and of every one of its sixteen
## tiles: the deep ring is only worth its resolve where the whole block is
## stamped, and a block mixing a model with carved geometry is not. Nothing in
## the game mixes shape classes in a border block, but the rule costs nothing and
## does not depend on that staying true.
func _ring_depth(source: RefCounted, shape: RefCounted) -> int:
	for row: int in RomLayout.MAP_BLOCK_TILE_WIDTH:
		for column: int in RomLayout.MAP_BLOCK_TILE_WIDTH:
			var tile: int = source.tile_at(column - RING_TILES, row - RING_TILES)
			if tile < 0:
				continue
			var shape_class: StringName = shape.at(
				tile,
				source.permission_at(Vector2i(
					(column - RING_TILES) >> 1, (row - RING_TILES) >> 1
				))
			)
			if not shape.is_model(shape_class):
				return RING_TILES
	return RING_TILES_MODELLED


## The floor carried out past the ring, as one flat quad per tile.
func _emit_skirt(tx: int, ty: int, atlas: RefCounted) -> void:
	var edge := Vector2i(clampi(tx, 0, _size.x - 1), clampi(ty, 0, _size.y - 1))
	var key: int = edge.y * _size.x + edge.x
	if not _border.has(key):
		_border[key] = _skirt_floor(edge)
	var floor_at: Vector2i = _border[key]
	if floor_at.x < 0:
		return
	# Twenty maps end in open sea, so most of the skirt in the game IS water and
	# it has to reach the water's own material or a coast runs out as a flat blue
	# floor beyond the last rippling tile. The recess is what says so, exactly as
	# it does inside the map.
	_sink = SINK_WATER if floor_at.y < 0 else SINK_TERRAIN
	_face_top(tx, ty, float(floor_at.y), atlas.uv(floor_at.x), SHADE_TOP_FLAT)
	_sink = SINK_TERRAIN


## The tile id and height of the floor at one grid edge position, as a Vector2i.
##
## THE RING'S OWN FLOOR, and only the ring's. Past the map the ground is the
## border block's, so the search is the depth of the ring and no further: on the
## twenty sea maps and the sixteen open ones that is the border block's own tile
## in every column, and a shoreline still carries the water out rather than the
## beach because the water is what the border block draws.
##
## A ring with no floor anywhere in it, which is a hedge or a tree line, falls
## back to the map's own edge ONCE for the whole map rather than per column.
## Per column was the older rule and it is wrong here: a town whose path meets
## its boundary laid an orange runway to the horizon, and a town whose north side
## is eight tiles of building drew nothing at all and opened a hole in the ground
## plane. A wrong patch of grass reads as grass; a hole reads as a hole.
func _skirt_floor(edge: Vector2i) -> Vector2i:
	var inward := Vector2i(
		1 if edge.x == 0 else (-1 if edge.x == _size.x - 1 else 0),
		1 if edge.y == 0 else (-1 if edge.y == _size.y - 1 else 0)
	)
	for step: int in maxi(_margin.x, 1):
		var at := edge + inward * step
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			break
		var index: int = at.y * _size.x + at.x
		if _art[index] == ART_FLAT and _tiles[index] >= 0:
			return Vector2i(_tiles[index], _heights[index])
	return _commonest_edge_floor()


var _edge_floor := Vector2i(-2, 0)


## Counted over the MAP's own perimeter and not the grid's, which is the ring: a
## hedge ring has no floor in it anywhere, which is the case this exists for.
func _commonest_edge_floor() -> Vector2i:
	if _edge_floor.x != -2:
		return _edge_floor
	var counts: Dictionary = {}
	var best: int = 0
	_edge_floor = Vector2i(-1, 0)
	var box := Rect2i(_margin, _map_size)
	for ty: int in range(box.position.y, box.end.y):
		for tx: int in range(box.position.x, box.end.x):
			if tx != box.position.x and ty != box.position.y \
					and tx != box.end.x - 1 and ty != box.end.y - 1:
				continue
			var index: int = ty * _size.x + tx
			# A RAMP IS FLAT ART AND IS NOT A FLOOR. The rim of a rock shelf is
			# resolved flat so its drawing can lie on the slope, and counting it
			# here paved the whole outside of Ecruteak in cliff face.
			if _art[index] != ART_FLAT or _tiles[index] < 0 or _ramp[index] == 1:
				continue
			var key: int = _tiles[index] * 1024 + _heights[index] + 512
			counts[key] = int(counts.get(key, 0)) + 1
			if int(counts[key]) > best:
				best = int(counts[key])
				_edge_floor = Vector2i(_tiles[index], _heights[index])
	return _edge_floor


## A FACADE TILE THAT DOES NOT DRAW ONLY FACADE, narrowed to the part that is.
##
## The wall's own box shrinks off the edges the drawing says are ground, and the
## strip that leaves is floor, drawn at whatever the neighbour beside it stands
## at and wearing that neighbour's art. `profile.gd:FACADE_MARGIN` says why.
##
## Everything else about the tile is unchanged: the box still folds the same
## drawing, still skirts to the same neighbours and still caps at the same
## height, so this is one narrower box and one quad of floor rather than a new
## kind of thing.
func _emit_margined(
	tx: int, ty: int, here: int, cap: int, left: int, right: int,
	atlas: RefCounted
) -> void:
	var x0: float = _world_x(tx) + float(left)
	var x1: float = _world_x(tx) + TILE - float(right)
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var uv: Rect2 = atlas.uv(cap)
	_quad(
		Vector3(x0, float(here), z1), Vector3(x1, float(here), z1),
		Vector3(x1, float(here), z0), Vector3(x0, float(here), z0),
		Vector3.UP, uv, SHADE_TOP_VOLUME
	)
	# The floor the narrowing exposes, one strip per edge, at the height of
	# whatever stands beside it so a house on a step does not float its own verge.
	if left > 0:
		_margin_floor(tx, ty, _world_x(tx), x0, _height_at(tx - 1, ty), atlas)
	if right > 0:
		_margin_floor(tx, ty, x1, _world_x(tx) + TILE, _height_at(tx + 1, ty), atlas)

	_side_span(tx, ty, x0, x1, here, _height_at(tx, ty + 1),
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_side_span(tx, ty, x0, x1, here, _height_at(tx, ty - 1),
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	# The narrowed sides face the strip they just exposed, so they run down to the
	# ground beside rather than to the neighbour two tiles away.
	var west: int = _height_at(tx - 1, ty) if left == 0 else mini(
		_height_at(tx - 1, ty), _height_at(tx, ty + 1)
	)
	var east: int = _height_at(tx + 1, ty) if right == 0 else mini(
		_height_at(tx + 1, ty), _height_at(tx, ty + 1)
	)
	_side_at(x1, z0, z1, here, east, Vector3(1.0, 0.0, 0.0), tx, ty, atlas)
	_side_at(x0, z0, z1, here, west, Vector3(-1.0, 0.0, 0.0), tx, ty, atlas)


## One strip of floor left by a narrowed facade, wearing the art of the tile it
## runs out to.
func _margin_floor(
	tx: int, ty: int, x0: float, x1: float, height: int, atlas: RefCounted
) -> void:
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var ground: Vector2i = _ground_art(tx, ty)
	var uv: Rect2 = atlas.uv(ground.x)
	var y: float = float(maxi(height, ground.y))
	_quad(
		Vector3(x0, y, z1), Vector3(x1, y, z1),
		Vector3(x1, y, z0), Vector3(x0, y, z0),
		Vector3.UP, uv, SHADE_TOP_FLAT
	)


## The south or north face of a narrowed box, band by band as `_side` does it but
## over a chosen span of x rather than the whole tile.
func _side_span(
	tx: int, ty: int, x0: float, x1: float, here: int, neighbour: int,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	if neighbour >= here:
		return
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	@warning_ignore("integer_division")
	for step: int in (here - neighbour) / BAND:
		var low: float = float(neighbour + step * BAND)
		var high: float = low + TILE
		var uv: Rect2 = atlas.uv(_band_tile(tx, ty, maxi(floori(low / TILE), 0)))
		if normal.z > 0.0:
			_quad(
				Vector3(x0, low, z1), Vector3(x1, low, z1),
				Vector3(x1, high, z1), Vector3(x0, high, z1),
				normal, uv, shade
			)
		else:
			_quad(
				Vector3(x1, low, z0), Vector3(x0, low, z0),
				Vector3(x0, high, z0), Vector3(x1, high, z0),
				normal, uv, shade
			)


## The east or west face of a narrowed box, standing at a chosen x.
func _side_at(
	x: float, z0: float, z1: float, here: int, neighbour: int,
	normal: Vector3, tx: int, ty: int, atlas: RefCounted
) -> void:
	if neighbour >= here:
		return
	@warning_ignore("integer_division")
	for step: int in (here - neighbour) / BAND:
		var low: float = float(neighbour + step * BAND)
		var high: float = low + TILE
		var uv: Rect2 = atlas.uv(_band_tile(tx, ty, maxi(floori(low / TILE), 0)))
		if normal.x > 0.0:
			_quad(
				Vector3(x, low, z1), Vector3(x, low, z0),
				Vector3(x, high, z0), Vector3(x, high, z1),
				normal, uv, SHADE_SIDE
			)
		else:
			_quad(
				Vector3(x, low, z0), Vector3(x, low, z1),
				Vector3(x, high, z1), Vector3(x, high, z0),
				normal, uv, SHADE_SIDE
			)


## Whether a tile's top is a TILTED quad rather than a flat one: a roof seen from
## above, or a facade band the pitch actually leaned. A slope-pinned tile whose
## column was read as a stack of storeys is neither, and has to keep every face a
## wall has: the dance hall stands its end board 128 px beside a 16 px gallery,
## and suppressing that face would open the tower down one side.
func _tilted(at: int) -> bool:
	return _part[at] == PART_ROOF or _pitched[at] == 1


## One face of a column, unless both sides of it are tilted: see the call site.
func _roof_side(
	tx: int, ty: int, tilted: bool, here: int, step: Vector2i,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	var at := Vector2i(tx + step.x, ty + step.y)
	if tilted and at.x >= 0 and at.y >= 0 and at.x < _size.x and at.y < _size.y \
			and _tilted(at.y * _size.x + at.x):
		return
	_side(tx, ty, here, _height_at(at.x, at.y), normal, shade, atlas)


## A ROOF IS TILTED, NOT STEPPED, and the whole of it is one rule at the corners.
##
## `_roof_row` drops a roof tile a band per `ROOF_DROP`, which is what the drawing
## says; laid out as one flat quad per tile that reads as a ziggurat, a band at a
## time, where the cartridge draws a slope. So a roof tile's top is a quad with
## FOUR corner heights, and each corner takes the mean of the roof tiles that
## touch it.
##
## That is continuous BY CONSTRUCTION and it is why nothing here can open a hole:
## two roof tiles sharing an edge compute both of its corners from the same set
## of neighbours, so their surfaces meet exactly whatever their nominal heights
## are. It is also why the roof's outer edge stays where it was: past the last
## roof tile there is nothing to average with, so the outermost corners keep the
## tile's own height and the wall under them still reaches it.
##
## `_heights` is left at the nominal band. What stands on a roof, what the battle
## traces its sight lines through and what the skirt below it reaches are all
## questions about the storey, not about the slope across one tile.
func _roof_corner(tx: int, ty: int, dx: int, dy: int) -> float:
	var total: float = 0.0
	var found: int = 0
	for step: Vector2i in [
		Vector2i(0, 0), Vector2i(dx, 0), Vector2i(0, dy), Vector2i(dx, dy)
	]:
		var at := Vector2i(tx + step.x, ty + step.y)
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			continue
		var index: int = at.y * _size.x + at.x
		if not _tilted(index):
			continue
		total += float(_heights[index])
		found += 1
	if found == 0:
		return float(_heights[ty * _size.x + tx])
	return total / float(found)


## The tilted top of one roof tile. The corners are named the way `_quad` wants
## them, counter-clockwise seen from outside.
func _face_roof(tx: int, ty: int, uv: Rect2, shade: Color) -> void:
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var a := Vector3(x0, _roof_corner(tx, ty, -1, 1), z1)
	var b := Vector3(x1, _roof_corner(tx, ty, 1, 1), z1)
	var c := Vector3(x1, _roof_corner(tx, ty, 1, -1), z0)
	var d := Vector3(x0, _roof_corner(tx, ty, -1, -1), z0)
	# THE NORMAL IS THE TILT'S, not UP. A gable's one band over one tile is a
	# slope of five degrees and nobody could see the difference; a great roof
	# falling twelve tiles from its ridge is a real 45 degree plane, and lighting
	# it as though it were the floor makes its two pitches the same brightness at
	# every hour of the day, which is the one thing a roof must not be.
	var normal: Vector3 = (c - a).cross(d - b).normalized()
	if normal.y < 0.0:
		normal = -normal
	_quad(a, b, c, d, normal, uv, shade)


## ONE TILE OF THE ROCK RIM, as the ramp `_measure_ramps` measured.
##
## Its top is a quad on four corner heights rather than one, wearing the tile's
## own drawing: the cartridge draws the rim as the rock's face and that face is
## exactly what a walker up the slope is looking at. What is left of the vertical
## skirt is only where the ramp meets something that is NOT shelf and stands
## lower, which is a rim running into a wall or a recess rather than into the
## floor it was cut for.
func _ramp_tile(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var uv: Rect2 = atlas.uv(maxi(_tiles[at], 0))
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var nw: float = float(_corners[at * 4])
	var ne: float = float(_corners[at * 4 + 1])
	var sw: float = float(_corners[at * 4 + 2])
	var se: float = float(_corners[at * 4 + 3])
	var normal: Vector3 = (Vector3(x1, ne, z0) - Vector3(x0, sw, z1)).cross(
		Vector3(x1, se, z1) - Vector3(x0, nw, z0)
	).normalized()
	if normal.y < 0.0:
		normal = -normal
	_quad(
		Vector3(x0, sw, z1), Vector3(x1, se, z1),
		Vector3(x1, ne, z0), Vector3(x0, nw, z0),
		normal, uv, SHADE_TOP_FLAT
	)
	# South, north, east and west, each from the neighbour's own floor up to the
	# two corners of the shared edge. A neighbour that is shelf too has the same
	# two heights there by construction, so there is nothing to close.
	_ramp_side(tx, ty, Vector2i(0, 1), sw, se, Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, uv)
	_ramp_side(tx, ty, Vector2i(0, -1), ne, nw, Vector3(0.0, 0.0, -1.0), SHADE_NORTH, uv)
	_ramp_side(tx, ty, Vector2i(1, 0), se, ne, Vector3(1.0, 0.0, 0.0), SHADE_SIDE, uv)
	_ramp_side(tx, ty, Vector2i(-1, 0), nw, sw, Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, uv)


## One side of a ramp, as a single quad with a sloping top edge. [param first]
## and [param second] are the corners of that edge read left to right from
## outside, which is the order `_quad` wants.
func _ramp_side(
	tx: int, ty: int, step: Vector2i, first: float, second: float,
	normal: Vector3, shade: Color, uv: Rect2
) -> void:
	var to := Vector2i(tx + step.x, ty + step.y)
	if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
		return
	var index: int = to.y * _size.x + to.x
	if _shelf[index] == 1:
		return
	var floor_y: float = float(_heights[index])
	if floor_y >= first and floor_y >= second:
		return
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	if step.y > 0:
		a = Vector3(x0, floor_y, z1)
		b = Vector3(x1, floor_y, z1)
	elif step.y < 0:
		a = Vector3(x1, floor_y, z0)
		b = Vector3(x0, floor_y, z0)
	elif step.x > 0:
		a = Vector3(x1, floor_y, z1)
		b = Vector3(x1, floor_y, z0)
	else:
		a = Vector3(x0, floor_y, z0)
		b = Vector3(x0, floor_y, z1)
	_quad(
		a, b,
		Vector3(b.x, maxf(second, floor_y), b.z), Vector3(a.x, maxf(first, floor_y), a.z),
		normal, uv, shade
	)


func _face_top(tx: int, ty: int, y: float, uv: Rect2, shade: Color) -> void:
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	_quad(
		Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0),
		Vector3.UP, uv, shade
	)


## One face of a column, as 8px bands running from the neighbour's own top up to
## this one's. A neighbour standing at least as tall hides the face entirely,
## which is most of the geometry inside a building; a neighbour standing lower
## leaves a skirt, which is what puts a lip on every shoreline.
func _side(
	tx: int, ty: int, here: int, neighbour: int,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	if neighbour >= here:
		return
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	for step: int in (here - neighbour) / BAND:
		var low: float = float(neighbour + step * BAND)
		var high: float = low + TILE
		# The band's own height above the ground plane picks the map row that
		# folds into it. A skirt below the plane repeats the tile's own art.
		var uv: Rect2 = atlas.uv(_band_tile(tx, ty, maxi(floori(low / TILE), 0)))
		if normal.z > 0.0:
			_quad(
				Vector3(x0, low, z1), Vector3(x1, low, z1),
				Vector3(x1, high, z1), Vector3(x0, high, z1),
				normal, uv, shade
			)
		elif normal.z < 0.0:
			_quad(
				Vector3(x1, low, z0), Vector3(x0, low, z0),
				Vector3(x0, high, z0), Vector3(x1, high, z0),
				normal, uv, shade
			)
		elif normal.x > 0.0:
			_quad(
				Vector3(x1, low, z1), Vector3(x1, low, z0),
				Vector3(x1, high, z0), Vector3(x1, high, z1),
				normal, uv, shade
			)
		else:
			_quad(
				Vector3(x0, low, z0), Vector3(x0, low, z1),
				Vector3(x0, high, z1), Vector3(x0, high, z0),
				normal, uv, shade
			)


## [param a] to [param d] are the face's corners read counter-clockwise from
## outside, with a and b its lower edge left to right, so the uv rectangle maps
## a to its bottom-left corner on every face alike.
##
## The triangles come out in the reverse of that order, because Godot's front
## faces wind CLOCKWISE seen from the front. Getting it backwards leaves every
## solid in the map inside out: the near faces cull away and the view is of the
## far side of things, which reads as a world of floating slabs.
func _quad(
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3, uv: Rect2, shade: Color
) -> void:
	var u0: float = uv.position.x
	var v0: float = uv.position.y
	var u1: float = u0 + uv.size.x
	var v1: float = v0 + uv.size.y
	_push(a, normal, Vector2(u0, v1), shade)
	_push(c, normal, Vector2(u1, v0), shade)
	_push(b, normal, Vector2(u1, v1), shade)
	_push(a, normal, Vector2(u0, v1), shade)
	_push(d, normal, Vector2(u0, v0), shade)
	_push(c, normal, Vector2(u1, v0), shade)


## Half of a `_quad`, and the same corner order: [param a] to [param b] is the
## lower edge left to right from outside, with [param c] the single vertex above
## it. Reversed the same way, because Godot's front faces wind clockwise.
func _tri(
	a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, shade: Color
) -> void:
	_push(a, normal, uv_a, shade)
	_push(c, normal, uv_c, shade)
	_push(b, normal, uv_b, shade)


func _push(vertex: Vector3, normal: Vector3, uv: Vector2, shade: Color) -> void:
	# THE TERRAIN CASE IS TESTED FIRST AND RETURNS, and that is not a style
	# choice: this runs once per VERTEX, about 25 million times over the game, and
	# terrain is 94% of them. Written as a `match` with the two rare sinks first it
	# cost 3.4 s of the emit, measured over every map with `tools/cost.gd`, for a
	# feature that adds no geometry at all.
	if _sink == SINK_TERRAIN:
		_vertices.push_back(vertex)
		_normals.push_back(normal)
		_uvs.push_back(uv)
		_colors.push_back(shade)
		return
	if _sink == SINK_TUFT:
		_tuft_vertices.push_back(vertex)
		_tuft_normals.push_back(normal)
		_tuft_uvs.push_back(uv)
		_tuft_colors.push_back(shade)
		# HOW FAR UP ITS OWN CLUMP THIS VERTEX STANDS, read off the vertex rather
		# than handed down per quad. The sway is squared through this, so a box
		# spanning several rows of the drawing has to lean by MORE at its top than
		# at its foot; one value for the whole box pins the two together and a
		# merged blade slides sideways in one piece. Per vertex it is also smoother
		# than the row-at-a-time value it replaces.
		_tuft_uv2s.push_back(Vector2(
			clampf((vertex.y - _tuft_foot) / _tuft_span, 0.0, 1.0), _sink_uv2.y
		))
		return
	_water_vertices.push_back(vertex)
	_water_normals.push_back(normal)
	_water_uvs.push_back(uv)
	_water_colors.push_back(shade)
