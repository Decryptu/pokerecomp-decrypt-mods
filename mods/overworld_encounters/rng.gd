extends RefCounted

## A fixed integer generator.

const MASK: int = 0xFFFFFFFF
const MULTIPLIER: int = 1664525
const INCREMENT: int = 1013904223
const SCRAMBLE: int = 0x2545F491
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

var _state: int = 0


func _init(seed_value: int = 1) -> void:
	_state = seed_value & MASK
	next()
	next()


func next() -> int:
	_state = (_state * MULTIPLIER + INCREMENT) & MASK
	var value: int = _state
	value ^= value >> 15
	value = (value * SCRAMBLE) & MASK
	value ^= value >> 13
	return value


func below(limit: int) -> int:
	if limit <= 1:
		return 0
	return (next() * limit) >> 32


func choose(values: Array) -> Variant:
	return null if values.is_empty() else values[below(values.size())]


static func mix(seed_value: int, values: Array) -> int:
	var mixed: int = seed_value & MASK
	for value: Variant in values:
		mixed = ((mixed ^ int(value)) * FNV_PRIME) & MASK
	return 1 if mixed == 0 else mixed


static func text_hash(value: String) -> int:
	var out: int = FNV_OFFSET
	for byte: int in value.to_utf8_buffer():
		out = ((out ^ byte) * FNV_PRIME) & MASK
	return out
