extends RefCounted

## The Generation II shape PROFILE: hand-authored pins over the automatic
## resolution in `tile_shape.gd`, in the spirit of a 3dSen game profile pinning a
## graphic to a geometry. `pass.gd` is the generated pass over every tileset, and
## this one wins where the two disagree.

const PASS: GDScript = preload("pass.gd")
const HOUSES: GDScript = preload("houses.gd")

const GROUND: Dictionary = {
	&"JOHTO": {
		&"tree": 5,  # 4517 of 9920
		&"boulder": 61,  # 16 of 80
		&"bush": 5,  # 82 of 91
	},
	&"JOHTO_MODERN": {
		&"tree": 6,  # 229 of 660
		&"boulder": 76,  # 1 of 1
		&"post": 6,  # 84 of 144
	},
	&"KANTO": {
		&"sapling": 44,  # 122 of 146
		&"bush": 44,  # 4751 of 7085
		&"post": 44,  # 4285 of 7991
	},
	&"BATTLE_TOWER_OUTSIDE": {
		&"tree": 5,  # 90 of 242
	},
	&"PLAYERS_HOUSE": {
		&"post": 1,  # 6 of 10
	},
	&"PORT": {
		&"boulder": 5,  # 88 of 132
	},
	&"GAME_CORNER": {
		&"sapling": 17,  # 23 of 64
		&"bush": 16,  # 31 of 116
	},
	&"ELITE_FOUR_ROOM": {
		&"sapling": 31,  # 35 of 80
		&"bush": 1,  # 12 of 14
	},
	&"TRAIN_STATION": {
		&"bush": 86,  # 28 of 48
	},
	&"LIGHTHOUSE": {
		&"boulder": 13,  # 11 of 26
		&"stool": 13,  # 81 of 163
	},
	&"PLAYERS_ROOM": {
		&"post": 1,  # 8 of 12
	},
	&"POKECOM_CENTER": {
		&"post": 17,  # 5 of 6
	},
	&"TOWER": {
		&"bush": 2,  # 434 of 490
	},
	&"CAVE": {
		&"boulder": 1,  # 1247 of 1453
	},
	&"PARK": {
		&"boulder": 0,  # 10 of 22
		&"canopy": 1,  # 908 of 1128
	},
	&"RADIO_TOWER": {
		&"stool": 1,  # 90 of 130
	},
	&"ICE_PATH": {
		&"boulder": 25,  # 190 of 472
	},
	&"FOREST": {
		&"sapling": 5,  # 392 of 396
		&"bush": 5,  # 4 of 4
		&"canopy": 5,  # 412 of 418
	},
}

const MOUNDS: Dictionary = {
	&"KANTO": {
		&"door": [72, 73, 88, 89],
		&"body": [1, 2, 17, 30, 36, 39, 52, 54, 55, 72, 73, 88, 89],
	},
}

const GROUND_PINS: Dictionary = {
	&"KANTO": {
		&"post": 35,
	},
}

const OBJECTS: Dictionary = {
	&"MANSION": [
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
	&"PORT": [
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
	&"GAME_CORNER": [
		{
			&"name": &"chair",
			&"tiles": [[10, 11], [26, 27]],
			&"window": Rect2i(2, 3, 12, 11),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	&"CAVE": [
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 9, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
		{
			&"name": &"ladder",
			&"tiles": [[42, 43], [58, 59]],
			&"window": Rect2i(3, 0, 9, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	&"FACILITY": [
		{
			&"name": &"chair",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	&"GATE": [
		{
			&"name": &"chair",
			&"tiles": [[84, 85], [86, 87]],
			&"window": Rect2i(2, 2, 12, 12),
			&"top": 0,
			&"depth": 6,
			&"height": 6,
		},
	],
	&"LAB": [
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
	&"TRAIN_STATION": [
		{
			&"name": &"ticket_gate",
			&"tiles": [[53, 54], [55, 56], [57, 58], [59, 60]],
			&"window": Rect2i(0, 0, 16, 32),
			&"top": 24,
			&"depth": 24,
			&"height": 8,
		},
	],
	&"RUINS_OF_ALPH": [
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
	&"TOWER": [
		{
			&"name": &"ridge",
			&"tiles": [[80, 81]],
			&"window": Rect2i(0, 0, 16, 8),
			&"top": 8,
			&"depth": 8,
			&"height": 8,
		},
	],
	&"PARK": [
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
	&"ICE_PATH": [
		{
			&"name": &"ladder",
			&"tiles": [[10, 11], [26, 27]],
			&"window": Rect2i(3, 0, 9, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	&"DARK_CAVE": [
		{
			&"name": &"ladder",
			&"tiles": [[40, 41], [56, 57]],
			&"window": Rect2i(3, 0, 9, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
		{
			&"name": &"ladder",
			&"tiles": [[42, 43], [58, 59]],
			&"window": Rect2i(3, 0, 9, 16),
			&"top": 0,
			&"depth": 3,
			&"height": 16,
		},
	],
	&"CHAMPIONS_ROOM": [
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
	&"BATTLE_TOWER_INSIDE": [
		{
			&"name": &"seat",
			&"tiles": [[14, 15], [30, 31]],
			&"window": Rect2i(0, 0, 16, 16),
			&"top": 10,
			&"depth": 10,
			&"height": 6,
		},
	],
	&"JOHTO": [
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
	&"PLAYERS_HOUSE": [
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
	&"POKECENTER": [
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
	&"MART": [
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
	&"HOUSE": [
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
	&"HOUSE": [
		{
			&"tiles": [[76, 77], [92, 93]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"PLAYERS_HOUSE": [
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
	&"POKECENTER": [
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
	&"GATE": [
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
	&"PORT": [
		{
			&"tiles": [[3, 4], [30, 31]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"FACILITY": [
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
	&"MANSION": [
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
	&"ELITE_FOUR_ROOM": [
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
	&"TRADITIONAL_HOUSE": [
		{
			&"tiles": [[76, 77], [92, 93]],
			&"down": true,
			&"step": Vector2i(-1, 0),
			&"steps": 4,
		},
	],
	&"CHAMPIONS_ROOM": [
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
	&"LIGHTHOUSE": [
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
	&"PLAYERS_ROOM": [
		{
			&"tiles": [[64, 65], [80, 81]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	&"TOWER": [
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
	&"CAVE": [
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
	&"RADIO_TOWER": [
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
	&"UNDERGROUND": [
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
	&"ICE_PATH": [
		{
			&"tiles": [[174, 175], [190, 191]],
			&"down": false,
			&"step": Vector2i(0, -1),
			&"steps": 4,
		},
	],
	&"DARK_CAVE": [
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
	&"OMANYTE_WORD_ROOM": [
		{
			&"tiles": [[84, 86], [88, 89]],
			&"down": true,
			&"step": Vector2i(0, -1),
			&"steps": 0,
		},
	],
}

const CLIFFS: Dictionary = {
	&"JOHTO": [76, 59, 61, 75, 77, 43, 45, 70, 71, 86, 87],
	&"JOHTO_MODERN": [76, 59, 61, 75, 77, 43, 45],
	&"KANTO": [55, 19, 53, 36, 39, 30, 2],
	&"BATTLE_TOWER_OUTSIDE": [44, 45, 60, 61, 75, 76, 77, 43, 59],
}

const FRONTS: Dictionary = {
	&"JOHTO": [76],
	&"JOHTO_MODERN": [76],
	&"KANTO": [55, 19, 53],
	&"BATTLE_TOWER_OUTSIDE": [44],
}

const LIPS: Dictionary = {
	&"KANTO": [1],
	&"JOHTO": [44],
	&"JOHTO_MODERN": [44],
}

const FENCES: Dictionary = {
	&"JOHTO": [[90], [89]],
	&"JOHTO_MODERN": [[90], [89]],
	&"BATTLE_TOWER_OUTSIDE": [[90], [89]],
	&"PARK": [[35, 36], [51, 52]],
}

const ROOM_WALL: Dictionary = {
	&"LAB": [[1, 1]],
	&"PLAYERS_HOUSE": [[17]],
	&"POKECENTER": [[2]],
	&"MART": [[17]],
	&"HOUSE": [[0]],
	&"GATE": [[92, 93], [16, 16]],
	&"TOWER": [[17], [33]],
	&"ELITE_FOUR_ROOM": [[37, 39], [53, 55]],
	&"TRADITIONAL_HOUSE": [[17]],
	&"UNDERGROUND": [[4], [20]],
	&"FACILITY": [[65], [77]],
	&"GAME_CORNER": [[2]],
	&"DARK_CAVE": [[38]],
	&"CAVE": [[38]],
	&"LIGHTHOUSE": [[94, 95], [74, 75]],
	&"RUINS_OF_ALPH": [[8, 9], [10, 11]],
	&"MANSION": [[138, 139], [154, 155]],
	&"RADIO_TOWER": [[17], [16]],
	&"ICE_PATH": [[132, 133], [148, 149]],
	&"TRAIN_STATION": [[48]],
	&"BATTLE_TOWER_INSIDE": [[84, 85], [80, 81]],
	&"CHAMPIONS_ROOM": [[70, 71], [86, 87]],
	&"PLAYERS_ROOM": [[2]],
	&"POKECOM_CENTER": [[2]],
	&"JOHTO": [[61]],
	&"HO_OH_WORD_ROOM": [[6]],
	&"KABUTO_WORD_ROOM": [[6]],
	&"OMANYTE_WORD_ROOM": [[6]],
	&"AERODACTYL_WORD_ROOM": [[6]],
}

const FACADE_MARGIN: Dictionary = {
	&"KANTO": {
		31: Vector2i(0, 5),
		60: Vector2i(0, 5),
		15: Vector2i(5, 0),
		29: Vector2i(5, 0),
	},
}

const FACADE_SLOPE: Dictionary = {
	&"JOHTO": [49, 52, 54, 65, 68, 72, 81, 82, 83, 84],
	&"BATTLE_TOWER_OUTSIDE": [10, 11, 12, 13, 14, 15, 16, 17, 18],
}

const TILESETS: Dictionary = {
	&"KANTO": {
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
			10, 11, 12, 15, 26, 27, 28, 29, 31, 34, 35, 47, 50, 60, 63, 66, 67, 68, 69,
			74, 75,
		],
		&"roof": [7, 18, 23, 76, 77, 78, 83, 90, 92, 93, 94, 95],
		&"roof_edge": [6, 8, 22, 24, 38, 40, 56],
		&"roof_corner": [5, 9, 21, 25, 37, 41],
	},
	&"HOUSE": {
		&"table": [5, 21, 38, 39, 41, 47, 50, 51, 54, 57, 58, 59, 60, 70, 71, 86, 87],
		&"bookcase": [14, 15, 48, 49],
		&"tombstone": [40, 55, 56, 63, 78],
		&"flowers": [42, 43, 94, 95, 84, 85],
		&"planter": [8, 9, 10, 11, 24, 25, 26, 27],
	},
	&"JOHTO": {
		&"ground": [154],
		&"sapling": [19, 21, 29, 69],
		&"wall": [70, 71, 86, 87],
		&"fence": [74, 89, 90],
		&"flower": [3],
		&"tall_grass": [4],
		&"facade": [7],
		&"sign_post": [78, 79, 94, 95],
		&"sea_rock": [88],
		&"tree": [30, 31, 46, 47, 62, 63],
	},
	&"JOHTO_MODERN": {
		&"ground": [91],
		&"tall_grass": [4],
		&"tree": [30, 31, 19, 21, 62, 63],
		&"sea_rock": [88],
		&"fence": [74, 89, 90],
	},
	&"BATTLE_TOWER_OUTSIDE": {
		&"tree": [30, 31, 19, 21, 62, 63],
		&"sign_post": [78, 79, 94, 95],
		&"fence": [74, 89, 90],
	},
	&"PORT": {
		&"sea_rock": [1, 2, 17, 18],
		&"statue_pillar": [6, 7, 22, 23, 8, 9, 24, 25],
	},
	&"CAVE": {
		&"boulder": [12, 13, 28, 29],
	},
	&"ICE_PATH": {
		&"boulder": [196, 197, 212, 213],
	},
	&"DARK_CAVE": {
		&"ground": [14, 15, 30, 31],
	},
	&"TRAIN_STATION": {
		&"tall_grass": [87],
		&"statue_pillar": [72, 73, 88, 89, 74, 75, 90, 91, 16, 1],
	},
	&"FOREST": {
		&"sapling": [40, 56, 57, 58],
		&"canopy": [12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63],
	},
	&"PARK": {
		&"canopy": [12, 13, 14, 15, 28, 29, 30, 31, 44, 45, 46, 47, 60, 61, 62, 63],
		&"flower": [3],
		&"fence": [5, 27, 35, 36, 37, 38, 43, 51, 52, 53, 54, 67, 83],
		&"kerb": [21, 55, 56, 57, 71, 73, 87, 88, 89],
		&"notice_case": [69, 70, 85, 86],
	},
	&"GAME_CORNER": {
		&"statue_pillar": [66, 67, 82, 83, 68, 69, 84, 85],
	},
	&"ELITE_FOUR_ROOM": {
		&"statue_pillar": [32, 33, 48, 49, 34, 35, 50, 51],
	},
	&"TOWER": {
		&"idol": [34, 35, 50, 51, 18, 19, 54, 55, 74, 75, 90, 91, 76, 92],
	},
	&"CHAMPIONS_ROOM": {
		&"statue_pillar": [152, 153, 154, 155, 156, 157, 158, 159],
	},
	&"LAB": {
		&"statue_pillar": [76, 77, 92, 93, 78, 79, 94, 95],
	},
	&"RUINS_OF_ALPH": {
		&"idol": [14, 15, 30, 31, 46, 47, 62, 63],
	},
	&"MANSION": {
		&"ground": [165, 181],
		&"planter": [46, 47, 94, 95],
	},
	&"LIGHTHOUSE": {
		&"stool": [7, 8, 23, 24],
		&"boulder": [72, 73, 88, 89],
	},
	&"RADIO_TOWER": {
		&"stool": [44, 45, 60, 61, 39, 40, 55, 56],
	},
	&"PLAYERS_HOUSE": {
		&"stool": [2, 3, 18, 19],
	},
	&"TRADITIONAL_HOUSE": {
		&"railing": [64, 65],
		&"ground": [16],
	},
	&"FACILITY": {
		&"planter": [44, 45, 60, 61, 46, 47, 62, 63],
	},
	&"UNDERGROUND": {
		&"planter": [
			30, 31, 46, 47, 62, 63, 69, 70, 85, 86, 7, 8, 23, 24, 9, 25, 48, 49,
		],
	},
	&"MART": {
		&"planter": [74, 75, 8, 9, 137, 138, 167, 168],
	},
	&"POKECOM_CENTER": {
		&"palm": [174, 175, 190, 191, 206, 207, 222, 223],
	},
	&"GATE": {
		&"planter": [5],
	},
}

const UNPINNED: Dictionary = {
	&"MANSION": [162],
	&"TRAIN_STATION": [55, 56],
	&"TOWER": [80, 81],
}


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
