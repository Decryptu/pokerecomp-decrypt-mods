extends RefCounted

## Population policy for the host's visible-encounter seam.

const Options := preload("options.gd")
const Plan := preload("plan.gd")
const Rng := preload("rng.gd")
const REFRESH_DOMAIN: int = 0x52465348
const SHINY_PULSE_FRAMES: int = 600
const GLOW_PERIOD_FRAMES: int = 48
const GLOW_PEAK: float = 0.45
const GLOW_COLOR := Color(1.0, 0.87, 0.35)
const MOVE_FRAMES: int = 96

const DESPAWN_MIN_FRAMES: int = 30 * 60
const DESPAWN_MAX_FRAMES: int = 60 * 60
const DESPAWN_AT: StringName = &"despawn_at"

const REFILL_FRAMES: int = 30

var _host: Gen2ModHost = null
var _id: StringName = &""
var _context: Dictionary = {}
var _entries: Array = []
var _frame: int = 0
var _refresh: RefCounted = null
var _next_number: int = 1


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
	var seed_value: int = int(_context.get("run_seed", 1))
	var maximum: int = _maximum()
	_entries = Plan.build(_context, seed_value, maximum, _id)
	var map: Vector2i = Vector2i(_context.get("map", Vector2i.ZERO))
	_refresh = Rng.new(Rng.mix(seed_value, [
		map.x, map.y, int(_context.get("generation", 0)), REFRESH_DOMAIN
	]))
	_next_number = Plan.first_free_number(maximum)
	for entry: Dictionary in _entries:
		entry["pulse"] = true
		_stamp_despawn(entry)


func advance_frame() -> void:
	_frame += 1
	if _frame % MOVE_FRAMES == 0:
		_roam()
	var pulse: bool = _frame % SHINY_PULSE_FRAMES == 0
	var amount: float = _glow_amount()
	for entry: Dictionary in _entries:
		entry["pulse"] = pulse
		if Plan.is_excellent(int(entry.get("dvs", 0))):
			entry["glow"] = {"color": GLOW_COLOR, "amount": amount}
	_retire()
	_refill()


func encounters() -> Array:
	return _entries.duplicate(true)


func battle_finished(id: StringName, _result: Dictionary) -> void:
	for index: int in _entries.size():
		if StringName((_entries[index] as Dictionary).get("id", &"")) == id:
			_entries.remove_at(index)
			return


func _stamp_despawn(entry: Dictionary) -> void:
	if Plan.is_shiny(int(entry.get("dvs", 0))):
		entry.erase(DESPAWN_AT)
		return
	entry[DESPAWN_AT] = _frame + DESPAWN_MIN_FRAMES + _refresh.below(
		DESPAWN_MAX_FRAMES - DESPAWN_MIN_FRAMES + 1
	)


func _retire() -> void:
	for index: int in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if entry.has(DESPAWN_AT) and _frame >= int(entry[DESPAWN_AT]):
			_entries.remove_at(index)


func _refill() -> void:
	if _refresh == null or _frame % REFILL_FRAMES != 0:
		return
	if _entries.size() >= _maximum():
		return
	var taken: Array[Vector2i] = []
	for entry: Dictionary in _entries:
		taken.append(Vector2i(entry["cell"]))
	var entry: Dictionary = Plan.mint(_context, _refresh, taken, _next_number, _id)
	if entry.is_empty():
		return
	_next_number += 1
	entry["pulse"] = true
	_stamp_despawn(entry)
	_entries.append(entry)


func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id == _id and key == Options.MAXIMUM and not _context.is_empty():
		_rebuild()


func _glow_amount() -> float:
	var phase: float = TAU * float(_frame % GLOW_PERIOD_FRAMES) / float(GLOW_PERIOD_FRAMES)
	return GLOW_PEAK * 0.5 * (1.0 - cos(phase))


func _maximum() -> int:
	return Options.maximum(_host, _id)


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
