extends RefCounted

## Population policy for the host's visible-encounter seam. Sprites, collision,
## battle transfer, shiny palettes, animation and audio remain host work.

const Plan := preload("plan.gd")
const SHINY_PULSE_FRAMES: int = 600
## A full cell every 1.6 seconds at the hardware's 60 frames per second. The
## actor seam names integer encounter cells, so moving faster reads as a chain
## of teleports and gives the player no practical route around one.
const MOVE_FRAMES: int = 96

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
	var generation: int = int(context.get("generation", -1))
	var current_generation: int = int(_context.get("generation", -1))
	if generation < current_generation:
		return
	_context = context.duplicate(true)
	if generation == current_generation:
		return
	_rebuild()


func _rebuild() -> void:
	_frame = 0
	_entries = Plan.build(
		_context, int(_context.get("run_seed", 1)), _maximum(), _id
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


func battle_finished(id: StringName, _result: Dictionary) -> void:
	for index: int in _entries.size():
		if StringName((_entries[index] as Dictionary).get("id", &"")) == id:
			_entries.remove_at(index)
			return


func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id == _id and key == &"maximum" and not _context.is_empty():
		_rebuild()


func _maximum() -> int:
	var value: Variant = _host.option(_id, &"maximum") if _host != null else null
	return 6 if value == null else clampi(int(value), 2, 8)


## One step each, into a cell that is eligible and empty.
##
## WHO IS STANDING WHERE IS THE HOST'S ANSWER and refusing them is this file's:
## `occupied` holds the map's own objects, NPCs and item balls alike, both cells
## of one mid-step and all four of a big one. Without it a roamer walked onto an
## NPC and stood inside them, which is what this reads. A wild an NPC walks onto
## is left where it is rather than moved or dropped: the host keeps drawing it,
## and it steps off on its own at the next move.
func _roam() -> void:
	var eligible: Dictionary = _context.get("eligible", {})
	var player: Dictionary = _context.get("player", {})
	var player_cell: Vector2i = Vector2i(player.get("cell", Vector2i(-1, -1)))
	var occupied: PackedVector2Array = _context.get("occupied", PackedVector2Array())
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		var method: StringName = StringName(entry.get("method", &""))
		if method == &"":
			continue
		var cells: PackedVector2Array = eligible.get(method, PackedVector2Array())
		var here: Vector2i = Vector2i(entry["cell"])
		var choices: Array[Vector2i] = []
		for delta: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + delta
			if next != player_cell and cells.has(next) \
					and not occupied.has(Vector2(next)) and not _standing_at(next):
				choices.append(next)
		if choices.is_empty():
			continue
		var pick: int = (index + 1 + _frame / MOVE_FRAMES) % choices.size()
		entry["cell"] = choices[pick]
		entry["facing"] = _facing(choices[pick] - here)


## Whether one of this provider's own wilds is already there. The map's objects
## are the host's answer and arrive in the context; see `_roam`.
func _standing_at(cell: Vector2i) -> bool:
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
