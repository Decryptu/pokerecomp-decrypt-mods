extends RefCounted

## The shape PROFILE: hand-authored pins over the automatic resolution in
## `tile_shape.gd`, in the spirit of a 3dSen game profile pinning a graphic to a
## geometry type.
##
## Nothing below is extracted, derived or copied from a cartridge. An entry can
## only ever change how a tile LOOKS in this view: collision, warps, triggers
## and scripts read the same data they always did.
##
## Most of the world needs no entry. `tile_shape.gd` resolves a tile from the
## cell's own collision permission, which in Generation II is real per-cell data
## rather than a walkable-tile list. Pin a tile here when that reads the drawing
## wrong: a ledge lip that should lie low, a roof that should wear its art on
## top, a canopy that should not stand as a full 16px wall.
##
## Pins are per tileset number, because a tile id means nothing without one.
## Surveying a tileset is the procedure in `../README.md`.
##
## Two tables, and this file holds the first. `profile_pass.gd` holds the second,
## generated from a full pass over every tileset in the game, and this one wins
## wherever both name a tile.
const PASS: GDScript = preload("profile_pass.gd")

## Class heights in world pixels. A walk cell is 16x16 and a graphics tile 8x8,
## so a height is a whole number of 8px bands and everything on this list is one.
const HEIGHTS: Dictionary = {
	&"ground": 0,
	# Water recesses so a shoreline shows a lip rather than a painted seam.
	&"water": -8,
	&"void": 0,
	&"ledge": 8,
	&"wall": 16,
	&"fence": 8,
	&"sign": 16,
	&"roof": 24,
	# Masonry drawn two courses tall: a gate, a plateau rim. Same fold as
	# `wall`, twice the height, and its own class because `wall` is one cell for
	# every interior in the game.
	&"cliff": 32,
	&"counter": 8,
	&"table": 8,
	&"desk": 16,
	&"bed": 8,
	&"bookcase": 24,
	# A building is measured off its own drawing the way a volume is, so these
	# are only what a stray one falls back to: a facade stands as many bands as
	# its column has wall rows and a roof lies on top of whatever that came to.
	&"facade": 16,
	&"roof_edge": 24,
	&"roof_corner": 24,
	# A cutout carries no height of its own: how tall it stands is COUNTED off the
	# drawing, because the drawing is what the reviewer measured. A concrete
	# bollard is 15 px of art on a 16 px cell and a wooden sign is 14, and no
	# class constant would have found either.
	&"post": 0,
	&"sign_post": 0,
	&"bush": 0,
	&"sapling": 0,
	&"tombstone": 0,
	&"flowers": 0,
	&"planter": 0,
	&"statue": 0,
	&"stand": 0,
	&"lie": 0,
	&"canopy": 0,
	&"tree": 0,
	# A raised flat surface seen from above: a counter, a table top, a stool. One
	# cell, because that is what a counter is in a game built on 16px cells.
	&"surface": 16,
	# A thing standing ON furniture carries no height of its own either: how tall
	# it is comes from its own rows and where it starts comes from the table.
	&"on_furniture": 0,
	# Stairs. Flat for now, and the class exists so a pass can RECORD them: a
	# step built as a lip in the middle of a walkable path is worse than a step
	# built flat, and the ramp needs the ground on both sides of it to have a
	# height first, which is open work.
	&"stairs": 0,
	# Tall grass is FLOOR. It is walked through, not over, and what stands up in
	# it is tufts: see TUFTS below.
	&"tall_grass": 0,
}

## How thick a cutout stands, in world pixels.
##
## The only thing that separates one cutout from another. A sign is a plate on a
## stick and reads wrong at any depth; a bollard is a round post and wants enough
## to be one; a bush is nearly as deep as it is wide.
const DEPTHS: Dictionary = {
	&"post": 8,
	&"sign_post": 3,
	# Half a cell, and the reviewer's own pick between three renders of a real
	# hedge: a bush as deep as it is wide leaves a gap between rank and rank, and
	# a hedge several cells deep reads as corduroy. Shallower closes the gap
	# without making a hedge one solid mass, which was the other candidate.
	&"bush": 7,
	&"sapling": 14,
	&"tombstone": 5,
	&"flowers": 12,
	&"planter": 12,
	&"statue": 10,
	# The two the full pass falls back to when its words name no known thing:
	# something standing, and something low with an outline.
	&"stand": 8,
	&"lie": 12,
}

## The cutouts that are ROUND IN PLAN rather than flat slabs.
##
## A bollard, a bush and a tree are round things and a slab of them reads as a
## sheet of paper from above. The plan is an ellipse across each row's own run,
## and every face still wears the FRONT drawing's texel at its own column: the
## reviewer's call, and the right one, because the drawing's outline is dark and
## a naive revolve would paint the whole object its own outline colour.
const ROUND: Dictionary = {
	&"post": true,
	&"bush": true,
	&"sapling": true,
	&"flowers": true,
	&"planter": true,
	&"statue": true,
	&"stand": true,
	&"lie": true,
	&"canopy": true,
}

## The cutouts whose mask is cut from the drawing's own OUTLINE rather than from
## the colours of the ground around it.
##
## A tree canopy is the case and it is not a small one. The ball is drawn in the
## same two greens the grass beneath it is dithered from, so no set of "ground"
## indices can separate the two: include the greens and the flood eats the lit
## half of the tree, leave them out and it keeps half the lawn. What DOES bound
## the drawing is its own dark outline. `mesher.gd:_structure_mask` has the rule
## and the reference had it first.
##
## The value is HOW MANY of the darkest shades form that boundary, because that
## is a fact about the drawing and not about the rule. A tree draws a ring and
## one shade is the ring. A dense thicket draws no ring at all and wants two, the
## reference's second reading of the same rule; nothing claims that yet, and open
## work 3 says why.
const OUTLINE: Dictionary = {
	&"canopy": 1,
	&"tree": 1,
}

## The classes that lie flat AND stand a thin slab of their own drawing up.
##
## Tall grass is the one, and it is neither a floor nor an object. The cartridge
## draws the tufts from above, on the ground, and then draws them AGAIN over the
## player's feet as they walk through: the overdraw is what says the grass is
## taller than they are. A diorama has to say the same thing with geometry, so
## the floor keeps the drawing and the tufts stand up out of it, one thin slab
## per tile at that tile's own depth. The player then walks BETWEEN the two rows
## of a cell, which is what the 2D view meant.
##
## The reference learned the shape of this the hard way and the note is worth
## keeping: one TILE is one standing piece at full height. Splitting each tile
## again into its top and bottom halves and standing those at two depths cuts
## every blade in half, and a clump reads as two stubs.
const TUFTS: Dictionary = {
	&"tall_grass": true,
}

## The classes built as an AUTHORED MODEL rather than carved from the drawing.
##
## The drawing still says how big the thing is and what colour it is; what it
## does not say is the shape, because a Game Boy sprite of a tree is a portrait
## of one at a fixed angle and not a plan of one. Six ways of carving that
## silhouette were built and measured and every one came out a drum, a stack of
## plates or a black hedge. `model.gd` has the reasoning and the geometry.
const MODEL: Dictionary = {
	&"canopy": true,
	&"tree": true,
}

## How many walk cells a cutout's DRAWING covers, where it is more than one.
##
## The mask is cut over the whole drawing rather than over each cell, because a
## flood run cell by cell walks along the seam between them and stands each half
## on the floor by itself: the potted plant's leaves would sit beside the pot
## instead of on top of it. Measured off the drawing, never off a tile id: the
## reviewer counted the plant as "8 tiles, 2 horizontal and 4 vertical".
## The largest the drawing gets, in walk cells, and the placement is what says
## whether a given one is that big: the small brick flower bed and the tall one
## are drawn out of the same top and bottom tiles.
const SPANS: Dictionary = {
	&"planter": Vector2i(1, 2),
	&"flowers": Vector2i(1, 2),
	&"canopy": Vector2i(2, 2),
	# The conifer: one cell across and TWO down, which is what the routes mostly
	# draw. Measured over the 29 maps of tileset 1: 3696 tall trees, top half and
	# bottom half in exactly equal numbers, against 846 short ones drawn in a
	# single cell. The short one is the same class collapsed by its placement.
	&"tree": Vector2i(1, 2),
}

## The cutouts whose extra cells are DEPTH rather than height.
##
## Two drawings this size and they mean opposite things. The potted plant's four
## rows are leaves above a pot: it stands, as tall as the drawing. The long
## flower bed's four rows are the same bed carrying on away from the eye: it is
## no taller than the small bed beside it, only longer, so each of its cells
## stands its own two rows at its own depth. Only the mask is cut over the whole
## drawing, because a cell in the middle of the bed has no ground on its own
## border for the flood to come in through.
const LYING: Dictionary = {
	&"flowers": true,
	&"lie": true,
}

## The cutouts whose drawing is a solid body the flood cannot be trusted with.
##
## The wooden sign is the case: its board is painted the same palette index as
## the floor, so the flood walks straight through the board and leaves the
## letters standing in mid air. Filling each column between its topmost and
## bottommost drawn pixel puts the board back, and the poles under it with it.
const FILLED: Dictionary = {
	&"sign_post": true,
}

## The tiles that draw the FACE of a terrain cliff, per tileset number.
##
## Not a class and deliberately not one: a cliff face stands up and is textured
## exactly like any other wall, and what is different about it is what is BEHIND
## it. The reviewer's own words: "rock walls are two tiles high, and then its the
## higher flat floor". So the ground north of a cliff is not the ground in front
## of it a few tiles further on; it is a PLATEAU, standing on top of the wall,
## which no per-column measurement can ever reach because a column measures one
## height and a cliff is two.
##
## Every face tile of the cliff belongs here: the rim, the corners, the crest and
## the cave mouth cut into the foot of one are all one wall, and listing them all
## is what lets a column's own run of them be read as a whole. What a tile must
## NOT be listed as is the face of anything that is not terrain: a house wall has
## a floor behind it, not a plateau.
##
## `FRONTS` is the subset that faces the SCREEN, with the raised floor
## immediately above the drawing. Only a front says which side of the wall is up:
## the west rim of the same cliff carries the plateau on one side and the low
## ground on the other, and every one of those rims is in `CLIFFS` to bound and
## to be measured with, and in `FRONTS` never.
##
## Mined from the full pass's own descriptions in the survey directory, which
## name a cliff face as such and say what stands above it, and cross-read against
## the reviewer's answers for tileset 3.
const CLIFFS: Dictionary = {
	# Routes: the raised brown rock shelf, its four rims and the cave mouth in it.
	1: [76, 59, 61, 77, 43, 45, 70, 71, 86, 87],
	# The tan rock face under a raised earth terrace.
	2: [76],
	# Towns: the rock walls of Cianwood and Olivine. 55 is the upper band of the
	# face and 19 and 53 the inner corners; 36, 39, 30 and 2 are the diagonal
	# ends, where the low ground is what lies beyond the diagonal.
	3: [55, 19, 53, 36, 39, 30, 2],
	# The brown rock cliff of the mountain routes, crest, body and both ends.
	4: [44, 45, 60, 61, 75, 76, 77, 43, 59],
}
const FRONTS: Dictionary = {
	1: [76],
	2: [76],
	3: [55, 19, 53],
	4: [44],
}

## The LIP: the plateau's own far edge, drawn from above with the seam INSIDE the
## drawing rather than under it.
##
## A cliff shows its face where it faces the screen and nothing at all where it
## faces away, so the far edge of a plateau is one flat row carrying a black line
## along its top and the low ground carries on immediately above it. Nothing
## stands between the two, which is exactly the leak that matters: the flood that
## carries a plateau's height across it would run straight out over the seam and
## take half the map with it. A lip therefore ENDS a region and then takes the
## height of the region on its own south side, which is the side its drawing
## belongs to.
##
## The reviewer's tileset 3 tile 1: "the far (top) edge row of the raised stone
## platform's walkable upper surface; the black line along its top is the seam
## where the platform meets the pale ground beyond".
const LIPS: Dictionary = {
	3: [1],
}


## Which part of a BUILDING a class depicts, and how far a sloped roof tile has
## fallen from the flat section beside it, in 8px bands.
##
## A Generation II building packs several surfaces into one drawing: the bottom
## rows are the facade seen face-on, the rows above are the roof seen from above,
## and the roof's sides fall away by a band or two per column at the gable. No
## single class covers that, and a tile id is not a band: what decides a height
## is where a tile sits in the building's own grid, which `mesher.gd` measures.
## These say only which of the two surfaces a drawing is, and how far down the
## slope it sits, both of which are facts about the drawing alone.
const BUILDING: Dictionary = {
	&"facade": &"wall",
	&"roof": &"roof",
	&"roof_edge": &"roof",
	&"roof_corner": &"roof",
}
const ROOF_DROP: Dictionary = {
	&"roof_edge": 1,
	&"roof_corner": 2,
}

## How the mesher draws each class.
##
##   flat     one quad, no box. Ground, water, the void past a map edge.
##   top      a box wearing its art on the TOP face: things whose 2D drawing
##            depicts a surface seen from above, such as a ledge lip or a bed.
##   upright  a box whose south face reconstructs the 2D artwork STANDING UP,
##            8px band by band, band k sampling the map row k tiles north. That
##            is most of Generation II: interior walls, tree canopies, facades.
const ART: Dictionary = {
	&"ground": &"flat",
	&"water": &"flat",
	&"void": &"flat",
	&"ledge": &"top",
	&"roof": &"top",
	&"bed": &"top",
	&"wall": &"upright",
	&"fence": &"upright",
	&"sign": &"upright",
	&"cliff": &"upright",
	&"counter": &"upright",
	&"table": &"upright",
	&"desk": &"upright",
	&"bookcase": &"upright",
	&"facade": &"upright",
	&"on_furniture": &"upright",
	&"stairs": &"flat",
	&"tall_grass": &"flat",
	&"roof_edge": &"top",
	&"roof_corner": &"top",
	# cutout: not a box at all. The drawing's own silhouette stands up one run of
	# pixels at a time, on ground taken from the walkable cell beside it, which is
	# what a thing with a shape rather than a face wants.
	&"post": &"cutout",
	&"sign_post": &"cutout",
	&"bush": &"cutout",
	&"sapling": &"cutout",
	&"tombstone": &"cutout",
	&"flowers": &"cutout",
	&"planter": &"cutout",
	&"statue": &"cutout",
	&"stand": &"cutout",
	&"lie": &"cutout",
	# A whole tree: canopy, trunk and the shadow it stands on, drawn as one 2x2
	# cell picture. The reference carves the same thing as one 32px hull.
	&"canopy": &"cutout",
	# The other tree the game draws, and the commoner one: a CONIFER, pointed at
	# the top, one cell across and drawn either one or two cells tall.
	&"tree": &"cutout",
	&"surface": &"top",
}

## Tileset number -> class -> the tile ids that class claims.
##
## Empty until a tileset has been surveyed. An unlisted tile is resolved from
## its cell's collision permission, which is right for the great majority of
## them; a pin is for the minority where the drawing and the permission disagree.
const TILESETS: Dictionary = {
	# Towns and cities, on 39 maps. Surveyed 2026-08-10; the heights quoted are
	# the reviewer's own measurements off the drawing.
	3: {
		# The concrete bollard along a path, 15 px of art over a 1 px shadow, and
		# the wooden pole, 13 px over a shadow with two rows of floor above it.
		&"post": [42, 43, 58, 59, 14, 85],
		# The wooden route sign: 14 px with a row of floor top and bottom.
		&"sign_post": [70, 71, 86, 87],
		# A cell each, and both about as tall as the player.
		&"bush": [64, 65, 80, 81],
		&"sapling": [45, 46, 61, 62],
		# Ground the detector was standing up because its cell is blocked by
		# what stands NEXT to it: grass under a ledge lip, and the stone floor
		# of a plateau.
		&"ground": [17, 44, 57],
		&"tall_grass": [82],
		# A lip drawn from above, lying low. Where the collision says a lip can be
		# HOPPED, `mesher.gd:_measure_ledges` overrides this with a wedge; the pin
		# is what the rest of them keep.
		&"ledge": [52, 54],
		# The house facade, face-on: brick, plain and plank walls, the shadow row
		# under them, both wall edges and both bottom corners, the windows, the
		# four tiles of a door, and the lettering and boards that are painted
		# straight onto the wall.
		&"facade": [
			10, 11, 12, 15, 26, 27, 28, 29, 31, 34, 35, 47, 50, 60, 63,
			66, 67, 68, 69, 74, 75,
		],
		# The roof seen from above, flat section: the middle, all four corners
		# and every straight edge.
		&"roof": [7, 18, 23, 76, 77, 78, 83, 90, 92, 93, 94, 95],
		# The gable: one band down beside the flat section, two at the corner of
		# the house. 56 is drawn for both sides and only its neighbours could say
		# which, so it takes the shallower fall.
		&"roof_edge": [6, 8, 22, 24, 38, 40, 56],
		&"roof_corner": [5, 9, 21, 25, 37, 41],
	},
	# Pokemon Centers, shops and houses, on 57 maps.
	5: {
		&"table": [5, 21, 38, 39, 41, 47, 50, 51, 54, 57, 58, 59, 60],
		# Three tiles tall, which is what `bookcase` already is.
		&"bookcase": [14, 15, 48, 49],
		&"tombstone": [40, 55, 56, 63, 78],
		# The small brick flower bed, one cell square. The tall one is four
		# tiles high and needs a cutout that spans two cells, which is open work.
		# The brick flower bed, in both sizes: the same top and bottom tiles, with
		# the tall one's two middle rows between them.
		&"flowers": [42, 43, 94, 95, 84, 85],
		# The potted plant, eight tiles: two wide and four tall, leaves over pot.
		&"planter": [8, 9, 10, 11, 24, 25, 26, 27],
	},
	# TALL GRASS, pinned from the full pass's own words. Which CELLS are tall
	# grass is the cartridge's to say and it says it in the collision byte, but
	# the host offers no accessor for those four codes yet: see the engine
	# request. Until it does, the tiles are named from their drawings, which is
	# what the profile is for anyway.
	1: {
		&"tall_grass": [4],
		# THE CONIFER, and tileset 1 is 29 maps: more of the game's outdoors than
		# any other. Six tiles, drawn as a pointed top over an optional middle over
		# a foot, and the middle is what makes a tall one: 3696 cells carry
		# [30,31,46,47] and exactly 3696 carry [46,47,62,63], so every tall tree is
		# a matched pair, while 846 cells draw [30,31,62,63] on its own and are the
		# short one. `SPANS` declares the tall one and the placement collapses it.
		&"tree": [30, 31, 46, 47, 62, 63],
	},
	2: {
		&"tall_grass": [4],
	},
	17: {
		&"tall_grass": [87],
	},
	# THE BIG TREE, and it is one whole block: four tiles by four, canopy, trunk
	# and the shadow ellipse it stands in, described tile by tile in the full
	# pass and standing as one plain box before this.
	#
	# Tileset 31 draws the same tree at the same sixteen ids, and once the mask is
	# cut on the drawing's own outline the two profiles agree to the decimal. It
	# was held back while the tree was CARVED, because a crown filling its block
	# edge to edge revolves into a drum and a dither's row jitter turns that into a
	# stack of plates; turning a model off the same silhouette has neither fault.
	31: {
		&"canopy": [
			12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63,
		],
	},
	25: {
		&"canopy": [
			12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63,
		],
	},
}


## The class a tile is pinned to, or an empty StringName when it is not pinned.
##
## The hand table above first, then the full pass in `profile_pass.gd`. The order
## is the point: the table above was authored from the reviewer's own
## measurements off the drawing, and the pass is a machine reading the same
## pictures, so where they disagree the person is right and the pass can be
## regenerated under them.
static func pinned_class(tileset_number: int, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset_number, null)
	if groups is Dictionary:
		for shape_class: StringName in (groups as Dictionary):
			var tiles: Variant = (groups as Dictionary)[shape_class]
			# A plain Array, because a PackedInt32Array literal is not a constant
			# expression and this whole table has to be one.
			if tiles is Array and (tiles as Array).has(tile):
				return shape_class
	return PASS.pinned_class(tileset_number, tile)


## Whether a tile draws the face of a terrain cliff, which is what says the
## ground behind it stands on top of it.
static func is_cliff(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = CLIFFS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


## Whether that face is the FRONT of the cliff, the one with the raised floor
## drawn immediately above it.
static func is_cliff_front(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = FRONTS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


## Whether the tile is the plateau's far edge, which ends a plateau and stands at
## the height of what is south of it.
static func is_cliff_lip(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = LIPS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


static func height_of(shape_class: StringName) -> int:
	return int(HEIGHTS.get(shape_class, 0))


static func art_of(shape_class: StringName) -> StringName:
	return StringName(ART.get(shape_class, &"flat"))


static func depth_of(shape_class: StringName) -> int:
	return int(DEPTHS.get(shape_class, 4))
