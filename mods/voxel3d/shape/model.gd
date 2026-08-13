extends RefCounted

## An AUTHORED voxel model, MEASURED and COLOURED from the cartridge's drawing.
##
## Most of this mod stands a drawing up, because most of Generation II's art is a
## picture of a face: a wall, a facade, a canopy seen head on. A TREE is not. Its
## sprite is a portrait of a tree rather than a plan of one, and carving the
## silhouette proves it: six ways of doing that were built and measured and every
## one came out a drum or a stack of plates, because the drawn leaves fill their
## square edge to edge and a revolve can only read that as a cylinder.
##
## A tree is also the easiest thing in the world to model. It is a trunk and a
## crown and it is symmetric. So the geometry is authored here and only what the
## cartridge can answer is read from it: how wide the crown is, how tall, how
## thick the trunk, and which colours to paint them.
##
## NOTHING HERE IS CARTRIDGE CONTENT. The shape is arithmetic; the colours come
## from the player's own cartridge at run time, the same way every texel in this
## mod does.
##
## The dark outline is deliberately NOT used. It is a drawing's way of separating
## itself from a flat background, and a solid standing in a real light does not
## need one: reusing it paints the tree its own outline colour, which is what
## made every carved attempt read as a black hedge.

const VOXEL: float = 2.0

## How much of the tree's height is trunk, how far the crown sits DOWN over it,
## and how thick the trunk is as a share of the crown's width. Authored numbers
## and the only ones in this file: a tree is a shape everybody knows, and these
## are what make a voxel one read as a tree rather than as a ball on a stick.
const TRUNK_SHARE: float = 0.5
const CROWN_SIT: float = 0.72
const TRUNK_THICKNESS: float = 0.13
## The crown is a little narrower than the drawing, so a row of trees shows the
## grass between them instead of closing into a hedge.
const CROWN_SPREAD: float = 0.46

## The crown shapes worth choosing between. All three are round in plan, which a
## tree is; what differs is the profile.
enum { BALL, BROAD, TIERED }

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## What is taken from the cartridge: how big the thing is and what colour it is.
##
## The PROPORTIONS are not taken, and that is the point. Measuring the drawn
## crown and the drawn trunk gives a cabbage on a stub, because a Game Boy sprite
## of a tree is a portrait at a fixed angle: its crown is drawn flat and wide to
## read against the grass, and its trunk is mostly hidden behind the crown. What
## survives the change of medium is the tree's SIZE and its COLOURS. The rest is
## what everybody already knows a tree looks like, and is authored below.
class Measure extends RefCounted:
	var width: int = 16
	var height: int = 16
	var crown: PackedColorArray = PackedColorArray()
	var bark: Color = Color(0.4, 0.26, 0.13)


## Reads the measurements off a cut mask and the colours off the art.
##
## The mask is the drawing's own silhouette, so its widest row is the crown and
## its narrowest row above the ground is the trunk. Both are facts the drawing
## states plainly; how DEEP the tree is, it does not state at all, and a tree
## being round is what answers that.
static func measure(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted
) -> Measure:
	var out := Measure.new()
	var widths := PackedInt32Array()
	widths.resize(span.y)
	var first_row: int = -1
	var last_row: int = -1
	var widest: int = 0
	for py: int in span.y:
		var first: int = -1
		var last: int = -1
		for px: int in span.x:
			if mask[py * span.x + px] == 1:
				if first < 0:
					first = px
				last = px
		widths[py] = 0 if first < 0 else last + 1 - first
		widest = maxi(widest, widths[py])
		if widths[py] > 0:
			if first_row < 0:
				first_row = py
			last_row = py
	if first_row < 0:
		return out
	out.width = maxi(widest, 6)
	out.height = maxi(last_row + 1 - first_row, 8)

	# The shadow pooled at the foot is as wide as the crown and is not the tree,
	# so the colours are read from the rows ABOVE it: the top two thirds are
	# leaves and the band under them is bark. Only the split matters, because
	# what comes back is a ranking and the tree is drawn in very few colours.
	var foliage: int = first_row + (out.height * 2) / 3
	out.crown = _tones(mask, span, tiles, across, atlas, first_row, foliage)
	var bark: PackedColorArray = _tones(
		mask, span, tiles, across, atlas, foliage + 1, last_row
	)
	if bark.size() > 0:
		out.bark = bark[0]
	if out.crown.is_empty():
		out.crown = PackedColorArray([Color(0.24, 0.5, 0.2)])
	return out


## The colours a band of the drawing is painted in, commonest first, with the
## tile's darkest shade left out because that is the outline and not a material.
static func _tones(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, from_row: int, to_row: int
) -> PackedColorArray:
	var counts: Dictionary = {}
	var colours: Dictionary = {}
	for py: int in range(maxi(from_row, 0), mini(to_row + 1, span.y)):
		for px: int in span.x:
			if mask[py * span.x + px] == 0:
				continue
			@warning_ignore("integer_division")
			var tile: int = tiles[(py / 8) * across.x + px / 8]
			var index: int = atlas.pixel(tile, px % 8, py % 8)
			if index < 0 or atlas.is_dark(tile, index, 1):
				continue
			var key: String = "%d:%d" % [tile, index]
			counts[key] = int(counts.get(key, 0)) + 1
			colours[key] = atlas.color_of(tile, index)
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var out := PackedColorArray()
	for key: String in ranked:
		out.append(colours[key])
		if out.size() >= 2:
			break
	return out


## Builds the tree, centred on x and z, standing on y = 0.
##
## Voxels rather than a smooth solid, because the whole diorama is voxels and a
## sphere in the middle of it would be the one thing that is not. Only the faces
## with nothing beside them are emitted, which is most of the saving.
func tree(measured: Measure, style: int) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()

	# The authored proportions. A trunk carries the crown clear of the ground and
	# the crown sits DOWN over the top of it, which is what stops a voxel tree
	# reading as a lollipop; the crown is as deep as it is wide because a tree is
	# round in plan and the drawing could never have said so.
	var radius: float = float(measured.width) * CROWN_SPREAD / VOXEL
	var trunk_high: float = float(measured.height) * TRUNK_SHARE / VOXEL
	var height: float = float(measured.height) / VOXEL - trunk_high * CROWN_SIT
	var trunk_half: float = maxf(float(measured.width) * TRUNK_THICKNESS / VOXEL, 1.0)
	var reach: int = ceili(radius) + 1
	var top: int = ceili(trunk_high * CROWN_SIT + height) + 1

	# The voxel grid, one byte a cell: 0 empty, 1 bark, 2 and 3 the crown's two
	# tones. Built whole first, because a face is only emitted where its
	# NEIGHBOUR is empty and that cannot be known one voxel at a time.
	var wide: int = reach * 2 + 1
	var solid := PackedByteArray()
	solid.resize(wide * wide * (top + 1))
	for vy: int in top + 1:
		for vz: int in wide:
			for vx: int in wide:
				var x: float = float(vx - reach)
				var z: float = float(vz - reach)
				var fill: int = 0
				var crown_foot: float = trunk_high * CROWN_SIT
				if float(vy) < trunk_high and absf(x) < trunk_half \
						and absf(z) < trunk_half:
					fill = 1
				if _in_crown(x, float(vy) - crown_foot, z, radius, height, style):
					# Two tones dithered on the voxel's own parity, which is what
					# the cartridge does across a flat drawing and what keeps this
					# from reading as moulded plastic.
					fill = 2 if (vx + vy + vz) % 2 == 0 else 3
				solid[(vy * wide + vz) * wide + vx] = fill

	var bark: Color = measured.bark
	var leaf: Color = measured.crown[0]
	var leaf2: Color = measured.crown[1] if measured.crown.size() > 1 else leaf
	for vy: int in top + 1:
		for vz: int in wide:
			for vx: int in wide:
				var fill: int = solid[(vy * wide + vz) * wide + vx]
				if fill == 0:
					continue
				var color: Color = bark
				if fill == 2:
					color = leaf
				elif fill == 3:
					color = leaf2
				_faces(solid, wide, top, vx, vy, vz, reach, color)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Whether a voxel is inside the crown, which is the only thing the three styles
## disagree about.
func _in_crown(
	x: float, y: float, z: float, radius: float, height: float, style: int
) -> bool:
	if y < 0.0 or y > height:
		return false
	var half: float = height * 0.5
	var up: float = (y - half) / maxf(half, 0.5)
	var plan: float = sqrt(x * x + z * z)
	match style:
		BROAD:
			# Wide and low, the crown of a field tree: full width for most of its
			# height and rounded only at the very top.
			var taper: float = 1.0 if up < 0.35 else 1.0 - (up - 0.35) / 0.65 * 0.85
			return plan <= radius * taper
		TIERED:
			# Three bands, each a little narrower, which is what a conifer and a
			# stylised broadleaf both read as at this size.
			var band: float = floorf(clampf(y / maxf(height, 1.0), 0.0, 0.999) * 3.0)
			return plan <= radius * (1.0 - band * 0.28)
		_:
			# A ball, and the honest reading of a drawn crown: round in plan and
			# round in profile.
			return plan * plan / (radius * radius) + up * up <= 1.0


const SIDES: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]


func _faces(
	solid: PackedByteArray, wide: int, top: int,
	vx: int, vy: int, vz: int, reach: int, color: Color
) -> void:
	for side: Vector3i in SIDES:
		var nx: int = vx + side.x
		var ny: int = vy + side.y
		var nz: int = vz + side.z
		if nx >= 0 and nx < wide and nz >= 0 and nz < wide and ny >= 0 and ny <= top:
			if solid[(ny * wide + nz) * wide + nx] != 0:
				continue
		# The foot is closed anyway: nothing sees under a tree.
		if side.y < 0 and vy == 0:
			continue
		var origin := Vector3(
			float(vx - reach) * VOXEL, float(vy) * VOXEL, float(vz - reach) * VOXEL
		)
		_quad(origin, side, color)


## One voxel face, wound clockwise from outside the way the rest of this mod
## winds everything.
func _quad(origin: Vector3, side: Vector3i, color: Color) -> void:
	var normal := Vector3(float(side.x), float(side.y), float(side.z))
	var along := Vector3(0.0, 0.0, 1.0) if absf(normal.y) > 0.5 else Vector3(0.0, 1.0, 0.0)
	var right: Vector3 = along.cross(normal).normalized() * VOXEL
	var up: Vector3 = normal.cross(right.normalized()).normalized() * VOXEL
	var centre: Vector3 = origin + Vector3(VOXEL, VOXEL, VOXEL) * 0.5 \
		+ normal * (VOXEL * 0.5)
	var a: Vector3 = centre - right * 0.5 - up * 0.5
	var b: Vector3 = centre + right * 0.5 - up * 0.5
	var c: Vector3 = centre + right * 0.5 + up * 0.5
	var d: Vector3 = centre - right * 0.5 + up * 0.5
	for vertex: Vector3 in [a, c, b, a, d, c]:
		_vertices.push_back(vertex)
		_normals.push_back(normal)
		_colors.push_back(color)
