extends SceneTree

## WHERE THE TERRAIN IS OPEN, found in the mesh itself rather than in a
## picture. Two tests: two rims over one line of ground, and an upright edge
## bounding one face where a corner wants two. A joint between edges of unequal
## length and a side a room cuts away for the camera are both closed ground, and
## neither is counted. A mesh opening is not always a visible one, since a solid
## may stand behind it, so a picture still decides.

const MOD := "user://mods/voxel3d"
const TILE: float = 8.0
const GRID: float = 100.0
const NAMED: int = 24


var _tally: Dictionary = {}
var _scripts: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [group,number|ts<n>|all] [least pixels]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var select: String = args[1] if args.size() > 1 else "all"
	var least: int = int(args[2]) if args.size() > 2 else 1
	for part: String in ["profile", "atlas", "mesher", "tile_shape", "map_source"]:
		_scripts[part] = load("%s/shape/%s.gd" % [MOD, part])
	_tally = {
		"drop": {}, "tileset": {}, "place": {}, "run": {},
		"maps": 0, "open": 0, "total": 0, "named": 0,
	}
	for map: Gen2WorldMap in data.world_maps():
		if _wanted(map, select):
			_measure(data, map, select, least)
	print("%d maps, %d with cracks, %d cracks" % [
		int(_tally["maps"]), int(_tally["open"]), int(_tally["total"]),
	])
	var total: int = int(_tally["total"])
	_ranked("by run", _tally["run"], total, "%s")
	_ranked("by drop", _tally["drop"], total, "%.1f px")
	_ranked("by place", _tally["place"], total, "%s")
	_ranked("by tileset", _tally["tileset"], total, "ts%d")
	quit(0)


func _measure(
	data: GameData, map: Gen2WorldMap, select: String, least: int
) -> void:
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var atlas: RefCounted = (_scripts["atlas"] as GDScript).new()
	var animation := Gen2WorldAnimation.new()
	animation.configure_tileset(data, tileset, 1)
	if not atlas.build(data, map, tileset, 1, animation):
		return
	var shape: RefCounted = (_scripts["tile_shape"] as GDScript).new(
		_scripts["profile"], map.tileset
	)
	var source: RefCounted = (_scripts["map_source"] as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (_scripts["mesher"] as GDScript).new()
	mesher.resolve(source, shape)
	var meshes: Array = mesher.emit(atlas)
	var water: Array = mesher.take_water()
	_tally["maps"] = int(_tally["maps"]) + 1
	_show_bare(map, select, _bare(meshes + water + mesher.take_tufts()))
	_show_cracks(
		map, select, source.outside(), _cracks(meshes + water, least, mesher)
	)


func _show_bare(map: Gen2WorldMap, select: String, bare: Array) -> void:
	if bare.is_empty() or int(_tally["named"]) >= NAMED:
		return
	print("%s  ts%d  %d tiles with no floor at all" % [
		"%d,%d" % [map.group, map.number], map.tileset, bare.size()
	])
	for index: int in (bare.size() if select != "all" else mini(12, bare.size())):
		print("   tile %d,%d" % [bare[index].x, bare[index].y])


func _show_cracks(
	map: Gen2WorldMap, select: String, outside: bool, cracks: Array
) -> void:
	_tally["total"] = int(_tally["total"]) + cracks.size()
	if cracks.is_empty():
		return
	_tally["open"] = int(_tally["open"]) + 1
	_count_in(_tally["place"], "outside" if outside else "inside", cracks.size())
	_count_in(_tally["tileset"], map.tileset, cracks.size())
	for crack: Dictionary in cracks:
		_count_in(_tally["drop"], snappedf(float(crack["drop"]), 0.1), 1)
		_count_in(_tally["run"], crack["run"], 1)
	if int(_tally["named"]) >= NAMED:
		return
	_tally["named"] = int(_tally["named"]) + 1
	print("%s  ts%d  %d cracks" % [
		"%d,%d" % [map.group, map.number], map.tileset, cracks.size()
	])
	cracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["drop"]) > float(b["drop"]))
	for index: int in (cracks.size() if select != "all" else mini(12, cracks.size())):
		var crack: Dictionary = cracks[index]
		print("   tile %-9s %-11s  %5.1f to %-5.1f  drop %.1f px  %s" % [
			"%d,%d" % [crack["tile"].x, crack["tile"].y], crack["run"],
			crack["low"], crack["high"], crack["drop"], crack["line"],
		])
	if select == "all" and cracks.size() > 12:
		print("   ... and %d more" % (cracks.size() - 12))


func _count_in(counts: Dictionary, key: Variant, more: int) -> void:
	counts[key] = int(counts.get(key, 0)) + more


func _ranked(title: String, counts: Dictionary, total: int, form: String) -> void:
	if total <= 0:
		return
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(counts[a]) > int(counts[b]))
	print(title)
	for key: Variant in keys:
		print("   %-10s %6d  %4.1f%%" % [
			form % key, int(counts[key]), 100.0 * float(counts[key]) / float(total),
		])


func _wanted(map: Gen2WorldMap, select: String) -> bool:
	if select == "all":
		return true
	if select.begins_with("ts"):
		return map.tileset == int(select.substr(2))
	var pair: PackedStringArray = select.split(",")
	return pair.size() == 2 and map.group == int(pair[0]) and map.number == int(pair[1])


func _bare(meshes: Array) -> Array:
	var covered: Dictionary = {}
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for mesh: ArrayMesh in meshes:
		for surface: int in mesh.get_surface_count():
			var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for at: int in range(0, points.size() - 2, 3):
				var a: Vector3 = points[at]
				var b: Vector3 = points[at + 1]
				var c: Vector3 = points[at + 2]
				if absf((b - a).cross(c - a).normalized().y) <= 0.05:
					continue
				var middle: Vector3 = (a + b + c) / 3.0
				var tile := Vector2i(floori(middle.x / TILE), floori(middle.z / TILE))
				covered[tile] = true
				low = Vector2i(mini(low.x, tile.x), mini(low.y, tile.y))
				high = Vector2i(maxi(high.x, tile.x), maxi(high.y, tile.y))
	var bare: Array = []
	for ty: int in range(low.y, high.y + 1):
		for tx: int in range(low.x, high.x + 1):
			if not covered.has(Vector2i(tx, ty)):
				bare.append(Vector2i(tx, ty))
	return bare


func _cracks(meshes: Array, least: int, mesher: RefCounted) -> Array:
	var surfaces: Array = _surfaces(meshes)
	var counts: Dictionary = _edge_counts(surfaces, _line_ends(surfaces))
	var lines: Dictionary = _boundary_lines(counts)
	var cracks: Array = []
	var ends: Dictionary = {}
	for line: String in lines:
		var crack: Dictionary = _crack_of(line, lines[line], least)
		if crack.is_empty() or not _sides_drawn(crack, mesher):
			continue
		cracks.append(crack)
		var bounds: PackedStringArray = line.split(",")
		ends["%s,%s" % [bounds[0], bounds[1]]] = true
		ends["%s,%s" % [bounds[2], bounds[3]]] = true
	for seam: Dictionary in _seams(counts, least):
		if not ends.has(seam["line"]) and _seam_drawn(seam["at"], mesher):
			cracks.append(seam)
	return cracks


## An upright edge bounding one face and no other. Two faces meeting at a
## building's corner run the whole column together, so whatever one of them
## alone still carries is open to the sky. The ground test cannot see it: its
## test is two rims over one line of ground, and a corner is neither.
func _seams(counts: Dictionary, least: int) -> Array:
	var columns: Dictionary = {}
	for key: String in counts:
		var edge: Array = counts[key]
		if int(edge[2]) != 1 or bool(edge[3]):
			continue
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		if absf(a.x - b.x) > 0.005 or absf(a.z - b.z) > 0.005:
			continue
		var column: String = "%.2f,%.2f" % [a.x, a.z]
		if not columns.has(column):
			columns[column] = []
		(columns[column] as Array).append(Vector2(minf(a.y, b.y), maxf(a.y, b.y)))
	var seams: Array = []
	for column: String in columns:
		for run: Vector2 in _joined(columns[column]):
			if run.y - run.x >= float(least):
				seams.append(_seam_of(column, run))
	return seams


## Segments that touch are one opening: the cut that parted them is a
## neighbouring face's end, not an edge of the gap.
func _joined(runs: Array) -> Array:
	runs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var joined: Array = []
	for run: Vector2 in runs:
		var last: Vector2 = joined[-1] if not joined.is_empty() else Vector2.ZERO
		if not joined.is_empty() and run.x <= last.y + 0.005:
			joined[-1] = Vector2(last.x, maxf(last.y, run.y))
			continue
		joined.append(run)
	return joined


func _seam_of(column: String, run: Vector2) -> Dictionary:
	var at: PackedStringArray = column.split(",")
	return {
		"tile": Vector2i(floori(float(at[0]) / TILE), floori(float(at[1]) / TILE)),
		"at": Vector2(float(at[0]), float(at[1])),
		"run": "upright",
		"low": run.x,
		"high": run.y,
		"drop": run.y - run.x,
		"line": column,
	}


## The four tiles a column stands between own the sides that would close it,
## and any one of them may be the face a room cut away for the camera. Unlike a
## line, which has one side each way, a column cannot say which face is missing,
## so a cut anywhere around it disowns the gap.
func _seam_drawn(at: Vector2, mesher: RefCounted) -> bool:
	for quadrant: Vector2 in [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)
	]:
		var centre: Vector2 = at + quadrant * TILE * 0.5
		if not mesher.draws_side(centre, Vector3(-quadrant.x, 0.0, 0.0)) \
			or not mesher.draws_side(centre, Vector3(0.0, 0.0, -quadrant.y)):
			return false
	return true


## The two tiles a line runs between each own the side facing the other. Where
## the mesher draws neither, the gap is the room's own cut-away.
func _sides_drawn(crack: Dictionary, mesher: RefCounted) -> bool:
	var bounds: PackedStringArray = (crack["line"] as String).split(",")
	var middle := Vector2(
		(float(bounds[0]) + float(bounds[2])) * 0.5,
		(float(bounds[1]) + float(bounds[3])) * 0.5
	)
	var step := Vector2(1.0, 0.0) if crack["run"] == "north-south" else Vector2(0.0, 1.0)
	var out := Vector3(step.x, 0.0, step.y)
	return mesher.draws_side(middle - step * TILE * 0.5, out) \
		or mesher.draws_side(middle + step * TILE * 0.5, -out)


## Every edge that bounds one flat face and no other, gathered by the line in
## the ground plan it lies along.
func _boundary_lines(counts: Dictionary) -> Dictionary:
	var lines: Dictionary = {}
	for key: String in counts:
		var edge: Array = counts[key]
		if int(edge[2]) != 1 or not bool(edge[3]):
			continue
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		if absf(a.x - b.x) > 0.01 and absf(a.z - b.z) > 0.01:
			continue
		if not _line_first(a, b):
			var swap: Vector3 = a
			a = b
			b = swap
		var line: String = "%.2f,%.2f,%.2f,%.2f" % [a.x, a.z, b.x, b.z]
		if not lines.has(line):
			lines[line] = []
		var ys: Array = lines[line]
		var pair := Vector2(a.y, b.y)
		if not ys.has(pair):
			ys.append(pair)
	return lines


func _line_first(a: Vector3, b: Vector3) -> bool:
	if absf(a.x - b.x) >= 0.01:
		return a.x < b.x
	return a.z <= b.z


## Two heights on one line and nothing between them: the drop is what a player
## would see through.
func _crack_of(line: String, ys: Array, least: int) -> Dictionary:
	if ys.size() < 2:
		return {}
	var low: float = 1e9
	var high: float = -1e9
	var drop: float = 0.0
	for pair: Vector2 in ys:
		low = minf(low, minf(pair.x, pair.y))
		high = maxf(high, maxf(pair.x, pair.y))
		for other: Vector2 in ys:
			drop = maxf(drop, maxf(absf(pair.x - other.x), absf(pair.y - other.y)))
	if drop < float(least):
		return {}
	var bounds: PackedStringArray = line.split(",")
	var x0: float = float(bounds[0])
	var z0: float = float(bounds[1])
	var x1: float = float(bounds[2])
	var z1: float = float(bounds[3])
	return {
		"tile": Vector2i(floori(minf(x0, x1) / TILE), floori(minf(z0, z1) / TILE)),
		"run": "north-south" if absf(x1 - x0) < 0.01 else "east-west",
		"low": low,
		"high": high,
		"drop": drop,
		"line": line,
	}


func _surfaces(meshes: Array) -> Array:
	var surfaces: Array = []
	for mesh: ArrayMesh in meshes:
		for surface: int in mesh.get_surface_count():
			surfaces.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return surfaces


func _flat_face(points: PackedVector3Array, at: int) -> bool:
	return absf((points[at + 1] - points[at]).cross(
		points[at + 2] - points[at]
	).normalized().y) > 0.5


## Where every edge on a straight line begins and ends, so an edge crossing a
## neighbour's end is cut there. A long edge meeting several short ones is a
## joint, not an opening, and pairing whole edges reads it as one.
func _line_ends(surfaces: Array) -> Dictionary:
	var ends: Dictionary = {}
	for points: PackedVector3Array in surfaces:
		for at: int in range(0, points.size() - 2, 3):
			for corner: int in 3:
				var a: Vector3 = points[at + corner]
				var b: Vector3 = points[at + (corner + 1) % 3]
				var key: String = _line_key(a, b)
				if key.is_empty():
					continue
				if not ends.has(key):
					ends[key] = {}
				var along: Dictionary = ends[key]
				var axis: String = key.left(1)
				along[_along(_snap(a), axis)] = true
				along[_along(_snap(b), axis)] = true
	return ends


func _edge_counts(surfaces: Array, ends: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for points: PackedVector3Array in surfaces:
		for at: int in range(0, points.size() - 2, 3):
			var flat: bool = _flat_face(points, at)
			for corner: int in 3:
				_count_cut(
					counts, ends,
					points[at + corner], points[at + (corner + 1) % 3], flat
				)
	return counts


## The line an edge lies on: the column it stands in where it runs up, the
## east-west or north-south line it lies along otherwise, sloped or level, or
## nothing where the edge runs across the ground plan.
func _line_key(a: Vector3, b: Vector3) -> String:
	var along_x: bool = absf(a.z - b.z) < 0.005
	if along_x == (absf(a.x - b.x) < 0.005):
		return _column_key(a, b)
	var low: Vector3 = a if (a.x < b.x if along_x else a.z < b.z) else b
	var high: Vector3 = b if low == a else a
	var from: float = low.x if along_x else low.z
	var slope: float = (high.y - low.y) / ((high.x - low.x) if along_x else (high.z - low.z))
	return "%s|%.2f|%.4f|%.3f" % [
		"x" if along_x else "z", a.z if along_x else a.x, slope, low.y - slope * from,
	]


## The column an edge stands in, or nothing where it runs across the ground
## plan or does not run at all.
func _column_key(a: Vector3, b: Vector3) -> String:
	if absf(a.x - b.x) > 0.005 or absf(a.y - b.y) < 0.005:
		return ""
	return "y|%.2f|%.2f" % [a.x, a.z]


func _count_cut(
	counts: Dictionary, ends: Dictionary, a: Vector3, b: Vector3, flat: bool
) -> void:
	var key: String = _line_key(a, b)
	if key.is_empty():
		_count(counts, a, b, flat)
		return
	var axis: String = key.left(1)
	var from: float = _along(_snap(a), axis)
	var to: float = _along(_snap(b), axis)
	var cuts := PackedFloat32Array()
	for at: float in ends[key] as Dictionary:
		if at > minf(from, to) + 0.005 and at < maxf(from, to) - 0.005:
			cuts.append(at)
	cuts.sort()
	if from > to:
		cuts.reverse()
	var last: Vector3 = a
	for at: float in cuts:
		var next: Vector3 = a.lerp(b, (at - from) / (to - from))
		_count(counts, last, next, flat)
		last = next
	_count(counts, last, b, flat)


func _count(counts: Dictionary, a: Vector3, b: Vector3, flat: bool) -> void:
	var one: Vector3 = _snap(a)
	var two: Vector3 = _snap(b)
	var key: String = "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f" % [
		one.x, one.y, one.z, two.x, two.y, two.z
	] if _before(one, two) else "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f" % [
		two.x, two.y, two.z, one.x, one.y, one.z
	]
	if counts.has(key):
		(counts[key] as Array)[2] += 1
		return
	counts[key] = [one, two, 1, flat]


func _along(point: Vector3, axis: String) -> float:
	if axis == "x":
		return point.x
	return point.y if axis == "y" else point.z


func _snap(point: Vector3) -> Vector3:
	return Vector3(
		roundf(point.x * GRID) / GRID,
		roundf(point.y * GRID) / GRID,
		roundf(point.z * GRID) / GRID
	)


func _before(a: Vector3, b: Vector3) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
