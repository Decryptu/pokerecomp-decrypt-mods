extends RefCounted

## Pure population planning from a host-resolved visible-encounter context.
## The host owns which cells and tables are eligible; this file only bounds and
## samples them, so the probe can prove the same run seed means the same map.

const Rng := preload("rng.gd")
const GRASS_WEIGHTS: Array[int] = [30, 30, 20, 10, 5, 4, 1]
const SURF_WEIGHTS: Array[int] = [60, 30, 10]
const SHINY_ATTACK: Array[int] = [2, 3, 6, 7, 10, 11, 14, 15]


static func build(context: Dictionary, run_seed: int, maximum: int) -> Array:
	var map: Vector2i = Vector2i(context.get("map", Vector2i.ZERO))
	var generation: int = int(context.get("generation", 0))
	var random := Rng.new(Rng.mix(run_seed, [map.x, map.y, generation]))
	var candidates: Array = _candidates(context)
	_shuffle(candidates, random)
	var count: int = mini(clampi(maximum, 0, 32), candidates.size())
	var out: Array = []
	for index: int in count:
		var candidate: Dictionary = candidates[index]
		var method: StringName = StringName(candidate["method"])
		var slots: Array = ((context.get("tables", {}) as Dictionary).get(method, []) as Array)
		var slot: Dictionary = _slot(slots, method, random)
		if slot.is_empty():
			continue
		var dvs: int = _dvs(random)
		out.append({
			"id": index + 1,
			"method": method,
			"cell": Vector2i(candidate["cell"]),
			"facing": random.below(4),
			"species": int(slot.get("species", 0)),
			"level": int(slot.get("level", 1)),
			"dvs": dvs,
		})
	return out


static func is_shiny(dvs: int) -> bool:
	var attack: int = (dvs >> 12) & 0xf
	var defense: int = (dvs >> 8) & 0xf
	var speed: int = (dvs >> 4) & 0xf
	var special: int = dvs & 0xf
	return defense == 10 and speed == 10 and special == 10 and attack in SHINY_ATTACK


static func _candidates(context: Dictionary) -> Array:
	var out: Array = []
	var eligible: Dictionary = context.get("eligible", {})
	var methods: Array = eligible.keys()
	methods.sort()
	for method: Variant in methods:
		for cell: Variant in (eligible[method] as Array):
			out.append({"method": StringName(method), "cell": Vector2i(cell)})
	return out


static func _shuffle(values: Array, random: RefCounted) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = random.below(index + 1)
		var held: Variant = values[index]
		values[index] = values[other]
		values[other] = held


static func _slot(slots: Array, method: StringName, random: RefCounted) -> Dictionary:
	if slots.is_empty():
		return {}
	var weights: Array[int] = SURF_WEIGHTS if method == &"surf" else GRASS_WEIGHTS
	var total: int = 0
	for index: int in mini(slots.size(), weights.size()):
		total += weights[index]
	var roll: int = random.below(total)
	for index: int in mini(slots.size(), weights.size()):
		if roll < weights[index]:
			return (slots[index] as Dictionary).duplicate(true)
		roll -= weights[index]
	return (slots[0] as Dictionary).duplicate(true)


static func _dvs(random: RefCounted) -> int:
	return (random.below(16) << 12) | (random.below(16) << 8) \
		| (random.below(16) << 4) | random.below(16)
