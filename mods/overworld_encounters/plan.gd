extends RefCounted

## Pure population planning from a host-resolved visible-encounter context.
## The host owns which cells and tables are eligible; this file only bounds and
## samples them, so the probe can prove the same run seed means the same map.

const Rng := preload("rng.gd")
const GRASS_WEIGHTS: Array[int] = [30, 30, 20, 10, 5, 4, 1]
const SURF_WEIGHTS: Array[int] = [60, 30, 10]
## What a Pokemon has to total over its four stored DVs to be worth a glow, out
## of sixty. A shiny cannot reach it: three of its DVs are pinned at ten and its
## ATTACK caps at fifteen, so forty-five is the most a shiny totals.
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


## The largest number [method build] can have issued for [param maximum], so a
## caller minting more of them afterwards knows where its own numbering starts.
## An id is what a battle result is reported under and what the host dedupes a
## pulse by, so one is never reused inside a map.
static func first_free_number(maximum: int) -> int:
	return clampi(maximum, 0, 32) + 1


## ONE more wild, for a map that refills rather than being built once.
##
## The same rules the build uses, against the context in force NOW: the host
## re-resolves `tables` when the hour, a swarm or the Bug Contest moves what a
## roll would read, and `eligible` when a script switches wilds off, so a
## replacement is drawn from what the map offers at the moment it appears rather
## than from what it offered when the player walked on.
##
## [param taken] is the cells this caller's own population already holds, which
## the context cannot know: `occupied` is the MAP's objects. Empty when there is
## nowhere left to stand.
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


## One entry on one candidate cell. The order the generator is drawn from is part
## of the answer, so this is written once and both callers spend it the same way.
static func _make(
	candidate: Dictionary, context: Dictionary, random: RefCounted, number: int,
	id_prefix: StringName
) -> Dictionary:
	var method: StringName = StringName(candidate["method"])
	var table: Dictionary = (context.get("tables", {}) as Dictionary).get(method, {})
	var slots: Array = table.get("slots", [])
	var slot: Dictionary = _slot(slots, method, random)
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


## `CheckShininess`, which is the HOST's answer and not a rule this mod may hold
## a copy of: the same call `Gen2WorldEncounters` stamps each entry's `shiny`
## with, so what this file exempts and what the player is shown a sparkle for
## can never come apart. It read the four DVs itself until 0.3.1 and agreed by
## luck rather than by construction.
static func is_shiny(dvs: int) -> bool:
	return Gen2Stats.is_shiny(dvs)


## Whether this one wears the glow: high enough over the four stored DVs and not
## a shiny, which has its own mark. HP's DV is assembled from the low bits of
## these four and is not a fifth number to add.
static func is_excellent(dvs: int) -> bool:
	if is_shiny(dvs):
		return false
	var total: int = 0
	for shift: int in [12, 8, 4, 0]:
		total += (dvs >> shift) & 0xf
	return total >= EXCELLENT_TOTAL


## Where a wild may be PUT, which is every eligible cell with nobody in it. The
## host answers who is standing where in `occupied` and leaves the refusal here,
## since a population is the provider's to place: see `docs/MODS.md`.
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


## An entry carries its own DVs, so the host takes them as they are and asks no
## shiny-roll provider about them. Asking here is what keeps a charm, a combo or
## anything else a mod is worth working on a Pokemon standing on the map as well
## as on one a step rolled. The host's own rule: extra words past the first, and
## the first shiny one stands.
##
## A population is still reproducible from the run seed for a given set of
## registered providers. How many words a wild costs the generator is one of this
## mod's inputs now, the way the table and the sweep are.
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
