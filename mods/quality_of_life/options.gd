extends RefCounted

## Every convenience this mod provides, named once.

const MOD_ID: StringName = &"quality_of_life"

const FIELD_MOVES: StringName = &"field_moves"
const AUTO_REPEL: StringName = &"auto_repel"
const CATCH_EXP: StringName = &"catch_exp"
const PC_ACCESS: StringName = &"pc_access"
const MOVE_GUIDE: StringName = &"move_guide"
const STAT_STAGES: StringName = &"stat_stages"
const WEATHER: StringName = &"weather"

const OFF_ON: Array = [0, 1]
const LABELS: Dictionary = {
	FIELD_MOVES: "FIELD MOVES",
	AUTO_REPEL: "AUTO REPEL",
	CATCH_EXP: "CATCH EXP",
	PC_ACCESS: "PC ACCESS",
	MOVE_GUIDE: "MOVE GUIDE",
	STAT_STAGES: "STAT STAGES",
	WEATHER: "WEATHER",
}
const KEYS: Array[StringName] = [
	FIELD_MOVES,
	AUTO_REPEL,
	CATCH_EXP,
	PC_ACCESS,
	MOVE_GUIDE,
	STAT_STAGES,
	WEATHER,
]


static func register(host: Gen2ModHost, id: StringName) -> void:
	for key: StringName in KEYS:
		host.register_option(id, {
			"key": key,
			"label": String(LABELS[key]),
			"values": OFF_ON,
			"labels": ["OFF", "ON"],
			"default": 0,
		})


static func enabled(host: Gen2ModHost, key: StringName) -> bool:
	if host == null or key not in KEYS:
		return false
	var value: Variant = host.option(MOD_ID, key)
	return value != null and int(value) != 0


static func settings(host: Gen2ModHost) -> Dictionary:
	var chosen: Dictionary = {}
	for key: StringName in KEYS:
		chosen[key] = enabled(host, key)
	return chosen
