extends RefCounted

## Which hidden item the follower can reach, as one pure function of where it
## stands.

const AROUND: Array[Vector2i] = [
	Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT,
]


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
