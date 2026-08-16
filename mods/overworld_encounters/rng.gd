extends RefCounted

## A fixed integer generator. Spawn plans are save-run facts, so the algorithm
## is written here rather than inherited from a Godot release.

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	_state = seed_value & 0x7fffffff
	if _state == 0:
		_state = 1


func next() -> int:
	_state = int((1103515245 * _state + 12345) & 0x7fffffff)
	return _state


func below(limit: int) -> int:
	return next() % maxi(limit, 1)


func choose(values: Array) -> Variant:
	return null if values.is_empty() else values[below(values.size())]


static func mix(seed_value: int, values: Array) -> int:
	var mixed: int = seed_value & 0x7fffffff
	for value: Variant in values:
		mixed = int((mixed * 16777619) ^ int(value)) & 0x7fffffff
	return 1 if mixed == 0 else mixed


static func text_hash(value: String) -> int:
	var out: int = 2166136261
	for byte: int in value.to_utf8_buffer():
		out = int((out ^ byte) * 16777619) & 0xffffffff
	return out
