extends RefCounted

## Where the follower stands, as one pure function of what the player did.

const STEPS: Dictionary = {
	Vector2i.DOWN: Gen2WorldSprite.FACING_DOWN,
	Vector2i.UP: Gen2WorldSprite.FACING_UP,
	Vector2i.LEFT: Gen2WorldSprite.FACING_LEFT,
	Vector2i.RIGHT: Gen2WorldSprite.FACING_RIGHT,
}

## What an observation carries where the map changed for a reason that renumbers
## nothing: a warp, a Fly, the first frame of a session.
const NO_CARRY: Vector2i = Vector2i.MAX

var _map: Vector2i = Vector2i(-1, -1)
var _cell: Vector2i = Vector2i.ZERO
var _facing: int = Gen2WorldSprite.FACING_DOWN
var _direction: Vector2i = Vector2i.ZERO
var _player_cell: Vector2i = Vector2i.ZERO
var _placed: bool = false


func observe(observation: Dictionary) -> Dictionary:
	var map: Vector2i = observation.get("map", Vector2i.ZERO)
	var player_cell: Vector2i = observation.get("cell", Vector2i.ZERO)
	var player_facing: int = int(observation.get("facing", Gen2WorldSprite.FACING_DOWN))
	var offset: Vector2 = observation.get("offset", Vector2.ZERO)

	if map != _map:
		_map = map
		_carry(observation.get("shift", NO_CARRY), player_cell)
	if not _placed:
		_cell = player_cell
		_facing = player_facing
		_direction = Vector2i.ZERO
		_placed = true
	elif player_cell != _player_cell:
		_step_toward(_player_cell, player_facing)
	if offset == Vector2.ZERO:
		_direction = Vector2i.ZERO
	_player_cell = player_cell

	var drawn: Vector2 = Vector2.ZERO
	if _direction != Vector2i.ZERO:
		drawn = -Vector2(_direction) * offset.length()
	return {
		"out": bool(observation.get("allowed", true)) and _cell != player_cell,
		"cell": _cell,
		"offset": drawn,
		"facing": _facing,
	}


## Crossing a connection renumbers every cell of the map left behind, so the
## follower is carried into the new numbering and keeps walking. A map change
## that is not a crossing carries nothing, and a warp between two maps the graph
## does join is told from a crossing by the step: the player walks over a
## connection one cell at a time, so the cell they came from is beside the one
## they are on. Both put the follower back under them.
func _carry(shift: Vector2i, player_cell: Vector2i) -> void:
	if not _placed or shift == NO_CARRY:
		_placed = false
		return
	_cell += shift
	_player_cell += shift
	if absi(_player_cell.x - player_cell.x) + absi(_player_cell.y - player_cell.y) > 1:
		_placed = false


func _step_toward(target: Vector2i, player_facing: int) -> void:
	var delta: Vector2i = target - _cell
	if delta == Vector2i.ZERO:
		_facing = player_facing
		_direction = Vector2i.ZERO
		return
	_cell = target
	if STEPS.has(delta):
		_facing = int(STEPS[delta])
		_direction = delta
		return
	_direction = Vector2i.ZERO


func face_back(player_facing: int) -> void:
	_facing = clampi(player_facing, Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT) ^ 1


func facing() -> int:
	return _facing


func reset() -> void:
	_placed = false
