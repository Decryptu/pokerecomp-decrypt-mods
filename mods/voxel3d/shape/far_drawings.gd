extends RefCounted

## WHICH DRAWING STANDS WHERE, on a map that was never resolved.
##
## `world/far_foliage.gd` dresses the maps on the horizon, and what it needs per
## cell is the name of the drawing standing on it, so `shape/mesher.gd:far_card_for`
## can cut that drawing out of the map's own sheet. A resolve answers both and
## costs a quarter of a second a map, which is out of the question for the tens
## of maps a horizon holds.
##
## THE NAME OF A DRAWING IS ITS ARRANGEMENT OF TILES. `mesher._model_bodies_of`
## keys every model mesh it builds on `str(tiles)` over the drawing's own box, so
## reading the same box off a bare map and stringing it the same way is the whole
## of the lookup. Nothing here builds geometry, measures a silhouette, floods a
## mask or asks about height: it reads tile ids and collision, which is what
## makes it milliseconds.
##
## THE BOX IS THE MESHER'S OWN RULE and this is a second copy of it, which is the
## one thing in this file worth arguing about. The rule lives in
## `mesher._box_start` and `mesher._measure_cutouts`, spent against arrays that
## only a full resolve fills, and lifting it out from under ten thousand lines
## that share those arrays is a bigger change than the horizon is worth today.
## So it is copied, deliberately, and `tools/far_drawings.gd` is what holds the
## copy honest: it resolves each map for real and checks every box this walk
## found against every box the mesher stamped a model into, over the 229 outdoor
## maps of the three cartridges. Unify it the day the span measurement is worth
## moving.
##
## A MAP IS WALKED ONCE and its answer kept, since a map's trees do not move.

const TileShapeScript: GDScript = preload("tile_shape.gd")
const MapSourceScript: GDScript = preload("map_source.gd")

## Pixels across one tile, and tiles across one walk cell.
const TILE: int = 8
const CELL_TILES: int = 2
## The most drawings one map may stand, so a pathological tileset cannot fill
## memory. Route 32, the thickest wood in the game, comes out near 1200.
const SPOT_LIMIT: int = 4096


## Where each drawing stands on [param map], and what it is.
##
## `str(tiles) -> { spots, class, tiles, across }`. The spots are in that map's
## own world pixels and there is ONE PER DRAWING rather than one per cell: a
## conifer is one card standing between the two cells it is drawn over, exactly
## as the mesh stamps one model there. The rest is what
## `shape/mesher.gd:far_card_for` needs to cut that drawing out of this map's own
## sheet: the tiles themselves, how many of them the drawing runs across, and the
## class whose facts say how it is masked and how it stands.
static func of_map(data: GameData, map: Gen2WorldMap, profile: GDScript) -> Dictionary:
	var out: Dictionary = {}
	if data == null or map == null:
		return out
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	if tileset == null:
		return out
	var shape: RefCounted = TileShapeScript.new(profile, map.tileset)
	var source: RefCounted = MapSourceScript.new(null, map, tileset, data)
	var size := Vector2i(map.width_blocks, map.height_blocks) \
		* RomLayout.MAP_BLOCK_TILE_WIDTH
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
	# Asked per CELL and spent on its four tiles, because the permission is the
	# cell's: asking it per tile is the same answer fetched four times, and this
	# walk is paid for on the frame a map comes into view.
	@warning_ignore("integer_division")
	var cells := Vector2i(size.x / CELL_TILES, size.y / CELL_TILES)
	for cy: int in cells.y:
		for cx: int in cells.x:
			var permission: int = source.permission_at(Vector2i(cx, cy))
			for down: int in CELL_TILES:
				for right: int in CELL_TILES:
					var tx: int = cx * CELL_TILES + right
					var ty: int = cy * CELL_TILES + down
					var at: int = ty * size.x + tx
					var tile: int = source.tile_at(tx, ty)
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
	var named_by_id: Array = []
	named_by_id.resize(ids.size())
	for named: StringName in ids:
		named_by_id[ids[named]] = named

	# One entry per BOX rather than per tile: every tile of a drawing resolves to
	# the same box, and the box is what wears a card.
	var seen: Dictionary = {}
	var placed: int = 0
	for ty: int in size.y:
		for tx: int in size.x:
			var at: int = ty * size.x + tx
			if klass[at] < 0:
				continue
			var named: StringName = named_by_id[klass[at]]
			if not shape.is_model(named):
				continue
			var box: Rect2i = _box(shape, named, tiles, klass, size, tx, ty, klass[at])
			# The box AND the class it was cut for. A box start belongs to one
			# box of one class, but a cell-sized fallback and a taller drawing
			# above it can start on the same tile, and keying on the position
			# alone would drop whichever was reached second.
			var mark: int = (box.position.y * size.x + box.position.x) * 1024 + klass[at]
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
				float(box.position.x * TILE) + float(box.size.x * TILE) * 0.5,
				float(box.position.y * TILE) + float(box.size.y * TILE) * 0.5
			))
			entry["spots"] = spots
			placed += 1
			if placed >= SPOT_LIMIT:
				return out
	return out


## THE BOX ONE DRAWING IS CUT OVER, in tiles. `mesher._span_box` and
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
	klass: PackedInt32Array, size: Vector2i, tx: int, ty: int, want: int
) -> Rect2i:
	var span: Vector2i = shape.span_cells(named)
	var across := Vector2i(maxi(span.x, 1), maxi(span.y, 1)) * CELL_TILES
	var start := Vector2i(tx - posmod(tx, across.x), ty - posmod(ty, across.y))
	if across == Vector2i(CELL_TILES, CELL_TILES) or shape.art(named) != &"cutout":
		return Rect2i(start, across)
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
	if not whole:
		return Rect2i(
			Vector2i(tx - posmod(tx, CELL_TILES), ty - posmod(ty, CELL_TILES)),
			Vector2i(CELL_TILES, CELL_TILES)
		)
	return Rect2i(start, Vector2i(across.x, rows))


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
