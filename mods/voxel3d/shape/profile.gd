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

## Class heights in world pixels. A walk cell is 16x16 and a graphics tile 8x8,
## so a height is a whole number of 8px bands and everything on this list is one.
const HEIGHTS: Dictionary = {
	&"ground": 0,
	# Water recesses so a shoreline shows a lip rather than a painted seam.
	&"water": -8,
	&"void": 0,
	&"ledge": 8,
	&"wall": 16,
	&"tree": 16,
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
	# A cutout carries no height of its own: how tall it stands is COUNTED off the
	# drawing, because the drawing is what the reviewer measured. A concrete
	# bollard is 15 px of art on a 16 px cell and a wooden sign is 14, and no
	# class constant would have found either.
	&"post": 0,
	&"sign_post": 0,
	&"bush": 0,
	&"sapling": 0,
}

## How thick a cutout stands, in world pixels.
##
## The only thing that separates one cutout from another. A sign is a plate on a
## stick and reads wrong at any depth; a bollard is a round post and wants enough
## to be one; a bush is nearly as deep as it is wide.
const DEPTHS: Dictionary = {
	&"post": 6,
	&"sign_post": 2,
	&"bush": 12,
	&"sapling": 12,
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
	&"tree": &"upright",
	&"fence": &"upright",
	&"sign": &"upright",
	&"cliff": &"upright",
	&"counter": &"upright",
	&"table": &"upright",
	&"desk": &"upright",
	&"bookcase": &"upright",
	# cutout: not a box at all. The drawing's own silhouette stands up one run of
	# pixels at a time, on ground taken from the walkable cell beside it, which is
	# what a thing with a shape rather than a face wants.
	&"post": &"cutout",
	&"sign_post": &"cutout",
	&"bush": &"cutout",
	&"sapling": &"cutout",
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
	},
}


## The class a tile is pinned to, or an empty StringName when it is not pinned.
static func pinned_class(tileset_number: int, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset_number, null)
	if not groups is Dictionary:
		return &""
	for shape_class: StringName in (groups as Dictionary):
		var tiles: Variant = (groups as Dictionary)[shape_class]
		# A plain Array, because a PackedInt32Array literal is not a constant
		# expression and this whole table has to be one.
		if tiles is Array and (tiles as Array).has(tile):
			return shape_class
	return &""


static func height_of(shape_class: StringName) -> int:
	return int(HEIGHTS.get(shape_class, 0))


static func art_of(shape_class: StringName) -> StringName:
	return StringName(ART.get(shape_class, &"flat"))


static func depth_of(shape_class: StringName) -> int:
	return int(DEPTHS.get(shape_class, 4))
