extends RefCounted

## Resolves every graphics tile of a map to an extrusion shape.
##
## Resolution order, and the order matters:
##
##   per tile   1. a pin in `profile.gd`                          (authored)
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


func height(shape_class: StringName) -> int:
	return _profile.height_of(shape_class)


func art(shape_class: StringName) -> StringName:
	return _profile.art_of(shape_class)


func depth(shape_class: StringName) -> int:
	return _profile.depth_of(shape_class)


func is_round(shape_class: StringName) -> bool:
	return bool(_profile.ROUND.get(shape_class, false))


func is_filled(shape_class: StringName) -> bool:
	return bool(_profile.FILLED.get(shape_class, false))


## Which surface of a building a class depicts, empty for everything that is not
## one, and how far a sloped roof tile has fallen, in bands.
func building_part(shape_class: StringName) -> StringName:
	return StringName(_profile.BUILDING.get(shape_class, &""))


func roof_drop(shape_class: StringName) -> int:
	return int(_profile.ROOF_DROP.get(shape_class, 0))


func is_merged(shape_class: StringName) -> bool:
	return bool(_profile.MERGED.get(shape_class, false))


func _pin(tile: int) -> StringName:
	if _pinned.has(tile):
		return _pinned[tile]
	var pinned: StringName = _profile.pinned_class(_tileset_number, tile)
	_pinned[tile] = pinned
	return pinned
