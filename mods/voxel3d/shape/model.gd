extends RefCounted

## A voxel model TURNED FROM THE DRAWING, one per distinct sprite, built once.
##
## Most of this mod stands a drawing up, because most of Generation II's art is a
## picture of a face: a wall, a facade, a shopfront seen head on. A TREE is not.
## Its sprite is a portrait of a thing that is round, and standing it up or
## carving it per pixel both fail for the same reason: they treat the picture as
## a plan. Six ways of carving one were built and measured and every one came out
## a drum, a stack of plates or a black hedge.
##
## What the sprite DOES state is the tree's profile. Its silhouette is half of a
## body of revolution: the width at each row is that row's diameter. So the model
## is the silhouette TURNED, which needs no taste at all and gets each tree's own
## shape for nothing. A pointed sprite comes out a cone, a round one a ball, a
## broad one a broad crown, and the two sizes of tree in the game come out at
## their two sizes because they are drawn at them.
##
## Three things are then added, and they are the whole of what is authored:
##
##   noise    the turned surface is smooth and a tree is not. Each voxel's own
##            radius is jittered a little, so the crown breaks into leaves and
##            the silhouette stops being a lathe.
##   roots    a trunk is not a pipe. Four roots flare from its foot, one each
##            way, which is what stops it meeting the ground in a hard circle.
##   light    see `_tone`. The drawing's own shading rule, applied in three
##            dimensions.
##
## NOTHING HERE IS CARTRIDGE CONTENT. The shape is arithmetic over a silhouette;
## the colours come from the player's own cartridge at run time, as every texel
## in this mod does.

## World pixels per voxel. One is the drawing's own resolution and is far more
## than a tree needs; two keeps the model under a couple of thousand triangles
## and still steps visibly, which is the look.
const VOXEL: float = 2.0
## And what a ROCK is built at. A voxel is an absolute size, so the same one that
## reads as chunky on a 32px tree leaves a 16px stone six voxels across and a
## sea rock three, which is a box whatever profile it was turned from. A crown is
## made of leaves and wants to be chunky; a stone has one surface and does not.
const ROCK_VOXEL: float = 1.0

## How ragged the crown is, as a share of each row's own radius. Enough to break
## the turned surface into clumps, little enough that the sprite's profile is
## still the shape being read.
const LEAF_NOISE: float = 0.22
## And how ragged a ROCK is. A crown is a thousand leaves and breaks up; a
## boulder is one stone and does not, so the jitter here is only what stops the
## turn reading as a machined dome.
const ROCK_NOISE: float = 0.08
## How far the roots reach past the trunk, and how tall they climb.
const ROOT_REACH: float = 1.6
const ROOT_RISE: float = 0.45

## THE DRAWING IS FORESHORTENED AND THE MODEL MUST NOT BE.
##
## A Generation II sprite is drawn from above and in front at once, so a tree
## states its width honestly and its height not at all: the big tree is 31 across
## and 22 down, which is a bush. Worse, the trunk is drawn almost entirely BEHIND
## the crown, so its four visible rows are what is left over rather than how tall
## it stands.
##
## So the profile is turned at its own widths and stretched up: the crown gets a
## quarter again of the rows it drew, and the trunk is held to a share of the
## crown's width, which is the proportion a tree has and a drawing of one cannot.
const CROWN_STRETCH: float = 1.3
const TRUNK_MIN: float = 0.5
## And how THICK it is, as a share of the crown's width. The drawn trunk is not
## the trunk either: what the sprite shows below the leaves is the trunk plus
## whatever of the crown's underside is drawn around it, so reading it directly
## gives a stump half as wide as the tree.
const TRUNK_THICKNESS: float = 0.22
## The least share of a band, as a percentage, a colour must cover to count as a
## material rather than as something showing through the leaves.
const TONE_SHARE: int = 8

## THREE OTHER WAYS OF SPENDING THE COLOURS WERE BUILT AND REFUSED, in round
## twenty-six, and they must not be re-derived. The reviewer saw all four in one
## sheet and in one wood and took the one below.
##
##   KEPT    what was in until then: the shades the drawing uses MINUS its
##           darkest, spent on exposure. The darkest is the outline a flat
##           drawing needs, so it was dropped whole, which left most crowns TWO
##           colours. That is the poverty this replaced, and it is what the
##           reviewer saw without being told to look for it.
##   DEEP    the same rule with the darkest kept for the deepest faces.
##   TURNED  the drawing's own colour at that row and that distance from the
##           centre. It needed the outline dropped from the ring and the dither
##           read by its commonest colour, and both of those are worth knowing:
##           a drawn row's outermost pixels are its outline and the outer ring of
##           a turned body is nearly all of its surface, so an outline kept is an
##           outline sprayed over the whole crown.
##
## Pictures for all four are in the survey directory under `round26/styles`.


var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
## Per vertex: how far up the CROWN it stands, 0 through the trunk and 1 at the
## top, which is what `world/wind.gd` bends the tree by. A model carries no
## texture, its colour being baked into the vertices, so UV is free for it.
var _sways := PackedVector2Array()
## The weight the next face is written with, set per voxel row.
var _sway: float = 0.0
## And the drawing's own colour at that row, which is what a ROCK is painted in.
var _band := Color(0.5, 0.5, 0.5)
## World pixels per voxel for the model being built. See `FINE_VOXEL`.
var _voxel: float = VOXEL


## What the drawing states about the thing it depicts.
##
## The PROFILE is the whole of the shape: half the drawn width at each row of the
## crown, top row first, in world pixels. Everything else here is either the
## trunk, which the drawing states directly, or colour.
class Measure extends RefCounted:
	var profile := PackedFloat32Array()
	var trunk_width: int = 6
	var trunk_height: int = 10
	## A SHRUB sits on the ground. It has no trunk to hold its crown up, no roots
	## to flare, and it is not foreshortened either: a tree is drawn small because
	## it is far away and tall, where a bush the reviewer measured as "about as
	## tall as the player" is drawn at the height it stands. Stretching one and
	## standing it on a stalk makes a small tree, which is what the first attempt
	## looked like.
	var shrub: bool = false
	## A ROCK is not a plant. It sits on the ground as a shrub does, and the three
	## other things this mod does to a plant are all wrong for it: it is barely
	## ragged, it does not bend in the wind, and it is not the dark mass a hedge
	## is, so the drawing's own exposure reads straight back off it.
	var rock: bool = false
	## A COLUMN is not turned from its silhouette: it is the widest row's radius
	## all the way up, with a flat top. See `profile.gd:COLUMN`.
	var column: bool = false
	## HOW TALL THE THING STANDS AGAINST HOW TALL IT IS DRAWN, where a person has
	## said and the drawing cannot. Zero takes the class's own default: 1.3 for a
	## tree, which is the foreshortening, and 1.0 for anything sitting on the
	## ground, which is the drawing read literally.
	##
	## A drawing being tall on screen is not a thing being tall in the world, and
	## this file is the third place that has had to say so: the reviewer corrected
	## the long flower bed, then the school chair, whose twelve drawn rows they
	## measured at six. A round stool is the same case at model scale. What a
	## face-on drawing states honestly is its WIDTH.
	var stretch: float = 0.0
	## Lightest first, and the drawing's darkest shade is NOT among them.
	var tones: PackedColorArray = PackedColorArray()
	## The same reading with the drawing's DARKEST kept, lightest first. This is
	## what the crown is painted from: see `_lit`.
	var shades: PackedColorArray = PackedColorArray()
	var bark: PackedColorArray = PackedColorArray()
	## The drawing's own colour at each row of the profile, top row first, which is
	## how a ROCK is painted. See `_bands`.
	var bands: PackedColorArray = PackedColorArray()
	## The colour of the CAP: what a drawing seen from above puts on the top of the
	## thing, which is the commonest colour over its upper rows. Only a COLUMN uses
	## it, and it is the one thing a band cannot say, since a band maps a drawn row
	## onto a HEIGHT and a cap is not at a height at all. See `_cap`.
	var cap := Color(0.5, 0.5, 0.5)

	func width() -> int:
		var widest: float = 0.0
		for radius: float in profile:
			widest = maxf(widest, radius)
		return int(widest * 2.0)

	func height() -> int:
		return profile.size() + trunk_height


## Reads the profile, the trunk and the colours off one cut drawing.
##
## The crown is the rows down to where the drawing narrows to a stick, the trunk
## is the stick, and whatever is below THAT is the shadow the tree is drawn
## standing in, which is not part of the tree. Reading the bands downward is what
## gets the trunk: the shadow is as wide as the crown, so a rule that looks
## upward from the foot finds a trunk one pixel tall and a tree with no trunk.
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
		out.profile = PackedFloat32Array([6.0, 8.0, 8.0, 6.0])
		out.tones = PackedColorArray([Color(0.35, 0.62, 0.28), Color(0.2, 0.42, 0.18)])
		out.shades = out.tones
		out.bark = PackedColorArray([Color(0.42, 0.28, 0.14)])
		return out

	var narrow: int = maxi(widest / 2, 1)
	# The crown ends where the drawing narrows to a stick BELOW ITS WIDEST ROW,
	# which is not the same as the first narrow row and the difference is a whole
	# class of tree. A fir is pointed: its top row is two pixels across, so a scan
	# starting at the top stops before it has begun and the crown comes out one row
	# of the widest radius, which is a flat disk on a stump. Every conifer in the
	# game is drawn that way, and the round tree only escaped it by one pixel.
	var widest_row: int = first_row
	for py: int in range(first_row, last_row + 1):
		if widths[py] == widest:
			widest_row = py
			break
	var crown_bottom: int = widest_row
	while crown_bottom <= last_row and widths[crown_bottom] > narrow:
		crown_bottom += 1
	var trunk_bottom: int = crown_bottom
	while trunk_bottom <= last_row and widths[trunk_bottom] > 0 \
			and widths[trunk_bottom] <= narrow:
		trunk_bottom += 1
	var trunk: int = 0
	for py: int in range(crown_bottom, trunk_bottom):
		trunk = maxi(trunk, widths[py])

	for py: int in range(first_row, crown_bottom):
		out.profile.append(float(widths[py]) * 0.5)
	if out.profile.is_empty():
		out.profile.append(float(widest) * 0.5)
	out.trunk_height = maxi(trunk_bottom - crown_bottom, 2)
	out.trunk_width = maxi(trunk, 3)

	out.tones = _tones(mask, span, tiles, across, atlas, first_row, crown_bottom - 1)
	out.shades = _tones(
		mask, span, tiles, across, atlas, first_row, crown_bottom - 1, false
	)
	out.bands = _bands(mask, span, tiles, across, atlas, first_row, crown_bottom - 1)
	out.cap = _cap(out.bands)
	# The bark is read all the way down to the drawing's last row, shadow and all:
	# what a tree draws under its crown is trunk, roots and the dark they sit in,
	# and the trunk band alone is too few pixels to rank on some tilesets.
	out.bark = _tones(mask, span, tiles, across, atlas, crown_bottom, last_row)
	# Bark is what is under the leaves and is NOT leaves. The band below a crown
	# is drawn with the crown's own greens in it wherever the canopy hangs over
	# the trunk, and taking the lightest of those paints a green trunk: dropping
	# every tone the crown already claimed is what leaves the wood behind.
	var wood := PackedColorArray()
	for colour: Color in out.bark:
		var claimed: bool = false
		for leaf: Color in out.tones:
			if leaf.is_equal_approx(colour):
				claimed = true
		if not claimed:
			wood.append(colour)
	if not wood.is_empty():
		out.bark = wood
	if out.tones.is_empty():
		out.tones = PackedColorArray([Color(0.35, 0.62, 0.28), Color(0.2, 0.42, 0.18)])
	if out.shades.is_empty():
		out.shades = out.tones
	if out.bark.is_empty():
		out.bark = PackedColorArray([Color(0.42, 0.28, 0.14)])
	return out


## The colours a band of the drawing is painted in, LIGHTEST FIRST, with each
## tile's darkest shade left out.
##
## The darkest shade is the outline. It is how a flat drawing separates itself
## from a flat background, and a solid standing in a real light has a silhouette
## already: painting it on is what made every carved attempt read as a lump of
## coal. What is left is the material, and it arrives sorted, which is what lets
## `_tone` spend it on the light.
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
	# BY COUNT FIRST, and only then by light. A tone the drawing spends a handful
	# of pixels on is not a material: the mask keeps whatever the outline
	# encloses, so a few pixels of the pale ground show through a gap in the
	# leaves, and ranking on brightness alone promoted those to the colour of
	# every sunlit face in the forest. Every tree in the game came out white.
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


## THE DRAWING'S OWN COLOUR AT EACH ROW, top row first.
##
## A crown is shaded leaf by leaf and the exposure rule reads it back in three
## dimensions, which is right for a plant and wrong for a STONE: a boulder is
## drawn in horizontal bands, pale where the sky reaches it and dark underneath,
## and that banding IS the shape saying which way is up. Read by exposure instead,
## a rock small enough to have nothing standing over it takes the lightest tone on
## every face, which turned the cave's gold boulder into a white one.
##
## The commonest colour across the row, skipping the outline, and a row with
## nothing in it keeps the row above: the fill of a broken ring can leave a row of
## the drawing empty and a boulder has no gaps in it.
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
	# A row above the first the drawing put any colour in keeps grey until one is
	# found, so the first colour is carried back up over them.
	if seen:
		for at: int in out.size():
			if out[at].is_equal_approx(Color(0.5, 0.5, 0.5)):
				continue
			for above: int in at:
				out[above] = out[at]
			break
	return out


## THE COLOUR OF A CAP, out of the bands the drawing was read into.
##
## A 2.5D sprite is a top and a front stacked, which this mod already reads that
## way at object and at building scale. A bollard is the same picture: its upper
## rows are the flat top seen from ABOVE and its lower rows are the side. Mapped
## onto height like any other band, the cap ends up painted round the shoulder of
## the cylinder and the top face takes the outline ring drawn at the very top,
## which is how a pale concrete cap came out grey.
##
## The commonest band over the upper half, then, which is the cap wherever a
## drawing has one and is the upper body wherever it does not.
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


static func _luminance(colour: Color) -> float:
	return colour.r * 0.299 + colour.g * 0.587 + colour.b * 0.114


const EMPTY: int = 0
const BARK: int = 1
const LEAF: int = 2


## Turns the profile into a voxel tree, centred on x and z, standing on y = 0.
func tree(measured: Measure) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_sways = PackedVector2Array()

	_voxel = ROCK_VOXEL if measured.rock else VOXEL
	var rows: int = measured.profile.size()
	var stretch: float = measured.stretch
	if stretch <= 0.0:
		stretch = 1.0 if measured.shrub else CROWN_STRETCH
	var crown_high: int = maxi(ceili(float(rows) * stretch / _voxel), 2)
	var trunk_high: int = 0 if measured.shrub else maxi(ceili(maxf(
		float(measured.trunk_height), float(measured.width()) * TRUNK_MIN
	) / _voxel), 2)
	var trunk_half: float = maxf(
		float(measured.width()) * TRUNK_THICKNESS * 0.5 / _voxel, 1.0
	)
	var widest: float = 0.0
	for radius: float in measured.profile:
		widest = maxf(widest, radius / _voxel)
	var reach: int = ceili(widest + (0.0 if measured.shrub else ROOT_REACH)) + 1
	var wide: int = reach * 2 + 1
	var tall: int = trunk_high + crown_high + 1

	var solid := PackedByteArray()
	solid.resize(wide * wide * tall)
	for vy: int in tall:
		for vz: int in wide:
			for vx: int in wide:
				var x: float = float(vx - reach)
				var z: float = float(vz - reach)
				var plan: float = sqrt(x * x + z * z)
				var fill: int = EMPTY
				if vy < trunk_high:
					# The trunk, and four roots flaring from its foot: a tree does
					# not meet the ground in a circle, and the flare is most of
					# what says which way is down.
					var root: float = maxf(
						1.0 - float(vy) / (float(trunk_high) * ROOT_RISE), 0.0
					) * ROOT_REACH
					var along: float = maxf(absf(x), absf(z))
					var across_root: float = minf(absf(x), absf(z))
					if plan <= trunk_half \
							or (across_root <= trunk_half * 0.55 \
								and along <= trunk_half + root):
						fill = BARK
				if fill == EMPTY:
					# The crown stands ON the trunk, so its foot is the trunk's top
					# and it is read upward from there.
					var radius: float = _radius(measured, vy - trunk_high, crown_high)
					if radius > 0.0:
						# The jitter is the leaves. Deterministic, so one tree is
						# one model however many times it is stamped.
						# A COLUMN takes none: the jitter is what stops a turn reading
						# as lathe work, and a bollard IS lathe work.
						var ragged: float = 0.0 if measured.column \
							else (ROCK_NOISE if measured.rock else LEAF_NOISE)
						var wobble: float = 1.0 + (_hash(vx, vy, vz) - 0.5) * 2.0 * ragged
						if plan <= radius * wobble:
							fill = LEAF
				solid[(vy * wide + vz) * wide + vx] = fill

	for vy: int in tall:
		# ZERO THROUGH THE TRUNK, because a trunk that sways is a tree falling
		# over, and rising through the crown from its foot. A shrub has no trunk
		# and so bends from its own base, which is what a springy mass does; its
		# bottom row still measures zero, so it stays on the ground. A ROCK is zero
		# everywhere, which is how a model made of the same material and stamped by
		# the same code stands still in the wind that moves the wood.
		_sway = 0.0 if measured.rock else clampf(
			float(vy - trunk_high) / float(maxi(crown_high - 1, 1)), 0.0, 1.0
		)
		_band = _band_at(measured, vy - trunk_high, crown_high)
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


## The crown's radius at a voxel row, in voxels, read off the drawing's own
## profile. [param up] counts from the crown's foot.
func _radius(measured: Measure, up: int, crown_high: int) -> float:
	if up < 0 or up >= crown_high:
		return 0.0
	# A COLUMN is the widest row all the way up, which is what makes its side
	# straight and its top flat. It is not a taper read off the drawing, because
	# what tapers in the drawing is the far edge of a flat cap seen from above.
	if measured.column:
		return float(measured.width()) * 0.5 / _voxel
	var rows: int = measured.profile.size()
	# The profile is written top row first and the model is built from the
	# ground, so the row is read from the far end.
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1) / float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return measured.profile[at] / _voxel


## The drawing's colour at a voxel row, read off the same profile row `_radius`
## reads the width off, so a band and the width it paints belong to each other.
func _band_at(measured: Measure, up: int, crown_high: int) -> Color:
	if measured.bands.is_empty():
		return Color(0.5, 0.5, 0.5)
	var rows: int = measured.bands.size()
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1)
			/ float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return measured.bands[at]


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
	# How much of the sky the voxel can see, which is what decides its colour: the
	# column ABOVE it and how enclosed it is by the twenty-six voxels AROUND it.
	# See `_tone`. Both are counted once per voxel, since they are facts about the
	# voxel and `_tone` is asked six times for it.
	# COUNTED ONLY IF SOMETHING IS DRAWN, and only once for the six faces. The
	# twenty-six neighbours are what the colour rule costs: the round tree's build
	# went from 10.4 ms to 17.6 counting them for every solid voxel, and 16.1
	# counting them only where a face is emitted. Less than it looks, because a
	# jittered crown is nearly all surface and has little inside it.
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
		# Nothing sees under a tree, and the foot is closed by the ground.
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
		_quad(origin, side, _tone(measured, fill, side, sky, near))


## THE DRAWING'S OWN SHADING RULE, IN THREE DIMENSIONS.
##
## A Game Boy artist has three usable shades and spends them on one thing: where
## the light falls. The pale ones are the top of the canopy where the sky reaches
## it, the dark ones are underneath and inside. That is not decoration, it is the
## drawing saying which way is up, and it is exactly the information a flat
## picture loses when it becomes a solid.
##
## So the shades are spent the same way here, on how much of the sky a face can
## see. See `_lit` for the rule, and for the two things it took to make the
## drawing's WHOLE palette usable rather than most of it.
func _tone(
	measured: Measure, fill: int, side: Vector3i, sky: int, near: int
) -> Color:
	var palette: PackedColorArray = measured.bark if fill == BARK else measured.tones
	# The crown is painted from the drawing's whole ladder, its darkest included.
	# A ROCK is painted by BAND and keeps the reading it was measured with, which
	# is that ladder without it.
	if fill == LEAF and not measured.rock and not measured.shades.is_empty():
		palette = measured.shades
	if palette.is_empty():
		return Color(0.3, 0.5, 0.25)
	# A ROCK IS PAINTED BY BAND, not by exposure: see `_bands`. What is left of the
	# rule here is the one thing a band cannot say, which is that a face looking
	# down at the ground is in its own shadow.
	if measured.rock:
		# A COLUMN's top face is the CAP the drawing draws, not the band at the
		# height the cap happens to be drawn at. See `_cap`.
		if measured.column and side.y > 0:
			return measured.cap
		if side.y >= 0:
			return _band
		return palette[clampi(_ladder(palette, _band) + 1, 0, palette.size() - 1)]
	# A SHRUB STARTS A STEP DARKER, because exposure alone reads it wrong. The
	# rule spends the palette on how much stands over a face, and almost nothing
	# stands over a thing seven voxels tall: every top face takes the lightest
	# tone and a hedge that the cartridge draws as a dark mass comes out a pale
	# one. The drawing is the authority on how dark the thing is and the tree's
	# own reading is what borrowed it out.
	# A ROCK is not that dark mass and is not read as one: a boulder is drawn pale
	# on top and shaded down its side, which is the exposure rule already, so it
	# takes the tree's own reading rather than the shrub's correction to it.
	var dark_mass: bool = measured.shrub and not measured.rock
	return _lit(palette, side, sky, near, dark_mass)


## LIT. The palette spent on how much of the sky a face can see, counted over the
## voxels AROUND it rather than the column above it, and mixed between rungs.
##
## Two things it answers that stepping by the column does not. A voxel deep in
## the middle of a crown has as much sky over it as one at the edge of the same
## row, so the whole rim of a wide tree took the same tone as its middle; and a
## drawing with two shades in it had two tones to spend however deep the body
## went, which is what makes a big crown read flat.
##
## Mixing is the one thing here that puts a colour on the model the cartridge did
## not draw, and it is the only place in this mod that does. It stays between two
## of the drawing's own shades and never outside them. The reviewer took it in
## round twenty-six over three rules that do not mix, having been told which one
## was which and shown all four in a wood.
func _lit(
	palette: PackedColorArray, side: Vector3i, sky: int, near: int, dark_mass: bool
) -> Color:
	var rung: float = 1.0 if dark_mass else 0.0
	if side.y > 0:
		rung -= 0.5
	elif side.y < 0:
		rung += 0.6
	rung += float(sky) * 0.5
	# Out of the twenty-six voxels around it, so a face on an open rim is lighter
	# than one in a hollow with the same sky over it.
	rung += float(near) / 26.0 * 1.6
	var top: int = palette.size() - 1
	var at: float = clampf(rung, 0.0, float(top))
	var low: int = int(floorf(at))
	return palette[low].lerp(palette[mini(low + 1, top)], at - float(low))


## Where a colour sits on a ladder of shades, lightest first, so a band or a ring
## can be stepped down from without leaving the cartridge's palette.
func _ladder(palette: PackedColorArray, colour: Color) -> int:
	for at: int in palette.size():
		if palette[at].is_equal_approx(colour):
			return at
	return 0


## One voxel face, wound clockwise from outside the way the rest of this mod
## winds everything.
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
		_sways.push_back(Vector2(_sway, 0.0))
