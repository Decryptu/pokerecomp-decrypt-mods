extends RefCounted

## The follower as the host drives it: one observation a frame in, one sprite
## out, no writes.

const Options := preload("options.gd")
const Party := preload("party.gd")
const Trail := preload("trail.gd")
const Finder := preload("finder.gd")

const HEART_FRAMES: int = 60

var _host: Gen2ModHost = null
var _id: StringName = &"follower"
var _world: Gen2WorldAPI = null
var _trail: RefCounted = Trail.new()
var _settings: Dictionary = Options.settings(null)
var _recalled: bool = false
var _pose: Dictionary = {}
var _heart: int = 0
var _outbox: Array = []
var _stood_at := Vector2i.MAX
var _map := Vector2i(-1, -1)


func configure(host: Gen2ModHost, id: StringName) -> void:
	_host = host
	_id = id
	_settings = Options.settings(host)
	host.option_changed.connect(_on_option_changed)
	host.action_changed.connect(_on_action_changed)


func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	_pose = {}
	_heart = 0
	_stood_at = Vector2i.MAX


func advance_frame() -> void:
	if _world == null:
		return
	_heart = maxi(0, _heart - 1)
	var map: Vector2i = _world.map_id()
	_pose = _trail.observe({
		"map": map,
		"shift": _carry_shift(map),
		"cell": _world.player_cell,
		"facing": _world.player_facing,
		"span": _world.player_step_span(),
		"allowed": _allowed(),
	})
	_map = map
	_look_for_an_item()


## Where the map just left sits in the one now loaded, in cells, off the host's
## own connection graph. `map_placements` holds every map the graph reaches from
## this one, so a crossing answers a shift and a warp into an unconnected map
## answers none.
func _carry_shift(map: Vector2i) -> Vector2i:
	if map == _map or _map.x < 0:
		return Vector2i.ZERO
	var placement: Dictionary = _world.map_placements().get(
		"%d:%d" % [_map.x, _map.y], {}
	)
	if placement.is_empty():
		return Trail.NO_CARRY
	return Vector2i(placement["origin"]) * Gen2Layout.MAP_BLOCK_CELL_WIDTH


func sprites() -> Array:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return []
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return []
	var pose: Dictionary = _trail.drawn(Trail.progress_of(_world.player_step_span()))
	var entry: Dictionary = {
		"icon": int(member["icon"]),
		"facing": _trail.facing(),
		"position_cells": Vector2(pose["cell"] as Vector2i) + (pose["offset"] as Vector2),
		"span": pose["span"],
	}
	if _heart > 0:
		entry["emote"] = Gen2WorldActors.EMOTE_HEART
	return [entry]


func interact(cell: Vector2i, facing: int) -> bool:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return false
	if cell != (_pose["cell"] as Vector2i):
		return false
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return false
	_trail.face_back(facing)
	_heart = HEART_FRAMES
	_outbox.append({
		"kind": Gen2WorldActors.REQUEST_CRY, "species": int(member["species"]),
	})
	return true


func take_requests() -> Array:
	var out: Array = _outbox
	_outbox = []
	return out


func _look_for_an_item() -> void:
	if _host == null or not bool(_settings[Options.PICKUP]):
		return
	if _pose.is_empty() or not bool(_pose.get("out", false)):
		return
	if (_pose["offset"] as Vector2) != Vector2.ZERO:
		return
	var cell: Vector2i = _pose["cell"]
	if cell == _stood_at:
		return
	_stood_at = cell
	var record: Dictionary = Finder.reach(
		_world.hidden_items(), cell, _world.can_walk_to
	)
	if record.is_empty():
		return
	_host.request_hidden_item(record["cell"])


func _allowed() -> bool:
	if _recalled or not _world.party_with_player():
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


func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id != _id:
		return
	if key == Options.PUT_AWAY:
		_toggle_recall()
		return
	if not Options.owns(key):
		return
	_settings = Options.settings(_host)
	if key == Options.SLOT:
		_trail.reset()


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != _id or key != Options.RECALL or not pressed:
		return
	_toggle_recall()


func _toggle_recall() -> void:
	_recalled = not _recalled
	_heart = 0
	if not _recalled:
		_trail.reset()
