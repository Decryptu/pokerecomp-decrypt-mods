extends RefCounted

## Every achievement, and the one question each asks of a run.

const BADGE_ZEPHYR: int = 0
const BADGE_RISING: int = 7
const BADGE_COUNT: int = 16
const MASK_JOHTO: int = 0x00FF
const MASK_ALL: int = 0xFFFF

const RULE_BADGE: StringName = &"badge"
const RULE_BADGE_SET: StringName = &"badge_set"
const RULE_CHAMPION: StringName = &"champion"
const RULE_RED: StringName = &"red"
const RULE_CAUGHT: StringName = &"caught"
const RULE_UNOWN: StringName = &"unown"
const RULE_PARTY: StringName = &"party"
const RULE_LEVEL: StringName = &"level"
const RULE_SHINY: StringName = &"shiny"
const RULE_MONEY: StringName = &"money"
const RULE_COINS: StringName = &"coins"
const RULE_HOURS: StringName = &"hours"

const SOUND_BADGE: StringName = &"get_badge"
const SOUND_KEY_ITEM: StringName = &"key_item"
const SOUND_ITEM: StringName = &"item"

const GEODUDE: int = 74
const STARYU: int = 120
const PIKACHU: int = 25
const BELLSPROUT: int = 69
const KOFFING: int = 109
const ABRA: int = 63
const MAGMAR: int = 126
const RHYDON: int = 112
const DRAGONITE: int = 149
const PIDGEOT: int = 18
const CHARIZARD: int = 6
const RATTATA: int = 19
const DITTO: int = 132
const CELEBI: int = 251
const UNOWN: int = 201
const CHANSEY: int = 113
const TYRANITAR: int = 248
const GYARADOS: int = 130
const MEOWTH: int = 52
const PORYGON: int = 137
const HOOTHOOT: int = 163

const DEX_COMPLETE: int = 251

const FULL_PARTY: int = 6

const ROWS: Array[Dictionary] = [
	{
		"id": &"zephyr_badge", "name": "ZEPHYRBADGE", "detail": "BEAT FALKNER",
		"rule": RULE_BADGE, "at": 0,
		"icon": {"badge": 0}, "sound": SOUND_BADGE,
	},
	{
		"id": &"hive_badge", "name": "HIVEBADGE", "detail": "BEAT BUGSY",
		"rule": RULE_BADGE, "at": 1,
		"icon": {"badge": 1}, "sound": SOUND_BADGE,
	},
	{
		"id": &"plain_badge", "name": "PLAINBADGE", "detail": "BEAT WHITNEY",
		"rule": RULE_BADGE, "at": 2,
		"icon": {"badge": 2}, "sound": SOUND_BADGE,
	},
	{
		"id": &"fog_badge", "name": "FOGBADGE", "detail": "BEAT MORTY",
		"rule": RULE_BADGE, "at": 3,
		"icon": {"badge": 3}, "sound": SOUND_BADGE,
	},
	{
		"id": &"mineral_badge", "name": "MINERALBADGE", "detail": "BEAT JASMINE",
		"rule": RULE_BADGE, "at": 4,
		"icon": {"badge": 4}, "sound": SOUND_BADGE,
	},
	{
		"id": &"storm_badge", "name": "STORMBADGE", "detail": "BEAT CHUCK",
		"rule": RULE_BADGE, "at": 5,
		"icon": {"badge": 5}, "sound": SOUND_BADGE,
	},
	{
		"id": &"glacier_badge", "name": "GLACIERBADGE", "detail": "BEAT PRYCE",
		"rule": RULE_BADGE, "at": 6,
		"icon": {"badge": 6}, "sound": SOUND_BADGE,
	},
	{
		"id": &"rising_badge", "name": "RISINGBADGE", "detail": "BEAT CLAIR",
		"rule": RULE_BADGE, "at": 7,
		"icon": {"badge": 7}, "sound": SOUND_BADGE,
	},
	{
		"id": &"boulder_badge", "name": "BOULDERBADGE", "detail": "BEAT BROCK",
		"rule": RULE_BADGE, "at": 8,
		"icon": {"species": GEODUDE}, "sound": SOUND_BADGE,
	},
	{
		"id": &"cascade_badge", "name": "CASCADEBADGE", "detail": "BEAT MISTY",
		"rule": RULE_BADGE, "at": 9,
		"icon": {"species": STARYU}, "sound": SOUND_BADGE,
	},
	{
		"id": &"thunder_badge", "name": "THUNDERBADGE", "detail": "BEAT LT.SURGE",
		"rule": RULE_BADGE, "at": 10,
		"icon": {"species": PIKACHU}, "sound": SOUND_BADGE,
	},
	{
		"id": &"rainbow_badge", "name": "RAINBOWBADGE", "detail": "BEAT ERIKA",
		"rule": RULE_BADGE, "at": 11,
		"icon": {"species": BELLSPROUT}, "sound": SOUND_BADGE,
	},
	{
		"id": &"soul_badge", "name": "SOULBADGE", "detail": "BEAT JANINE",
		"rule": RULE_BADGE, "at": 12,
		"icon": {"species": KOFFING}, "sound": SOUND_BADGE,
	},
	{
		"id": &"marsh_badge", "name": "MARSHBADGE", "detail": "BEAT SABRINA",
		"rule": RULE_BADGE, "at": 13,
		"icon": {"species": ABRA}, "sound": SOUND_BADGE,
	},
	{
		"id": &"volcano_badge", "name": "VOLCANOBADGE", "detail": "BEAT BLAINE",
		"rule": RULE_BADGE, "at": 14,
		"icon": {"species": MAGMAR}, "sound": SOUND_BADGE,
	},
	{
		"id": &"earth_badge", "name": "EARTHBADGE", "detail": "BEAT BLUE",
		"rule": RULE_BADGE, "at": 15,
		"icon": {"species": RHYDON}, "sound": SOUND_BADGE,
	},
	{
		"id": &"johto_cleared", "name": "JOHTO CLEARED", "detail": "EIGHT BADGES",
		"rule": RULE_BADGE_SET, "at": MASK_JOHTO,
		"icon": {"badge": BADGE_RISING}, "sound": SOUND_BADGE,
	},
	{
		"id": &"champion", "name": "CHAMPION", "detail": "BEAT THE LEAGUE",
		"rule": RULE_CHAMPION, "at": 0,
		"icon": {"species": DRAGONITE}, "sound": SOUND_BADGE,
	},
	{
		"id": &"kanto_cleared", "name": "KANTO CLEARED", "detail": "ALL 16 BADGES",
		"rule": RULE_BADGE_SET, "at": MASK_ALL,
		"icon": {"species": PIDGEOT}, "sound": SOUND_BADGE,
	},
	{
		"id": &"mt_silver", "name": "MT.SILVER", "detail": "BEAT RED",
		"rule": RULE_RED, "at": 0,
		"icon": {"species": CHARIZARD}, "sound": SOUND_BADGE,
	},
	{
		"id": &"first_catch", "name": "FIRST CATCH", "detail": "ONE CAUGHT",
		"rule": RULE_CAUGHT, "at": 1,
		"icon": {"species": RATTATA}, "sound": SOUND_ITEM,
	},
	{
		"id": &"hundred_caught", "name": "100 CAUGHT", "detail": "100 SPECIES",
		"rule": RULE_CAUGHT, "at": 100,
		"icon": {"species": DITTO}, "sound": SOUND_ITEM,
	},
	{
		"id": &"pokedex", "name": "POKéDEX", "detail": "ALL 251 CAUGHT",
		"rule": RULE_CAUGHT, "at": DEX_COMPLETE,
		"icon": {"species": CELEBI}, "sound": SOUND_KEY_ITEM,
	},
	{
		"id": &"unown", "name": "UNOWN", "detail": "ALL 26 LETTERS",
		"rule": RULE_UNOWN, "at": 26,
		"icon": {"species": UNOWN}, "sound": SOUND_KEY_ITEM,
	},
	{
		"id": &"full_party", "name": "FULL PARTY", "detail": "SIX AT ONCE",
		"rule": RULE_PARTY, "at": FULL_PARTY,
		"icon": {"species": CHANSEY}, "sound": SOUND_ITEM,
	},
	{
		"id": &"level_100", "name": "LEVEL 100", "detail": "THE WHOLE WAY",
		"rule": RULE_LEVEL, "at": 100,
		"icon": {"species": TYRANITAR}, "sound": SOUND_ITEM,
	},
	{
		"id": &"shiny", "name": "SHINY", "detail": "ONE OWNED",
		"rule": RULE_SHINY, "at": 1,
		"icon": {"species": GYARADOS}, "sound": SOUND_ITEM,
	},
	{
		"id": &"rich", "name": "RICH", "detail": "100000 IN CASH",
		"rule": RULE_MONEY, "at": 100000,
		"icon": {"species": MEOWTH}, "sound": SOUND_ITEM,
	},
	{
		"id": &"high_roller", "name": "HIGH ROLLER", "detail": "1000 COINS",
		"rule": RULE_COINS, "at": 1000,
		"icon": {"species": PORYGON}, "sound": SOUND_ITEM,
	},
	{
		"id": &"one_day", "name": "ONE DAY", "detail": "24 HOURS PLAYED",
		"rule": RULE_HOURS, "at": 24,
		"icon": {"species": HOOTHOOT}, "sound": SOUND_ITEM,
	},
]


static func holds(row: Dictionary, progress: Dictionary) -> bool:
	var at: int = int(row.get("at", 0))
	match StringName(row.get("rule", &"")):
		RULE_BADGE:
			return (int(progress.get(&"badges", 0)) & (1 << at)) != 0
		RULE_BADGE_SET:
			return (int(progress.get(&"badges", 0)) & at) == at
		RULE_CHAMPION:
			return bool(progress.get(&"hall_of_fame", false))
		RULE_RED:
			return bool(progress.get(&"beat_red", false))
		RULE_CAUGHT:
			return int(progress.get(&"caught_count", 0)) >= at
		RULE_UNOWN:
			return int(progress.get(&"unown_caught", 0)) >= at
		RULE_PARTY:
			return int(progress.get(&"party_count", 0)) >= at
		RULE_LEVEL:
			return int(progress.get(&"highest_level", 0)) >= at
		RULE_SHINY:
			return int(progress.get(&"shiny_count", 0)) >= at
		RULE_MONEY:
			return int(progress.get(&"money", 0)) >= at
		RULE_COINS:
			return int(progress.get(&"coins", 0)) >= at
		RULE_HOURS:
			return int(progress.get(&"play_hours", 0)) >= at
	return false


static func held(progress: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in ROWS:
		if holds(row, progress):
			out.append(StringName(row["id"]))
	return out


static func find(id: StringName) -> Dictionary:
	for candidate: Dictionary in ROWS:
		if StringName(candidate["id"]) == id:
			return candidate
	return {}
