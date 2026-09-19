extends RefCounted

## The settings this mod registers, and the one place that names them.

const MOD_ID: StringName = &"randomizer"

const SEED: StringName = &"seed"
const SEED_MAXIMUM: int = 9999

const NUMBER_KIND: StringName = &"number"

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
## The toggles read off `GameData.catalog()`, which the host builds from
## Generation II scripts alone: on Red, Blue and Yellow there is no row behind
## them, so they are not offered there.
const CATALOG_TOGGLES: Array[StringName] = [
	SPECIALS, STARTERS, TRADES, ITEMS, BADGES, SHOPS,
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
	host.register_option(id, {
		"key": SEED, "label": "SEED", "kind": NUMBER_KIND,
		"minimum": 0, "maximum": SEED_MAXIMUM, "default": 0,
	})
	for key: StringName in toggles_for(host.generation()):
		host.register_option(id, {
			"key": key, "label": String(TOGGLE_LABELS[key]),
			"values": OFF_ON, "labels": ["OFF", "ON"], "default": 1,
		})


static func toggles_for(generation: int) -> Array[StringName]:
	if generation != RomRegistry.GEN1:
		return TOGGLES
	var keys: Array[StringName] = TOGGLES.duplicate()
	for key: StringName in CATALOG_TOGGLES:
		keys.erase(key)
	return keys


static func settings(host: Gen2ModHost) -> Dictionary:
	var chosen: Dictionary = {"seed": 0}
	for key: StringName in TOGGLES:
		chosen[key] = true
	if host == null:
		return chosen
	chosen["seed"] = clampi(int(host.option(MOD_ID, SEED)), 0, SEED_MAXIMUM)
	for key: StringName in TOGGLES:
		var value: Variant = host.option(MOD_ID, key)
		chosen[key] = value != null and int(value) != 0
	return chosen


static func seed_text(seed_value: int) -> String:
	return "%04d" % (seed_value % (SEED_MAXIMUM + 1))
