extends RefCounted

const Rng := preload("rng.gd")
const EXCELLENT_TOTAL: int = 50


static func build(
	context: Dictionary, run_seed: int, maximum: int,
	id_prefix: StringName = &"overworld_encounters"
) -> Array:
	var map: Vector2i = Vector2i(context.get("map", Vector2i.ZERO))
	var generation: int = int(context.get("generation", 0))
	var random := Rng.new(Rng.mix(run_seed, [map.x, map.y, generation]))
	var candidates: Array = _candidates(context)
	_shuffle(candidates, random)
	var count: int = mini(clampi(maximum, 0, 32), candidates.size())
	var out: Array = []
	for index: int in count:
		var entry: Dictionary = _make(
			candidates[index], context, random, index + 1, id_prefix
		)
		if not entry.is_empty():
			out.append(entry)
	return out


static func first_free_number(maximum: int) -> int:
	return clampi(maximum, 0, 32) + 1


static func mint(
	context: Dictionary, random: RefCounted, taken: Array[Vector2i], number: int,
	id_prefix: StringName = &"overworld_encounters"
) -> Dictionary:
	var candidates: Array = _candidates(context)
	var free: Array = []
	for candidate: Variant in candidates:
		if not taken.has(Vector2i((candidate as Dictionary)["cell"])):
			free.append(candidate)
	if free.is_empty():
		return {}
	return _make(free[random.below(free.size())], context, random, number, id_prefix)


static func _make(
	candidate: Dictionary, context: Dictionary, random: RefCounted, number: int,
	id_prefix: StringName
) -> Dictionary:
	var method: StringName = StringName(candidate["method"])
	var table: Dictionary = (context.get("tables", {}) as Dictionary).get(method, {})
	var slot: Dictionary = _slot(table.get("slots", []), random)
	if slot.is_empty():
		return {}
	var minimum: int = int(slot.get("min_level", 1))
	var maximum_level: int = maxi(minimum, int(slot.get("max_level", minimum)))
	var facing: int = random.below(4)
	var species: int = int(slot.get("species", 0))
	var level: int = minimum + random.below(maximum_level - minimum + 1)
	return {
		"id": StringName("%s:%d" % [id_prefix, number]),
		"method": method,
		"cell": Vector2i(candidate["cell"]),
		"facing": facing,
		"species": species,
		"level": level,
		"dvs": _dvs(random, context, species, level, method),
	}


static func is_shiny(dvs: int) -> bool:
	return Gen2Stats.is_shiny(dvs)


static func is_excellent(dvs: int) -> bool:
	if is_shiny(dvs):
		return false
	var total: int = 0
	for shift: int in [12, 8, 4, 0]:
		total += (dvs >> shift) & 0xf
	return total >= EXCELLENT_TOTAL


static func _candidates(context: Dictionary) -> Array:
	var out: Array = []
	var eligible: Dictionary = context.get("eligible", {})
	var player: Dictionary = context.get("player", {})
	var player_cell: Vector2i = Vector2i(player.get("cell", Vector2i(-1, -1)))
	var occupied: PackedVector2Array = context.get("occupied", PackedVector2Array())
	var methods: Array = eligible.keys()
	methods.sort()
	for method: Variant in methods:
		for cell: Variant in eligible[method]:
			if Vector2i(cell) == player_cell or occupied.has(Vector2(cell)):
				continue
			out.append({"method": StringName(method), "cell": Vector2i(cell)})
	return out


static func _shuffle(values: Array, random: RefCounted) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = random.below(index + 1)
		var held: Variant = values[index]
		values[index] = values[other]
		values[other] = held


## The cartridge's own slot roll: each slot in its share of the table's `chance`.
static func _slot(slots: Array, random: RefCounted) -> Dictionary:
	var total: int = 0
	for slot: Dictionary in slots:
		total += int(slot["chance"])
	if total <= 0:
		return {}
	var roll: int = random.below(total)
	for slot: Dictionary in slots:
		roll -= int(slot["chance"])
		if roll < 0:
			return slot.duplicate(true)
	return {}


static func _dvs(
	random: RefCounted, context: Dictionary, species: int, level: int, method: StringName
) -> int:
	var map: Vector2i = Vector2i(context.get("map", Vector2i(-1, -1)))
	var rolls: int = Gen2ModHost.shiny_roll_count({
		"species": species,
		"level": level,
		"method": method,
		"map_group": map.x,
		"map_number": map.y,
	})
	var word: int = _roll_dvs(random)
	for _extra: int in maxi(0, rolls - 1):
		if is_shiny(word):
			break
		word = _roll_dvs(random)
	return word


static func _roll_dvs(random: RefCounted) -> int:
	return (random.below(16) << 12) | (random.below(16) << 8) \
		| (random.below(16) << 4) | random.below(16)
