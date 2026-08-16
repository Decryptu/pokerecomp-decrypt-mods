extends RefCounted

## The settings and the one control this mod registers, and the one place they
## are named.
##
## Described here and never drawn: the host builds the start menu's MODS entry
## and this mod's own page in the launcher out of the registration, and the
## control is bound in the launcher's controls card or carried on the on-screen
## pad. See `docs/MODS.md` in pokerecomp.

const MOD_ID: StringName = &"follower"

## Which party slot walks. LEAD is the slot every other game with a follower
## uses, and the other five are here because a party is six and picking is free.
const SLOT: StringName = &"slot"
const SLOT_VALUES: Array = [1, 2, 3, 4, 5, 6]
const SLOT_LABELS: Array = ["LEAD", "2", "3", "4", "5", "6"]

## Whether the follower stays out on a bike and on the water. Both are off,
## because a Pokemon jogging beside a bicycle and one walking on the sea are the
## two places the illusion breaks, and both are one press away for anyone who
## wants them anyway.
const CYCLING: StringName = &"cycling"
const SURFING: StringName = &"surfing"

const OFF_ON: Array = [0, 1]

## Puts the follower away and calls it back. A control rather than a setting: it
## is pressed while walking around, and the settings menu is not where a player
## reaches for it. Registered as well as bound, so it exists before anyone opens
## the controls card. `F` is bound to none of the cartridge's eight, which is the
## one thing a default has to clear.
const RECALL: StringName = &"recall"


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": SLOT, "label": "WHO",
		"values": SLOT_VALUES, "labels": SLOT_LABELS, "default": 1,
	})
	host.register_option(id, {
		"key": CYCLING, "label": "ON BIKE",
		"values": OFF_ON, "labels": ["OFF", "ON"], "default": 0,
	})
	host.register_option(id, {
		"key": SURFING, "label": "ON WATER",
		"values": OFF_ON, "labels": ["OFF", "ON"], "default": 0,
	})
	host.register_action(id, {
		"key": RECALL, "label": "Recall the follower",
		"default": [{"kind": "key", "code": KEY_F}],
	})


## What the player chose. A mod loaded by a probe or a tool registered nothing,
## so a missing host answers the defaults rather than nothing.
static func settings(host: Gen2ModHost) -> Dictionary:
	var chosen: Dictionary = {SLOT: 1, CYCLING: false, SURFING: false}
	if host == null:
		return chosen
	var slot: Variant = host.option(MOD_ID, SLOT)
	chosen[SLOT] = 1 if slot == null else clampi(int(slot), 1, SLOT_VALUES.size())
	for key: StringName in [CYCLING, SURFING]:
		var value: Variant = host.option(MOD_ID, key)
		chosen[key] = false if value == null else int(value) != 0
	return chosen


## Whether [param key] is one this mod registered, for a change handler that is
## handed every mod's settings.
static func owns(key: StringName) -> bool:
	return key in [SLOT, CYCLING, SURFING]
