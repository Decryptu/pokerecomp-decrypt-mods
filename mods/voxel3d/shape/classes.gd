extends RefCounted

## The shape vocabulary: what each class stands, wears and measures. A profile
## pins a generation's tiles to these names.

const HEIGHTS: Dictionary = {
	&"ground": 0,
	&"water": -8,
	&"sea_rock": -8,
	&"void": 0,
	&"ledge": 8,
	&"wall": 16,
	&"fence": 8,
	&"kerb": 8,
	&"sign": 16,
	&"roof": 24,
	&"cliff": 32,
	&"counter": 8,
	&"table": 8,
	&"desk": 16,
	&"bed": 8,
	&"bookcase": 24,
	&"facade": 16,
	&"roof_edge": 24,
	&"roof_corner": 24,
	&"post": 0,
	&"sign_post": 0,
	&"notice_case": 0,
	&"bush": 0,
	&"sapling": 0,
	&"tombstone": 0,
	&"flowers": 0,
	&"flower": 0,
	&"planter": 0,
	&"palm": 0,
	&"statue": 0,
	&"statue_pillar": 0,
	&"idol": 0,
	&"stand": 0,
	&"lie": 0,
	&"stool": 0,
	&"canopy": 0,
	&"tree": 0,
	&"boulder": 0,
	&"railing": 8,
	&"surface": 16,
	&"on_furniture": 0,
	&"stairs": 0,
	&"tall_grass": 0,
}

const DEPTHS: Dictionary = {
	&"post": 8,
	&"knob": 8,
	&"sign_post": 3,
	&"notice_case": 3,
	&"bush": 7,
	&"sapling": 14,
	&"tombstone": 5,
	&"flowers": 12,
	&"flower": 12,
	&"planter": 12,
	&"palm": 12,
	&"statue": 10,
	&"statue_pillar": 16,
	&"idol": 16,
	&"stand": 8,
	&"lie": 12,
	&"boulder": 16,
	&"sea_rock": 8,
	&"stool": 16,
}

const STEMS: Dictionary = {
	&"flower": true,
}

const ROUND: Dictionary = {
	&"post": true,
	&"bush": true,
	&"sapling": true,
	&"flowers": true,
	&"flower": true,
	&"planter": true,
	&"palm": true,
	&"statue": true,
	&"statue_pillar": true,
	&"stand": true,
	&"lie": true,
	&"canopy": true,
	&"boulder": true,
	&"sea_rock": true,
	&"stool": true,
}

const OUTLINE: Dictionary = {
	&"canopy": 1,
	&"tree": 1,
	&"bush": 1,
	&"sapling": 1,
	&"boulder": 1,
	&"sea_rock": 1,
	&"post": 1,
	&"stool": 1,
	&"sign_post": 2,
	&"notice_case": 2,
	&"idol": 1,
}

const TUFTS: Dictionary = {
	&"tall_grass": true,
}

const SWAYS: Dictionary = {
	&"flower": true,
}

const MODEL: Dictionary = {
	&"canopy": true,
	&"tree": true,
	&"bush": true,
	&"sapling": true,
	&"boulder": true,
	&"sea_rock": true,
	&"stool": true,
	&"planter": true,
	&"palm": true,
	&"post": true,
}

const SHRUB: Dictionary = {
	&"bush": true,
	&"boulder": true,
	&"sea_rock": true,
	&"stool": true,
	&"post": true,
}

const POTTED: Dictionary = {
	&"planter": true,
	&"palm": true,
}

const STRETCH: Dictionary = {
	&"stool": 0.6,
	&"sea_rock": 0.5,
	&"sapling": 1.35,
	&"post": 0.71,
}

const ROCK: Dictionary = {
	&"boulder": true,
	&"sea_rock": true,
	&"stool": true,
	&"post": true,
}

const COLUMN: Dictionary = {
	&"post": true,
}

const SPANS: Dictionary = {
	&"planter": Vector2i(1, 2),
	&"palm": Vector2i(1, 2),
	&"flowers": Vector2i(1, 2),
	&"canopy": Vector2i(2, 2),
	&"tree": Vector2i(1, 2),
	&"statue_pillar": Vector2i(1, 2),
	&"idol": Vector2i(1, 2),
}

const LYING: Dictionary = {
	&"flowers": true,
	&"lie": true,
}

const FILLED: Dictionary = {
	&"sign_post": true,
	&"boulder": true,
	&"stool": true,
	&"flower": true,
	&"palm": true,
	&"idol": true,
}

const OUTSIDE: int = -2

## The house paint alphabet, one character per pixel of a drawing. There is no
## character for a DOOR: a door is a wall you walk through, and walking through
## is collision, which nothing here touches. None for a SLOPE either: the top of
## a column's wall is that column's roof height.
const HOUSE_NONE := "."
const HOUSE_WALL := "W"
const HOUSE_ROOF := "R"
const HOUSE_FRONT := "F"

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

const ART: Dictionary = {
	&"ground": &"flat",
	&"water": &"flat",
	&"sea_rock": &"flat",
	&"void": &"flat",
	&"ledge": &"top",
	&"roof": &"top",
	&"bed": &"top",
	&"wall": &"upright",
	&"fence": &"fence",
	&"sign": &"upright",
	&"cliff": &"upright",
	&"counter": &"upright",
	&"kerb": &"upright",
	&"table": &"upright",
	&"desk": &"upright",
	&"bookcase": &"upright",
	&"facade": &"upright",
	&"on_furniture": &"upright",
	&"stairs": &"flat",
	&"tall_grass": &"flat",
	&"roof_edge": &"top",
	&"roof_corner": &"top",
	&"post": &"cutout",
	&"knob": &"ball",
	&"sign_post": &"cutout",
	&"notice_case": &"cutout",
	&"bush": &"cutout",
	&"sapling": &"cutout",
	&"tombstone": &"cutout",
	&"flowers": &"cutout",
	&"flower": &"cutout",
	&"planter": &"cutout",
	&"palm": &"cutout",
	&"statue": &"cutout",
	&"statue_pillar": &"cutout",
	&"idol": &"cutout",
	&"stand": &"cutout",
	&"lie": &"cutout",
	&"boulder": &"cutout",
	&"stool": &"cutout",
	&"railing": &"railing",
	&"canopy": &"cutout",
	&"tree": &"cutout",
	&"surface": &"top",
}


static func height_of(shape_class: StringName) -> int:
	return int(HEIGHTS.get(shape_class, 0))


static func art_of(shape_class: StringName) -> StringName:
	return StringName(ART.get(shape_class, &"flat"))


static func depth_of(shape_class: StringName) -> int:
	return int(DEPTHS.get(shape_class, 4))
