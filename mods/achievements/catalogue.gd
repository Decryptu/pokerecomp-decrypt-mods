extends RefCounted

## Every achievement, and the one question each asks of a run.
##
## A row is a fact about the state a save is in, never a moment that passed:
## "eight badges", not "a badge was just awarded". That is the whole of what
## makes the mod work on a save it was installed onto years late, since a state
## a game reached is still readable and a moment is not. Nothing here reads,
## draws or writes; `ledger.gd` decides what is new and `mod.gd` spends it.
##
## `rule` and `at` are a pair rather than a Callable so the table stays data: it
## can be printed, counted and driven from a probe without a host.

## Badge indices, in the order the cartridge's own engine flags run. The eight
## Johto ones are also their index into the trainer card's badge art
## (`card_badges`, four tiles a badge); the Kanto eight have no art, since the
## card's Kanto page is unreachable on the cartridge and reuses the Johto
## drawings, so those rows wear the gym's own type instead.
const BADGE_RISING: int = 7
const BADGE_COUNT: int = 16
## The two sets as masks, because "all of JOHTO" is which eight rather than how
## many: a run holding eight Kanto badges and no Johto one has not cleared
## Johto, and only a mask says so.
const MASK_JOHTO: int = 0x00FF
const MASK_ALL: int = 0xFFFF

## What one row asks. Each is answered by [method holds] against one field of
## the host's progress snapshot.
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

## Every species number an icon names, so a row never carries a bare literal.
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

## The Pokedex is 251 entries on all three cartridges, which is also CELEBI's
## number and why that row wears it.
const DEX_COMPLETE: int = 251

## A party is six, `Gen2Party.MAX_SIZE`, named here so the row reads.
const FULL_PARTY: int = 6

const ROWS: Array[Dictionary] = [
	{
		"id": &"zephyr_badge", "name": "ZEPHYRBADGE",
		"detail": "Beat FALKNER at\nthe VIOLET GYM.",
		"rule": RULE_BADGE, "at": 0, "icon": {"badge": 0},
	},
	{
		"id": &"hive_badge", "name": "HIVEBADGE",
		"detail": "Beat BUGSY at the\nAZALEA GYM.",
		"rule": RULE_BADGE, "at": 1, "icon": {"badge": 1},
	},
	{
		"id": &"plain_badge", "name": "PLAINBADGE",
		"detail": "Beat WHITNEY at\nthe GOLDENROD GYM.",
		"rule": RULE_BADGE, "at": 2, "icon": {"badge": 2},
	},
	{
		"id": &"fog_badge", "name": "FOGBADGE",
		"detail": "Beat MORTY at the\nECRUTEAK GYM.",
		"rule": RULE_BADGE, "at": 3, "icon": {"badge": 3},
	},
	{
		"id": &"mineral_badge", "name": "MINERALBADGE",
		"detail": "Beat JASMINE at\nthe OLIVINE GYM.",
		"rule": RULE_BADGE, "at": 4, "icon": {"badge": 4},
	},
	{
		"id": &"storm_badge", "name": "STORMBADGE",
		"detail": "Beat CHUCK at the\nCIANWOOD GYM.",
		"rule": RULE_BADGE, "at": 5, "icon": {"badge": 5},
	},
	{
		"id": &"glacier_badge", "name": "GLACIERBADGE",
		"detail": "Beat PRYCE at the\nMAHOGANY GYM.",
		"rule": RULE_BADGE, "at": 6, "icon": {"badge": 6},
	},
	{
		"id": &"rising_badge", "name": "RISINGBADGE",
		"detail": "Beat CLAIR at the\nBLACKTHORN GYM.",
		"rule": RULE_BADGE, "at": 7, "icon": {"badge": 7},
	},
	{
		"id": &"boulder_badge", "name": "BOULDERBADGE",
		"detail": "Beat BROCK at the\nPEWTER GYM.",
		"rule": RULE_BADGE, "at": 8, "icon": {"species": GEODUDE},
	},
	{
		"id": &"cascade_badge", "name": "CASCADEBADGE",
		"detail": "Beat MISTY at the\nCERULEAN GYM.",
		"rule": RULE_BADGE, "at": 9, "icon": {"species": STARYU},
	},
	{
		"id": &"thunder_badge", "name": "THUNDERBADGE",
		"detail": "Beat LT.SURGE at\nthe VERMILION GYM.",
		"rule": RULE_BADGE, "at": 10, "icon": {"species": PIKACHU},
	},
	{
		"id": &"rainbow_badge", "name": "RAINBOWBADGE",
		"detail": "Beat ERIKA at the\nCELADON GYM.",
		"rule": RULE_BADGE, "at": 11, "icon": {"species": BELLSPROUT},
	},
	{
		"id": &"soul_badge", "name": "SOULBADGE",
		"detail": "Beat JANINE at\nthe FUCHSIA GYM.",
		"rule": RULE_BADGE, "at": 12, "icon": {"species": KOFFING},
	},
	{
		"id": &"marsh_badge", "name": "MARSHBADGE",
		"detail": "Beat SABRINA at\nthe SAFFRON GYM.",
		"rule": RULE_BADGE, "at": 13, "icon": {"species": ABRA},
	},
	{
		"id": &"volcano_badge", "name": "VOLCANOBADGE",
		"detail": "Beat BLAINE in the\nSEAFOAM ISLANDS.",
		"rule": RULE_BADGE, "at": 14, "icon": {"species": MAGMAR},
	},
	{
		"id": &"earth_badge", "name": "EARTHBADGE",
		"detail": "Beat BLUE at the\nVIRIDIAN GYM.",
		"rule": RULE_BADGE, "at": 15, "icon": {"species": RHYDON},
	},
	{
		"id": &"johto_cleared", "name": "JOHTO CLEARED",
		"detail": "Win all eight\nJOHTO badges.",
		"rule": RULE_BADGE_SET, "at": MASK_JOHTO, "icon": {"badge": BADGE_RISING},
	},
	{
		"id": &"champion", "name": "CHAMPION",
		"detail": "Beat the ELITE\nFOUR and LANCE.",
		"rule": RULE_CHAMPION, "at": 0, "icon": {"species": DRAGONITE},
	},
	{
		"id": &"kanto_cleared", "name": "KANTO CLEARED",
		"detail": "Win all eight\nKANTO badges.",
		"rule": RULE_BADGE_SET, "at": MASK_ALL, "icon": {"species": PIDGEOT},
	},
	{
		"id": &"mt_silver", "name": "MT.SILVER",
		"detail": "Beat RED at the\ntop of MT.SILVER.",
		"rule": RULE_RED, "at": 0, "icon": {"species": CHARIZARD},
	},
	{
		"id": &"first_catch", "name": "FIRST CATCH",
		"detail": "Catch your first\nPOKéMON.",
		"rule": RULE_CAUGHT, "at": 1, "icon": {"species": RATTATA},
	},
	{
		"id": &"hundred_caught", "name": "100 CAUGHT",
		"detail": "Catch a hundred\ndifferent POKéMON.",
		"rule": RULE_CAUGHT, "at": 100, "icon": {"species": DITTO},
	},
	{
		"id": &"pokedex", "name": "POKéDEX",
		"detail": "Catch all 251\nPOKéMON.",
		"rule": RULE_CAUGHT, "at": DEX_COMPLETE, "icon": {"species": CELEBI},
	},
	{
		"id": &"unown", "name": "UNOWN",
		"detail": "Register all 26\nUNOWN letters.",
		"rule": RULE_UNOWN, "at": 26, "icon": {"species": UNOWN},
	},
	{
		"id": &"full_party", "name": "FULL PARTY",
		"detail": "Carry six POKéMON\nat once.",
		"rule": RULE_PARTY, "at": FULL_PARTY, "icon": {"species": CHANSEY},
	},
	{
		"id": &"level_100", "name": "LEVEL 100",
		"detail": "Raise a POKéMON to\nlevel 100.",
		"rule": RULE_LEVEL, "at": 100, "icon": {"species": TYRANITAR},
	},
	{
		"id": &"shiny", "name": "SHINY",
		"detail": "Own a shiny\nPOKéMON.",
		"rule": RULE_SHINY, "at": 1, "icon": {"species": GYARADOS},
	},
	{
		"id": &"rich", "name": "RICH",
		"detail": "Carry a hundred\nthousand in cash.",
		"rule": RULE_MONEY, "at": 100000, "icon": {"species": MEOWTH},
	},
	{
		"id": &"high_roller", "name": "HIGH ROLLER",
		"detail": "Hold a thousand\nGame Corner coins.",
		"rule": RULE_COINS, "at": 1000, "icon": {"species": PORYGON},
	},
	{
		"id": &"one_day", "name": "ONE DAY",
		"detail": "Play for twenty-\nfour hours.",
		"rule": RULE_HOURS, "at": 24, "icon": {"species": HOOTHOOT},
	},
]


## Whether [param row] is true of the run [param progress] describes.
##
## An absent field reads as nothing achieved rather than as an error, so a row
## asking a question an older host does not answer stays locked instead of
## unlocking for everyone.
static func holds(row: Dictionary, progress: Dictionary) -> bool:
	var at: int = int(row.get("at", 0))
	match StringName(row.get("rule", &"")):
		RULE_BADGE:
			return (int(progress.get("badges", 0)) & (1 << at)) != 0
		RULE_BADGE_SET:
			return (int(progress.get("badges", 0)) & at) == at
		RULE_CHAMPION:
			return bool(progress.get("hall_of_fame", false))
		RULE_RED:
			return bool(progress.get("beat_red", false))
		RULE_CAUGHT:
			return int(progress.get("caught_count", 0)) >= at
		RULE_UNOWN:
			return int(progress.get("unown_caught", 0)) >= at
		RULE_PARTY:
			return int(progress.get("party_count", 0)) >= at
		RULE_LEVEL:
			return int(progress.get("highest_level", 0)) >= at
		RULE_SHINY:
			return int(progress.get("shiny_count", 0)) >= at
		RULE_MONEY:
			return int(progress.get("money", 0)) >= at
		RULE_COINS:
			return int(progress.get("coins", 0)) >= at
		RULE_HOURS:
			return int(progress.get("play_hours", 0)) >= at
	return false


## Every row that is true of [param progress], in table order.
static func held(progress: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in ROWS:
		if holds(row, progress):
			out.append(StringName(row["id"]))
	return out


## The row with that id, or an empty Dictionary.
static func find(id: StringName) -> Dictionary:
	for candidate: Dictionary in ROWS:
		if StringName(candidate["id"]) == id:
			return candidate
	return {}
