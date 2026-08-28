extends RefCounted

## The settings and the one control this mod registers, named once here.

const MOD_ID: StringName = &"follower"

const SLOT: StringName = &"slot"
const SLOT_VALUES: Array = [1, 2, 3, 4, 5, 6]
const SLOT_LABELS: Array = ["LEAD", "2", "3", "4", "5", "6"]

const CYCLING: StringName = &"cycling"
const SURFING: StringName = &"surfing"

const OFF_ON: Array = [0, 1]

const PICKUP: StringName = &"pickup"

const RECALL: StringName = &"recall"

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


static func owns(key: StringName) -> bool:
	return key in [SLOT, CYCLING, SURFING, PICKUP]
