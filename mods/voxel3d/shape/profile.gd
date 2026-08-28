extends RefCounted

## The shape PROFILE: hand-authored pins over the automatic resolution in
## `tile_shape.gd`, in the spirit of a 3dSen game profile pinning a graphic to
## generated from a full pass over every tileset in the game, and this one wins
const PASS: GDScript = preload("profile_pass.gd")

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

const GROUND: Dictionary = {
	1: {
		&"tree": 5,  # 4517 of 9920
		&"boulder": 61,  # 16 of 80
		&"bush": 5,  # 82 of 91
	},
	2: {
		&"tree": 6,  # 229 of 660
		&"boulder": 76,  # 1 of 1
		&"post": 6,  # 84 of 144
	},
	3: {
		&"sapling": 44,  # 122 of 146
		&"bush": 44,  # 4751 of 7085
		&"post": 44,  # 4285 of 7991
	},
	4: {
		&"tree": 5,  # 90 of 242
	},
	6: {
		&"post": 1,  # 6 of 10
	},
	9: {
		&"boulder": 5,  # 88 of 132
	},
	14: {
		&"sapling": 17,  # 23 of 64
		&"bush": 16,  # 31 of 116
	},
	15: {
		&"sapling": 31,  # 35 of 80
		&"bush": 1,  # 12 of 14
	},
	17: {
		&"bush": 86,  # 28 of 48
	},
	19: {
		&"boulder": 13,  # 11 of 26
		&"stool": 13,  # 81 of 163
	},
	20: {
		&"post": 1,  # 8 of 12
	},
	21: {
		&"post": 17,  # 5 of 6
	},
	23: {
		&"bush": 2,  # 434 of 490
	},
	24: {
		&"boulder": 1,  # 1247 of 1453
	},
	25: {
		&"boulder": 0,  # 10 of 22
		&"canopy": 1,  # 908 of 1128
	},
	27: {
		&"stool": 1,  # 90 of 130
	},
	29: {
		&"boulder": 25,  # 190 of 472
	},
	31: {
		&"sapling": 5,  # 392 of 396
		&"bush": 5,  # 4 of 4
		&"canopy": 5,  # 412 of 418
	},
}

const MOUNDS: Dictionary = {
	3: {
		&"door": [72, 73, 88, 89],
		&"body": [1, 2, 17, 30, 36, 39, 52, 54, 55, 72, 73, 88, 89],
	},
}

const GROUND_PINS: Dictionary = {
	3: {
		&"post": 35,
	},
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
	&"sapling": 1.0,
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

const OBJECTS: Dictionary = {
	13: [
		{
			&"name": &"desk",
			&"tiles": [[42, 43, 44, 45], [58, 59, 60, 61], [74, 75, 76, 77]],
			&"window": Rect2i(0, 0, 32, 22),
			&"top": 16,
			&"depth": 16,
			&"height": 6,
		},
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
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
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
		{
			&"name": &"chair",
			&"tiles": [[64, 65], [80, 81]],
			&"window": Rect2i(2, 3, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
		{
			&"name": &"bench",
			&"tiles": [[10, 11, 12, 13], [26, 27, 28, 29], [37, 38, 38, 39]],
			&"window": Rect2i(0, 0, 32, 24),
			&"top": 16,
			&"depth": 16,
			&"height": 8,
			&"wrap": true,
			&"foot": true,
		},
		{
			&"name": &"terminal",
			&"tiles": [[10, 11], [26, 27]],
			&"window": Rect2i(0, 0, 16, 15),
			&"top": 0,
			&"depth": 8,
			&"height": 12,
			&"rise": 8,
			&"cap": 4,
		},
		{
			&"name": &"bookcase",
			&"tiles": [[5, 7], [3, 4], [3, 4], [53, 54]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 8,
			&"depth": 16,
			&"height": 24,
			&"box": true,
			&"foot": true,
		},
		{
			&"name": &"bin",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(2, 1, 11, 14),
			&"top": 7,
			&"depth": 11,
			&"height": 8,
			&"bin": true,
		},
		{
			&"name": &"bench_long",
			&"tiles": [
				[5, 6, 6, 6, 6, 7],
				[21, 22, 22, 22, 22, 23],
				[37, 38, 38, 38, 38, 39],
			],
			&"window": Rect2i(0, 0, 48, 24),
			&"top": 16,
			&"depth": 16,
			&"height": 8,
			&"wrap": true,
			&"foot": true,
		},
	],
	17: [
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
		{
			&"name": &"vessel",
			&"tiles": [[80, 81], [82, 83]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 8,
			&"depth": 8,
			&"height": 8,
			&"filled": true,
		},
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
		{
			&"name": &"fountain",
			&"tiles": [[76, 77, 78], [92, 93, 94]],
			&"window": Rect2i(3, 0, 18, 16),
			&"height": 12,
			&"model": true,
			&"outline": 2,
		},
		{
			&"name": &"bench",
			&"tiles": [[7, 8, 9, 10], [23, 24, 25, 26], [39, 40, 41, 42]],
			&"window": Rect2i(0, 0, 32, 21),
			&"top": 0,
			&"depth": 13,
			&"height": 17,
			&"seat": true,
		},
		{
			&"name": &"bin",
			&"tiles": [[90, 91], [19, 130]],
			&"window": Rect2i(2, 1, 11, 14),
			&"top": 8,
			&"depth": 11,
			&"height": 10,
			&"bin": true,
		},
	],
	29: [
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
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 13, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
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
		{
			&"name": &"bicycle",
			&"tiles": [[12, 13, 14, -1], [28, 29, 30, 31]],
			&"window": Rect2i(0, 0, 32, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
		{
			&"name": &"pillar",
			&"tiles": [[193, 194], [195, 196], [197, 198], [197, 198]],
			&"window": Rect2i(0, 0, 16, 32),
			&"height": 32,
			&"model": true,
		},
	],
	22: [
		{
			&"name": &"seat",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 10,
			&"depth": 10,
			&"height": 6,
		},
	],
	1: [
		{
			&"name": &"bell_tower",
			&"tiles": [
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[59, 26, 39, 40, 149, 150, 28, 61],
				[59, 151, 41, 42, 152, 152, 153, 61],
				[59, 6, 6, 6, 6, 6, 6, 61],
				[75, 76, 154, 154, 76, 76, 76, 77],
			],
			&"window": Rect2i(0, 0, 64, 128),
			&"filled": true,
			&"top": 0,
			&"cap": 8,
			&"depth": 64,
			&"height": 128,
		},
		{
			&"name": &"sprout_tower",
			&"tower": true,
			&"door": [2, 3],
			&"axis": 7,
			&"layers": [
				{&"tiles": 2, &"half": 3, &"art": [1, 8, 6, 2]},
				{&"tiles": 1, &"half": 4, &"top_half": 3, &"art": [1, 7, 6, 1]},
				{&"tiles": 2, &"half": 3, &"art": [1, 6, 6, 1]},
				{&"tiles": 1, &"half": 4, &"top_half": 3, &"art": [1, 5, 6, 1]},
				{&"tiles": 2, &"half": 3, &"art": [1, 4, 6, 1]},
				{&"tiles": 1, &"half": 4, &"top_half": 2, &"art": [1, 3, 6, 1],
					&"top": [0, 0, 8, 4]},
			],
			&"tiles": [
				[49, 83, 83, 83, 83, 83, 83, 52],
				[65, 83, 83, 83, 83, 83, 83, 68],
				[65, 83, 83, 83, 83, 83, 83, 68],
				[81, 82, 82, 82, 82, 82, 82, 84],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[34, 65, 148, 149, 149, 150, 68, 37],
				[80, 81, 82, 82, 82, 82, 84, 85],
				[59, 26, 39, 40, 149, 150, 28, 61],
				[59, 151, 41, 42, 152, 152, 153, 61],
				[59, 6, 6, 6, 6, 6, 6, 61],
				[75, 76, 154, 154, 76, 76, 76, 77],
			],
			&"window": Rect2i(0, 0, 64, 80),
			&"filled": true,
			&"top": 0,
			&"depth": 64,
			&"height": 80,
		},
	],
	6: [
		{
			&"name": &"table",
			&"tiles": [
				[35, 34, 34, 36],
				[37, 21, 21, 53],
				[37, 21, 21, 53],
				[51, 50, 50, 52],
				[28, 64, 64, 29],
			],
			&"window": Rect2i(0, 0, 32, 40),
			&"top": 32,
			&"depth": 32,
			&"height": 8,
			&"wrap": true,
			&"foot": true,
		},
		{
			&"name": &"terminal",
			&"tiles": [[64, 65], [32, 33], [66, 67]],
			&"window": Rect2i(0, 0, 16, 24),
			&"depth": 12,
			&"height": 30,
			&"terminal": true,
		},
		{
			&"name": &"carving",
			&"tiles": [[34, 35], [82, 83], [37, 53]],
			&"window": Rect2i(0, 0, 16, 24),
			&"solid": true,
			&"top": 0,
			&"depth": 12,
			&"height": 24,
			&"wrap": true,
			&"rise": 8,
		},
		{
			&"name": &"stool",
			&"tiles": [[2, 3], [18, 19]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 12,
			&"height": 8,
			&"stool": true,
		},
		{
			&"name": &"half_wall",
			&"tiles": [
				[37, 53], [37, 53], [37, 53], [37, 53], [37, 53], [51, 52],
				[17, 17], [17, 17],
			],
			&"window": Rect2i(0, 0, 16, 64),
			&"solid": true,
			&"top": 48,
			&"depth": 48,
			&"height": 16,
		},
		{
			&"name": &"television_stand",
			&"tiles": [[6, 7], [22, 23], [8, 9]],
			&"window": Rect2i(0, 0, 16, 24),
			&"filled": true,
			&"top": 0,
			&"depth": 14,
			&"height": 20,
		},
		{
			&"name": &"fridge",
			&"tiles": [[10, 11], [26, 27], [42, 43]],
			&"window": Rect2i(0, 0, 16, 24),
			&"top": 8,
			&"depth": 16,
			&"height": 16,
		},
		{
			&"name": &"sink",
			&"tiles": [[67, 69], [24, 25]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 8,
			&"depth": 16,
			&"height": 16,
		},
		{
			&"name": &"hob",
			&"tiles": [[80, 81], [82, 83]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 8,
			&"depth": 16,
			&"height": 16,
		},
		{
			&"name": &"drawers",
			&"tiles": [[14, 15], [58, 59]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 8,
			&"depth": 16,
			&"height": 16,
		},
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
	7: [
		{
			&"name": &"counter",
			&"tiles": [
				[52, 52, 52, 52, 12, 12, 52, 52, 52, 12],
				[36, 36, 36, 36, 36, 36, 36, 36, 36, 36],
			],
			&"window": Rect2i(0, 0, 80, 16),
			&"solid": true,
			&"top": 8,
			&"depth": 8,
			&"height": 8,
		},
		{
			&"name": &"counter_till",
			&"tiles": [[3, 37], [19, 53], [70, 71]],
			&"window": Rect2i(0, 0, 16, 24),
			&"solid": true,
			&"top": 16,
			&"depth": 16,
			&"height": 8,
		},
		{
			&"name": &"counter_wall",
			&"tiles": [[15], [15], [37]],
			&"window": Rect2i(0, 0, 8, 24),
			&"solid": true,
			&"top": 24,
			&"depth": 24,
			&"height": 8,
		},
		{
			&"name": &"machine_desk",
			&"tiles": [[60, 61, 61, 63, 10, 11], [76, 77, 78, 79, 26, 27]],
			&"window": Rect2i(0, 0, 48, 16),
			&"solid": true,
			&"top": 8,
			&"depth": 8,
			&"height": 8,
		},
		{
			&"name": &"healing_machine",
			&"tiles": [[28, 29, 30, 31], [44, 45, 46, 47]],
			&"window": Rect2i(0, 0, 32, 16),
			&"solid": true,
			&"top": 0,
			&"depth": 12,
			&"height": 16,
			&"rise": 8,
			&"cap": 4,
		},
		{
			&"name": &"desk_screen",
			&"tiles": [[4, 5], [20, 21]],
			&"window": Rect2i(0, 0, 16, 16),
			&"solid": true,
			&"top": 0,
			&"depth": 8,
			&"height": 16,
			&"rise": 8,
			&"cap": 4,
		},
		{
			&"name": &"pc",
			&"tiles": [[32, 33], [48, 49], [64, 65]],
			&"window": Rect2i(0, 0, 16, 24),
			&"solid": true,
			&"top": 0,
			&"depth": 16,
			&"height": 24,
			&"wrap": true,
			&"cap": 4,
		},
		{
			&"name": &"chair",
			&"tiles": [[72, 73], [88, 89]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 12,
			&"depth": 12,
			&"height": 4,
			&"wrap": true,
		},
	],
	12: [
		{
			&"name": &"shelf_glass",
			&"tiles": [[12, 13], [86, 87], [88, 89], [90, 91]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 8,
			&"depth": 16,
			&"height": 24,
			&"box": true,
			&"foot": true,
		},
		{
			&"name": &"shelf_low",
			&"tiles": [[12, 13], [80, 81], [80, 81], [94, 95]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 8,
			&"depth": 16,
			&"height": 24,
			&"box": true,
			&"foot": true,
		},
		{
			&"name": &"shelf_wide",
			&"tiles": [
				[64, 65, 66, 43], [80, 81, 82, 69], [67, 68, 92, 93], [83, 84, 31, 85],
			],
			&"window": Rect2i(0, 0, 32, 32),
			&"top": 8,
			&"depth": 16,
			&"height": 24,
			&"box": true,
			&"foot": true,
		},
		{
			&"name": &"shelf_side",
			&"tiles": [[38, 39], [54, 55], [40, 41], [56, 57]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 8,
			&"depth": 16,
			&"height": 24,
			&"box": true,
			&"foot": true,
			&"turn": true,
		},
		{
			&"name": &"counter_back",
			&"tiles": [
				[42, 43], [62, 63], [62, 63], [32, 33], [48, 49], [62, 63], [62, 63],
				[30, 47], [26, 25],
			],
			&"window": Rect2i(0, 0, 16, 72),
			&"solid": true,
			&"top": 64,
			&"depth": 64,
			&"height": 8,
		},
		{
			&"name": &"counter_hidden",
			&"tiles": [[12, 13, 12, 13], [80, 81, 80, 81]],
			&"art": [[30, 47, 30, 47], [26, 25, 26, 25]],
			&"window": Rect2i(0, 0, 32, 16),
			&"solid": true,
			&"top": 8,
			&"depth": 8,
			&"height": 8,
		},
	],
	5: [
		{
			&"name": &"table",
			&"tiles": [
				[38, 39, 39, 41],
				[54, 47, 47, 57],
				[5, 47, 47, 21],
				[60, 58, 58, 59],
			],
			&"window": Rect2i(0, 0, 32, 32),
			&"top": 24,
			&"depth": 24,
			&"height": 8,
			&"wrap": true,
			&"foot": true,
		},
		{
			&"name": &"terminal",
			&"tiles": [[64, 65], [32, 33], [66, 67]],
			&"window": Rect2i(0, 0, 16, 24),
			&"depth": 12,
			&"height": 30,
			&"terminal": true,
		},
		{
			&"name": &"carving",
			&"tiles": [[34, 35], [82, 83], [37, 53]],
			&"window": Rect2i(0, 0, 16, 24),
			&"solid": true,
			&"top": 0,
			&"depth": 12,
			&"height": 24,
			&"wrap": true,
			&"rise": 8,
		},
		{
			&"name": &"stool",
			&"tiles": [[2, 3], [18, 19]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 12,
			&"height": 8,
			&"stool": true,
		},
	],
}

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
		{
			&"tiles": [[68, 69], [84, 85]],
			&"down": false,
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
		{
			&"tiles": [[145, 145], [142, 142]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 5,
		},
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
		{
			&"tiles": [[32, 33], [48, 49]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
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
		{
			&"tiles": [[32, 33], [48, 49]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
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
		{
			&"tiles": [[84, 86], [88, 89]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
	],
}

const CLIFFS: Dictionary = {
	1: [76, 59, 61, 75, 77, 43, 45, 70, 71, 86, 87],
	2: [76, 59, 61, 75, 77, 43, 45],
	3: [55, 19, 53, 36, 39, 30, 2],
	4: [44, 45, 60, 61, 75, 76, 77, 43, 59],
}
const FRONTS: Dictionary = {
	1: [76],
	2: [76],
	3: [55, 19, 53],
	4: [44],
}

const LIPS: Dictionary = {
	3: [1],
	1: [44],
	2: [44],
}

const FENCES: Dictionary = {
	1: [[90], [89]],
	2: [[90], [89]],
	4: [[90], [89]],
	25: [[35, 36], [51, 52]],
}

const ROOM_WALL: Dictionary = {
	10: [[1, 1]],
	6: [[17]],
	7: [[2]],
	12: [[17]],
	5: [[0]],
	8: [[92, 93], [16, 16]],
	23: [[17], [33]],
	15: [[37, 39], [53, 55]],
	16: [[17]],
	28: [[4], [20]],
	11: [[65], [77]],
	14: [[2]],
	30: [[38]],
	24: [[38]],
	19: [[94, 95], [74, 75]],
	26: [[8, 9], [10, 11]],
	13: [[138, 139], [154, 155]],
	27: [[17], [16]],
	29: [[132, 133], [148, 149]],
	17: [[48]],
	22: [[84, 85], [80, 81]],
	18: [[70, 71], [86, 87]],
	20: [[2]],
	21: [[2]],
	1: [[61]],
	33: [[6]],
	34: [[6]],
	35: [[6]],
	36: [[6]],
}

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

const FACADE_MARGIN: Dictionary = {
	3: {
		31: Vector2i(0, 5),
		60: Vector2i(0, 5),
		15: Vector2i(5, 0),
		29: Vector2i(5, 0),
	},
}

const FACADE_SLOPE: Dictionary = {
	1: [49, 52, 54, 65, 68, 72, 81, 82, 83, 84],
	4: [10, 11, 12, 13, 14, 15, 16, 17, 18],
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

const TILESETS: Dictionary = {
	3: {
		&"post": [42, 43, 58, 59, 14, 85],
		&"flower": [3],
		&"sign_post": [70, 71, 86, 87],
		&"railing": [16, 32],
		&"knob": [33],
		&"bush": [64, 65, 80, 81],
		&"sapling": [45, 46, 61, 62],
		&"ground": [17, 44, 57, 4],
		&"tall_grass": [82],
		&"ledge": [52, 54],
		&"facade": [
			10, 11, 12, 15, 26, 27, 28, 29, 31, 34, 35, 47, 50, 60, 63,
			66, 67, 68, 69, 74, 75,
		],
		&"roof": [7, 18, 23, 76, 77, 78, 83, 90, 92, 93, 94, 95],
		&"roof_edge": [6, 8, 22, 24, 38, 40, 56],
		&"roof_corner": [5, 9, 21, 25, 37, 41],
	},
	5: {
		&"table": [5, 21, 38, 39, 41, 47, 50, 51, 54, 57, 58, 59, 60, 70, 71, 86, 87],
		&"bookcase": [14, 15, 48, 49],
		&"tombstone": [40, 55, 56, 63, 78],
		&"flowers": [42, 43, 94, 95, 84, 85],
		&"planter": [8, 9, 10, 11, 24, 25, 26, 27],
	},
	1: {
		&"ground": [154],
		&"wall": [70, 71, 86, 87],
		&"fence": [74, 89, 90],
		&"flower": [3],
		&"tall_grass": [4],
		&"facade": [7],
		&"sign_post": [78, 79, 94, 95],
		&"sea_rock": [88],
		&"tree": [30, 31, 46, 47, 62, 63],
	},
	2: {
		&"ground": [91],
		&"tall_grass": [4],
		&"tree": [30, 31, 19, 21, 62, 63],
		&"sea_rock": [88],
		&"fence": [74, 89, 90],
	},
	4: {
		&"tree": [30, 31, 19, 21, 62, 63],
		&"sign_post": [78, 79, 94, 95],
		&"fence": [74, 89, 90],
	},
	9: {
		&"sea_rock": [1, 2, 17, 18],
		&"statue_pillar": [6, 7, 22, 23, 8, 9, 24, 25],
	},
	24: {
		&"boulder": [12, 13, 28, 29],
	},
	29: {
		&"boulder": [196, 197, 212, 213],
	},
	30: {
		&"ground": [14, 15, 30, 31],
	},
	17: {
		&"tall_grass": [87],
		&"statue_pillar": [72, 73, 88, 89, 74, 75, 90, 91, 16, 1],
	},
	31: {
		&"canopy": [
			12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63,
		],
	},
	25: {
		&"canopy": [
			12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63,
		],
		&"flower": [3],
		&"fence": [5, 27, 35, 36, 37, 38, 43, 51, 52, 53, 54, 67, 83],

		&"kerb": [21, 55, 56, 57, 71, 73, 87, 88, 89],
		&"notice_case": [69, 70, 85, 86],
	},
	14: {
		&"statue_pillar": [66, 67, 82, 83, 68, 69, 84, 85],
	},
	15: {
		&"statue_pillar": [32, 33, 48, 49, 34, 35, 50, 51],
	},
	23: {
		&"idol": [34, 35, 50, 51, 18, 19, 54, 55, 74, 75, 90, 91, 76, 92],
	},
	18: {
		&"statue_pillar": [152, 153, 154, 155, 156, 157, 158, 159],
	},
	10: {
		&"statue_pillar": [76, 77, 92, 93, 78, 79, 94, 95],
	},
	26: {
		&"idol": [14, 15, 30, 31, 46, 47, 62, 63],
	},
	13: {
		&"ground": [165, 181],
		&"planter": [46, 47, 94, 95],
	},
	19: {
		&"stool": [7, 8, 23, 24],
		&"boulder": [72, 73, 88, 89],
	},
	27: {
		&"stool": [44, 45, 60, 61, 39, 40, 55, 56],
	},
	6: {
		&"stool": [2, 3, 18, 19],
	},
	16: {
		&"railing": [64, 65],
		&"ground": [16],
	},
	11: {
		&"planter": [44, 45, 60, 61, 46, 47, 62, 63],
	},
	28: {
		&"planter": [
			30, 31, 46, 47, 62, 63,
			69, 70, 85, 86, 7, 8, 23, 24, 9, 25, 48, 49,
		],
	},
	12: {
		&"planter": [74, 75, 8, 9, 137, 138, 167, 168],
	},
	21: {
		&"palm": [174, 175, 190, 191, 206, 207, 222, 223],
	},
}

const UNPINNED: Dictionary = {
	13: [162],
	17: [55, 56],
	23: [80, 81],
}


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


static func height_of(shape_class: StringName) -> int:
	return int(HEIGHTS.get(shape_class, 0))


static func art_of(shape_class: StringName) -> StringName:
	return StringName(ART.get(shape_class, &"flat"))


static func depth_of(shape_class: StringName) -> int:
	return int(DEPTHS.get(shape_class, 4))
