extends RefCounted

## A voxel model turned from the drawing, one per distinct sprite, built once.

const VOXEL: float = 2.0
const ROCK_VOXEL: float = 1.0
const POT_STALK: float = 5.0
const LEAF_FLANK: float = 0.9

const LEAF_NOISE: float = 0.22
const ROCK_NOISE: float = 0.08
const ROOT_REACH: float = 1.6
const ROOT_RISE: float = 0.45

const CROWN_STRETCH: float = 1.3
const TRUNK_MIN: float = 0.5
const TRUNK_THICKNESS: float = 0.22
const TONE_SHARE: int = 8

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _sways := PackedVector2Array()
var _uvs := PackedVector2Array()
var _sway_foot: float = 0.0
var _sway_span: float = 1.0
var _sway_still: bool = false
var _band := Color(0.5, 0.5, 0.5)
var _wrap := PackedColorArray()
var _voxel: float = VOXEL


class Measure extends RefCounted:
	var profile := PackedFloat32Array()
	var trunk_width: int = 6
	var trunk_height: int = 10
	var shrub: bool = false
	var potted: bool = false
	var pot := PackedFloat32Array()
	var pot_bands: PackedColorArray = PackedColorArray()
	var rock: bool = false
	var column: bool = false
	var stretch: float = 0.0
	var tones: PackedColorArray = PackedColorArray()
	var shades: PackedColorArray = PackedColorArray()
	var bark: PackedColorArray = PackedColorArray()
	var bands: PackedColorArray = PackedColorArray()
	var cap := Color(0.5, 0.5, 0.5)
	var cap_rows: int = 0
	var side_bands: PackedColorArray = PackedColorArray()
	var wraps: Array = []

	func width() -> int:
		var widest: float = 0.0
		for radius: float in profile:
			widest = maxf(widest, radius)
		return int(widest * 2.0)

	func height() -> int:
		return profile.size() + trunk_height


## Solid pixels per row, and the first and last row that has any.
class Rows:
	var width := PackedInt32Array()
	var first: int = -1
	var last: int = -1
	var widest: int = 0


static func _rows(mask: PackedByteArray, span: Vector2i) -> Rows:
	var out := Rows.new()
	out.width.resize(span.y)
	for py: int in span.y:
		var first: int = -1
		var last: int = -1
		for px: int in span.x:
			if mask[py * span.x + px] == 1:
				if first < 0:
					first = px
				last = px
		out.width[py] = 0 if first < 0 else last + 1 - first
		out.widest = maxi(out.widest, out.width[py])
		if out.width[py] > 0:
			if out.first < 0:
				out.first = py
			out.last = py
	return out


## Where the crown stops and the trunk starts, by the row that first narrows to
## half the widest row and the run of narrow rows under it.
static func _crown_bottom(rows: Rows) -> int:
	var narrow: int = maxi(rows.widest / 2, 1)
	var at: int = rows.first
	for py: int in range(rows.first, rows.last + 1):
		if rows.width[py] == rows.widest:
			at = py
			break
	while at <= rows.last and rows.width[at] > narrow:
		at += 1
	return at


static func _trunk_bottom(rows: Rows, crown_bottom: int) -> int:
	var narrow: int = maxi(rows.widest / 2, 1)
	var at: int = crown_bottom
	while at <= rows.last and rows.width[at] > 0 and rows.width[at] <= narrow:
		at += 1
	return at


## Where a pot starts: the run under the crown no wider than its thinnest row.
static func _pot_top(rows: Rows, crown_bottom: int) -> int:
	var thin: int = 0
	for py: int in range(crown_bottom, rows.last + 1):
		if rows.width[py] > 0 and (thin == 0 or rows.width[py] < thin):
			thin = rows.width[py]
	var at: int = crown_bottom
	while at <= rows.last and rows.width[at] <= thin:
		at += 1
	return at


## The bark colours, which are the trunk's own colours less the leaf ones and
## less anything lighter than the lightest leaf.
static func _wood(bark: PackedColorArray, tones: PackedColorArray) -> PackedColorArray:
	var lightest: float = 0.0
	for leaf: Color in tones:
		lightest = maxf(lightest, leaf.get_luminance())
	var out := PackedColorArray()
	for colour: Color in bark:
		if colour.get_luminance() > lightest:
			continue
		var claimed: bool = false
		for leaf: Color in tones:
			claimed = claimed or leaf.is_equal_approx(colour)
		if not claimed:
			out.append(colour)
	return out


## What a shape with nothing measurable in it falls back to.
static func _greenery(out: Measure) -> Measure:
	if out.tones.is_empty():
		out.tones = PackedColorArray([
			Color(0.35, 0.62, 0.28), Color(0.2, 0.42, 0.18)
		])
	if out.shades.is_empty():
		out.shades = out.tones
	if out.bark.is_empty():
		out.bark = PackedColorArray([Color(0.42, 0.28, 0.14)])
	return out


static func measure(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, measured_pot: bool = false
) -> Measure:
	var out := Measure.new()
	out.potted = measured_pot
	var rows: Rows = _rows(mask, span)
	if rows.first < 0:
		out.profile = PackedFloat32Array([6.0, 8.0, 8.0, 6.0])
		return _greenery(out)

	var crown_bottom: int = _crown_bottom(rows)
	var trunk_bottom: int = _trunk_bottom(rows, crown_bottom)
	var trunk: int = 0
	for py: int in range(crown_bottom, trunk_bottom):
		trunk = maxi(trunk, rows.width[py])
	for py: int in range(rows.first, crown_bottom):
		out.profile.append(float(rows.width[py]) * 0.5)
	if out.profile.is_empty():
		out.profile.append(float(rows.widest) * 0.5)
	out.trunk_height = maxi(trunk_bottom - crown_bottom, 2)
	out.trunk_width = maxi(trunk, 3)

	var pot_top: int = crown_bottom
	if measured_pot:
		pot_top = _pot_top(rows, crown_bottom)
		out.trunk_height = maxi(pot_top - crown_bottom, 1)
		_measure_pot(out, rows, pot_top, mask, span, tiles, across, atlas)
	_measure_crown(out, rows, crown_bottom, mask, span, tiles, across, atlas)
	var bark_bottom: int = (pot_top - 1) if pot_top > crown_bottom else rows.last
	out.bark = _tones(
		mask, span, tiles, across, atlas, crown_bottom, bark_bottom
	)
	_measure_bark(out)
	return _greenery(out)


static func _measure_pot(
	out: Measure, rows: Rows, pot_top: int, mask: PackedByteArray,
	span: Vector2i, tiles: Array, across: Vector2i, atlas: RefCounted
) -> void:
	for py: int in range(pot_top, rows.last + 1):
		out.pot.append(float(rows.width[py]) * 0.5)
	if pot_top <= rows.last:
		out.pot_bands = _bands(mask, span, tiles, across, atlas, pot_top, rows.last)


static func _measure_crown(
	out: Measure, rows: Rows, crown_bottom: int, mask: PackedByteArray,
	span: Vector2i, tiles: Array, across: Vector2i, atlas: RefCounted
) -> void:
	var top: int = rows.first
	var end: int = crown_bottom - 1
	out.tones = _tones(mask, span, tiles, across, atlas, top, end)
	out.shades = _tones(mask, span, tiles, across, atlas, top, end, false)
	out.bands = _bands(mask, span, tiles, across, atlas, top, end)
	out.cap = _cap(out.bands)
	out.cap_rows = _cap_rows(out.bands, out.cap)
	for at: int in range(out.cap_rows, out.bands.size()):
		out.side_bands.append(out.bands[at])
	if out.side_bands.is_empty():
		out.side_bands = out.bands
	out.wraps = _wraps(
		mask, span, tiles, across, atlas, top + out.cap_rows, end
	)


## The trunk keeps its own colours where it has any of its own, and borrows the
## darkest leaf shade where every colour on it is also a leaf's.
static func _measure_bark(out: Measure) -> void:
	var wood: PackedColorArray = _wood(out.bark, out.tones)
	if wood.is_empty() and not out.bark.is_empty() and not out.shades.is_empty():
		wood.append(out.shades[out.shades.size() - 1])
	if not wood.is_empty():
		out.bark = wood

static func _tones(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, from_row: int, to_row: int, drop_dark: bool = true
) -> PackedColorArray:
	var counts: Dictionary = {}
	var colours: Dictionary = {}
	var total: int = 0
	for py: int in range(maxi(from_row, 0), mini(to_row + 1, span.y)):
		for px: int in span.x:
			if mask[py * span.x + px] == 0:
				continue
			@warning_ignore("integer_division")
			var tile: int = tiles[(py / 8) * across.x + px / 8]
			var index: int = atlas.pixel(tile, px % 8, py % 8)
			if index < 0 or (drop_dark and atlas.is_dark(tile, index, 1)):
				continue
			var colour: Color = atlas.color_of(tile, index)
			var key: int = colour.to_rgba32()
			counts[key] = int(counts.get(key, 0)) + 1
			colours[key] = colour
			total += 1
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	var kept: Array = []
	for key: int in ranked:
		if int(counts[key]) * 100 < total * TONE_SHARE:
			break
		kept.append(colours[key])
	if kept.is_empty() and not ranked.is_empty():
		kept.append(colours[ranked[0]])
	kept.sort_custom(func(a: Color, b: Color) -> bool:
		return _luminance(a) > _luminance(b))
	var out := PackedColorArray()
	for colour: Color in kept:
		out.append(colour)
	return out


static func _bands(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, from_row: int, to_row: int
) -> PackedColorArray:
	var out := PackedColorArray()
	var last := Color(0.5, 0.5, 0.5)
	var seen: bool = false
	for py: int in range(maxi(from_row, 0), mini(to_row + 1, span.y)):
		var counts: Dictionary = {}
		var colours: Dictionary = {}
		for px: int in span.x:
			if mask[py * span.x + px] == 0:
				continue
			@warning_ignore("integer_division")
			var tile: int = tiles[(py / 8) * across.x + px / 8]
			var index: int = atlas.pixel(tile, px % 8, py % 8)
			if index < 0 or atlas.is_dark(tile, index, 1):
				continue
			var colour: Color = atlas.color_of(tile, index)
			var key: int = colour.to_rgba32()
			counts[key] = int(counts.get(key, 0)) + 1
			colours[key] = colour
		var best: int = -1
		for key: int in counts:
			if best < 0 or int(counts[key]) > int(counts[best]):
				best = key
		if best >= 0:
			last = colours[best]
			seen = true
		out.append(last)
	if seen:
		for at: int in out.size():
			if out[at].is_equal_approx(Color(0.5, 0.5, 0.5)):
				continue
			for above: int in at:
				out[above] = out[at]
			break
	return out


static func _cap(bands: PackedColorArray) -> Color:
	if bands.is_empty():
		return Color(0.5, 0.5, 0.5)
	var counts: Dictionary = {}
	var colours: Dictionary = {}
	for at: int in maxi(bands.size() / 2, 1):
		var key: int = bands[at].to_rgba32()
		counts[key] = int(counts.get(key, 0)) + 1
		colours[key] = bands[at]
	var best: int = -1
	for key: int in counts:
		if best < 0 or int(counts[key]) > int(counts[best]):
			best = key
	return colours[best]


static func _cap_rows(bands: PackedColorArray, cap: Color) -> int:
	var deepest: int = -1
	for at: int in maxi(bands.size() / 2, 1):
		if bands[at].is_equal_approx(cap):
			deepest = at
	return deepest + 1


static func _wraps(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, from_row: int, to_row: int
) -> Array:
	var out: Array = []
	for py: int in range(maxi(from_row, 0), mini(to_row + 1, span.y)):
		var row := PackedColorArray()
		var first: int = -1
		var last: int = -1
		for px: int in span.x:
			if mask[py * span.x + px] == 1:
				if first < 0:
					first = px
				last = px
		if first >= 0:
			for px: int in range(first, last + 1):
				@warning_ignore("integer_division")
				var tile: int = tiles[(py / 8) * across.x + px / 8]
				var index: int = atlas.pixel(tile, px % 8, py % 8)
				if index < 0 or atlas.is_dark(tile, index, 1):
					row.append(Color(0.0, 0.0, 0.0, 0.0))
				else:
					row.append(atlas.color_of(tile, index))
			var carried := Color(0.5, 0.5, 0.5)
			for at: int in row.size():
				if row[at].a > 0.0:
					carried = row[at]
				else:
					row[at] = carried
			for step: int in row.size():
				var at: int = row.size() - 1 - step
				if row[at].a > 0.0:
					carried = row[at]
				else:
					row[at] = carried
		out.append(row)
	return out


static func _luminance(colour: Color) -> float:
	return colour.r * 0.299 + colour.g * 0.587 + colour.b * 0.114

const EMPTY: int = 0
const BARK: int = 1
const LEAF: int = 2
const POT: int = 3


func tree(measured: Measure) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_sways = PackedVector2Array()

	_voxel = ROCK_VOXEL if measured.rock or measured.potted else VOXEL
	var rows: int = measured.profile.size()
	var stretch: float = measured.stretch
	if stretch <= 0.0:
		stretch = 1.0 if measured.shrub else CROWN_STRETCH
	var crown_high: int = maxi(ceili(float(rows) * stretch / _voxel), 2)
	var trunk_high: int = 0 if measured.shrub else maxi(ceili(
		maxf(float(measured.trunk_height), POT_STALK) / _voxel
		if not measured.pot.is_empty()
		else maxf(float(measured.trunk_height), float(measured.width()) * TRUNK_MIN)
			/ _voxel
	), 2)
	var trunk_half: float = maxf(
		float(measured.width()) * TRUNK_THICKNESS * 0.5 / _voxel, 1.0
	)
	var widest: float = 0.0
	for radius: float in measured.profile:
		widest = maxf(widest, radius / _voxel)
	var pot_high: int = 0
	var pot_wide: float = 0.0
	if not measured.pot.is_empty():
		pot_high = maxi(ceili(float(measured.pot.size()) / _voxel), 1)
		for radius: float in measured.pot:
			pot_wide = maxf(pot_wide, radius / _voxel)
	var reach: int = ceili(
		maxf(widest, pot_wide) + (0.0 if measured.shrub or pot_high > 0 else ROOT_REACH)
	) + 1
	var wide: int = reach * 2 + 1
	var tall: int = pot_high + trunk_high + crown_high + 1
	_sway_still = measured.rock
	_sway_foot = float(pot_high + trunk_high) * _voxel
	_sway_span = float(maxi(crown_high - 1, 1)) * _voxel

	var solid := PackedByteArray()
	solid.resize(wide * wide * tall)
	for vy: int in tall:
		for vz: int in wide:
			for vx: int in wide:
				var x: float = float(vx - reach)
				var z: float = float(vz - reach)
				var plan: float = sqrt(x * x + z * z)
				var fill: int = EMPTY
				if vy < pot_high:
					var at_row: int = mini(
						int(float(pot_high - 1 - vy) * _voxel), measured.pot.size() - 1
					)
					var wall: float = measured.pot[at_row] / _voxel
					if vy == pot_high - 1:
						wall += 1.0
					if plan <= wall:
						fill = POT
				elif vy < pot_high + trunk_high:
					var root: float = 0.0 if pot_high > 0 else maxf(
						1.0 - float(vy - pot_high) / (float(trunk_high) * ROOT_RISE), 0.0
					) * ROOT_REACH
					var along: float = maxf(absf(x), absf(z))
					var across_root: float = minf(absf(x), absf(z))
					if plan <= trunk_half \
							or (across_root <= trunk_half * 0.55 \
								and along <= trunk_half + root):
						fill = BARK
				if fill == EMPTY:
					var radius: float = _radius(
						measured, vy - pot_high - trunk_high, crown_high
					)
					if radius > 0.0:
						var ragged: float = 0.0 if measured.column \
							else (ROCK_NOISE if measured.rock else LEAF_NOISE)
						if plan <= radius * _wobble(x, z, plan, vy, ragged):
							fill = LEAF
				solid[(vy * wide + vz) * wide + vx] = fill

	for vy: int in tall:
		_band = _band_at(measured, vy - pot_high - trunk_high, crown_high)
		_wrap = _wrap_at(measured, vy - pot_high - trunk_high, crown_high)
		if vy < pot_high and not measured.pot_bands.is_empty():
			_band = measured.pot_bands[clampi(
				measured.pot_bands.size() - 1 - int(float(vy) * _voxel),
				0, measured.pot_bands.size() - 1
			)]
		for vz: int in wide:
			for vx: int in wide:
				if solid[(vy * wide + vz) * wide + vx] == EMPTY:
					continue
				_faces(solid, wide, tall, vx, vy, vz, reach, measured)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _sways
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

const RAY_STEPS: float = 8.0


func _wobble(x: float, z: float, plan: float, vy: int, ragged: float) -> float:
	if ragged <= 0.0:
		return 1.0
	var ray: float = maxf(plan, 1.0)
	return 1.0 - _hash(
		int(roundf(x / ray * RAY_STEPS)), vy, int(roundf(z / ray * RAY_STEPS))
	) * ragged


func _radius(measured: Measure, up: int, crown_high: int) -> float:
	if up < 0 or up >= crown_high:
		return 0.0
	if measured.column:
		var straight: float = float(measured.width()) * 0.5 / _voxel
		if up == 0 or up == crown_high - 1:
			return maxf(straight - 1.0, 1.0)
		return straight
	var rows: int = measured.profile.size()
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1) / float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return measured.profile[at] / _voxel


func _wrap_at(measured: Measure, up: int, crown_high: int) -> PackedColorArray:
	if measured.wraps.is_empty():
		return PackedColorArray()
	var rows: int = measured.wraps.size()
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1)
			/ float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return measured.wraps[at]


func _band_at(measured: Measure, up: int, crown_high: int) -> Color:
	var bands: PackedColorArray = measured.bands
	if measured.column and not measured.side_bands.is_empty():
		bands = measured.side_bands
	if bands.is_empty():
		return Color(0.5, 0.5, 0.5)
	var rows: int = bands.size()
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1)
			/ float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return bands[at]


func _hash(x: int, y: int, z: int) -> float:
	var value: float = sin(float(x) * 12.9898 + float(y) * 78.233 + float(z) * 37.719) \
		* 43758.5453
	return value - floorf(value)

const SIDES: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]


func _faces(
	solid: PackedByteArray, wide: int, tall: int,
	vx: int, vy: int, vz: int, reach: int, measured: Measure
) -> void:
	var fill: int = solid[(vy * wide + vz) * wide + vx]
	var sky: int = 0
	var near: int = 0
	var counted: bool = false
	for side: Vector3i in SIDES:
		var nx: int = vx + side.x
		var ny: int = vy + side.y
		var nz: int = vz + side.z
		if nx >= 0 and nx < wide and nz >= 0 and nz < wide and ny >= 0 and ny < tall:
			if solid[(ny * wide + nz) * wide + nx] != EMPTY:
				continue
		if side.y < 0 and vy == 0:
			continue
		if not counted:
			counted = true
			for above: int in range(vy + 1, tall):
				if solid[(above * wide + vz) * wide + vx] != EMPTY:
					sky += 1
			near = -1
			for dy: int in range(maxi(vy - 1, 0), mini(vy + 2, tall)):
				for dz: int in range(maxi(vz - 1, 0), mini(vz + 2, wide)):
					for dx: int in range(maxi(vx - 1, 0), mini(vx + 2, wide)):
						if solid[(dy * wide + dz) * wide + dx] != EMPTY:
							near += 1
		var origin := Vector3(
			float(vx - reach) * _voxel, float(vy) * _voxel, float(vz - reach) * _voxel
		)
		_quad(origin, side, _tone(measured, fill, side, sky, near, float(vx - reach)))


func _tone(
	measured: Measure, fill: int, side: Vector3i, sky: int, near: int,
	across: float
) -> Color:
	if fill == POT:
		if side.y >= 0:
			return _band
		return _band.darkened(0.25)
	var palette: PackedColorArray = measured.bark if fill == BARK else measured.tones
	if fill == LEAF and not measured.rock and not measured.shades.is_empty():
		palette = measured.shades
	if palette.is_empty():
		return Color(0.3, 0.5, 0.25)
	if measured.rock:
		if measured.column and side.y > 0:
			return measured.cap
		if measured.column and side.y == 0 and not _wrap.is_empty():
			var at: int = int(round(float(_wrap.size()) * 0.5 + across * _voxel))
			return _wrap[clampi(at, 0, _wrap.size() - 1)]
		if side.y >= 0:
			return _band
		return palette[clampi(_ladder(palette, _band) + 1, 0, palette.size() - 1)]
	if fill == LEAF and not measured.pot.is_empty():
		return _lit(
			palette, side, sky, near, false,
			-LEAF_FLANK if side.x < 0 or side.z < 0 else LEAF_FLANK
		)
	var dark_mass: bool = measured.shrub and not measured.rock
	return _lit(palette, side, sky, near, dark_mass)


func _lit(
	palette: PackedColorArray, side: Vector3i, sky: int, near: int, dark_mass: bool,
	flank: float = 0.0
) -> Color:
	var rung: float = (1.0 if dark_mass else 0.0) + flank
	if side.y > 0:
		rung -= 0.5
	elif side.y < 0:
		rung += 0.6
	rung += float(sky) * 0.5
	rung += float(near) / 26.0 * 1.6
	var top: int = palette.size() - 1
	var at: float = clampf(rung, 0.0, float(top))
	var low: int = int(floorf(at))
	return palette[low].lerp(palette[mini(low + 1, top)], at - float(low))


func _ladder(palette: PackedColorArray, colour: Color) -> int:
	for at: int in palette.size():
		if palette[at].is_equal_approx(colour):
			return at
	return 0


func _sway_at(height: float) -> float:
	if _sway_still:
		return 0.0
	return clampf((height - _sway_foot) / _sway_span, 0.0, 1.0)


func _quad(origin: Vector3, side: Vector3i, color: Color) -> void:
	var normal := Vector3(float(side.x), float(side.y), float(side.z))
	var along := Vector3(0.0, 0.0, 1.0) if absf(normal.y) > 0.5 else Vector3(0.0, 1.0, 0.0)
	var right: Vector3 = along.cross(normal).normalized() * _voxel
	var up: Vector3 = normal.cross(right.normalized()).normalized() * _voxel
	var centre: Vector3 = origin + Vector3(_voxel, _voxel, _voxel) * 0.5 \
		+ normal * (_voxel * 0.5)
	var a: Vector3 = centre - right * 0.5 - up * 0.5
	var b: Vector3 = centre + right * 0.5 - up * 0.5
	var c: Vector3 = centre + right * 0.5 + up * 0.5
	var d: Vector3 = centre - right * 0.5 + up * 0.5
	for vertex: Vector3 in [a, c, b, a, d, c]:
		_vertices.push_back(vertex)
		_normals.push_back(normal)
		_colors.push_back(color)
		_sways.push_back(Vector2(_sway_at(vertex.y), 0.0))


func impostor(measured: Measure) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_sways = PackedVector2Array()
	_voxel = ROCK_VOXEL if measured.rock or measured.potted else VOXEL
	var rows: int = measured.profile.size()
	var stretch: float = measured.stretch
	if stretch <= 0.0:
		stretch = 1.0 if measured.shrub else CROWN_STRETCH
	var crown_high: int = maxi(ceili(float(rows) * stretch / _voxel), 2)
	var trunk_high: int = 0 if measured.shrub else maxi(ceili(
		maxf(float(measured.trunk_height), POT_STALK) / _voxel
		if not measured.pot.is_empty()
		else maxf(float(measured.trunk_height), float(measured.width()) * TRUNK_MIN)
			/ _voxel
	), 2)
	var trunk_half: float = maxf(
		float(measured.width()) * TRUNK_THICKNESS * 0.5 / _voxel, 1.0
	)
	var pot_high: int = 0
	if not measured.pot.is_empty():
		pot_high = maxi(ceili(float(measured.pot.size()) / _voxel), 1)
	var tall: int = pot_high + trunk_high + crown_high + 1
	_sway_still = measured.rock
	_sway_foot = float(pot_high + trunk_high) * _voxel
	_sway_span = float(maxi(crown_high - 1, 1)) * _voxel

	var widths := PackedFloat32Array()
	var tones: PackedColorArray = PackedColorArray()
	for vy: int in tall:
		var half: float = 0.0
		var tone: Color = Color(0.5, 0.5, 0.5)
		if vy < pot_high:
			var at_row: int = mini(
				int(float(pot_high - 1 - vy) * _voxel), measured.pot.size() - 1
			)
			half = measured.pot[at_row] / _voxel
			if vy == pot_high - 1:
				half += 1.0
			if not measured.pot_bands.is_empty():
				tone = measured.pot_bands[clampi(
					measured.pot_bands.size() - 1 - int(float(vy) * _voxel),
					0, measured.pot_bands.size() - 1
				)]
		elif vy < pot_high + trunk_high:
			half = trunk_half
			tone = measured.bark[measured.bark.size() / 2] if not measured.bark.is_empty() \
				else Color(0.35, 0.25, 0.18)
		else:
			half = _radius(measured, vy - pot_high - trunk_high, crown_high)
			tone = _band_at(measured, vy - pot_high - trunk_high, crown_high)
		widths.push_back(half)
		tones.push_back(tone)

	var run: int = 0
	while run < tall:
		if widths[run] <= 0.0:
			run += 1
			continue
		var last: int = run
		while last + 1 < tall and is_equal_approx(widths[last + 1], widths[run]) \
				and tones[last + 1] == tones[run]:
			last += 1
		var half: float = widths[run] * _voxel
		var foot: float = float(run) * _voxel
		var head: float = float(last + 1) * _voxel
		_band_quad(Vector3(0.0, 0.0, 1.0), half, foot, head, tones[run])
		_band_quad(Vector3(1.0, 0.0, 0.0), half, foot, head, tones[run])
		run = last + 1

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _sways
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func sprite(measured: Measure) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_sways = PackedVector2Array()
	_uvs = PackedVector2Array()
	_voxel = ROCK_VOXEL if measured.rock or measured.potted else VOXEL
	var frame: Vector3 = _stand(measured)
	_sway_still = measured.rock
	_sway_foot = frame.x
	_sway_span = frame.y
	var half: float = maxf(float(measured.width()) * 0.5, _voxel)
	_sprite_quad(Vector3(0.0, 0.0, 1.0), half, frame.z)
	_sprite_quad(Vector3(1.0, 0.0, 0.0), half, frame.z)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _sways
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sprite_quad(normal: Vector3, half: float, high: float) -> void:
	var across: Vector3 = Vector3(normal.z, 0.0, normal.x) * half
	var corners: Array[Vector3] = [
		-across, across, across + Vector3(0.0, high, 0.0),
		-across + Vector3(0.0, high, 0.0),
	]
	var map: Array[Vector2] = [
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
	]
	for corner: int in [0, 2, 1, 0, 3, 2]:
		_vertices.push_back(corners[corner])
		_normals.push_back(normal)
		_colors.push_back(Color.WHITE)
		_uvs.push_back(map[corner])
		_sways.push_back(Vector2(_sway_at(corners[corner].y), 0.0))


func _stand(measured: Measure) -> Vector3:
	var rows: int = measured.profile.size()
	var stretch: float = measured.stretch
	if stretch <= 0.0:
		stretch = 1.0 if measured.shrub else CROWN_STRETCH
	var crown_high: int = maxi(ceili(float(rows) * stretch / _voxel), 2)
	var trunk_high: int = 0 if measured.shrub else maxi(ceili(
		maxf(float(measured.trunk_height), POT_STALK) / _voxel
		if not measured.pot.is_empty()
		else maxf(float(measured.trunk_height), float(measured.width()) * TRUNK_MIN)
			/ _voxel
	), 2)
	var pot_high: int = 0
	if not measured.pot.is_empty():
		pot_high = maxi(ceili(float(measured.pot.size()) / _voxel), 1)
	return Vector3(
		float(pot_high + trunk_high) * _voxel,
		float(maxi(crown_high - 1, 1)) * _voxel,
		float(pot_high + trunk_high + crown_high + 1) * _voxel
	)


func _band_quad(
	normal: Vector3, half: float, foot: float, head: float, tone: Color
) -> void:
	var across: Vector3 = Vector3(normal.z, 0.0, normal.x) * half
	var a: Vector3 = -across + Vector3(0.0, foot, 0.0)
	var b: Vector3 = across + Vector3(0.0, foot, 0.0)
	var c: Vector3 = across + Vector3(0.0, head, 0.0)
	var d: Vector3 = -across + Vector3(0.0, head, 0.0)
	for side: float in [1.0, -1.0]:
		var facing: Vector3 = normal * side
		for vertex: Vector3 in ([a, c, b, a, d, c] if side > 0.0 else [a, b, c, a, c, d]):
			_vertices.push_back(vertex)
			_normals.push_back(facing)
			_colors.push_back(tone)
			_sways.push_back(Vector2(_sway_at(vertex.y), 0.0))
