extends RefCounted

## Every convenience this mod provides, named once.

const MOD_ID: StringName = &"quality_of_life"

const FIELD_MOVES: StringName = &"field_moves"
const AUTO_REPEL: StringName = &"auto_repel"
const CATCH_EXP: StringName = &"catch_exp"
const PC_ACCESS: StringName = &"pc_access"
const RUN_SHOES: StringName = &"run_shoes"
const MOVE_GUIDE: StringName = &"move_guide"
const STAT_STAGES: StringName = &"stat_stages"
const WEATHER: StringName = &"weather"
const EXP_SCALE: StringName = &"exp_scale"
const MULTI_EXP: StringName = &"multi_exp"

const OFF_ON: Array = [0, 1]
const LABELS: Dictionary = {
	FIELD_MOVES: "FIELD MOVES",
	AUTO_REPEL: "AUTO REPEL",
	CATCH_EXP: "CATCH EXP",
	PC_ACCESS: "PC ACCESS",
	RUN_SHOES: "RUN SHOES",
	MOVE_GUIDE: "MOVE GUIDE",
	STAT_STAGES: "STAT STAGES",
	WEATHER: "WEATHER",
}
const KEYS: Array[StringName] = [
	FIELD_MOVES,
	AUTO_REPEL,
	CATCH_EXP,
	PC_ACCESS,
	RUN_SHOES,
	MOVE_GUIDE,
	STAT_STAGES,
	WEATHER,
]

## The host holds a product between MIN_EXPERIENCE_SCALE and MAX_EXPERIENCE_SCALE,
## so these rungs are inside its range and matched back with is_equal_approx.
const NO_SCALE: float = 1.0
const SCALES: Array = [0.5, NO_SCALE, 1.5, 2.0, 4.0]
const SCALE_LABELS: Array = ["x0.5", "x1", "x1.5", "x2", "x4"]

## What a party member who did not fight is paid, as a fraction of a fighter's
## own award. The three rungs are the cartridge, Gen 6's Exp. Share and Gen 8's.
const NO_SHARE: float = 0.0
const SHARES: Array = [NO_SHARE, 0.5, 1.0]
const SHARE_LABELS: Array = ["OFF", "HALF", "FULL"]


static func register(host: Gen2ModHost, id: StringName) -> void:
	for key: StringName in KEYS:
		host.register_option(id, {
			"key": key,
			"label": String(LABELS[key]),
			"values": OFF_ON,
			"labels": ["OFF", "ON"],
			"default": 0,
		})
	host.register_option(id, {
		"key": EXP_SCALE,
		"label": "EXP RATE",
		"values": SCALES,
		"labels": SCALE_LABELS,
		"default": NO_SCALE,
	})
	host.register_option(id, {
		"key": MULTI_EXP,
		"label": "MULTI EXP",
		"values": SHARES,
		"labels": SHARE_LABELS,
		"default": NO_SHARE,
	})


static func enabled(host: Gen2ModHost, key: StringName) -> bool:
	if host == null or key not in KEYS:
		return false
	var value: Variant = host.option(MOD_ID, key)
	return value != null and int(value) != 0


static func scale(host: Gen2ModHost) -> float:
	if host == null:
		return NO_SCALE
	var value: Variant = host.option(MOD_ID, EXP_SCALE)
	return NO_SCALE if value == null else float(value)


static func bystander_share(host: Gen2ModHost) -> float:
	if host == null:
		return NO_SHARE
	var value: Variant = host.option(MOD_ID, MULTI_EXP)
	return NO_SHARE if value == null else float(value)
