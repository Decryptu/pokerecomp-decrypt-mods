extends RefCounted

## The settings this mod registers, and the one place that names them.
##
## The entry script registers them and both renderers read them back, so a key
## or a rung written out three times is three chances to disagree. A setting is
## DESCRIBED here and never drawn: the host builds the start menu's MODS entry
## and this mod's card in the launcher out of the same registration, which is why
## no menu is written here. See `docs/MODS.md` in pokerecomp.
##
## Values live per installation in `user://mod_options.json`, not in a save: a
## draw distance is a property of this machine and must not change when a slot is
## loaded.

## What `mod.json` declares. A renderer is handed no manifest, so this is how it
## names itself to the host when reading its own settings back.
const MOD_ID: StringName = &"voxel3d"

const Steering: GDScript = preload("steering.gd")

const DISTANCE: StringName = &"distance"
const WHEEL: StringName = &"wheel"
const CAMERA: StringName = &"camera"
## A setting that is a press rather than a ladder: see `register`.
const RECENTRE: StringName = &"recentre"

## How far out the mesh is built, in walk cells, measured from the player. Zero
## is the whole map, which is what this did before the setting existed and what
## a small map costs nothing to keep doing.
##
## The default is not FULL on purpose. The biggest map meshes whole in 39 ms of
## geometry, and sixteen cells of it is 13 ms for a picture that is the same one:
## the eye sits 190 world pixels back at the default pitch, which frames about
## sixteen cells of ground and no more. What sees past a window is a LOW camera,
## where the frame's top edge runs nearly level and reaches ninety cells out, and
## there the cut edge is visible. That is what FULL is for.
##
## See `world/renderer.gd` for what happens when the player walks out of one.
const DISTANCE_VALUES: Array = [12, 16, 24, 0]

## Which way a wheel notch zooms. The only part of the binding that is a
## preference rather than a decision, which is why it is the only part with a
## setting; `steering.gd` owns the rest and both views share it.
const WHEEL_VALUES: Array = [1, -1]

## The pitch the overworld camera opens at, in degrees above the horizon.
## Near-flat is a street-level shot, near-overhead is the tile page with height
## on it, and the middle rung is what the view was framed at.
const CAMERA_VALUES: Array = [24.0, 50.0, 74.0]

const REGISTERED: Array[Dictionary] = [
	{
		"key": DISTANCE, "label": "DISTANCE",
		"values": DISTANCE_VALUES, "labels": ["12", "16", "24", "FULL"],
		"default": 16,
	},
	{
		"key": WHEEL, "label": "WHEEL",
		"values": WHEEL_VALUES, "labels": ["NORMAL", "INVERTED"],
		"default": 1,
	},
	{
		"key": CAMERA, "label": "CAMERA",
		"values": CAMERA_VALUES, "labels": ["LOW", "MID", "HIGH"],
		"default": 50.0,
	},
]


## The camera's own commands, declared to the host so a player can rebind them
## and reach them from a pad or a thumb. `steering.gd` owns the list, since it
## owns what each one MEANS.
##
## And the same recentre again as a SETTING, which is not a duplicate: an action
## has to be bound to something before it exists, and the one player who most
## needs to put a lost camera back is the one who has not opened the controls
## card. A press in the MODS menu needs no binding at all.
static func register(host: Gen2ModHost, id: StringName) -> void:
	for option: Dictionary in REGISTERED:
		host.register_option(id, option)
	# Feature-detected rather than assumed: `api_version` gates a mod built for
	# an older host, not a host older than the mod, so this is the mod's to check.
	if not host.has_method("register_action"):
		return
	for action: Dictionary in Steering.ACTIONS:
		host.register_action(id, action)
	host.register_option(id, {
		"key": RECENTRE, "label": "CAMERA", "kind": &"button", "press_label": "RECENTRE",
	})


## What the player chose, or [param fallback] when nothing did the registering.
## A renderer loaded on its own, by a probe or a tool, is the case that answers
## null: the entry script never ran, so there is nothing to read.
static func value(key: StringName, fallback: Variant) -> Variant:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null:
		return fallback
	var chosen: Variant = host.option(MOD_ID, key)
	return fallback if chosen == null else chosen


## How hard a control is being HELD, 0 to 1, which is the one thing about the
## bindings a view has to poll rather than be told: an edge cannot say how far a
## stick has travelled and a glide is made of nothing else. A key answers 0 or 1,
## and no host at all answers 0, which is what leaves a probe or a tool with a
## still camera. See `steering.gd:Glide`.
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


## The same for the CONTROLS, which arrive as the mod's own command name rather
## than as an `InputEvent`: whether a key, a pad, a stick or a finger produced it
## is the host's business and not a renderer's.
static func listen_actions(handler: Callable) -> bool:
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host == null or not host.has_signal("action_changed"):
		return false
	host.action_changed.connect(handler)
	return true
