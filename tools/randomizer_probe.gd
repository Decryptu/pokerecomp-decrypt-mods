extends SceneTree

## Builds the randomizer's plan against a real cartridge cache and PRINTS what
## it changed, without a game running.
##
## A randomizer that cannot be shown to be deterministic is not finished, so the
## first two lines are the whole point: one seed built twice has to digest to
## the same number, and two seeds have to digest to different ones. The rest is
## what the sane defaults promise, checked rather than asserted in a comment.
##
##   Godot --headless --path <pokerecomp> -s tools/randomizer_probe.gd -- \
##       <cartridge> [seed] [other seed]

const DEFAULT_SEED: int = 1234
const OTHER_SEED: int = 5678


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cache directory> [seed] [other seed]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return

	# The mod sits beside this tool in the same checkout, which is what lets a
	# probe run without the mod being installed or linked anywhere.
	var mod: String = (get_script() as Script).resource_path.get_base_dir() \
		.get_base_dir().path_join("mods/randomizer")
	var plan: GDScript = load("%s/plan.gd" % mod)
	var rng: GDScript = load("%s/rng.gd" % mod)
	var options: GDScript = load("%s/options.gd" % mod)
	if plan == null or rng == null or options == null:
		print("no mod scripts under %s" % mod)
		quit(1)
		return

	var seed_value: int = int(args[1]) if args.size() > 1 else DEFAULT_SEED
	var other_seed: int = int(args[2]) if args.size() > 2 else OTHER_SEED
	# Every setting on: what is being checked is the plan, and a toggle that is
	# off is a part of it nobody can see.
	var settings: Dictionary = options.settings(null)
	settings["seed"] = seed_value

	var world: Dictionary = plan.gather(data)
	print("cartridge  %s: %d species, %d moves, %d trainer classes, %d types" % [
		data.id, (world["species_numbers"] as Array).size(),
		(world["move_numbers"] as Array).size(),
		(world["trainer_numbers"] as Array).size(),
		(world["type_pool"] as Array).size(),
	])

	var host: Gen2ModHost = Gen2ModHost.instance()
	var validate := func(candidate: Dictionary) -> Dictionary:
		return host.validate_placement(data, candidate)
	var first: Dictionary = plan.build(world, settings, validate)
	var again: Dictionary = plan.build(world, settings, validate)
	var elsewhere: Dictionary = plan.build(world, _with_seed(settings, other_seed), validate)
	var first_digest: int = rng.text_hash(_canonical(first))
	var again_digest: int = rng.text_hash(_canonical(again))
	var other_digest: int = rng.text_hash(_canonical(elsewhere))

	print("seed %s     digest %08x, built twice %08x" % [
		options.seed_text(seed_value), first_digest, again_digest,
	])
	print("seed %s     digest %08x" % [options.seed_text(other_seed), other_digest])
	_report("one seed twice is one game", first_digest == again_digest)
	_report("two seeds are two games", first_digest != other_digest)

	_counts(first)
	_samples(world, first, data)
	_wild_sample(world, first, data)
	var failures: int = _rules(world, first, validate)
	quit(1 if failures > 0 else 0)


func _with_seed(settings: Dictionary, seed_value: int) -> Dictionary:
	var out: Dictionary = settings.duplicate(true)
	out["seed"] = seed_value
	return out


func _counts(patches: Dictionary) -> void:
	for kind: StringName in patches.keys():
		print("patched    %-10s %d rows" % [kind, (patches[kind] as Array).size()])


## The plan's list for one kind, by number, for a check that wants to ask about
## one row rather than walk them all.
func _by_number(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in entries:
		out[int(entry["number"])] = entry["fields"]
	return out


## A few rows written out, because a count says a plan ran and a row says what
## it did.
func _samples(world: Dictionary, patches: Dictionary, data: GameData) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var patched: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_SPECIES])
	for number: int in [1, 4, 7, 25]:
		if not patched.has(number):
			continue
		var was: Dictionary = species[number]
		var now: Dictionary = patched[number]
		print("%-12s types %s -> %s, stats %s -> %s" % [
			String(was.get("name", "?")), _ints(was.get("types", [])), now.get("types", []),
			_stat_line(was.get("stats", {})), _stat_line(now.get("stats", {})),
		])
		var learnset: Array = now.get("learnset", [])
		if not learnset.is_empty():
			var opening: Dictionary = learnset[0]
			print("             opens with %s at level %d" % [
				data.move(int(opening["move"])).get("name", "?"), int(opening["level"]),
			])


## One route's grass, written out both ways. A count says the tables were
## walked; a route says what the player will meet on it.
func _wild_sample(world: Dictionary, patches: Dictionary, data: GameData) -> void:
	var tables: Dictionary = world[Gen2ContentOverlay.KIND_ENCOUNTER]
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_ENCOUNTER] as Array):
		if StringName(entry["method"]) != &"grass":
			continue
		var was: Dictionary = tables[int(entry["at"])]
		print("map %d,%d grass  %s" % [
			int(entry["group"]), int(entry["number"]),
			_names(data, ((was["slots"] as Array)[0] as Array)),
		])
		print("            ->  %s" % _names(
			data, (((entry["fields"] as Dictionary)["slots"] as Array)[0] as Array)
		))
		return


func _names(data: GameData, slots: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for slot: Dictionary in slots:
		out.append("%s %d" % [
			data.species(int(slot["species"])).get("name", "?"), int(slot["level"]),
		])
	return ", ".join(out)


## The cartridge's own rows come back out of JSON as floats, which is a fact
## about the cache and not about the type.
func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out


func _stat_line(stats: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for key: String in ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]:
		out.append(str(int(stats.get(key, 0))))
	return "/".join(out)


## What the sane defaults promise, asked of every row rather than of a sample.
func _rules(world: Dictionary, patches: Dictionary, validator: Callable) -> int:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var moves: Dictionary = world[Gen2ContentOverlay.KIND_MOVE]
	var totals: Dictionary = world["totals"]
	var patched: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_SPECIES])
	var numbers: Array[int] = []
	for number: int in patched:
		numbers.append(number)
	numbers.sort()

	var kept_total: bool = true
	var armed: bool = true
	var climbs: bool = true
	for number: int in numbers:
		var row: Dictionary = patched[number]
		var stats: Dictionary = row.get("stats", {})
		if not stats.is_empty() and _sum(stats) != int(totals[number]):
			kept_total = false
		for index: int in (row.get("learnset", []) as Array).size():
			var entry: Dictionary = (row["learnset"] as Array)[index]
			if index > 0 and int(entry.get("level", 1)) > 5:
				continue
			if int(moves[int(entry["move"])].get("power", 0)) <= 0:
				armed = false
		for evolution: Dictionary in (row.get("evolutions", []) as Array):
			if int(totals[int(evolution["target"])]) < int(totals[number]):
				climbs = false

	var lines: bool = _lines_climb(species, patched)
	var levels: bool = _wild_keeps_levels(world, patches)
	var distinct_learnsets: bool = _learnsets_do_not_repeat(patched)
	var changed_species: bool = _species_replacements_change(world, patches)
	var extended_wild: bool = _indexed_wild_keeps_shape(world, patches)
	var decoded_sites: bool = _checks_change_species(world, patches)
	var placement_pool: bool = _placement_is_permutation(world, patches)
	var placement_valid: bool = _placement_validates(patches, validator)
	var failures: int = 0
	for check: Array in [
		["a species keeps its base stat total", kept_total],
		["nothing opens without a way to attack", armed],
		["an evolution is never a downgrade", climbs],
		["an evolution line's stats still climb", lines],
		["a wild slot keeps its level and its place", levels],
		["a learnset avoids repeat moves", distinct_learnsets],
		["a species replacement is not a no-op", changed_species],
		["extra wild sources keep every non-species field", extended_wild],
		["decoded Pokemon sites change both trade halves", decoded_sites],
		["items, badges and shop stock are permutations", placement_pool],
		["the host accepts the critical placement", placement_valid],
	]:
		if not _report(String(check[0]), bool(check[1])):
			failures += 1
	return failures


func _learnsets_do_not_repeat(patched: Dictionary) -> bool:
	for fields: Dictionary in patched.values():
		var used: Array[int] = []
		for entry: Dictionary in (fields.get("learnset", []) as Array):
			var move: int = int(entry.get("move", 0))
			if used.has(move):
				return false
			used.append(move)
	return true


func _species_replacements_change(world: Dictionary, patches: Dictionary) -> bool:
	var trainer_patches: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_TRAINER])
	for number: int in trainer_patches:
		var before: Variant = (world[Gen2ContentOverlay.KIND_TRAINER] as Dictionary)[number] \
			.get("trainers", [])
		var after: Variant = (trainer_patches[number] as Dictionary).get("trainers", [])
		if not _species_changed(before, after):
			return false
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_ENCOUNTER] as Array):
		var before: Dictionary = (world[Gen2ContentOverlay.KIND_ENCOUNTER] as Dictionary)[
			int(entry["at"])
		]
		if not _species_changed(
			before.get("slots", []), (entry["fields"] as Dictionary).get("slots", [])
		):
			return false
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_FISHING] as Array):
		var before: Dictionary = (world[Gen2ContentOverlay.KIND_FISHING] as Dictionary)[
			int(entry["number"])
		]
		if not _species_changed(
			before.get("rods", []), (entry["fields"] as Dictionary).get("rods", [])
		):
			return false
	for kind: StringName in [&"treemon", &"fishing_time"]:
		var rows: Dictionary = world[kind]
		for entry: Dictionary in (patches[kind] as Array):
			var number: int = int(entry["number"])
			if not _species_changed(rows[number], entry["fields"]):
				return false
	for kind: StringName in [&"bug_contest", &"roaming"]:
		var rows: Dictionary = world[kind]
		for entry: Dictionary in (patches[kind] as Array):
			var number: int = int(entry["number"])
			if int((rows[number] as Dictionary)["species"]) \
					== int((entry["fields"] as Dictionary)["species"]):
				return false
	return true


func _checks_change_species(world: Dictionary, patches: Dictionary) -> bool:
	var rows: Dictionary = world[&"check"]
	var found: bool = false
	for entry: Dictionary in (patches[&"check"] as Array):
		var number: int = int(entry["number"])
		if not (rows[number] as Dictionary).has("species"):
			continue
		found = true
		if int((rows[number] as Dictionary).get("species", 0)) \
				== int((entry["fields"] as Dictionary).get("species", 0)):
			return false
		if StringName((rows[number] as Dictionary).get("kind", &"")) \
				== Gen2WorldCatalog.KIND_TRADE \
				and int((rows[number] as Dictionary).get("requested_species", 0)) \
				== int((entry["fields"] as Dictionary).get("requested_species", 0)):
			return false
	return found


func _placement_is_permutation(world: Dictionary, patches: Dictionary) -> bool:
	var rows: Dictionary = world[&"check"]
	var changed: Dictionary = _by_number(patches[&"check"])
	var before_items: Array[String] = []
	var after_items: Array[String] = []
	var before_badges: Array[int] = []
	var after_badges: Array[int] = []
	var badge_sites: int = 0
	var before_stock: Array[int] = []
	var after_stock: Array[int] = []
	var before_prices: Array[int] = []
	var after_prices: Array[int] = []
	for id: int in rows:
		var row: Dictionary = rows[id]
		var kind: StringName = StringName(row.get("kind", &""))
		if kind == Gen2WorldCatalog.KIND_ITEM:
			before_items.append("%d:%d" % [int(row["item"]), int(row["quantity"])])
			var now: Dictionary = changed.get(id, {})
			after_items.append("%d:%d" % [int(now.get("item", -1)), int(now.get("quantity", -1))])
		elif kind == Gen2WorldCatalog.KIND_BADGE:
			badge_sites += 1
			var before_badge: int = int(row["badge"])
			var after_badge: int = int((changed.get(id, {}) as Dictionary).get("badge", -1))
			if not before_badges.has(before_badge):
				before_badges.append(before_badge)
			if not after_badges.has(after_badge):
				after_badges.append(after_badge)
		elif kind == Gen2WorldCatalog.KIND_SHOP:
			var was: Array = row.get("items", [])
			var now: Array = (changed.get(id, {}) as Dictionary).get("items", [])
			if was.size() != now.size():
				return false
			for entry: Dictionary in was:
				if not before_stock.has(int(entry["item"])):
					before_stock.append(int(entry["item"]))
				before_prices.append(int(entry["price"]))
			for entry: Dictionary in now:
				if not after_stock.has(int(entry["item"])):
					after_stock.append(int(entry["item"]))
				after_prices.append(int(entry["price"]))
	before_items.sort()
	after_items.sort()
	before_badges.sort()
	after_badges.sort()
	before_stock.sort()
	after_stock.sort()
	before_prices.sort()
	after_prices.sort()
	return badge_sites > 0 and before_items == after_items and before_badges == after_badges \
		and before_stock == after_stock and before_prices == after_prices


func _placement_validates(patches: Dictionary, validator: Callable) -> bool:
	var proposed: Dictionary = {}
	for entry: Dictionary in (patches[&"check"] as Array):
		proposed[int(entry["number"])] = entry["fields"]
	var first: Dictionary = validator.call(proposed)
	var again: Dictionary = validator.call(proposed)
	return bool(first.get("ok", false)) and first == again


func _species_changed(before: Variant, after: Variant) -> bool:
	if before is Array:
		if not after is Array or (before as Array).size() != (after as Array).size():
			return false
		for index: int in (before as Array).size():
			if not _species_changed((before as Array)[index], (after as Array)[index]):
				return false
		return true
	if before is Dictionary:
		if not after is Dictionary:
			return false
		if (before as Dictionary).has("species"):
			return int((before as Dictionary)["species"]) != int((after as Dictionary)["species"])
		for key: Variant in before as Dictionary:
			if not _species_changed(
				(before as Dictionary)[key], (after as Dictionary).get(key, null)
			):
				return false
	return true


## What the wild tables promise: every slot is still there, in the same place,
## at the level the cartridge put it. Only the species moves, and the same walk
## covers a grass table's three times of day, a water table's flat list and a
## rod's thresholds.
func _wild_keeps_levels(world: Dictionary, patches: Dictionary) -> bool:
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_ENCOUNTER] as Array):
		var was: Dictionary = (world[Gen2ContentOverlay.KIND_ENCOUNTER] as Dictionary)[
			int(entry["at"])
		]
		if not _same_shape(was.get("slots", []), (entry["fields"] as Dictionary)["slots"]):
			return false
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_FISHING] as Array):
		var was: Dictionary = (world[Gen2ContentOverlay.KIND_FISHING] as Dictionary)[
			int(entry["number"])
		]
		if not _same_shape(was.get("rods", []), (entry["fields"] as Dictionary)["rods"]):
			return false
	return true


func _indexed_wild_keeps_shape(world: Dictionary, patches: Dictionary) -> bool:
	for kind: StringName in [&"treemon", &"fishing_time"]:
		var rows: Dictionary = world[kind]
		for entry: Dictionary in (patches[kind] as Array):
			if not _same_shape(rows[int(entry["number"])], entry["fields"]):
				return false
	for kind: StringName in [&"bug_contest", &"roaming"]:
		var rows: Dictionary = world[kind]
		for entry: Dictionary in (patches[kind] as Array):
			var before: Dictionary = rows[int(entry["number"])]
			var after: Dictionary = before.duplicate(true)
			after["species"] = int((entry["fields"] as Dictionary)["species"])
			if not _same_shape(before, after):
				return false
	return true


## The same nesting, the same entries and every key but the species equal.
func _same_shape(was: Variant, now: Variant) -> bool:
	if was is Array:
		if not now is Array or (was as Array).size() != (now as Array).size():
			return false
		for index: int in (was as Array).size():
			if not _same_shape((was as Array)[index], (now as Array)[index]):
				return false
		return true
	if was is Dictionary:
		if not now is Dictionary:
			return false
		for key: Variant in was as Dictionary:
			if String(key) == "species":
				continue
			if not _same_shape((was as Dictionary)[key], (now as Dictionary).get(key, null)):
				return false
		return true
	return int(was) == int(now) if was is float or was is int else was == now


## What a shared permutation BUYS, asked of the cartridge's own evolution
## edges: every gap between a species and what it evolves into is still there,
## on some stat or other, and none of them changed sign. Read as the sorted list
## of the six differences, because which slot a gap ended up in is exactly what
## the shuffle moved.
func _lines_climb(species: Dictionary, patched: Dictionary) -> bool:
	var numbers: Array[int] = []
	for number: int in patched:
		numbers.append(number)
	numbers.sort()
	for number: int in numbers:
		var now: Dictionary = (patched[number] as Dictionary).get("stats", {})
		if now.is_empty():
			continue
		for evolution: Dictionary in (species[number].get("evolutions", []) as Array):
			var target: int = int(evolution.get("target", 0))
			if not patched.has(target):
				continue
			var target_now: Dictionary = (patched[target] as Dictionary).get("stats", {})
			if target_now.is_empty():
				continue
			if _gaps(species[number].get("stats", {}), species[target].get("stats", {})) \
					!= _gaps(now, target_now):
				return false
	return true


## The six differences between two species' stats, sorted, which is the part of
## them a permutation cannot change.
func _gaps(low: Dictionary, high: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for key: String in ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]:
		out.append(int(high.get(key, 0)) - int(low.get(key, 0)))
	out.sort()
	return out


func _sum(stats: Dictionary) -> int:
	var total: int = 0
	for key: String in ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]:
		total += int(stats.get(key, 0))
	return total


func _report(what: String, passed: bool) -> bool:
	print("%s  %s" % ["ok  " if passed else "FAIL", what])
	return passed


## The plan written out in one order, so a digest is a fact about the plan and
## not about the order a Dictionary handed its keys over in.
func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var pairs: PackedStringArray = PackedStringArray()
		for key: Variant in keys:
			pairs.append("%s=%s" % [key, _canonical((value as Dictionary)[key])])
		return "{%s}" % ",".join(pairs)
	if value is Array:
		var items: PackedStringArray = PackedStringArray()
		for item: Variant in value as Array:
			items.append(_canonical(item))
		return "[%s]" % ",".join(items)
	return str(value)
