extends RefCounted

## Resolves every graphics tile of a map to an extrusion shape.

const Stems: GDScript = preload("stems.gd")

var _profile: GDScript = null
var _tileset_number: int = 0
var _pinned: Dictionary = {}


func _init(profile: GDScript, tileset_number: int) -> void:
	_profile = profile
	_tileset_number = tileset_number


func at(tile: int, permission: int) -> StringName:
	var pinned: StringName = _pin(tile)
	if pinned != &"":
		if permission == Gen2WorldCollision.LAND_TILE and building_part(pinned) != &"":
			return &"ground"
		return pinned
	match permission:
		Gen2WorldCollision.WATER_TILE:
			return &"water"
		Gen2WorldCollision.LAND_TILE:
			return &"ground"
	return &"wall"


func is_pinned(tile: int) -> bool:
	return _pin(tile) != &""


func is_cliff(tile: int) -> bool:
	return _profile.is_cliff(_tileset_number, tile)


func fence_face() -> Array:
	return _profile.fence_face(_tileset_number)


func is_cliff_front(tile: int) -> bool:
	return _profile.is_cliff_front(_tileset_number, tile)


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


func is_tufted(shape_class: StringName) -> bool:
	return bool(_profile.TUFTS.get(shape_class, false))


func is_swaying(shape_class: StringName) -> bool:
	return bool(_profile.SWAYS.get(shape_class, false))


func is_model(shape_class: StringName) -> bool:
	return bool(_profile.MODEL.get(shape_class, false))


func outline_shades(shape_class: StringName) -> int:
	return int(_profile.OUTLINE.get(shape_class, 0))


func is_shrub(shape_class: StringName) -> bool:
	return bool(_profile.SHRUB.get(shape_class, false))


func is_potted(shape_class: StringName) -> bool:
	return bool(_profile.POTTED.get(shape_class, false))


func is_rock(shape_class: StringName) -> bool:
	return bool(_profile.ROCK.get(shape_class, false))


func is_column(shape_class: StringName) -> bool:
	return bool(_profile.COLUMN.get(shape_class, false))


func model_stretch(shape_class: StringName) -> float:
	return float(_profile.STRETCH.get(shape_class, 0.0))


func span_cells(shape_class: StringName) -> Vector2i:
	return _profile.SPANS.get(shape_class, Vector2i.ONE)


func is_lying(shape_class: StringName) -> bool:
	return bool(_profile.LYING.get(shape_class, false))


func is_filled(shape_class: StringName) -> bool:
	return bool(_profile.FILLED.get(shape_class, false))


func stem_rows(shape_class: StringName) -> Array:
	if not bool(_profile.STEMS.get(shape_class, false)):
		return []
	return Stems.of_class(shape_class)


func building_part(shape_class: StringName) -> StringName:
	return StringName(_profile.BUILDING.get(shape_class, &""))


func roof_drop(shape_class: StringName) -> int:
	return int(_profile.ROOF_DROP.get(shape_class, 0))


func facade_margin(tile: int) -> Vector2i:
	var table: Dictionary = _profile.FACADE_MARGIN.get(_tileset_number, {})
	return table.get(tile, Vector2i.ZERO)


func is_facade_slope(tile: int) -> bool:
	var tiles: Variant = _profile.FACADE_SLOPE.get(_tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


func objects() -> Array:
	return _profile.OBJECTS.get(_tileset_number, [])


func object_outside() -> int:
	return _profile.OUTSIDE


func stairs() -> Array:
	return _profile.STAIRS.get(_tileset_number, [])


func room_wall() -> Array:
	return _profile.ROOM_WALL.get(_tileset_number, [])


func mound_tiles() -> Dictionary:
	return _profile.MOUNDS.get(_tileset_number, {})


func ground_table() -> Dictionary:
	var table: Dictionary = (_profile.GROUND.get(_tileset_number, {}) as Dictionary).duplicate()
	table.merge(_profile.GROUND_PINS.get(_tileset_number, {}) as Dictionary, true)
	return table


func _pin(tile: int) -> StringName:
	if _pinned.has(tile):
		return _pinned[tile]
	var pinned: StringName = _profile.pinned_class(_tileset_number, tile)
	_pinned[tile] = pinned
	return pinned
