extends RefCounted

## A fixed integer generator. Spawn plans are save-run facts, so the algorithm
## is written here rather than inherited from a Godot release.
##
## The step is a 32-bit LCG with an xorshift-multiply scramble on the way out,
## and `below` is a multiply-shift rather than a modulo. Both matter: a raw LCG's
## low bits carry almost no entropy, so `state % limit` made `plan.gd:_shuffle`
## favour the opening of the candidate list and put a map's whole population in
## the first patch of grass the collision walk reached. Over 200 seeds on map 3,2
## the first eighth drew 715 picks and the last 282; it is flat now.
##
## The constants and the shape are the randomizer mod's: arithmetic that stays
## inside a 64-bit integer exactly, and a seed that means the same thing on two
## machines and after an engine update.

const MASK: int = 0xFFFFFFFF
const MULTIPLIER: int = 1664525
const INCREMENT: int = 1013904223
const SCRAMBLE: int = 0x2545F491
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

var _state: int = 0


func _init(seed_value: int = 1) -> void:
	_state = seed_value & MASK
	## Two steps of warm-up: an LCG carries a low bit upward slowly, so seeds
	## differing only in the bottom bits are still close after one.
	next()
	next()


func next() -> int:
	_state = (_state * MULTIPLIER + INCREMENT) & MASK
	var value: int = _state
	value ^= value >> 15
	value = (value * SCRAMBLE) & MASK
	value ^= value >> 13
	return value


## A number below [param limit]. The bias is one part in 2^32, and it does not
## favour low values the way a modulo does.
func below(limit: int) -> int:
	if limit <= 1:
		return 0
	return (next() * limit) >> 32


func choose(values: Array) -> Variant:
	return null if values.is_empty() else values[below(values.size())]


## FNV-1a, so a map and a generation reach the seed without asking the engine
## what a value hashes to.
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
