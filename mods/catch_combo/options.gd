extends RefCounted

## One setting: how often the box after a catch says how long the combo is.

const MOD_ID: StringName = &"catch_combo"

const BOX: StringName = &"box"

const BOX_OFF: int = 0
## Only where the combo reaches a rung that is worth more DV words, which is the
## one moment the odds actually changed.
const BOX_RUNGS: int = 1
const BOX_EVERY: int = 2


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": BOX,
		"label": "COMBO BOX",
		"values": [BOX_OFF, BOX_RUNGS, BOX_EVERY],
		"labels": ["OFF", "RUNGS", "EVERY"],
		"default": BOX_EVERY,
	})


static func box(host: Gen2ModHost) -> int:
	if host == null:
		return BOX_EVERY
	var value: Variant = host.option(MOD_ID, BOX)
	return BOX_EVERY if value == null else int(value)
