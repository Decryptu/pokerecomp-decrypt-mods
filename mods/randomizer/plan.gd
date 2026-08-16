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

## The wild tables, in the order [method Gen2ContentOverlay.encounter_number]
## numbers them. Each is patched per map.
const ENCOUNTER_METHODS: Array[StringName] = [
	&"grass", &"surf", &"swarm_grass", &"swarm_water",
]

## How many fishing groups are looked for. The cartridge has a dozen and the
## reader answers empty past the last, so this is a bound rather than a count.
const FISHING_GROUPS: int = 64

const KIND_TREEMON: StringName = &"treemon"
const KIND_BUG_CONTEST: StringName = &"bug_contest"
const KIND_ROAMING: StringName = &"roaming"
const KIND_FISHING_TIME: StringName = &"fishing_time"
const KIND_CHECK: StringName = &"check"
const SPECIAL_KINDS: Array[StringName] = [
	Gen2WorldCatalog.KIND_GIFT,
	Gen2WorldCatalog.KIND_STATIC,
	Gen2WorldCatalog.KIND_PRIZE,
]
const PLACEMENT_ATTEMPTS: int = 1024

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

## The patches one seed and one set of toggles produce, as kind to a list of
## `{ number, fields }` in ascending number order, an encounter carrying the
## method and the map its own helper takes as well. A list rather than a
## Dictionary because the ORDER is part of the answer: two machines have to
## apply the same plan, and Dictionary keys come back in whatever order they
## went in.
##
## [param world] is one [method gather], which the caller holds so that
## rebuilding after a setting changed does not read the whole cartridge again.
static func build(
	world: Dictionary, settings: Dictionary, validator: Callable = Callable()
) -> Dictionary:
	var seed_value: int = int(settings.get("seed", 0))
	var species: Dictionary = {}
	var moves: Dictionary = {}
	var trainers: Array = []
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
	var encounters: Array = []
	var fishing: Array = []
	var treemons: Array = []
	var contest: Array = []
	var roaming: Array = []
	var fishing_time: Array = []
	var checks: Array = []
	if bool(settings.get("encounters", false)):
		_randomize_encounters(world, seed_value, encounters)
		_randomize_fishing(world, seed_value, fishing)
		_randomize_indexed(world, KIND_TREEMON, seed_value, "treemon", treemons)
		_randomize_indexed(world, KIND_BUG_CONTEST, seed_value, "contest", contest)
		_randomize_indexed(world, KIND_ROAMING, seed_value, "roaming", roaming)
		_randomize_indexed(world, KIND_FISHING_TIME, seed_value, "fishing_time", fishing_time)
	if bool(settings.get("specials", false)):
		_randomize_checks(world, SPECIAL_KINDS, seed_value, checks)
	if bool(settings.get("starters", false)):
		_randomize_starters(world, seed_value, checks)
	if bool(settings.get("trades", false)):
		_randomize_trades(world, seed_value, checks)
	_randomize_placement(world, settings, seed_value, validator, checks)
	return {
		Gen2ContentOverlay.KIND_SPECIES: _listed(species),
		Gen2ContentOverlay.KIND_MOVE: _listed(moves),
		Gen2ContentOverlay.KIND_TRAINER: trainers,
		Gen2ContentOverlay.KIND_ENCOUNTER: encounters,
		Gen2ContentOverlay.KIND_FISHING: fishing,
		KIND_TREEMON: treemons,
		KIND_BUG_CONTEST: contest,
		KIND_ROAMING: roaming,
		KIND_FISHING_TIME: fishing_time,
		KIND_CHECK: checks,
	}


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
	var species_numbers: Array[int] = _rows(data.species, data.species_count(), species)
	var move_numbers: Array[int] = _rows(data.move, data.move_count(), moves)
	var trainer_numbers: Array[int] = _rows(data.trainer, data.trainer_count(), trainers)

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
		Gen2ContentOverlay.KIND_ENCOUNTER: _encounters(data),
		Gen2ContentOverlay.KIND_FISHING: _fishing(data),
		KIND_TREEMON: _treemons(data),
		KIND_BUG_CONTEST: _indexed(data.bug_contest_mons()),
		KIND_ROAMING: _indexed(data.world_roaming_mons()),
		KIND_FISHING_TIME: _indexed(data.world_fishing_time_groups()),
		KIND_CHECK: _checks(data.catalog()),
	}


## The base stat total, which every sane default here is measured against.
static func _total(row: Dictionary) -> int:
	var stats: Dictionary = row.get("stats", {})
	var sum: int = 0
	for key: String in STAT_KEYS:
		sum += int(stats.get(key, 0))
	return sum


## One kind's rows, numbered from one the way the cartridge numbers them, kept
## by number and listed in the order they are walked in.
static func _rows(reader: Callable, count: int, into: Dictionary) -> Array[int]:
	var numbers: Array[int] = []
	for number: int in range(1, count + 1):
		var row: Dictionary = reader.call(number)
		if row.is_empty():
			continue
		into[number] = row
		numbers.append(number)
	return numbers


## Every map's wild table, keyed by the coordinate the host packs a method, a
## group and a map number into, with the three kept beside the row because
## [method Gen2ModHost.patch_encounter] takes them apart again.
##
## Walked over the maps the cartridge carries rather than over the tables' own
## keys: a map is the thing a patch addresses, and `world_maps()` is the list of
## them.
static func _encounters(data: GameData) -> Dictionary:
	var out: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		for method: StringName in ENCOUNTER_METHODS:
			var row: Dictionary = data.world_encounter(method, map.group, map.number)
			if row.is_empty() or (row.get("slots", []) as Array).is_empty():
				continue
			var at: int = Gen2ContentOverlay.encounter_number(method, map.group, map.number)
			if at < 0 or out.has(at):
				continue
			row = row.duplicate(true)
			row["method"] = method
			row["group"] = map.group
			row["number"] = map.number
			out[at] = row
	return out


## Every fishing group, by the number a map header names it with.
static func _fishing(data: GameData) -> Dictionary:
	var out: Dictionary = {}
	for group: int in range(1, FISHING_GROUPS + 1):
		var row: Dictionary = data.world_fishing_group(group)
		if not row.is_empty():
			out[group] = row
	return out


static func _treemons(data: GameData) -> Dictionary:
	var out: Dictionary = {}
	for index: int in data.treemon_set_count():
		var row: Dictionary = data.treemon_set(index)
		if not row.is_empty():
			out[index] = row
	return out


static func _indexed(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for index: int in rows.size():
		if rows[index] is Dictionary:
			out[index] = (rows[index] as Dictionary).duplicate(true)
	return out


static func _checks(catalog: Gen2WorldCatalog) -> Dictionary:
	var out: Dictionary = {}
	for kind: StringName in Gen2WorldCatalog.KINDS:
		for row: Dictionary in catalog.rows(kind):
			out[int(row["id"])] = row.duplicate(true)
	return out


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
		var used: Array[int] = []
		for index: int in learnset.size():
			var entry: Dictionary = learnset[index]
			var opening: bool = index == 0 or int(entry.get("level", 1)) <= EARLY_LEVEL
			var pool: Array[int] = early if opening else any
			var available: Array[int] = []
			for move: int in pool:
				if not used.has(move):
					available.append(move)
			if available.is_empty():
				available = pool
			var chosen: int = available[rng.below(available.size())]
			entry["move"] = chosen
			used.append(chosen)
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
static func _randomize_trainers(world: Dictionary, seed_value: int, out: Array) -> void:
	var classes: Dictionary = world[Gen2ContentOverlay.KIND_TRAINER]
	if (world["by_total"] as Array).is_empty():
		return
	for number: int in (world["trainer_numbers"] as Array[int]):
		var roster: Array = (classes[number].get("trainers", []) as Array).duplicate(true)
		if roster.is_empty():
			continue
		var rng := Rng.new()
		rng.begin(seed_value, "trainer", number)
		for trainer: Dictionary in roster:
			_substitute(trainer.get("party", []), world, rng)
		out.append({"number": number, "fields": {"trainers": roster}})


## Wild encounters: every slot of every map's table replaced, keeping the level
## the cartridge put there and the rates it appears at. A route stays as easy or
## as dangerous as it was, and what walks out of the grass is different.
##
## The tables are read-only through `GameData` and patched through the host's
## own `patch_encounter`, so the coordinate is carried rather than recomputed.
static func _randomize_encounters(world: Dictionary, seed_value: int, out: Array) -> void:
	var tables: Dictionary = world[Gen2ContentOverlay.KIND_ENCOUNTER]
	if (world["by_total"] as Array).is_empty():
		return
	for at: int in _sorted(tables):
		var row: Dictionary = tables[at]
		var slots: Array = (row.get("slots", []) as Array).duplicate(true)
		var rng := Rng.new()
		rng.begin(seed_value, "encounter", at)
		_substitute(slots, world, rng)
		out.append({
			"at": at, "method": StringName(row["method"]), "group": int(row["group"]),
			"number": int(row["number"]), "fields": {"slots": slots},
		})


## The same for the three rods of every fishing group. An entry that names no
## species defers to the day and night table; that table is randomized through
## its own typed host seam below.
static func _randomize_fishing(world: Dictionary, seed_value: int, out: Array) -> void:
	var groups: Dictionary = world[Gen2ContentOverlay.KIND_FISHING]
	if (world["by_total"] as Array).is_empty():
		return
	for group: int in _sorted(groups):
		var rods: Array = ((groups[group] as Dictionary).get("rods", []) as Array).duplicate(true)
		var rng := Rng.new()
		rng.begin(seed_value, "fishing", group)
		_substitute(rods, world, rng)
		out.append({"number": group, "fields": {"rods": rods}})


## The four indexed wild sources outside map and rod tables. Only species move;
## encounter weights, level bounds, roaming position and rod thresholds remain
## the cartridge's.
static func _randomize_indexed(
	world: Dictionary, kind: StringName, seed_value: int, stream: String, out: Array
) -> void:
	var rows: Dictionary = world[kind]
	for index: int in _sorted(rows):
		var row: Dictionary = (rows[index] as Dictionary).duplicate(true)
		var rng := Rng.new()
		rng.begin(seed_value, stream, index)
		_substitute(row, world, rng)
		var fields: Dictionary = {}
		match kind:
			KIND_TREEMON:
				fields = {
					"common": row.get("common", []),
					"rare": row.get("rare", []),
				}
			KIND_FISHING_TIME:
				fields = {"day": row.get("day", {}), "night": row.get("night", {})}
			_:
				fields = {"species": int(row.get("species", 0))}
		out.append({"number": index, "fields": fields})


## Pokemon handed over or fought at decoded sites. Levels, held items and Game
## Corner prices stay attached to their sites; only the species changes.
static func _randomize_checks(
	world: Dictionary, kinds: Array[StringName], seed_value: int, out: Array
) -> void:
	var rows: Dictionary = world[KIND_CHECK]
	for id: int in _sorted(rows):
		var row: Dictionary = rows[id]
		var kind: StringName = StringName(row.get("kind", &""))
		if not kinds.has(kind):
			continue
		var rng := Rng.new()
		rng.begin(seed_value, "check_%s" % kind, id)
		out.append({
			"number": id,
			"fields": {"species": _near(world, int(row.get("species", 0)), rng)},
		})


static func _randomize_trades(world: Dictionary, seed_value: int, out: Array) -> void:
	var rows: Dictionary = world[KIND_CHECK]
	for id: int in _sorted(rows):
		var row: Dictionary = rows[id]
		if StringName(row.get("kind", &"")) != Gen2WorldCatalog.KIND_TRADE:
			continue
		var offered := Rng.new()
		offered.begin(seed_value, "trade_offered", id)
		var requested := Rng.new()
		requested.begin(seed_value, "trade_requested", id)
		out.append({
			"number": id,
			"fields": {
				"species": _near(world, int(row.get("species", 0)), offered),
				"requested_species": _near(
					world, int(row.get("requested_species", 0)), requested
				),
			},
		})


static func _randomize_starters(world: Dictionary, seed_value: int, out: Array) -> void:
	var rows: Dictionary = world[KIND_CHECK]
	var used: Array[int] = []
	for id: int in _check_ids(rows, Gen2WorldCatalog.KIND_STARTER):
		var row: Dictionary = rows[id]
		var rng := Rng.new()
		rng.begin(seed_value, "starter", id)
		var species: int = _near(world, int(row.get("species", 0)), rng, used)
		used.append(species)
		out.append({"number": id, "fields": {"species": species}})


## Item rewards and badges are placements rather than independent substitutions:
## their whole pool is permuted, then the host proves the proposed check map has
## no self-lock it can see. A failed attempt installs nothing and advances only
## this stream. Shop shelves are economic rather than progression rewards; their
## prices stay in place while one bijection replaces item ids cartridge-wide.
static func _randomize_placement(
	world: Dictionary, settings: Dictionary, seed_value: int,
	validator: Callable, out: Array
) -> void:
	var items: bool = bool(settings.get("items", false))
	var badges: bool = bool(settings.get("badges", false))
	var shops: bool = bool(settings.get("shops", false))
	if not items and not badges and not shops:
		return
	# Critical placement is never accepted without the host's cartridge proof.
	if (items or badges) and not validator.is_valid():
		return
	if items or badges:
		validator.call({}) # Warm the host's catalog and map graph once.
	for attempt: int in PLACEMENT_ATTEMPTS:
		var candidate: Dictionary = _placement_candidate(
			world, seed_value, attempt, items, badges, shops
		)
		if shops and not _shop_shelves_are_unique(world[KIND_CHECK], candidate):
			continue
		if items or badges:
			var result: Variant = validator.call(candidate)
			if not result is Dictionary or not bool((result as Dictionary).get("ok", false)):
				continue
		for id: int in _sorted(candidate):
			out.append({"number": id, "fields": candidate[id]})
		return


static func _placement_candidate(
	world: Dictionary, seed_value: int, attempt: int,
	items: bool, badges: bool, shops: bool
) -> Dictionary:
	var rows: Dictionary = world[KIND_CHECK]
	var out: Dictionary = {}
	if items:
		var sites: Array[int] = _check_ids(rows, Gen2WorldCatalog.KIND_ITEM)
		var rewards: Array = []
		for id: int in sites:
			var row: Dictionary = rows[id]
			rewards.append({
				"item": int(row.get("item", 0)),
				"quantity": int(row.get("quantity", 1)),
			})
		var rng := Rng.new()
		rng.begin(seed_value, "item_placement", attempt)
		rewards = rng.shuffled(rewards)
		for index: int in sites.size():
			out[sites[index]] = (rewards[index] as Dictionary).duplicate(true)
	if badges:
		var sites: Array[int] = _check_ids(rows, Gen2WorldCatalog.KIND_BADGE)
		var groups: Dictionary = {}
		for id: int in sites:
			var badge: int = int((rows[id] as Dictionary).get("badge", 0))
			if not groups.has(badge):
				groups[badge] = [] as Array[int]
			(groups[badge] as Array[int]).append(id)
		var originals: Array[int] = _sorted(groups)
		var rng := Rng.new()
		rng.begin(seed_value, "badge_placement", attempt)
		var rewards: Array = rng.shuffled(originals)
		for index: int in originals.size():
			for id: int in (groups[originals[index]] as Array[int]):
				out[id] = {"badge": int(rewards[index])}
	if shops:
		var sites: Array[int] = _check_ids(rows, Gen2WorldCatalog.KIND_SHOP)
		var item_pool: Array[int] = []
		for id: int in sites:
			var shelf: Array = (rows[id] as Dictionary).get("items", [])
			for entry: Dictionary in shelf:
				var item: int = int(entry.get("item", 0))
				if not item_pool.has(item):
					item_pool.append(item)
		item_pool.sort()
		var rng := Rng.new()
		rng.begin(seed_value, "shop_placement", attempt)
		var replacements: Array = rng.shuffled(item_pool)
		var mapping: Dictionary = {}
		for index: int in item_pool.size():
			mapping[item_pool[index]] = int(replacements[index])
		for id: int in sites:
			var shelf: Array = (rows[id] as Dictionary).get("items", []).duplicate(true)
			for entry: Dictionary in shelf:
				entry["item"] = int(mapping.get(int(entry.get("item", 0)), entry.get("item", 0)))
			out[id] = {"items": shelf}
	return out


static func _check_ids(rows: Dictionary, kind: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in _sorted(rows):
		if StringName((rows[id] as Dictionary).get("kind", &"")) == kind:
			out.append(id)
	return out


static func _shop_shelves_are_unique(rows: Dictionary, patches: Dictionary) -> bool:
	for id: int in _check_ids(rows, Gen2WorldCatalog.KIND_SHOP):
		var used: Array[int] = []
		for entry: Dictionary in (patches.get(id, {}) as Dictionary).get("items", []):
			var item: int = int(entry.get("item", 0))
			if used.has(item):
				return false
			used.append(item)
	return true


## Replaces the species of every entry inside [param value], however deeply it
## is nested and whatever else the entry carries.
##
## One walk covers all three shapes, which is why it is written this way rather
## than three times: a grass table is a list per time of day, a water table is
## one flat list, a rod is a list of thresholds, and a trainer's party is a list
## of Pokemon. What they have in common is the only thing being changed.
static func _substitute(value: Variant, world: Dictionary, rng: RefCounted) -> void:
	if value is Array:
		for entry: Variant in value as Array:
			_substitute(entry, world, rng)
		return
	if not value is Dictionary:
		return
	var entry: Dictionary = value
	if entry.has("species"):
		entry["species"] = _near(world, int(entry["species"]), rng)
		return
	for child: Variant in entry.values():
		_substitute(child, world, rng)


## A species of about the strength of [param original]: the band of the base
## stat total order around it, which is what keeps an early route early and a
## gym leader beatable. See [constant TRAINER_WINDOW].
static func _near(
	world: Dictionary, original: int, rng: RefCounted, excluded: Array[int] = []
) -> int:
	var by_total: Array[int] = world["by_total"]
	var rank: Dictionary = world["rank"]
	var centre: int = int(rank.get(original, by_total.size() / 2))
	var low: int = maxi(centre - TRAINER_WINDOW, 0)
	var high: int = mini(centre + TRAINER_WINDOW, by_total.size() - 1)
	var candidates: Array[int] = []
	for index: int in range(low, high + 1):
		if by_total[index] != original and not excluded.has(int(by_total[index])):
			candidates.append(by_total[index])
	if candidates.is_empty():
		return original
	return candidates[rng.below(candidates.size())]


## The keys of [param rows] as ascending numbers, which is the order everything
## here is walked in.
static func _sorted(rows: Dictionary) -> Array[int]:
	var numbers: Array[int] = []
	for number: int in rows:
		numbers.append(number)
	numbers.sort()
	return numbers


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


## The rows assembled by number, listed in ascending number order.
static func _listed(rows: Dictionary) -> Array:
	var out: Array = []
	for number: int in _sorted(rows):
		out.append({"number": number, "fields": rows[number]})
	return out


## The fields being assembled for one number, created on first use so a species
## touched by three settings is patched once.
static func _field(out: Dictionary, number: int) -> Dictionary:
	if not out.has(number):
		out[number] = {}
	return out[number]
