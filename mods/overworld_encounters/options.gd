extends RefCounted

const MAXIMUM: StringName = &"maximum"
## How many wild Pokemon one map may hold at once.
const MAXIMUM_VALUES: Array = [2, 4, 6, 8, 12, 16]
const MAXIMUM_DEFAULT: int = 6


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": MAXIMUM, "label": "VISIBLE",
		"values": MAXIMUM_VALUES, "labels": ["2", "4", "6", "8", "12", "16"],
		"default": MAXIMUM_DEFAULT,
	})


static func maximum(host: Gen2ModHost, id: StringName) -> int:
	if host == null:
		return MAXIMUM_DEFAULT
	var value: Variant = host.option(id, MAXIMUM)
	if value == null:
		return MAXIMUM_DEFAULT
	return clampi(int(value), MAXIMUM_VALUES[0], MAXIMUM_VALUES[-1])
