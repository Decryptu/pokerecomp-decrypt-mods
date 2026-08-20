extends RefCounted

## Which hidden item the follower can reach, as one pure function of where it
## stands.
##
## Nothing here touches a host or a node: it is handed the map's own hidden-item
## records, the cell the follower is on and a test for whether a cell can be
## walked into, and answers the record to ask the host for. That is what lets
## `tools/follower_probe.gd` ask the rule of a made-up map with no game running.
##
## THE RULE IS TWO LINES. The follower takes what it is standing on, which is
## what a player pressing A on that cell would get. Failing that it reaches ONE
## cardinal step into a cell it could not have walked into, which is the item
## under a rock, inside a wall or across a ledge; a hidden item on open floor
## beside it is left alone, because the follower can simply walk over that one
## and reaching for it would empty a route from a cell away.

## The four, in the order a tie between two of them is settled: the same order
## `trail.gd` names its steps in, so the answer is the map's and never the order
## the cartridge happened to write its background events in.
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


## The first untaken record on [param cell]. A map with two on one cell is not a
## thing the cartridge has, and taking the first is what a player would get.
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
