extends RefCounted

const MAXIMUM: StringName = &"maximum"
const MAXIMUM_VALUES: Array = [2, 4, 6, 8]


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": MAXIMUM, "label": "VISIBLE",
		"values": MAXIMUM_VALUES, "labels": ["2", "4", "6", "8"], "default": 6,
	})


static func maximum(host: Gen2ModHost, id: StringName) -> int:
	if host == null:
		return 6
	var value: Variant = host.option(id, MAXIMUM)
	return 6 if value == null else clampi(int(value), 2, 8)
