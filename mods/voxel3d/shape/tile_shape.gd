extends RefCounted

## Resolves every graphics tile of a map to an extrusion shape: a generation's
## profile says which tiles are pinned, `classes.gd` what each class is.

const Classes: GDScript = preload("classes.gd")
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
	return Classes.height_of(shape_class)


func art(shape_class: StringName) -> StringName:
	return Classes.art_of(shape_class)


func depth(shape_class: StringName) -> int:
	return Classes.depth_of(shape_class)


func is_round(shape_class: StringName) -> bool:
	return bool(Classes.ROUND.get(shape_class, false))


func is_tufted(shape_class: StringName) -> bool:
	return bool(Classes.TUFTS.get(shape_class, false))


func is_swaying(shape_class: StringName) -> bool:
	return bool(Classes.SWAYS.get(shape_class, false))


func is_model(shape_class: StringName) -> bool:
	return bool(Classes.MODEL.get(shape_class, false))


func outline_shades(shape_class: StringName) -> int:
	return int(Classes.OUTLINE.get(shape_class, 0))


func is_shrub(shape_class: StringName) -> bool:
	return bool(Classes.SHRUB.get(shape_class, false))


func is_potted(shape_class: StringName) -> bool:
	return bool(Classes.POTTED.get(shape_class, false))


func is_rock(shape_class: StringName) -> bool:
	return bool(Classes.ROCK.get(shape_class, false))


func is_column(shape_class: StringName) -> bool:
	return bool(Classes.COLUMN.get(shape_class, false))


func model_stretch(shape_class: StringName) -> float:
	return float(Classes.STRETCH.get(shape_class, 0.0))


func span_cells(shape_class: StringName) -> Vector2i:
	return Classes.SPANS.get(shape_class, Vector2i.ONE)


func is_lying(shape_class: StringName) -> bool:
	return bool(Classes.LYING.get(shape_class, false))


func is_filled(shape_class: StringName) -> bool:
	return bool(Classes.FILLED.get(shape_class, false))


func stem_rows(shape_class: StringName) -> Array:
	if not bool(Classes.STEMS.get(shape_class, false)):
		return []
	return Stems.of_class(shape_class)


func building_part(shape_class: StringName) -> StringName:
	return StringName(Classes.BUILDING.get(shape_class, &""))


func roof_drop(shape_class: StringName) -> int:
	return int(Classes.ROOF_DROP.get(shape_class, 0))


func facade_margin(tile: int) -> Vector2i:
	var table: Dictionary = _profile.FACADE_MARGIN.get(_tileset_number, {})
	return table.get(tile, Vector2i.ZERO)


func is_facade_slope(tile: int) -> bool:
	var tiles: Variant = _profile.FACADE_SLOPE.get(_tileset_number, null)
	return tiles is Array and (tiles as Array).has(tile)


func objects() -> Array:
	return _profile.OBJECTS.get(_tileset_number, [])


func object_outside() -> int:
	return Classes.OUTSIDE


func stairs() -> Array:
	return _profile.STAIRS.get(_tileset_number, [])


func room_wall() -> Array:
	return _profile.ROOM_WALL.get(_tileset_number, [])


func houses() -> Array:
	return _profile.houses(_tileset_number)


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
