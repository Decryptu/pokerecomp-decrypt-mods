extends RefCounted

## Which drawing stands where, on a map that was never resolved.
##
## `world/far_foliage.gd` needs the name of the drawing on each cell so
## `shape/mesher.gd:far_card_for` can cut it out of the map's own sheet. A resolve
## answers that and costs a quarter of a second a map, which is out of the question
## for the tens of maps a horizon holds.
##
## The name of a drawing is its arrangement of tiles. `mesher._model_bodies_of`
## keys every model mesh on `str(tiles)` over the drawing's box, so reading the
## same box off a bare map and stringing it the same way is the whole lookup.
## Nothing here builds geometry, measures a silhouette, floods a mask or asks
## about height: it reads tile ids and collision, which is why it is milliseconds.
##
## The box rule is a second copy of the mesher's, which is the one thing here
## worth arguing about: `mesher._box_start` and `mesher._measure_cutouts` are
## spent against arrays only a full resolve fills. `tools/far_drawings.gd` holds
## the copy honest, resolving each map for real and checking every box this walk
## found against every box the mesher stamped a model into, over the 229 outdoor
## maps of the three cartridges. Unify it when the span measurement is worth
## moving.
##
## A map is walked once and its answer kept, since a map's trees do not move.

const TileShapeScript: GDScript = preload("tile_shape.gd")
const MapSourceScript: GDScript = preload("map_source.gd")

## Pixels across one tile, and tiles across one walk cell.
const TILE: int = 8
const CELL_TILES: int = 2
## Tiles across one block, which is what the world past the maps is tiled with.
## See [method of_border].
const BLOCK_TILES: int = 4
## Walk cells across one block.
const CELLS_PER_BLOCK: int = 2
## The most drawings one map may stand, so a pathological tileset cannot fill
## memory. Route 32, the thickest wood in the game, comes out near 1200.
const SPOT_LIMIT: int = 4096


## What stands on [param map], as `{ drawings, buildings }`.
##
## `drawings` is `str(tiles) -> { spots, class, tiles, across }`. The spots are in
## that map's own world pixels and there is ONE PER DRAWING rather than one per
## cell: a conifer is one card standing between the two cells it is drawn over,
## exactly as the mesh stamps one model there. The rest is what
## `shape/mesher.gd:far_card_for` needs to cut that drawing out of this map's own
## sheet: the tiles themselves, how many of them the drawing runs across, and the
## class whose facts say how it is masked and how it stands.
##
## `buildings` is what `world/far_houses.gd` stands, one entry a building. Both
## come off ONE pass over the map, because reading its tiles is what the walk
## actually costs.
##
## [param margin] widens the walk past the map's own edge, in tiles, which is
## what the LOADED map wants: the mesh resolves the map inside a border ring and
## stamps models out there too, so a view standing its own cards past the mesh
## has to cover the same ring or leave a band with nothing on it. `map_source.gd`
## answers past the edge already, with the connection strip and the neighbouring
## maps folded in, so the ring reads exactly as the mesh reads it. Spots come back
## in the MAP'S own pixels either way, negative inside the ring.
static func of_map(
	data: GameData, map: Gen2WorldMap, profile: GDScript, margin: int = 0
) -> Dictionary:
	var out: Dictionary = {"drawings": {}, "buildings": []}
	if data == null or map == null:
		return out
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return out
	var shape: RefCounted = TileShapeScript.new(profile, map.tileset)
	var source: RefCounted = MapSourceScript.new(null, map, tileset, data)
	var origin := Vector2i(-margin, -margin)
	var size := Vector2i(map.width_blocks, map.height_blocks) \
		* RomLayout.MAP_BLOCK_TILE_WIDTH + Vector2i(margin, margin) * 2
	if size.x <= 0 or size.y <= 0:
		return out

	# The whole map read once: a tile id and the class it resolves to, per tile.
	# The class follows from the tile and the cell's permission and from nothing
	# else, which is `mesher._tile_fact`'s own reason for keying its cache that
	# way, so the profile is asked once per distinct pair rather than per tile.
	var tiles := PackedInt32Array()
	var klass := PackedInt32Array()
	tiles.resize(size.x * size.y)
	klass.resize(size.x * size.y)
	var ids: Dictionary = {}
	var known: Dictionary = {}
	# Read a block at a time. Resolving a tile means resolving the block it sits
	# in, and a block holds sixteen of them: asked per tile, a walk over a map and
	# its border ring resolves the same block sixteen times over and costs 66 ms
	# on route 26 against 24. The PERMISSION is still asked per cell, because
	# inside the map it is the map's own collision and not the block's.
	@warning_ignore("integer_division")
	var blocks := Vector2i(
		size.x / BLOCK_TILES, size.y / BLOCK_TILES
	)
	@warning_ignore("integer_division")
	var block_origin: Vector2i = origin / BLOCK_TILES
	for by: int in blocks.y:
		for bx: int in blocks.x:
			var block: int = source.block_at(
				block_origin.x + bx, block_origin.y + by
			)
			for cy: int in CELLS_PER_BLOCK:
				for cx: int in CELLS_PER_BLOCK:
					var permission: int = source.permission_at(Vector2i(
						block_origin.x * CELLS_PER_BLOCK + bx * CELLS_PER_BLOCK + cx,
						block_origin.y * CELLS_PER_BLOCK + by * CELLS_PER_BLOCK + cy
					))
					for down: int in CELL_TILES:
						for right: int in CELL_TILES:
							var slot_x: int = cx * CELL_TILES + right
							var slot_y: int = cy * CELL_TILES + down
							var at: int = (by * BLOCK_TILES + slot_y) * size.x \
								+ bx * BLOCK_TILES + slot_x
							var tile: int = -1 if block < 0 else tileset.tile_index(
								block, slot_y * BLOCK_TILES + slot_x
							)
							tiles[at] = tile
							if tile < 0:
								klass[at] = -1
								continue
							var pair: int = tile * 256 + permission + 1
							if not known.has(pair):
								var named: StringName = shape.at(tile, permission)
								if not ids.has(named):
									ids[named] = ids.size()
								known[pair] = ids[named]
							klass[at] = known[pair]
	var named_by_id: Array = _named_by_id(ids)
	out["drawings"] = _walk(shape, tiles, klass, named_by_id, size, origin)
	out["buildings"] = _buildings(shape, tiles, klass, named_by_id, size, origin)
	return out


## Every building on the map, as `{ rect, rows, tiles }`: the rectangle it covers
## in TILES, what each of its rows draws, and the tile ids inside it, which is
## what a box is painted from.
##
## A row is roof, WALL OR NEITHER, and it is answered per row rather than as two
## counts: a flood joins two houses that touch, and a rectangle that holds them
## both has rows of each in whatever order they stand. `world/far_houses.gd` is
## where that is read, and it is the only place that has to care.
##
## A building is found by its CLASS and not by the arrangement `shape/houses.gd`
## paints: the painted table is the near view's, it is an override on a hundred
## drawings of the several hundred placed, and reading it needs the resolve's own
## matching pass. Out here a rectangle is all that is standing, so the profile's
## own `facade` and `roof` are enough to find one and to say which of its rows is
## which. See `world/far_houses.gd` for what is built from it.
##
## Connected by the four sides, because a town draws its houses with a tile of
## ground between them and a terrace as one run.
static func _buildings(
	shape: RefCounted, tiles: PackedInt32Array, klass: PackedInt32Array,
	named_by_id: Array, size: Vector2i, origin: Vector2i
) -> Array:
	var part := PackedByteArray()
	part.resize(size.x * size.y)
	var any: bool = false
	var known: Dictionary = {}
	for at: int in klass.size():
		if klass[at] < 0:
			continue
		if not known.has(klass[at]):
			var built: StringName = shape.building_part(named_by_id[klass[at]])
			known[klass[at]] = 2 if built == &"roof" else (1 if built == &"wall" else 0)
		part[at] = known[klass[at]]
		any = any or part[at] > 0
	var out: Array = []
	if not any:
		return out
	var seen := PackedByteArray()
	seen.resize(size.x * size.y)
	for ty: int in size.y:
		for tx: int in size.x:
			var at: int = ty * size.x + tx
			if part[at] == 0 or seen[at] == 1:
				continue
			seen[at] = 1
			var stack: Array = [Vector2i(tx, ty)]
			var box := Rect2i(tx, ty, 1, 1)
			var roofs: Dictionary = {}
			var walls: Dictionary = {}
			while not stack.is_empty():
				var here: Vector2i = stack.pop_back()
				box = box.expand(here).expand(here + Vector2i.ONE)
				if part[here.y * size.x + here.x] == 2:
					roofs[here.y] = true
				else:
					walls[here.y] = true
				for way: Vector2i in [
					Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
				]:
					var next: Vector2i = here + way
					if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
						continue
					var index: int = next.y * size.x + next.x
					if part[index] == 0 or seen[index] == 1:
						continue
					seen[index] = 1
					stack.append(next)
			var drawn: Array = []
			var rows := PackedByteArray()
			rows.resize(box.size.y)
			for row: int in box.size.y:
				rows[row] = 2 if roofs.has(box.position.y + row) \
					else (1 if walls.has(box.position.y + row) else 0)
				for column: int in box.size.x:
					drawn.append(_tile_at(
						tiles, size, box.position.x + column, box.position.y + row
					))
			out.append({
				"rect": Rect2i(box.position + origin, box.size),
				"rows": rows, "tiles": drawn,
			})
	return out


## The drawings in a map's border block, which is the whole of the world past the
## maps: `world/far_field.gd` fills everything the camera can reach with that one
## block, so out there the same thirty-two pixels repeat for ever, and on forty of
## the seventy-seven outdoor maps every tile of them is a tree.
##
## Answered in the BLOCK'S own pixels and otherwise exactly as [method of_map]
## answers, so the same card is cut for it and the same stamp stands it.
##
## The box rule needs no more than the block: a drawing is two or four tiles
## across and a block is four, and both align on the same lattice, so nothing
## straddles two of them.
static func of_border(
	data: GameData, map: Gen2WorldMap, profile: GDScript
) -> Dictionary:
	var out: Dictionary = {}
	if data == null or map == null:
		return out
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return out
	var shape: RefCounted = TileShapeScript.new(profile, map.tileset)
	var size := Vector2i(BLOCK_TILES, BLOCK_TILES)
	var tiles := PackedInt32Array()
	var klass := PackedInt32Array()
	tiles.resize(size.x * size.y)
	klass.resize(size.x * size.y)
	var ids: Dictionary = {}
	for ty: int in size.y:
		for tx: int in size.x:
			var at: int = ty * size.x + tx
			var tile: int = tileset.tile_index(map.border_block, ty * BLOCK_TILES + tx)
			tiles[at] = tile
			if tile < 0:
				klass[at] = -1
				continue
			@warning_ignore("integer_division")
			var permission: int = tileset.collision_index(
				map.border_block, tx / CELL_TILES, ty / CELL_TILES
			)
			var named: StringName = shape.at(tile, permission)
			if not ids.has(named):
				ids[named] = ids.size()
			klass[at] = ids[named]
	return _walk(shape, tiles, klass, _named_by_id(ids), size, Vector2i.ZERO)


static func _named_by_id(ids: Dictionary) -> Array:
	var out: Array = []
	out.resize(ids.size())
	for named: StringName in ids:
		out[ids[named]] = named
	return out


## Every drawing standing on a grid of tiles already resolved to classes, as
## `str(tiles) -> { spots, class, tiles, across }`.
##
## One entry per BOX rather than per tile: every tile of a drawing resolves to
## the same box, and the box is what wears a card.
static func _walk(
	shape: RefCounted, tiles: PackedInt32Array, klass: PackedInt32Array,
	named_by_id: Array, size: Vector2i, origin: Vector2i
) -> Dictionary:
	var out: Dictionary = {}
	var seen: Dictionary = {}
	# What each declared box came to, kept because every tile of a drawing asks
	# the same question and the answer costs a flood of row tests and a string a
	# cell. Asked per tile it was most of the walk: 62 ms on route 26 against 24.
	var decided: Dictionary = {}
	var placed: int = 0
	for ty: int in size.y:
		for tx: int in size.x:
			var at: int = ty * size.x + tx
			if klass[at] < 0:
				continue
			var named: StringName = named_by_id[klass[at]]
			if not shape.is_model(named):
				continue
			var box: Rect2i = _box(
				shape, named, tiles, klass, size, origin, tx, ty, klass[at], decided
			)
			# The box AND the class it was cut for. A box start belongs to one
			# box of one class, but a cell-sized fallback and a taller drawing
			# above it can start on the same tile, and keying on the position
			# alone would drop whichever was reached second. Offset, because a
			# box inside the border ring starts at a NEGATIVE tile.
			var mark: int = ((box.position.y + 4096) * 8192
				+ box.position.x + 4096) * 1024 + klass[at]
			if seen.has(mark):
				continue
			seen[mark] = true
			var drawn: Array = []
			for row: int in box.size.y:
				for column: int in box.size.x:
					drawn.append(_tile_at(
						tiles, size, box.position.x + column, box.position.y + row
					))
			var key: String = str(drawn)
			if not out.has(key):
				out[key] = {
					"spots": PackedVector2Array(),
					"class": named,
					"tiles": drawn,
					"across": box.size,
				}
			# Read out, pushed and put back, because a packed array is a VALUE:
			# pushing into the one the dictionary answers with fills a copy, and
			# every map came back with its drawings named and no spots under them.
			var entry: Dictionary = out[key]
			var spots: PackedVector2Array = entry["spots"]
			spots.push_back(Vector2(
				float((origin.x + box.position.x) * TILE)
					+ float(box.size.x * TILE) * 0.5,
				float((origin.y + box.position.y) * TILE)
					+ float(box.size.y * TILE) * 0.5
			))
			entry["spots"] = spots
			placed += 1
			if placed >= SPOT_LIMIT:
				return out
	return out


## The box one drawing is cut over, in tiles. `mesher._span_box` and
## `mesher._measure_cutouts` together, read off the class rather than off a
## resolve's arrays; see this file's own note on why it is a copy.
##
## A class declares the largest its drawing gets and the PLACEMENT says whether
## this one is that big: the box is taken where every row of it carries the
## class and no cell of it draws what another cell draws, and one cell otherwise.
## That last test is what tells a tall conifer, a pointed cell over a footed one,
## from a pair of short ones, which is the same cell twice.
static func _box(
	shape: RefCounted, named: StringName, tiles: PackedInt32Array,
	klass: PackedInt32Array, size: Vector2i, origin: Vector2i,
	tx: int, ty: int, want: int, decided: Dictionary
) -> Rect2i:
	var span: Vector2i = shape.span_cells(named)
	var across := Vector2i(maxi(span.x, 1), maxi(span.y, 1)) * CELL_TILES
	# Aligned on the map and not on the walk. `mesher._box_start` takes a map
	# coordinate modulo the box, and a walk that starts inside the border ring is
	# offset from the map by however deep the ring is: aligning on the walk's own
	# origin boxes every drawing in the ring half a cell out.
	var here := Vector2i(origin.x + tx, origin.y + ty)
	var start := Vector2i(
		here.x - posmod(here.x, across.x), here.y - posmod(here.y, across.y)
	) - origin
	if across == Vector2i(CELL_TILES, CELL_TILES) or shape.art(named) != &"cutout":
		return Rect2i(start, across)
	# Asked once per declared box. Whether the box is whole and how far it is cut
	# back follow from the box and the class alone, so every tile of a drawing
	# gets the same answer and only the first pays for it.
	var mark: int = ((start.y + 4096) * 8192 + start.x + 4096) * 1024 + want
	var answer: Array = decided.get(mark, [])
	if answer.is_empty():
		answer = _decide(shape, named, span, across, tiles, klass, size, start, want)
		decided[mark] = answer
	if not bool(answer[0]):
		return Rect2i(
			Vector2i(
				here.x - posmod(here.x, CELL_TILES),
				here.y - posmod(here.y, CELL_TILES)
			) - origin,
			Vector2i(CELL_TILES, CELL_TILES)
		)
	return Rect2i(start, Vector2i(across.x, int(answer[1])))


## Whether one declared box is the whole drawing, and how many tile rows of it
## are, as `[whole, rows]`. `mesher._measure_cutouts`' own two tests.
static func _decide(
	shape: RefCounted, named: StringName, span: Vector2i, across: Vector2i,
	tiles: PackedInt32Array, klass: PackedInt32Array, size: Vector2i,
	start: Vector2i, want: int
) -> Array:
	var lying: bool = shape.is_lying(named)
	var rows: int = across.y
	if not lying:
		while rows > CELL_TILES \
				and not _row_carries(klass, size, start, rows - 1, across.x, want):
			rows -= 1
	var whole: bool = true
	for row: int in rows:
		if not _row_carries(klass, size, start, row, across.x, want):
			whole = false
			break
	if whole and not lying:
		# The CLASS'S OWN span and not the rows left, which is `_measure_cutouts`'
		# order: a drawing cut back to three tiles is still asked about the two
		# cells it was declared over.
		whole = not _repeats(tiles, size, start, Vector2i(
			maxi(span.x, 1), maxi(span.y, 1)
		))
	return [whole, rows]


## Whether every tile of one row of the box carries the class.
static func _row_carries(
	klass: PackedInt32Array, size: Vector2i, start: Vector2i, row: int,
	wide: int, want: int
) -> bool:
	var ty: int = start.y + row
	if ty < 0 or ty >= size.y:
		return false
	for column: int in wide:
		var tx: int = start.x + column
		if tx < 0 or tx >= size.x or klass[ty * size.x + tx] != want:
			return false
	return true


## Whether any cell of the box draws exactly what another cell of it draws, in
## walk cells. `mesher._repeats`, and it is what tells one tall drawing from a
## row of short ones: a conifer is a pointed cell over a footed cell and the two
## differ, where a pair of short trees is the same cell twice.
static func _repeats(
	tiles: PackedInt32Array, size: Vector2i, start: Vector2i, span: Vector2i
) -> bool:
	var seen: Dictionary = {}
	for row: int in span.y:
		for column: int in span.x:
			var cell: Array = []
			for down: int in CELL_TILES:
				for right: int in CELL_TILES:
					cell.append(_tile_at(
						tiles, size,
						start.x + column * CELL_TILES + right,
						start.y + row * CELL_TILES + down
					))
			var key: String = str(cell)
			if seen.has(key):
				return true
			seen[key] = true
	return false


## The tile id at a map tile position, or 0 past the map, which is what
## `mesher._tile_at` answers past its own grid.
static func _tile_at(
	tiles: PackedInt32Array, size: Vector2i, tx: int, ty: int
) -> int:
	if tx < 0 or ty < 0 or tx >= size.x or ty >= size.y:
		return 0
	return maxi(tiles[ty * size.x + tx], 0)
