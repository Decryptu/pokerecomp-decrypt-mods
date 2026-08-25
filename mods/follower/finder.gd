extends RefCounted

## Which hidden item the follower can reach, as one pure function of where it
## stands. It touches no host and no node, so `tools/follower_probe.gd` can ask
## the rule of a made-up map.
##
## The rule: take what it is standing on. Failing that, reach one cardinal step
## into a cell it could not have walked into, which is the item under a rock,
## inside a wall or across a ledge. A hidden item on open floor beside it is left
## alone, since the follower can simply walk over that one.

## The four, in the order that settles a tie. Same order as `trail.gd`'s steps,
## so the answer never depends on the order the cartridge wrote its events in.
const AROUND: Array[Vector2i] = [
	Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT,
]


## The record to ask the host for, or empty when the follower reaches none.
##
## [param records] is `Gen2WorldAPI.hidden_items()`, [param cell] the follower's
## own, and [param walkable] a `func(cell: Vector2i, from: Vector2i) -> bool`
## answering whether the follower could step into that cell from this one.
static func reach(records: Array, cell: Vector2i, walkable: Callable) -> Dictionary:
	var under: Dictionary = _at(records, cell)
	if not under.is_empty():
		return under
	if not walkable.is_valid():
		return {}
	for direction: Vector2i in AROUND:
		var neighbour: Vector2i = cell + direction
		if bool(walkable.call(neighbour, direction)):
			continue
		var beside: Dictionary = _at(records, neighbour)
		if not beside.is_empty():
			return beside
	return {}


## The first untaken record on [param cell]. No cartridge map has two on one
## cell, and the first is what a player would get.
static func _at(records: Array, cell: Vector2i) -> Dictionary:
	for record: Variant in records:
		if not record is Dictionary:
			continue
		var row: Dictionary = record
		if bool(row.get("taken", false)):
			continue
		if Vector2i(row.get("cell", Vector2i.ZERO)) == cell:
			return row
	return {}
