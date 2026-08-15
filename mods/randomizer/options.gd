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

## The seed, as four digits. A setting is a LADDER of values or a press, and
## neither is a text field, so the shareable code is a four-digit number the
## player dials in: 10000 seeds, said out loud in one breath, and every one of
## them reachable from a pad or a thumb without a keyboard. One row instead of
## four is an engine request rather than a workaround; see HANDOFF.md.
const SEED_KEYS: Array[StringName] = [&"seed_1", &"seed_2", &"seed_3", &"seed_4"]
const DIGITS: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

const STATS: StringName = &"stats"
const TYPES: StringName = &"types"
const LEARNSETS: StringName = &"learnsets"
const EVOLUTIONS: StringName = &"evolutions"
const MOVES: StringName = &"moves"
const TRAINERS: StringName = &"trainers"

## Each thing the mod can randomize is its own rung, so a player can shuffle
## movesets and leave base stats where the cartridge put them.
const TOGGLES: Array[StringName] = [STATS, TYPES, LEARNSETS, EVOLUTIONS, MOVES, TRAINERS]
const TOGGLE_LABELS: Dictionary = {
	STATS: "STATS", TYPES: "TYPES", LEARNSETS: "MOVESETS",
	EVOLUTIONS: "EVOLVES", MOVES: "MOVES", TRAINERS: "TRAINERS",
}
const OFF_ON: Array = [0, 1]


static func register(host: Gen2ModHost, id: StringName) -> void:
	for index: int in SEED_KEYS.size():
		host.register_option(id, {
			"key": SEED_KEYS[index], "label": "SEED %d" % (index + 1),
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
	var digits: Array[int] = []
	for key: StringName in SEED_KEYS:
		var value: Variant = host.option(MOD_ID, key)
		digits.append(0 if value == null else int(value))
	chosen["seed"] = seed_from_digits(digits)
	for key: StringName in TOGGLES:
		var value: Variant = host.option(MOD_ID, key)
		chosen[key] = true if value == null else int(value) != 0
	return chosen


## The four digits read as the number they spell, which is what a player shares.
static func seed_from_digits(digits: Array[int]) -> int:
	var value: int = 0
	for digit: int in digits:
		value = value * 10 + clampi(digit, 0, 9)
	return value


## The seed as the player sees it on the four rows, leading zeros kept: 42 is
## dialled 0-0-4-2 and is not the same code as 4200.
static func seed_text(seed_value: int) -> String:
	return "%04d" % (seed_value % 10000)


## Whether [param key] is one this mod registered, for a change handler that is
## handed every mod's settings.
static func owns(key: StringName) -> bool:
	return SEED_KEYS.has(key) or TOGGLES.has(key)
