extends RefCounted

## The whole randomization, as one pure function of the cartridge and the seed.
##
## Nothing here touches the host, the world or a node: [method build] is handed
## an opened [GameData] and a settings Dictionary and answers the patches to
## apply, which is what lets `tools/randomizer_probe.gd` check that one seed
## twice is one run twice without a game running.
##
## The cartridge is read through an overlay of its own, so a baseline is the
## cartridge's own row whatever this mod has already patched. Rebuilding after a
## setting changes therefore starts where the first build did, rather than
## shuffling an already shuffled table.

## Untyped on purpose: annotated `GDScript` the parser knows only that it is a
## script, and every `Rng.new()` below comes back a Variant.
const Rng := preload("rng.gd")

## The six base stats, in a fixed written-down order. Never the Dictionary's own
## key order: it is the importer's, not ours, and a plan that depended on it
## would be a plan that depended on a host detail nobody promised.
const STAT_KEYS: Array[String] = [
	"hp", "attack", "defense", "speed", "sp_attack", "sp_defense",
]

## One past the last cartridge number of any kind, which is where mod content
## starts. Scanned rather than counted because [GameData] counts species and
## trainer classes and does not count moves.
const MAX_NUMBER: int = Gen2ContentOverlay.FIRST_MOD_NUMBER - 1

## What a starter is holding at level five. Every learnset entry this early, and
## the first entry of every species whatever its level, is drawn from moves that
## do damage, land reliably and are not a one-off: a randomizer that opens with
## four status moves and a wild PIDGEY is a randomizer nobody finishes.
const EARLY_LEVEL: int = 5
const EARLY_POWER_MIN: int = 1
const EARLY_POWER_MAX: int = 60
## Four fifths of the cartridge's own 255, which is what $FF means in the byte.
const EARLY_ACCURACY_MIN: int = 204

## How far up and down the base-stat-total order a trainer's Pokemon may be
## replaced from. A gym leader whose team came out of the top of the table is
## the other way a run stops being finishable.
const TRAINER_WINDOW: int = 12

## The patches one seed and one set of toggles produce, as kind to number to the
## fields [method Gen2ModHost.patch_content] takes. [param world] is one
## [method gather], which the caller holds so that rebuilding after a setting
## changed does not read the whole cartridge again.
static func build(world: Dictionary, settings: Dictionary) -> Dictionary:
	var seed_value: int = int(settings.get("seed", 0))
	var species: Dictionary = {}
	var moves: Dictionary = {}
	var trainers: Dictionary = {}
	# Evolutions first: they decide nothing else here, but reading them in one
	# place keeps the species fields assembled in one order.
	if bool(settings.get("evolutions", false)):
		_randomize_evolutions(world, seed_value, species)
	if bool(settings.get("stats", false)):
		_randomize_stats(world, seed_value, species)
	if bool(settings.get("types", false)):
		_randomize_types(world, seed_value, species)
	if bool(settings.get("learnsets", false)):
		_randomize_learnsets(world, seed_value, species)
	if bool(settings.get("moves", false)):
		_randomize_moves(world, seed_value, moves)
	if bool(settings.get("trainers", false)):
		_randomize_trainers(world, seed_value, trainers)
	return {
		Gen2ContentOverlay.KIND_SPECIES: species,
		Gen2ContentOverlay.KIND_MOVE: moves,
		Gen2ContentOverlay.KIND_TRAINER: trainers,
	}


## The cartridge's own values for every field this mod ever writes, which is
## what puts a row back when its setting is switched off. A patch is what the
## overlay holds, so a row is restored by patching it with what it was, not by
## dropping the patch.
static func original_fields(world: Dictionary, kind: StringName, number: int) -> Dictionary:
	var rows: Dictionary = world[kind]
	if not rows.has(number):
		return {}
	var row: Dictionary = rows[number]
	if kind == Gen2ContentOverlay.KIND_SPECIES:
		return {
			"stats": (row.get("stats", {}) as Dictionary).duplicate(true),
			"types": (row.get("types", []) as Array).duplicate(true),
			"learnset": (row.get("learnset", []) as Array).duplicate(true),
			"evolutions": (row.get("evolutions", []) as Array).duplicate(true),
		}
	if kind == Gen2ContentOverlay.KIND_MOVE:
		return {
			"power": int(row.get("power", 0)),
			"accuracy": int(row.get("accuracy", 255)),
			"type": int(row.get("type", 0)),
		}
	return {"trainers": (row.get("trainers", []) as Array).duplicate(true)}


## Everything the plan reads, gathered once: the rows, the totals, the type
## numbers this cartridge uses and which species evolve into which.
##
## [param data] is given an overlay of its own, which is the documented way to
## read a cache without a mod's own patches folded in. It is the caller's
## instance: this mod opens its own [GameData] rather than the one the game
## plays from.
static func gather(data: GameData) -> Dictionary:
	data.set_content_overlay(Gen2ContentOverlay.new())
	var species: Dictionary = {}
	var moves: Dictionary = {}
	var trainers: Dictionary = {}
	var species_numbers: Array[int] = []
	var move_numbers: Array[int] = []
	var trainer_numbers: Array[int] = []
	for number: int in range(1, MAX_NUMBER + 1):
		var row: Dictionary = data.species(number)
		if not row.is_empty():
			species[number] = row
			species_numbers.append(number)
		row = data.move(number)
		if not row.is_empty():
			moves[number] = row
			move_numbers.append(number)
		row = data.trainer(number)
		if not row.is_empty():
			trainers[number] = row
			trainer_numbers.append(number)

	var totals: Dictionary = {}
	var type_pool: Array[int] = []
	for number: int in species_numbers:
		totals[number] = _total(species[number])
		for slot: Variant in (species[number].get("types", []) as Array):
			var type_number: int = int(slot)
			if not type_pool.has(type_number):
				type_pool.append(type_number)
	type_pool.sort()

	var by_total: Array[int] = species_numbers.duplicate()
	by_total.sort_custom(func(a: int, b: int) -> bool:
		return a < b if int(totals[a]) == int(totals[b]) else int(totals[a]) < int(totals[b])
	)
	var rank: Dictionary = {}
	for index: int in by_total.size():
		rank[by_total[index]] = index

	return {
		Gen2ContentOverlay.KIND_SPECIES: species,
		Gen2ContentOverlay.KIND_MOVE: moves,
		Gen2ContentOverlay.KIND_TRAINER: trainers,
		"species_numbers": species_numbers,
		"move_numbers": move_numbers,
		"trainer_numbers": trainer_numbers,
		"totals": totals,
		"type_pool": type_pool,
		"by_total": by_total,
		"rank": rank,
		"families": _families(species, species_numbers),
	}


## The base stat total, which every sane default here is measured against.
static func _total(row: Dictionary) -> int:
	var stats: Dictionary = row.get("stats", {})
	var sum: int = 0
	for key: String in STAT_KEYS:
		sum += int(stats.get(key, 0))
	return sum


## Which species share an evolution line, as number to the line's own lowest
## number. Read from the CARTRIDGE's evolutions and not from a randomized set,
## so the stat shuffle means the same thing whether or not evolutions were
## randomized: each setting is its own.
static func _families(species: Dictionary, numbers: Array[int]) -> Dictionary:
	var neighbours: Dictionary = {}
	for number: int in numbers:
		neighbours[number] = [] as Array[int]
	for number: int in numbers:
		for entry: Dictionary in (species[number].get("evolutions", []) as Array):
			var target: int = int(entry.get("target", 0))
			if not neighbours.has(target) or target == number:
				continue
			(neighbours[number] as Array[int]).append(target)
			(neighbours[target] as Array[int]).append(number)

	var family: Dictionary = {}
	for number: int in numbers:
		if family.has(number):
			continue
		var queue: Array[int] = [number]
		var seen: Array[int] = [number]
		while not queue.is_empty():
			var current: int = queue.pop_back()
			for next_number: int in (neighbours[current] as Array[int]):
				if seen.has(next_number):
					continue
				seen.append(next_number)
				queue.append(next_number)
		seen.sort()
		for member: int in seen:
			family[member] = seen[0]
	return family


## The six stats permuted, the same permutation for every species in a line.
##
## A permutation keeps the total exactly, so nothing gets stronger or weaker;
## sharing it along the line keeps every stat CLIMBING the way the cartridge
## drew it, since both ends of an evolution move the same stat into the same
## slot. Rolling per species instead is what puts a first stage's Attack above
## its own final form's.
static func _randomize_stats(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var family: Dictionary = world["families"]
	var orders: Dictionary = {}
	for number: int in (world["species_numbers"] as Array[int]):
		var key: int = int(family.get(number, number))
		if not orders.has(key):
			var rng := Rng.new()
			rng.begin(seed_value, "stats", key)
			orders[key] = rng.shuffled(STAT_KEYS)
		var order: Array = orders[key]
		var stats: Dictionary = species[number].get("stats", {})
		var shuffled: Dictionary = {}
		for index: int in STAT_KEYS.size():
			shuffled[STAT_KEYS[index]] = int(stats.get(String(order[index]), 0))
		_field(out, number)["stats"] = shuffled


## One type assignment per line, so a Pokemon does not change type by evolving.
## The pool is the set of type numbers this cartridge's own species carry, which
## is how the unused slots between the physical and special runs stay out of it
## without a table of type numbers being written down here.
static func _randomize_types(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var pool: Array[int] = world["type_pool"]
	if pool.size() < 2:
		return
	var family: Dictionary = world["families"]
	var chosen: Dictionary = {}
	for number: int in (world["species_numbers"] as Array[int]):
		var key: int = int(family.get(number, number))
		if not chosen.has(key):
			var rng := Rng.new()
			rng.begin(seed_value, "types", key)
			var first: int = pool[rng.below(pool.size())]
			var second: int = first
			# Half of them dual-typed, which is about the cartridge's own share.
			if rng.below(2) == 1:
				second = pool[rng.below(pool.size())]
			# The cartridge writes a single type as the same number twice, and
			# so does this: nothing downstream reads a one-element list.
			chosen[key] = [first, second]
		_field(out, number)["types"] = (chosen[key] as Array).duplicate()


## Level-up moves replaced, keeping every level exactly. What is guarded is the
## opening: see [constant EARLY_LEVEL].
static func _randomize_learnsets(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var pools: Dictionary = _move_pools(world)
	var any: Array[int] = pools["any"]
	var early: Array[int] = pools["early"]
	if any.is_empty() or early.is_empty():
		return
	for number: int in (world["species_numbers"] as Array[int]):
		var rng := Rng.new()
		rng.begin(seed_value, "learnset", number)
		var learnset: Array = (species[number].get("learnset", []) as Array).duplicate(true)
		for index: int in learnset.size():
			var entry: Dictionary = learnset[index]
			var opening: bool = index == 0 or int(entry.get("level", 1)) <= EARLY_LEVEL
			var pool: Array[int] = early if opening else any
			entry["move"] = pool[rng.below(pool.size())]
		if not learnset.is_empty():
			_field(out, number)["learnset"] = learnset


## Move powers and accuracies PERMUTED among the moves that do damage, rather
## than drawn fresh. A permutation keeps the game's own spread: the same number
## of weak moves, the same number of unreliable ones, none of it invented. Types
## are drawn, since a type is a label rather than a budget.
##
## A status move is left entirely alone. Its type and its effect are entangled,
## so retyping THUNDERWAVE moves which Pokemon it cannot paralyse and giving it
## a power turns it into something else altogether.
static func _randomize_moves(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var moves: Dictionary = world[Gen2ContentOverlay.KIND_MOVE]
	var pool: Array[int] = world["type_pool"]
	var damaging: Array[int] = (_move_pools(world)["damaging"] as Array[int])
	if damaging.is_empty():
		return
	var powers: Array = []
	var accuracies: Array = []
	for number: int in damaging:
		powers.append(int(moves[number].get("power", 0)))
		accuracies.append(int(moves[number].get("accuracy", 255)))
	var power_rng := Rng.new()
	power_rng.begin(seed_value, "move_power", 0)
	powers = power_rng.shuffled(powers)
	var accuracy_rng := Rng.new()
	accuracy_rng.begin(seed_value, "move_accuracy", 0)
	accuracies = accuracy_rng.shuffled(accuracies)
	for index: int in damaging.size():
		var number: int = damaging[index]
		var fields: Dictionary = {"power": powers[index], "accuracy": accuracies[index]}
		if not pool.is_empty():
			var rng := Rng.new()
			rng.begin(seed_value, "move_type", number)
			fields["type"] = pool[rng.below(pool.size())]
		out[number] = fields


## Evolution targets replaced, method and parameter kept: a stone evolution is
## still that stone, at that level, for that happiness.
##
## One rule, and it does two jobs. A target is drawn from STRICTLY ABOVE the
## source in the base stat total order, so evolving is never a downgrade and a
## line still climbs. And because every edge climbs that order, no set of them
## can close into a loop, which is a proof rather than a check: a cycle would
## have to come back down. The one species at the top of the order has nothing
## above it and keeps the target the cartridge gave it.
static func _randomize_evolutions(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var by_total: Array[int] = world["by_total"]
	var rank: Dictionary = world["rank"]
	for number: int in (world["species_numbers"] as Array[int]):
		var evolutions: Array = (species[number].get("evolutions", []) as Array).duplicate(true)
		if evolutions.is_empty():
			continue
		var first: int = int(rank.get(number, 0)) + 1
		var span: int = by_total.size() - first
		if span <= 0:
			continue
		var rng := Rng.new()
		rng.begin(seed_value, "evolution", number)
		for entry: Dictionary in evolutions:
			entry["target"] = by_total[first + rng.below(span)]
		_field(out, number)["evolutions"] = evolutions


## Every trainer's Pokemon replaced with one of about its own strength, drawn
## from the band of the base stat total order around it: see
## [constant TRAINER_WINDOW]. Levels, held items and the moves a trainer's
## Pokemon carries in its own record are the cartridge's and stay.
##
## The whole `trainers` array is rewritten because an Array field replaces
## rather than merging, so it is built out of the cartridge's own rows with the
## species substituted in place, and every key those rows carry rides along.
static func _randomize_trainers(world: Dictionary, seed_value: int, out: Dictionary) -> void:
	var classes: Dictionary = world[Gen2ContentOverlay.KIND_TRAINER]
	var by_total: Array[int] = world["by_total"]
	var rank: Dictionary = world["rank"]
	if by_total.is_empty():
		return
	for number: int in (world["trainer_numbers"] as Array[int]):
		var roster: Array = (classes[number].get("trainers", []) as Array).duplicate(true)
		if roster.is_empty():
			continue
		var rng := Rng.new()
		rng.begin(seed_value, "trainer", number)
		for trainer: Dictionary in roster:
			for mon: Dictionary in (trainer.get("party", []) as Array):
				var original: int = int(mon.get("species", 0))
				var centre: int = int(rank.get(original, by_total.size() / 2))
				var low: int = maxi(centre - TRAINER_WINDOW, 0)
				var high: int = mini(centre + TRAINER_WINDOW, by_total.size() - 1)
				mon["species"] = by_total[low + rng.below(high - low + 1)]
		out[number] = {"trainers": roster}


## The move numbers a learnset or a rebalance draws from, read off the
## CARTRIDGE's own move rows. Read before anything is patched, so what a
## learnset counts as an opening move does not depend on whether move powers
## were randomized too.
static func _move_pools(world: Dictionary) -> Dictionary:
	var moves: Dictionary = world[Gen2ContentOverlay.KIND_MOVE]
	var any: Array[int] = []
	var damaging: Array[int] = []
	var early: Array[int] = []
	for number: int in (world["move_numbers"] as Array[int]):
		var row: Dictionary = moves[number]
		var power: int = int(row.get("power", 0))
		var accuracy: int = int(row.get("accuracy", 255))
		any.append(number)
		if power <= 0:
			continue
		damaging.append(number)
		if power >= EARLY_POWER_MIN and power <= EARLY_POWER_MAX \
				and accuracy >= EARLY_ACCURACY_MIN:
			early.append(number)
	return {"any": any, "damaging": damaging, "early": early}


## The fields being assembled for one number, created on first use so a species
## touched by three settings is patched once.
static func _field(out: Dictionary, number: int) -> Dictionary:
	if not out.has(number):
		out[number] = {}
	return out[number]
