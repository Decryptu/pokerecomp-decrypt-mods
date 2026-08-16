extends RefCounted

## The follower as the host drives it: one observation a frame in, one sprite
## out, and no writes at all.
##
## This is the shape `register_world_actor` asks for, which is the seam the
## engine owes this mod and the one thing it cannot run without today.
## Everything below it reads is already public
## on `Gen2WorldAPI` and everything it draws with is already the host's: a
## sprite here names the cartridge's own icon row and nothing else, so the host
## resolves the strip, the palette, the time of day and the icon's own animation
## rate exactly as it does for a mon-icon object standing on a map.
##
## Not a scene node and never one. A follower is a pose, and the pose layer is
## `docs/MODS.md`'s own answer to a mod that wants one.

const Options := preload("options.gd")
const Party := preload("party.gd")
const Trail := preload("trail.gd")

var _host: Gen2ModHost = null
var _id: StringName = &"follower"
var _world: Gen2WorldAPI = null
var _trail: RefCounted = Trail.new()
## What the player last chose, read on a change rather than every frame.
var _settings: Dictionary = Options.settings(null)
## Whether the recall control has put the follower away. Per session and not per
## save: the host hands a mod its own save namespace through the manifest, and
## an actor is handed a world, so a recall that outlives a reload is a thing to
## ask for once anything wants it.
var _recalled: bool = false
var _pose: Dictionary = {}


func configure(host: Gen2ModHost, id: StringName) -> void:
	_host = host
	_id = id
	_settings = Options.settings(host)
	host.option_changed.connect(_on_option_changed)
	host.action_changed.connect(_on_action_changed)


## The map changed, or the view was created.
func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	_pose = {}


## One world frame, after the player's own step has advanced.
func advance_frame() -> void:
	if _world == null:
		return
	_pose = _trail.observe({
		"map": _world.map_id(),
		"cell": _world.player_cell,
		"facing": _world.player_facing,
		"offset": _world.player_step_offset_cells(),
		"allowed": _allowed(),
	})


## What to draw, in the order to draw it. A read, so a second view asking again
## in the same frame gets the same answer.
func sprites() -> Array:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return []
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return []
	return [{
		"icon": int(member["icon"]),
		"facing": int(_pose["facing"]),
		"position_cells": Vector2(_pose["cell"] as Vector2i) + (_pose["offset"] as Vector2),
	}]


## Whether anything should be out at all: the recall control, the two movement
## settings, and a party that has someone to send.
func _allowed() -> bool:
	if _recalled:
		return false
	var mode: StringName = _world.movement_mode
	if mode == Gen2WorldAPI.MOVEMENT_BIKE and not bool(_settings[Options.CYCLING]):
		return false
	if mode == Gen2WorldAPI.MOVEMENT_SURF and not bool(_settings[Options.SURFING]):
		return false
	return bool(_member().get("out", false))


func _member() -> Dictionary:
	return Party.member(
		_world.party_summary(), _world.data, int(_settings[Options.SLOT])
	)


## A slot or a movement setting moved. The follower comes back out from under
## the player rather than sliding across the map from where the last one stood.
func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id != _id or not Options.owns(key):
		return
	_settings = Options.settings(_host)
	if key == Options.SLOT:
		_trail.reset()


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != _id or key != Options.RECALL or not pressed:
		return
	_recalled = not _recalled
	if not _recalled:
		_trail.reset()
