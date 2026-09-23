extends RefCounted

const Catalogue := preload("catalogue.gd")

const VERSION: int = 1
const KEY_VERSION: String = "version"
const KEY_UNLOCKED: String = "unlocked"

const QUIET_ABOVE: int = 3

var unlocked: Dictionary = {}

var _rows: Array[Dictionary] = []
var _recorded: bool = false


func _init(rows: Array[Dictionary]) -> void:
	_rows = rows


func restore(saved: Dictionary) -> void:
	unlocked = {}
	_recorded = int(saved.get(KEY_VERSION, 0)) == VERSION
	if not _recorded:
		return
	var stored_ids: Variant = saved.get(KEY_UNLOCKED, [])
	if not stored_ids is Array:
		return
	for id: Variant in stored_ids as Array:
		unlocked[StringName(id)] = true


func stored() -> Dictionary:
	var ids: Array = []
	for id: StringName in unlocked:
		ids.append(String(id))
	ids.sort()
	return {KEY_VERSION: VERSION, KEY_UNLOCKED: ids}


func closed() -> void:
	unlocked = {}
	_recorded = false


func scan(progress: Dictionary) -> Dictionary:
	var fresh: Array[StringName] = []
	for id: StringName in Catalogue.held(_rows, progress):
		if unlocked.has(id):
			continue
		unlocked[id] = true
		fresh.append(id)
	var quiet: bool = not _recorded or fresh.size() > QUIET_ABOVE
	_recorded = true
	return {"unlocked": fresh, "quiet": quiet}


func progress_counts() -> Vector2i:
	var held: int = 0
	for row: Dictionary in _rows:
		if unlocked.has(StringName(row["id"])):
			held += 1
	return Vector2i(held, _rows.size())


func has(id: StringName) -> bool:
	return unlocked.has(id)
