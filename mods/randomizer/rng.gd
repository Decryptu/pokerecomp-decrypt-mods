extends RefCounted

## The only source of chance in this mod, and the reason a seed means the same
## thing on two machines.

const MASK: int = 0xFFFFFFFF
const MULTIPLIER: int = 1664525
const INCREMENT: int = 1013904223
const SCRAMBLE: int = 0x2545F491
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

var _state: int = 0


static func text_hash(text: String) -> int:
	var value: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		value = ((value ^ byte) * FNV_PRIME) & MASK
	return value


func begin(seed_value: int, domain: String, number: int) -> void:
	_state = (seed_value & MASK) ^ text_hash(domain) ^ ((number * FNV_PRIME) & MASK)
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


func pick(values: Array) -> Variant:
	return null if values.is_empty() else values[below(values.size())]


func shuffled(values: Array) -> Array:
	var out: Array = values.duplicate()
	for index: int in range(out.size() - 1, 0, -1):
		var other: int = below(index + 1)
		var held: Variant = out[index]
		out[index] = out[other]
		out[other] = held
	return out
