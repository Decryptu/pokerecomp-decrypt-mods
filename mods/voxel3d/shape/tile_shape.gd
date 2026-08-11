extends RefCounted

## Resolves every graphics tile of a map to an extrusion shape.
##
## Resolution order, and the order matters:
##
##   per tile   1. a pin in `profile.gd`, except a BUILDING pin in a walkable
##                 cell, which is the pavement wearing the wall's own tile
##                                                                 (authored)
##   per CELL   2. the cell's collision permission is water    -> "water"
##              3. the cell's collision permission is walkable -> "ground"
##   per tile   4. anything left                                -> "wall"
##
## The cell steps are the load-bearing part, and Generation II hands them over
## directly: collision is a real permission byte per 2x2 walk cell, not a
## walkable-tile list to be reverse-read. A tile sitting in a walkable cell is
## ground the player is standing on whatever it is drawn as, which is what keeps
## flowers, grass tufts and the gaps in a fence row from extruding into pillars.
## Only a pin overrides that.
##
## Step 4 covers a cell that IS blocked: everything in it rises.
##
## Purely presentational. A shape decides how a tile draws and nothing else.

var _profile: GDScript = null
var _tileset_number: int = 0
## tile id -> class, for the tiles already asked for. A map asks for the same
## ninety-six tiles a few thousand times over.
var _pinned: Dictionary = {}


func _init(profile: GDScript, tileset_number: int) -> void:
	_profile = profile
	_tileset_number = tileset_number


## [param permission] is Gen2WorldAPI.collision_permission_at() for the walk
## cell this tile sits in, and [param tile] the graphics tile id.
func at(tile: int, permission: int) -> StringName:
	var pinned: StringName = _pin(tile)
	if pinned != &"":
		# A building is never walked on, and the one plain tile draws both a house
		# wall and the pavement in front of it: tileset 3's tile 35 is most of a
		# town's paving and also the blank part of a wall. The cell is what tells
		# them apart, so this pin alone does not override collision, and the
		# pavement lies flat instead of standing a band above the floor beside it.
		if permission == Gen2WorldCollision.LAND_TILE and building_part(pinned) != &"":
			return &"ground"
		return pinned
	match permission:
		Gen2WorldCollision.WATER_TILE:
			return &"water"
		Gen2WorldCollision.LAND_TILE:
			return &"ground"
	return &"wall"


## Whether the profile named this tile. A pin carries its own height, so the
## mesher's column measurement leaves it alone.
func is_pinned(tile: int) -> bool:
	return _pin(tile) != &""


## Whether the tile draws the face of a terrain cliff. A property of the tile
## and not of its class: a cliff face stands up like any other wall and what is
## different about it is the plateau behind it.
func is_cliff(tile: int) -> bool:
	return _profile.is_cliff(_tileset_number, tile)


## Whether it is the front of one: the face drawn toward the screen, with the
## raised floor immediately above it. Only a front says which side is up.
func is_cliff_front(tile: int) -> bool:
	return _profile.is_cliff_front(_tileset_number, tile)


## Whether it is the plateau's far EDGE, seen from above with the seam inside its
## own drawing.
func is_cliff_lip(tile: int) -> bool:
	return _profile.is_cliff_lip(_tileset_number, tile)


func height(shape_class: StringName) -> int:
	return _profile.height_of(shape_class)


func art(shape_class: StringName) -> StringName:
	return _profile.art_of(shape_class)


func depth(shape_class: StringName) -> int:
	return _profile.depth_of(shape_class)


func is_round(shape_class: StringName) -> bool:
	return bool(_profile.ROUND.get(shape_class, false))


## How big the drawing is, in walk cells. A hull is keyed to the size of the
## drawing and never to a tile id.
func span_cells(shape_class: StringName) -> Vector2i:
	return _profile.SPANS.get(shape_class, Vector2i.ONE)


## Whether the drawing's extra cells are depth rather than height: a long flower
## bed is no taller than a short one.
func is_lying(shape_class: StringName) -> bool:
	return bool(_profile.LYING.get(shape_class, false))


func is_filled(shape_class: StringName) -> bool:
	return bool(_profile.FILLED.get(shape_class, false))


## Which surface of a building a class depicts, empty for everything that is not
## one, and how far a sloped roof tile has fallen, in bands.
func building_part(shape_class: StringName) -> StringName:
	return StringName(_profile.BUILDING.get(shape_class, &""))


func roof_drop(shape_class: StringName) -> int:
	return int(_profile.ROOF_DROP.get(shape_class, 0))



func _pin(tile: int) -> StringName:
	if _pinned.has(tile):
		return _pinned[tile]
	var pinned: StringName = _profile.pinned_class(_tileset_number, tile)
	_pinned[tile] = pinned
	return pinned
