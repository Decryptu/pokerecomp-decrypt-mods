extends RefCounted

## Where the follower stands, as one pure function of what the player did.

const STEPS: Dictionary = {
	Vector2i.DOWN: Gen2WorldSprite.FACING_DOWN,
	Vector2i.UP: Gen2WorldSprite.FACING_UP,
	Vector2i.LEFT: Gen2WorldSprite.FACING_LEFT,
	Vector2i.RIGHT: Gen2WorldSprite.FACING_RIGHT,
}

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

	if not _placed or map != _map:
		_map = map
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
