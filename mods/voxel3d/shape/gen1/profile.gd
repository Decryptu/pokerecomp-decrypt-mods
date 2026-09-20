extends RefCounted

## The Generation I shape PROFILE: hand-authored pins over the automatic
## resolution in `tile_shape.gd`, keyed by the tileset's cartridge name. `pass.gd` is the generated pass over every tileset, and this one wins
## where the two disagree.

const PASS: GDScript = preload("pass.gd")
const HOUSES: GDScript = preload("houses.gd")

const GROUND: Dictionary = {}

const MOUNDS: Dictionary = {}

const GROUND_PINS: Dictionary = {}

const OBJECTS: Dictionary = {}

const STAIRS: Dictionary = {
	&"REDS_HOUSE_1": [
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
	],
	&"REDS_HOUSE_2": [
		{
			&"tiles": [[10, 11], [26, 27]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"MUSEUM": [
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[10, 11], [26, 27]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"UNDERGROUND": [
		{
			&"tiles": [[3, 4], [19, 20]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
	],
	&"GATE": [
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[10, 11], [26, 27]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"SHIP": [
		{
			&"tiles": [[41, 42], [57, 58]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[39, 40], [55, 56]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"CEMETERY": [
		{
			&"tiles": [[3, 4], [19, 20]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[11, 12], [27, 28]],
			&"down": true,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
	],
	&"MANSION": [
		{
			&"tiles": [[12, 13], [28, 29]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
		{
			&"tiles": [[10, 11], [26, 27]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	&"FACILITY": [
		{
			&"tiles": [[3, 4], [19, 78]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[90, 91], [67, 52]],
			&"down": false,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
		{
			&"tiles": [[11, 12], [27, 28]],
			&"down": true,
			&"step": Vector2i(1, 0),
			&"steps": 4,
		},
	],
}

const CLIFFS: Dictionary = {}
const FRONTS: Dictionary = {}

const LIPS: Dictionary = {}

const FENCES: Dictionary = {
	&"OVERWORLD": [[14], [85]],
}

const ROOM_WALL: Dictionary = {}

const FACADE_MARGIN: Dictionary = {}

const FACADE_SLOPE: Dictionary = {
	&"OVERWORLD": [5, 6, 7, 8, 9, 21, 22, 23, 24, 25],
}

const TILESETS: Dictionary = {
	&"OVERWORLD": {
		&"bush": [64, 65, 80, 81],
		&"facade": [
			4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 21, 22, 23, 24, 25, 26, 27, 28, 31, 34,
			37, 38, 40, 41, 47, 63, 66, 67, 68, 69, 74, 75, 78, 79, 92, 93,
		],
		&"fence": [14, 85],
		&"ledge": [39, 52, 54, 55],
		&"roof": [18, 56, 76, 77, 83, 90],
		&"sapling": [45, 46, 61, 62],
		&"sign_post": [70, 71, 86, 87],
		&"tree_round": [42, 43, 58, 59],
	},
	&"REDS_HOUSE_1": {
		&"desk": [34, 35, 48, 49, 50, 51],
		&"ground": [4, 20],
		&"stand": [6, 7, 22, 23, 40, 54, 55, 56, 57],
		&"stool": [2, 3, 18, 19],
		&"table": [38, 39, 41, 42, 43, 44, 58, 59, 60],
		&"wall": [0, 36, 37, 52, 53],
	},
	&"MART": {
		&"bookcase": [
			23, 29, 40, 44, 45, 46, 47, 62, 63, 64, 65, 67, 68, 69, 71, 76, 77, 78, 79,
			80, 81, 83, 84, 85, 87, 90, 91,
		],
		&"counter": [8, 14, 15, 16, 24, 25, 30, 31, 41, 56, 89],
		&"stand": [32, 33, 34, 35, 48, 49, 50, 51],
		&"void": [0],
	},
	&"FOREST": {
		&"canopy": [4, 5, 6, 7, 21, 22, 23, 35, 36, 37, 38, 39, 53, 54],
		&"ground": [0],
		&"ledge": [46],
		&"sign_post": [33, 34, 49, 50],
		&"tree_round": [2, 3, 18, 19],
	},
	&"REDS_HOUSE_2": {
		&"bed": [45, 46, 47, 61, 62, 63],
		&"lie": [14, 15, 30, 31],
		&"stand": [
			6, 7, 8, 9, 22, 23, 24, 25, 32, 33, 40, 54, 55, 56, 57, 64, 65, 68, 69, 70,
			71,
		],
		&"stool": [2, 3, 18, 19],
		&"table": [38, 39, 41, 42, 43, 44, 50, 51, 58, 59, 60, 66, 67],
		&"wall": [0, 36, 37, 52, 53],
	},
	&"DOJO": {
		&"bookcase": [13, 14, 29, 30],
		&"table": [41, 42, 57, 59, 78, 79],
		&"void": [15],
	},
	&"POKECENTER": {
		&"counter": [8, 10, 24, 25, 36, 37, 38, 39, 42, 43, 52, 53, 56, 90, 91],
		&"planter": [32, 33, 34, 35, 48, 49, 50, 51],
		&"stand": [7, 13, 58, 59, 66, 70, 72, 73, 74, 75, 82, 86],
		&"table": [9, 88],
		&"wall": [
			2, 3, 4, 5, 6, 16, 18, 19, 20, 21, 22, 40, 41, 76, 77, 92, 93, 94, 95,
		],
	},
	&"GYM": {
		&"boulder": [7, 8, 23, 24],
		&"bush": [44, 45, 46, 47],
		&"counter": [88, 89, 90],
		&"ground": [4, 6, 22],
		&"stand": [2, 18, 19, 54, 55, 56, 64, 65, 80, 81, 85, 91, 92, 93, 94, 95],
		&"stool": [11, 12, 27, 28],
		&"wall": [
			5, 13, 14, 15, 16, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39, 41, 42, 48, 49,
			50, 51, 53, 62, 66, 68, 69, 70, 71, 84, 86, 87,
		],
	},
	&"HOUSE": {
		&"desk": [14, 15, 30, 31, 48, 49],
		&"ground": [4, 20],
		&"stand": [8, 9, 10, 11, 24, 25, 26, 27, 70, 71, 86, 87],
		&"stool": [2, 3, 18, 19],
		&"table": [38, 39, 41, 47, 54, 57, 58, 59, 60, 80, 81, 82, 83],
		&"wall": [0, 36, 45, 46, 52, 61, 62, 72, 73, 75, 88, 89, 90, 91],
	},
	&"FOREST_GATE": {
		&"counter": [7, 8, 23, 24, 50, 51],
		&"ground": [4, 20],
		&"planter": [5, 6, 21, 22, 37, 38, 53, 54],
		&"wall": [41, 43, 72, 74],
	},
	&"MUSEUM": {
		&"bookcase": [
			7, 8, 9, 25, 34, 35, 39, 40, 44, 46, 48, 49, 50, 51, 58, 60, 63, 64, 65,
			66, 67, 68, 69, 70, 71, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91,
		],
		&"counter": [23, 24],
		&"ground": [4, 20],
		&"planter": [5, 6, 21, 22, 37, 38, 53, 54],
		&"stand": [76, 77, 92, 93],
		&"stool": [2, 3, 18, 19],
		&"wall": [72, 74, 78, 79],
	},
	&"UNDERGROUND": {
		&"void": [16],
		&"wall": [2, 6, 9, 22, 23],
	},
	&"GATE": {
		&"counter": [7, 8, 9, 23, 24, 50, 51],
		&"desk": [34, 35],
		&"ground": [4, 20],
		&"planter": [5, 6, 21, 22, 37, 38, 53, 54],
		&"stand": [14, 15, 30, 31, 36, 52, 57],
		&"stool": [2, 3, 18, 19],
		&"void": [16],
		&"wall": [0, 32, 33, 41, 43, 45, 58, 61, 62, 72, 74],
	},
	&"SHIP": {
		&"bed": [70, 71, 86, 87],
		&"bookcase": [43, 54],
		&"stool": [7, 8, 23, 24, 66, 67, 72, 73, 88, 89],
		&"table": [9, 10, 11, 12, 25, 26, 28, 44, 53, 59, 60, 64, 65, 68, 69, 80, 81],
		&"void": [1],
		&"wall": [
			2, 3, 5, 6, 14, 15, 16, 17, 18, 19, 21, 22, 30, 31, 32, 33, 34, 37, 38, 45,
			46, 47, 48, 49, 50, 51, 61, 62, 63, 84, 85,
		],
	},
	&"SHIP_PORT": {
		&"roof": [
			0, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24,
			25, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 44, 45, 46, 47,
			48, 51, 52, 53, 54, 55, 56, 57, 61, 62, 64, 65, 66, 67, 68, 69, 77, 78, 79,
			81, 82, 83, 85, 90, 91, 93,
		],
		&"stand": [60, 72, 73, 74, 75, 76, 88, 89],
		&"wall": [1, 49, 80, 86, 87],
	},
	&"CEMETERY": {
		&"counter": [2, 18, 29, 30],
		&"post": [5, 6, 21, 22],
		&"stand": [39, 47, 55, 61, 62, 63],
		&"wall": [9, 10, 17, 25, 26, 32, 48],
	},
	&"INTERIOR": {
		&"bookcase": [7, 8, 9, 10, 23, 24, 25, 26, 39, 40, 41, 42, 55, 56, 57, 58],
		&"counter": [63, 64, 72, 73, 74, 75, 76, 77, 78, 81, 91, 92],
		&"ground": [1, 2, 31, 79, 82],
		&"stand": [17, 18, 33, 34],
		&"stool": [43, 44, 59, 60, 61, 62],
		&"table": [11, 12, 13, 14, 27, 28, 29, 30],
		&"void": [47],
		&"wall": [
			16, 19, 20, 32, 35, 36, 37, 38, 45, 46, 48, 49, 50, 51, 52, 53, 54, 68, 87,
			88, 89, 90, 93, 94,
		],
	},
	&"CAVERN": {
		&"ground": [8, 9, 10, 11, 20, 24, 25, 26, 27, 32, 33, 34, 42, 47],
		&"ledge": [5, 21, 22, 41],
		&"lie": [43, 44, 45, 46],
		&"void": [34, 60],
		&"wall": [
			1, 2, 3, 4, 6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 23, 28, 29, 30, 31, 36,
			37, 38, 39, 40, 49,
		],
	},
	&"LOBBY": {
		&"bookcase": [
			34, 35, 42, 43, 44, 45, 50, 51, 58, 59, 60, 61, 64, 65, 66, 67, 80, 81, 82,
			83,
		],
		&"counter": [9, 21, 25, 36, 37, 38, 39, 41, 48, 49, 52, 53, 54, 57, 85, 86, 87],
		&"ground": [4, 20],
		&"stand": [14, 15, 30, 31],
		&"stool": [7, 8, 23, 24],
		&"void": [16],
		&"wall": [
			1, 2, 3, 6, 18, 19, 22, 33, 46, 47, 62, 63, 68, 70, 71, 72, 73, 75, 76, 77,
			78, 79, 84, 88, 89, 91, 92, 93,
		],
	},
	&"MANSION": {
		&"bookcase": [21, 34, 35, 40, 45, 46, 47, 50, 51, 56, 61, 62, 63, 87],
		&"ground": [4, 20],
		&"stand": [8, 9, 24, 25, 68, 69, 70, 71],
		&"stool": [2, 3, 18, 19],
		&"table": [36, 37, 38, 39, 41, 52, 53, 54, 55, 57, 58, 59, 60, 64, 65, 66, 67],
		&"void": [16],
		&"wall": [
			6, 7, 15, 22, 23, 30, 31, 33, 42, 43, 48, 49, 72, 73, 74, 75, 76, 77, 78,
			79, 80, 88, 89, 90, 91, 92, 93,
		],
	},
	&"LAB": {
		&"bookcase": [
			10, 11, 26, 27, 40, 41, 59, 64, 65, 66, 69, 70, 74, 75, 85, 86, 90, 91,
		],
		&"planter": [50, 51, 67, 68],
		&"stand": [44, 45, 46, 47, 60, 61, 62, 63],
		&"stool": [6, 7, 14, 15, 22, 23, 30, 31],
		&"table": [2, 3, 4, 5, 18, 19, 20, 21, 58, 72, 73, 80, 81, 82, 83, 84],
		&"void": [54],
		&"wall": [
			16, 17, 24, 25, 28, 29, 32, 33, 34, 35, 36, 37, 42, 43, 48, 49, 71, 87, 88,
			89,
		],
	},
	&"CLUB": {
		&"counter": [5, 7, 8, 16, 23, 24, 54, 71, 72, 73, 74],
		&"desk": [55, 56, 57, 58, 59, 60, 61, 62, 64, 65],
		&"ground": [30],
		&"stand": [9, 11, 12, 13, 14, 21, 22, 27, 28, 29],
		&"stool": [38, 39, 42, 43],
		&"wall": [1, 2, 3, 6, 17, 18, 19, 48, 49, 50, 51, 52, 63, 66, 67, 68, 69, 70],
	},
	&"FACILITY": {
		&"bookcase": [40, 41, 56, 57],
		&"bush": [38, 54, 83, 84],
		&"counter": [2, 13, 14, 18, 29, 30, 53, 68, 69],
		&"ground": [20],
		&"stand": [5, 6, 7, 15, 21, 22, 23, 31, 39, 47, 55, 61, 62, 63],
		&"void": [51],
		&"wall": [
			8, 9, 10, 24, 25, 26, 36, 37, 42, 43, 44, 45, 46, 58, 59, 60, 64, 65, 74,
			75, 76, 77, 80, 81, 86, 87, 88, 89,
		],
	},
	&"PLATEAU": {
		&"bookcase": [5, 6, 14, 15],
		&"boulder": [7, 8, 23, 24, 29, 34, 42, 43],
		&"roof": [61, 62, 64, 65, 68],
		&"sign_post": [9, 10, 25, 26],
		&"stand": [16, 18, 37, 38, 40, 41],
		&"wall": [3, 13, 21, 22, 32, 33, 46, 47, 48, 49],
	},
	&"BEACH_HOUSE": {
		&"counter": [50, 51, 66, 67],
		&"ground": [1, 4, 17, 20],
		&"stand": [32, 33, 64, 65],
		&"stool": [2, 3, 18, 19],
		&"table": [38, 39, 41, 42, 43, 44, 54, 55, 56, 57, 58, 59, 60],
		&"wall": [0, 6, 7, 22, 23],
	},
}

const UNPINNED: Dictionary = {}


static func pinned_class(tileset: StringName, tile: int) -> StringName:
	var groups: Variant = TILESETS.get(tileset, null)
	if groups is Dictionary:
		for shape_class: StringName in (groups as Dictionary):
			var tiles: Variant = (groups as Dictionary)[shape_class]
			if tiles is Array and (tiles as Array).has(tile):
				return shape_class
	var taken: Variant = UNPINNED.get(tileset, null)
	if taken is Array and (taken as Array).has(tile):
		return &""
	return PASS.pinned_class(tileset, tile)


static func fence_face(tileset: StringName) -> Array:
	var tiles: Variant = FENCES.get(tileset, null)
	return tiles as Array if tiles is Array else []


static func is_cliff(tileset: StringName, tile: int) -> bool:
	var tiles: Variant = CLIFFS.get(tileset, null)
	return tiles is Array and (tiles as Array).has(tile)


static func is_cliff_front(tileset: StringName, tile: int) -> bool:
	var tiles: Variant = FRONTS.get(tileset, null)
	return tiles is Array and (tiles as Array).has(tile)


static func is_cliff_lip(tileset: StringName, tile: int) -> bool:
	var tiles: Variant = LIPS.get(tileset, null)
	return tiles is Array and (tiles as Array).has(tile)


static func houses(tileset: StringName) -> Array:
	return HOUSES.of_tileset(tileset)
