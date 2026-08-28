extends RefCounted

## Which drawing stands where, on a map that was never resolved.

const TileShapeScript: GDScript = preload("tile_shape.gd")
const MapSourceScript: GDScript = preload("map_source.gd")

const TILE: int = 8
const CELL_TILES: int = 2
const BLOCK_TILES: int = 4
const CELLS_PER_BLOCK: int = 2
const SPOT_LIMIT: int = 4096


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

	var tiles := PackedInt32Array()
	var klass := PackedInt32Array()
	tiles.resize(size.x * size.y)
	klass.resize(size.x * size.y)
	var ids: Dictionary = {}
	var known: Dictionary = {}
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


static func _walk(
	shape: RefCounted, tiles: PackedInt32Array, klass: PackedInt32Array,
	named_by_id: Array, size: Vector2i, origin: Vector2i
) -> Dictionary:
	var out: Dictionary = {}
	var seen: Dictionary = {}
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


static func _box(
	shape: RefCounted, named: StringName, tiles: PackedInt32Array,
	klass: PackedInt32Array, size: Vector2i, origin: Vector2i,
	tx: int, ty: int, want: int, decided: Dictionary
) -> Rect2i:
	var span: Vector2i = shape.span_cells(named)
	var across := Vector2i(maxi(span.x, 1), maxi(span.y, 1)) * CELL_TILES
	var here := Vector2i(origin.x + tx, origin.y + ty)
	var start := Vector2i(
		here.x - posmod(here.x, across.x), here.y - posmod(here.y, across.y)
	) - origin
	if across == Vector2i(CELL_TILES, CELL_TILES) or shape.art(named) != &"cutout":
		return Rect2i(start, across)
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
		whole = not _repeats(tiles, size, start, Vector2i(
			maxi(span.x, 1), maxi(span.y, 1)
		))
	return [whole, rows]


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


static func _tile_at(
	tiles: PackedInt32Array, size: Vector2i, tx: int, ty: int
) -> int:
	if tx < 0 or ty < 0 or tx >= size.x or ty >= size.y:
		return 0
	return maxi(tiles[ty * size.x + tx], 0)
