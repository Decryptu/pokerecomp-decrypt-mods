extends RefCounted

## A voxel model turned from the drawing, one per distinct sprite, built once.
##
## Most of this mod stands a drawing up, because most of Generation II's art is a
## picture of a face. A tree is not: its sprite is a portrait of something round,
## and standing it up or carving it per pixel both treat the picture as a plan.
## Six ways of carving one were built and measured and every one came out a drum,
## a stack of plates or a black hedge.
##
## What the sprite does state is the profile: its silhouette is half a body of
## revolution, the width at each row being that row's diameter. So the model is
## the silhouette turned, which needs no taste and gets each tree's own shape for
## nothing: a pointed sprite comes out a cone, a round one a ball.
##
## Three things are added, and they are the whole of what is authored:
##
##   noise    each voxel's radius is jittered, so the crown breaks into leaves
##            and the silhouette stops being a lathe.
##   roots    four flare from the trunk's foot, so it does not meet the ground
##            in a hard circle.
##   light    see `_tone`, the drawing's own shading rule in three dimensions.
##
## No cartridge content is here: the shape is arithmetic over a silhouette and
## the colours come from the player's own cartridge at run time.

## World pixels per voxel. One is the drawing's own resolution and is far more
## than a tree needs; two keeps the model under a couple of thousand triangles
## and still steps visibly, which is the look.
const VOXEL: float = 2.0
## And what a rock is built at. A voxel is an absolute size, so the one that reads
## as chunky on a 32px tree leaves a 16px stone six voxels across, which is a box
## whatever profile it was turned from.
const ROCK_VOXEL: float = 1.0
## The least stalk a potted plant stands its crown on, in world pixels. The crown
## hangs over most of the drawn stalk, so read literally the leaves sit on the rim.
const POT_STALK: float = 5.0
## How far a potted crown's two lit flanks move on the ladder, in rungs.
const LEAF_FLANK: float = 0.9

## How ragged the crown is, as a share of each row's radius: enough to break the
## turned surface into clumps, little enough that the profile still reads.
const LEAF_NOISE: float = 0.22
## And how ragged a rock is. A boulder is one stone, so the jitter is only what
## stops the turn reading as a machined dome.
const ROCK_NOISE: float = 0.08
## How far the roots reach past the trunk, and how tall they climb.
const ROOT_REACH: float = 1.6
const ROOT_RISE: float = 0.45

## The drawing is foreshortened and the model must not be.
##
## A Generation II sprite is drawn from above and in front at once, so a tree
## states its width honestly and its height not at all: the big tree is 31 across
## and 22 down, which is a bush. The trunk is drawn almost entirely behind the
## crown, so its four visible rows are what is left over rather than its height.
##
## So the profile is turned at its own widths and stretched up: the crown gets a
## quarter again of the rows it drew, and the trunk is held to a share of the
## crown's width.
const CROWN_STRETCH: float = 1.3
const TRUNK_MIN: float = 0.5
## And how thick it is, as a share of the crown's width. What the sprite shows
## below the leaves is the trunk plus whatever of the crown's underside is drawn
## around it, so reading it directly gives a stump half as wide as the tree.
const TRUNK_THICKNESS: float = 0.22
## The least share of a band, as a percentage, a colour must cover to count as a
## material rather than as something showing through the leaves.
const TONE_SHARE: int = 8

## Three other ways of spending the colours were built and refused, and must not
## be re-derived:
##
##   KEPT    the shades the drawing uses minus its darkest, spent on exposure.
##           The darkest is the outline a flat drawing needs, so dropping it
##           whole left most crowns two colours.
##   DEEP    the same rule with the darkest kept for the deepest faces.
##   TURNED  the drawing's own colour at that row and that distance from the
##           centre. It needs the outline dropped from the ring and the dither
##           read by its commonest colour: a drawn row's outermost pixels are its
##           outline, and the outer ring of a turned body is nearly all of its
##           surface, so an outline kept is one sprayed over the whole crown.

## How a column is built was the same question one level down. What `_radius`,
## `_band_at` and `_tone` do now: the ends bevelled, the lid's rows out of the
## side, and the side painted by the drawn column. What was refused, so nobody
## rebuilds it: a straight barrel painted by band alone, which reads as a plain
## drum; the bevel on its own; and the bevel with the lid taken out but the side
## still mixed by row.


var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
## Per vertex: how far up the crown it stands, 0 through the trunk and 1 at the
## top, which is what `world/wind.gd` bends the tree by. A model carries no
## texture, so UV is free for it.
var _sways := PackedVector2Array()
var _uvs := PackedVector2Array()
## The sway weight is read off the VERTEX rather than the voxel row, so these are
## the two numbers a vertex height is measured against: where the crown's foot is
## and how tall it is, both in world pixels. See `_sway_at`.
var _sway_foot: float = 0.0
var _sway_span: float = 1.0
var _sway_still: bool = false
## And the drawing's own colour at that row, which is what a ROCK is painted in.
var _band := Color(0.5, 0.5, 0.5)
## And its colours ACROSS that row, left to right, which is what a WRAPPED column
## is painted with. Set per voxel row beside `_band`.
var _wrap := PackedColorArray()
## World pixels per voxel for the model being built. See `FINE_VOXEL`.
var _voxel: float = VOXEL


## What the drawing states about the thing it depicts.
##
## The profile is the whole shape: half the drawn width at each row of the crown,
## top row first, in world pixels. Everything else is either the trunk, which the
## drawing states directly, or colour.
class Measure extends RefCounted:
	var profile := PackedFloat32Array()
	var trunk_width: int = 6
	var trunk_height: int = 10
	## A shrub sits on the ground: no trunk, no roots, and not foreshortened
	## either, since a bush is drawn at the height it stands. Stretching one and
	## standing it on a stalk makes a small tree, which the first attempt was.
	var shrub: bool = false
	## A POTTED plant keeps the rows below its stalk: they are the pot, not the
	## shadow the thing stands in. Half the drawn width at each of those rows, top
	## first, and the drawing's own colour at each of them.
	var potted: bool = false
	var pot := PackedFloat32Array()
	var pot_bands: PackedColorArray = PackedColorArray()
	## A rock is not a plant. It sits on the ground as a shrub does, is barely
	## ragged, does not bend in the wind, and is not the dark mass a hedge is, so
	## the drawing's own exposure reads straight back off it.
	var rock: bool = false
	## A COLUMN is not turned from its silhouette: it is the widest row's radius
	## all the way up, with a flat top. See `profile.gd:COLUMN`.
	var column: bool = false
	## How tall the thing stands against how tall it is drawn, where a person has
	## said and the drawing cannot. Zero takes the class default: 1.3 for a tree,
	## which is the foreshortening, and 1.0 for anything on the ground.
	##
	## A drawing being tall on screen is not a thing being tall in the world, and
	## this is the third place that has had to say so, after the long flower bed
	## and the school chair. What a face-on drawing states honestly is its WIDTH.
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
	## How many of the drawing's leading rows ARE that cap, so a column can take
	## them out of its side. See `_cap_rows`.
	var cap_rows: int = 0
	## The bands with those rows taken out: what a column's SIDE is painted from.
	var side_bands: PackedColorArray = PackedColorArray()
	## Per side row, the drawing's own colours across it, left to right, which is
	## what wraps round a barrel. See `_wraps`.
	var wraps: Array = []

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
## is the stick, and below that is the shadow the tree is drawn standing in.
## Reading downward is what gets the trunk: the shadow is as wide as the crown, so
## looking upward from the foot finds a trunk one pixel tall.
static func measure(
	mask: PackedByteArray, span: Vector2i, tiles: Array, across: Vector2i,
	atlas: RefCounted, measured_pot: bool = false
) -> Measure:
	var out := Measure.new()
	out.potted = measured_pot
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
	# which is not the first narrow row, and the difference is a whole class of
	# tree: a fir's top row is two pixels across, so a scan from the top stops
	# before it begins and comes out a disk on a stump.
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

	# The pot is what is left under the stalk, and only where a person has said
	# the thing has one: the same rows under a tree are its shadow.
	#
	# The stalk ends where the drawing widens again, which is not what
	# `trunk_bottom` answers: that stops at the first row wider than half the
	# crown, and a pot's rim is drawn exactly that wide.
	var pot_top: int = crown_bottom
	if measured_pot:
		var thin: int = 0
		for py: int in range(crown_bottom, last_row + 1):
			if widths[py] > 0 and (thin == 0 or widths[py] < thin):
				thin = widths[py]
		while pot_top <= last_row and widths[pot_top] <= thin:
			pot_top += 1
		out.trunk_height = maxi(pot_top - crown_bottom, 1)
	if measured_pot and pot_top <= last_row:
		for py: int in range(pot_top, last_row + 1):
			out.pot.append(float(widths[py]) * 0.5)
		out.pot_bands = _bands(mask, span, tiles, across, atlas, pot_top, last_row)
	out.tones = _tones(mask, span, tiles, across, atlas, first_row, crown_bottom - 1)
	out.shades = _tones(
		mask, span, tiles, across, atlas, first_row, crown_bottom - 1, false
	)
	out.bands = _bands(mask, span, tiles, across, atlas, first_row, crown_bottom - 1)
	out.cap = _cap(out.bands)
	out.cap_rows = _cap_rows(out.bands, out.cap)
	# The side is what is left under the cap, and never nothing: a drawing that is
	# all lid keeps its whole band rather than coming back blank.
	for at: int in range(out.cap_rows, out.bands.size()):
		out.side_bands.append(out.bands[at])
	if out.side_bands.is_empty():
		out.side_bands = out.bands
	out.wraps = _wraps(
		mask, span, tiles, across, atlas, first_row + out.cap_rows, crown_bottom - 1
	)
	# Bark is read down to the drawing's last row, shadow and all: what a tree
	# draws under its crown is trunk, roots and the dark they sit in, and the
	# trunk band alone is too few pixels to rank on some tilesets. A potted
	# plant's stalk is the stalk: below the crown is the pot, and reading it in
	# paints a blue stem under a green crown.
	out.bark = _tones(
		mask, span, tiles, across, atlas, crown_bottom,
		(pot_top - 1) if measured_pot and pot_top > crown_bottom else last_row
	)
	# Bark is what is under the leaves and is NOT leaves: the band below a crown
	# carries the crown's own greens wherever the canopy hangs over the trunk, so
	# dropping every tone the crown claimed is what leaves the wood behind.
	#
	# And bark is never lighter than the leaves over it, which is what the cut
	# tree needed: its stem is two dark lines with the grass between them, and the
	# flood encloses that grass, so the leftover came back at 0.89 luminance
	# against the crown's 0.66. A trunk stands in its own shade, so anything
	# brighter than the brightest leaf is ground showing through the drawing. When
	# both filters empty the band, the darkest shade is what is left.
	var lightest: float = 0.0
	for leaf: Color in out.tones:
		lightest = maxf(lightest, leaf.get_luminance())
	var wood := PackedColorArray()
	for colour: Color in out.bark:
		var claimed: bool = false
		for leaf: Color in out.tones:
			if leaf.is_equal_approx(colour):
				claimed = true
		if not claimed and colour.get_luminance() <= lightest:
			wood.append(colour)
	# Only where the band had something to say. A band ranking no tone at all,
	# which is most conifers, already has the authored brown below, and that is
	# right for a trunk the drawing does not paint.
	if wood.is_empty() and not out.bark.is_empty() and not out.shades.is_empty():
		wood.append(out.shades[out.shades.size() - 1])
	if not wood.is_empty():
		out.bark = wood
	if out.tones.is_empty():
		out.tones = PackedColorArray([Color(0.35, 0.62, 0.28), Color(0.2, 0.42, 0.18)])
	if out.shades.is_empty():
		out.shades = out.tones
	if out.bark.is_empty():
		out.bark = PackedColorArray([Color(0.42, 0.28, 0.14)])
	return out


## The colours a band of the drawing is painted in, lightest first, with each
## tile's darkest shade left out.
##
## The darkest shade is the outline, which is how a flat drawing separates itself
## from a flat background. A solid in a real light has a silhouette already, and
## painting one on is what made every carved attempt read as a lump of coal. What
## is left is the material, sorted, which is what `_tone` spends on the light.
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
	# By count first and only then by light. A tone the drawing spends a handful
	# of pixels on is not a material: a few pixels of pale ground show through a
	# gap in the leaves, and ranking on brightness alone made every tree white.
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


## The drawing's own colour at each row, top row first.
##
## A crown is shaded leaf by leaf and the exposure rule reads that back in three
## dimensions, which is right for a plant and wrong for a stone: a boulder is
## drawn in horizontal bands, pale where the sky reaches it and dark underneath,
## and that banding is the shape saying which way is up. Read by exposure, a small
## rock takes the lightest tone on every face.
##
## The commonest colour across the row, skipping the outline. A row with nothing
## in it keeps the row above, since a boulder has no gaps in it.
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


## The colour of a cap, out of the bands the drawing was read into.
##
## A 2.5D sprite is a top and a front stacked. A bollard's upper rows are the flat
## top seen from above and its lower rows the side; mapped onto height like any
## other band, the cap ends up painted round the shoulder and the top face takes
## the outline ring drawn at the very top.
##
## So it is the commonest band over the upper half: the cap where a drawing has
## one and the upper body where it does not.
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


## How many leading rows are the cap: the deepest row in the drawing's upper half
## still painted the cap's colour, and everything above it. Counting the leading
## run misses it, because a drawing's first row is its outline arc rather than its
## lid, so a run test stops there and calls the cap zero rows deep.
static func _cap_rows(bands: PackedColorArray, cap: Color) -> int:
	var deepest: int = -1
	for at: int in maxi(bands.size() / 2, 1):
		if bands[at].is_equal_approx(cap):
			deepest = at
	return deepest + 1


## The drawing's own colours across each row, left to right, one per world pixel
## of the row's width, for the rows a column's side is painted from.
##
## A barrel is the one shape where a drawn row IS the surface: the sprite shows
## the near half straight on, so the pixel three across from the middle is what
## the barrel looks like three across from its middle, and the lit and shaded
## sides wrap round as drawn. The one reading here that keeps WHERE across a
## drawing a colour was used.
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
				# The outline is the drawing's edge and not the barrel's colour at
				# that column: it would paint a black stripe down both flanks.
				if index < 0 or atlas.is_dark(tile, index, 1):
					row.append(Color(0.0, 0.0, 0.0, 0.0))
				else:
					row.append(atlas.color_of(tile, index))
			# An outline pixel takes the nearest colour inside it, so the flanks
			# are the material rather than a hole.
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
## The pot a houseplant stands in, painted by the drawing's own band at its own
## row the way a rock is rather than by exposure: a pot is one glazed surface and
## the cartridge has already shaded it.
const POT: int = 3


## Turns the profile into a voxel tree, centred on x and z, standing on y = 0.
func tree(measured: Measure) -> ArrayMesh:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_sways = PackedVector2Array()

	# A houseplant is a 16 px THING and the two-pixel voxel a crown is chunked at
	# leaves its pot six voxels across, which is a box. Same reasoning as a rock's.
	_voxel = ROCK_VOXEL if measured.rock or measured.potted else VOXEL
	var rows: int = measured.profile.size()
	var stretch: float = measured.stretch
	if stretch <= 0.0:
		stretch = 1.0 if measured.shrub else CROWN_STRETCH
	var crown_high: int = maxi(ceili(float(rows) * stretch / _voxel), 2)
	# A houseplant's stalk is drawn in front of its crown and states its own
	# length, where a tree's is drawn behind one and states nothing, which is what
	# the floor under `TRUNK_MIN` is for. It is still held to `POT_STALK`: a
	# shorter stalk is a crown sitting on the rim with no plant between the two.
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
	# The pot is turned the way the crown is and it stands on the ground, with the
	# stalk and the crown lifted onto its rim. Its rows are read the other way up:
	# the drawing's last row is the pot's foot.
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
	# Zero through the trunk, because a trunk that sways is a tree falling over,
	# rising through the crown from its foot. A shrub has no trunk and bends from
	# its own base, its bottom vertices still measuring zero. A rock is zero
	# everywhere, so it stands still in the wind that moves the wood.
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
					# The pot's own drawn width at that row, its last row lowest.
					var at_row: int = mini(
						int(float(pot_high - 1 - vy) * _voxel), measured.pot.size() - 1
					)
					# A pot has a rim: its top course stands a voxel proud of the
					# body, which is what tells a pot from a drum and what the
					# drawn rim row is too narrow to say once turned.
					var wall: float = measured.pot[at_row] / _voxel
					if vy == pot_high - 1:
						wall += 1.0
					if plan <= wall:
						fill = POT
				elif vy < pot_high + trunk_high:
					# The trunk, and four roots flaring from its foot: a tree does
					# not meet the ground in a circle, and the flare is most of
					# what says which way is down.
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
					# The crown stands ON the trunk, so its foot is the trunk's top
					# and it is read upward from there.
					var radius: float = _radius(
						measured, vy - pot_high - trunk_high, crown_high
					)
					if radius > 0.0:
						# The jitter is the leaves, and deterministic, so one tree
						# is one model however often it is stamped. A column takes
						# none: a bollard IS lathe work.
						var ragged: float = 0.0 if measured.column \
							else (ROCK_NOISE if measured.rock else LEAF_NOISE)
						if plan <= radius * _wobble(x, z, plan, vy, ragged):
							fill = LEAF
				solid[(vy * wide + vz) * wide + vx] = fill

	for vy: int in tall:
		_band = _band_at(measured, vy - pot_high - trunk_high, crown_high)
		_wrap = _wrap_at(measured, vy - pot_high - trunk_high, crown_high)
		if vy < pot_high and not measured.pot_bands.is_empty():
			# The bands are the drawing's rows top first and the model is built
			# from the ground, so the foot of the pot is the LAST of them.
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


## How much of its row's radius the crown reaches along one ray, in 0 to 1.
##
## The jitter is a rough surface and not a sieve, and what makes the difference is
## what the hash is keyed on. Keyed on the VOXEL the wobble differs for every
## voxel along one ray, so the shell is a speckle with the ground visible through
## it. Keyed on the RAY there is one radius per direction per row, so everything
## inside is solid and the silhouette is as ragged as before.
##
## And it only ever cuts in. A sprite states its WIDTH honestly, so a crown
## wobbling out is wider than what the cartridge drew: the bush came out 18 px
## across on a 16 px cell and stood on the road.
##
## `RAY_STEPS` is how coarse the directions are, which decides how big a clump of
## leaves is. Finer and the crown reads as sandpaper.
const RAY_STEPS: float = 8.0


func _wobble(x: float, z: float, plan: float, vy: int, ragged: float) -> float:
	if ragged <= 0.0:
		return 1.0
	var ray: float = maxf(plan, 1.0)
	return 1.0 - _hash(
		int(roundf(x / ray * RAY_STEPS)), vy, int(roundf(z / ray * RAY_STEPS))
	) * ragged


## The crown's radius at a voxel row, in voxels, read off the drawing's own
## profile. [param up] counts from the crown's foot.
func _radius(measured: Measure, up: int, crown_high: int) -> float:
	if up < 0 or up >= crown_high:
		return 0.0
	# A column is the widest row all the way up, which makes its side straight and
	# its top flat. Not a taper off the drawing: what tapers there is the far edge
	# of a flat cap seen from above.
	if measured.column:
		var straight: float = float(measured.width()) * 0.5 / _voxel
		# Cast concrete has an edge and a barrel of voxels has none. One voxel
		# drawn in at the top ring and at the foot is the whole of it.
		if up == 0 or up == crown_high - 1:
			return maxf(straight - 1.0, 1.0)
		return straight
	var rows: int = measured.profile.size()
	# The profile is written top row first and the model is built from the
	# ground, so the row is read from the far end.
	var at: int = clampi(
		int(round(float(crown_high - 1 - up) * float(rows - 1) / float(maxi(crown_high - 1, 1)))),
		0, rows - 1
	)
	return measured.profile[at] / _voxel


## The drawing's colours ACROSS the side row that `_band_at` takes its band from,
## so a wrap and the band it replaces are the same row of the same drawing.
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


## The drawing's colour at a voxel row, read off the same profile row `_radius`
## reads the width off, so a band and the width it paints belong to each other.
func _band_at(measured: Measure, up: int, crown_high: int) -> Color:
	var bands: PackedColorArray = measured.bands
	# A column's side is what is under the lid. Painting the lid's rows up the
	# side as well squashes the body's own shading into the lower half of the
	# post, which is what makes it read as banded rather than as concrete.
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
	# How much of the sky the voxel can see, which is what decides its colour: the
	# column ABOVE it and how enclosed it is by the twenty-six voxels AROUND it.
	# See `_tone`. Both are counted once per voxel, since they are facts about the
	# voxel and `_tone` is asked six times for it.
	# Counted only if something is drawn, and only once for the six faces. The
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
		_quad(origin, side, _tone(measured, fill, side, sky, near, float(vx - reach)))


## The drawing's own shading rule, in three dimensions.
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
	measured: Measure, fill: int, side: Vector3i, sky: int, near: int,
	across: float
) -> Color:
	if fill == POT:
		# The pot's own drawn colour at that row, a step darker underneath, which
		# is the one thing about a turned body a band cannot say.
		if side.y >= 0:
			return _band
		return _band.darkened(0.25)
	var palette: PackedColorArray = measured.bark if fill == BARK else measured.tones
	# The crown is painted from the drawing's whole ladder, its darkest included.
	# A ROCK is painted by BAND and keeps the reading it was measured with, which
	# is that ladder without it.
	if fill == LEAF and not measured.rock and not measured.shades.is_empty():
		palette = measured.shades
	if palette.is_empty():
		return Color(0.3, 0.5, 0.25)
	# A rock is painted by band, not by exposure: see `_bands`. What is left of the
	# rule here is the one thing a band cannot say, which is that a face looking
	# down at the ground is in its own shadow.
	if measured.rock:
		# A COLUMN's top face is the CAP the drawing draws, not the band at the
		# height the cap happens to be drawn at. See `_cap`.
		if measured.column and side.y > 0:
			return measured.cap
		if measured.column and side.y == 0 and not _wrap.is_empty():
			# Where across the drawing this face stands. The barrel is as wide as
			# the row is drawn, so the two are the same measure and the artist's
			# own lit and shaded flanks land on the flanks.
			var at: int = int(round(float(_wrap.size()) * 0.5 + across * _voxel))
			return _wrap[clampi(at, 0, _wrap.size() - 1)]
		if side.y >= 0:
			return _band
		return palette[clampi(_ladder(palette, _band) + 1, 0, palette.size() - 1)]
	# A potted crown is lit from one side as well as from above. Exposure alone
	# spends the ladder on how much stands over a face, so a plant standing in the
	# open takes one green on every flank and reads flat; the cartridge paints it
	# light down one side and dark down the other, and that is the volume. Painting
	# it by BAND instead was built and thrown away: a dithered crown's commonest
	# colour per row is its OUTLINE, and the whole plant came back near-black.
	if fill == LEAF and not measured.pot.is_empty():
		return _lit(
			palette, side, sky, near, false,
			-LEAF_FLANK if side.x < 0 or side.z < 0 else LEAF_FLANK
		)
	# A shrub starts a step darker, because exposure alone reads it wrong. The
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
	palette: PackedColorArray, side: Vector3i, sky: int, near: int, dark_mass: bool,
	flank: float = 0.0
) -> Color:
	var rung: float = (1.0 if dark_mass else 0.0) + flank
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


## How hard a point bends, READ OFF THE VERTEX AND NEVER OFF THE VOXEL.
##
## One weight for a whole voxel row is what put the holes in the crown. The top
## vertices of a row sit exactly where the bottom vertices of the row above sit,
## so handing the two rows different weights SHEARS them apart in the wind: the
## crown opens along every horizontal seam and the ground, the wall and the sky
## come through a solid body. Reading the weight off the vertex's own height
## gives coincident vertices equal weights, so the whole crown deforms as one
## skin and no gap can open however hard it blows.
##
## It is the rule `mesher.gd` already learned for the tall grass, where one value
## per box slid a merged blade sideways in one piece, and it is the same fix.
func _sway_at(height: float) -> float:
	if _sway_still:
		return 0.0
	return clampf((height - _sway_foot) / _sway_span, 0.0, 1.0)


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
		_sways.push_back(Vector2(_sway_at(vertex.y), 0.0))


## The same thing as a flat drawing stood up, for the distance.
##
## A stamped model is 700 to 1200 triangles and a map wears hundreds of them, so
## models are between 81 and 92 per cent of every outdoor map's geometry. That is
## affordable for the ground the player is standing on and it is not affordable
## for the maps behind it, which is why everything past the mesh is a flat page
## today.
##
## This is the middle rung. It reads the SAME `Measure` the solid is turned from,
## so the silhouette is the drawing's own width at every row and the colours are
## the drawing's own bands, and it spends that on two crossed planes instead of a
## turned volume. Rows of equal width and colour merge into one band, so a tree
## comes out in tens of triangles rather than hundreds and still reads as that
## tree rather than as a green lolly.
##
## The wind frame is copied exactly rather than approximated: same `_sway_foot`
## and `_sway_span`, so an impostor bends with the trees around it and a stamp
## that crosses the swap does not jump.
##
## Both windings are emitted because the foliage material culls back faces and a
## plane has two sides. Giving impostors a `cull_disabled` material of their own
## would halve this again; it is a second material on the sink and not worth it
## until the rung is real.
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

	# Per voxel row: how wide the thing is there and what colour it is, which is
	# the same pair `tree` fills its solid and paints its faces from.
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


## The drawing itself stood up, which is the cheapest a thing can be and still
## be the thing.
##
## Two crossed quads, four triangles, wearing the tileset pixels cut out of the
## drawing rather than a silhouette rebuilt from its measurement. The band
## version above reconstructs the shape row by row and costs about 120 triangles;
## this is the same idea carried all the way, and it is the picture the cartridge
## actually drew.
##
## It stands exactly as tall and as wide as the SOLID of the same drawing, so a
## stamp crossing the detail ring does not change size. `cull_disabled` on the
## material is what lets one quad serve both faces.
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


## One upright quad of a cut-out drawing, wearing the whole picture.
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


## The foot of the sway, its span and the thing's whole height, which is the one
## frame the solid, the band impostor and the cut-out all have to agree on or a
## stamp changes size as it crosses the ring.
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


## One upright band of an impostor, both faces of it, in the plane whose normal
## is [param normal].
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
