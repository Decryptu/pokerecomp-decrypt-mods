extends RefCounted

## Population policy for the host's visible-encounter seam. Sprites, collision,
## battle transfer, shiny palettes, animation and audio remain host work.

const Plan := preload("plan.gd")
const SHINY_PULSE_FRAMES: int = 600
const MOVE_FRAMES: int = 32

var _host: Gen2ModHost = null
var _id: StringName = &""
var _context: Dictionary = {}
var _entries: Array = []
var _frame: int = 0


func configure(host: Gen2ModHost, id: StringName) -> void:
	_host = host
	_id = id
	host.option_changed.connect(_on_option_changed)


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	_frame = 0
	_entries = Plan.build(
		_context, int(_context.get("run_seed", 1)), _maximum()
	)
	for entry: Dictionary in _entries:
		entry["pulse"] = true


func advance_frame() -> void:
	_frame += 1
	if _frame % MOVE_FRAMES == 0:
		_roam()
	var pulse: bool = _frame % SHINY_PULSE_FRAMES == 0
	for entry: Dictionary in _entries:
		entry["pulse"] = pulse


func encounters() -> Array:
	return _entries.duplicate(true)


func battle_finished(id: int, _result: Dictionary) -> void:
	for index: int in _entries.size():
		if int((_entries[index] as Dictionary).get("id", -1)) == id:
			_entries.remove_at(index)
			return


func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id == _id and key == &"maximum" and not _context.is_empty():
		set_context(_context)


func _maximum() -> int:
	var value: Variant = _host.option(_id, &"maximum") if _host != null else null
	return 6 if value == null else clampi(int(value), 2, 8)


func _roam() -> void:
	var eligible: Dictionary = _context.get("eligible", {})
	for entry: Dictionary in _entries:
		var method: StringName = StringName(entry.get("method", &""))
		if method == &"":
			continue
		var cells: Array = eligible.get(method, [])
		var here: Vector2i = Vector2i(entry["cell"])
		var choices: Array[Vector2i] = []
		for delta: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + delta
			if cells.has(next) and not _occupied(next):
				choices.append(next)
		if choices.is_empty():
			continue
		var pick: int = (int(entry["id"]) + _frame / MOVE_FRAMES) % choices.size()
		entry["cell"] = choices[pick]
		entry["facing"] = _facing(choices[pick] - here)


func _occupied(cell: Vector2i) -> bool:
	for entry: Dictionary in _entries:
		if Vector2i(entry["cell"]) == cell:
			return true
	return false


func _facing(delta: Vector2i) -> int:
	if delta == Vector2i.UP:
		return 1
	if delta == Vector2i.LEFT:
		return 2
	if delta == Vector2i.RIGHT:
		return 3
	return 0
