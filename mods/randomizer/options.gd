extends RefCounted

## The settings this mod registers, and the one place that names them.
## this mod as well as convenient: a seed is what a run was generated from, and

const MOD_ID: StringName = &"randomizer"

const SEED: StringName = &"seed"
const SEED_MAXIMUM: int = 9999

const NUMBER_KIND: StringName = &"number"
const SEED_DIGIT_KEYS: Array[StringName] = [&"seed_1", &"seed_2", &"seed_3", &"seed_4"]
const DIGITS: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

const STATS: StringName = &"stats"
const TYPES: StringName = &"types"
const LEARNSETS: StringName = &"learnsets"
const EVOLUTIONS: StringName = &"evolutions"
const MOVES: StringName = &"moves"
const TRAINERS: StringName = &"trainers"
const ENCOUNTERS: StringName = &"encounters"
const SPECIALS: StringName = &"specials"
const STARTERS: StringName = &"starters"
const TRADES: StringName = &"trades"
const ITEMS: StringName = &"items"
const BADGES: StringName = &"badges"
const SHOPS: StringName = &"shops"

const TOGGLES: Array[StringName] = [
	STATS, TYPES, LEARNSETS, EVOLUTIONS, MOVES, TRAINERS, ENCOUNTERS, SPECIALS,
	STARTERS, TRADES, ITEMS, BADGES, SHOPS,
]
const TOGGLE_LABELS: Dictionary = {
	STATS: "STATS", TYPES: "TYPES", LEARNSETS: "MOVESETS", EVOLUTIONS: "EVOLVES",
	MOVES: "MOVES", TRAINERS: "TRAINERS", ENCOUNTERS: "WILD",
	SPECIALS: "GIFTS/STATIC",
	STARTERS: "STARTERS", TRADES: "TRADES", ITEMS: "ITEMS",
	BADGES: "BADGES", SHOPS: "SHOPS",
}
const OFF_ON: Array = [0, 1]


static func register(host: Gen2ModHost, id: StringName) -> void:
	var seed_row: Dictionary = host.register_option(id, {
		"key": SEED, "label": "SEED", "kind": NUMBER_KIND,
		"minimum": 0, "maximum": SEED_MAXIMUM, "default": 0,
	})
	if not bool(seed_row.get("ok", false)):
		for index: int in SEED_DIGIT_KEYS.size():
			host.register_option(id, {
				"key": SEED_DIGIT_KEYS[index], "label": "SEED %d" % (index + 1),
				"values": DIGITS, "default": 0,
			})
	for key: StringName in TOGGLES:
		host.register_option(id, {
			"key": key, "label": String(TOGGLE_LABELS[key]),
			"values": OFF_ON, "labels": ["OFF", "ON"], "default": 1,
		})


static func settings(host: Gen2ModHost) -> Dictionary:
	var chosen: Dictionary = {"seed": 0}
	for key: StringName in TOGGLES:
		chosen[key] = true
	if host == null:
		return chosen
	chosen["seed"] = _seed(host)
	for key: StringName in TOGGLES:
		var value: Variant = host.option(MOD_ID, key)
		chosen[key] = true if value == null else int(value) != 0
	return chosen


static func _seed(host: Gen2ModHost) -> int:
	var value: Variant = host.option(MOD_ID, SEED)
	if value != null:
		return clampi(int(value), 0, SEED_MAXIMUM)
	var spelled: int = 0
	for key: StringName in SEED_DIGIT_KEYS:
		var digit: Variant = host.option(MOD_ID, key)
		spelled = spelled * 10 + (0 if digit == null else clampi(int(digit), 0, 9))
	return spelled


static func seed_text(seed_value: int) -> String:
	return "%04d" % (seed_value % (SEED_MAXIMUM + 1))


static func owns(key: StringName) -> bool:
	return key == SEED or SEED_DIGIT_KEYS.has(key) or TOGGLES.has(key)
