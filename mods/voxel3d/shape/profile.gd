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
	&"notice_case": 0,
	&"bush": 0,
	&"sapling": 0,
	&"tombstone": 0,
	&"flowers": 0,
	&"planter": 0,
	&"statue": 0,
	# A STATUE ON A PILLAR carries no height of its own either: how tall it stands
	# is counted off its own drawing, which is two cells of it.
	&"statue_pillar": 0,
	&"stand": 0,
	&"lie": 0,
	# A STOOL is a turned model and counts its own height off its own drawing,
	# exactly as a boulder does.
	&"stool": 0,
	&"canopy": 0,
	&"tree": 0,
	&"boulder": 0,
	# A RAILING stands half a cell, which is the reviewer's own answer: a fence
	# with posts and a rail you see over. Its drawing is a line seen from above
	# and states no height at all, so this is the whole of what says how tall.
	&"railing": 8,
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
	# A glazed notice case is a board in a frame on two posts, so it is the wooden
	# route sign's shape at the park's own scale and takes the sign's depth.
	&"notice_case": 3,
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
	# A STATUE ON A PILLAR STANDS ON A WHOLE CELL, which is the reviewer's own
	# measurement of it: "in a 3D world the statue would be 1 cell on the ground
	# and 2 cell high". It is round, so each row's own drawn run is its diameter
	# and this only says the cap is the cell rather than two thirds of it.
	&"statue_pillar": 16,
	# The two the full pass falls back to when its words name no known thing:
	# something standing, and something low with an outline.
	&"stand": 8,
	&"lie": 12,
	# A boulder is a turned model and carves nothing; this is only what one falls
	# back to, and a rock is as deep as it is wide.
	&"boulder": 16,
	# A stool is round in plan and its drawing is one walk cell, so it is as deep
	# as it is wide. Only the fallback: it is turned.
	&"stool": 16,
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
	&"statue_pillar": true,
	&"stand": true,
	&"lie": true,
	&"canopy": true,
	&"boulder": true,
	&"stool": true,
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
## one shade is the ring. A drawing that only rings its top and opens at the foot
## wants two, the reference's second reading of the same rule: see
## `notice_case` below, which is the first thing to claim it.
##
## A CARVED CLASS TAKES THIS RULE EXACTLY AS A MODELLED ONE DOES. Every class
## here was a model until the National Park's notice cabinet, and the note that
## said a carved class cut on its outline draws nothing was measured and is
## wrong: `mesher.gd:_cutout` carves an outline-cut mask like any other.
const OUTLINE: Dictionary = {
	&"canopy": 1,
	&"tree": 1,
	&"bush": 1,
	# THE CUT TREE IS DRAWN AS A DITHER and it is the reason this pin matters
	# here: its crown is a checkerboard of its own dark shades against the grass's
	# own two, so the ground rule keeps every other pixel and drops the rest. It
	# is ringed in the darkest shade like every other plant.
	&"sapling": 1,
	# A rock standing in the sea is drawn in the water's own blues and a rock on a
	# cave floor in the floor's own golds, so the ground rule has nothing to cut
	# on. Every one of them is drawn inside a dark ring.
	&"boulder": 1,
	# A BOLLARD'S TOP FACE IS DRAWN IN THE PAVING'S OWN INDEX, which is what put
	# the holes in it: the cap is index 0 and so is the pavement it stands on, so
	# the ground rule cut the middle out of every one of them and left a ring. The
	# dark ring the cartridge draws round it closes on one shade.
	&"post": 1,
	# A stool stands on a carpet or on floorboards drawn in its own shades, and it
	# is drawn inside a dark ring like everything else indoors.
	&"stool": 1,
	# THE NATIONAL PARK'S NOTICE CABINET, and it wants TWO. Its frame is the
	# darkest shade and closes round the top and the sides, but its lower panel is
	# drawn in the middle shade and meets the ground in it, so one shade lets the
	# flood up through the foot and out again: 148 pixels come back with a two-row
	# slot cut clean through the case. The second shade closes that foot, and the
	# whole cabinet stands at 222.
	&"notice_case": 2,
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
	&"bush": true,
	# THE CUT TREE, which is a small tree drawn as its own silhouette and is
	# therefore a portrait of a symmetric thing, the third row of the pipeline
	# table. Carved it was the worst thing on the tileset: a dithered crown cut
	# per pixel run is a lattice of separated columns with the paving, the wall
	# and the sky all visible straight through it.
	&"sapling": true,
	&"boulder": true,
	&"stool": true,
	# THE CONCRETE BOLLARD, which the carved path revolved per row into a ribbed
	# drum with the paving showing THROUGH it. See `COLUMN` for the shape and
	# `OUTLINE` for the holes.
	&"post": true,
}

## The modelled classes that sit ON THE GROUND rather than standing on a trunk.
##
## A tree's sprite is foreshortened and its trunk is drawn behind its crown, so
## the model stretches it and stands it up. A bush is neither: the reviewer
## measured it as about as tall as the player and that is what it is drawn as.
## Reading one as a tree makes a small tree, which is exactly what it looked
## like. See `model.gd:Measure.shrub`.
const SHRUB: Dictionary = {
	&"bush": true,
	&"boulder": true,
	&"stool": true,
	&"post": true,
}

## The modelled classes that are STONE rather than growing.
##
## A rock sits on the ground exactly as a shrub does and is read the same way up,
## so `SHRUB` covers its shape. What it is not is alive: it is barely ragged, it
## does not bend in the wind, and it is not the dark mass a hedge is. See
## `model.gd:Measure.rock`.
## HOW TALL A MODELLED THING STANDS against how tall it is DRAWN.
##
## The drawing states a width honestly and a height not at all, and everything
## turned so far has been able to take its own drawn height because it is drawn
## standing: a bush, a rock, a tree once its foreshortening is undone. A round
## STOOL is not. Its top half is the seat seen from ABOVE, which is depth on the
## page and no height at all, so read literally a knee-high seat stands a full
## walk cell and comes out a barrel.
##
## Nothing but a person can settle the number, which is what the reviewer already
## did twice for carved things: the long flower bed is no taller than the short
## one, and the school chair's twelve drawn rows are six. 0.6 of sixteen drawn
## rows is ten world pixels, between that chair and the player's own height,
## which is where the pass put it: "waist high", "a knee-high seat".
##
## Unlisted takes the class's own default, 1.3 for a tree and 1.0 for anything
## sitting on the ground. See `model.gd:Measure.stretch`.
##
## IT IS READ ON THE CARVED PATH TOO, through `mesher.gd:_carve_y`, so the table
## means the same thing whichever way a drawing is built. Nothing carved claims
## it: the potted plant was the candidate and the reviewer measured it at its own
## drawn 32 px in round twenty-four.
const STRETCH: Dictionary = {
	&"stool": 0.6,
	# A CUT TREE IS NOT FORESHORTENED, which is the whole reason it takes a number
	# here. `tree`'s own 1.3 corrects a sprite that draws its trunk BEHIND its
	# crown and so states no height at all; this drawing states all of it, a
	# ragged crown over four rows of bare stem over a flared foot, and stretching
	# that stands a full-sized tree where the cartridge draws a waist-high one.
	# Read at 1.0 it is 15 px across and 16 tall, which is its own drawing.
	&"sapling": 1.0,
	# A BOLLARD IS DRAWN TALLER THAN IT STANDS, for the reason this table exists:
	# seven of its fourteen drawn rows are the LID seen from above, which is depth
	# on the page and no height at all, so read literally it comes out a drum
	# nearly as tall as the player. The reviewer measured it at 9 or 10 world
	# pixels in round twenty-nine and 0.71 of fourteen rows is ten. FIFTH time a
	# drawing being tall on screen has had to be separated from a thing being tall
	# in the world.
	&"post": 0.71,
}

const ROCK: Dictionary = {
	&"boulder": true,
	# A STOOL IS FURNITURE AND READS THE SAME WAY A STONE DOES, which is the whole
	# reason it takes this and not the plant's reading. It is small, so one world
	# pixel per voxel rather than the tree's two, or a 16px seat comes out six
	# voxels across and is a pillow. It does not sway. And its colour is BY BAND:
	# a stool is drawn pale on the seat where the light falls and dark down the
	# pedestal, which is a horizontal rule and not an exposure one, and exposure
	# would take the lightest tone for every face of a thing nothing stands over.
	&"stool": true,
	# A CONCRETE BOLLARD is stone by every one of those readings.
	&"post": true,
}


## The modelled classes that are a straight COLUMN rather than a turned
## silhouette: the same radius all the way up, and a FLAT top.
##
## A turn is right for anything drawn as a portrait of a rounded body, which is
## most of what this pipeline builds. A bollard is not one. The reviewer's own
## words for it in round twenty-seven: "they are not like a ball, they are a
## standing cylinder, so the upper part is flat, it is not rounded". The drawing
## agrees and says why the turn cannot know: what a bollard's sprite draws is its
## flat top seen from ABOVE with its side below, so the rows that taper are the
## far edge of the cap rather than a body narrowing, and a revolve reads that
## taper as a dome.
##
## The widest row is the radius, the drawn height is the height, and `model.gd`
## does the rest. Colour comes from `ROCK`'s own band reading, which is what puts
## the light on top and the dark at the foot, since that is where the drawing
## puts them.
const COLUMN: Dictionary = {
	&"post": true,
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
	# A STATUE ON A PILLAR, and the reviewer's words are the whole specification:
	# "the bottom cell is the pillar base, and the upper one is the statue laying
	# above it. since pokemon 2D world is seen slightly from above, they are both
	# taking 2 cells vertically and 1 horizontally. in a 3D world the statue would
	# be 1 cell on the ground and 2 cell high".
	#
	# So the extra cell is HEIGHT and not depth, which is the potted plant's case
	# and not the long flower bed's, and it is why this is not in LYING. Without
	# it each cell was cut and revolved on its own and every one of these stood as
	# two drums stacked, a lump above a pillar with a seam between them.
	#
	# ITS OWN CLASS RATHER THAN `statue`, and that is the whole reason there are
	# two. The full pass named seven tilesets `statue`, all seven drawn one cell
	# over one cell, and moving the class moved all of them: tileset 26's came out
	# a chewed banded column, plainly worse than the flat pieces it replaced, so
	# whatever that drawing is it is not this. A span is a fact about a DRAWING and
	# a class is how the profile addresses one, so the drawings a person has
	# actually read get their own.
	&"statue_pillar": Vector2i(1, 2),
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
	# A BOULDER'S RING IS NOT CLOSED. A tree draws a ring of its darkest shade all
	# the way round and the flood stops at it; a rock is drawn against water or
	# against a cave floor of its own palette and its outline has gaps in it, so
	# the flood walks in and eats the stone, leaving the outline dots and the
	# interior stipple standing on their own. That reads as a crenellated lump and
	# it starves the colour: the tones are read off the mask, and a mask of nothing
	# but shading came back with ONE tone for the sea rock. Filling each column
	# between its topmost and bottommost drawn pixel puts the stone back.
	&"boulder": true,
	# A STOOL'S SEAT IS RINGED AND ITS LEGS ARE NOT. Printed as text, tileset 19's
	# is a closed ring of the darkest shade round the cushion and then splayed legs
	# with the floor showing between them and reaching the drawing's own bottom
	# edge, so the flood walks straight up through the legs and leaves the seat
	# standing on scraps. Filling each column puts a pedestal under it, which is
	# also the only thing a revolve can make of splayed legs. Measured both ways
	# and the two pictures are the same, because the seat is what the profile is
	# read off and the legs reach as wide as it does; kept because it is the safer
	# reading of an open ring and it costs nothing here.
	&"stool": true,
}

## THE OBJECTS, per tileset number. A thing that is not a tile and does not fit
## the grid.
##
## Everything else here resolves a tile and stands it up where that tile sits. A
## wall or a canopy is drawn tile by tile and comes out right that way. A CHAIR is
## not: it is drawn as four corners across four tiles, straddling the seam between
## them, and tileset 13's tile 74 is the desk's bottom-left leg, the chair's
## top-left corner and the floor between the two at once. No pin can be right
## about that tile, because the tile is three things.
##
## So an object is declared by the ARRANGEMENT OF TILE IDS it is drawn out of,
## which is what identifies it wherever the map places it, and `mesher.gd`
## `_measure_objects` finds every occurrence, gives every tile it covers back to
## the FLOOR, and stands one thing of the declared size at the drawing's own
## position. Two objects may claim the same tile and both are drawn: the desk and
## the chair below it do.
##
## Each declaration says:
##
##   tiles   the arrangement, row by row, -1 for a tile it covers but does not
##           care about
##   window  where in that arrangement the thing is actually drawn, in pixels.
##           Authored because the arrangement's own rectangle holds the
##           neighbours as well: the chair's four tiles hold the desk's bottom
##           edge along their top.
##   top     how many rows of the window are the surface seen FROM ABOVE. The
##           rest are the face seen face-on. This is the same split
##           `_measure_buildings` makes at building scale, and it is the whole of
##           what a 2.5D drawing is: a top and a front, stacked.
##   depth   how far it reaches away from the eye, in world pixels
##   height  how tall it stands
##
## DEPTH AND HEIGHT ARE THE DRAWING'S OWN ROW COUNTS wherever it draws a top: the
## desk's top band is 16 rows and the reviewer measured the desk at 15 or 16 deep,
## its face is 6 rows and they measured 6 or 7 high. Where a drawing has no top
## band at all the depth is not in the picture and is authored: their number for
## the chair is 6.
##
## A -1 in the arrangement is a tile the object covers and has no opinion about.
## OUTSIDE is the other thing a rectangle can hold and the SHIP needed it: a
## bounding box round something that is not rectangular holds tiles that are not
## the object at all, and giving open sea back to the floor puts a still slab in
## the middle of a harbour. An OUTSIDE tile is matched against nothing, is not
## covered, and keeps whatever it already was. It is still part of the rectangle
## the MASK is cut over, which is the whole reason to name it rather than shrink
## the box: see the ship.
const OUTSIDE: int = -2

const OBJECTS: Dictionary = {
	13: [
		# The school desk, and the thing that made this whole item: 32 wide, drawn as
		# a top seen from above with books and a globe on it, then a front with an
		# apron and legs. Its bottom row of tiles is shared with the chair.
		{
			&"name": &"desk",
			&"tiles": [[42, 43, 44, 45], [58, 59, 60, 61], [74, 75, 76, 77]],
			&"window": Rect2i(0, 0, 32, 22),
			&"top": 16,
			&"depth": 16,
			&"height": 6,
		},
		# The chair, 12 px square in the middle of four tiles, drawn face-on with a
		# back: no rows of it are seen from above, so its depth and its height are
		# both the reviewer's, 6 and 6.
		#
		# THE DRAWING IS NOT TAKEN AT ITS WORD HERE and that is round eleven's
		# answer. Its twelve rows were stood up as twelve pixels first, which is a
		# chair with a back and reads as a cabinet beside a desk half its height.
		# Three builds went in front of the reviewer and they took their own numbers
		# for both: a drawing being tall on screen is not a thing being tall in the
		# world, which is the correction they made once before, about the flower
		# bed. What a face-on drawing states honestly is its WIDTH.
		{
			&"name": &"chair",
			&"tiles": [[74, 75], [90, 91]],
			&"window": Rect2i(4, 4, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	9: [
		# THE SHIP, and it is the largest thing in the game: fifteen tiles by six,
		# moored at the foot of the pier on both port maps and drawn the same way on
		# each. The reviewer's own answer named this machinery before it existed:
		# "flag every single part of the boat to have its global size, and just make
		# a voxel model directly where those tiles are".
		#
		# ITS BOX IS A TILE OF OPEN WATER WIDER THAN ITSELF ON EVERY SIDE, and that
		# margin is the object. A mask is cut by flooding in from the border, and the
		# border of the hull's own rectangle is half hull: the flood read three of
		# the four palette indices as sea and ate the ship. Ringed in water the ring
		# is 91% one index, the flood stops at the paint and the mask is the ship.
		# The margin tiles are OUTSIDE, so the sea is not handed to the floor.
		#
		# The window is the drawing and the arrangement is the rectangle it was cut
		# from: 120 px by 48, starting a tile in and a tile down. Its top forty rows
		# are the decks seen from above, laid across forty pixels of water; the last
		# eight are the hull, standing eight above the waterline. Both are the
		# drawing's own row counts, which is the rule wherever a drawing has a top
		# band at all.
		{
			&"name": &"ship",
			&"tiles": [
				[-2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2],
				[-2, -2, -2, -2, -2, -2, -2, 36, 37, 38, 39, 40, 41, 42, -2, -2, -2],
				[-2, 43, 44, 45, 45, 46, 47, 48, 50, 51, 52, 53, 16, 54, 55, 56, -2],
				[-2, 57, 58, 58, 51, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, -2],
				[-2, 43, 44, 45, 51, 70, 71, 72, 73, 73, 74, 75, 76, 77, 78, 79, -2],
				[-2, 57, 58, 80, 81, 82, 82, 83, 83, 84, 44, 45, 85, 86, 87, -2, -2],
				[-2, -2, 88, 89, 90, 90, 91, 92, 92, 93, 94, 94, 94, 95, -2, -2, -2],
				[-2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2],
			],
			&"window": Rect2i(8, 8, 120, 48),
			&"top": 40,
			&"depth": 40,
			&"height": 8,
		},
	],
	14: [
		# THE SAME CHAIR AGAIN, on a tileset that draws it 12 by 11 filling a whole
		# walk cell rather than straddling four tiles, and lays it out in a
		# chequerboard with the floor. It shares no tile with anything, so what it
		# gains here is not the finding but the SIZE: carved as a silhouette it stood
		# its full drawn height on the class's own depth and read as a bar stool, and
		# it is the chair the reviewer already settled at 6 by 6.
		{
			&"name": &"chair",
			&"tiles": [[10, 11], [26, 27]],
			&"window": Rect2i(2, 3, 12, 11),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	24: [
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[42, 43], [58, 59]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	11: [
		# THE THIRD CHAIR, and the numbers are the reviewer's own from round eleven
		# rather than a new question: a chair drawn 12 px square over four tiles,
		# face-on, with a backrest and no top band at all. Tileset 13 draws the same
		# thing at the same size and they measured it 6 deep and 6 high, over its
		# twelve drawn rows, because a drawing being tall on screen is not a thing
		# being tall in the world.
		#
		# The pass named all four tiles `sure`: "the top-left quarter of a small
		# wooden chair drawn as its own outline", "the left of the seat, the
		# cross-rails and the left legs". Printed as text the drawing sits at x2..13
		# and y2..13 with two clear rows of floor above and below it, so the mask
		# cuts cleanly on the outline and needs no filling.
		{
			&"name": &"chair",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	8: [
		# THE SAME CHAIR A FOURTH TIME, drawn 12 px square over a whole walk cell on
		# the chequered floor of the Goldenrod flower shop and two houses. Its four
		# tiles are its own and the block places it against floor tile 1 on every
		# side, so nothing here is new but the ids: it takes the 6 and 6 the reviewer
		# measured in round eleven, as tilesets 11, 13 and 14 do.
		{
			&"name": &"chair",
			&"tiles": [[84, 85], [86, 87]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	10: [
		# AND A FIFTH, under the desks of the Goldenrod radio studio, drawn a row
		# lower in its cell than tileset 8 draws it. The desk above it is already a
		# counter and stands correctly; only the chair fell to `stand` and was
		# revolved into a drum.
		{
			&"name": &"chair",
			&"tiles": [[64, 65], [80, 81]],
			&"window": Rect2i(2, 3, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	17: [
		# THE MAGNET TRAIN TICKET GATE, two of them side by side at the head of the
		# stairs with the walkway between, and the largest thing left in the `stand`
		# fallback that is one drawing rather than a tail. Revolved, each was a drum
		# in a doorway.
		#
		# One cell wide and two deep: a cream body running 24 rows AWAY from the eye,
		# which is the gate seen from above, and a dark chunk of 8 rows at its near
		# end, which is its face. So the depth is the drawing's own 24 and the height
		# is its own 8, the rule the desk, the stone vessel and the ship all took;
		# the reviewer confirmed the 8 in round twenty-two against 12 and 16.
		#
		# The window is the whole rectangle: the gate's dark side rails run to the
		# tile edge over its middle rows, so there is no margin to crop to. The flood
		# still cuts it, because those rails ARE the outline it stops at and the rest
		# of the border is the station's plain grey floor.
		{
			&"name": &"ticket_gate",
			&"tiles": [[53, 54], [55, 56], [57, 58], [59, 60]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 24,
			&"depth": 24,
			&"height": 8,
		},
	],
	26: [
		# THE STONE VESSEL, and it needs no person at all: it draws a TOP BAND, so
		# the band's own row count IS the depth and the rows below it are the face.
		# The pass read all four tiles `sure` and split them for us: 80 and 81 are
		# "the ridged lid seen from slightly ABOVE with the ridges reading as the
		# top surface", 82 and 83 "its boxy base, whose dark rectangular panel is
		# drawn FACE-ON". Eight rows each, so eight deep and eight high, over a
		# whole cell of width. Squat, which is the pass's own word for it.
		#
		# FILLED, and printing the mask is what said so. This drawing fills its cell
		# edge to edge in the same golds the brick floor is dithered from, so the
		# border the flood comes in from IS the vessel: it walks in through the
		# ridges and eats the body, which is the boulder's case and the ship's.
		# Filling each column between its topmost and bottommost drawn pixel puts
		# the box back, and the box is what the thing is.
		{
			&"name": &"vessel",
			&"tiles": [[80, 81], [82, 83]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 8,
			&"depth": 8,
			&"height": 8,
			&"filled": true,
		},
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[38, 39], [40, 41]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	23: [
		# THE RIDGE ALONG THE GREAT ROOF, and the declaration IS the reviewer's own
		# rule for telling it from the wooden bridge drawn out of the same tile:
		# "the one on the roof has a mirrored tile on its right, while the wooden
		# floor never has this mirrored tile next to it". An object is found by its
		# ARRANGEMENT, so [80, 81] is that sentence written down, and it matches on
		# the roof and nowhere else in the game.
		#
		# Unpinned and left to the collision the crest came out 48 px of wall down
		# the middle of the roof, because the run of it is four tiles deep and the
		# column measurement reads that as three walk cells. It is not a wall: it is
		# "an upper small thing on the roof", so it stands one band, and its eight
		# rows are all seen from ABOVE, which makes the band's own row count the
		# depth exactly as it does for every other object drawn with a top.
		{
			&"name": &"ridge",
			&"tiles": [[80, 81]],
			&"window": Rect2i(0, 0, 16, 8),
			&"top": 8,
			&"depth": 8,
			&"height": 8,
		},
	],
	25: [
		# THE NATIONAL PARK'S TIERED FOUNTAIN, and it is the first object that is
		# TURNED rather than stood up. A round stone basin in three tiers with a
		# spout on top, drawn as its own silhouette on the paving, four placements
		# on three maps.
		#
		# NO PIN CAN REACH IT AND THAT IS THE POINT. The drawing is 18 px wide
		# across THREE tiles and centred on the seam between two of them, so it
		# fits neither a cell nor a `SPANS` box, whose start is grid-aligned at
		# `tx - posmod(tx, across.x)`. An arrangement of tile ids is not tied to
		# the grid at all and finds it wherever the map puts it. The tiles either
		# side of the drawing are paving and are part of the rectangle the mask is
		# cut over, which is what the WINDOW is for: it keeps them out of the
		# profile the turn is read from without shrinking the box the flood needs.
		#
		# TWO SHADES OF OUTLINE, the park's cabinet having established the reading
		# on the same paving: cut on one shade the basin comes back as its own tier
		# lines and 92 loose pixels, which turns into a stack of rings with holes
		# between them. On two it is the solid 230-pixel silhouette a revolve wants.
		#
		# HOW TALL IT STANDS is the one authored number, as it is for every turned
		# thing whose drawing is partly seen from above: three quarters of the
		# sixteen rows it is drawn. `depth` says nothing about a turned body, which
		# is as deep as it is wide, so it is not declared.
		{
			&"name": &"fountain",
			&"tiles": [[76, 77, 78], [92, 93, 94]],
			&"window": Rect2i(3, 0, 18, 16),
			&"height": 12,
			&"model": true,
			&"outline": 2,
		},
	],
	29: [
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[10, 11], [26, 27]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	30: [
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
		# A LADDER STANDING ON THE GROUND, which is the reviewer's other kind: "a
		# ladder going upstair, its placed on the ground". A portrait seen face-on
		# with no rows above it at all, so it is the chair's own case with nothing
		# but the numbers changed: one cell tall because that is what it has to be
		# to climb, and three pixels thick because a ladder is two rails.
		{
			&"name": &"ladder",
			&"tiles": [[42, 43], [58, 59]],
			&"window": Rect2i(2, 0, 14, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	18: [
		# A PARKED BICYCLE, and it is the flattest thing in the game: "side view
		# drawn FACE-ON as its own silhouette, about 3 tiles wide and 2 tall", four
		# of them along the bike shop wall. Revolved by the fallback each of its
		# seven tiles became a drum, so a bicycle read as a row of bollards.
		#
		# It is the ladder's case: a portrait with no top band, so its height is what
		# it takes to be one and its depth is what two wheels are. The fourth tile of
		# the top row is the reviewer's own "just floor with a small bicycle wheel
		# visible because of perspective", so the box covers it and the object says
		# nothing about it.
		{
			&"name": &"bicycle",
			&"tiles": [[12, 13, 14, -1], [28, 29, 30, 31]],
			&"window": Rect2i(0, 0, 32, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	22: [
		# A LOW PADDED SEAT, 2x2 tiles, standing in rows on the carpet of the big
		# room, and the drawing states both its numbers itself: "its top surface
		# drawn from ABOVE and its sides folded in", ten rows of top over six of
		# face, which is the split every object with a top band is read by.
		{
			&"name": &"seat",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 10,
			&"depth": 10,
			&"height": 6,
		},
	],
	6: [
		# A TELEVISION STANDING FREE IN THE ROOM, "2 tiles wide and 2 tall, waist
		# high", drawn FACE-ON as a casing with a blue screen in it. Revolved it was
		# a drum with the screen smeared round it.
		#
		# It FILLS its cell edge to edge in the casing's own dark shade, so there is
		# no ground inside the drawing for the flood to cut against and the mask is
		# taken whole. What a face-on drawing states honestly is its width, so the
		# two numbers a person owns are here: waist high is 12, and a Game Boy era
		# television is nearly as deep as it is wide.
		{
			&"name": &"television",
			&"tiles": [[6, 7], [22, 23]],
			&"window": Rect2i(0, 0, 16, 16),
			&"filled": true,
			&"top": 0,
			&"depth": 12,
			&"height": 12,
		},
	],
}

## THE STAIRCASES, per tileset number, found the same way an object is.
##
## A flight is FOUR TILES and a perspective drawing of one, which is the
## reviewer's own answer: a 2x2 tile box, four steps on a 45 degree ramp, going
## either up or down. Measured over the whole game: 288 flights, 272 of them a
## single walk cell, drawn out of 54 distinct arrangements over 22 tilesets.
##
## THEY DO NOT CHANGE LEVEL. Every one of the 288 has the same ground on both
## sides of it, because these are WARP staircases: you step on one and leave the
## floor entirely. So a ramp between two levels is not what is being built here
## and open work 2 has the measurement that says so. What is built is the flight
## itself, as the drawing shows it.
##
## `step` is the direction it DESCENDS in the world plane, or climbs where `down`
## is false, and it is the one thing a person has to say: the reviewer read
## tileset 7's as going "from right to left to go underground", which is west.
##
## `corner` REPLACES `step` for a landing where two runs meet, and names both
## climb directions at once: (1, -1) climbs east and north, which is a raised
## platform's bottom-left corner. A tread there is an L wrapping the corner
## rather than a strip across a cell, and `mesher.gd:_emit_stair_corner` has the
## one line the whole shape falls out of.
const STAIRS: Dictionary = {
	5: [
		{
			&"tiles": [[76, 77], [92, 93]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	6: [
		{
			&"tiles": [[76, 77], [92, 93]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
		{
			&"tiles": [[78, 79], [94, 95]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	7: [
		{
			&"tiles": [[66, 67], [82, 83]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	8: [
		{
			&"tiles": [[88, 89], [90, 91]],
			&"down": true,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[80, 81], [82, 83]],
			&"down": false,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	9: [
		{
			&"tiles": [[3, 4], [30, 31]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	11: [
		{
			&"tiles": [[16, 17], [32, 33]],
			&"down": false,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[48, 49], [24, 25]],
			&"down": true,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[50, 51], [67, 68]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	13: [
		{
			&"tiles": [[10, 11], [26, 27]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
		{
			&"tiles": [[8, 9], [24, 25]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 3,
		},
		{
			&"tiles": [[163, 164], [179, 180]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	15: [
		# THE GRAND STAIRCASE, and the only flight in the game that is not one walk
		# cell. Four tiles by four, a banister down each edge and the treads
		# between them, and the reviewer counted what it does: four steps in each
		# half, so eight over the whole of it, climbing TWO levels rather than one.
		# The tread stays four pixels, which is what keeps every flight in the game
		# at the same 45 degrees whatever its length.
		{
			&"tiles": [
				[83, 84, 89, 83], [83, 84, 89, 83], [83, 84, 89, 83], [83, 84, 89, 83],
			],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 8,
			&"rise": 32,
		},
		{
			&"tiles": [[64, 65], [66, 67]],
			&"down": true,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[44, 45], [60, 61]],
			&"down": false,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	16: [
		{
			&"tiles": [[76, 77], [92, 93]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	18: [
		# THE LEAGUE'S PLATFORM, and the only staircase in the game that is a real
		# level change rather than a warp. Three runs round the edge of a floor that
		# stands one level up, and they can only be built because that floor is
		# PAINTED: see `shape/levels.gd` and open work 5. Built without it they
		# would be step-blocks standing in a floor that is flat only because nothing
		# had told the mesh otherwise.
		# Five steps, which is the reviewer's own count, over the same 16 pixels
		# every other flight climbs.
		{
			&"tiles": [[136, 137], [136, 137]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 5,
		},
		{
			&"tiles": [[139, 140], [139, 140]],
			&"down": false,
			&"step": Vector2i(-1, 0),
			&"steps": 5,
		},
		{
			&"tiles": [[148, 148], [147, 147]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 5,
		},
		# THE SOUTH SKIRT either side of the carpet, which is the same five steps
		# the carpet climbs, drawn on the same dais and running between the carpet
		# and each corner landing. Folded onto a one-level wall it read as steps
		# from most angles and as a painted stripe from above.
		{
			&"tiles": [[145, 145], [142, 142]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 5,
		},
		# THE TWO CORNER LANDINGS, where the west and east runs meet the south
		# skirt, and the only flight in the game that TURNS. The reviewer read both
		# and their words are the specification: "both horizontal and vertical steps
		# are meeting, so to go up you walk from bottom left to top right", and the
		# same for the bottom right the other way about.
		#
		# A key of tileset and tile is NOT unique here: 136 is the first tile of the
		# west run as well, and only the whole arrangement tells the two apart.
		# THE SOUTH SKIRT either side of the carpet, which is the same five steps
		# the carpet climbs, drawn on the same dais and running between the carpet
		# and each corner landing. Folded onto a one-level wall it read as steps
		# from most angles and as a painted stripe from above.
		{
			&"tiles": [[136, 144], [141, 142]],
			&"down": false,
			&"corner": Vector2i(1, -1),
			&"steps": 5,
		},
		{
			&"tiles": [[146, 140], [142, 143]],
			&"down": false,
			&"corner": Vector2i(-1, -1),
			&"steps": 5,
		},
		{
			&"tiles": [[84, 85], [84, 85]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	19: [
		{
			&"tiles": [[39, 40], [55, 56]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[41, 42], [57, 58]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
	],
	20: [
		{
			&"tiles": [[64, 65], [80, 81]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	23: [
		# A LADDER'S HOLE, and it is a stairwell with no steps in it. The reviewer
		# reads these as "a hole in the ground with a ladder inside it going
		# underground", and the drawing is a dark shaft with the ladder's rails
		# showing in it, so the cartridge's own picture of the hole laid on the
		# pit's floor is the picture of a ladder in a hole. What the mask CANNOT
		# give is the ladder on its own: cut on its outline the whole shaft comes
		# back as one body of about 170 pixels, which stood up would be a slab.
		{
			&"tiles": [[68, 69], [84, 85]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 3,
		},
		{
			&"tiles": [[14, 15], [30, 31]],
			&"down": true,
			&"step": Vector2i(0, 1),
			&"steps": 3,
		},
	],
	24: [
		# A LADDER'S HOLE, and it is a stairwell with no steps in it. The reviewer
		# reads these as "a hole in the ground with a ladder inside it going
		# underground", and the drawing is a dark shaft with the ladder's rails
		# showing in it, so the cartridge's own picture of the hole laid on the
		# pit's floor is the picture of a ladder in a hole. What the mask CANNOT
		# give is the ladder on its own: cut on its outline the whole shaft comes
		# back as one body of about 170 pixels, which stood up would be a slab.
		{
			&"tiles": [[32, 33], [48, 49]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
		# A LADDER'S HOLE, and it is a stairwell with no steps in it. The reviewer
		# reads these as "a hole in the ground with a ladder inside it going
		# underground", and the drawing is a dark shaft with the ladder's rails
		# showing in it, so the cartridge's own picture of the hole laid on the
		# pit's floor is the picture of a ladder in a hole. What the mask CANNOT
		# give is the ladder on its own: cut on its outline the whole shaft comes
		# back as one body of about 170 pixels, which stood up would be a slab.
		{
			&"tiles": [[34, 35], [50, 51]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
		{
			&"tiles": [[54, 55], [54, 55]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	27: [
		{
			&"tiles": [[14, 15], [30, 31]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	28: [
		{
			&"tiles": [[42, 43], [58, 59]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 3,
		},
		{
			&"tiles": [[44, 45], [60, 61]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 3,
		},
	],
	29: [
		{
			&"tiles": [[174, 175], [190, 191]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	30: [
		# A LADDER'S HOLE, and it is a stairwell with no steps in it. The reviewer
		# reads these as "a hole in the ground with a ladder inside it going
		# underground", and the drawing is a dark shaft with the ladder's rails
		# showing in it, so the cartridge's own picture of the hole laid on the
		# pit's floor is the picture of a ladder in a hole. What the mask CANNOT
		# give is the ladder on its own: cut on its outline the whole shaft comes
		# back as one body of about 170 pixels, which stood up would be a slab.
		{
			&"tiles": [[32, 33], [48, 49]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
		# A LADDER'S HOLE, and it is a stairwell with no steps in it. The reviewer
		# reads these as "a hole in the ground with a ladder inside it going
		# underground", and the drawing is a dark shaft with the ladder's rails
		# showing in it, so the cartridge's own picture of the hole laid on the
		# pit's floor is the picture of a ladder in a hole. What the mask CANNOT
		# give is the ladder on its own: cut on its outline the whole shaft comes
		# back as one body of about 170 pixels, which stood up would be a slab.
		{
			&"tiles": [[34, 35], [50, 51]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
		{
			&"tiles": [[54, 55], [54, 55]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	35: [
		# NOT A STAIRCASE AND NOT A LADDER: "a hole in the ground, the wooden planks
		# are broken". A pit is what a stairwell is once its steps are taken out, so
		# this costs one declaration and no code, and it is the same thing the
		# bicycle ramp of tileset 23 wants in open work 14.
		{
			&"tiles": [[84, 86], [88, 89]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
	],
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

## HOW MUCH OF A FACADE TILE IS NOT THE FACADE, in pixels off its left and right
## edges, per tileset and tile.
##
## A wall's end tile does not draw only wall. The reviewer read tileset 3's tile
## by tile: "this is the right edge of a house wall, the white vertical line on
## the far right is the floor, the grayish part is the house shadow, the black
## line is the house wall edge, and the white section on the left is the house
## wall itself". So five of its eight columns are the ground BESIDE the house and
## the shadow the house throws on it, and folding the tile whole stood all five
## up on the wall's face: every house in the game wore a pale grey frame down
## both edges.
##
## The wall's box is narrowed by these instead, and the strip they leave is
## floor. What the drawing says about the shadow is dropped rather than laid
## down, for the reason a model drops its darkest shade: that shadow is what a
## flat picture needs to sit an object on a floor, and this floor has a sun over
## it throwing a real one.
##
## The BOTTOM rows of the same drawings are deliberately not here. Tile 26's last
## two rows are shadow and floor too, but they land at the very foot of the wall
## where it meets the ground, and two pixels of dark there read as the contact
## shadow they are. Only the vertical strips read as a frame.
const FACADE_MARGIN: Dictionary = {
	3: {
		# The right edge of a wall, and the bottom right corner under it.
		31: Vector2i(0, 5),
		60: Vector2i(0, 5),
		# The left edge of a wall, and the bottom left corner under it, which the
		# reviewer read the same way about: "the white vertical line on the far left
		# is the floor, the grayish part is the house shadow, the black line is the
		# house wall edge, and the white section on the right is the house wall
		# itself".
		15: Vector2i(5, 0),
		29: Vector2i(5, 0),
	},
}

## WHICH FACADE TILES ARE THE FRONT SLOPE OF A ROOF, per tileset and tile.
##
## A facade is a wall seen face-on and it stands up square, which is right for a
## wall and wrong for the other thing Generation II draws face-on. Tileset 1's
## houses do not draw their roof from above at all: they draw the front PITCH of
## it, four rows of plank or of speckled tile over two rows of wall, and the full
## pass reads every one of them the same way, "drawn FACE-ON, this is the front
## slope of the roof and not a view from above". Stood up square that is a barn:
## a tall box with roof texture down its upper half and a flat lid, on every
## house of the twenty-four maps tileset 1 carries.
##
## So those bands LEAN BACK over the building's own footprint, one tile of depth
## per band of height, which is the reference's band table
## (`sprite_to_voxel_methodology.md`, "the taper rate IS the slope"). The fold
## already makes a house as deep as its drawing is tall, so the pitch leans back
## INTO the footprint and the building's total height does not move by a pixel.
##
## Per TILE and not per class, for `FACADE_MARGIN`'s reason: which surface a
## drawing depicts is a fact about that drawing, and `facade` covers both.
const FACADE_SLOPE: Dictionary = {
	# The plank roof of the wooden house, six tiles across and four rows down over
	# a veranda storey: 82 and 83 are its field, 81/65/49 and 84/68/52 the end
	# boards that close it off at either side. And the speckled brown roof of the
	# small brick house, 82 again for its eave with 72 and 54 above it.
	1: [49, 52, 54, 65, 68, 72, 81, 82, 83, 84],
	# The same reading on the one map tileset 4 draws a house on, in cyan
	# corrugated sheet: "the roof being about three rows tall, FACE-ON rather than
	# from above". Pinned with tileset 1 so the two cannot drift apart, which is
	# the lesson the conifer and the notice board both cost.
	4: [10, 11, 12, 13, 14, 15, 16, 17, 18],
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
	&"notice_case": &"cutout",
	&"bush": &"cutout",
	&"sapling": &"cutout",
	&"tombstone": &"cutout",
	&"flowers": &"cutout",
	&"planter": &"cutout",
	&"statue": &"cutout",
	&"statue_pillar": &"cutout",
	&"stand": &"cutout",
	&"lie": &"cutout",
	&"boulder": &"cutout",
	&"stool": &"cutout",
	# railing: a LINE seen from above, built as a rail on posts. See
	# `mesher.gd:_railing`, and the pipeline table for why it is a fourth thing a
	# drawing can be rather than one of the three.
	&"railing": &"railing",
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
		# THE METAL RAILING round Goldenrod's lawns, 2200 tiles and the largest
		# thing left in the full pass's `stand` fallback after the boulders. Two
		# rails and a post cap: 16 runs north to south, 32 east to west, 33 is the
		# round white cap where two runs meet. The reviewer's answer in round ten
		# is that it is a fence you see over, half a cell tall.
		&"railing": [16, 32, 33],
		# A cell each, and both about as tall as the player.
		&"bush": [64, 65, 80, 81],
		&"sapling": [45, 46, 61, 62],
		# Ground the detector was standing up because its cell is blocked by
		# what stands NEXT to it: grass under a ledge lip, and the stone floor
		# of a plateau.
		#
		# AND 4, THE STEP THROUGH THE LEDGE, which the generated pass called a lip
		# and which is the flat pale tread the player walks down: 126 tiles on 21
		# maps, and the reviewer's own item. A LIP IS THE BLOCKED CELL A HOP
		# PASSES OVER, so a tile whose every placement is WALKABLE is not one, and
		# that test is what found this and the four tilesets below.
		&"ground": [17, 44, 57, 4],
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
	# grass is the cartridge's own answer and `Gen2WorldCollision.is_grass` gives
	# it, so these pins are an OVERRIDE and no longer the only reading: they stand
	# a drawing up where no collision code says so.
	1: {
		# The paving in front of the mart door, walked on and drawn flat.
		&"ground": [154],
		&"tall_grass": [4],
		# THE PINK BRICK WALL of the small house, which the pass read as paving and
		# which is why every one of those houses was a roof block over a hole. The
		# same slot draws both: 592 placements lie in walkable cells on 3 maps and
		# are the brick causeway the pass described, 458 lie in blocked cells on 16
		# and are the wall between the windows and the eave. Tileset 2 pins the same
		# drawing `facade` and calls it "the pale blue brick wall of a shop".
		# The COLLISION is what tells them apart and it already does: a building pin
		# in a walkable cell resolves back to ground, which is the rule tileset 3's
		# tile 35 was given for exactly this.
		&"facade": [7],
		# THE ROUTE NOTICE BOARD, 78 of them over 22 maps and the largest thing left
		# in the full pass's `stand` fallback. `stand` is ROUND, so a board with a
		# frame, four lines of writing and two legs was revolved into a drum. It is
		# the same drawing as tileset 3's wooden route sign, which the reviewer
		# measured themselves: a plate on posts, cut on its own outline and standing
		# as many pixels as it is drawn.
		&"sign_post": [78, 79, 94, 95],
		# THE SEA ROCK, one 8px tile drawn as a small oval stone and laid in
		# diagonal chains across the water: 802 cells of it, every one drawing the
		# tile four times, so a cell is four separate stones and the model is placed
		# per BODY rather than per cell.
		&"boulder": [88],
		# THE CONIFER, and tileset 1 is 29 maps: more of the game's outdoors than
		# any other. Six tiles, drawn as a pointed top over an optional middle over
		# a foot, and the middle is what makes a tall one: 3696 cells carry
		# [30,31,46,47] and exactly 3696 carry [46,47,62,63], so every tall tree is
		# a matched pair, while 846 cells draw [30,31,62,63] on its own and are the
		# short one. `SPANS` declares the tall one and the placement collapses it.
		&"tree": [30, 31, 46, 47, 62, 63],
	},
	# THE SAME TREE AGAIN, and tilesets 2 and 4 draw it out of the same six slots
	# tileset 1 does: a top at [30,31], a foot at [62,63] and a middle that makes
	# a tall one, which is [46,47] there and [19,21] here. Every block that places
	# it is the conifer's own arrangement, top over middle over middle over foot
	# for the tall one and top over foot for the short, so `SPANS` and the repeat
	# rule collapse it exactly as they do tileset 1's.
	2: {
		# The step up to a doorway, drawn as a flat tread and walked on.
		&"ground": [91],
		&"tall_grass": [4],
		&"tree": [30, 31, 19, 21, 62, 63],
		&"boulder": [88],
	},
	4: {
		&"tree": [30, 31, 19, 21, 62, 63],
		# The same notice board tileset 1 draws, at the same four ids, on paving
		# instead of on grass. One placement on one map, and it is here so the two
		# tilesets cannot drift apart: the conifer went the same way.
		&"sign_post": [78, 79, 94, 95],
	},
	# EVERY BOULDER IN THE GAME, and each of these is one walk cell drawn as a
	# 2x2-tile stone: 268 of them standing in the sea off Olivine, 775 on the cave
	# floors of tileset 24 and 133 ice rocks on the snow of tileset 29. They stood
	# as `stand`, the full pass's fallback for something standing, which carved
	# them into heaps of rubble; the pass's own words call all three a rounded
	# boulder drawn as its own silhouette, which is the portrait a model is turned
	# from. See "The sprite-to-model pipeline".
	9: {
		&"boulder": [1, 2, 17, 18],
		# The pair flanking a doorway, one placement each on two maps.
		&"statue_pillar": [6, 7, 22, 23, 8, 9, 24, 25],
	},
	24: {
		&"boulder": [12, 13, 28, 29],
	},
	29: {
		&"boulder": [196, 197, 212, 213],
	},
	30: {
		# The floor of the opening in the cave wall, one walk cell of it, walked
		# through rather than hopped over.
		&"ground": [14, 15, 30, 31],
	},
	17: {
		&"tall_grass": [87],
		# THE BRONZE FIGURE ON A STONE PLINTH, twelve of them over three maps and
		# drawn over two different bases: the second swaps the base's top row for
		# [16, 1], which this tileset draws nowhere else, so both are pinned or half
		# a drawing resolves no span at all.
		&"statue_pillar": [72, 73, 88, 89, 74, 75, 90, 91, 16, 1],
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
		# THE NATIONAL PARK'S BIN, and it was drawn NOWHERE AT ALL. A round grey
		# vessel with a dark hollow in its top, one walk cell over four tiles,
		# standing on the paving beside the benches; five placements on three maps.
		# Photographed where the cartridge puts it, the paving is bare.
		#
		# The paving is dithered in the same greys the bin is drawn in, which is the
		# case `OUTLINE` exists for and the reason nothing stood: the ground flood
		# walks straight through the flanks. `boulder` answers all of it, because a
		# bin is read exactly as a rock is: cut on its own dark ring, FILLED so an
		# open rim cannot starve it, turned rather than carved, one world pixel per
		# voxel, no sway, and coloured BY BAND, which is what a thing drawn pale on
		# top and dark down its side wants.
		&"boulder": [90, 91, 19, 130],
		# THE NOTICE CABINET BESIDE IT, and it was drawn nowhere for the same
		# reason: a glazed case in a dark frame standing on two posts, one walk
		# cell over four tiles, six placements on two maps. The pass split it
		# between `stand` and `post`, and both cut their mask on the colours of the
		# ground, which here is dithered in the case's own greys.
		#
		# It is FLAT and FACE-ON where the bin is round, so it is carved rather
		# than turned: a board in a frame on posts, which is the wooden route
		# sign's shape, cut on its own outline and standing the fourteen rows it is
		# drawn.
		&"notice_case": [69, 70, 85, 86],
	},
	# THE SAME STATUE ON THE SAME PILLAR, which the full pass had as `statue` and
	# which came out a heap of loose pieces. It is not one of the two the reviewer
	# read, and it is here because it is the same arrangement, [66,67/82,83] over
	# [68,69/84,85], and because the picture of it is plainly better.
	14: {
		&"statue_pillar": [66, 67, 82, 83, 68, 69, 84, 85],
	},
	# THE POKE BALL ON ITS PILLAR, the pair that flanks a doorway at the League and
	# the Centers, about eighteen of them. Top cell the ball, bottom cell the base.
	15: {
		&"statue_pillar": [32, 33, 48, 49, 34, 35, 50, 51],
	},
	# THE RHYHORN ON ITS PILLAR, and the statues that share its base, standing
	# round the walls of a wooden hall. The commonest drawing in the game that had
	# no word for it: 485 tiles resolved to the full pass's catch-all for something
	# standing, and this is most of them. The base [54,55] is drawn under more than
	# one statue, which is why the tiles above it are pinned with it: half a drawing
	# pinned and half not resolves no span at all.
	#
	# THE HEALING MACHINE IS NOT ONE OF THESE, and that is a measured refusal
	# rather than an oversight. A dome on a box is a statue on a pillar in
	# everything the geometry says, so it was pinned here, built and photographed:
	# turned, the box comes back narrower than its own drawing and the dome shrinks
	# onto it over a dark gap, where the fallback stands a legible red dome on a
	# grey cabinet. What it is drawn as is a BOX with a round lid, and nothing here
	# turns half a drawing.
	23: {
		&"statue_pillar": [34, 35, 50, 51, 18, 19, 54, 55, 74, 75, 90, 91, 76, 92],
	},
	# THE OTHER FIVE THE FULL PASS CALLED `statue`, all of them the same
	# arrangement as the three above: a 2x4 run of tiles, one walk cell wide and
	# two tall, the upper cell the figure and the lower one the base it stands on.
	# Held back a round because moving the CLASS had moved all seven at once and
	# tileset 26's was read as coming out worse; photographed one at a time it does
	# not, and what it replaced there is two thin pipes.
	#
	# THE LEAGUE'S HALL, eight of them down a red carpet on map 16,7, and the
	# clearest drawing of the arrangement in the game: a round head on a tiered
	# pedestal with open floor either side of it.
	18: {
		&"statue_pillar": [152, 153, 154, 155, 156, 157, 158, 159],
	},
	# The pair flanking a doorway, one placement each on one map.
	10: {
		&"statue_pillar": [76, 77, 92, 93, 78, 79, 94, 95],
	},
	# THE RUINS OF ALPH, 42 of them over nine maps, and it is the SAME DRAWING
	# tileset 23 places in its wooden hall, pixel for pixel over both cells and
	# only the palette apart.
	#
	# IT IS TURNED ON A LATHE AND THAT IS THE REVIEWER'S OWN ANSWER, taken over a
	# square-carved build of the same drawing that was committed first and shown
	# beside it. So the exception this drawing seemed to want is not one: it fills
	# its 16x32 box edge to edge, which makes every row's run the full width, and
	# it is still a round thing. What that costs is a column the flood has walked
	# into down one side; what carving it square bought was a legible face on a
	# boxy prop, and a stone pillar was wanted over the face. Do not re-derive the
	# square build: it was measured, photographed and refused.
	26: {
		&"statue_pillar": [14, 15, 30, 31, 46, 47, 62, 63],
	},
	# THE SCHOOL'S NORTH WALL, which the full pass read as three more flights of
	# stairs and the reviewer read tile by tile. One run holds two real flights set
	# into it, [163,164,179,180], which is declared in STAIRS and stays; what is on
	# either side of them is not. 165 and 181 are the wall's END, "the very left
	# edge is a small section of a vertical wall, the middle part is just the
	# floor", so they lie flat. Twenty tiles on one map, all of them 21,15.
	# ITS POTTED PLANT is the same drawing tileset 5 and tileset 11 draw and takes
	# the same class, at ONE CELL: "the leafy top of a potted plant, its own
	# silhouette cut out against the wall behind; it sits on the pot below (tiles
	# 94/95) which stands on the pink floor". A `planter` counts its own height
	# off its own drawing, so the size is the placement's business and not the
	# pin's. Cut cell by cell it was one cell anyway, so what moves is the class:
	# `stand` revolved it into a striped green drum eight pixels tall on the floor
	# beside a cabinet three times its height.
	13: {
		&"ground": [165, 181],
		&"planter": [46, 47, 94, 95],
	},
	# THE ROUND STOOLS, and they were the largest thing left in the `stand`
	# fallback that is one drawing rather than a tail.
	#
	# The pass read every one of them and its words are the specification: tileset
	# 19's is "a round pink stool with a red rim and dark splayed legs, drawn as
	# its own SILHOUETTE against the chequered floor; the stool is 2x2 tiles, waist
	# high, and they stand in rows beside the blue tables". `stand` is ROUND but it
	# is CARVED, so each cell was cut on its own and stood at the class's own eight
	# pixels: a pink wafer on the floor where the cartridge draws a seat.
	#
	# A round seat on a pedestal is a portrait of a symmetric thing, which is the
	# third row of the pipeline table, and it is turned like a boulder rather than
	# like a plant: see ROCK.
	#
	# ITS BALL ORNAMENT takes `boulder` in the same room and for the same reason a
	# rock does rather than a plant: "a large red and white ball-shaped ornament,
	# drawn as its own SILHOUETTE with a heavy dark outline, 2x2 tiles, about waist
	# high, standing free in the middle of the room floor". One world pixel per
	# voxel, no sway, colour BY BAND, which is how a sphere is drawn.
	19: {
		&"stool": [7, 8, 23, 24],
		&"boulder": [72, 73, 88, 89],
	},
	# TWO STOOLS ON ONE TILESET, drawn out of different tiles and only the palette
	# apart: "a round pink cushioned stool with a dark pedestal" and "a round tan
	# stool with a dark pedestal", on the carpet and on the plank floor.
	#
	# ITS ROUND TABLE IS NOT ONE, though it is the same drawing a size up: pinned
	# `stool` and photographed, the turn eats the dark splayed legs and returns a
	# pale mushroom, where the carved fallback keeps a cream top over a dark base.
	# A stool's legs are a pedestal and a table's are four thin ones with carpet
	# between them, which is what a revolve cannot hold.
	27: {
		&"stool": [44, 45, 60, 61, 39, 40, 55, 56],
	},
	# A THIRD TILESET DRAWS THE SAME STOOL, four of them round a table, and it was
	# left out because its two rows were pinned differently: the seat as `top` and
	# the legs as `stand`, so the class it wanted could not be read off either row
	# alone. The pass's words are the same drawing as the other two, "the round
	# padded seat drawn from ABOVE as a light disc with a dark rim" over "the dark
	# legs and the shadow under the seat, its own SILHOUETTE with floorboards
	# showing through the gaps", which is exactly what `STRETCH` was measured for:
	# half of a stool's drawing is the seat seen from above, which is depth on the
	# page and no height at all.
	6: {
		&"stool": [2, 3, 18, 19],
	},
	16: {
		&"railing": [64, 65],
		# The tread at the foot of the shop counter, walked on and drawn flat.
		&"ground": [16],
	},
	# THE POTTED PLANT, which is the drawing tileset 5 already calls `planter`: a
	# leafy crown over a stalk over a pot, two tiles across and four down, one walk
	# cell wide and two tall, standing on its own on a chequered floor. The full
	# pass split every one of them between two classes, so no row of one named the
	# drawing and the whole group sat in the `stand` tail as a squat pot with a
	# tuft of leaves beside it, cut cell by cell.
	#
	# IT STANDS ITS OWN 32 PX, which is the reviewer's own answer in round
	# twenty-four, shown the same plant built at four heights in the room it
	# stands in. An earlier session read the full height as a green column as tall
	# as the bookcase beside it and shelved the whole build for it; the reader who
	# owns that judgement was asked and disagreed.
	11: {
		&"planter": [44, 45, 60, 61, 46, 47, 62, 63],
	},
	# THE PORT'S TWO PLANTS, and they are the first drawing in the game to want
	# HALF A CELL of height. The brown pot is "two tiles wide and three tall, two
	# rows of leaves over one row of pot", so its box's bottom row is the floor it
	# stands on: see `mesher.gd:_measure_cutouts`, which cuts the box back to the
	# rows the drawing uses rather than collapsing it.
	#
	# The grey urn is the tileset 11 plant's own size, two tiles by four, and it
	# is drawn under TWO different crowns, "a tangle of golden-brown branches" and
	# "a dark mass of red blossoms". Both are the same plant and both take the
	# class: the urn's own tiles are shared between them, so neither could be
	# pinned without the other.
	28: {
		&"planter": [
			30, 31, 46, 47, 62, 63,
			69, 70, 85, 86, 7, 8, 23, 24, 9, 25, 48, 49,
		],
	},
	# ONE MORE OF THE SAME PLANT, found the same way and taking the same class:
	# "the dark green foliage of a potted plant, its own silhouette drawn from the
	# front" over "the red planter box at its foot", two tiles by four.
	#
	# TILESET 21'S IS NOT THIS DRAWING and its blocks are what say so, which is the
	# rule about looking at the block rather than the tile list. It is drawn at
	# three heights out of the same crown, trunk and pot, and one of them REPEATS
	# the trunk row: that is the flower bed's case, a thing that tiles into a
	# continuous row, and pinning it here stood one plant of a pair as a sprawl.
	12: {
		&"planter": [74, 75, 8, 9, 137, 138, 167, 168],
	},
}

## The tiles the PASS pinned and a person has taken back.
##
## The table above corrects the pass by naming a better class, and there is one
## correction it cannot make that way: a tile whose right answer is NO PIN AT
## ALL. A plain standing wall is exactly that, deliberately, because the
## automatic resolution stands a blocked tile up already and MEASURES its height
## off the drawing where a pin would force one.
##
## Tileset 13's 162 is the reviewer's own reading: the pass called
## [161,162,177,178] a flight of stairs and they call it "a vertical wall, and a
## metal fence joining the wall", the fence drawn thin down the left edge because
## it runs away from the eye. Standing as stairs it cut a stairwell into a wall.
##
## The fence itself is left painted on the wall rather than built as a `railing`:
## it shares its tiles with the wall, so a railing pin, which turns a tile into
## floor with a rail on it, would open a hole through the wall it is joined to.
const UNPINNED: Dictionary = {
	13: [162],
	# THE MAGNET TRAIN STATION'S CREAM PILLARS, which the pass called `stand` and
	# revolved into drums standing in a wall. They are the vertical strips between
	# the blue brick panels and they are the wall: unpinned and blocked, a tile
	# resolves `wall` and stands the full cell, flush with the brick beside it,
	# which is the reviewer's own answer in round twenty-two.
	#
	# THE SAME TWO IDS ARE THE TICKET GATE'S MIDDLE ROWS, so this cannot be done
	# without the gate below and the gate cannot be done without this. An object is
	# found by its whole ARRANGEMENT and overrides whatever its tiles resolved to,
	# so the gate keeps its shape while these tiles stop being a class of their own.
	17: [55, 56],
	# ONE DRAWING THAT IS TWO THINGS, and the largest group left in the `stand`
	# tail: 116 tiles that the pass revolved into a row of chests marching up a
	# roof. The reviewer read both places in round twenty-four and they are not
	# the same thing at all: on the tower's great roof it is "an upper small thing
	# on the roof", and in the wooden hall it is "just a bridge made of wood where
	# you can walk onto".
	#
	# THEIR RULE FOR TELLING THEM APART IS THE MIRRORED NEIGHBOUR: the roof pairs
	# 80 with 81, which is 80 drawn the other way round, and the bridge never has
	# one beside it. The COLLISION says the same thing and says it per cell, which
	# is cheaper and is what an unpinned tile already reads: the hall's 48 tiles
	# are walkable and the roof's 68 are blocked. So both answers fall out of
	# taking the pin away. The bridge lies flat and is walked on; the crest stands
	# and has its height measured off its own column, which is what a blocked tile
	# with no pin does everywhere else in the game.
	23: [80, 81],
}


## The class a tile is pinned to, or an empty StringName when it is not pinned.
##
## The hand table above first, then the full pass in `profile_pass.gd`. The order
## is the point: the table above was authored from the reviewer's own
## measurements off the drawing, and the pass is a machine reading the same
## pictures, so where they disagree the person is right and the pass can be
## regenerated under them. UNPINNED is the same authority saying the pass should
## have named a tile nothing at all.
static func pinned_class(tileset_number: int, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset_number, null)
	if groups is Dictionary:
		for shape_class: StringName in (groups as Dictionary):
			var tiles: Variant = (groups as Dictionary)[shape_class]
			# A plain Array, because a PackedInt32Array literal is not a constant
			# expression and this whole table has to be one.
			if tiles is Array and (tiles as Array).has(tile):
				return shape_class
	var taken: Variant = UNPINNED.get(tileset_number, null)
	if taken is Array and (taken as Array).has(tile):
		return &""
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
