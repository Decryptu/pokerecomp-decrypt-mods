extends RefCounted

## Turns a map's tile layer into one static mesh.
##
## Units are WORLD PIXELS throughout: a graphics tile is 8 across, a walk cell
## 16, and a height is a whole number of 8px bands, so a shape height can be
## read straight off the art.

const Houses: GDScript = preload("houses.gd")
const Levels: GDScript = preload("levels.gd")
const Model: GDScript = preload("model.gd")

const TILE: float = 8.0
const TILE_PX: int = 8
const BAND: int = 8
## The shortest face that may lift the ground behind it. A face under a walk
## cell stands its own rim and seeds no plateau: a kerb is not a storey.
const PLATEAU_FLOOR: int = BAND * 2

## How large a region a face shorter than a walk cell may lift, in tiles.
## Four walk cells: a rock patch, never a town.
const PATCH_TILES: int = 16

## Volume height cap in walk cells, so nothing measured wrong becomes a tower.
const MAX_CELLS: int = 3
const CELL_TILES: int = RomLayout.MAP_BLOCK_CELL_WIDTH

## Per-face brightness into the sampled texel. South is the artwork itself and
## draws untouched; a volume's top darkens so the plateau behind reads as depth.
const SHADE_SOUTH: Color = Color(1.0, 1.0, 1.0)
const SHADE_SIDE: Color = Color(0.80, 0.80, 0.80)
const SHADE_NORTH: Color = Color(0.64, 0.64, 0.64)
const SHADE_TOP_FLAT: Color = Color(1.0, 1.0, 1.0)
const SHADE_TOP_VOLUME: Color = Color(0.86, 0.86, 0.86)

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()

## Water and standing grass leave the terrain mesh: neither is opaque paint, so
## each wants its own material. Only a recess's TOP quad and a tuft's STANDING
## part go; the bank and the floor stay terrain.
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
## Per tuft vertex: height up its own clump, 0 at the root and 1 at the tip, and
## the clump's phase. `ARRAY_TEX_UV2`, since UV is already the atlas.
var _tuft_uv2s := PackedVector2Array()
## A quarter turn applied to everything `_quad` lays down. See `_turned`.
var _turn: bool = false
var _turn_pivot := Vector3.ZERO
var _sink: int = SINK_TERRAIN
var _sink_uv2 := Vector2.ZERO

## Art modes, kept per tile as a byte because every tile of every map carries one.
const ART_FLAT: int = 0
const ART_TOP: int = 1
const ART_UPRIGHT: int = 2
const ART_CUTOUT: int = 3
const ART_LEDGE: int = 4
const ART_RAILING: int = 5
const ART_FENCE: int = 6
const ART_BALL: int = 7
## A fence's thickness, the one authored number in it: a drawing seen face-on
## states its width and height and says nothing about its depth.
const FENCE_THICK: float = 3.0

## The RESOLVED grid, map plus border ring, and the map's own size inside it.
## Arrays index on the grid; the world is measured from the map's own corner, so
## everything outside this file speaks map coordinates.
var _size := Vector2i.ZERO
var _map_size := Vector2i.ZERO
var _margin := Vector2i.ZERO
var _margin_far := Vector2i.ZERO
var _map_end := Vector2i.ZERO
const BANK_SPAN: int = 6
var _bank: ImageTexture = null
var _tiles := PackedInt32Array()
var _art := PackedByteArray()
var _depths := PackedByteArray()
var _round := PackedByteArray()
var _filled := PackedByteArray()
var _stem := PackedByteArray()
var _stem_rise := PackedByteArray()
var _stem_shapes: Array = []
var _outlined := PackedByteArray()
var _modelled := PackedByteArray()
var _shrub := PackedByteArray()
var _rock := PackedByteArray()
var _potted := PackedByteArray()
var _column := PackedByteArray()
var _stretch := PackedFloat32Array()
var _tufted := PackedByteArray()
var _long_grass := PackedByteArray()
var _span_x := PackedByteArray()
var _span_y := PackedByteArray()
var _span_cut := PackedByteArray()
var _lying := PackedByteArray()
var _on_furniture := PackedByteArray()
var _swaying := PackedByteArray()
var _klass := PackedInt32Array()
var _class_ids: Dictionary = {}

var _facts: Dictionary = {}
const FACT_STRIDE: int = 258
const FACT_ART: int = 0
const FACT_DEPTH: int = 1
const FACT_ROUND: int = 2
const FACT_FILLED: int = 3
const FACT_STEM: int = 4
const FACT_STEM_RISE: int = 5
const FACT_OUTLINED: int = 6
const FACT_MODELLED: int = 7
const FACT_SHRUB: int = 8
const FACT_ROCK: int = 9
const FACT_COLUMN: int = 10
const FACT_STRETCH: int = 11
const FACT_TUFTED: int = 12
const FACT_LYING: int = 13
const FACT_ON_FURNITURE: int = 14
const FACT_SPAN_X: int = 15
const FACT_SPAN_Y: int = 16
const FACT_KLASS: int = 17
const FACT_PART: int = 18
const FACT_DROP: int = 19
const FACT_SLOPE: int = 20
const FACT_VOID: int = 21
const FACT_MARGIN_LEFT: int = 22
const FACT_MARGIN_RIGHT: int = 23
const FACT_VOLUME: int = 24
const FACT_CLIFF: int = 25
const FACT_FRONT: int = 26
const FACT_LIP: int = 27
const FACT_HEIGHT: int = 28
const FACT_POTTED: int = 29
const FACT_SWAYS: int = 30

var _object_covered := PackedByteArray()
var _object_over: Dictionary = {}
var _surface := PackedInt32Array()
const NO_OBJECT: int = -0x40000000
var _objects: Array = []
var _stair_at := PackedInt32Array()
var _stairs: Array = []
var _stair_done: Dictionary = {}
var _object_done: Dictionary = {}
const PART_NONE: int = 0
const PART_WALL: int = 1
const PART_ROOF: int = 2
var _part := PackedByteArray()
var _drop := PackedByteArray()
var _slope := PackedByteArray()
var _pitched := PackedByteArray()
const HOUSE_NONE: int = 0
const HOUSE_GROUND: int = 1
const HOUSE_WALL: int = 2
const HOUSE_ROOF: int = 3
const FRAGMENT_OF: int = 90
var _house := PackedByteArray()
var _houses: Array = []
var _house_covered := PackedByteArray()
var _house_over: Dictionary = {}
var _house_done: Dictionary = {}
var _house_plans: Dictionary = {}
var _void := PackedByteArray()
var _margin_left := PackedByteArray()
var _margin_right := PackedByteArray()
var _heights := PackedInt32Array()
var _volume := PackedByteArray()
var _cliff := PackedByteArray()
var _front := PackedByteArray()
var _lip := PackedByteArray()
const FENCE_ACROSS: int = 1
const FENCE_AWAY: int = 2
var _fence_arms := PackedByteArray()
var _fence_done: Dictionary = {}
var _fence_mask := PackedByteArray()
var _fence_tall: int = 0
var _fence_wide: int = 0
var _fence_tiles: Array = []
var _shelf := PackedByteArray()
var _ramp := PackedByteArray()
var _corners := PackedInt32Array()
var _doorway := PackedByteArray()
var _bases := PackedInt32Array()
const LEDGE_NONE: int = 0
const LEDGE_SOUTH: int = 1
const LEDGE_NORTH: int = 2
const LEDGE_EAST: int = 4
const LEDGE_WEST: int = 8
const LEDGE_RISE: int = BAND
var _ledge := PackedByteArray()


func build(
	source: RefCounted, shape: RefCounted, atlas: RefCounted, window: Rect2i = Rect2i()
) -> Array:
	resolve(source, shape)
	return emit(atlas, window)


func emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> Array:
	if not begin_emit(atlas, window):
		return []
	while not emit_step(0):
		pass
	return take_chunks()

const CHUNK_TILES: int = 16

const MODEL_CHUNK_TILES: int = CHUNK_TILES

const CACHE_MARGIN_CHUNKS: int = 2

var _emit_atlas: RefCounted = null
var _chunks: Array[Rect2i] = []
var _chunk_keys: Array[Vector2i] = []
var _chunk_at: int = 0
var _chunk_cursor := Vector2i.ZERO
var _ready: Array = []
var _water_ready: Array = []
var _tuft_ready: Array = []

var _chunk_cache: Dictionary = {}
var _emitted := Rect2i()
var _chunk_houses := PackedInt32Array()
var _chunk_objects := PackedInt32Array()
var _chunk_stairs := PackedInt32Array()
var _chunk_fences := PackedInt32Array()
var _chunk_skirt_fences: Array = []
var _chunk_spots: Array = []
var _chunk_shared: bool = false
var _selected: Dictionary = {}
var _structure_owner: Dictionary = {}


func begin_emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> bool:
	_emit_atlas = null
	_chunks = []
	_chunk_keys = []
	_chunk_at = 0
	_ready = []
	_water_ready = []
	_tuft_ready = []
	if _size == Vector2i.ZERO:
		return false
	var reach: int = maxi(BORDER_TILES - _margin.x, 0) if _outside else 0
	var box := Rect2i(-Vector2i(reach, reach), _size + Vector2i(reach, reach) * 2)
	var view := box
	if window.size.x > 0 and window.size.y > 0:
		view = box.intersection(Rect2i(window.position + _margin, window.size))
	if view.size.x <= 0 or view.size.y <= 0:
		return false
	_emit_atlas = atlas
	for key: String in _model_spots:
		_model_spots[key] = {}
	_object_done.clear()
	_house_done.clear()
	_stair_done.clear()
	_fence_done.clear()
	_skirt_fence_done.clear()
	_built_model = false
	var first := Vector2i(
		floori(float(view.position.x) / CHUNK_TILES),
		floori(float(view.position.y) / CHUNK_TILES)
	)
	var last := Vector2i(
		floori(float(view.end.x - 1) / CHUNK_TILES),
		floori(float(view.end.y - 1) / CHUNK_TILES)
	)
	_selected = {}
	_emitted = Rect2i()
	for cy: int in range(first.y, last.y + 1):
		for cx: int in range(first.x, last.x + 1):
			var at := Vector2i(cx, cy)
			var chunk := Rect2i(
				at * CHUNK_TILES, Vector2i(CHUNK_TILES, CHUNK_TILES)
			).intersection(box)
			if chunk.size.x <= 0 or chunk.size.y <= 0:
				continue
			_selected[at] = true
			_emitted = chunk if _emitted.size == Vector2i.ZERO else _emitted.merge(chunk)
			if _reusable(at, chunk):
				_reuse(at)
				continue
			_chunks.append(chunk)
			_chunk_keys.append(at)
	_forget_chunks(_selected)
	if _chunks.is_empty():
		return not _ready.is_empty() or not _water_ready.is_empty() \
			or not _tuft_ready.is_empty()
	_open_chunk()
	return true


func _owned_here(key: String) -> bool:
	var mine: Vector2i = _chunk_keys[_chunk_at]
	if not _structure_owner.has(key):
		_structure_owner[key] = mine
		return true
	if _structure_owner[key] == mine:
		return true
	_chunk_shared = true
	return not _selected.has(_structure_owner[key])


func _reusable(at: Vector2i, chunk: Rect2i) -> bool:
	if not _chunk_cache.has(at):
		return false
	var held: Dictionary = _chunk_cache[at]
	if held["rect"] != chunk:
		return false
	return _inside_ring(chunk, held["ring_at"], held["ring_reach"]) \
		and _inside_ring(chunk, _ring_at, _ring_reach)


func _inside_ring(chunk: Rect2i, centre: Vector3, reach: float) -> bool:
	if reach <= 0.0:
		return true
	var here := Vector2(centre.x, centre.z)
	for corner: Vector2i in [
		chunk.position, Vector2i(chunk.end.x, chunk.position.y),
		Vector2i(chunk.position.x, chunk.end.y), chunk.end,
	]:
		if Vector2(_world_x(corner.x), _world_z(corner.y)).distance_to(here) >= reach:
			return false
	return true


func _reuse(at: Vector2i) -> void:
	var held: Dictionary = _chunk_cache[at]
	if held["terrain"] != null:
		_ready.append(held["terrain"])
	if held["water"] != null:
		_water_ready.append(held["water"])
	if held["tufts"] != null:
		_tuft_ready.append(held["tufts"])
	for index: int in held["houses"] as PackedInt32Array:
		_house_done[index] = true
	for index: int in held["objects"] as PackedInt32Array:
		_object_done[index] = true
	for index: int in held["stairs"] as PackedInt32Array:
		_stair_done[index] = true
	for cell: int in held["fences"] as PackedInt32Array:
		_fence_done[cell] = true
	for cell: Vector2i in held["skirt_fences"] as Array:
		_skirt_fence_done[cell] = true
	for spot: Array in held["spots"] as Array:
		(_model_spots[spot[0]] as Dictionary)[spot[1]] = spot[2]


func _forget_chunks(wanted: Dictionary) -> void:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for at: Vector2i in wanted:
		low = low.min(at)
		high = high.max(at)
	low -= Vector2i(CACHE_MARGIN_CHUNKS, CACHE_MARGIN_CHUNKS)
	high += Vector2i(CACHE_MARGIN_CHUNKS, CACHE_MARGIN_CHUNKS)
	for at: Vector2i in _chunk_cache.keys():
		if at.x < low.x or at.y < low.y or at.x > high.x or at.y > high.y:
			_chunk_cache.erase(at)


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
				done_tiles += 1
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


func take_chunks() -> Array:
	var out: Array = _ready
	_ready = []
	return out


func bank_field() -> ImageTexture:
	return _bank


func bank_world() -> Vector2:
	return Vector2(_size) * TILE


func bank_origin() -> Vector2:
	return Vector2(_margin) * TILE


func bank_span() -> float:
	return float(BANK_SPAN)


func _measure_bank() -> void:
	_bank = null
	var count: int = _size.x * _size.y
	if not _outside or count <= 0:
		return
	var field := PackedByteArray()
	field.resize(count)
	var queue := PackedInt32Array()
	var wet: bool = false
	for at: int in count:
		if _is_water(at):
			field[at] = BANK_SPAN
			wet = true
		else:
			field[at] = 0
			queue.push_back(at)
	if not wet:
		return
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		var next: int = int(field[at]) + 1
		if next > BANK_SPAN:
			continue
		@warning_ignore("integer_division")
		var y: int = at / _size.x
		var x: int = at - y * _size.x
		if x > 0 and int(field[at - 1]) > next:
			field[at - 1] = next
			queue.push_back(at - 1)
		if x < _size.x - 1 and int(field[at + 1]) > next:
			field[at + 1] = next
			queue.push_back(at + 1)
		if y > 0 and int(field[at - _size.x]) > next:
			field[at - _size.x] = next
			queue.push_back(at - _size.x)
		if y < _size.y - 1 and int(field[at + _size.x]) > next:
			field[at + _size.x] = next
			queue.push_back(at + _size.x)
	for at: int in count:
		field[at] = int(round(float(field[at]) / float(BANK_SPAN) * 255.0))
	_bank = ImageTexture.create_from_image(
		Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_R8, field)
	)


func take_water() -> Array:
	var out: Array = _water_ready
	_water_ready = []
	return out


func take_tufts() -> Array:
	var out: Array = _tuft_ready
	_tuft_ready = []
	return out


func _open_chunk() -> void:
	_chunk_cursor = _chunks[_chunk_at].position
	_chunk_houses = PackedInt32Array()
	_chunk_objects = PackedInt32Array()
	_chunk_stairs = PackedInt32Array()
	_chunk_fences = PackedInt32Array()
	_chunk_skirt_fences = []
	_chunk_spots = []
	_chunk_shared = false
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


func _close_chunk() -> void:
	var terrain: ArrayMesh = _mesh_of(_vertices, _normals, _uvs, _colors) \
		if not _vertices.is_empty() else null
	var water: ArrayMesh = _mesh_of(
		_water_vertices, _water_normals, _water_uvs, _water_colors
	) if not _water_vertices.is_empty() else null
	var tufts: ArrayMesh = _mesh_of(
		_tuft_vertices, _tuft_normals, _tuft_uvs, _tuft_colors, _tuft_uv2s
	) if not _tuft_vertices.is_empty() else null
	if terrain != null:
		_ready.append(terrain)
	if water != null:
		_water_ready.append(water)
	if tufts != null:
		_tuft_ready.append(tufts)
	if _chunk_shared:
		_chunk_cache.erase(_chunk_keys[_chunk_at])
		return
	_chunk_cache[_chunk_keys[_chunk_at]] = {
		"rect": _chunks[_chunk_at],
		"terrain": terrain, "water": water, "tufts": tufts,
		"houses": _chunk_houses, "objects": _chunk_objects,
		"stairs": _chunk_stairs, "fences": _chunk_fences,
		"skirt_fences": _chunk_skirt_fences, "spots": _chunk_spots,
		"ring_at": _ring_at, "ring_reach": _ring_reach,
	}


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


func emitted_bounds_tiles() -> Rect2i:
	if _emitted.size == Vector2i.ZERO:
		return Rect2i()
	return Rect2i(_emitted.position - _margin, _emitted.size)


func stamped_bounds_tiles() -> Rect2i:
	if _size == Vector2i.ZERO:
		return Rect2i()
	return Rect2i(-_margin, _size)


func drawn_bounds_tiles() -> Rect2i:
	if _size == Vector2i.ZERO:
		return Rect2i()
	var reach := Vector2i(_skirt_reach(), _skirt_reach())
	return Rect2i(-(_margin + reach), _size + reach * 2)


func _world_x(tx: int) -> float:
	return float(tx - _margin.x) * TILE


func _world_z(ty: int) -> float:
	return float(ty - _margin.y) * TILE


## The four-neighbourhood, in the order the passes below walk it.
const STEPS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
]
## `_pond_shore` answers differently by the order it meets the ground, so its own
## order is pinned here rather than shared. See that function.
const POND_STEPS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
]


## A grid index, or -1 off the grid. Every lookup goes through here so no pass
## carries its own bounds test.
func _index(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return -1
	return ty * _size.x + tx


func _index_of(tile: Vector2i) -> int:
	return _index(tile.x, tile.y)


func _tile_of(at: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(at % _size.x, at / _size.x)


## The in-grid four-neighbours of a tile.
func _neighbours(at: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var from: Vector2i = _tile_of(at)
	for step: Vector2i in STEPS:
		var index: int = _index(from.x + step.x, from.y + step.y)
		if index >= 0:
			out.append(index)
	return out


## Every tile reachable from `start` through `accept`, marking `seen` as it goes.
func _spread(start: int, seen: PackedByteArray, accept: Callable) -> PackedInt32Array:
	var region := PackedInt32Array()
	seen[start] = 1
	region.append(start)
	var walked: int = 0
	while walked < region.size():
		for index: int in _neighbours(region[walked]):
			if seen[index] == 0 and accept.call(index):
				seen[index] = 1
				region.append(index)
		walked += 1
	return region


func grid_index(map_tile: Vector2i) -> int:
	return _index_of(map_tile + _margin)


func _margin_cells() -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(_margin.x / CELL_TILES, _margin.y / CELL_TILES)


func _tile_fact(shape: RefCounted, tile: int, permission: int) -> Array:
	var shape_class: StringName = shape.at(tile, permission)
	if not _class_ids.has(shape_class):
		_class_ids[shape_class] = _class_ids.size()
	var fact: Array = []
	fact.resize(FACT_SWAYS + 1)
	fact[FACT_KLASS] = int(_class_ids[shape_class])
	fact[FACT_ART] = _art_mode(shape.art(shape_class))
	fact[FACT_DEPTH] = clampi(shape.depth(shape_class), 1, 16)
	fact[FACT_OUTLINED] = shape.outline_shades(shape_class)
	fact[FACT_STRETCH] = shape.model_stretch(shape_class)
	fact[FACT_DROP] = shape.roof_drop(shape_class)
	var span: Vector2i = shape.span_cells(shape_class)
	fact[FACT_SPAN_X] = maxi(span.x, 1)
	fact[FACT_SPAN_Y] = maxi(span.y, 1)
	fact[FACT_ROUND] = int(shape.is_round(shape_class))
	fact[FACT_FILLED] = int(shape.is_filled(shape_class))
	fact[FACT_MODELLED] = int(shape.is_model(shape_class))
	fact[FACT_SHRUB] = int(shape.is_shrub(shape_class))
	fact[FACT_ROCK] = int(shape.is_rock(shape_class))
	fact[FACT_POTTED] = int(shape.is_potted(shape_class))
	fact[FACT_COLUMN] = int(shape.is_column(shape_class))
	fact[FACT_TUFTED] = int(shape.is_tufted(shape_class))
	fact[FACT_SWAYS] = int(shape.is_swaying(shape_class))
	fact[FACT_LYING] = int(shape.is_lying(shape_class))
	fact[FACT_ON_FURNITURE] = int(shape_class == &"on_furniture")
	fact[FACT_VOID] = int(shape_class == &"void")
	_fact_stem(fact, shape, shape_class)
	_fact_building(fact, shape, shape_class, tile)
	_fact_cliff(fact, shape, shape_class, tile)
	return fact


## A stem is kept once and named by index, since one drawing's stem serves every
## placement of it. Index 0 means none, so the stored index is one-based.
func _fact_stem(fact: Array, shape: RefCounted, shape_class: StringName) -> void:
	var stem: Array = shape.stem_rows(shape_class)
	if stem.is_empty():
		fact[FACT_STEM] = 0
		fact[FACT_STEM_RISE] = 0
		return
	var found: int = _stem_shapes.find(stem)
	if found < 0:
		found = _stem_shapes.size()
		_stem_shapes.append(stem)
	fact[FACT_STEM] = found + 1
	fact[FACT_STEM_RISE] = clampi(stem.size(), 0, 32)


func _fact_building(
	fact: Array, shape: RefCounted, shape_class: StringName, tile: int
) -> void:
	var part: int = PART_NONE
	match shape.building_part(shape_class):
		&"wall":
			part = PART_WALL
		&"roof":
			part = PART_ROOF
	var margin: Vector2i = Vector2i.ZERO
	var slope: int = 0
	if part == PART_WALL:
		margin = shape.facade_margin(tile)
		slope = int(shape.is_facade_slope(tile))
	fact[FACT_PART] = part
	fact[FACT_MARGIN_LEFT] = margin.x
	fact[FACT_MARGIN_RIGHT] = margin.y
	fact[FACT_SLOPE] = slope


## An unpinned volume's height is -1, which means measure it off the drawing.
func _fact_cliff(
	fact: Array, shape: RefCounted, shape_class: StringName, tile: int
) -> void:
	var is_volume: bool = fact[FACT_ART] == ART_UPRIGHT
	var on_face: bool = is_volume or fact[FACT_ART] == ART_TOP
	var cliff: int = int(on_face and shape.is_cliff(tile))
	fact[FACT_VOLUME] = int(is_volume)
	fact[FACT_CLIFF] = cliff
	fact[FACT_FRONT] = int(cliff == 1 and shape.is_cliff_front(tile))
	fact[FACT_LIP] = int(not is_volume and shape.is_cliff_lip(tile))
	fact[FACT_HEIGHT] = -1 if is_volume and not shape.is_pinned(tile) \
		else shape.height(shape_class)


## Tiles a slice of a banded pass answers, so one slice is the same size on a
## wide map as on a narrow one.
const BAND_TILES: int = 512

var _resolve_passes: Array[Callable] = []
var _resolve_at: int = 0


func resolve(source: RefCounted, shape: RefCounted) -> void:
	begin_resolve(source, shape)
	while not resolve_step(0):
		pass


## Sizing the grid comes first and whole, so `size_tiles` answers straight away.
func begin_resolve(source: RefCounted, shape: RefCounted) -> void:
	_forget()
	_resolve_passes = []
	_resolve_at = 0
	if source == null or not source.valid():
		return
	_outside = source.outside()
	_room_wall = [] if _outside else shape.room_wall()
	_ground_table = shape.ground_table()
	_size_grid(source, shape)
	_resolve_passes = _passes(source, shape)


## Runs whole passes until the budget is spent, and answers whether the map is
## measured. A budget of zero runs the lot.
func resolve_step(budget_usec: int) -> bool:
	var until: int = Time.get_ticks_usec() + budget_usec
	while _resolve_at < _resolve_passes.size():
		_resolve_passes[_resolve_at].call()
		_resolve_at += 1
		if budget_usec > 0 and Time.get_ticks_usec() >= until:
			break
	if _resolve_at < _resolve_passes.size():
		return false
	_resolve_passes = []
	return true


func _forget() -> void:
	_size = Vector2i.ZERO
	_edge_floor = Vector2i(-2, 0)
	_ground_table = {}
	for held: Variant in [
		_masks, _hulls, _facts, _border, _ground_by_id, _model_meshes,
		_model_spots, _model_bodies, _model_measures, _model_inputs,
		_model_cutouts, _chunk_cache, _structure_owner, _commonest_index
	]:
		held.clear()
	# `_house_plans` is not among them: a plan is read off the drawing alone and
	# every drawing has its own id, so it outlives the map it was first met on.


## The grid is the map plus the ring around it, each side grown on its own.
func _size_grid(source: RefCounted, shape: RefCounted) -> void:
	var ring: int = _ring_depth(source, shape) if _outside \
		else (ROOM_RING if not _room_wall.is_empty() else 0)
	_map_size = source.size_cells() * RomLayout.MAP_BLOCK_CELL_WIDTH
	_margin = Vector2i(
		_ring_side(source, shape, ring, Vector2i(-1, 0)),
		_ring_side(source, shape, ring, Vector2i(0, -1))
	)
	_margin_far = Vector2i(
		_ring_side(source, shape, ring, Vector2i(1, 0)),
		_ring_side(source, shape, ring, Vector2i(0, 1))
	)
	_size = _map_size + _margin + _margin_far
	_map_end = _margin + _map_size
	var count: int = _size.x * _size.y
	for band: Variant in [
		_tiles, _art, _depths, _round, _filled, _stem, _stem_rise, _outlined,
		_modelled, _shrub, _rock, _potted, _column, _stretch, _tufted,
		_long_grass, _swaying, _span_x, _span_y, _span_cut, _lying,
		_on_furniture, _klass, _part, _drop, _slope, _pitched, _void,
		_margin_left, _margin_right, _heights, _volume, _cliff, _front, _lip,
		_bases
	]:
		band.resize(count)
	_ledge.resize(count)
	_ledge.fill(LEDGE_NONE)
	for cleared: Variant in [_shelf, _doorway, _room]:
		cleared.resize(count)
		cleared.fill(0)


## A shell tile stands outside the map and wears the room's own wall. Marked in
## one pass so the fill after it tests a byte rather than four bounds a tile.
func _mark_shell() -> void:
	_room.fill(0)
	if _room_wall.is_empty():
		return
	for ty: int in _size.y:
		for tx: int in _size.x:
			if (
				tx < _margin.x or ty < _margin.y
				or tx >= _map_end.x or ty >= _map_end.y
			):
				_room[ty * _size.x + tx] = ROOM_SHELL


func _fill_row(source: RefCounted, shape: RefCounted, ty: int) -> void:
	var cell_y: int = (ty - _margin.y) >> 1
	for tx: int in _size.x:
		var at: int = ty * _size.x + tx
		var shell: bool = _room[at] == ROOM_SHELL
		var tile: int = _room_wall_tile(tx, ty) if shell \
			else source.tile_at(tx - _margin.x, ty - _margin.y)
		_tiles[at] = tile
		_bases[at] = ty
		_cliff[at] = 0
		_front[at] = 0
		_lip[at] = 0
		if tile < 0:
			_blank_tile(at)
			continue
		var cell := Vector2i((tx - _margin.x) >> 1, cell_y)
		var permission: int = -1 if shell else source.permission_at(cell)
		var key: int = tile * FACT_STRIDE + permission + 1
		var fact: Array = _facts.get(key, [])
		if fact.is_empty():
			fact = _tile_fact(shape, tile, permission)
			_facts[key] = fact
		_art[at] = fact[FACT_ART]
		_depths[at] = fact[FACT_DEPTH]
		_round[at] = fact[FACT_ROUND]
		_filled[at] = fact[FACT_FILLED]
		_stem[at] = fact[FACT_STEM]
		_stem_rise[at] = fact[FACT_STEM_RISE]
		_outlined[at] = fact[FACT_OUTLINED]
		_modelled[at] = fact[FACT_MODELLED]
		_shrub[at] = fact[FACT_SHRUB]
		_rock[at] = fact[FACT_ROCK]
		_potted[at] = fact[FACT_POTTED]
		_column[at] = fact[FACT_COLUMN]
		_stretch[at] = fact[FACT_STRETCH]
		_swaying[at] = fact[FACT_SWAYS]
		_lying[at] = fact[FACT_LYING]
		_on_furniture[at] = fact[FACT_ON_FURNITURE]
		_span_x[at] = fact[FACT_SPAN_X]
		_span_y[at] = fact[FACT_SPAN_Y]
		_span_cut[at] = 0
		_klass[at] = fact[FACT_KLASS]
		_part[at] = fact[FACT_PART]
		_drop[at] = fact[FACT_DROP]
		_slope[at] = fact[FACT_SLOPE]
		_void[at] = fact[FACT_VOID]
		_margin_left[at] = fact[FACT_MARGIN_LEFT]
		_margin_right[at] = fact[FACT_MARGIN_RIGHT]
		_volume[at] = fact[FACT_VOLUME]
		_cliff[at] = fact[FACT_CLIFF]
		_front[at] = fact[FACT_FRONT]
		_lip[at] = fact[FACT_LIP]
		_heights[at] = fact[FACT_HEIGHT]
		var grass: int = source.code_at(cell)
		_tufted[at] = int(
			fact[FACT_TUFTED] == 1 or Gen2WorldCollision.is_grass(grass)
		)
		_long_grass[at] = int(Gen2WorldCollision.is_long_grass(grass))


func _blank_tile(at: int) -> void:
	_heights[at] = 0
	_volume[at] = 0
	_art[at] = ART_FLAT
	_part[at] = PART_NONE


## Every pass, in the order each depends on the last. One is the unit a slice
## stops on, so the longest of them is the longest frame a resolve can cost.
func _passes(source: RefCounted, shape: RefCounted) -> Array[Callable]:
	var passes: Array[Callable] = [_mark_shell]
	_band_rows(passes, _fill_rows.bind(source, shape))
	passes.append_array([
		_match_map_houses.bind(source, shape),
		_measure_columns,
		_measure_cliffs,
		_apply_levels.bind(source),
		_measure_plateaus,
		_settle_ponds,
		_settle_beds,
		_measure_buildings,
		_settle_void,
		_settle_unmeasured,
		_measure_room,
		_measure_room_fill,
		_measure_furniture,
	])
	_band_rows(passes, _measure_cutouts)
	passes.append_array([
		_measure_objects.bind(shape, source),
		_settle_aprons,
		_measure_room_behind,
		_measure_house_boxes.bind(source),
		_settle_house_ground,
		_measure_stairs.bind(shape),
		_measure_ledges.bind(source),
		_measure_fences.bind(shape),
		_measure_mouths,
		_measure_ramps,
		_measure_mounds.bind(shape),
		_measure_doors.bind(shape),
	])
	_band(passes, _measure_collision_doors.bind(source))
	passes.append_array([
		_measure_shores,
		_measure_surfaces,
		_measure_bank,
	])
	return passes


## A pass whose rows are answered in order is spent a band of rows at a time.
## The band comes first in its signature, since a bound argument lands after it.
func _band_rows(passes: Array[Callable], over: Callable) -> void:
	var rows: int = maxi(BAND_TILES / maxi(_size.x, 1), 1)
	for from: int in range(0, _size.y, rows):
		passes.append(over.bind(from, mini(from + rows, _size.y)))


## The same for a pass that walks the grid by index rather than by row.
func _band(passes: Array[Callable], over: Callable) -> void:
	var count: int = _size.x * _size.y
	for from: int in range(0, count, BAND_TILES):
		passes.append(over.bind(from, mini(from + BAND_TILES, count)))


func _fill_rows(from: int, to: int, source: RefCounted, shape: RefCounted) -> void:
	for ty: int in range(from, to):
		_fill_row(source, shape, ty)


func _match_map_houses(source: RefCounted, shape: RefCounted) -> void:
	var painted_map: Gen2WorldMap = source.map()
	if painted_map != null:
		_match_houses(shape, painted_map.tileset)


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
				_heights[at] = height if _heights[at] >= 0 else _heights[at] + height
			elif _heights[at] >= 0:
				_heights[at] += height


func _match_houses(shape: RefCounted, tileset_number: int) -> void:
	var count: int = _size.x * _size.y
	_house.resize(count)
	_house.fill(HOUSE_NONE)
	_houses.clear()
	var painted: Array = Houses.of_tileset(tileset_number)
	# Largest drawing first, so a big house claims before a piece of it can.
	painted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["tiles"] as Array).size() * ((a["tiles"][0] as Array).size()) \
			> (b["tiles"] as Array).size() * ((b["tiles"][0] as Array).size()))
	var found: Array = []
	var offered: Array = []
	var where: Dictionary = _tile_spots()
	for house: Dictionary in painted:
		_offer_house(house, where, found, offered)
	_drop_overlapping(offered)
	var claims: Dictionary = _claim_houses(offered)
	for index: int in found.size():
		_paint_house(shape, found[index], index, claims)


## Every grid position each tile id sits at, so a pattern is looked for from its
## anchor rather than from every tile of the map.
func _tile_spots() -> Dictionary:
	var where: Dictionary = {}
	for at: int in _size.x * _size.y:
		var tile: int = maxi(_tiles[at], 0)
		if not where.has(tile):
			where[tile] = []
		(where[tile] as Array).append(at)
	return where


func _offer_house(
	house: Dictionary, where: Dictionary, found: Array, offered: Array
) -> void:
	var pattern: Array = house["tiles"]
	var across := Vector2i((pattern[0] as Array).size(), pattern.size())
	if across.x > _size.x or across.y > _size.y:
		return
	var anchor: Vector3i = _pattern_anchor(pattern, across, where)
	for spot: int in where.get(anchor.z, []) as Array:
		var tile: Vector2i = _tile_of(spot) - Vector2i(anchor.x, anchor.y)
		if tile.x < 0 or tile.y < 0 \
				or tile.x > _size.x - across.x or tile.y > _size.y - across.y:
			continue
		if not _pattern_at(pattern, across, tile.x, tile.y):
			continue
		var plans: Array = _house_plan(house)
		found.append([house, tile, across, plans])
		for index: int in plans.size():
			var rect: Rect2i = _house_tile_rect(plans[index], across)
			rect.position += tile
			offered.append([
				rect.size.x * rect.size.y, found.size() - 1, index, rect, 0
			])


## A box mostly inside a bigger box belonging to another placement is a piece of
## that one seen twice, and is struck out.
func _drop_overlapping(offered: Array) -> void:
	for offer: Array in offered:
		for other: Array in offered:
			if other[1] == offer[1] or other[0] <= offer[0]:
				continue
			if (offer[3] as Rect2i).intersection(other[3] as Rect2i).get_area() \
					* 100 >= offer[0] * FRAGMENT_OF:
				offer[4] = 1
				break


func _claim_houses(offered: Array) -> Dictionary:
	var claims: Dictionary = {}
	for offer: Array in offered:
		if offer[4] == 1 or _house_claimed(offer[3] as Rect2i):
			continue
		var rect: Rect2i = offer[3]
		var mine: PackedInt32Array = claims.get(offer[1], PackedInt32Array())
		mine.append(offer[2])
		claims[offer[1]] = mine
		for row: int in rect.size.y:
			for column: int in rect.size.x:
				_house[(rect.position.y + row) * _size.x
					+ rect.position.x + column] = HOUSE_WALL
	return claims


## A placement with boxes is kept as boxes; one without is painted per tile.
func _paint_house(
	shape: RefCounted, place: Array, index: int, claims: Dictionary
) -> void:
	var house: Dictionary = place[0]
	var start: Vector2i = place[1]
	var across: Vector2i = place[2]
	if not (place[3] as Array).is_empty():
		if claims.has(index):
			_houses.append([house, start, across, [], claims[index]])
		return
	var paint: Array = house["paint"]
	for row: int in across.y:
		for column: int in across.x:
			var at: int = (start.y + row) * _size.x + start.x + column
			var stroke: String = _house_word(paint, row, column)
			if stroke == "":
				continue
			if stroke == Houses.NONE:
				if _part[at] == PART_NONE:
					continue
				_house[at] = HOUSE_GROUND
			elif stroke == Houses.ROOF:
				_house[at] = HOUSE_ROOF
			else:
				_house[at] = HOUSE_WALL
			_house_tile(shape, at, stroke)


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


func _house_body_mask(plans: Array, across: Vector2i) -> PackedByteArray:
	var stood := PackedByteArray()
	stood.resize(across.x * across.y)
	for plan: Dictionary in plans:
		if int(plan.get("right", -1)) < 0:
			continue
		@warning_ignore("integer_division")
		var first := Vector2i(
			int(plan["cover_left"]) / TILE_PX, int(plan["north_row"]) / TILE_PX
		)
		@warning_ignore("integer_division")
		var last := Vector2i(
			int(plan["cover_right"]) / TILE_PX, int(plan["south_row"]) / TILE_PX
		)
		for row: int in range(maxi(first.y, 0), mini(last.y, across.y - 1) + 1):
			for column: int in range(maxi(first.x, 0), mini(last.x, across.x - 1) + 1):
				stood[row * across.x + column] = 1
	return stood


func _measure_house_boxes(source: RefCounted) -> void:
	_house_covered.resize(_size.x * _size.y)
	_house_covered.fill(0)
	_house_over.clear()
	_house_open.clear()
	_house_ground.clear()
	_released_ground.clear()
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
		var floors := PackedInt32Array()
		for row: int in across.y:
			for column: int in across.x:
				floors.append(_cell_floor((start.x + column) >> 1, (start.y + row) >> 1))
		if _house_inside_object(start, across):
			continue
		var chosen: Array = _house_chosen(entry)
		var footprint: PackedByteArray = _house_footprint(chosen, across)
		var stood: PackedByteArray = _house_body_mask(chosen, across)
		for row: int in across.y:
			for column: int in across.x:
				if footprint[row * across.x + column] == 0:
					continue
				var at: int = (start.y + row) * _size.x + start.x + column
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
				if stood[row * across.x + column] == 0:
					_house_open[at] = Vector2i(start.x, start.x + across.x)


func _house_inside_object(start: Vector2i, across: Vector2i) -> bool:
	if _object_covered.is_empty():
		return false
	for row: int in across.y:
		for column: int in across.x:
			var at: int = (start.y + row) * _size.x + start.x + column
			if at < 0 or at >= _object_covered.size() or _object_covered[at] == 0:
				return false
	return true

var _house_open: Dictionary = {}
var _house_ground: Dictionary = {}
var _released_ground: Dictionary = {}


func _settle_house_ground() -> void:
	for at: int in _house_open:
		var span: Vector2i = _house_open[at]
		@warning_ignore("integer_division")
		var ty: int = at / _size.x
		var found := Vector2i(-1, 0)
		for step: int in range(1, _size.x):
			var reached: bool = false
			for way: int in [-1, 1]:
				var at_x: int = (span.x - step) if way < 0 else (span.y - 1 + step)
				if at_x < 0 or at_x >= _size.x:
					continue
				reached = true
				var index: int = ty * _size.x + at_x
				if _art[index] == ART_FLAT and _tiles[index] >= 0:
					found = Vector2i(_tiles[index], _heights[index])
					break
			if found.x >= 0 or not reached:
				break
		if found.x < 0:
			continue
		_house_ground[at] = found
		_heights[at] = found.y


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


func _house_tile(shape: RefCounted, at: int, stroke: String) -> void:
	var painted: StringName = &"roof"
	if stroke == Houses.WALL or stroke == Houses.FRONT:
		painted = &"facade"
	elif stroke == Houses.NONE:
		painted = &"ground"
	_art[at] = _art_mode(shape.art(painted))
	_depths[at] = clampi(shape.depth(painted), 1, 16)
	_heights[at] = shape.height(painted)
	_volume[at] = int(_art[at] == ART_UPRIGHT)
	match painted:
		&"facade":
			_part[at] = PART_WALL
		&"roof":
			_part[at] = PART_ROOF
		_:
			_part[at] = PART_NONE
	_slope[at] = int(stroke == Houses.FRONT)
	_round[at] = 0
	_filled[at] = 0
	_stem[at] = 0
	_stem_rise[at] = 0
	_outlined[at] = 0
	_modelled[at] = 0
	_shrub[at] = 0
	_rock[at] = 0
	_potted[at] = 0
	_column[at] = 0
	_tufted[at] = 0
	_long_grass[at] = 0
	_swaying[at] = 0
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
		&"ball":
			return ART_BALL
		_:
			return ART_FLAT


func _measure_columns() -> void:
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	var region := _regions(cells)

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
					if _heights[at] == -1:
						_heights[at] = height
						_bases[at] = base


func _fence(
	tx: int, ty: int, ground: float, atlas: RefCounted, arms: int = -1
) -> void:
	if _fence_mask.is_empty():
		_fence_profile(atlas)
	if _fence_mask.is_empty():
		return
	if arms < 0:
		arms = int(_fence_arms[ty * _size.x + tx])
	var cell := Vector2i((tx - _margin.x) >> 1, (ty - _margin.y) >> 1)
	var middle := Vector2(
		_world_x(_margin.x + cell.x * CELL_TILES) + TILE,
		_world_z(_margin.y + cell.y * CELL_TILES) + TILE
	)
	if arms & FENCE_ACROSS:
		_fence_arm(middle, ground, true, atlas)
	if arms & FENCE_AWAY:
		_fence_arm(middle, ground, false, atlas)


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
				var cap: bool = _fence_open(px, run, py - 1, py)
				var west: bool = px == 0 or _fence_open(px - 1, px, py, py + deep)
				var east: bool = run == _fence_wide or _fence_open(run, run + 1, py, py + deep)
				_fence_box(box, atlas.uv_box(tile, sub),
					atlas.uv_box(tile, Rect2i(sub.position, Vector2i.ONE)),
					across, cap, west, east)
				px = run


func _fence_open(from_x: int, to_x: int, from_y: int, to_y: int) -> bool:
	for py: int in range(from_y, to_y):
		if py < 0 or py >= _fence_tall:
			return true
		for px: int in range(from_x, to_x):
			if px < 0 or px >= _fence_wide or _fence_mask[py * _fence_wide + px] == 0:
				return true
	return false


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


func _measure_fences(shape: RefCounted) -> void:
	_fence_tiles = shape.fence_face()
	_fence_mask = PackedByteArray()
	_fence_arms.resize(_size.x * _size.y)
	_fence_arms.fill(0)
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	var here: PackedByteArray = _fence_cells(cells)
	if here.is_empty():
		return
	for cell_y: int in cells.y:
		for cell_x: int in cells.x:
			if here[cell_y * cells.x + cell_x] == 1:
				_arm_fence_cell(cells, here, cell_x, cell_y)


## Which walk cells carry a fence at all, so a run is read cell by cell.
func _fence_cells(cells: Vector2i) -> PackedByteArray:
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
	return here if any else PackedByteArray()


## A fence cell runs the way its neighbours lie. A cell standing alone runs
## across, since a post on its own is drawn face-on.
## A fence cell runs the way its neighbours lie. A cell standing alone runs
## across, since a post on its own is drawn face-on.
func _arm_fence_cell(
	cells: Vector2i, here: PackedByteArray, cell_x: int, cell_y: int
) -> void:
	var arms: int = 0
	if _fence_beside(cells, here, cell_x, cell_y, Vector2i(1, 0)):
		arms |= FENCE_ACROSS
	if _fence_beside(cells, here, cell_x, cell_y, Vector2i(0, 1)):
		arms |= FENCE_AWAY
	if arms == 0:
		arms = FENCE_ACROSS
	for row: int in CELL_TILES:
		for column: int in CELL_TILES:
			var at: int = (cell_y * CELL_TILES + row) * _size.x \
				+ cell_x * CELL_TILES + column
			if _art[at] != ART_FENCE:
				continue
			_fence_arms[at] = arms
			_heights[at] = 0
			_volume[at] = 0


## Whether another fence cell lies either way along one axis.
func _fence_beside(
	cells: Vector2i, here: PackedByteArray, cell_x: int, cell_y: int,
	axis: Vector2i
) -> bool:
	for way: int in [-1, 1]:
		var to := Vector2i(cell_x + axis.x * way, cell_y + axis.y * way)
		if to.x < 0 or to.y < 0 or to.x >= cells.x or to.y >= cells.y:
			continue
		if here[to.y * cells.x + to.x] == 1:
			return true
	return false


func _fence_profile(atlas: RefCounted) -> void:
	_fence_mask = PackedByteArray()
	_fence_tall = 0
	if _fence_tiles.size() < 2:
		return
	_fence_wide = (_fence_tiles[0] as Array).size() * TILE_PX
	var rows: int = _fence_tiles.size() * TILE_PX
	var dark: PackedByteArray = _fence_dark(atlas, rows)
	var foot: int = _last_dark_row(dark, rows)
	if foot < 0:
		return
	_fence_tall = foot + 1
	var mask: PackedByteArray = _fence_cut(dark)
	# Nothing hangs below a column's own lowest dark pixel: a fence stands on the
	# ground rather than trailing the background under it.
	for px: int in _fence_wide:
		var foot_row: int = -1
		for py: int in _fence_tall:
			if dark[py * _fence_wide + px] == 1:
				foot_row = py
		for py: int in range(foot_row + 1, _fence_tall):
			mask[py * _fence_wide + px] = 0
	_fence_mask = mask


## The fence cut out of its background, flooded from the TOP ROW alone: a fence
## is open to the sky above it and stands on the ground at its foot.
func _fence_cut(dark: PackedByteArray) -> PackedByteArray:
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
	return mask


func _fence_dark(atlas: RefCounted, rows: int) -> PackedByteArray:
	var dark := PackedByteArray()
	dark.resize(_fence_wide * rows)
	for py: int in rows:
		for px: int in _fence_wide:
			var tile: int = _profile_tile(px, py)
			var index: int = atlas.pixel(tile, px % TILE_PX, py % TILE_PX)
			if atlas.is_dark(tile, index, 1):
				dark[py * _fence_wide + px] = 1
	return dark


func _last_dark_row(dark: PackedByteArray, rows: int) -> int:
	var foot: int = -1
	for py: int in rows:
		for px: int in _fence_wide:
			if dark[py * _fence_wide + px] == 1:
				foot = py
	return foot


func _profile_tile(px: int, py: int) -> int:
	@warning_ignore("integer_division")
	var row: Array = _fence_tiles[py / TILE_PX] as Array
	@warning_ignore("integer_division")
	return int(row[px / TILE_PX])


func _measure_ramps() -> void:
	var count: int = _size.x * _size.y
	_ramp.resize(count)
	_ramp.fill(0)
	_corners.resize(count * 4)
	for at: int in count:
		for corner: int in 4:
			_corners[at * 4 + corner] = _heights[at]
	var distance: PackedInt32Array = _shelf_depths()
	for at: int in count:
		if distance[at] >= 0:
			_slope_shelf(at, distance)


## How many tiles in from its own lip each shelf tile lies, by breadth. A lip is
## a shelf tile with lower ground beside it inside the map.
func _shelf_depths() -> PackedInt32Array:
	var count: int = _size.x * _size.y
	var distance := PackedInt32Array()
	distance.resize(count)
	distance.fill(-1)
	var stack := PackedInt32Array()
	for at: int in count:
		if _shelf[at] == 1 and _heights[at] > 0 and _on_shelf_lip(at):
			distance[at] = 1
			stack.append(at)
	var head: int = 0
	while head < stack.size():
		var at: int = stack[head]
		head += 1
		for index: int in _neighbours(at):
			if distance[index] < 0 and _shelf[index] == 1 and _heights[index] > 0:
				distance[index] = distance[at] + 1
				stack.append(index)
	return distance


func _on_shelf_lip(at: int) -> bool:
	var from: Vector2i = _tile_of(at)
	for step: Vector2i in STEPS:
		var to: Vector2i = from + step
		var index: int = _index_of(to)
		if index < 0 or not _in_map(to.x, to.y):
			continue
		if _shelf[index] == 0 and _heights[index] < _heights[at]:
			return true
	return false


## One shelf tile: each corner pulled down to the shallowest depth around it, so
## a shelf falls away as a slope rather than a step.
func _slope_shelf(at: int, distance: PackedInt32Array) -> void:
	var tile: Vector2i = _tile_of(at)
	var sloped: bool = false
	for corner: int in 4:
		var step := Vector2i(-1 if corner % 2 == 0 else 1, -1 if corner < 2 else 1)
		var near: int = distance[at]
		for reach: Vector2i in [Vector2i(step.x, 0), Vector2i(0, step.y), step]:
			near = _shelf_near(at, tile + reach, near, distance)
		var high: int = mini(near * BAND, _heights[at])
		_corners[at * 4 + corner] = high
		sloped = sloped or high < _heights[at]
	if sloped:
		_ramp[at] = 1
		_art[at] = ART_FLAT
		_volume[at] = 0


func _shelf_near(
	at: int, to: Vector2i, near: int, distance: PackedInt32Array
) -> int:
	var index: int = _index_of(to)
	if index < 0 or not _in_map(to.x, to.y):
		return near
	if _shelf[index] == 0:
		return 0 if _heights[index] < _heights[at] else near
	return mini(near, maxi(distance[index], 0))

func _in_map(tx: int, ty: int) -> bool:
	return (
		tx >= _margin.x and ty >= _margin.y
		and tx < _map_end.x and ty < _map_end.y
	)


func _commonest_water() -> int:
	var counts: Dictionary = {}
	var best: int = -1
	for at: int in _size.x * _size.y:
		if not _is_water(at):
			continue
		var tile: int = _tiles[at]
		counts[tile] = int(counts.get(tile, 0)) + 1
		if best < 0 or int(counts[tile]) > int(counts[best]):
			best = tile
	return best


func _measure_surfaces() -> void:
	_surface.resize(_size.x * _size.y)
	_surface.fill(NO_OBJECT)
	for entry: Array in _objects:
		var object: Dictionary = entry[0]
		var start: Vector2i = entry[1]
		var across: Vector2i = entry[2]
		var front: float = entry[3]
		var top: int = int(_object_base(object, start, across)) \
			+ int(object.get(&"height", 0))
		if top <= 0:
			continue
		if not object.has(&"depth"):
			for row: int in across.y:
				for column: int in across.x:
					var to := Vector2i(start.x + column, start.y + row)
					if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
						continue
					var covered: int = to.y * _size.x + to.x
					if _object_covered[covered] == 1:
						_surface[covered] = maxi(_surface[covered], top)
			continue
		var window: Rect2i = object[&"window"]
		var left: float = _world_x(start.x) + float(window.position.x)
		var box := Rect2(
			left, front - float(object[&"depth"]), float(window.size.x), float(object[&"depth"])
		)
		for ty: int in range(
			floori(box.position.y / TILE) + _margin.y,
			ceili(box.end.y / TILE) + _margin.y
		):
			if ty < 0 or ty >= _size.y:
				continue
			for tx: int in range(
				floori(box.position.x / TILE) + _margin.x,
				ceili(box.end.x / TILE) + _margin.x
			):
				if tx < 0 or tx >= _size.x:
					continue
				var at: int = ty * _size.x + tx
				_surface[at] = maxi(_surface[at], top)

const WATER_DRAUGHT: int = 2


func surface_height_at_position(position: Vector3) -> int:
	var tx: int = floori(position.x / TILE) + _margin.x
	var ty: int = floori(position.z / TILE) + _margin.y
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	var column: int = _height_at(tx, ty)
	var object: int = _surface[ty * _size.x + tx]
	if object > column:
		return object
	return column - WATER_DRAUGHT if column < 0 else column

const MOUND_HIGH: int = 16
const MOUND_MAX: int = 256


func _measure_mounds(shape: RefCounted) -> void:
	var tiles: Dictionary = shape.mound_tiles()
	var doors: Array = tiles.get(&"door", [])
	var body: Array = tiles.get(&"body", [])
	if doors.is_empty() or body.is_empty():
		return
	var inside: PackedByteArray = _mound_interiors(doors, body)
	if inside.is_empty():
		return
	var distance: PackedInt32Array = _mound_depths(inside)
	for at: int in inside.size():
		if inside[at] == 1:
			_raise_mound(at, inside, distance)


## Every tile of a mound small enough to be one: a door tile and the body it
## reaches. A region over `MOUND_MAX` is a landscape rather than a mound.
func _mound_interiors(doors: Array, body: Array) -> PackedByteArray:
	var count: int = _size.x * _size.y
	var inside := PackedByteArray()
	inside.resize(count)
	var seen := PackedByteArray()
	seen.resize(count)
	var any: bool = false
	var is_body: Callable = func(at: int) -> bool:
		return _tiles[at] >= 0 and body.has(_tiles[at])
	for start: int in count:
		if seen[start] == 1 or _tiles[start] < 0 or not doors.has(_tiles[start]):
			continue
		var region: PackedInt32Array = _spread(start, seen, is_body)
		if region.size() > MOUND_MAX:
			continue
		for at: int in region:
			inside[at] = 1
		any = true
	return inside if any else PackedByteArray()


## How many tiles in from its own edge each mound tile lies, by breadth.
func _mound_depths(inside: PackedByteArray) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(inside.size())
	distance.fill(0)
	var queue := PackedInt32Array()
	for at: int in inside.size():
		if inside[at] == 0:
			continue
		distance[at] = -1
		if _on_mound_edge(at, inside):
			distance[at] = 1
			queue.append(at)
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for index: int in _neighbours(at):
			if inside[index] == 1 and distance[index] < 0:
				distance[index] = distance[at] + 1
				queue.append(index)
	return distance


## A tile with a neighbour outside the mound, the grid's own edge included.
func _on_mound_edge(at: int, inside: PackedByteArray) -> bool:
	var from: Vector2i = _tile_of(at)
	for step: Vector2i in STEPS:
		var index: int = _index(from.x + step.x, from.y + step.y)
		if index < 0 or inside[index] == 0:
			return true
	return false


## One mound tile: flat art at the mound's height, with each corner pulled down
## to the shallowest depth around it so the rim slopes rather than steps.
func _raise_mound(at: int, inside: PackedByteArray, distance: PackedInt32Array) -> void:
	_heights[at] = MOUND_HIGH
	_art[at] = ART_FLAT
	_volume[at] = 0
	_modelled[at] = 0
	var tile: Vector2i = _tile_of(at)
	var sloped: bool = false
	for corner: int in 4:
		var step := Vector2i(-1 if corner % 2 == 0 else 1, -1 if corner < 2 else 1)
		var near: int = maxi(distance[at], 0)
		for reach: Vector2i in [Vector2i(step.x, 0), Vector2i(0, step.y), step]:
			var to: Vector2i = tile + reach
			var index: int = _index_of(to)
			if index < 0 or not _in_map(to.x, to.y):
				continue
			near = mini(near, maxi(distance[index], 0) if inside[index] == 1 else 0)
		var high: int = mini(near * BAND, MOUND_HIGH)
		_corners[at * 4 + corner] = high
		sloped = sloped or high < MOUND_HIGH
	if sloped:
		_ramp[at] = 1


func _measure_doors(shape: RefCounted) -> void:
	var tiles: Dictionary = shape.mound_tiles()
	if tiles.is_empty():
		return
	var doors: Array = tiles.get(&"door", [])
	if doors.is_empty():
		return
	for at: int in _size.x * _size.y:
		if _tiles[at] < 0 or not doors.has(_tiles[at]):
			continue
		if _ramp[at] == 1 or _heights[at] > 0:
			continue
		@warning_ignore("integer_division")
		var from := Vector2i(at % _size.x, at / _size.x)
		var high: int = 0
		for step: Vector2i in STEPS:
			var to: Vector2i = from + step
			if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
				continue
			var index: int = to.y * _size.x + to.x
			if _tiles[index] >= 0 and doors.has(_tiles[index]):
				continue
			high = maxi(high, _heights[index])
		if high <= 0:
			continue
		_heights[at] = high
		_doorway[at] = 1
		for corner: int in 4:
			_corners[at * 4 + corner] = high


func _measure_collision_doors(from: int, to: int, source: RefCounted) -> void:
	if source == null or not _outside:
		return
	for at: int in range(from, to):
		if not _flat_and_free(at):
			continue
		if _tallest_beside(at) <= 0 or not _is_collision_door(source, at):
			continue
		# The doorway takes the height of the wall it is cut into, so the wall
		# either side of it and not another doorway carrying the same hole.
		var high: int = _tallest_beside(at, source)
		if high <= 0:
			continue
		_heights[at] = high
		_doorway[at] = 1
		for corner: int in 4:
			_corners[at * 4 + corner] = high


## Ground a door could be cut into: flat, unclaimed by a house, and not a ramp.
func _flat_and_free(at: int) -> bool:
	if _tiles[at] < 0 or _heights[at] > 0 or _ramp[at] == 1:
		return false
	return _house_covered.is_empty() or _house_covered[at] == 0


## The tallest neighbour, skipping any that is itself a collision door when a
## source is given.
func _tallest_beside(at: int, source: RefCounted = null) -> int:
	var high: int = 0
	for index: int in _neighbours(at):
		if source != null and _is_collision_door(source, index):
			continue
		high = maxi(high, _heights[index])
	return high


func _is_collision_door(source: RefCounted, at: int) -> bool:
	@warning_ignore("integer_division")
	var tile := Vector2i(at % _size.x - _margin.x, at / _size.x - _margin.y)
	var code: int = source.code_at(Vector2i(
		floori(float(tile.x) / float(CELL_TILES)),
		floori(float(tile.y) / float(CELL_TILES))
	))
	return code == Gen2WorldCollision.COLL_DOOR \
		or code == Gen2WorldCollision.COLL_DOOR_79 \
		or code == Gen2WorldCollision.COLL_CAVE


func _measure_mouths() -> void:
	for at: int in _size.x * _size.y:
		if _void[at] != 1 or _heights[at] != 0:
			continue
		@warning_ignore("integer_division")
		var from := Vector2i(at % _size.x, at / _size.x)
		var high: int = 0
		for step: Vector2i in STEPS:
			var to: Vector2i = from + step
			if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
				continue
			var index: int = to.y * _size.x + to.x
			if _void[index] == 1 or _cliff[index] == 0:
				continue
			high = maxi(high, _heights[index])
		if high <= 0:
			continue
		_heights[at] = high
		_shelf[at] = 1


func _measure_shores() -> void:
	var count: int = _size.x * _size.y
	var open_water: int = _commonest_water()
	for at: int in count:
		if _ramp[at] == 1 or not _is_water(at) or _tiles[at] == open_water:
			continue
		if _modelled[at] == 1:
			continue
		if _slope_shore(at):
			_ramp[at] = 1


## A shore corner rises to meet the bank across it, so the water laps up rather
## than meeting the land in a step. Answers whether any corner moved.
func _slope_shore(at: int) -> bool:
	var tile: Vector2i = _tile_of(at)
	var sloped: bool = false
	for corner: int in 4:
		var step := Vector2i(-1 if corner % 2 == 0 else 1, -1 if corner < 2 else 1)
		var high: int = _heights[at]
		for reach: Vector2i in [Vector2i(step.x, 0), Vector2i(0, step.y), step]:
			var index: int = _index_of(tile + reach)
			if index < 0 or _tiles[index] < 0 or _heights[index] <= _heights[at]:
				continue
			high = maxi(high, _corners[index * 4 + _corner_across(step, reach)])
		_corners[at * 4 + corner] = high
		sloped = sloped or high > _heights[at]
	return sloped


func _corner_across(step: Vector2i, reach: Vector2i) -> int:
	var sx: int = step.x if reach.x == 0 else -step.x
	var sy: int = step.y if reach.y == 0 else -step.y
	return (0 if sx < 0 else 1) + (0 if sy < 0 else 2)


func _measure_cliffs() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var structures: Array[PackedInt32Array] = []
	var banded := PackedInt32Array()
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
		structures.append(members)
		banded.append(_face_bands(members))
	var tallest: int = 0
	for bands: int in banded:
		tallest = maxi(tallest, bands)
	for index: int in structures.size():
		var members: PackedInt32Array = structures[index]
		var bands: int = banded[index]
		if bands <= 0:
			if tallest <= 0:
				continue
			for at: int in members:
				if _heights[at] <= tallest * BAND:
					continue
				_heights[at] = tallest * BAND
				_bases[at] = _cliff_base(at)
				_shelf[at] = 1
			continue
		for at: int in members:
			_heights[at] = bands * BAND
			_bases[at] = _cliff_base(at)
			_shelf[at] = 1


func _face_bands(members: PackedInt32Array) -> int:
	var runs: Dictionary = {}
	for at: int in members:
		if _front[at] == 0:
			continue
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


func _cliff_base(at: int) -> int:
	var walk: int = at
	while walk + _size.x < _cliff.size() and _cliff[walk + _size.x] == 1:
		walk += _size.x
	@warning_ignore("integer_division")
	return walk / _size.x


func _measure_plateaus() -> void:
	var seeds: Dictionary = {}
	var fronts: Dictionary = {}
	var patches: Dictionary = {}
	if not _cliff_evidence(seeds, fronts, patches):
		return
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var floor_of: Callable = _is_plateau_floor
	for start: int in seen.size():
		if seen[start] == 1 or not _is_plateau_floor(start):
			continue
		var members: PackedInt32Array = _spread(start, seen, floor_of)
		var raise: int = _plateau_height(members, seeds, fronts, patches)
		if raise < 0:
			continue
		for at: int in members:
			_heights[at] = raise
			_shelf[at] = 1
	_settle_lips()


## A plateau rises to its lowest seed. A front anywhere in it blocks the lift
## outright; a patch seed, which comes off a face under a walk cell, speaks only
## for a region small enough to be a rock rather than a town.
func _plateau_height(
	members: PackedInt32Array, seeds: Dictionary, fronts: Dictionary,
	patches: Dictionary
) -> int:
	var lift: int = -1
	var patch: int = -1
	for at: int in members:
		if fronts.has(at):
			return -1
		if seeds.has(at):
			var height: int = int(seeds[at])
			lift = height if lift < 0 else mini(lift, height)
		if patches.has(at):
			var height: int = int(patches[at])
			patch = height if patch < 0 else mini(patch, height)
	if lift >= 0:
		return lift
	return patch if members.size() <= PATCH_TILES else -1

func _settle_lips() -> void:
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _lip[at] == 0 or ty + 1 >= _size.y:
				continue
			var under: int = _heights[(ty + 1) * _size.x + tx]
			if _art[(ty + 1) * _size.x + tx] == ART_FLAT and under > 0:
				_heights[at] = under
				_shelf[at] = 1


func _settle_ponds() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	for start: int in seen.size():
		if seen[start] == 1 or not _is_water(start):
			continue
		var members := PackedInt32Array()
		var shore: int = _pond_shore(start, seen, members)
		if shore <= 0:
			continue
		for at: int in members:
			_heights[at] += shore


## Floods one body of water into `members` and answers the height of the ground
## around it, or -1 where that ground is not all at one height.
##
## A zero reads as "nothing seen yet" rather than as ground at zero, so a ring of
## 0 and 16 answers 16 or -1 depending on which the flood reaches last. Whirl
## Islands, map 3,72 tiles 36,60 to 39,71, is the one pool in the game where that
## decides anything: it stands a band proud of the floor beside it, and reading a
## zero as a height leaves it recessed and opens the map edge behind it. Which is
## right is a picture the reviewer has not been shown, so the order stands.
func _pond_shore(
	start: int, seen: PackedByteArray, members: PackedInt32Array
) -> int:
	var shore: int = 0
	var stack: Array[int] = [start]
	seen[start] = 1
	while not stack.is_empty():
		var at: int = stack.pop_back()
		members.append(at)
		var from: Vector2i = _tile_of(at)
		for step: Vector2i in POND_STEPS:
			var index: int = _index(from.x + step.x, from.y + step.y)
			if index < 0:
				shore = -1
				continue
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
	return shore

func _settle_beds() -> void:
	if not _class_ids.has(&"kerb"):
		return
	var kerb_id: int = int(_class_ids[&"kerb"])
	_bed_kerb = kerb_id
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var floor_of: Callable = _is_bed_floor
	for start: int in seen.size():
		if seen[start] == 1 or not _is_bed_floor(start):
			continue
		var members: PackedInt32Array = _spread(start, seen, floor_of)
		var kerb: int = _kerb_around(members, kerb_id)
		if kerb <= 0:
			continue
		for at: int in members:
			_heights[at] = kerb


## The one kerb height ringing a bed, or -1 where the ring is broken: anything
## that is not a kerb of the same height leaves the bed on the floor.
func _kerb_around(members: PackedInt32Array, kerb_id: int) -> int:
	var kerb: int = 0
	for at: int in members:
		var from: Vector2i = _tile_of(at)
		for step: Vector2i in STEPS:
			var index: int = _index(from.x + step.x, from.y + step.y)
			if index < 0:
				return -1
			if _is_bed_floor(index):
				continue
			if _klass[index] != kerb_id or _heights[index] <= 0:
				return -1
			if kerb == 0:
				kerb = _heights[index]
			elif kerb != _heights[index]:
				return -1
	return kerb

func _is_bed_floor(at: int) -> bool:
	return _tiles[at] >= 0 and _heights[at] == 0 and _klass[at] != _bed_kerb

var _bed_kerb: int = -1


func _is_water(at: int) -> bool:
	return _tiles[at] >= 0 and _art[at] == ART_FLAT and _heights[at] < 0


func _cliff_evidence(
	seeds: Dictionary, fronts: Dictionary, patches: Dictionary
) -> bool:
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
					var index: int = above * _size.x + tx
					if height >= PLATEAU_FLOOR:
						seeds[index] = mini(int(seeds.get(index, height)), height)
					elif height > 0:
						patches[index] = mini(int(patches.get(index, height)), height)
				var below: int = ty + run
				if _front[(below - 1) * _size.x + tx] == 1 \
						and below < _size.y \
						and _is_plateau_floor(below * _size.x + tx):
					fronts[below * _size.x + tx] = true
			ty += run
	return any


func _cliff_height(tx: int, top_row: int) -> int:
	var height: int = 0
	var ty: int = top_row
	while ty < _size.y and _cliff[ty * _size.x + tx] == 1:
		height = maxi(height, _heights[ty * _size.x + tx])
		ty += 1
	return height


func _is_plateau_floor(at: int) -> bool:
	return (
		_tiles[at] >= 0 and _art[at] == ART_FLAT and _heights[at] == 0
		and _lip[at] == 0 and _void[at] == 0
	)


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


func _settle_void() -> void:
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	var empty: Callable = func(at: int) -> bool: return _void[at] == 1
	for start: int in seen.size():
		if _void[start] == 0 or seen[start] == 1:
			continue
		var members: PackedInt32Array = _spread(start, seen, empty)
		var floor_height: int = _void_floor(members)
		if floor_height == 0:
			continue
		for at: int in members:
			_heights[at] = floor_height


## The void drops to the lowest measured floor around it, so a hole reads as a
## hole rather than as ground at zero.
func _void_floor(members: PackedInt32Array) -> int:
	var floor_height: int = 0
	for at: int in members:
		for index: int in _neighbours(at):
			if _void[index] == 1 or _volume[index] == 1 or _heights[index] == -1:
				continue
			floor_height = mini(floor_height, _heights[index])
	return floor_height

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


func _measure_furniture() -> void:
	var placed := PackedByteArray()
	placed.resize(_size.x * _size.y)
	for ty: int in range(_size.y - 1, -1, -1):
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _on_furniture[at] == 0 or placed[at] == 1:
				continue
			var under: int = 0
			if ty + 1 < _size.y:
				under = maxi(_heights[(ty + 1) * _size.x + tx], 0)
			var run: int = 1
			while ty - run >= 0 and _on_furniture[(ty - run) * _size.x + tx] == 1:
				run += 1
			var top: int = under + run * BAND
			for step: int in run:
				var index: int = at - step * _size.x
				_heights[index] = top
				@warning_ignore("integer_division")
				_bases[index] = ty + under / BAND
				_volume[index] = 1
				placed[index] = 1

const APRON_CLASSES: Array[StringName] = [&"table", &"counter", &"desk"]


func _settle_aprons() -> void:
	_apron_face.clear()
	var wanted: Dictionary = {}
	for shape_class: StringName in APRON_CLASSES:
		if _class_ids.has(shape_class):
			wanted[int(_class_ids[shape_class])] = true
	if wanted.is_empty():
		return
	for at: int in _size.x * _size.y:
		if _is_apron(at, wanted):
			_release_apron(at, wanted)


## The bottom row of a standing run: the row above it is the same class at the
## same height on a different tile, and the row below it is not.
func _is_apron(at: int, wanted: Dictionary) -> bool:
	if not _stands_apron(at, wanted):
		return false
	var north: int = at - _size.x
	if at < _size.x or not wanted.has(int(_klass[north])):
		return false
	if _heights[north] != _heights[at] or _tiles[north] == _tiles[at]:
		return false
	var south: int = at + _size.x
	if south >= _size.x * _size.y:
		return true
	return not (
		wanted.has(int(_klass[south])) and _heights[south] == _heights[at]
	)


## A standing tile of a wanted class that nothing else has already claimed.
func _stands_apron(at: int, wanted: Dictionary) -> bool:
	if not wanted.has(int(_klass[at])):
		return false
	if _art[at] != ART_TOP and _art[at] != ART_UPRIGHT:
		return false
	if _object_covered[at] == 1 or _house[at] != HOUSE_NONE:
		return false
	return _heights[at] > 0 and _tiles[at] >= 0


## Lay the bottom row flat on the floor beside it and hand its own art up the
## run, so the standing part wears the apron and the floor is floor.
func _release_apron(at: int, wanted: Dictionary) -> void:
	var tile: Vector2i = _tile_of(at)
	var floor_tile: Vector2i = _floor_beside(tile.x, tile.y)
	if floor_tile.x < 0:
		return
	_floor_art[at] = floor_tile
	var apron: int = _tiles[at]
	_heights[at] = floor_tile.y
	_art[at] = ART_FLAT
	_volume[at] = 0
	_on_furniture[at] = 0
	var up: int = tile.y - 1
	while up >= 0:
		var above: int = up * _size.x + tile.x
		if not wanted.has(int(_klass[above])) or _heights[above] <= 0:
			break
		_apron_face[above] = apron
		up -= 1

var _apron_face: Dictionary = {}

var _floor_art: Dictionary = {}


func _surface_beside(tx: int, ty: int, height: int) -> Vector2i:
	for step: int in range(1, _size.x):
		var reached: bool = false
		for way: int in [-1, 1]:
			var at_x: int = tx + step * way
			if at_x < 0 or at_x >= _size.x:
				continue
			reached = true
			var index: int = ty * _size.x + at_x
			if _object_covered[index] == 1 or _tiles[index] < 0:
				continue
			if (_art[index] == ART_TOP or _art[index] == ART_UPRIGHT) \
					and _heights[index] == height:
				return Vector2i(_tiles[index], height)
		if not reached:
			break
	return Vector2i(-1, 0)


func _floor_beside(tx: int, ty: int) -> Vector2i:
	for step: int in range(1, _size.x):
		var reached: bool = false
		for way: int in [-1, 1]:
			var at_x: int = tx + step * way
			if at_x < 0 or at_x >= _size.x:
				continue
			reached = true
			var index: int = ty * _size.x + at_x
			if _art[index] == ART_FLAT and _tiles[index] >= 0 and _heights[index] >= 0:
				return _floor_art.get(index, Vector2i(_tiles[index], _heights[index]))
		if not reached:
			break
	return Vector2i(-1, 0)


func _box_start(tx: int, ty: int, across: Vector2i) -> Vector2i:
	var map_x: int = tx - _margin.x
	var map_y: int = ty - _margin.y
	return Vector2i(
		_margin.x + map_x - posmod(map_x, across.x),
		_margin.y + map_y - posmod(map_y, across.y)
	)


func _span_box(at: int, tx: int, ty: int) -> Rect2i:
	var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
	var start: Vector2i = _box_start(tx, ty, across)
	if _span_cut[at] > 0:
		across.y = int(_span_cut[at])
	return Rect2i(start, across)


func _measure_cutouts(from: int, to: int) -> void:
	for ty: int in range(from, to):
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _art[at] != ART_CUTOUT or (_span_x[at] == 1 and _span_y[at] == 1):
				continue
			var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
			var start: Vector2i = _box_start(tx, ty, across)
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


func _row_holds(start: Vector2i, row: int, wide: int, klass: int) -> bool:
	var ty: int = start.y + row
	if ty >= _size.y:
		return false
	for column: int in wide:
		var tx: int = start.x + column
		if tx < _size.x and _klass[ty * _size.x + tx] == klass:
			return true
	return false


func _row_carries(start: Vector2i, row: int, wide: int, klass: int) -> bool:
	var ty: int = start.y + row
	if ty >= _size.y:
		return false
	for column: int in wide:
		var tx: int = start.x + column
		if tx >= _size.x or _klass[ty * _size.x + tx] != klass:
			return false
	return true


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


## The pattern tile with the fewest spots on this map, so a placement is looked
## for from the rarest tile of the drawing rather than from a roof corner every
## house on the map shares. The order placements come out in does not move with
## it: a spot ascends row by row, and so does the origin under it.
func _pattern_anchor(pattern: Array, across: Vector2i, where: Dictionary) -> Vector3i:
	var anchor := Vector3i(0, 0, 0)
	var fewest: int = 1 << 30
	for row: int in across.y:
		var line: Array = pattern[row]
		for column: int in across.x:
			var want: int = int(line[column])
			if want < 0:
				continue
			var spots: int = (where.get(want, []) as Array).size()
			if spots >= fewest:
				continue
			anchor = Vector3i(column, row, want)
			fewest = spots
			if spots == 0:
				return anchor
	return anchor


func _pattern_at(pattern: Array, across: Vector2i, tx: int, ty: int) -> bool:
	for row: int in across.y:
		var line: Array = pattern[row]
		for column: int in across.x:
			var want: int = int(line[column])
			if want >= 0 and _tile_at(tx + column, ty + row) != want:
				return false
	return true


func _object_front(
	source: RefCounted, object: Dictionary, start: Vector2i, across: Vector2i
) -> float:
	var window: Rect2i = object[&"window"]
	var front: float = _world_z(start.y) + float(window.position.y + window.size.y)
	if source == null or not object.has(&"depth"):
		return front
	var deep: float = float(object[&"depth"])
	var left: float = _world_x(start.x) + float(window.position.x)
	var right: float = left + float(window.size.x)
	if not _stands_on_floor(source, left, right, front - deep, front):
		return front
	var cell: float = float(CELL_TILES) * TILE
	var edge: float = -1.0
	for row: int in across.y:
		var at: float = _world_z(start.y + row)
		if not _stands_on_floor(source, left, right, at, at + TILE):
			edge = maxf(edge, floorf(at / cell + 1.0) * cell)
	if edge < 0.0 or edge >= front \
			or _stands_on_floor(source, left, right, edge - deep, edge):
		return front
	return edge


func _stands_on_floor(
	source: RefCounted, left: float, right: float, back: float, front: float
) -> bool:
	var cell: float = float(CELL_TILES) * TILE
	for cell_y: int in range(floori(back / cell), ceili(front / cell)):
		for cell_x: int in range(floori(left / cell), ceili(right / cell)):
			if source.permission_at(Vector2i(cell_x, cell_y)) != Gen2WorldCollision.WALL_TILE:
				return true
	return false


func _measure_objects(shape: RefCounted, source: RefCounted) -> void:
	_floor_art.clear()
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
				_objects.append([
					object, Vector2i(tx, ty), across,
					_object_front(source, object, Vector2i(tx, ty), across),
				])
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
						var rise: int = int(object.get(&"rise", 0))
						if rise > 0:
							var stood: Vector2i = _surface_beside(
								tx + column, ty + row, floors[row * across.x + column] + rise
							)
							if stood.x >= 0:
								_heights[at] = stood.y
								_floor_art[at] = stood
						var over: PackedInt32Array = _object_over.get(
							at, PackedInt32Array()
						)
						over.append(index)
						_object_over[at] = over

const STAIR_RISE: int = 16
const STAIR_STEPS: int = 4


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
					_ledge[at] |= _ledge_facing(step)
					_heights[at] = base
					_art[at] = ART_LEDGE
					_volume[at] = 0
					_cliff[at] = 0
					_front[at] = 0
					_lip[at] = 0
					_bases[at] = tile.y
	_join_ledge_corners()


func _join_ledge_corners() -> void:
	var additions: Dictionary = {}
	for ty: int in range(2, _size.y - 2):
		for tx: int in range(2, _size.x - 2):
			if _ledge_at(tx, ty) != LEDGE_NONE:
				continue
			for dy: int in [-1, 1]:
				var vertical: int = _ledge_at(tx, ty + dy * 2)
				if (vertical & (LEDGE_EAST | LEDGE_WEST)) == 0:
					continue
				for dx: int in [-1, 1]:
					var horizontal: int = _ledge_at(tx + dx * 2, ty)
					if (horizontal & (LEDGE_SOUTH | LEDGE_NORTH)) == 0:
						continue
					var leg_vertical := Vector2i(tx, ty + dy)
					var leg_horizontal := Vector2i(tx + dx, ty)
					if _ledge_at(leg_vertical.x, leg_vertical.y) != LEDGE_NONE \
						or _ledge_at(leg_horizontal.x, leg_horizontal.y) != LEDGE_NONE:
						continue
					var vertical_facing: int = vertical & (LEDGE_EAST | LEDGE_WEST)
					var horizontal_facing: int = horizontal & (LEDGE_SOUTH | LEDGE_NORTH)
					if _ledge_step(vertical_facing).x != -dx \
						or _ledge_step(horizontal_facing).y != -dy:
						continue
					var vertical_base: int = _heights[(ty + dy * 2) * _size.x + tx]
					var horizontal_base: int = _heights[ty * _size.x + tx + dx * 2]
					if vertical_base != horizontal_base:
						continue
					var base: int = vertical_base
					additions[leg_vertical] = [vertical_facing, base]
					additions[leg_horizontal] = [horizontal_facing, base]
					additions[Vector2i(tx, ty)] = [vertical_facing | horizontal_facing, base]
	for tile: Vector2i in additions:
		var values: Array = additions[tile]
		_set_ledge_tile(tile, int(values[0]), int(values[1]))


func _set_ledge_tile(tile: Vector2i, facing: int, base: int) -> void:
	var at: int = tile.y * _size.x + tile.x
	if _tiles[at] < 0:
		return
	_ledge[at] |= facing
	_heights[at] = base
	_art[at] = ART_LEDGE
	_volume[at] = 0
	_cliff[at] = 0
	_front[at] = 0
	_lip[at] = 0
	_bases[at] = tile.y


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


func _ledge_steps(facings: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for facing: int in [LEDGE_SOUTH, LEDGE_NORTH, LEDGE_EAST, LEDGE_WEST]:
		if (facings & facing) != 0:
			out.append(_ledge_step(facing))
	return out


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


func _measure_buildings() -> void:
	var column := PackedInt32Array()
	column.resize(_size.x)
	var placed := PackedByteArray()
	placed.resize(_size.x * _size.y)
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
			var runs: PackedInt32Array = PackedInt32Array()
			var bands: int = 0
			var pitch: int = 0x7fffffff
			for tx: int in range(wall, last + 1):
				var run: int = 1
				while ty - run >= 0 and _part[(ty - run) * _size.x + tx] == PART_WALL:
					run += 1
				runs.append(run)
				pitch = mini(pitch, _facade_pitch(tx, ty, run))
				bands = maxi(bands, _facade_period(tx, ty, run))
			if pitch > bands:
				pitch = 0
			for tx: int in range(wall, last + 1):
				var under: int = column[tx]
				var top: int = under + bands * BAND
				var flat: int = runs[tx - wall] - pitch
				for step: int in runs[tx - wall]:
					var index: int = (ty - step) * _size.x + tx
					var climbed: int = clampi(step - flat + 1, 0, pitch)
					_heights[index] = top - (pitch - climbed) * BAND
					_pitched[index] = int(climbed > 0)
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

const ROOF_RIDGE_NONE: int = 0
const ROOF_RIDGE_FLAT: int = 1
const ROOF_RIDGE_LEFT: int = 2
const ROOF_RIDGE_RIGHT: int = 3


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
	var hanging: bool = ridge == ROOF_RIDGE_LEFT or ridge == ROOF_RIDGE_RIGHT
	for tx: int in range(from, to + 1):
		var at: int = ty * _size.x + tx
		var height: int = agreed - fall[tx - from] * BAND
		if column[tx] > 0 or not hanging:
			height = maxi(height, column[tx])
		_heights[at] = height
		_volume[at] = 0
		@warning_ignore("integer_division")
		_bases[at] = ty + maxi(height / BAND - 1, 0)
		column[tx] = height


func _cell_unmeasured(cell_x: int, cell_y: int) -> bool:
	return _heights[cell_y * CELL_TILES * _size.x + cell_x * CELL_TILES] == -1


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


func height_at_position(position: Vector3) -> int:
	return _height_at(
		floori(position.x / TILE) + _margin.x, floori(position.z / TILE) + _margin.y
	)


func occlusion_height_at_position(position: Vector3) -> int:
	var tx: int = floori(position.x / TILE) + _margin.x
	var ty: int = floori(position.z / TILE) + _margin.y
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	var at: int = ty * _size.x + tx
	var top: int = _height_at(tx, ty)
	if _modelled[at] == 0:
		return top
	var box: Rect2i = _span_box(at, tx, ty)
	var stretch: float = _stretch[at]
	if stretch <= 0.0:
		stretch = 1.0 if _shrub[at] == 1 or _rock[at] == 1 else Model.CROWN_STRETCH
	return top + ceili(float(box.size.y) * TILE * stretch)


func _beside(tx: int, ty: int, step: Vector2i) -> int:
	var to := Vector2i(tx + step.x, ty + step.y)
	if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
		return 0
	var index: int = to.y * _size.x + to.x
	if _ramp[index] == 1:
		var corners: Vector2i = _shared_corners(step)
		return mini(_corners[index * 4 + corners.x], _corners[index * 4 + corners.y])
	if _art[index] == ART_LEDGE:
		var steps: Array[Vector2i] = _ledge_steps(_ledge[index])
		var base: int = _heights[index]
		var u: int = int(step.x < 0)
		var v: int = int(step.y < 0)
		if step.x == 0:
			return int(minf(
				_wedge_y(base, steps, 0, v), _wedge_y(base, steps, 1, v)
			))
		return int(minf(
			_wedge_y(base, steps, u, 0), _wedge_y(base, steps, u, 1)
		))
	return _heights[index]


func _shared_corners(step: Vector2i) -> Vector2i:
	if step.y > 0:
		return Vector2i(0, 1)
	if step.y < 0:
		return Vector2i(2, 3)
	if step.x > 0:
		return Vector2i(0, 2)
	return Vector2i(1, 3)


func _height_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	return _heights[ty * _size.x + tx]


func _face_tile(tx: int, ty: int, band: int) -> int:
	var apron: int = int(_apron_face.get(ty * _size.x + tx, -1))
	if apron >= 0:
		return apron
	return _band_tile(tx, ty, band)


func _band_tile(tx: int, ty: int, band: int) -> int:
	if not _room.is_empty():
		var mark: int = _room[ty * _size.x + tx]
		if mark == ROOM_SHELL or mark == ROOM_FILL:
			return _tiles[ty * _size.x + tx]
		if mark == ROOM_BEHIND:
			return _room_wall_tile(tx, ty)
	var row: int = _bases[ty * _size.x + tx] - band
	if row < 0:
		row = 0
	var tile: int = _tiles[row * _size.x + tx]
	return tile if tile >= 0 else _tiles[ty * _size.x + tx]

const RING_SHARE: float = 0.7
var _masks: Dictionary = {}


func _mask_key(tiles: Array, filled: bool, outline: int) -> String:
	return "%s,%d,%d" % [str(tiles), int(filled), outline]


func _structure_mask(
	tiles: Array, across: Vector2i, atlas: RefCounted, filled: bool,
	outline: int = 0
) -> PackedByteArray:
	var key: String = _mask_key(tiles, filled, outline)
	if _masks.has(key):
		return _masks[key]

	var mask := PackedByteArray()
	for frame: int in atlas.frame_count(tiles):
		var one: PackedByteArray = _mask_frame(
			tiles, across, atlas, filled, outline, frame
		)
		if mask.is_empty():
			mask = one
			continue
		for at: int in mask.size():
			if one[at] == 1:
				mask[at] = 1
	_masks[key] = mask
	return mask


func _mask_frame(
	tiles: Array, across: Vector2i, atlas: RefCounted, filled: bool,
	outline: int, frame: int
) -> PackedByteArray:
	var size := Vector2i(across.x * int(TILE), across.y * int(TILE))
	var indices := PackedInt32Array()
	indices.resize(size.x * size.y)
	var open := PackedByteArray()
	open.resize(size.x * size.y)
	for py: int in size.y:
		for px: int in size.x:
			@warning_ignore("integer_division")
			var tile: int = tiles[(py / int(TILE)) * across.x + px / int(TILE)]
			var index: int = atlas.frame_pixel(
				tile, px % int(TILE), py % int(TILE), frame
			)
			indices[py * size.x + px] = index
			if outline > 0:
				open[py * size.x + px] = 0 if atlas.is_dark(tile, index, outline) else 1

	if outline > 0:
		return _flood(size, open, filled)

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
		open[at] = int(ground.has(indices[at]))
	return _flood(size, open, filled)


func _flood(
	size: Vector2i, open: PackedByteArray, filled: bool
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

	return mask


func _ring_pixel(ring: Dictionary, indices: PackedInt32Array, at: int) -> void:
	ring[indices[at]] = int(ring.get(indices[at], 0)) + 1


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
	var body := _bodies(mask, span)
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

var _hulls: Dictionary = {}


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

var _model_meshes: Dictionary = {}
var _model_spots: Dictionary = {}
var _model_bodies: Dictionary = {}
var _built_model: bool = false


func _place_model(tx: int, ty: int, atlas: RefCounted, base: float = INF) -> void:
	var at: int = ty * _size.x + tx
	var box: Rect2i = _span_box(at, tx, ty)
	var across: Vector2i = box.size
	var start: Vector2i = box.position
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var ground: float = base if is_finite(base) else float(_ground_art(tx, ty).y)
	for body: Array in _model_bodies_of(tiles, across, at, atlas):
		var key: String = body[0]
		var middle: Vector2 = body[1]
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
		var worn: String = key
		if _ring_reach > 0.0 and _model_measures.has(key) \
				and Vector2(spot.x, spot.z).distance_to(
					Vector2(_ring_at.x, _ring_at.z)
				) > _ring_reach:
			worn = _far_key(key)
		var placed: Array = [
			Transform3D(Basis(Vector3(0.0, 1.0, 0.0), turn), spot),
			_hash_spot(anchor + Vector2i(0, 53)),
			_model_chunk(start),
		]
		(_model_spots[worn] as Dictionary)[str(start)] = placed
		_chunk_spots.append([worn, str(start), placed])


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
	if _potted[at] == 1:
		for pixel: int in body.size():
			if body[pixel] >= 0:
				body[pixel] = 0
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
				only[pixel] = int(body[pixel] == group)
			var measured: RefCounted = Model.measure(
				only, span, tiles, across, atlas, _potted[at] == 1
			)
			measured.shrub = _shrub[at] == 1
			measured.rock = _rock[at] == 1
			measured.potted = _potted[at] == 1
			measured.column = _column[at] == 1
			measured.stretch = _stretch[at]
			_model_meshes[key] = _model_mesh_of(measured)
			_model_measures[key] = measured
			_model_inputs[key] = [only, span, tiles, across]
			_model_cutouts[key] = _cut_out(only, span, tiles, across, atlas)
			_model_spots[key] = {}
			_built_model = true
		var box: Rect2i = bounds[group]
		out.append([key, Vector2(box.position) + Vector2(box.size) * 0.5])
	_model_bodies[drawing] = out
	return out

const MODEL_BODY_MIN: int = 8

const MODEL_NUDGE: float = 5.0

static var impostor_models: bool = false

var _model_measures: Dictionary = {}
var _model_inputs: Dictionary = {}
var _recolour_queue: PackedStringArray = PackedStringArray()
var _recolour_at: int = 0
var _recolour_atlas: RefCounted = null
var _model_cutouts: Dictionary = {}
const IMPOSTOR_SUFFIX: String = "~far"
var _ring_at := Vector3.ZERO
var _ring_reach: float = 0.0


func set_detail_ring(at: Vector3, reach: float) -> void:
	_ring_at = at
	_ring_reach = maxf(reach, 0.0)


func begin_recolour(atlas: RefCounted) -> void:
	_recolour_atlas = atlas
	_recolour_queue = PackedStringArray(_model_inputs.keys()) if atlas != null \
		else PackedStringArray()
	_recolour_at = 0


func recolour_step(budget_usec: int) -> bool:
	if _recolour_atlas == null or _recolour_at >= _recolour_queue.size():
		_recolour_atlas = null
		return true
	var until: int = Time.get_ticks_usec() + budget_usec
	while _recolour_at < _recolour_queue.size():
		_recolour_one(_recolour_queue[_recolour_at], _recolour_atlas)
		_recolour_at += 1
		if Time.get_ticks_usec() >= until:
			return _recolour_at >= _recolour_queue.size()
	_recolour_atlas = null
	return true


func recolour_models(atlas: RefCounted) -> void:
	begin_recolour(atlas)
	while not recolour_step(1 << 30):
		pass


func _recolour_one(key: String, atlas: RefCounted) -> void:
	var was: RefCounted = _model_measures.get(key)
	if was == null:
		return
	var input: Array = _model_inputs[key]
	var measured: RefCounted = Model.measure(
		input[0], input[1], input[2], input[3], atlas, was.potted
	)
	measured.shrub = was.shrub
	measured.rock = was.rock
	measured.potted = was.potted
	measured.column = was.column
	measured.stretch = was.stretch
	_model_measures[key] = measured
	_rewrite_mesh(_model_meshes.get(key), _model_mesh_of(measured))
	var cutout: ImageTexture = _model_cutouts.get(key)
	if cutout != null:
		var fresh: ImageTexture = _cut_out(
			input[0], input[1], input[2], input[3], atlas
		)
		if fresh != null:
			cutout.set_image(fresh.get_image())
	var far: String = key + IMPOSTOR_SUFFIX
	if _model_meshes.has(far):
		var model: RefCounted = Model.new()
		_rewrite_mesh(
			_model_meshes[far],
			model.sprite(measured) if cutout != null else model.impostor(measured)
		)


func _rewrite_mesh(into: ArrayMesh, fresh: ArrayMesh) -> void:
	if into == null or fresh == null:
		return
	into.clear_surfaces()
	for surface: int in fresh.get_surface_count():
		into.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, fresh.surface_get_arrays(surface)
		)


func _model_mesh_of(measured: RefCounted) -> ArrayMesh:
	var model: RefCounted = Model.new()
	return model.impostor(measured) if impostor_models else model.tree(measured)


func _far_key(key: String) -> String:
	var far: String = key + IMPOSTOR_SUFFIX
	if not _model_meshes.has(far):
		var model: RefCounted = Model.new()
		var measured: RefCounted = _model_measures[key]
		_model_meshes[far] = model.sprite(measured) \
			if _model_cutouts.get(key) != null else model.impostor(measured)
		_model_spots[far] = {}
	return far


func far_card_for(
	tiles: Array, across: Vector2i, shape: RefCounted, named: StringName,
	atlas: RefCounted
) -> Array:
	if tiles.is_empty() or across.x <= 0 or across.y <= 0 or atlas == null:
		return []
	var span: Vector2i = across * int(TILE)
	var mask: PackedByteArray = _structure_mask(
		tiles, across, atlas, shape.is_filled(named), shape.outline_shades(named)
	)
	var body: PackedInt32Array = _bodies(mask, span)
	var potted: bool = shape.is_potted(named)
	if potted:
		for pixel: int in body.size():
			if body[pixel] >= 0:
				body[pixel] = 0
	var counts: Dictionary = {}
	for pixel: int in body.size():
		if body[pixel] >= 0:
			counts[body[pixel]] = int(counts.get(body[pixel], 0)) + 1
	var best: int = -1
	var widest: int = 0
	for group: int in counts:
		if int(counts[group]) >= MODEL_BODY_MIN and int(counts[group]) > widest:
			widest = int(counts[group])
			best = group
	if best < 0:
		return []
	var only := PackedByteArray()
	only.resize(mask.size())
	for pixel: int in body.size():
		only[pixel] = int(body[pixel] == best)
	var cutout: ImageTexture = _cut_out(only, span, tiles, across, atlas)
	if cutout == null:
		return []
	var measured: RefCounted = Model.measure(only, span, tiles, across, atlas, potted)
	measured.shrub = shape.is_shrub(named)
	measured.rock = shape.is_rock(named)
	measured.potted = potted
	measured.column = shape.is_column(named)
	measured.stretch = shape.model_stretch(named)
	return [Model.new().sprite(measured), cutout]


func far_tree() -> Array:
	var best: String = ""
	var widest: int = 0
	for key: String in _model_cutouts:
		var cutout: ImageTexture = _model_cutouts[key]
		if cutout == null:
			continue
		var area: int = cutout.get_width() * cutout.get_height()
		if area > widest:
			widest = area
			best = key
	if best.is_empty():
		return []
	return [_model_meshes[_far_key(best)], _model_cutouts[best]]


func _cut_out(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted
) -> ImageTexture:
	var box := Rect2i(0, 0, 0, 0)
	var any: bool = false
	for py: int in span.y:
		for px: int in span.x:
			if mask[py * span.x + px] != 1:
				continue
			if not any:
				any = true
				box = Rect2i(px, py, 1, 1)
			else:
				box = box.expand(Vector2i(px + 1, py + 1)).expand(Vector2i(px, py))
	if not any or box.size.x <= 0 or box.size.y <= 0:
		return null
	var image := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for py: int in box.size.y:
		for px: int in box.size.x:
			var at := Vector2i(box.position.x + px, box.position.y + py)
			if mask[at.y * span.x + at.x] != 1:
				continue
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(at.y / int(TILE)) * across.x + at.x / int(TILE)])
			var drawn: Color = atlas.texel(tile, at.x % int(TILE), at.y % int(TILE))
			image.set_pixel(px, py, Color(drawn.r, drawn.g, drawn.b, 1.0))
	return ImageTexture.create_from_image(image)


func _hash_spot(anchor: Vector2i) -> float:
	var value: float = sin(float(anchor.x) * 127.1 + float(anchor.y) * 311.7) * 43758.5453
	return value - floorf(value)


static func _model_chunk(start: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(start.x) / MODEL_CHUNK_TILES),
		floori(float(start.y) / MODEL_CHUNK_TILES)
	)


func take_models() -> Array:
	var out: Array = []
	for key: String in _model_meshes:
		var groups: Dictionary = {}
		for entry: Array in (_model_spots.get(key, {}) as Dictionary).values():
			var cell: Vector2i = entry[2]
			if not groups.has(cell):
				groups[cell] = []
			(groups[cell] as Array).append(entry)
		for cell: Vector2i in groups:
			var placed: Array[Transform3D] = []
			var phases := PackedFloat32Array()
			for entry: Array in groups[cell] as Array:
				placed.append(entry[0] as Transform3D)
				phases.append(float(entry[1]))
			out.append([
				_model_meshes[key], placed, phases,
				_model_cutouts.get(key.trim_suffix(IMPOSTOR_SUFFIX)) \
					if key.ends_with(IMPOSTOR_SUFFIX) else null,
			])
	return out


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


func _object_base(object: Dictionary, start: Vector2i, across: Vector2i) -> float:
	var tx: int = start.x
	var ty: int = start.y + across.y - 1
	var base: float = float(_ground_art(tx, ty).y)
	if ty >= 0 and ty < _size.y and tx >= 0 and tx < _size.x \
			and _floor_art.has(ty * _size.x + tx):
		return base
	return base + float(object.get(&"rise", 0))


func _emit_object(index: int, atlas: RefCounted) -> void:
	var object: Dictionary = _objects[index][0]
	if not bool(object.get(&"turn", false)):
		_emit_object_body(index, atlas)
		return
	_turn = true
	_emit_object_body(index, atlas)
	_turn = false


## One standing object, measured out of its own drawing.
class Standing:
	var start := Vector2i.ZERO
	var across := Vector2i.ZERO
	var window := Rect2i()
	var span := Vector2i.ZERO
	var tiles: Array = []
	var mask := PackedByteArray()
	## Rows of the drawing that lie across the depth rather than down the height.
	var top_rows: int = 0
	var face_from: int = 0
	var face_rows: int = 0
	var deep: float = 0.0
	var tall: float = 0.0
	var base: float = 0.0
	var high: float = 0.0
	var front: float = 0.0
	var back: float = 0.0
	var left: float = 0.0
	var right: float = 0.0


func _emit_object_body(index: int, atlas: RefCounted) -> void:
	var entry: Array = _objects[index]
	var object: Dictionary = entry[0]
	var it := Standing.new()
	it.start = entry[1]
	it.across = entry[2]
	it.front = entry[3]
	it.span = it.across * int(TILE)
	it.window = object[&"window"]
	it.tiles = _object_tiles(object, it.start, it.across)
	it.mask = _object_mask(object, it.tiles, it.across, atlas)
	if _object_built(object, it, atlas):
		return
	_object_measure(object, it)
	if _turn:
		_turn_pivot = Vector3(
			(it.left + it.right) * 0.5, 0.0, (it.front + it.back) * 0.5
		)
	_object_faces(it, atlas)
	_object_sides(object, it, atlas)


## The drawing an object wears: its own authored art where it has some, else the
## tiles the map places under it.
func _object_tiles(object: Dictionary, start: Vector2i, across: Vector2i) -> Array:
	var painted: Array = object.get(&"art", [])
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(
				int((painted[row] as Array)[column]) if not painted.is_empty()
				else _tile_at(start.x + column, start.y + row)
			)
	return tiles


func _object_mask(
	object: Dictionary, tiles: Array, across: Vector2i, atlas: RefCounted
) -> PackedByteArray:
	var mask: PackedByteArray = _structure_mask(
		tiles, across, atlas, bool(object.get(&"filled", false)),
		int(object.get(&"outline", 1))
	)
	if not bool(object.get(&"solid", false)):
		return mask
	mask = mask.duplicate()
	mask.fill(1)
	return mask


## An object declared as one of the authored shapes builds itself and is done.
func _object_built(
	object: Dictionary, it: Standing, atlas: RefCounted
) -> bool:
	if bool(object.get(&"model", false)):
		_object_model(
			object, it.start, it.across, it.tiles, it.mask, it.span, it.window, atlas
		)
	elif bool(object.get(&"bin", false)):
		_object_bin(
			object, it.start, it.across, it.front, it.tiles, it.mask, it.span,
			it.window, atlas
		)
	elif bool(object.get(&"terminal", false)):
		_object_terminal(
			object, it.start, it.across, it.front, it.tiles, it.mask, it.span,
			it.window, atlas
		)
	elif bool(object.get(&"stool", false)):
		_object_stool(
			object, it.start, it.across, it.front, it.tiles, it.mask, it.span,
			it.window, atlas
		)
	elif bool(object.get(&"seat", false)):
		_object_seat(
			object, it.start, it.across, it.front, it.tiles, it.mask, it.span,
			it.window, atlas
		)
	elif bool(object.get(&"tower", false)):
		_object_tower(object, it.start, it.across, it.tiles, it.window, atlas)
	else:
		return false
	return true


func _object_measure(object: Dictionary, it: Standing) -> void:
	it.top_rows = clampi(int(object.get(&"top", 0)), 0, it.window.size.y)
	it.face_rows = it.window.size.y - it.top_rows
	it.face_from = it.window.position.y + it.top_rows
	var face_until: int = it.window.position.y + it.window.size.y
	if bool(object.get(&"foot", false)):
		var reach: Vector2i = _drawn_rows(
			it.mask, it.span, it.window, it.face_from, face_until
		)
		if reach.y > reach.x:
			it.face_from = reach.x
			it.face_rows = reach.y - reach.x
	it.deep = float(object[&"depth"])
	it.tall = float(object[&"height"])
	it.base = _object_base(object, it.start, it.across)
	it.back = it.front - it.deep
	it.left = _world_x(it.start.x) + float(it.window.position.x)
	it.right = it.left + float(it.window.size.x)
	it.high = it.base + it.tall


## The drawing itself, greedily gathered into the largest rectangles that stay
## inside one tile: the top rows lie across the depth, the rest stand up the face.
func _object_faces(it: Standing, atlas: RefCounted) -> void:
	var taken := PackedByteArray()
	taken.resize(it.window.size.x * it.window.size.y)
	for row: int in it.window.size.y:
		var py: int = it.window.position.y + row
		var above: bool = py < it.face_from
		@warning_ignore("integer_division")
		var down_stop: int = mini(
			((py / int(TILE)) + 1) * int(TILE) - it.window.position.y,
			it.face_from - it.window.position.y if above else it.window.size.y
		)
		var px: int = it.window.position.x
		while px < it.window.position.x + it.window.size.x:
			px = _object_patch(it, atlas, taken, row, py, px, above, down_stop)


## One rectangle from `px` rightward, as deep as it can go without leaving the
## tile or meeting a pixel already spent. Answers where the next one starts.
func _object_patch(
	it: Standing, atlas: RefCounted, taken: PackedByteArray, row: int, py: int,
	px: int, above: bool, down_stop: int
) -> int:
	var column: int = px - it.window.position.x
	if taken[row * it.window.size.x + column] == 1 \
			or not _drawn(it.mask, it.span, px, py):
		return px + 1
	@warning_ignore("integer_division")
	var stop: int = mini(
		(px / int(TILE) + 1) * int(TILE),
		it.window.position.x + it.window.size.x
	)
	var run: int = px
	while run < stop \
			and taken[row * it.window.size.x + run - it.window.position.x] == 0 \
			and _drawn(it.mask, it.span, run, py):
		run += 1
	var deep_rows: int = _object_patch_depth(
		it, taken, row, py, px, column, run, down_stop
	)
	for down: int in deep_rows:
		for step: int in run - px:
			taken[(row + down) * it.window.size.x + column + step] = 1
	_object_quad(it, atlas, py, px, run, row, deep_rows, above)
	return run


func _object_patch_depth(
	it: Standing, taken: PackedByteArray, row: int, py: int, px: int,
	column: int, run: int, down_stop: int
) -> int:
	var deep_rows: int = 1
	while row + deep_rows < down_stop:
		var whole: bool = true
		for step: int in run - px:
			if taken[(row + deep_rows) * it.window.size.x + column + step] == 1 \
					or not _drawn(it.mask, it.span, px + step, py + deep_rows):
				whole = false
				break
		if not whole:
			break
		deep_rows += 1
	return deep_rows


func _object_quad(
	it: Standing, atlas: RefCounted, py: int, px: int, run: int, row: int,
	deep_rows: int, above: bool
) -> void:
	var far: float = 0.0
	var near: float = 0.0
	if above:
		far = it.back + it.deep * float(row) / float(it.top_rows)
		near = it.back + it.deep * float(row + deep_rows) / float(it.top_rows)
	else:
		far = it.high - it.tall * float(py - it.face_from) / float(it.face_rows)
		near = it.high - it.tall \
			* float(py - it.face_from + deep_rows) / float(it.face_rows)
	@warning_ignore("integer_division")
	var tile: int = int(it.tiles[(py / int(TILE)) * it.across.x + px / int(TILE)])
	var uv: Rect2 = atlas.uv_box(
		tile, Rect2i(px % int(TILE), py % int(TILE), run - px, deep_rows)
	)
	var x0: float = _world_x(it.start.x) + float(px)
	var x1: float = _world_x(it.start.x) + float(run)
	if above:
		_quad(
			Vector3(x0, it.high, near), Vector3(x1, it.high, near),
			Vector3(x1, it.high, far), Vector3(x0, it.high, far),
			Vector3.UP, uv, SHADE_TOP_FLAT
		)
		return
	_quad(
		Vector3(x0, near, it.front), Vector3(x1, near, it.front),
		Vector3(x1, far, it.front), Vector3(x0, far, it.front),
		Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
	)


## The three faces the drawing does not show, and the lid where nothing lies
## across the top already.
func _object_sides(
	object: Dictionary, it: Standing, atlas: RefCounted
) -> void:
	if bool(object.get(&"wrap", false)) or bool(object.get(&"box", false)):
		var ends := Rect2()
		if bool(object.get(&"box", false)):
			ends = _bin_texel(
				atlas, it.tiles, it.across, it.mask, it.span, it.window,
				it.window.position.y, it.window.position.y + it.top_rows, -1
			)
		_object_wrap(
			atlas, it.tiles, it.across, it.mask, it.span, it.window, it.face_from,
			it.face_rows, it.left, it.right, it.front, it.back, it.base, it.high,
			ends
		)
		return
	var side: Rect2 = _object_texel(
		atlas, it.tiles, it.across, it.mask, it.span, it.window,
		it.window.position.y + it.top_rows,
		it.window.position.y + it.window.size.y
	)
	_quad(
		Vector3(it.right, it.base, it.back), Vector3(it.left, it.base, it.back),
		Vector3(it.left, it.high, it.back), Vector3(it.right, it.high, it.back),
		Vector3(0.0, 0.0, -1.0), side, SHADE_NORTH
	)
	_quad(
		Vector3(it.right, it.base, it.front), Vector3(it.right, it.base, it.back),
		Vector3(it.right, it.high, it.back), Vector3(it.right, it.high, it.front),
		Vector3(1.0, 0.0, 0.0), side, SHADE_SIDE
	)
	_quad(
		Vector3(it.left, it.base, it.back), Vector3(it.left, it.base, it.front),
		Vector3(it.left, it.high, it.front), Vector3(it.left, it.high, it.back),
		Vector3(-1.0, 0.0, 0.0), side, SHADE_SIDE
	)
	if it.top_rows == 0:
		_object_lid(object, it, atlas)


func _object_lid(object: Dictionary, it: Standing, atlas: RefCounted) -> void:
	var cap: int = int(object.get(&"cap", 0))
	if cap > 0:
		_object_cap(
			atlas, it.tiles, it.across, it.mask, it.span, it.window, cap,
			it.left, it.right, it.high, it.front, it.back
		)
		return
	_quad(
		Vector3(it.left, it.high, it.front), Vector3(it.right, it.high, it.front),
		Vector3(it.right, it.high, it.back), Vector3(it.left, it.high, it.back),
		Vector3.UP,
		_object_texel(
			atlas, it.tiles, it.across, it.mask, it.span, it.window,
			it.window.position.y, it.window.position.y + it.window.size.y
		),
		SHADE_TOP_FLAT
	)


func _object_tower(
	object: Dictionary, start: Vector2i, across: Vector2i,
	tiles: Array, window: Rect2i, atlas: RefCounted
) -> void:
	var base: float = _object_base(object, start, across)
	var cx: float = _world_x(start.x) + float(window.position.x) \
		+ float(window.size.x) * 0.5
	var cz: float = _world_z(start.y) + float(object[&"axis"]) * TILE
	var door := Vector2i(-1, -1)
	if object.has(&"door"):
		var span: Array = object[&"door"]
		door = Vector2i(int(span[0]), int(span[1]))
	var low: float = base
	for layer: Dictionary in object[&"layers"] as Array:
		var high: float = low + float(layer[&"tiles"]) * TILE
		var half: float = float(layer[&"half"]) * TILE
		var top_half: float = float(layer.get(&"top_half", layer[&"half"])) * TILE
		var art: Array = layer[&"art"]
		var box := Rect2i(int(art[0]), int(art[1]), int(art[2]), int(art[3]))
		for side: int in 4:
			_tower_face(
				tiles, across, box, door, side, cx, cz, low, high, half, top_half,
				atlas
			)
		if layer.has(&"top"):
			var over: Array = layer[&"top"]
			_tower_top(
				tiles, across,
				Rect2i(int(over[0]), int(over[1]), int(over[2]), int(over[3])),
				cx, cz, high, top_half, atlas
			)
		low = high

const TOWER_SHADES: Array = [SHADE_SOUTH, SHADE_SIDE, SHADE_NORTH, SHADE_SIDE]


func _tower_face(
	tiles: Array, across: Vector2i, art: Rect2i, door: Vector2i, side: int,
	cx: float, cz: float, low: float, high: float, half: float, top_half: float,
	atlas: RefCounted
) -> void:
	if half <= 0.0 or art.size.x <= 0 or art.size.y <= 0:
		return
	@warning_ignore("integer_division")
	var wide: int = int(half * 2.0) / TILE_PX
	if wide <= 0:
		return
	var rows: int = art.size.y
	var normal: Vector3 = [
		Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0),
	][side]
	for band: int in rows:
		var t0: float = float(rows - band - 1) / float(rows)
		var t1: float = float(rows - band) / float(rows)
		var y0: float = lerpf(low, high, t0)
		var y1: float = lerpf(low, high, t1)
		var s0: float = lerpf(1.0, top_half / half, t0)
		var s1: float = lerpf(1.0, top_half / half, t1)
		var tile_row: int = art.position.y + band
		for column: int in wide:
			var art_column: int = _tower_art_column(art, door, side, column, wide)
			var at: int = tile_row * across.x + art_column
			if at < 0 or at >= tiles.size():
				continue
			var uv: Rect2 = atlas.uv_box(
				int(tiles[at]), Rect2i(0, 0, TILE_PX, TILE_PX)
			)
			var u0: float = -half + float(column) * TILE
			var u1: float = u0 + TILE
			_quad(
				_tower_corner(side, cx, cz, u0 * s0, y0, half * s0),
				_tower_corner(side, cx, cz, u1 * s0, y0, half * s0),
				_tower_corner(side, cx, cz, u1 * s1, y1, half * s1),
				_tower_corner(side, cx, cz, u0 * s1, y1, half * s1),
				normal, uv, TOWER_SHADES[side]
			)


func _tower_corner(
	side: int, cx: float, cz: float, along: float, y: float, out: float
) -> Vector3:
	match side:
		0:
			return Vector3(cx + along, y, cz + out)
		1:
			return Vector3(cx + out, y, cz - along)
		2:
			return Vector3(cx - along, y, cz - out)
		_:
			return Vector3(cx - out, y, cz + along)


func _tower_art_column(
	art: Rect2i, door: Vector2i, side: int, column: int, wide: int
) -> int:
	@warning_ignore("integer_division")
	var at: int = (column * 2 + 1) * art.size.x / (wide * 2)
	at = art.position.x + clampi(at, 0, art.size.x - 1)
	if side == 0 or door.x < 0 or at < door.x or at > door.y:
		return at
	var left: int = door.x - 1
	var right: int = door.y + 1
	if left < art.position.x:
		return mini(right, art.position.x + art.size.x - 1)
	if right > art.position.x + art.size.x - 1:
		return left
	return left if at - door.x <= door.y - at else right


func _tower_top(
	tiles: Array, across: Vector2i, art: Rect2i,
	cx: float, cz: float, y: float, half: float, atlas: RefCounted
) -> void:
	if half <= 0.0 or art.size.x <= 0 or art.size.y <= 0:
		return
	@warning_ignore("integer_division")
	var wide: int = int(half * 2.0) / TILE_PX
	if wide <= 0:
		return
	for row: int in wide:
		@warning_ignore("integer_division")
		var art_row: int = art.position.y + clampi(
			(row * 2 + 1) * art.size.y / (wide * 2), 0, art.size.y - 1
		)
		var z0: float = -half + float(row) * TILE
		var z1: float = z0 + TILE
		for column: int in wide:
			@warning_ignore("integer_division")
			var art_column: int = art.position.x + clampi(
				(column * 2 + 1) * art.size.x / (wide * 2), 0, art.size.x - 1
			)
			var at: int = art_row * across.x + art_column
			if at < 0 or at >= tiles.size():
				continue
			var uv: Rect2 = atlas.uv_box(
				int(tiles[at]), Rect2i(0, 0, TILE_PX, TILE_PX)
			)
			var x0: float = -half + float(column) * TILE
			var x1: float = x0 + TILE
			_quad(
				Vector3(cx + x0, y, cz + z1), Vector3(cx + x1, y, cz + z1),
				Vector3(cx + x1, y, cz + z0), Vector3(cx + x0, y, cz + z0),
				Vector3.UP, uv, SHADE_TOP_FLAT
			)

const BIN_SEGMENTS: int = 16
const BIN_WALL: float = 1.5
const BIN_FOOT: float = 0.72
const BIN_FLOOR: float = 2.0


func _object_bin(
	object: Dictionary, start: Vector2i, across: Vector2i, front: float, tiles: Array,
	mask: PackedByteArray, span: Vector2i, window: Rect2i, atlas: RefCounted
) -> void:
	var top_rows: int = clampi(int(object.get(&"top", 0)), 0, window.size.y)
	var face_rows: int = window.size.y - top_rows
	if face_rows <= 0:
		return
	var base: float = float(_ground_art(start.x, start.y + across.y - 1).y)
	var high: float = base + float(object[&"height"])
	var wide: float = float(window.size.x)
	var centre := Vector2(
		_world_x(start.x) + float(window.position.x) + wide * 0.5, front - wide * 0.5
	)
	var lip: float = 0.0
	for row: int in top_rows:
		lip = maxf(lip, _bin_half(mask, span, window, window.position.y + row))
	var foot: float = lip
	for row: int in face_rows:
		lip = maxf(lip, _bin_half(mask, span, window, window.position.y + top_rows + row))
	foot = maxf(
		_bin_half(mask, span, window, window.position.y + window.size.y - 1),
		lip * BIN_FOOT
	)
	var body: Rect2 = _bin_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y + top_rows, window.position.y + window.size.y, -1
	)
	var body_index: int = _bin_index(
		atlas, tiles, across, mask, span, window,
		window.position.y + top_rows, window.position.y + window.size.y, -1
	)
	var band: Rect2 = _bin_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y + top_rows, window.position.y + window.size.y, body_index
	)
	@warning_ignore("integer_division")
	var band_row: int = face_rows / 2
	var mouth: Rect2 = _bin_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y, window.position.y + top_rows, -1
	)
	var step: float = TAU / float(BIN_SEGMENTS)
	var inner_floor: float = base + BIN_FLOOR
	for row: int in face_rows:
		var y_high: float = high - (high - base) * float(row) / float(face_rows)
		var y_low: float = high - (high - base) * float(row + 1) / float(face_rows)
		var r_high: float = lerpf(foot, lip, float(face_rows - row) / float(face_rows))
		var r_low: float = lerpf(foot, lip, float(face_rows - row - 1) / float(face_rows))
		var skin: Rect2 = band if row == band_row else body
		for segment: int in BIN_SEGMENTS:
			var d0: Vector2 = _bin_ray(float(segment) * step)
			var d1: Vector2 = _bin_ray(float(segment + 1) * step)
			var out: Vector3 = Vector3(d0.x + d1.x, 0.0, d0.y + d1.y).normalized()
			_quad(
				_bin_point(centre, d0, r_low, y_low),
				_bin_point(centre, d1, r_low, y_low),
				_bin_point(centre, d1, r_high, y_high),
				_bin_point(centre, d0, r_high, y_high),
				out, skin, SHADE_SIDE
			)
			if y_low >= inner_floor:
				_quad(
					_bin_point(centre, d1, r_low - BIN_WALL, y_low),
					_bin_point(centre, d0, r_low - BIN_WALL, y_low),
					_bin_point(centre, d0, r_high - BIN_WALL, y_high),
					_bin_point(centre, d1, r_high - BIN_WALL, y_high),
					-out, mouth, SHADE_NORTH
				)
	for segment: int in BIN_SEGMENTS:
		var d0: Vector2 = _bin_ray(float(segment) * step)
		var d1: Vector2 = _bin_ray(float(segment + 1) * step)
		_quad(
			_bin_point(centre, d0, lip, high),
			_bin_point(centre, d1, lip, high),
			_bin_point(centre, d1, lip - BIN_WALL, high),
			_bin_point(centre, d0, lip - BIN_WALL, high),
			Vector3.UP, band, SHADE_TOP_FLAT
		)
		_tri(
			_bin_point(centre, d0, foot - BIN_WALL, inner_floor),
			_bin_point(centre, d1, foot - BIN_WALL, inner_floor),
			Vector3(centre.x, inner_floor, centre.y),
			Vector3.UP,
			mouth.position, mouth.end, mouth.position + mouth.size * 0.5,
			SHADE_TOP_FLAT
		)


func _room_faces(tx: int, ty: int, normal: Vector3) -> bool:
	if _room.is_empty():
		return true
	var here: int = _room[ty * _size.x + tx]
	if here == 0:
		return true
	if here == ROOM_DRAWN or here == ROOM_BEHIND:
		return normal.z > 0.0
	if here == ROOM_FILL:
		return true
	if normal.x > 0.0:
		return tx < _margin.x
	if normal.x < 0.0:
		return tx >= _map_end.x
	if normal.z > 0.0:
		return ty < _margin.y
	return ty >= _map_end.y

const STOOL_SEAT: float = 3.0
const STOOL_LEG: float = 5.0
const STOOL_LEG_THICK: float = 2.0
const STOOL_LEG_REACH: float = 0.62
const SQRT_HALF: float = 0.70710678
const STOOL_SEAT_SHARE: float = 0.75
const STOOL_GLINT: float = 0.42
const STOOL_LEG_SHADE: int = 0


func _row_run(mask: PackedByteArray, span: Vector2i, window: Rect2i, py: int) -> int:
	var widest: int = 0
	var run: int = 0
	for px: int in range(window.position.x, window.position.x + window.size.x):
		if _drawn(mask, span, px, py):
			run += 1
			widest = maxi(widest, run)
		else:
			run = 0
	return widest


## A round seat on four splayed legs, built from the drawing's own widest row.
func _object_stool(
	_object: Dictionary, start: Vector2i, across: Vector2i, front: float, tiles: Array,
	mask: PackedByteArray, span: Vector2i, window: Rect2i, atlas: RefCounted
) -> void:
	var wide: int = _stool_width(mask, span, window)
	if wide < 2:
		return
	var base: float = float(_ground_art(start.x, start.y + across.y - 1).y)
	var tile: int = int(tiles[0])
	var radius: float = float(wide) * 0.5
	var left: float = _world_x(start.x) + float(window.position.x) \
		+ (float(window.size.x) - float(wide)) * 0.5
	var back: float = front - float(wide)
	var low: float = base + STOOL_LEG
	_stool_seat(wide, left, back, low, low + STOOL_SEAT, tile, atlas)
	_stool_legs(
		Vector2(left + radius, back + radius), radius, base, low, tile, atlas
	)


## The seat is as wide as the drawing's widest row, and there is only a stool to
## build if a row near that width carries a seat.
func _stool_width(
	mask: PackedByteArray, span: Vector2i, window: Rect2i
) -> int:
	var rows := PackedInt32Array()
	var widest: int = 0
	for py: int in range(window.position.y, window.position.y + window.size.y):
		var run: int = _row_run(mask, span, window, py)
		rows.append(run)
		widest = maxi(widest, run)
	if widest < 2:
		return 0
	var first: int = -1
	var last: int = -1
	for row: int in rows.size():
		if rows[row] <= 0:
			continue
		if first < 0:
			first = row
		if float(rows[row]) >= float(widest) * STOOL_SEAT_SHARE:
			last = row
	return widest if first >= 0 and last >= first else 0


## A disc of unit columns: a lid on each, and a rim wherever the disc ends.
func _stool_seat(
	wide: int, left: float, back: float, low: float, high: float, tile: int,
	atlas: RefCounted
) -> void:
	var radius: float = float(wide) * 0.5
	var rim: Rect2 = _shade_texel(atlas, tile, 1)
	var filled := PackedByteArray()
	filled.resize(wide * wide)
	for j: int in wide:
		for i: int in wide:
			var to_centre := Vector2(float(i) + 0.5 - radius, float(j) + 0.5 - radius)
			filled[j * wide + i] = int(to_centre.length() <= radius - 0.5)
	for j: int in wide:
		for i: int in wide:
			if filled[j * wide + i] == 0:
				continue
			var x0: float = left + float(i)
			var z0: float = back + float(j)
			_quad(
				Vector3(x0, high, z0 + 1.0), Vector3(x0 + 1.0, high, z0 + 1.0),
				Vector3(x0 + 1.0, high, z0), Vector3(x0, high, z0),
				Vector3.UP, _stool_lid(filled, wide, i, j, radius, tile, atlas),
				SHADE_TOP_FLAT
			)
			_stool_rim(filled, wide, i, j, x0, z0, low, high, rim)


## The lid darkens at the disc's edge and catches a highlight near its middle.
func _stool_lid(
	filled: PackedByteArray, wide: int, i: int, j: int, radius: float,
	tile: int, atlas: RefCounted
) -> Rect2:
	if _stool_edge(filled, wide, i, j):
		return _shade_texel(atlas, tile, 0)
	var out: float = Vector2(
		float(i) + 0.5 - radius, float(j) + 0.5 - radius
	).length() / radius
	return _shade_texel(atlas, tile, 3 if out < STOOL_GLINT else 2)


func _stool_edge(filled: PackedByteArray, wide: int, i: int, j: int) -> bool:
	if i == 0 or j == 0 or i + 1 >= wide or j + 1 >= wide:
		return true
	return (
		filled[j * wide + i - 1] == 0 or filled[j * wide + i + 1] == 0
		or filled[(j - 1) * wide + i] == 0 or filled[(j + 1) * wide + i] == 0
	)


func _stool_rim(
	filled: PackedByteArray, wide: int, i: int, j: int, x0: float, z0: float,
	low: float, high: float, rim: Rect2
) -> void:
	if j + 1 >= wide or filled[(j + 1) * wide + i] == 0:
		_quad(
			Vector3(x0, low, z0 + 1.0), Vector3(x0 + 1.0, low, z0 + 1.0),
			Vector3(x0 + 1.0, high, z0 + 1.0), Vector3(x0, high, z0 + 1.0),
			Vector3(0.0, 0.0, 1.0), rim, SHADE_SOUTH
		)
	if j == 0 or filled[(j - 1) * wide + i] == 0:
		_quad(
			Vector3(x0 + 1.0, low, z0), Vector3(x0, low, z0),
			Vector3(x0, high, z0), Vector3(x0 + 1.0, high, z0),
			Vector3(0.0, 0.0, -1.0), rim, SHADE_NORTH
		)
	if i + 1 >= wide or filled[j * wide + i + 1] == 0:
		_quad(
			Vector3(x0 + 1.0, low, z0 + 1.0), Vector3(x0 + 1.0, low, z0),
			Vector3(x0 + 1.0, high, z0), Vector3(x0 + 1.0, high, z0 + 1.0),
			Vector3(1.0, 0.0, 0.0), rim, SHADE_SIDE
		)
	if i == 0 or filled[j * wide + i - 1] == 0:
		_quad(
			Vector3(x0, low, z0), Vector3(x0, low, z0 + 1.0),
			Vector3(x0, high, z0 + 1.0), Vector3(x0, high, z0),
			Vector3(-1.0, 0.0, 0.0), rim, SHADE_SIDE
		)


func _stool_legs(
	centre: Vector2, radius: float, base: float, low: float, tile: int,
	atlas: RefCounted
) -> void:
	var reach: float = radius * STOOL_LEG_REACH
	var half: float = STOOL_LEG_THICK * 0.5
	for corner: Vector2 in [
		Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)
	]:
		var at := Vector2(
			centre.x + corner.x * reach * SQRT_HALF,
			centre.y + corner.y * reach * SQRT_HALF
		)
		_box(
			at.x - half, at.x + half, base, low, at.y - half, at.y + half,
			_shade_texel(atlas, tile, STOOL_LEG_SHADE)
		)

const TERMINAL_DESK: float = 12.0
const TERMINAL_DESK_DEEP: float = 12.0
const TERMINAL_SCREEN: float = 16.0
const TERMINAL_SCREEN_DEEP: float = 8.0
const TERMINAL_KEYS_OUT: float = 2.0
const TERMINAL_KEYS_DEEP: float = 6.0
const TERMINAL_KEYS_THICK: float = 2.0
const TERMINAL_KEYS_INSET: float = 2.0
const TERMINAL_SCREEN_INSET: float = 2.0


func _object_terminal(
	object: Dictionary, start: Vector2i, across: Vector2i, front: float, tiles: Array,
	mask: PackedByteArray, span: Vector2i, window: Rect2i, atlas: RefCounted
) -> void:
	var base: float = _object_base(object, start, across)
	var left: float = _world_x(start.x) + float(window.position.x)
	var right: float = left + float(window.size.x)
	var desk_back: float = front - TERMINAL_DESK_DEEP
	var desk_top: float = base + TERMINAL_DESK
	var screen_top: float = desk_top + TERMINAL_SCREEN
	var screen_back: float = front - TERMINAL_SCREEN_DEEP
	var screen_front: float = front + 0.01
	var wood: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y + 16, window.position.y + window.size.y
	)
	var case: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y, window.position.y + 8
	)
	_box(left, right, base, desk_top, desk_back, front, wood)
	_lid(left, right, desk_top, desk_back, front, wood)
	_box(
		left + TERMINAL_SCREEN_INSET, right - TERMINAL_SCREEN_INSET,
		desk_top, screen_top, screen_back, front, case
	)
	_lid(
		left + TERMINAL_SCREEN_INSET, right - TERMINAL_SCREEN_INSET,
		screen_top, screen_back, front, case
	)
	var inset: int = int(TERMINAL_SCREEN_INSET)
	for row: int in 2:
		for column: int in across.x:
			var tile: int = int(tiles[row * across.x + column])
			var cut := Rect2i(0, 0, int(TILE), int(TILE))
			if column == 0:
				cut.position.x = inset
				cut.size.x -= inset
			if column == across.x - 1:
				cut.size.x -= inset
			if cut.size.x <= 0:
				continue
			var x0: float = left + float(column) * TILE + float(cut.position.x)
			var high: float = screen_top - float(row) * TILE
			_quad(
				Vector3(x0, high - TILE, screen_front),
				Vector3(x0 + float(cut.size.x), high - TILE, screen_front),
				Vector3(x0 + float(cut.size.x), high, screen_front),
				Vector3(x0, high, screen_front),
				Vector3(0.0, 0.0, 1.0), atlas.uv_box(tile, cut), SHADE_SOUTH
			)
	var keys_front: float = front + TERMINAL_KEYS_OUT
	var keys_back: float = keys_front - TERMINAL_KEYS_DEEP
	var keys_low: float = desk_top - TERMINAL_KEYS_THICK
	_box(
		left + TERMINAL_KEYS_INSET, right - TERMINAL_KEYS_INSET,
		keys_low, desk_top, keys_back, keys_front, wood
	)
	for column: int in across.x:
		var tile: int = int(tiles[2 * across.x + column])
		var x0: float = maxf(left + float(column) * TILE, left + TERMINAL_KEYS_INSET)
		var x1: float = minf(x0 + TILE, right - TERMINAL_KEYS_INSET)
		if x1 <= x0:
			continue
		_quad(
			Vector3(x0, desk_top + 0.01, keys_front),
			Vector3(x1, desk_top + 0.01, keys_front),
			Vector3(x1, desk_top + 0.01, keys_back),
			Vector3(x0, desk_top + 0.01, keys_back),
			Vector3.UP,
			atlas.uv_box(tile, Rect2i(0, 3, int(TILE), 5)), SHADE_TOP_FLAT
		)

const SEAT_HIGH: float = 8.0
const SEAT_SLAB: float = 2.0
const SEAT_BACK: float = 9.0
const SEAT_BACK_THICK: float = 2.0
const SEAT_LEG_THICK: float = 3.0


func _object_seat(
	object: Dictionary, start: Vector2i, across: Vector2i, front: float, tiles: Array,
	mask: PackedByteArray, span: Vector2i, window: Rect2i, atlas: RefCounted
) -> void:
	var base: float = float(_ground_art(start.x, start.y + across.y - 1).y)
	var left: float = _world_x(start.x) + float(window.position.x)
	var right: float = left + float(window.size.x)
	var deep: float = float(object.get(&"depth", 13))
	var near: float = front
	var far: float = front - deep
	var top: int = window.position.y
	var back_uv: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window, top, top + int(TILE)
	)
	var seat_uv: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window, top + int(TILE), top + int(TILE) * 2
	)
	var leg_uv: Rect2 = _shade_texel(atlas, int(tiles[0]), 0)

	var seat_top: float = base + SEAT_HIGH
	var seat_low: float = seat_top - SEAT_SLAB
	_box(left, right, seat_low, seat_top, far, near, seat_uv)
	_quad(
		Vector3(left, seat_top, near), Vector3(right, seat_top, near),
		Vector3(right, seat_top, far), Vector3(left, seat_top, far),
		Vector3.UP, seat_uv, SHADE_TOP_FLAT
	)

	var back_top: float = seat_top + SEAT_BACK
	_box(left, right, seat_top, back_top, far, far + SEAT_BACK_THICK, back_uv)
	_quad(
		Vector3(left, back_top, far + SEAT_BACK_THICK),
		Vector3(right, back_top, far + SEAT_BACK_THICK),
		Vector3(right, back_top, far), Vector3(left, back_top, far),
		Vector3.UP, back_uv, SHADE_TOP_FLAT
	)

	for edge: float in [left, right - SEAT_LEG_THICK]:
		_box(
			edge, edge + SEAT_LEG_THICK, base, seat_low,
			far, far + SEAT_LEG_THICK, leg_uv
		)
		_box(
			edge, edge + SEAT_LEG_THICK, base, seat_low,
			near - SEAT_LEG_THICK, near, leg_uv
		)


func _box(
	x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, uv: Rect2
) -> void:
	_quad(
		Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1),
		Vector3(x0, y1, z1), Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
	)
	_quad(
		Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0),
		Vector3(x1, y1, z0), Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
	)
	_quad(
		Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0),
		Vector3(x1, y1, z1), Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
	)
	_quad(
		Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1),
		Vector3(x0, y1, z0), Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
	)


func _lid(
	x0: float, x1: float, y: float, z0: float, z1: float, uv: Rect2
) -> void:
	_quad(
		Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0),
		Vector3.UP, uv, SHADE_TOP_FLAT
	)


func _shade_texel(atlas: RefCounted, tile: int, rank: int) -> Rect2:
	var order: PackedInt32Array = atlas.shade_order(tile)
	if order.is_empty():
		return atlas.uv(tile)
	var want: int = order[clampi(rank, 0, order.size() - 1)]
	for py: int in int(TILE):
		for px: int in int(TILE):
			if atlas.pixel(tile, px, py) == want:
				return atlas.uv_box(tile, Rect2i(px, py, 1, 1))
	return atlas.uv(tile)


func _bin_ray(angle: float) -> Vector2:
	return Vector2(sin(angle), cos(angle))


func _bin_point(centre: Vector2, ray: Vector2, radius: float, y: float) -> Vector3:
	var reach: float = maxf(radius, 0.0)
	return Vector3(centre.x + ray.x * reach, y, centre.y + ray.y * reach)


func _bin_half(
	mask: PackedByteArray, span: Vector2i, window: Rect2i, py: int
) -> float:
	var first: int = -1
	var last: int = -1
	for px: int in range(window.position.x, window.position.x + window.size.x):
		if not _drawn(mask, span, px, py):
			continue
		if first < 0:
			first = px
		last = px
	if first < 0:
		return 0.0
	return float(last + 1 - first) * 0.5


func _bin_texel(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, from_row: int, to_row: int, besides: int
) -> Rect2:
	var counts: Dictionary = {}
	var spot: Dictionary = {}
	_bin_tally(
		atlas, tiles, across, mask, span, window, from_row, to_row, counts, spot
	)
	var best: int = _bin_best(counts, besides)
	if best < 0:
		return atlas.uv(int(tiles[0]))
	var at: Array = spot[best]
	return atlas.uv_box(int(at[0]), Rect2i(int(at[1]), int(at[2]), 1, 1))


func _bin_index(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, from_row: int, to_row: int, besides: int
) -> int:
	var counts: Dictionary = {}
	var spot: Dictionary = {}
	_bin_tally(
		atlas, tiles, across, mask, span, window, from_row, to_row, counts, spot
	)
	return _bin_best(counts, besides)


func _bin_tally(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, from_row: int, to_row: int,
	counts: Dictionary, spot: Dictionary
) -> void:
	for py: int in range(from_row, to_row):
		for px: int in range(window.position.x, window.position.x + window.size.x):
			if not _drawn(mask, span, px, py):
				continue
			@warning_ignore("integer_division")
			var tile: int = int(tiles[(py / int(TILE)) * across.x + px / int(TILE)])
			var index: int = atlas.pixel(tile, px % int(TILE), py % int(TILE))
			if index < 0:
				continue
			counts[index] = int(counts.get(index, 0)) + 1
			if not spot.has(index):
				spot[index] = [tile, px % int(TILE), py % int(TILE)]


func _bin_best(counts: Dictionary, besides: int) -> int:
	var best: int = -1
	for index: int in counts:
		if index == besides:
			continue
		if best < 0 or int(counts[index]) > int(counts[best]):
			best = index
	return best


func _drawn_rows(
	mask: PackedByteArray, span: Vector2i, window: Rect2i, from_row: int, to_row: int
) -> Vector2i:
	var first: int = -1
	var last: int = -1
	for py: int in range(from_row, to_row):
		for px: int in range(window.position.x, window.position.x + window.size.x):
			if not _drawn(mask, span, px, py):
				continue
			if first < 0:
				first = py
			last = py
			break
	if first < 0:
		return Vector2i(from_row, to_row)
	return Vector2i(first, last + 1)


func _face_runs(
	tiles: Array, across: Vector2i, mask: PackedByteArray, span: Vector2i,
	window: Rect2i, py: int
) -> Array:
	var runs: Array = []
	var px: int = window.position.x
	while px < window.position.x + window.size.x:
		if not _drawn(mask, span, px, py):
			px += 1
			continue
		var stop: int = mini(
			(px / int(TILE) + 1) * int(TILE), window.position.x + window.size.x
		)
		var run: int = px
		while run < stop and _drawn(mask, span, run, py):
			run += 1
		@warning_ignore("integer_division")
		runs.append([px, run, int(tiles[(py / int(TILE)) * across.x + px / int(TILE)])])
		px = run
	return runs


func _object_wrap(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, face_from: int, face_rows: int,
	left: float, right: float, front: float, back: float,
	base: float, high: float, ends: Rect2
) -> void:
	if face_rows <= 0:
		return
	var tall: float = high - base
	var window_left: int = window.position.x
	var window_right: int = window.position.x + window.size.x
	var deep: int = int(roundf(front - back))
	var plain: bool = ends.size != Vector2.ZERO
	if plain:
		_quad(
			Vector3(right, base, front), Vector3(right, base, back),
			Vector3(right, high, back), Vector3(right, high, front),
			Vector3(1.0, 0.0, 0.0), ends, SHADE_SIDE
		)
		_quad(
			Vector3(left, base, back), Vector3(left, base, front),
			Vector3(left, high, front), Vector3(left, high, back),
			Vector3(-1.0, 0.0, 0.0), ends, SHADE_SIDE
		)
	for row: int in face_rows:
		var py: int = face_from + row
		var high_y: float = high - tall * float(row) / float(face_rows)
		var low_y: float = high - tall * float(row + 1) / float(face_rows)
		for entry: Array in _face_runs(tiles, across, mask, span, window, py):
			var px: int = int(entry[0])
			var run: int = int(entry[1])
			var tile: int = int(entry[2])
			var uv: Rect2 = atlas.uv_box(
				tile, Rect2i(px % int(TILE), py % int(TILE), run - px, 1)
			)
			var x0: float = left + float(px - window_left)
			var x1: float = left + float(run - window_left)
			_quad(
				Vector3(x1, low_y, back), Vector3(x0, low_y, back),
				Vector3(x0, high_y, back), Vector3(x1, high_y, back),
				Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
			)
			if plain:
				continue
			var west_from: int = maxi(px, window_left)
			var west_to: int = mini(run, window_left + deep)
			if west_to > west_from:
				var wz0: float = front - float(west_from - window_left)
				var wz1: float = front - float(west_to - window_left)
				_quad(
					Vector3(left, low_y, wz1), Vector3(left, low_y, wz0),
					Vector3(left, high_y, wz0), Vector3(left, high_y, wz1),
					Vector3(-1.0, 0.0, 0.0),
					atlas.uv_box(tile, Rect2i(
						west_from % int(TILE), py % int(TILE), west_to - west_from, 1
					)),
					SHADE_SIDE
				)
			var east_from: int = maxi(px, window_right - deep)
			var east_to: int = mini(run, window_right)
			if east_to > east_from:
				var ez0: float = front - float(window_right - east_to)
				var ez1: float = front - float(window_right - east_from)
				_quad(
					Vector3(right, low_y, ez1), Vector3(right, low_y, ez0),
					Vector3(right, high_y, ez0), Vector3(right, high_y, ez1),
					Vector3(1.0, 0.0, 0.0),
					atlas.uv_box(tile, Rect2i(
						east_from % int(TILE), py % int(TILE), east_to - east_from, 1
					)),
					SHADE_SIDE
				)


func _object_cap(
	atlas: RefCounted, tiles: Array, across: Vector2i, mask: PackedByteArray,
	span: Vector2i, window: Rect2i, rows: int,
	left: float, _right: float, high: float, front: float, back: float
) -> void:
	var deep: float = front - back
	var blank: Rect2 = _object_texel(
		atlas, tiles, across, mask, span, window,
		window.position.y, window.position.y + window.size.y
	)
	var course: float = 0.0
	while course < deep:
		var cut: float = minf(float(rows), deep - course)
		for row: int in rows:
			if float(row) >= cut:
				break
			var py: int = window.position.y + row
			var px: int = window.position.x
			while px < window.position.x + window.size.x:
				var stop: int = mini(
					(px / int(TILE) + 1) * int(TILE),
					window.position.x + window.size.x
				)
				var here: bool = _drawn(mask, span, px, py)
				var run: int = px
				while run < stop and _drawn(mask, span, run, py) == here:
					run += 1
				@warning_ignore("integer_division")
				var tile: int = int(tiles[(py / int(TILE)) * across.x + px / int(TILE)])
				var uv: Rect2 = blank
				if here:
					uv = atlas.uv_box(
						tile, Rect2i(px % int(TILE), py % int(TILE), run - px, 1)
					)
				var near: float = back + course + float(row) + 1.0
				var far: float = back + course + float(row)
				var x0: float = left + float(px - window.position.x)
				var x1: float = left + float(run - window.position.x)
				_quad(
					Vector3(x0, high, near), Vector3(x1, high, near),
					Vector3(x1, high, far), Vector3(x0, high, far),
					Vector3.UP, uv, SHADE_TOP_FLAT
				)
				px = run
		course += float(rows)


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
	if bool(object.get(&"whole", false)):
		for pixel: int in body.size():
			if body[pixel] >= 0:
				body[pixel] = 0
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
	var ground: float = _object_base(object, start, across)
	for group: int in counts:
		if int(counts[group]) < MODEL_BODY_MIN:
			continue
		var key: String = "%s:%s#%d" % [str(object[&"name"]), str(tiles), group]
		if not _model_meshes.has(key):
			var only := PackedByteArray()
			only.resize(mask.size())
			for pixel: int in body.size():
				only[pixel] = int(body[pixel] == group)
			var measured: RefCounted = Model.measure(only, span, tiles, across, atlas)
			measured.shrub = bool(object.get(&"shrub", true))
			measured.rock = bool(object.get(&"rock", true))
			var drawn_rows: int = int((bounds[group] as Rect2i).size.y)
			if drawn_rows > 0:
				measured.stretch = float(object[&"height"]) / float(drawn_rows)
			_model_meshes[key] = _model_mesh_of(measured)
			_model_spots[key] = {}
			_built_model = true
		var middle: Vector2 = Vector2((bounds[group] as Rect2i).get_center())
		var placed: Array = [
			Transform3D(Basis(), Vector3(
				_world_x(start.x) + middle.x, ground, _world_z(start.y) + middle.y
			)),
			0.0,
			_model_chunk(start),
		]
		(_model_spots[key] as Dictionary)[str(start)] = placed
		_chunk_spots.append([key, str(start), placed])

const HOUSE_BODY_MIN: int = 32


func _house_plan(house: Dictionary) -> Array:
	var id: int = int(house.get("id", -1))
	if _house_plans.has(id):
		return _house_plans[id]
	var paint: Array = house["paint"]
	var rows: int = paint.size()
	var cols: int = String(paint[0]).length()
	var owner: PackedInt32Array = _house_flood(_house_mask(paint, Houses.WALL), cols)
	var terrace: PackedInt32Array = _house_flood(_house_mask(paint, ""), cols)
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


## One byte a pixel, 1 where the paint answers the word, so the flood reads a
## byte rather than indexing a string once a neighbour. An empty word is any
## stroke at all.
func _house_mask(paint: Array, word: String) -> PackedByteArray:
	var blank: int = Houses.NONE.unicode_at(0)
	var want: int = -1 if word.is_empty() else word.unicode_at(0)
	var mask := PackedByteArray()
	for line: String in paint:
		var bytes: PackedByteArray = line.to_ascii_buffer()
		for at: int in bytes.size():
			var painted: bool = bytes[at] != blank if want < 0 else bytes[at] == want
			bytes[at] = 1 if painted else 0
		mask.append_array(bytes)
	return mask


@warning_ignore("integer_division")
func _house_flood(mask: PackedByteArray, cols: int) -> PackedInt32Array:
	var owner := PackedInt32Array()
	owner.resize(mask.size())
	owner.fill(-1)
	var steps := PackedInt32Array([-cols, cols, -1, 1])
	var bodies: int = 0
	var stack := PackedInt32Array()
	for start: int in mask.size():
		if owner[start] >= 0 or mask[start] == 0:
			continue
		owner[start] = bodies
		stack.push_back(start)
		while not stack.is_empty():
			var at: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			for step: int in steps:
				var next: int = at + step
				if next < 0 or next >= mask.size() or owner[next] >= 0 \
						or mask[next] == 0:
					continue
				var sideways: bool = absi(step) == 1
				if sideways and next / cols != at / cols:
					continue
				owner[next] = bodies
				stack.push_back(next)
		bodies += 1
	return owner


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


func _house_carry(
	from: PackedInt32Array, to: PackedInt32Array, left: int, right: int
) -> void:
	var last: int = -1
	for x: int in range(left, right + 1):
		if from[x] < 0:
			continue
		if last >= 0:
			for gap: int in range(last + 1, x):
				var near: int = last if gap - last <= x - gap else x
				from[gap] = from[near]
				to[gap] = to[near]
		last = x


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
	var box: Vector4i = _house_extent(cols, rows, owner, terrace, body, walls, tops)
	if box.y < 0:
		return {}
	var left: int = box.x
	var right: int = box.y
	var foot: int = _house_foot(walls, box.z)
	var gap: int = int(foot + 1 < rows and walls[foot + 1] * 2 < walls[foot])
	var reach: Vector2i = _house_roof_rows(
		paint, rows, left, right, tops, eave_from, eave_to, cap_from, cap_to
	)
	var top_row: int = reach.x
	var peak: int = reach.y
	_house_carry(cap_from, cap_to, left, right)
	var rival: PackedInt32Array = _house_rivals(rows, cols, owner, terrace, body, box.w)
	var cover: Vector2i = _house_reach(
		paint, rows, cols, rival, tops, left, right, Vector2i(top_row, peak - 1)
	)
	var ridge: Vector2i = _house_ridge(tops, left, right, peak)
	return {
		"rows": rows, "cols": cols, "foot": foot, "gap": gap,
		"left": left, "right": right,
		"cover_left": cover.x, "cover_right": cover.y,
		"top_row": top_row, "north_row": maxi(top_row + gap, foot + 1 - (right + 1 - left)),
		"south_row": foot + 1,
		"tops": tops, "eave_from": eave_from, "eave_to": eave_to,
		"cap_from": cap_from, "cap_to": cap_to, "m0": ridge.x, "m1": ridge.y,
		"peak_rise": float(foot + 1 - peak),
		"left_rise": float(foot + 1 - tops[left]),
		"right_rise": float(foot + 1 - tops[right]),
		"thick": _house_thick(eave_from, eave_to, left, right, ridge.x),
	}


## The body's own box as left, right, bottom and terrace group, filling in the
## wall count per row and the first wall row per column on the way.
func _house_extent(
	cols: int, rows: int, owner: PackedInt32Array, terrace: PackedInt32Array,
	body: int, walls: PackedInt32Array, tops: PackedInt32Array
) -> Vector4i:
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
	return Vector4i(left, right, bottom, group)


## The bottom row of the wall proper: a row holding less than half the row above
## it is the ground the house stands on rather than more house.
func _house_foot(walls: PackedInt32Array, bottom: int) -> int:
	var foot: int = bottom
	while foot > 0 and (walls[foot] == 0 or walls[foot] * 2 < walls[foot - 1]):
		foot -= 1
	return foot


## Above each wall column: a run of front-facing roof, then a run of roof seen
## from above. Answers the highest drawn row and the highest wall row.
## Above each wall column: a run of front-facing roof, then a run of roof seen
## from above. Answers the highest drawn row and the highest wall row.
func _house_roof_rows(
	paint: Array, rows: int, left: int, right: int, tops: PackedInt32Array,
	eave_from: PackedInt32Array, eave_to: PackedInt32Array,
	cap_from: PackedInt32Array, cap_to: PackedInt32Array
) -> Vector2i:
	var peak: int = rows
	var top_row: int = rows
	for x: int in range(left, right + 1):
		if tops[x] < 0:
			continue
		peak = mini(peak, tops[x])
		top_row = mini(top_row, tops[x])
		var y: int = _house_paint_run(
			paint, tops[x] - 1, x, Houses.FRONT, eave_from, eave_to
		)
		y = _house_paint_run(paint, y, x, Houses.ROOF, cap_from, cap_to)
		if cap_from[x] >= 0:
			top_row = mini(top_row, cap_from[x])
		elif eave_from[x] >= 0:
			top_row = mini(top_row, eave_from[x])
	return Vector2i(top_row, peak)


## Walks up one column while the paint reads `stroke`, recording the run's top
## and bottom. Answers the first row that does not.
func _house_paint_run(
	paint: Array, from: int, x: int, stroke: String,
	first: PackedInt32Array, last: PackedInt32Array
) -> int:
	var y: int = from
	while y >= 0 and paint[y][x] == stroke:
		first[x] = y
		if last[x] < 0:
			last[x] = y
		y -= 1
	return y


## How many columns each column is from another body on the same terrace, so a
## roof knows how far it may oversail before it reaches its neighbour.
func _house_rivals(
	rows: int, cols: int, owner: PackedInt32Array, terrace: PackedInt32Array,
	body: int, group: int
) -> PackedInt32Array:
	var rival := PackedInt32Array()
	rival.resize(cols)
	rival.fill(cols * 2)
	for x: int in cols:
		for y: int in rows:
			var at: int = y * cols + x
			if terrace[at] == group and owner[at] >= 0 and owner[at] != body:
				rival[x] = 0
	for x: int in range(1, cols):
		rival[x] = mini(rival[x], rival[x - 1] + 1)
	for x: int in range(cols - 2, -1, -1):
		rival[x] = mini(rival[x], rival[x + 1] + 1)
	return rival


## The run of columns standing at the highest row, which is the ridge.
func _house_ridge(
	tops: PackedInt32Array, left: int, right: int, peak: int
) -> Vector2i:
	var m0: int = right + 1
	var m1: int = -1
	for x: int in range(left, right + 1):
		if tops[x] == peak:
			m0 = mini(m0, x)
			m1 = maxi(m1, x)
	return Vector2i(m0, m1) if m1 >= 0 else Vector2i(left, right)


## The eave's thickness in rows: the ridge column's own, else the commonest over
## the body, taking the taller where two are as common.
func _house_thick(
	eave_from: PackedInt32Array, eave_to: PackedInt32Array,
	left: int, right: int, ridge: int
) -> int:
	if eave_to[ridge] >= 0:
		return eave_to[ridge] - eave_from[ridge] + 1
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
	return best


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


func _house_lid(
	tiles: Array, across: Vector2i, plan: Dictionary, origin_x: float,
	base: float, near: float, far: float, atlas: RefCounted
) -> void:
	var tops: PackedInt32Array = plan["tops"]
	var left: int = int(plan["left"])
	var right: int = int(plan["right"])
	var column: int = left
	while column <= right:
		var top: int = tops[column]
		if top < 0:
			column += 1
			continue
		var run: int = 1
		while column + run <= right:
			if (column + run) / TILE_PX != column / TILE_PX \
					or tops[column + run] != top:
				break
			run += 1
		@warning_ignore("integer_division")
		var tile: int = int(tiles[(top / TILE_PX) * across.x + column / TILE_PX])
		var uv: Rect2 = atlas.uv_box(
			tile, Rect2i(column % TILE_PX, top % TILE_PX, run, 1)
		)
		var y_west: float = base + _house_rise(plan, float(column))
		var y_east: float = base + _house_rise(plan, float(column + run))
		var x0: float = origin_x + float(column)
		var x1: float = origin_x + float(column + run)
		_quad(
			Vector3(x0, y_west, near), Vector3(x1, y_east, near),
			Vector3(x1, y_east, far), Vector3(x0, y_west, far),
			Vector3.UP, uv, SHADE_TOP_FLAT
		)
		column += run


func _emit_house(index: int, atlas: RefCounted) -> void:
	var entry: Array = _houses[index]
	var start: Vector2i = entry[1]
	var across: Vector2i = entry[2]
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	for plan: Dictionary in _house_chosen(entry):
		_emit_house_body(plan, tiles, start, across, entry[3], atlas)


func _house_chosen(entry: Array) -> Array:
	var plans: Array = _house_plan(entry[0])
	var out: Array = []
	for index: int in entry[4] as PackedInt32Array:
		if index >= 0 and index < plans.size():
			out.append(plans[index])
	return out


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
		_house_lid(tiles, across, plan, origin_x, base, south, north, atlas)
		return

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


func _emit_stairs(index: int, atlas: RefCounted) -> void:
	var entry: Array = _stairs[index]
	var flight: Dictionary = entry[0]
	var start: Vector2i = entry[1]
	var base: float = float(entry[2])
	var down: bool = bool(flight[&"down"])
	var across: Vector2i = entry[3]
	var steps: int = int(flight.get(&"steps", STAIR_STEPS))
	var climb: int = int(flight.get(&"rise", STAIR_RISE))
	if flight.has(&"corner"):
		_emit_stair_corner(
			start, base, flight[&"corner"], across, steps, climb, atlas
		)
		return
	var step: Vector2i = flight[&"step"]
	var run: int = (across.x if step.x != 0 else across.y) * int(TILE)
	var rise: float = float(climb) / float(steps)
	var tread_deep: float = float(run) / float(steps)
	if not down:
		_stair_head(start, base, step, across, climb, atlas)
	for tread: int in steps:
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
			if not down:
				_stair_flank(
					step, base, height, piece, box,
					Vector2(x0, z0), Vector2(x1, z1), uv
				)
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


func _emit_stair_corner(
	start: Vector2i, base: float, corner: Vector2i, across: Vector2i,
	steps: int, climb: int, atlas: RefCounted
) -> void:
	var span: int = mini(across.x, across.y) * int(TILE)
	var rise: float = float(climb) / float(steps)
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
		_stair_corner_riser(
			start, corner, span, true, low, span, top - rise, top, atlas
		)
		_stair_corner_riser(
			start, corner, span, false, low, span, top - rise, top, atlas
		)


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


func _stair_corner_riser(
	start: Vector2i, corner: Vector2i, span: int, along_u: bool,
	at: int, until: int, low: float, high: float, atlas: RefCounted
) -> void:
	var plane: int = at if (corner.x > 0 if along_u else corner.y > 0) else span - at
	var inward: int = plane if (corner.x > 0 if along_u else corner.y > 0) else plane - 1
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


func _stair_head(
	start: Vector2i, base: float, step: Vector2i, across: Vector2i, climb: int,
	atlas: RefCounted
) -> void:
	var edge: int = int(TILE)
	var run: int = (across.x if step.x != 0 else across.y) * edge
	var wide: int = (across.y if step.x != 0 else across.x)
	var high: float = base + float(climb)
	for piece: int in wide:
		var along: int = piece * edge
		var tile: int = _tile_at(
			start.x + _stair_offset(step.x, across.x, piece),
			start.y + _stair_offset(step.y, across.y, piece)
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


func _cutout(
	tx: int, ty: int, depth: float, round_plan: bool, filled: bool, outline: int,
	base: float, ground_tile: int, atlas: RefCounted
) -> void:
	var at: int = ty * _size.x + tx
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
		"%s,%d,%d" % [key, int(round_plan), roundi(depth)]
	)

	var edge: int = int(TILE)
	var tile: int = _tiles[at]
	var origin := Vector2i(tx - start.x, ty - start.y) * edge

	var mid: float = 0.0
	var top: float = 0.0
	if _lying[at] == 1:
		mid = _world_z((ty >> 1) * CELL_TILES) + CELL_TILES * TILE * 0.5
		top = CELL_TILES * TILE - float((ty & 1) * edge)
	else:
		mid = _world_z(((start.y + across.y - 1) >> 1) * CELL_TILES) \
			+ CELL_TILES * TILE * 0.5
		var foot: int = across.y
		while foot > 1 and not _row_holds(start, foot - 1, across.x, _klass[at]):
			foot -= 1
		top = float(foot * int(TILE) - origin.y)

	_carve_base = base + float(_stem_rise[at])
	_carve_lift = _stretch[at] if _stretch[at] > 0.0 else 1.0

	var swaying: bool = _swaying[at] == 1
	if swaying:
		_sink = SINK_TUFT
		_sink_uv2 = Vector2(0.0, _hash_spot(Vector2i(tx, ty)))
		_tuft_foot = base
		_tuft_span = maxf(_carve_y(top) - base, 1.0)

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
	if swaying:
		_sink = SINK_TERRAIN


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


func _stem_shade(row: int, tall: int, greens: int) -> int:
	var up: float = float(tall - 1 - row) / float(maxi(tall - 1, 1))
	return clampi(int(up * float(greens)), 0, greens - 1)


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


func _carve_y(rows: float) -> float:
	return _carve_base + rows * _carve_lift

var _carve_base: float = 0.0
var _carve_lift: float = 1.0


func _drawn(mask: PackedByteArray, span: Vector2i, px: int, py: int) -> bool:
	if px < 0 or py < 0 or px >= span.x or py >= span.y:
		return false
	return mask[py * span.x + px] == 1

const INTERIOR_REACH: int = 3


func _interior(mask: PackedByteArray, span: Vector2i, px: int, py: int) -> bool:
	return (
		_drawn(mask, span, px, py)
		and _drawn(mask, span, px - 1, py) and _drawn(mask, span, px + 1, py)
		and _drawn(mask, span, px, py - 1) and _drawn(mask, span, px, py + 1)
	)


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

	for horizontal: bool in [true, false]:
		for near: bool in [true, false]:
			var run: int = -1
			var length: int = box.size.x if horizontal else box.size.y
			for step: int in length + 1:
				var open: bool = false
				if step < length:
					var side: int = box.size.y - 1 if horizontal else box.size.x - 1
					var across: int = 0 if near else side
					var outward: int = -1 if near else 1
					var at := origin + box.position
					var beyond := Vector2i.ZERO
					if horizontal:
						at += Vector2i(step, across)
						beyond = at + Vector2i(0, outward)
					else:
						at += Vector2i(across, step)
						beyond = at + Vector2i(outward, 0)
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
		var sample: int = box.position.y + (0 if near else box.size.y - 1)
		if box.size.y > 1:
			sample += 1 if near else -1
		if near:
			var walk_column: int = box.position.x + from
			for _step: int in INTERIOR_REACH:
				if _interior(mask, span, origin.x + walk_column, origin.y + sample):
					break
				if not _drawn(mask, span, origin.x + walk_column, origin.y + sample + 1):
					break
				sample += 1
		var strip: Rect2 = atlas.uv_box(tile, Rect2i(box.position.x + from, sample, to - from, 1))
		if near:
			_quad(
				Vector3(x0, y, front), Vector3(x1, y, front),
				Vector3(x1, y, back), Vector3(x0, y, back),
				Vector3.UP, strip, SHADE_TOP_VOLUME
			)
		else:
			_quad(
				Vector3(x0, y, back), Vector3(x1, y, back),
				Vector3(x1, y, front), Vector3(x0, y, front),
				Vector3.DOWN, strip, SHADE_NORTH
			)
		return

	var x: float = _world_x(tx) + float(box.position.x + (0 if near else box.size.x))
	var high: float = _carve_y(top - float(box.position.y + from))
	var low: float = _carve_y(top - float(box.position.y + to))
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
const RAIL_RUN: int = 6


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

const BALL_VOXELS: int = 8


func _ball(tx: int, ty: int, ground: float, atlas: RefCounted) -> void:
	var tile: int = _tile_at(tx, ty)
	var shades: int = maxi(atlas.shade_order(tile).size(), 1)
	var radius: float = float(BALL_VOXELS) * 0.5
	var origin_x: float = _world_x(tx) + (TILE - float(BALL_VOXELS)) * 0.5
	var origin_z: float = _world_z(ty) + (TILE - float(BALL_VOXELS)) * 0.5
	for vy: int in BALL_VOXELS:
		@warning_ignore("integer_division")
		var uv: Rect2 = _shade_texel(atlas, tile, vy * shades / BALL_VOXELS)
		var y0: float = ground + float(vy)
		var y1: float = y0 + 1.0
		for vz: int in BALL_VOXELS:
			var z0: float = origin_z + float(vz)
			var z1: float = z0 + 1.0
			for vx: int in BALL_VOXELS:
				if not _in_ball(vx, vy, vz, radius):
					continue
				var x0: float = origin_x + float(vx)
				var x1: float = x0 + 1.0
				if not _in_ball(vx, vy, vz + 1, radius):
					_quad(
						Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1),
						Vector3(x0, y1, z1), Vector3(0.0, 0.0, 1.0), uv, SHADE_SOUTH
					)
				if not _in_ball(vx, vy, vz - 1, radius):
					_quad(
						Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0),
						Vector3(x1, y1, z0), Vector3(0.0, 0.0, -1.0), uv, SHADE_NORTH
					)
				if not _in_ball(vx + 1, vy, vz, radius):
					_quad(
						Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0),
						Vector3(x1, y1, z1), Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
					)
				if not _in_ball(vx - 1, vy, vz, radius):
					_quad(
						Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1),
						Vector3(x0, y1, z0), Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
					)
				if not _in_ball(vx, vy + 1, vz, radius):
					_quad(
						Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0),
						Vector3(x0, y1, z0), Vector3.UP, uv, SHADE_TOP_FLAT
					)
				if vy > 0 and not _in_ball(vx, vy - 1, vz, radius):
					_quad(
						Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1),
						Vector3(x0, y0, z1), Vector3.DOWN, uv, SHADE_NORTH
					)


func _in_ball(vx: int, vy: int, vz: int, radius: float) -> bool:
	var dx: float = float(vx) + 0.5 - radius
	var dy: float = float(vy) + 0.5 - radius
	var dz: float = float(vz) + 0.5 - radius
	return dx * dx + dy * dy + dz * dz <= radius * radius


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


## The far row along a step's own axis, the near row against it, and the piece's
## own place across it.
func _stair_offset(step: int, across: int, piece: int) -> int:
	if step > 0:
		return across - 1
	return 0 if step < 0 else piece


func _tile_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return 0
	return maxi(_tiles[ty * _size.x + tx], 0)


## The floor a drawing stands on: what a house or an apron released here, else
## the nearest flat ground beside it, else the tile's own art.
func _ground_art(tx: int, ty: int) -> Vector2i:
	var at: int = ty * _size.x + tx
	var released: Vector2i = _house_ground.get(at, Vector2i(-1, 0))
	if released.x >= 0:
		return released
	released = _floor_art.get(at, Vector2i(-1, 0))
	if released.x >= 0:
		return released
	var beside: Vector2i = _floor_beside_ring(tx, ty)
	if beside.x >= 0:
		return beside
	var named: int = _ground_tile_at(at)
	if named >= 0:
		return Vector2i(named, 0)
	if _covered_at(at):
		var along: Vector2i = _released_ground.get(at, Vector2i(-1, 0))
		if along.x < 0:
			along = _floor_along_row(tx, ty)
			if along.x >= 0:
				_released_ground[at] = along
		if along.x >= 0:
			return along
	return Vector2i(maxi(_tiles[at], 0), 0)


## Flat ground one tile out, then two. A stair or a ramp in a direction stops
## that direction being looked down any further: its floor is not this floor.
func _floor_beside_ring(tx: int, ty: int) -> Vector2i:
	var blocked: Dictionary = {}
	for ring: int in [1, 2]:
		for way: Vector2i in STEPS:
			if ring > 1 and blocked.has(way):
				continue
			var index: int = _index(tx + way.x * ring, ty + way.y * ring)
			if index < 0:
				continue
			if _stair_at[index] >= 0 or _ramp[index] == 1:
				blocked[way] = true
				continue
			if _art[index] == ART_FLAT and _heights[index] >= 0:
				return _floor_art.get(
					index, Vector2i(maxi(_tiles[index], 0), _heights[index])
				)
	return Vector2i(-1, 0)


func _covered_at(at: int) -> bool:
	if not _house_covered.is_empty() and _house_covered[at] == 1:
		return true
	return not _object_covered.is_empty() and _object_covered[at] == 1


func _floor_along_row(tx: int, ty: int) -> Vector2i:
	for step: int in range(1, _size.x):
		var reached: bool = false
		for way: int in [-1, 1]:
			var at_x: int = tx + way * step
			if at_x < 0 or at_x >= _size.x:
				continue
			reached = true
			var index: int = ty * _size.x + at_x
			if _art[index] == ART_FLAT and _tiles[index] >= 0 \
					and _heights[index] >= 0:
				return _floor_art.get(
					index, Vector2i(maxi(_tiles[index], 0), _heights[index])
				)
		if not reached:
			break
	return Vector2i(-1, 0)


func _emit(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var tile: int = _tiles[at]
	if tile < 0:
		return
	var art: int = _art[at]
	if art == ART_CUTOUT or art == ART_RAILING or art == ART_FENCE \
			or art == ART_BALL:
		_emit_detail(tx, ty, at, atlas)
		return
	if art == ART_LEDGE:
		_wedge(tx, ty, atlas)
		return
	if _ramp[at] == 1:
		_sink = SINK_TERRAIN
		_ramp_tile(tx, ty, atlas)
		return
	_emit_body(tx, ty, at, tile, atlas)


## A drawing that is not the ground it stands on: the floor under it is laid
## first, with its four sides, and then the drawing itself.
func _emit_detail(tx: int, ty: int, at: int, atlas: RefCounted) -> void:
	var ground: Vector2i = _ground_art(tx, ty)
	if ground.y < 0 and _house_ground.has(at):
		_sink = SINK_WATER
	_face_top(
		tx, ty, float(ground.y), atlas.uv(ground.x),
		SHADE_TOP_VOLUME if _floor_art.has(at) else SHADE_TOP_FLAT
	)
	_sink = SINK_TERRAIN
	_side(tx, ty, ground.y, _beside(tx, ty, Vector2i(0, 1)),
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas, ground.x)
	_side(tx, ty, ground.y, _beside(tx, ty, Vector2i(0, -1)),
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas, ground.x)
	_side(tx, ty, ground.y, _beside(tx, ty, Vector2i(1, 0)),
		Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas, ground.x)
	_side(tx, ty, ground.y, _beside(tx, ty, Vector2i(-1, 0)),
		Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas, ground.x)
	_emit_standing(tx, ty, at, ground, atlas)


## What stands on the floor that tile drew. A house or an object is emitted whole
## from the first of its tiles this chunk owns, so each is drawn once.
func _emit_standing(
	tx: int, ty: int, at: int, ground: Vector2i, atlas: RefCounted
) -> void:
	if _house_covered[at] == 1:
		_emit_covering(at, atlas, _house_over, _house_done, _chunk_houses, "h", true)
		return
	if _object_covered[at] == 1:
		_emit_covering(
			at, atlas, _object_over, _object_done, _chunk_objects, "o", false
		)
		return
	if _art[at] == ART_BALL:
		_ball(tx, ty, float(ground.y), atlas)
		return
	if _art[at] == ART_RAILING:
		_railing(tx, ty, float(ground.y), atlas)
		return
	if _art[at] == ART_FENCE:
		_emit_fence(tx, ty, float(ground.y), atlas)
		return
	if _modelled[at] == 1:
		_place_model(tx, ty, atlas)
		return
	_cutout(
		tx, ty, float(_depths[at]), _round[at] == 1, _filled[at] == 1,
		int(_outlined[at]), float(ground.y), ground.x, atlas
	)


func _emit_fence(tx: int, ty: int, ground: float, atlas: RefCounted) -> void:
	var cell: int = ((ty - _margin.y) >> 1) * _size.x + ((tx - _margin.x) >> 1)
	if not _owned_here("f%d" % cell) or _fence_done.has(cell):
		return
	_fence_done[cell] = true
	_chunk_fences.append(cell)
	_fence(tx, ty, ground, atlas)


func _emit_covering(
	at: int, atlas: RefCounted, over: Dictionary, done: Dictionary,
	chunk: Array, mark: String, house: bool
) -> void:
	for index: int in over.get(at, PackedInt32Array()) as PackedInt32Array:
		if not _owned_here(mark + str(index)) or done.has(index):
			continue
		done[index] = true
		chunk.append(index)
		if house:
			_emit_house(index, atlas)
		else:
			_emit_object(index, atlas)


## The tile as a solid: its cap, its four sides, and whatever stands on it.
func _emit_body(tx: int, ty: int, at: int, tile: int, atlas: RefCounted) -> void:
	var here: int = _heights[at]
	var is_volume: bool = _volume[at] == 1
	@warning_ignore("integer_division")
	var cap: int = _band_tile(tx, ty, maxi(here / BAND - 1, 0)) if is_volume else tile
	if _floor_art.has(at):
		cap = int((_floor_art[at] as Vector2i).x)
	_sink = SINK_WATER if _is_water(at) else SINK_TERRAIN
	if _margin_left[at] > 0 or _margin_right[at] > 0:
		_emit_margined(
			tx, ty, here, cap, int(_margin_left[at]), int(_margin_right[at]), atlas
		)
		_sink = SINK_TERRAIN
		return
	var tilted: bool = _tilted(at)
	_emit_cap(tx, ty, at, here, cap, tilted, is_volume, atlas)
	_sink = SINK_TERRAIN
	_roof_side(tx, ty, tilted, here, Vector2i(0, 1), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(0, -1), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(1, 0), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_roof_side(tx, ty, tilted, here, Vector2i(-1, 0), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_emit_on_top(tx, ty, at, here, atlas)


## The room's own shell south of the map draws no cap: the camera looks over it
## from inside, and a lid there would roof the room.
func _emit_cap(
	tx: int, ty: int, at: int, here: int, cap: int, tilted: bool,
	is_volume: bool, atlas: RefCounted
) -> void:
	if not _room.is_empty() and _room[at] == ROOM_SHELL and ty >= _map_end.y:
		return
	if tilted:
		_face_roof(tx, ty, atlas.uv(cap), SHADE_TOP_FLAT)
		return
	_face_top(
		tx, ty, float(here), atlas.uv(cap),
		SHADE_TOP_VOLUME if is_volume else SHADE_TOP_FLAT
	)


func _emit_on_top(
	tx: int, ty: int, at: int, here: int, atlas: RefCounted
) -> void:
	if _tufted[at] == 1:
		_tufts(tx, ty, float(here), atlas, _long_grass[at] == 1)
	if _modelled[at] == 1:
		_place_model(tx, ty, atlas, float(here))
	var stair: int = _stair_at[at]
	if stair < 0 or _stair_done.has(stair) or not _owned_here("s%d" % stair):
		return
	_stair_done[stair] = true
	_chunk_stairs.append(stair)
	_emit_stairs(stair, atlas)

const TUFT_THICK: float = 2.0
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
	var phase: float = _hash_spot(Vector2i(tx, ty))
	_sink = SINK_TUFT
	_sink_uv2 = Vector2(0.0, phase)
	_tuft_foot = base
	_tuft_span = float(edge) * stretch
	var blade := PackedByteArray()
	blade.resize(edge * edge)
	for py: int in edge:
		for px: int in edge:
			blade[py * edge + px] = int(atlas.pixel(tile, px, py) != ground)
	var taken := PackedByteArray()
	taken.resize(edge * edge)
	for py: int in edge:
		for px: int in edge:
			if taken[py * edge + px] == 1 or blade[py * edge + px] == 0:
				continue
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

var _tuft_foot: float = 0.0
var _tuft_span: float = 8.0


func _tuft_box(
	tx: int, tile: int, atlas: RefCounted, from: int, to: int,
	from_row: int, to_row: int, base: float, back: float, front: float,
	blade: PackedByteArray, stretch: float
) -> void:
	var edge: int = int(TILE)
	var x0: float = _world_x(tx) + float(from)
	var x1: float = _world_x(tx) + float(to)
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


func _wedge(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var facings: int = _ledge[at]
	var steps: Array[Vector2i] = _ledge_steps(facings)
	var base: int = _heights[at]
	var top: int = base + LEDGE_RISE
	var uv: Rect2 = atlas.uv(maxi(_tiles[at], 0))
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	_quad(
		Vector3(x0, _wedge_y(base, steps, 0, 1), z1),
		Vector3(x1, _wedge_y(base, steps, 1, 1), z1),
		Vector3(x1, _wedge_y(base, steps, 1, 0), z0),
		Vector3(x0, _wedge_y(base, steps, 0, 0), z0),
		_wedge_normal(steps), uv, SHADE_TOP_FLAT
	)
	_side(tx, ty, top if (facings & LEDGE_SOUTH) != 0 else base,
		_beside(tx, ty, Vector2i(0, 1)), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_side(tx, ty, top if (facings & LEDGE_NORTH) != 0 else base,
		_beside(tx, ty, Vector2i(0, -1)), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	_side(tx, ty, top if (facings & LEDGE_EAST) != 0 else base,
		_beside(tx, ty, Vector2i(1, 0)), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_side(tx, ty, top if (facings & LEDGE_WEST) != 0 else base,
		_beside(tx, ty, Vector2i(-1, 0)), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	for step: Vector2i in steps:
		var across := Vector2i(step.y, step.x)
		_wedge_end(tx, ty, across, step, facings, base, top, uv)
		_wedge_end(tx, ty, -across, step, facings, base, top, uv)


func _wedge_end(
	tx: int, ty: int, side: Vector2i, step: Vector2i,
	facings: int, base: int, top: int, uv: Rect2
) -> void:
	var nx: int = tx + side.x
	var ny: int = ty + side.y
	var facing: int = _ledge_facing(step)
	if (_ledge_at(nx, ny) & facing) != 0:
		return
	if (_ledge_facing(side) & facings) != 0:
		return
	if _height_at(nx, ny) >= top:
		return
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var low: float = float(base)
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
	var over_a: bool = (a - b).dot(Vector3(float(step.x), 0.0, float(step.y))) > 0.0
	var apex: Vector3 = (a if over_a else b) + Vector3(0.0, float(top - base), 0.0)
	_tri(
		a, b, apex, normal,
		Vector2(uv.position.x, uv.position.y + uv.size.y),
		Vector2(uv.position.x + uv.size.x, uv.position.y + uv.size.y),
		Vector2(uv.position.x if over_a else uv.position.x + uv.size.x, uv.position.y),
		shade
	)


func _wedge_y(base: int, steps: Array[Vector2i], u: int, v: int) -> float:
	var along: int = 0
	for step: Vector2i in steps:
		if step.x > 0:
			along = maxi(along, u)
		elif step.x < 0:
			along = maxi(along, 1 - u)
		elif step.y > 0:
			along = maxi(along, v)
		else:
			along = maxi(along, 1 - v)
	return float(base + LEDGE_RISE * along)


func _wedge_normal(steps: Array[Vector2i]) -> Vector3:
	var normal := Vector3(0.0, 1.0, 0.0)
	for step: Vector2i in steps:
		normal += Vector3(-float(step.x), 0.0, -float(step.y))
	return normal.normalized()


func _ledge_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= _size.x or ty >= _size.y:
		return LEDGE_NONE
	return _ledge[ty * _size.x + tx]

const RING_TILES: int = 4
const RING_TILES_MODELLED: int = 16
const BORDER_TILES: int = 32
var _border: Dictionary = {}
var _outside: bool = false

const ROOM_RING: int = 2
const ROOM_CELLS: int = 2
const ROOM_SHELL: int = 1
const ROOM_DRAWN: int = 2
const ROOM_BEHIND: int = 3
const ROOM_FILL: int = 4
var _room := PackedByteArray()
var _room_wall: Array = []


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

const RING_GROWTH: int = 8


func _ring_side(
	source: RefCounted, shape: RefCounted, base: int, out: Vector2i
) -> int:
	if not _outside or base <= 0:
		return base
	var depth: int = base
	while _ring_cuts(source, shape, base, depth, out):
		depth += CELL_TILES
		if depth > base + RING_GROWTH:
			return base
	return depth


func _ring_cuts(
	source: RefCounted, shape: RefCounted, base: int, depth: int, out: Vector2i
) -> bool:
	if out.y != 0:
		var ty: int = -depth if out.y < 0 else _map_size.y + depth - 1
		for tx: int in range(-base, _map_size.x + base):
			if _ring_building(source, shape, tx, ty):
				return true
		return false
	var tx: int = -depth if out.x < 0 else _map_size.x + depth - 1
	for ty: int in range(-base, _map_size.y + base):
		if _ring_building(source, shape, tx, ty):
			return true
	return false


func _ring_building(
	source: RefCounted, shape: RefCounted, tx: int, ty: int
) -> bool:
	var tile: int = source.tile_at(tx, ty)
	if tile < 0:
		return false
	var part: StringName = shape.building_part(
		shape.at(tile, source.permission_at(Vector2i(tx >> 1, ty >> 1)))
	)
	return part == &"wall" or part == &"roof"


func _measure_room_behind() -> void:
	if _room_wall.is_empty() or _object_covered.is_empty():
		return
	var tall: int = ROOM_CELLS * CELL_TILES * BAND
	var base: int = _margin.y + CELL_TILES - 1
	for ty: int in range(_margin.y, _margin.y + CELL_TILES):
		for tx: int in range(_margin.x, _map_end.x):
			var at: int = ty * _size.x + tx
			if _object_covered[at] == 0 or _heights[at] >= tall:
				continue
			_room[at] = ROOM_BEHIND
			_heights[at] = tall
			_bases[at] = base
			_art[at] = ART_UPRIGHT
			_volume[at] = 1
			_object_covered[at] = 0


func _room_wall_tile(tx: int, ty: int) -> int:
	if _room_wall.is_empty():
		return -1
	var row: Array = _room_wall[posmod(ty - _margin.y, _room_wall.size())]
	if row.is_empty():
		return -1
	return int(row[posmod(tx - _margin.x, row.size())])


func _measure_room() -> void:
	if _room_wall.is_empty():
		return
	var tall: int = ROOM_CELLS * CELL_TILES * BAND
	var floor_row: int = _size.y - 1
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _room[at] != ROOM_SHELL:
				continue
			_heights[at] = tall
			_bases[at] = floor_row if ty >= _map_end.y else ty
	for tx: int in range(_margin.x, _map_end.x):
		var run: int = 0
		while _margin.y + run < _map_end.y \
				and _volume[(_margin.y + run) * _size.x + tx] == 1:
			run += 1
		if run == 0:
			continue
		var base: int = _margin.y + run - 1
		if _heights[base * _size.x + tx] >= tall:
			continue
		for step: int in run:
			var at: int = (_margin.y + step) * _size.x + tx
			_heights[at] = tall
			_bases[at] = base
			_room[at] = ROOM_DRAWN


func _measure_room_fill() -> void:
	if _room_wall.is_empty():
		return
	var count: int = _size.x * _size.y
	var seen := PackedByteArray()
	seen.resize(count)
	var region := PackedInt32Array()
	var tall: int = ROOM_CELLS * CELL_TILES * BAND
	for start: int in count:
		if _void[start] == 0 or seen[start] == 1:
			continue
		region.clear()
		region.append(start)
		seen[start] = 1
		var at_edge: bool = false
		var head: int = 0
		while head < region.size():
			var at: int = region[head]
			head += 1
			var tx: int = at % _size.x
			@warning_ignore("integer_division")
			var ty: int = at / _size.x
			if tx <= _margin.x or ty <= _margin.y \
					or tx >= _map_end.x - 1 \
					or ty >= _map_end.y - 1:
				at_edge = true
			for step: Vector2i in STEPS:
				var to := Vector2i(tx + step.x, ty + step.y)
				if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
					continue
				var index: int = to.y * _size.x + to.x
				if _void[index] == 1 and seen[index] == 0:
					seen[index] = 1
					region.append(index)
		if not at_edge:
			continue
		for at: int in region:
			var tx: int = at % _size.x
			@warning_ignore("integer_division")
			var ty: int = at / _size.x
			_room[at] = ROOM_FILL
			_tiles[at] = _room_wall_tile(tx, ty)
			_heights[at] = tall
			_bases[at] = ty
			_art[at] = ART_UPRIGHT
			_volume[at] = 1
			_void[at] = 0
			_modelled[at] = 0
			_tufted[at] = 0
			_cliff[at] = 0
			_front[at] = 0
			_lip[at] = 0
			_pitched[at] = 0
			_margin_left[at] = 0
			_margin_right[at] = 0


func _emit_skirt(tx: int, ty: int, atlas: RefCounted) -> void:
	var floor_at: Vector2i = _skirt_floor_at(tx, ty)
	if floor_at.x < 0:
		return
	var edge := Vector2i(clampi(tx, 0, _size.x - 1), clampi(ty, 0, _size.y - 1))
	_sink = SINK_WATER if floor_at.y < 0 else SINK_TERRAIN
	_face_top(tx, ty, float(floor_at.y), atlas.uv(floor_at.x), SHADE_TOP_FLAT)
	_sink = SINK_TERRAIN
	_skirt_fence(tx, ty, edge, float(floor_at.y), atlas)
	_sink = SINK_WATER if floor_at.y < 0 else SINK_TERRAIN
	for step: Vector2i in STEPS:
		_skirt_side(tx, ty, step, floor_at, atlas)
	_sink = SINK_TERRAIN


func _skirt_floor_at(tx: int, ty: int) -> Vector2i:
	var edge := Vector2i(clampi(tx, 0, _size.x - 1), clampi(ty, 0, _size.y - 1))
	var key: int = edge.y * _size.x + edge.x
	if not _border.has(key):
		_border[key] = _skirt_floor(edge)
	return _border[key]


func _skirt_reach() -> int:
	return maxi(BORDER_TILES - _margin.x, 0) if _outside else 0


func _skirt_beside(tx: int, ty: int) -> int:
	if tx >= 0 and ty >= 0 and tx < _size.x and ty < _size.y:
		return _heights[ty * _size.x + tx]
	var reach: int = _skirt_reach()
	if tx < -reach or ty < -reach \
			or tx >= _size.x + reach or ty >= _size.y + reach:
		return 0
	var floor_at: Vector2i = _skirt_floor_at(tx, ty)
	return 0 if floor_at.x < 0 else floor_at.y


func _skirt_side(
	tx: int, ty: int, step: Vector2i, floor_at: Vector2i, atlas: RefCounted
) -> void:
	var here: int = floor_at.y
	var neighbour: int = _skirt_beside(tx + step.x, ty + step.y)
	if neighbour >= here:
		return
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var full: Rect2 = atlas.uv(floor_at.x)
	var shade: Color = SHADE_SOUTH if step.y > 0 else (
		SHADE_NORTH if step.y < 0 else SHADE_SIDE
	)
	var normal := Vector3(float(step.x), 0.0, float(step.y))
	var low: float = float(neighbour)
	while low < float(here):
		var high: float = minf(low + TILE, float(here))
		var uv: Rect2 = full
		if high - low < TILE:
			uv.size.y = full.size.y * (high - low) / TILE
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		if step.y > 0:
			a = Vector3(x0, low, z1)
			b = Vector3(x1, low, z1)
		elif step.y < 0:
			a = Vector3(x1, low, z0)
			b = Vector3(x0, low, z0)
		elif step.x > 0:
			a = Vector3(x1, low, z1)
			b = Vector3(x1, low, z0)
		else:
			a = Vector3(x0, low, z0)
			b = Vector3(x0, low, z1)
		_quad(
			a, b, Vector3(b.x, high, b.z), Vector3(a.x, high, a.z), normal, uv, shade
		)
		low = high

var _skirt_fence_done: Dictionary = {}


func _skirt_fence(
	tx: int, ty: int, edge: Vector2i, ground: float, atlas: RefCounted
) -> void:
	var out_x: bool = tx < 0 or tx >= _size.x
	var out_y: bool = ty < 0 or ty >= _size.y
	if out_x == out_y:
		return
	var index: int = edge.y * _size.x + edge.x
	if _art[index] != ART_FENCE:
		return
	var arm: int = FENCE_ACROSS if out_x else FENCE_AWAY
	if int(_fence_arms[index]) & arm == 0:
		return
	var cell := Vector2i((tx - _margin.x) >> 1, (ty - _margin.y) >> 1)
	if not _owned_here("k%s" % str(cell)) or _skirt_fence_done.has(cell):
		return
	_skirt_fence_done[cell] = true
	_chunk_skirt_fences.append(cell)
	_fence(tx, ty, ground, atlas, arm)

const SKIRT_ALONG: int = 8


func _skirt_floor(edge: Vector2i) -> Vector2i:
	var inward := Vector2i(
		1 if edge.x == 0 else (-int(edge.x == _size.x - 1)),
		1 if edge.y == 0 else (-int(edge.y == _size.y - 1))
	)
	var found: Vector2i = _skirt_column(edge, inward)
	if found.x >= 0:
		return found
	var along := Vector2i(inward.y, inward.x)
	for step: int in range(1, SKIRT_ALONG + 1):
		for way: int in [1, -1]:
			found = _skirt_column(edge + along * step * way, inward)
			if found.x >= 0:
				return found
	return _commonest_edge_floor()


func _skirt_column(edge: Vector2i, inward: Vector2i) -> Vector2i:
	if edge.x < 0 or edge.y < 0 or edge.x >= _size.x or edge.y >= _size.y:
		return Vector2i(-1, 0)
	for step: int in maxi(_margin.x, 1):
		var at := edge + inward * step
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			break
		var index: int = at.y * _size.x + at.x
		if _doorway[index] == 1:
			continue
		if _art[index] == ART_FLAT and _tiles[index] >= 0:
			return Vector2i(_tiles[index], _heights[index])
	return Vector2i(-1, 0)

var _edge_floor := Vector2i(-2, 0)


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
			if _art[index] != ART_FLAT or _tiles[index] < 0 or _ramp[index] == 1:
				continue
			var key: int = _tiles[index] * 1024 + _heights[index] + 512
			counts[key] = int(counts.get(key, 0)) + 1
			if int(counts[key]) > best:
				best = int(counts[key])
				_edge_floor = Vector2i(_tiles[index], _heights[index])
	return _edge_floor

var _ground_table: Dictionary = {}
var _ground_by_id: Dictionary = {}


func _ground_tile_at(at: int) -> int:
	if _ground_by_id.is_empty():
		for shape_class: StringName in _class_ids:
			_ground_by_id[int(_class_ids[shape_class])] = int(
				_ground_table.get(shape_class, -1)
			)
	return int(_ground_by_id.get(_klass[at], -1))


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
	if left > 0:
		_margin_floor(tx, ty, _world_x(tx), x0, _height_at(tx - 1, ty), atlas)
	if right > 0:
		_margin_floor(tx, ty, x1, _world_x(tx) + TILE, _height_at(tx + 1, ty), atlas)

	_side_span(tx, ty, x0, x1, here, _height_at(tx, ty + 1),
		Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_side_span(tx, ty, x0, x1, here, _height_at(tx, ty - 1),
		Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	var west: int = _height_at(tx - 1, ty) if left == 0 else mini(
		_height_at(tx - 1, ty), _height_at(tx, ty + 1)
	)
	var east: int = _height_at(tx + 1, ty) if right == 0 else mini(
		_height_at(tx + 1, ty), _height_at(tx, ty + 1)
	)
	_side_at(x1, z0, z1, here, east, Vector3(1.0, 0.0, 0.0), tx, ty, atlas)
	_side_at(x0, z0, z1, here, west, Vector3(-1.0, 0.0, 0.0), tx, ty, atlas)


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
		var uv: Rect2 = atlas.uv(_face_tile(tx, ty, maxi(floori(low / TILE), 0)))
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
		var uv: Rect2 = atlas.uv(_face_tile(tx, ty, maxi(floori(low / TILE), 0)))
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


func _tilted(at: int) -> bool:
	return _part[at] == PART_ROOF or _pitched[at] == 1


func _roof_side(
	tx: int, ty: int, tilted: bool, here: int, step: Vector2i,
	normal: Vector3, shade: Color, atlas: RefCounted
) -> void:
	var at := Vector2i(tx + step.x, ty + step.y)
	if tilted and at.x >= 0 and at.y >= 0 and at.x < _size.x and at.y < _size.y \
			and _tilted(at.y * _size.x + at.x):
		return
	_side(tx, ty, here, _beside(tx, ty, step), normal, shade, atlas)


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


func _face_roof(tx: int, ty: int, uv: Rect2, shade: Color) -> void:
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	var a := Vector3(x0, _roof_corner(tx, ty, -1, 1), z1)
	var b := Vector3(x1, _roof_corner(tx, ty, 1, 1), z1)
	var c := Vector3(x1, _roof_corner(tx, ty, 1, -1), z0)
	var d := Vector3(x0, _roof_corner(tx, ty, -1, -1), z0)
	var normal: Vector3 = (c - a).cross(d - b).normalized()
	if normal.y < 0.0:
		normal = -normal
	_quad(a, b, c, d, normal, uv, shade)


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
	_ramp_side(tx, ty, Vector2i(0, 1), sw, se, Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, uv)
	_ramp_side(tx, ty, Vector2i(0, -1), ne, nw, Vector3(0.0, 0.0, -1.0), SHADE_NORTH, uv)
	_ramp_side(tx, ty, Vector2i(1, 0), se, ne, Vector3(1.0, 0.0, 0.0), SHADE_SIDE, uv)
	_ramp_side(tx, ty, Vector2i(-1, 0), nw, sw, Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, uv)


func _ramp_side(
	tx: int, ty: int, step: Vector2i, first: float, second: float,
	normal: Vector3, shade: Color, uv: Rect2
) -> void:
	var to := Vector2i(tx + step.x, ty + step.y)
	var floor_y: float = 0.0
	if to.x < 0 or to.y < 0 or to.x >= _size.x or to.y >= _size.y:
		floor_y = float(_skirt_beside(to.x, to.y))
	else:
		var index: int = to.y * _size.x + to.x
		if _shelf[index] == 1:
			return
		floor_y = float(_heights[index])
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


func _side(
	tx: int, ty: int, here: int, neighbour: int,
	normal: Vector3, shade: Color, atlas: RefCounted, art: int = -1
) -> void:
	if neighbour >= here:
		return
	if not _room_faces(tx, ty, normal):
		return
	if not _room.is_empty() and _room[ty * _size.x + tx] != 0:
		shade = SHADE_SOUTH
	var x0: float = _world_x(tx)
	var x1: float = x0 + TILE
	var z0: float = _world_z(ty)
	var z1: float = z0 + TILE
	for step: int in (here - neighbour) / BAND:
		var low: float = float(neighbour + step * BAND)
		var high: float = low + TILE
		var uv: Rect2 = atlas.uv(
			art if art >= 0 else _face_tile(tx, ty, maxi(floori(low / TILE), 0))
		)
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


func _turned(point: Vector3) -> Vector3:
	return Vector3(
		_turn_pivot.x - (point.z - _turn_pivot.z),
		point.y,
		_turn_pivot.z + (point.x - _turn_pivot.x)
	)


func _quad(
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3, uv: Rect2, shade: Color
) -> void:
	if _turn:
		a = _turned(a)
		b = _turned(b)
		c = _turned(c)
		d = _turned(d)
		normal = Vector3(-normal.z, normal.y, normal.x)
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


func _tri(
	a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, shade: Color
) -> void:
	_push(a, normal, uv_a, shade)
	_push(c, normal, uv_c, shade)
	_push(b, normal, uv_b, shade)


func _push(vertex: Vector3, normal: Vector3, uv: Vector2, shade: Color) -> void:
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
		_tuft_uv2s.push_back(Vector2(
			clampf((vertex.y - _tuft_foot) / _tuft_span, 0.0, 1.0), _sink_uv2.y
		))
		return
	_water_vertices.push_back(vertex)
	_water_normals.push_back(normal)
	_water_uvs.push_back(uv)
	_water_colors.push_back(shade)
