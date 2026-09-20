extends RefCounted

## The Generation I shape PROFILE: hand-authored pins over the automatic
## resolution in `tile_shape.gd`, keyed by Red, Blue and Yellow's own tileset
## numbers. `pass.gd` is the generated pass over every tileset, and this one wins
## where the two disagree.

const PASS: GDScript = preload("pass.gd")
const HOUSES: GDScript = preload("houses.gd")

const GROUND: Dictionary = {}

const MOUNDS: Dictionary = {}

const GROUND_PINS: Dictionary = {}

const OBJECTS: Dictionary = {}

const STAIRS: Dictionary = {}

const CLIFFS: Dictionary = {}
const FRONTS: Dictionary = {}

const LIPS: Dictionary = {}

const FENCES: Dictionary = {}

const ROOM_WALL: Dictionary = {}

const FACADE_MARGIN: Dictionary = {}

const FACADE_SLOPE: Dictionary = {}

const TILESETS: Dictionary = {}

const UNPINNED: Dictionary = {}


static func pinned_class(tileset_number: int, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset_number, null)
	if groups is Dictionary:
		for shape_class: StringName in (groups as Dictionary):
			var tiles: Variant = (groups as Dictionary)[shape_class]
			if tiles is Array and (tiles as Array).has(tile):
				return shape_class
	var taken: Variant = UNPINNED.get(tileset_number, null)
	if taken is Array and (taken as Array).has(tile):
		return &""
	return PASS.pinned_class(tileset_number, tile)


static func fence_face(tileset_number: int) -> Array:
	var tiles: Variant = FENCES.get(tileset_number, null)
	return tiles as Array if tiles is Array else []


static func is_cliff(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = CLIFFS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


static func is_cliff_front(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = FRONTS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


static func is_cliff_lip(tileset_number: int, tile: int) -> bool:
	var tiles: Variant = LIPS.get(tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


static func houses(tileset_number: int) -> Array:
	return HOUSES.of_tileset(tileset_number)
