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
}

## Tileset number -> class -> the tile ids that class claims.
##
## Empty until a tileset has been surveyed. An unlisted tile is resolved from
## its cell's collision permission, which is right for the great majority of
## them; a pin is for the minority where the drawing and the permission disagree.
const TILESETS: Dictionary = {}


## The class a tile is pinned to, or an empty StringName when it is not pinned.
static func pinned_class(tileset_number: int, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset_number, null)
	if not groups is Dictionary:
		return &""
	for shape_class: StringName in (groups as Dictionary):
		var tiles: Variant = (groups as Dictionary)[shape_class]
		if tiles is PackedInt32Array and (tiles as PackedInt32Array).has(tile):
			return shape_class
	return &""


static func height_of(shape_class: StringName) -> int:
	return int(HEIGHTS.get(shape_class, 0))


static func art_of(shape_class: StringName) -> StringName:
	return StringName(ART.get(shape_class, &"flat"))
