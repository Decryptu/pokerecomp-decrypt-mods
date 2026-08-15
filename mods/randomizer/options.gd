extends RefCounted

## The settings this mod registers, and the one place that names them.
##
## A setting is DESCRIBED here and never drawn: the host builds the start menu's
## MODS entry and this mod's card in the launcher out of the same registration.
## See `docs/MODS.md` in pokerecomp.
##
## Values live per installation in `user://mod_options.json`. That is right for
## this mod as well as convenient: a seed is what a run was generated from, and
## a run whose seed changed when a slot was loaded would not be the run any more.

const MOD_ID: StringName = &"randomizer"

## The seed, as one number the player types or steps. Four digits rather than
## more: a code is worth having when it can be said out loud, and ten thousand
## runs is a great many to share.
const SEED: StringName = &"seed"
const SEED_MAXIMUM: int = 9999

## The same seed as four one-digit ladders, for a host built before
## `OPTION_NUMBER` existed. A ladder is the one option kind every host has had,
## so this is what the mod falls back to rather than reading a seed of zero
## forever and saying nothing. Written as a string rather than as
## `Gen2ModHost.OPTION_NUMBER` for the same reason: a constant the older host
## does not carry would stop this file parsing there at all.
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

## Each thing the mod can randomize is its own rung, so a player can shuffle
## movesets and leave base stats where the cartridge put them.
const TOGGLES: Array[StringName] = [
	STATS, TYPES, LEARNSETS, EVOLUTIONS, MOVES, TRAINERS, ENCOUNTERS,
]
const TOGGLE_LABELS: Dictionary = {
	STATS: "STATS", TYPES: "TYPES", LEARNSETS: "MOVESETS", EVOLUTIONS: "EVOLVES",
	MOVES: "MOVES", TRAINERS: "TRAINERS", ENCOUNTERS: "WILD",
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


## What the player chose, as the Dictionary `plan.gd` takes. A mod loaded by a
## probe or a tool registered nothing, so a missing host answers the defaults
## rather than nothing: the plan is then still buildable and still the plan
## seed 0000 describes.
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


## The one number, or the four digits read as the number they spell. Which of
## the two registered is the host's answer and not a thing to remember here.
static func _seed(host: Gen2ModHost) -> int:
	var value: Variant = host.option(MOD_ID, SEED)
	if value != null:
		return clampi(int(value), 0, SEED_MAXIMUM)
	var spelled: int = 0
	for key: StringName in SEED_DIGIT_KEYS:
		var digit: Variant = host.option(MOD_ID, key)
		spelled = spelled * 10 + (0 if digit == null else clampi(int(digit), 0, 9))
	return spelled


## The seed as the player shares it, leading zeros kept: 42 is the code 0042 and
## is not 4200.
static func seed_text(seed_value: int) -> String:
	return "%04d" % (seed_value % (SEED_MAXIMUM + 1))


## Whether [param key] is one this mod registered, for a change handler that is
## handed every mod's settings.
static func owns(key: StringName) -> bool:
	return key == SEED or SEED_DIGIT_KEYS.has(key) or TOGGLES.has(key)
