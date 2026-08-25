extends RefCounted

## The settings this mod registers, and the one place that names them.
##
## The entry script registers them and both renderers read them back, so writing
## a key or a rung three times is three chances to disagree. Described and never
## drawn: the host builds the MODS entry and the mod's page out of the same
## registration. See `docs/MODS.md` in pokerecomp.
##
## Values live per installation in `user://mod_options.json`, not in a save: a
## draw distance must not change when a slot is loaded.

## What `mod.json` declares. A renderer is handed no manifest, so this is how it
## names itself when reading its settings back.
const MOD_ID: StringName = &"voxel3d"

const Steering: GDScript = preload("steering.gd")

const DISTANCE: StringName = &"distance"
const SCALE: StringName = &"scale"
const WHEEL: StringName = &"wheel"
const CAMERA: StringName = &"camera"
## A setting that is a press rather than a ladder: see `register`.
const RECENTRE: StringName = &"recentre"

## How far out the mesh is built, in walk cells from the player. Zero is the
## whole map.
##
## The default is not FULL on purpose: the biggest map meshes whole in 39 ms and
## sixteen cells of it in 13 ms for the same picture, since the eye sits 190 world
## pixels back at the default pitch and frames about sixteen cells. A LOW camera
## reaches ninety cells out and does see the cut edge, which is what FULL is for.
##
## See `world/renderer.gd` for what happens when the player walks out of one.
const DISTANCE_VALUES: Array = [12, 16, 24, 0]

## How many window pixels the 3D pass draws one of. See
## `world/diorama.gd:set_render_scale` for why this is the one rung that matters
## on a device that cannot afford the window it was given.
##
## The default is by platform, not taste: a desktop draws the whole window and a
## phone starts at a half, since there is no benchmarking a phone from here.
const SCALE_VALUES: Array = [1, 2, 3, 4]

## Which way a wheel notch zooms. The only part of the binding that is a
## preference rather than a decision, which is why it is the only part with a
## setting; `steering.gd` owns the rest and both views share it.
const WHEEL_VALUES: Array = [1, -1]

## The pitch the overworld camera opens at, in degrees above the horizon.
## Near-flat is a street-level shot, near-overhead is the tile page with height
## on it, and the middle rung is what the view was framed at.
const CAMERA_VALUES: Array = [14.0, 24.0, 50.0, 74.0]

## The shallowest rung is not a fourth taste: it is what makes the sky reachable
## from the menu at all. The eye looks down by its own pitch, so with a 42 degree
## lens the frame's top edge sits at 21 degrees minus the pitch, and every other
## rung puts that edge below the horizon. 14 puts seven degrees of sky in frame;
## the rig's own floor is 12.

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
		# ANGLE and not CAMERA: the recentre button below is the camera's row.
		"key": CAMERA, "label": "ANGLE",
		"values": CAMERA_VALUES, "labels": ["LEVEL", "LOW", "MID", "HIGH"],
		"default": 50.0,
	},
]


## The camera's commands, declared to the host so a player can rebind them and
## reach them from a pad or a thumb. `steering.gd` owns the list.
##
## The recentre appears again as a menu row, which is not a duplicate: an action
## has to be bound before it exists, and a menu press needs no binding.
static func register(host: Gen2ModHost, id: StringName) -> void:
	for option: Dictionary in REGISTERED:
		var row: Dictionary = option
		if row["key"] == SCALE:
			row = option.duplicate()
			row["default"] = default_scale()
		host.register_option(id, row)
	# Feature-detected: `api_version` gates a mod built for an older host, not a
	# host older than the mod.
	if not host.has_method("register_action"):
		return
	for action: Dictionary in Steering.ACTIONS:
		host.register_action(id, action)
	host.register_option(id, {
		"key": RECENTRE, "label": "CAMERA", "kind": &"button", "press_label": "RECENTRE",
	})


## The rung this device opens at. See SCALE_VALUES.
static func default_scale() -> int:
	return 2 if OS.has_feature("mobile") else 1


## What the player chose, or [param fallback] when nothing registered. A renderer
## loaded on its own by a probe or a tool is the case: the entry script never ran.
static func value(key: StringName, fallback: Variant) -> Variant:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null:
		return fallback
	var chosen: Variant = host.option(MOD_ID, key)
	return fallback if chosen == null else chosen


## How hard a control is being held, 0 to 1: the one thing a view has to poll
## rather than be told, since an edge cannot say how far a stick has travelled. A
## key answers 0 or 1, and no host answers 0. See `steering.gd:Glide`.
static func strength(key: StringName) -> float:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null or not host.has_method("action_strength"):
		return 0.0
	return host.action_strength(MOD_ID, key)


## Connects [param handler] to the host's own change signal, so a view reacts to
## a press instead of polling. Answers false when there is no host to listen to.
static func listen(handler: Callable) -> bool:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null:
		return false
	host.option_changed.connect(handler)
	return true


## The same for the controls, which arrive as the mod's own command name rather
## than as an `InputEvent`: what produced it is the host's business.
static func listen_actions(handler: Callable) -> bool:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null or not host.has_signal("action_changed"):
		return false
	host.action_changed.connect(handler)
	return true
