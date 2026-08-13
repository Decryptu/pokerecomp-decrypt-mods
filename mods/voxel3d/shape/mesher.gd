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

const Levels: GDScript = preload("levels.gd")
const Model: GDScript = preload("model.gd")

const TILE: float = 8.0
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

## Art modes, kept per tile as a byte because every tile of every map carries one.
const ART_FLAT: int = 0
const ART_TOP: int = 1
const ART_UPRIGHT: int = 2
const ART_CUTOUT: int = 3
## Not a class's art but a shape the COLLISION asks for: see `_measure_ledges`.
const ART_LEDGE: int = 4

var _size := Vector2i.ZERO
var _tiles := PackedInt32Array()
var _art := PackedByteArray()
var _depths := PackedByteArray()
## Per tile: whether its cutout is round in plan, and whether its drawing is a
## solid body the border flood cannot be trusted with.
var _round := PackedByteArray()
var _filled := PackedByteArray()
## Per tile: how many of its darkest shades bound the drawing, 0 for a mask cut
## from the ground's colours instead.
var _outlined := PackedByteArray()
## Per tile: whether an authored MODEL stands here rather than carved geometry.
var _modelled := PackedByteArray()
## Per tile: whether a slab of its own drawing stands up out of the floor.
var _tufted := PackedByteArray()
## Per tile: how many cells across and down the drawing this cutout belongs to
## is, which is what the mask is cut over, and which class it is.
var _span_x := PackedByteArray()
var _span_y := PackedByteArray()
var _lying := PackedByteArray()
## Per tile: whether the drawing stands on FURNITURE rather than on the ground.
var _on_furniture := PackedByteArray()
var _klass := PackedInt32Array()
var _class_ids: Dictionary = {}
## Per tile: which surface of a building it depicts, and how many bands a sloped
## roof tile has fallen from the flat section beside it.
const PART_NONE: int = 0
const PART_WALL: int = 1
const PART_ROOF: int = 2
var _part := PackedByteArray()
var _drop := PackedByteArray()
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


## False when there is nothing to draw at all.
func begin_emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> bool:
	_emit_atlas = null
	_chunks = []
	_chunk_at = 0
	_ready = []
	if _size == Vector2i.ZERO:
		return false
	var reach: int = BORDER_TILES if _outside else 0
	var box := Rect2i(-Vector2i(reach, reach), _size + Vector2i(reach, reach) * 2)
	if window.size.x > 0 and window.size.y > 0:
		box = box.intersection(window)
	if box.size.x <= 0 or box.size.y <= 0:
		return false
	_emit_atlas = atlas
	_model_spots.clear()
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
					_emit_border(_chunk_cursor.x, _chunk_cursor.y, _emit_atlas)
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


func _open_chunk() -> void:
	_chunk_cursor = _chunks[_chunk_at].position
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_colors = PackedColorArray()


func _close_chunk() -> void:
	# A chunk of nothing is most of the sky above a route edge and all of a map's
	# void; an empty mesh is an instance the engine still has to cull.
	if _vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ready.append(mesh)


func size_pixels() -> Vector2:
	return Vector2(_size) * TILE


func size_tiles() -> Vector2i:
	return _size


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
	_border.clear()
	# Keyed on tile ids, which mean nothing without the tileset they came from.
	_model_meshes.clear()
	_commonest_index.clear()
	if source == null or not source.valid():
		return
	_outside = source.outside()
	_size = source.size_cells() * RomLayout.MAP_BLOCK_CELL_WIDTH
	var count: int = _size.x * _size.y
	_tiles.resize(count)
	_art.resize(count)
	_depths.resize(count)
	_round.resize(count)
	_filled.resize(count)
	_outlined.resize(count)
	_modelled.resize(count)
	_tufted.resize(count)
	_span_x.resize(count)
	_span_y.resize(count)
	_lying.resize(count)
	_on_furniture.resize(count)
	_klass.resize(count)
	_part.resize(count)
	_drop.resize(count)
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

	for ty: int in _size.y:
		var cell_y: int = ty >> 1
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			var tile: int = source.tile_at(tx, ty)
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
			var permission: int = source.permission_at(Vector2i(tx >> 1, cell_y))
			var shape_class: StringName = shape.at(tile, permission)
			var art: StringName = shape.art(shape_class)
			_art[at] = _art_mode(art)
			_depths[at] = clampi(shape.depth(shape_class), 1, 16)
			_round[at] = 1 if shape.is_round(shape_class) else 0
			_filled[at] = 1 if shape.is_filled(shape_class) else 0
			_outlined[at] = shape.outline_shades(shape_class)
			_modelled[at] = 1 if shape.is_model(shape_class) else 0
			_tufted[at] = 1 if shape.is_tufted(shape_class) else 0
			_lying[at] = 1 if shape.is_lying(shape_class) else 0
			_on_furniture[at] = 1 if shape_class == &"on_furniture" else 0
			var span: Vector2i = shape.span_cells(shape_class)
			_span_x[at] = maxi(span.x, 1)
			_span_y[at] = maxi(span.y, 1)
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

	_measure_columns()
	# Before the plateau pass, which is the automatic reading of the same thing:
	# where a person has said what the levels are, the cliff pass has nothing left
	# to work out and its flood would only fight the answer.
	_apply_levels(source)
	_measure_plateaus()
	_measure_buildings()
	# Before the furniture, which asks what the height of the thing under it came
	# to and would read an unsettled -1 as standing on the floor.
	_settle_unmeasured()
	_measure_furniture()
	_measure_cutouts()
	# Last, because it overrides whatever the passes above made of a ledge tile
	# and reads the ground they settled either side of it.
	_measure_ledges(source)


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
				map.group, map.number, Vector2i(tx >> 1, ty >> 1)
			)
			if height <= 0:
				continue
			if _art[at] == ART_FLAT:
				# Water keeps its own recess and rides up on the floor it is cut
				# into, which is what `_settle_ponds` does for a measured one.
				_heights[at] = height if _heights[at] >= 0 else _heights[at] + height
			elif _heights[at] >= 0:
				_heights[at] += height


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
func _measure_cutouts() -> void:
	for ty: int in _size.y:
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			if _art[at] != ART_CUTOUT or (_span_x[at] == 1 and _span_y[at] == 1):
				continue
			var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
			var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
			var whole: bool = true
			for row: int in across.y:
				for column: int in across.x:
					var here := Vector2i(start.x + column, start.y + row)
					if here.x >= _size.x or here.y >= _size.y \
							or _klass[here.y * _size.x + here.x] != _klass[at]:
						whole = false
						break
				if not whole:
					break
			if whole and _lying[at] == 0:
				whole = not _repeats(start, Vector2i(int(_span_x[at]), int(_span_y[at])))
			if not whole:
				_span_x[at] = 1
				_span_y[at] = 1


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
			var code: int = source.code_at(Vector2i(cx, cy))
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
			for tx: int in range(wall, last + 1):
				var run: int = 1
				while ty - run >= 0 and _part[(ty - run) * _size.x + tx] == PART_WALL:
					run += 1
				runs.append(run)
				bands = maxi(bands, _facade_period(tx, ty, run))
			for tx: int in range(wall, last + 1):
				var under: int = column[tx]
				var top: int = under + bands * BAND
				for step: int in runs[tx - wall]:
					var index: int = (ty - step) * _size.x + tx
					_heights[index] = top
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
	for tx: int in range(from, to + 1):
		var at: int = ty * _size.x + tx
		var height: int = maxi(agreed - int(_drop[at]) * BAND, column[tx])
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
	return _height_at(floori(position.x / TILE), floori(position.z / TILE))


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


func _structure_mask(
	tiles: Array, across: Vector2i, atlas: RefCounted, filled: bool,
	outline: int = 0
) -> PackedByteArray:
	var key: String = "%s,%d,%d" % [str(tiles), 1 if filled else 0, outline]
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
## ONE SPAN PER ROW, from the row's first drawn pixel to its last, and NOT one
## per contiguous run. These drawings are dithered, so a row of one bush is half
## a dozen short runs with floor showing between them, and revolving each run
## separately makes one dome into six little cylinders in a line. The reference
## takes the row's extent for exactly this reason (`Structures.lua:roundTemplate`,
## `lo = lo or ix; hi = ix` over the whole row): a gap in the drawing is a gap in
## the SURFACE, not a new object. Measured over every map, it is also very
## slightly cheaper than splitting per run, 6.066M triangles against 6.087M.
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
	mask: PackedByteArray, span: Vector2i, round_plan: bool, depth: int
) -> PackedByteArray:
	var levels := PackedByteArray()
	levels.resize(mask.size())
	var deepest: int = clampi(depth, 1, 255)
	if not round_plan:
		for at: int in mask.size():
			levels[at] = deepest if mask[at] == 1 else 0
		return levels
	for py: int in span.y:
		var first: int = -1
		var last: int = -1
		for px: int in span.x:
			if mask[py * span.x + px] == 1:
				if first < 0:
					first = px
				last = px
		if first < 0:
			continue
		var middle: float = (float(first) + float(last) + 1.0) * 0.5
		var radius: float = maxf((float(last) + 1.0 - float(first)) * 0.5, 0.5)
		for step: int in range(first, last + 1):
			if mask[py * span.x + step] == 0:
				continue
			var away: float = float(step) + 0.5 - middle
			var chord: float = 2.0 * sqrt(maxf(radius * radius - away * away, 0.0))
			levels[py * span.x + step] = clampi(roundi(chord), 1, 255)
	return levels


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


func _place_model(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
	var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var key: String = str(tiles)
	if not _model_meshes.has(key):
		var mask: PackedByteArray = _structure_mask(
			tiles, across, atlas, false, int(_outlined[at])
		)
		var measured: RefCounted = Model.measure(
			mask, across * int(TILE), tiles, across, atlas
		)
		_model_meshes[key] = (Model.new() as RefCounted).tree(measured)
		_model_spots[key] = {}
	# The middle of the drawing's own footprint, on the ground beside it.
	var spot := Vector3(
		(float(start.x) + float(across.x) * 0.5) * TILE,
		float(_ground_art(tx, ty).y),
		(float(start.y) + float(across.y) * 0.5) * TILE
	)
	(_model_spots[key] as Dictionary)[str(start)] = spot


## The models this emit placed: a list of [mesh, spots], one per distinct
## drawing. Empty until an emit has run.
func take_models() -> Array:
	var out: Array = []
	for key: String in _model_meshes:
		var spots := PackedVector3Array()
		for spot: Vector3 in (_model_spots[key] as Dictionary).values():
			spots.append(spot)
		if not spots.is_empty():
			out.append([_model_meshes[key], spots])
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
	base: float, atlas: RefCounted
) -> void:
	var at: int = ty * _size.x + tx
	var across := Vector2i(int(_span_x[at]), int(_span_y[at])) * CELL_TILES
	# The structure's own grid, which is the block grid: a drawing one cell wide
	# and two tall fills half a block across and the whole of it down.
	var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
	var tiles: Array = []
	for row: int in across.y:
		for column: int in across.x:
			tiles.append(_tile_at(start.x + column, start.y + row))
	var span := across * int(TILE)
	var mask: PackedByteArray = _structure_mask(tiles, across, atlas, filled, outline)
	var levels: PackedByteArray = _cell_levels(mask, span, round_plan, roundi(depth))

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
	var mid: float = 0.0
	var top: float = 0.0
	if _lying[at] == 1:
		mid = float(ty >> 1) * CELL_TILES * TILE + CELL_TILES * TILE * 0.5
		top = CELL_TILES * TILE - float((ty & 1) * edge)
	else:
		mid = float((start.y + across.y - 1) >> 1) * CELL_TILES * TILE \
			+ CELL_TILES * TILE * 0.5
		top = float(span.y - origin.y)

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
				tx, tile, atlas, mask, origin, span, top + base,
				Rect2i(column, row, wide, tall), mid - half, mid + half
			)


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


func _cutout_box(
	tx: int, tile: int, atlas: RefCounted, mask: PackedByteArray,
	origin: Vector2i, span: Vector2i, top: float, box: Rect2i, back: float, front: float
) -> void:
	var x0: float = float(tx) * TILE + float(box.position.x)
	var x1: float = x0 + float(box.size.x)
	var high: float = top - float(box.position.y)
	var low: float = high - float(box.size.y)
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
					open = not _drawn(mask, span, beyond.x, beyond.y)
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
		var x0: float = float(tx) * TILE + float(box.position.x + from)
		var x1: float = float(tx) * TILE + float(box.position.x + to)
		var y: float = top - float(box.position.y) \
			- (0.0 if near else float(box.size.y))
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

	var x: float = float(tx) * TILE + float(box.position.x + (0 if near else box.size.x))
	var high: float = top - float(box.position.y + from)
	var low: float = top - float(box.position.y + to)
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
func _ground_art(tx: int, ty: int) -> Vector2i:
	for step: Vector2i in [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
	]:
		var at := Vector2i(tx + step.x, ty + step.y)
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			continue
		var index: int = at.y * _size.x + at.x
		if _art[index] == ART_FLAT and _heights[index] >= 0:
			return Vector2i(maxi(_tiles[index], 0), _heights[index])
	return Vector2i(maxi(_tiles[ty * _size.x + tx], 0), 0)


func _emit(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var tile: int = _tiles[at]
	if tile < 0:
		return
	if _art[at] == ART_CUTOUT:
		var ground: Vector2i = _ground_art(tx, ty)
		_face_top(tx, ty, float(ground.y), atlas.uv(ground.x), SHADE_TOP_FLAT)
		_side(tx, ty, ground.y, _height_at(tx, ty + 1), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
		_side(tx, ty, ground.y, _height_at(tx, ty - 1), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
		_side(tx, ty, ground.y, _height_at(tx + 1, ty), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
		_side(tx, ty, ground.y, _height_at(tx - 1, ty), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
		# The ground under it is drawn either way; what stands ON it is either the
		# drawing carved out or an authored model stamped there.
		if _modelled[at] == 1:
			_place_model(tx, ty, atlas)
		else:
			_cutout(
				tx, ty, float(_depths[at]), _round[at] == 1, _filled[at] == 1,
				int(_outlined[at]), float(ground.y), atlas
			)
		return
	if _art[at] == ART_LEDGE:
		_wedge(tx, ty, atlas)
		return
	var here: int = _heights[at]
	var is_volume: bool = _volume[at] == 1

	# A volume wears its structure's TOP row on its cap, so the plateau behind a
	# standing drawing is the top of that drawing rather than whatever tile the
	# column happens to sit on.
	@warning_ignore("integer_division")
	var cap: int = _band_tile(tx, ty, maxi(here / BAND - 1, 0)) if is_volume else tile
	_face_top(
		tx, ty, float(here), atlas.uv(cap),
		SHADE_TOP_VOLUME if is_volume else SHADE_TOP_FLAT
	)

	_side(tx, ty, here, _height_at(tx, ty + 1), Vector3(0.0, 0.0, 1.0), SHADE_SOUTH, atlas)
	_side(tx, ty, here, _height_at(tx, ty - 1), Vector3(0.0, 0.0, -1.0), SHADE_NORTH, atlas)
	_side(tx, ty, here, _height_at(tx + 1, ty), Vector3(1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	_side(tx, ty, here, _height_at(tx - 1, ty), Vector3(-1.0, 0.0, 0.0), SHADE_SIDE, atlas)
	if _tufted[at] == 1:
		_tufts(tx, ty, float(here), atlas)


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


func _tufts(tx: int, ty: int, base: float, atlas: RefCounted) -> void:
	var tile: int = _tiles[ty * _size.x + tx]
	if tile < 0:
		return
	var ground: int = _commonest(tile, atlas)
	var edge: int = int(TILE)
	var middle: float = float(ty) * TILE + TILE * 0.5
	var back: float = middle - TUFT_THICK * 0.5
	var front: float = middle + TUFT_THICK * 0.5
	for py: int in edge:
		var run: int = -1
		for px: int in edge + 1:
			var blade: bool = px < edge and atlas.pixel(tile, px, py) != ground
			if blade and run < 0:
				run = px
			elif not blade and run >= 0:
				_tuft_run(tx, tile, atlas, run, px, py, base, back, front, ground)
				run = -1


## One run of blade along one row of the drawing, stood up as a box. The row is
## read the way every upright face in this mod is: the drawing's top row is the
## top of the thing.
func _tuft_run(
	tx: int, tile: int, atlas: RefCounted, from: int, to: int, py: int,
	base: float, back: float, front: float, ground: int
) -> void:
	var x0: float = float(tx) * TILE + float(from)
	var x1: float = float(tx) * TILE + float(to)
	var low: float = base + float(int(TILE) - 1 - py)
	var high: float = low + 1.0
	var uv: Rect2 = atlas.uv_box(tile, Rect2i(from, py, to - from, 1))
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
	# A lid only where nothing stands on this run, and ends only where the blade
	# stops: a face inside the clump is never seen and is not worth emitting.
	if py == 0 or atlas.pixel(tile, from, py - 1) == ground:
		_quad(
			Vector3(x0, high, front), Vector3(x1, high, front),
			Vector3(x1, high, back), Vector3(x0, high, back),
			Vector3.UP, uv, SHADE_TOP_FLAT
		)
	_quad(
		Vector3(x0, low, back), Vector3(x0, low, front),
		Vector3(x0, high, front), Vector3(x0, high, back),
		Vector3(-1.0, 0.0, 0.0), uv, SHADE_SIDE
	)
	_quad(
		Vector3(x1, low, front), Vector3(x1, low, back),
		Vector3(x1, high, back), Vector3(x1, high, front),
		Vector3(1.0, 0.0, 0.0), uv, SHADE_SIDE
	)


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
	var x0: float = float(tx) * TILE
	var x1: float = x0 + TILE
	var z0: float = float(ty) * TILE
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
	var x0: float = float(tx) * TILE
	var x1: float = x0 + TILE
	var z0: float = float(ty) * TILE
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


## What lies past the edge of the map: the FLOOR at that edge, carried outward.
##
## A route that stops dead a few cells past its edge is the one thing a
## perspective view shows that a tile page never had to answer for, and a fight
## staged near an edge is shot against sky. So the ground runs on. Only the
## ground: the tree line or the fence a map ends in is a thing standing ON the
## floor, and repeating it outward would build a wall around the world.
##
## The nearest flat tile inward from the edge is that floor, which is why a
## shoreline carries the water out rather than the beach.
##
## OUT OF DOORS ONLY. A room ends at its walls and there is nothing past them:
## carrying a floor out of a house would lay its lino across the void it is
## drawn against. The host is what says which a map is.
const BORDER_TILES: int = 32
## How far in from the edge to look for it before giving up.
const BORDER_REACH: int = 8
var _border: Dictionary = {}
var _outside: bool = false


func _emit_border(tx: int, ty: int, atlas: RefCounted) -> void:
	var edge := Vector2i(clampi(tx, 0, _size.x - 1), clampi(ty, 0, _size.y - 1))
	var key: int = edge.y * _size.x + edge.x
	if not _border.has(key):
		_border[key] = _border_floor(edge)
	var floor_at: Vector2i = _border[key]
	if floor_at.x < 0:
		return
	_face_top(tx, ty, float(floor_at.y), atlas.uv(floor_at.x), SHADE_TOP_FLAT)


## The tile id and height of the floor at one edge position, as a Vector2i, or a
## negative tile where the edge is nothing but structures for as far as this
## looks.
func _border_floor(edge: Vector2i) -> Vector2i:
	var inward := Vector2i(
		1 if edge.x == 0 else (-1 if edge.x == _size.x - 1 else 0),
		1 if edge.y == 0 else (-1 if edge.y == _size.y - 1 else 0)
	)
	for step: int in BORDER_REACH:
		var at := edge + inward * step
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			break
		var index: int = at.y * _size.x + at.x
		if _art[index] == ART_FLAT and _tiles[index] >= 0:
			return Vector2i(_tiles[index], _heights[index])
	return Vector2i(-1, 0)


func _face_top(tx: int, ty: int, y: float, uv: Rect2, shade: Color) -> void:
	var x0: float = float(tx) * TILE
	var x1: float = x0 + TILE
	var z0: float = float(ty) * TILE
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
	var x0: float = float(tx) * TILE
	var x1: float = x0 + TILE
	var z0: float = float(ty) * TILE
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
	_vertices.push_back(vertex)
	_normals.push_back(normal)
	_uvs.push_back(uv)
	_colors.push_back(shade)
