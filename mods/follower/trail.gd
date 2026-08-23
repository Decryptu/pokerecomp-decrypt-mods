extends RefCounted

## Where the follower stands, as one pure function of what the player did.
##
## Nothing here touches a host, a node or the clock: it is fed one observation
## per frame and answers the pose to draw. That is what lets `tools/follower_probe.gd`
## walk a whole route with no game running and get the poses the game would.
##
## THE RULE IS ONE LINE: the follower stands on the cell the player has just
## left. The player's logical cell commits at the START of a step, so the moment
## the player commits A to B the cell behind them is A, and the follower begins
## its own step into it. Both steps then draw with the same fraction, which is
## why the follower needs no frame counter of its own and can never drift a
## frame ahead of or behind the player: `player_step_offset_cells()` is the one
## clock for both.

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
		# A warp, a fly or the first frame of a session. The follower comes back
		# out from under the player rather than walking across the new map to
		# find them, which is also what the cartridge's own `follow` does when a
		# script puts two objects down together.
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


## Into the cell the player left. A single cardinal step is walked; anything
## else is a jump the follower cannot walk, so it is taken at once.
##
## More than one cell commits together whenever a script applies a movement
## stream, and a ledge hop lands two cells away in one commit, so this is the
## ordinary case rather than the strange one.
func _step_toward(target: Vector2i, player_facing: int) -> void:
	var delta: Vector2i = target - _cell
	if delta == Vector2i.ZERO:
		# The player stepped out from on top of the follower, which is the frame
		# after it was placed. It has not walked, so it takes their facing.
		_facing = player_facing
		_direction = Vector2i.ZERO
		return
	_cell = target
	if STEPS.has(delta):
		_facing = int(STEPS[delta])
		_direction = delta
		return
	_direction = Vector2i.ZERO


## Turns the follower to look back at the player, which is what being petted
## asks of it. The player is facing the follower, so the follower faces the way
## they came from; a pose and nothing else, so the cell and the step it is
## drawing are both left where they are.
##
## The mirror of a facing rather than a table of its own: DOWN and UP are 0 and
## 1, LEFT and RIGHT are 2 and 3, so the opposite of any of the four is its own
## index with the low bit flipped.
func face_back(player_facing: int) -> void:
	_facing = clampi(player_facing, Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT) ^ 1


## The facing the next pose will carry, for a caller that has just turned it and
## is answering a read taken on the same frame.
func facing() -> int:
	return _facing


## Puts the follower back under the player on the next frame, which is what a
## recall and a party change both want: it walks out again rather than sliding
## across the map from wherever it was standing.
func reset() -> void:
	_placed = false
