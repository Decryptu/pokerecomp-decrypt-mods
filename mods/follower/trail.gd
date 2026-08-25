extends RefCounted

## Where the follower stands, as one pure function of what the player did.
##
## It touches no host, node or clock: one observation per frame in, one pose out.
## That is what lets `tools/follower_probe.gd` walk a route with no game running.
##
## The rule: the follower stands on the cell the player has just left. The
## player's logical cell commits at the start of a step, so the moment they
## commit A to B the cell behind them is A and the follower steps into it. Both
## steps draw with the same fraction, so the follower needs no frame counter and
## cannot drift.

const STEPS: Dictionary = {
	Vector2i.DOWN: Gen2WorldSprite.FACING_DOWN,
	Vector2i.UP: Gen2WorldSprite.FACING_UP,
	Vector2i.LEFT: Gen2WorldSprite.FACING_LEFT,
	Vector2i.RIGHT: Gen2WorldSprite.FACING_RIGHT,
}

var _map: Vector2i = Vector2i(-1, -1)
var _cell: Vector2i = Vector2i.ZERO
var _facing: int = Gen2WorldSprite.FACING_DOWN
## The cardinal step being drawn, or zero while the follower stands still.
var _direction: Vector2i = Vector2i.ZERO
var _player_cell: Vector2i = Vector2i.ZERO
var _placed: bool = false


## One frame. [param observation] carries `map` and `cell` as `Vector2i`,
## `facing` as a `Gen2WorldSprite` facing, `offset` as the player's own in-flight
## step in fractional cells, and `allowed`, which is everything the settings and
## the party have to say about whether the follower is out at all.
##
## Answers `{ out, cell, offset, facing }`: `cell` is the logical cell the
## follower has committed to and `offset` the fraction of a cell still to walk
## into it, in the same sign the host's own step offset uses, so a renderer draws
## at `cell + offset` exactly as it draws the player.
func observe(observation: Dictionary) -> Dictionary:
	var map: Vector2i = observation.get("map", Vector2i.ZERO)
	var player_cell: Vector2i = observation.get("cell", Vector2i.ZERO)
	var player_facing: int = int(observation.get("facing", Gen2WorldSprite.FACING_DOWN))
	var offset: Vector2 = observation.get("offset", Vector2.ZERO)

	if not _placed or map != _map:
		# A warp, a Fly or the first frame of a session: come back out from under
		# the player rather than walking across the new map, which is what the
		# cartridge's own `follow` does.
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


## Into the cell the player left. A single cardinal step is walked; anything else
## is taken at once, which is the ordinary case: a scripted movement stream and a
## ledge hop both commit more than one cell together.
func _step_toward(target: Vector2i, player_facing: int) -> void:
	var delta: Vector2i = target - _cell
	if delta == Vector2i.ZERO:
		# The player stepped off the follower, the frame after it was placed. It
		# has not walked, so it takes their facing.
		_facing = player_facing
		_direction = Vector2i.ZERO
		return
	_cell = target
	if STEPS.has(delta):
		_facing = int(STEPS[delta])
		_direction = delta
		return
	_direction = Vector2i.ZERO


## Turns the follower to look back at the player, which is what petting asks of
## it. A pose and nothing else: the cell and the step being drawn stay put.
##
## DOWN and UP are 0 and 1 and LEFT and RIGHT are 2 and 3, so the opposite facing
## is the same index with the low bit flipped.
func face_back(player_facing: int) -> void:
	_facing = clampi(player_facing, Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT) ^ 1


## The facing the next pose will carry, for a caller that just turned it.
func facing() -> int:
	return _facing


## Puts the follower back under the player next frame, so a recall or a party
## change walks it out again rather than sliding it across the map.
func reset() -> void:
	_placed = false
