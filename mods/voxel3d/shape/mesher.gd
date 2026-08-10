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

var _size := Vector2i.ZERO
var _tiles := PackedInt32Array()
var _art := PackedByteArray()
var _depths := PackedByteArray()
var _heights := PackedInt32Array()
var _volume := PackedByteArray()
## The southernmost map row of the structure each tile belongs to. The fold reads
## north from there rather than from the tile itself, so every column of one
## structure shows the same drawing standing up and a face exposed at its back
## does not sample the ground behind it.
var _bases := PackedInt32Array()


## Resolves a map and builds it. Returns null when there is nothing to draw.
## [param source] is a `map_source.gd`, over the live world or over records.
## [param window] is a rectangle in TILES, empty for the whole map.
func build(
	source: RefCounted, shape: RefCounted, atlas: RefCounted, window: Rect2i = Rect2i()
) -> ArrayMesh:
	resolve(source, shape)
	return emit(atlas, window)


## The geometry for [param window], out of what [method resolve] already worked
## out. Nothing is measured again: what a tile is and how tall it stands is a
## fact about the MAP, and reading it through the window would make a structure's
## height depend on where the player was standing when the mesh was built.
##
## An empty window is the whole map; anything else is clipped to it.
func emit(atlas: RefCounted, window: Rect2i = Rect2i()) -> ArrayMesh:
	if _size == Vector2i.ZERO:
		return null
	var box := Rect2i(Vector2i.ZERO, _size)
	if window.size.x > 0 and window.size.y > 0:
		box = box.intersection(window)

	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_colors = PackedColorArray()

	for ty: int in range(box.position.y, box.end.y):
		for tx: int in range(box.position.x, box.end.x):
			_emit(tx, ty, atlas)

	if _vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	if source == null or not source.valid():
		return
	_size = source.size_cells() * RomLayout.MAP_BLOCK_CELL_WIDTH
	var count: int = _size.x * _size.y
	_tiles.resize(count)
	_art.resize(count)
	_depths.resize(count)
	_heights.resize(count)
	_volume.resize(count)
	_bases.resize(count)

	for ty: int in _size.y:
		var cell_y: int = ty >> 1
		for tx: int in _size.x:
			var at: int = ty * _size.x + tx
			var tile: int = source.tile_at(tx, ty)
			_tiles[at] = tile
			_bases[at] = ty
			if tile < 0:
				_heights[at] = 0
				_volume[at] = 0
				_art[at] = ART_FLAT
				continue
			var permission: int = source.permission_at(Vector2i(tx >> 1, cell_y))
			var shape_class: StringName = shape.at(tile, permission)
			var art: StringName = shape.art(shape_class)
			_art[at] = _art_mode(art)
			_depths[at] = clampi(shape.depth(shape_class), 1, 16)
			var is_volume: bool = art == &"upright"
			_volume[at] = 1 if is_volume else 0
			# A pin is authority: it names the height too, and the column
			# measurement below leaves it alone.
			if is_volume and not shape.is_pinned(tile):
				_heights[at] = -1
			else:
				_heights[at] = shape.height(shape_class)

	_measure_columns()


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
func _measure_columns() -> void:
	@warning_ignore("integer_division")
	var cells := Vector2i(_size.x / CELL_TILES, _size.y / CELL_TILES)
	for cell_x: int in cells.x:
		var cell_y: int = 0
		while cell_y < cells.y:
			if not _cell_unmeasured(cell_x, cell_y):
				cell_y += 1
				continue
			var run: int = 0
			while cell_y + run < cells.y and _cell_unmeasured(cell_x, cell_y + run):
				run += 1
			var height: int = mini(_period(cell_x, cell_y, run), MAX_CELLS) \
				* CELL_TILES * BAND
			var base: int = (cell_y + run) * CELL_TILES - 1
			for step: int in run:
				for row: int in CELL_TILES:
					var ty: int = (cell_y + step) * CELL_TILES + row
					for column: int in CELL_TILES:
						var at: int = ty * _size.x + cell_x * CELL_TILES + column
						# A pinned tile inside an otherwise unmeasured cell keeps
						# the height its pin gave it.
						if _heights[at] == -1:
							_heights[at] = height
							_bases[at] = base
			cell_y += run


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


## The pixels of one CELL that belong to the drawing rather than to the ground
## behind it, as a 16x16 mask, keyed on the cell's four tiles.
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
const RING_SHARE: float = 0.7
var _masks: Dictionary = {}


func _cell_mask(cell_tiles: Array, atlas: RefCounted) -> PackedByteArray:
	var key: String = "%d,%d,%d,%d" % cell_tiles
	if _masks.has(key):
		return _masks[key]

	var size: int = CELL_TILES * int(TILE)
	var indices := PackedInt32Array()
	indices.resize(size * size)
	for py: int in size:
		for px: int in size:
			@warning_ignore("integer_division")
			var tile: int = cell_tiles[(py / int(TILE)) * CELL_TILES + px / int(TILE)]
			indices[py * size + px] = atlas.pixel(tile, px % int(TILE), py % int(TILE))

	var ring: Dictionary = {}
	var ring_count: int = 0
	for step: int in size:
		for at: int in [step, (size - 1) * size + step, step * size, step * size + size - 1]:
			ring[indices[at]] = int(ring.get(indices[at], 0)) + 1
			ring_count += 1
	var ranked: Array = ring.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return ring[a] > ring[b])
	var ground: Dictionary = {}
	var covered: int = 0
	for index: int in ranked:
		if covered >= float(ring_count) * RING_SHARE:
			break
		ground[index] = true
		covered += int(ring[index])

	var mask := PackedByteArray()
	mask.resize(size * size)
	mask.fill(1)
	var stack := PackedInt32Array()
	for step: int in size:
		for at: int in [step, (size - 1) * size + step, step * size, step * size + size - 1]:
			stack.append(at)
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if mask[at] == 0 or not ground.has(indices[at]):
			continue
		mask[at] = 0
		@warning_ignore("integer_division")
		var py: int = at / size
		var px: int = at % size
		if px > 0:
			stack.append(at - 1)
		if px < size - 1:
			stack.append(at + 1)
		if py > 0:
			stack.append(at - size)
		if py < size - 1:
			stack.append(at + size)

	_masks[key] = mask
	return mask


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
func _cutout(tx: int, ty: int, depth: float, atlas: RefCounted) -> void:
	var cell := Vector2i(tx >> 1, ty >> 1)
	var cell_tiles: Array = []
	for row: int in CELL_TILES:
		for column: int in CELL_TILES:
			cell_tiles.append(_tile_at(cell.x * CELL_TILES + column, cell.y * CELL_TILES + row))
	var mask: PackedByteArray = _cell_mask(cell_tiles, atlas)

	var span: int = CELL_TILES * int(TILE)
	var edge: int = int(TILE)
	var tile: int = _tiles[ty * _size.x + tx]
	var origin := Vector2i((tx & 1) * edge, (ty & 1) * edge)
	var mid: float = float(cell.y) * CELL_TILES * TILE + CELL_TILES * TILE * 0.5
	var back: float = mid - depth * 0.5
	var front: float = mid + depth * 0.5

	var taken := PackedByteArray()
	taken.resize(edge * edge)
	for row: int in edge:
		for column: int in edge:
			if taken[row * edge + column] == 1 \
					or not _drawn(mask, span, origin.x + column, origin.y + row):
				continue
			var wide: int = 1
			while column + wide < edge and taken[row * edge + column + wide] == 0 \
					and _drawn(mask, span, origin.x + column + wide, origin.y + row):
				wide += 1
			var tall: int = 1
			while row + tall < edge:
				var whole: bool = true
				for step: int in wide:
					if taken[(row + tall) * edge + column + step] == 1 \
							or not _drawn(mask, span, origin.x + column + step, origin.y + row + tall):
						whole = false
						break
				if not whole:
					break
				tall += 1
			for down: int in tall:
				for across: int in wide:
					taken[(row + down) * edge + column + across] = 1
			_cutout_box(
				tx, tile, atlas, mask, origin, span,
				Rect2i(column, row, wide, tall), back, front
			)


## One rectangle of a cutout, as a box wearing its own texels.
##
## Every face along an edge the drawing continues past is left out, and the ones
## along an edge it does not are cut into the RUNS that are actually exposed. A
## face emitted whole where the drawing continues under half of it would be
## hidden anyway; cutting it is what keeps a silhouette's edge exactly the
## drawing's, and what lets the end walls wear their own end pixel's colour so a
## cut edge is never a foreign one.
func _drawn(mask: PackedByteArray, span: int, px: int, py: int) -> bool:
	if px < 0 or py < 0 or px >= span or py >= span:
		return false
	return mask[py * span + px] == 1


func _cutout_box(
	tx: int, tile: int, atlas: RefCounted, mask: PackedByteArray,
	origin: Vector2i, span: int, box: Rect2i, back: float, front: float
) -> void:
	var x0: float = float(tx) * TILE + float(box.position.x)
	var x1: float = x0 + float(box.size.x)
	var high: float = float(span - (origin.y + box.position.y))
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
						tx, tile, atlas, origin, span, box, back, front,
						horizontal, near, run, step
					)
					run = -1


func _cutout_edge(
	tx: int, tile: int, atlas: RefCounted, origin: Vector2i, span: int, box: Rect2i,
	back: float, front: float, horizontal: bool, near: bool, from: int, to: int
) -> void:
	if horizontal:
		var x0: float = float(tx) * TILE + float(box.position.x + from)
		var x1: float = float(tx) * TILE + float(box.position.x + to)
		var y: float = float(span - (origin.y + box.position.y)) \
			- (0.0 if near else float(box.size.y))
		var uv: Rect2 = atlas.uv_box(
			tile, Rect2i(box.position.x + from, box.position.y + (0 if near else box.size.y - 1),
				to - from, 1)
		)
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
	var high: float = float(span - (origin.y + box.position.y + from))
	var low: float = float(span - (origin.y + box.position.y + to))
	var uv: Rect2 = atlas.uv_box(
		tile, Rect2i(box.position.x + (0 if near else box.size.x - 1),
			box.position.y + from, 1, to - from)
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


## The art a cutout stands ON: the nearest neighbouring tile that is flat ground,
## because a cutout's own drawing is the object and painting it on the floor as
## well would leave a bollard lying under itself.
func _ground_art(tx: int, ty: int) -> int:
	for step: Vector2i in [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
	]:
		var at := Vector2i(tx + step.x, ty + step.y)
		if at.x < 0 or at.y < 0 or at.x >= _size.x or at.y >= _size.y:
			continue
		var index: int = at.y * _size.x + at.x
		if _art[index] == ART_FLAT and _heights[index] == 0:
			return maxi(_tiles[index], 0)
	return maxi(_tiles[ty * _size.x + tx], 0)


func _emit(tx: int, ty: int, atlas: RefCounted) -> void:
	var at: int = ty * _size.x + tx
	var tile: int = _tiles[at]
	if tile < 0:
		return
	if _art[at] == ART_CUTOUT:
		_face_top(tx, ty, 0.0, atlas.uv(_ground_art(tx, ty)), SHADE_TOP_FLAT)
		_cutout(tx, ty, float(_depths[at]), atlas)
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


func _push(vertex: Vector3, normal: Vector3, uv: Vector2, shade: Color) -> void:
	_vertices.push_back(vertex)
	_normals.push_back(normal)
	_uvs.push_back(uv)
	_colors.push_back(shade)
