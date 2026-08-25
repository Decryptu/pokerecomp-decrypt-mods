extends RefCounted

## The settings and the one control this mod registers, named once here.
##
## Described and never drawn: the host builds the MODS entry and the mod's page
## out of this registration, and the control is bound in the launcher's controls
## card. See `docs/MODS.md` in pokerecomp.

const MOD_ID: StringName = &"follower"

## Which party slot walks. LEAD is what every other game with a follower uses.
const SLOT: StringName = &"slot"
const SLOT_VALUES: Array = [1, 2, 3, 4, 5, 6]
const SLOT_LABELS: Array = ["LEAD", "2", "3", "4", "5", "6"]

## Whether the follower stays out on a bike and on the water. Both off: a Pokemon
## jogging beside a bicycle and one walking on the sea are where the illusion
## breaks.
const CYCLING: StringName = &"cycling"
const SURFING: StringName = &"surfing"

const OFF_ON: Array = [0, 1]

## Whether the follower picks up a hidden item it walks over. Off, because the
## cartridge hides them to be looked for.
const PICKUP: StringName = &"pickup"

## Puts the follower away and calls it back. A control rather than a setting,
## since it is pressed while walking around. `F` is bound to none of the
## cartridge's eight buttons, which is what a default has to clear.
const RECALL: StringName = &"recall"

## The same recall as a menu row, which is not a duplicate: a control has to be
## bound before it exists, and the player who most needs this is the one on a pad
## or a phone. A menu press needs no binding, so there is always a way in.
##
## A button rather than a rung, because what it toggles is per session and a rung
## would be written to `user://mod_options.json`. It toggles exactly as the
## control does.
const PUT_AWAY: StringName = &"put_away"


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
	host.register_option(id, {
		"key": PICKUP, "label": "FINDS ITEMS",
		"values": OFF_ON, "labels": ["OFF", "ON"], "default": 0,
	})
	host.register_action(id, {
		"key": RECALL, "label": "Recall the follower",
		"default": [{"kind": "key", "code": KEY_F}],
	})
	host.register_option(id, {
		"key": PUT_AWAY, "label": "FOLLOWER",
		"kind": &"button", "press_label": "RECALL",
	})


## What the player chose. A probe or tool registered nothing, so a missing host
## answers the defaults.
static func settings(host: Gen2ModHost) -> Dictionary:
	var chosen: Dictionary = {SLOT: 1, CYCLING: false, SURFING: false, PICKUP: false}
	if host == null:
		return chosen
	var slot: Variant = host.option(MOD_ID, SLOT)
	chosen[SLOT] = 1 if slot == null else clampi(int(slot), 1, SLOT_VALUES.size())
	for key: StringName in [CYCLING, SURFING, PICKUP]:
		var value: Variant = host.option(MOD_ID, key)
		chosen[key] = false if value == null else int(value) != 0
	return chosen


## Whether [param key] is one this mod registered, for a handler that is handed
## every mod's settings.
static func owns(key: StringName) -> bool:
	return key in [SLOT, CYCLING, SURFING, PICKUP]
