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

## The host's own names for the two moves a follower makes; a hop covers two.
const KIND_STEP: StringName = &"step"
const KIND_HOP: StringName = &"jump_step"

var _map: Vector2i = Vector2i(-1, -1)
var _cell: Vector2i = Vector2i.ZERO
var _facing: int = Gen2WorldSprite.FACING_DOWN
var _direction: Vector2i = Vector2i.ZERO
var _kind: StringName = KIND_STEP
var _player_cell: Vector2i = Vector2i.ZERO
var _placed: bool = false


func observe(observation: Dictionary) -> Dictionary:
	var map: Vector2i = observation.get("map", Vector2i.ZERO)
	var player_cell: Vector2i = observation.get("cell", Vector2i.ZERO)
	var player_facing: int = int(observation.get("facing", Gen2WorldSprite.FACING_DOWN))
	var span: Dictionary = observation.get("span", {})

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
	if span.is_empty():
		_direction = Vector2i.ZERO
	_player_cell = player_cell

	var pose: Dictionary = drawn(progress_of(span))
	pose["out"] = bool(observation.get("allowed", true)) and _cell != player_cell
	return pose


## The follower's progress is the player's, so it arrives when they do whatever
## either step cost. A distance cannot say this: a hop covers two cells.
static func progress_of(span: Dictionary) -> float:
	return 1.0 if span.is_empty() else float(span["progress"])


## SMOOTH SCROLL moves this between two hardware frames, so it is a read the
## host asks again every drawn frame rather than a pose held from [method
## observe]. The span is the same move for a view that folds plan into height.
func drawn(progress: float) -> Dictionary:
	if _direction == Vector2i.ZERO:
		return {"cell": _cell, "offset": Vector2.ZERO, "span": {}}
	return {
		"cell": _cell,
		"offset": -Vector2(_direction) * (1.0 - progress),
		"span": {
			"from": _cell - _direction,
			"to": _cell,
			"progress": progress,
			"kind": _kind,
		},
	}


## Crossing a connection renumbers every cell of the map left behind, so the
## follower is carried into the new numbering and keeps walking. A crossing is
## told from a warp by the step: the player walks over a connection one cell at
## a time, so the cell they came from is beside the one they are on.
func _carry(shift: Vector2i, player_cell: Vector2i) -> void:
	if not _placed or shift == NO_CARRY:
		_placed = false
		return
	_cell += shift
	_player_cell += shift
	if absi(_player_cell.x - player_cell.x) + absi(_player_cell.y - player_cell.y) > 1:
		_placed = false


## The player's last move, replayed a move behind them. Two cells of one
## direction is a ledge, so the follower takes it rather than being put down.
func _step_toward(target: Vector2i, player_facing: int) -> void:
	var delta: Vector2i = target - _cell
	if delta == Vector2i.ZERO:
		_facing = player_facing
		_direction = Vector2i.ZERO
		return
	_cell = target
	var way := Vector2i(signi(delta.x), signi(delta.y))
	if STEPS.has(way) and (delta == way or delta == way * 2):
		_facing = int(STEPS[way])
		_direction = delta
		_kind = KIND_STEP if delta == way else KIND_HOP
		return
	_direction = Vector2i.ZERO


func face_back(player_facing: int) -> void:
	_facing = clampi(player_facing, Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT) ^ 1


func facing() -> int:
	return _facing


func reset() -> void:
	_placed = false
