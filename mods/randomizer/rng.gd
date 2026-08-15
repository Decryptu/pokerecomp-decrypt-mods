extends RefCounted

## The only source of chance in this mod, and the reason a seed means the same
## thing on two machines.
##
## Godot's own `RandomNumberGenerator` is not used, and neither is `hash()`.
## Both are the engine's to change between versions, and a shared seed that
## stops agreeing after an update is the one bug a randomizer cannot survive.
## What is here is written down: a 32-bit linear congruential step with an
## xorshift-multiply scramble on the way out, in arithmetic that never leaves
## the range a 64-bit integer holds exactly.
##
## A stream is opened per DOMAIN and per NUMBER rather than drawn from one long
## sequence, so nothing depends on the order the caller happens to walk in and
## turning one setting off does not move what another one produced. Species 43's
## stats come from the same stream whether or not moves were randomized.

const MASK: int = 0xFFFFFFFF
const MULTIPLIER: int = 1664525
const INCREMENT: int = 1013904223
## Small enough that a 32-bit value times it stays inside a signed 64-bit
## integer: the wider constants the usual mixers reach for overflow here, and
## GDScript wraps rather than saying so.
const SCRAMBLE: int = 0x2545F491
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

var _state: int = 0


## FNV-1a over the UTF-8 bytes. What turns a domain name into a number without
## asking the engine what a String hashes to.
static func text_hash(text: String) -> int:
	var value: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		value = ((value ^ byte) * FNV_PRIME) & MASK
	return value


## Opens the stream for one thing: [param domain] names what is being decided,
## [param number] which row it is being decided for.
func begin(seed_value: int, domain: String, number: int) -> void:
	_state = (seed_value & MASK) ^ text_hash(domain) ^ ((number * FNV_PRIME) & MASK)
	# Two steps of warm-up, because a low seed and a low number differ in the
	# bottom bits alone and an LCG carries those upward slowly.
	next()
	next()


func next() -> int:
	_state = (_state * MULTIPLIER + INCREMENT) & MASK
	var value: int = _state
	value ^= value >> 15
	value = (value * SCRAMBLE) & MASK
	value ^= value >> 13
	return value


## A number below [param limit]. Multiply-shift rather than a modulo: the bias
## is one part in 2^32 and it does not favour the low values the way a modulo of
## a limit that is not a power of two does.
func below(limit: int) -> int:
	if limit <= 1:
		return 0
	return (next() * limit) >> 32


func pick(values: Array) -> Variant:
	return null if values.is_empty() else values[below(values.size())]


## Fisher-Yates, downward, on a copy. Used where a shuffle has to keep the
## multiset it started with: the six base stats of one species, the powers of
## every damaging move.
func shuffled(values: Array) -> Array:
	var out: Array = values.duplicate()
	for index: int in range(out.size() - 1, 0, -1):
		var other: int = below(index + 1)
		var held: Variant = out[index]
		out[index] = out[other]
		out[other] = held
	return out
