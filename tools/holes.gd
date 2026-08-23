extends SceneTree

## WHERE THE TERRAIN IS OPEN, found in the mesh itself rather than in a picture.
##
## A hole is the one fault a count never shows and a render only shows against a
## sky nobody would ship: two surfaces meet at different heights and nothing
## stands between them, so the map is see-through along a line. The pictures
## found three of them and each cost a round; this answers the whole game in one
## run.
##
## THE TEST IS THE MESH'S OWN EDGES. An edge shared by two triangles is closed by
## construction. An edge belonging to ONE triangle is a rim, which is legitimate
## everywhere a surface ends; but two rims lying over the SAME line of ground at
## DIFFERENT heights are two lips facing each other with air between them, and
## that is a crack whatever built it. Reported in MAP tile coordinates, the ones
## `map_grid.py` rules and `shot.gd` aims at.
##
##   Godot --headless --path <pokerecomp> -s tools/holes.gd -- <cache> \
##       [group,number|tileset <n>|all] [least pixels]
##
## [param least pixels] drops cracks shorter than it, default 1.
##
## A run over `all` names the first maps and counts the rest, which is readable
## and is NOT a distribution: taking the drop sizes off that printout counts the
## twelve worst of two dozen maps and calls it the game. The last line is the
## whole population, by drop and by tileset, so a round can pick the class that
## carries the most rather than the one that printed first.

const MOD := "user://mods/voxel3d"
const TILE: float = 8.0
## Positions are exact multiples of a pixel in this mesher, so rounding to a
## hundredth only guards the ramp corners' own averaging.
const GRID: float = 100.0
## How many maps to name in full before the run prints counts alone.
const NAMED: int = 24


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [group,number|ts<n>|all] [least pixels]")
		quit(1)
		return
	var data: GameData = GameData.open_directory(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var select: String = args[1] if args.size() > 1 else "all"
	var least: int = int(args[2]) if args.size() > 2 else 1
	# drop in pixels -> how many, and tileset -> how many, over every map
	# scanned rather than over the ones named.
	var by_drop: Dictionary = {}
	var by_tileset: Dictionary = {}

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var atlas_script: GDScript = load("%s/shape/atlas.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)

	var maps: int = 0
	var open_maps: int = 0
	var total: int = 0
	var named: int = 0
	for map: Gen2WorldMap in data.world_maps():
		if not _wanted(map, select):
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var atlas: RefCounted = atlas_script.new()
		# THE SEQUENCE, so the rims counted here are the rims the game draws.
		# See `atlas.gd:frame_count`.
		var animation := Gen2WorldAnimation.new()
		animation.configure_tileset(data, tileset, 1)
		if not atlas.build(data, map, tileset, 1, animation):
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset, data)
		var mesher: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		var meshes: Array = mesher.emit(atlas)
		maps += 1

		var bare: Array = _bare(meshes + mesher.take_water() + mesher.take_tufts())
		if not bare.is_empty() and named < NAMED:
			print("%s  ts%d  %d tiles with no floor at all" % [
				"%d,%d" % [map.group, map.number], map.tileset, bare.size()
			])
			for index: int in (bare.size() if select != "all" else mini(12, bare.size())):
				print("   tile %d,%d" % [bare[index].x, bare[index].y])
		var cracks: Array = _cracks(meshes + mesher.take_water(), least)
		total += cracks.size()
		if cracks.is_empty():
			continue
		open_maps += 1
		for crack: Dictionary in cracks:
			var drop: float = float(crack["drop"])
			by_drop[drop] = int(by_drop.get(drop, 0)) + 1
		by_tileset[map.tileset] = int(by_tileset.get(map.tileset, 0)) + cracks.size()
		if named >= NAMED:
			continue
		named += 1
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
	print("%d maps, %d with cracks, %d cracks" % [maps, open_maps, total])
	_ranked("by drop", by_drop, total, "%.1f px")
	_ranked("by tileset", by_tileset, total, "ts%d")
	quit(0)


## One population, commonest first, with the share each class carries: which
## class to take next is the only question this printout answers.
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


## THE OTHER WAY A MAP IS SEE-THROUGH: not a step with no wall but a tile with
## no surface, which is a hole the size of a tile and reads as a line of sky at a
## grazing angle. Answered over the box the mesh itself fills, so the skirt is
## included and the world outside it is not.
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
				# ANY tilt counts as a floor here, where a rim counts as one only
				# past 0.5: a rock rim cut in one tile stands at 63 degrees and is
				# still the thing covering that tile.
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


## Every pair of rims lying over one line of ground at two heights, as one entry
## each, keyed by the ground line so a crack is reported once however many
## triangles bound it.
func _cracks(meshes: Array, least: int) -> Array:
	var counts: Dictionary = {}
	for mesh: ArrayMesh in meshes:
		for surface: int in mesh.get_surface_count():
			var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for at: int in range(0, points.size() - 2, 3):
				# A VERTICAL FACE'S OWN TOP AND FOOT are two horizontal rims over
				# one line of ground at two heights, which is the shape of a crack
				# and is a closed wall. Only a rim belonging to a SURFACE counts.
				var flat: bool = absf((points[at + 1] - points[at]).cross(
					points[at + 2] - points[at]
				).normalized().y) > 0.5
				_count(counts, points[at], points[at + 1], flat)
				_count(counts, points[at + 1], points[at + 2], flat)
				_count(counts, points[at + 2], points[at], flat)
	# The rims alone, gathered by the line of ground each lies over.
	var lines: Dictionary = {}
	for key: String in counts:
		var edge: Array = counts[key]
		if int(edge[2]) != 1 or bool(edge[3]) == false:
			continue
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		# A rim crossing both axes at once is a quad's own diagonal or a cutout's
		# cut, neither of which bounds a step in the ground.
		if absf(a.x - b.x) > 0.01 and absf(a.z - b.z) > 0.01:
			continue
		# READ ALONG THE LINE AND NOT ALONG THE EDGE, so a rim and the rim facing
		# it are compared end for end. A SLOPING rim counts: the rock rim the
		# border block is drawn as is a slope, and the face missing under it is
		# the longest crack in the game.
		if a.x > b.x or (absf(a.x - b.x) < 0.01 and a.z > b.z):
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
	var cracks: Array = []
	for line: String in lines:
		var ys: Array = lines[line]
		if ys.size() < 2:
			continue
		var low: float = 1e9
		var high: float = -1e9
		var drop: float = 0.0
		for pair: Vector2 in ys:
			low = minf(low, minf(pair.x, pair.y))
			high = maxf(high, maxf(pair.x, pair.y))
			for other: Vector2 in ys:
				drop = maxf(drop, maxf(absf(pair.x - other.x), absf(pair.y - other.y)))
		if drop < float(least):
			continue
		var bounds: PackedStringArray = line.split(",")
		var x0: float = float(bounds[0])
		var z0: float = float(bounds[1])
		var x1: float = float(bounds[2])
		var z1: float = float(bounds[3])
		cracks.append({
			"tile": Vector2i(floori(minf(x0, x1) / TILE), floori(minf(z0, z1) / TILE)),
			"run": "north-south" if absf(x1 - x0) < 0.01 else "east-west",
			"low": low,
			"high": high,
			"drop": drop,
			"line": line,
		})
	return cracks


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
