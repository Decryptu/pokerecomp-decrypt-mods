extends RefCounted

## The settings this mod registers, and the one place that names them.

const MOD_ID: StringName = &"voxel3d"

const Steering: GDScript = preload("steering.gd")

const DISTANCE: StringName = &"distance"
const SCALE: StringName = &"scale"
const WHEEL: StringName = &"wheel"
const CAMERA: StringName = &"camera"
const RECENTRE: StringName = &"recentre"

const DISTANCE_VALUES: Array = [12, 16, 24, 0]

const SCALE_VALUES: Array = [1, 2, 3, 4]

const WHEEL_VALUES: Array = [1, -1]

const CAMERA_VALUES: Array = [14.0, 24.0, 50.0, 74.0]

const REGISTERED: Array[Dictionary] = [
	{
		"key": DISTANCE, "label": "DISTANCE",
		"values": DISTANCE_VALUES, "labels": ["12", "16", "24", "FULL"],
		"default": 16,
	},
	{
		"key": SCALE, "label": "RES",
		"values": SCALE_VALUES, "labels": ["FULL", "1/2", "1/3", "1/4"],
		"default": 1,
	},
	{
		"key": WHEEL, "label": "WHEEL",
		"values": WHEEL_VALUES, "labels": ["NORMAL", "INVERTED"],
		"default": 1,
	},
	{
		"key": CAMERA, "label": "ANGLE",
		"values": CAMERA_VALUES, "labels": ["LEVEL", "LOW", "MID", "HIGH"],
		"default": 50.0,
	},
]


static func register(host: Gen2ModHost, id: StringName) -> void:
	for option: Dictionary in REGISTERED:
		var row: Dictionary = option
		if row["key"] == SCALE:
			row = option.duplicate()
			row["default"] = default_scale()
		host.register_option(id, row)
	if not host.has_method("register_action"):
		return
	for action: Dictionary in Steering.ACTIONS:
		host.register_action(id, action)
	host.register_option(id, {
		"key": RECENTRE, "label": "CAMERA", "kind": &"button", "press_label": "RECENTRE",
	})


static func default_scale() -> int:
	return 2 if OS.has_feature("mobile") else 1


static func value(key: StringName, fallback: Variant) -> Variant:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null:
		return fallback
	var chosen: Variant = host.option(MOD_ID, key)
	return fallback if chosen == null else chosen


static func strength(key: StringName) -> float:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null or not host.has_method("action_strength"):
		return 0.0
	return host.action_strength(MOD_ID, key)


static func listen(handler: Callable) -> bool:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null:
		return false
	host.option_changed.connect(handler)
	return true


static func listen_actions(handler: Callable) -> bool:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null or not host.has_signal("action_changed"):
		return false
	host.action_changed.connect(handler)
	return true
