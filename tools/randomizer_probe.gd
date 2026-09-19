extends SceneTree

## Builds the randomizer's plan against a real cartridge cache and PRINTS what
## it changed, without a game running.

const DEFAULT_SEED: int = 1234
const OTHER_SEED: int = 5678
const FISHING_LISTS: Array[String] = ["rods", "slots"]
const SPECIAL_TWINS: Array[String] = ["sp_attack", "sp_defense"]


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
	var settings: Dictionary = options.settings(null)
	settings["seed"] = seed_value

	var world: Dictionary = plan.gather(data)
	print("cartridge  %s: %d species, %d moves, %d trainer classes, %d types, %d sites" % [
		data.id, (world["species_numbers"] as Array).size(),
		(world["move_numbers"] as Array).size(),
		(world["trainer_numbers"] as Array).size(),
		(world["type_pool"] as Array).size(),
		(world[&"check"] as Dictionary).size(),
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
	quit(int(failures > 0))


func _with_seed(settings: Dictionary, seed_value: int) -> Dictionary:
	var out: Dictionary = settings.duplicate(true)
	out["seed"] = seed_value
	return out


func _counts(patches: Dictionary) -> void:
	for kind: StringName in patches.keys():
		print("patched    %-10s %d rows" % [kind, (patches[kind] as Array).size()])


func _by_number(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in entries:
		out[int(entry["number"])] = entry["fields"]
	return out


func _samples(world: Dictionary, patches: Dictionary, data: GameData) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var keys: Array[String] = world["stat_keys"]
	var patched: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_SPECIES])
	for number: int in [1, 4, 7, 25]:
		if not patched.has(number):
			continue
		var was: Dictionary = species[number]
		var now: Dictionary = patched[number]
		print("%-12s types %s -> %s, stats %s -> %s" % [
			String(was.get("name", "?")), _ints(was.get("types", [])), now.get("types", []),
			_stat_line(was.get("stats", {}), keys), _stat_line(now.get("stats", {}), keys),
		])
		var opening: Array = _opening(now)
		if not opening.is_empty():
			print("             opens with %s at level %d" % [
				data.move(int(opening[0])).get("name", "?"), int(opening[1]),
			])


## The first move a fresh one knows: a starting move on Generation I, else the
## learnset's head. `[move, level]`, or empty.
func _opening(fields: Dictionary) -> Array:
	var starting: Array = fields.get("starting_moves", [])
	if not starting.is_empty():
		return [int(starting[0]), 1]
	var learnset: Array = fields.get("learnset", [])
	if learnset.is_empty():
		return []
	return [int((learnset[0] as Dictionary)["move"]), int((learnset[0] as Dictionary)["level"])]


func _wild_sample(world: Dictionary, patches: Dictionary, data: GameData) -> void:
	var tables: Dictionary = world[Gen2ContentOverlay.KIND_ENCOUNTER]
	for entry: Dictionary in (patches[Gen2ContentOverlay.KIND_ENCOUNTER] as Array):
		if StringName(entry["method"]) != &"grass":
			continue
		var was: Dictionary = tables[int(entry["at"])]
		print("map %d,%d grass  %s" % [
			int(entry["group"]), int(entry["number"]), _names(data, was["slots"]),
		])
		print("            ->  %s" % _names(data, (entry["fields"] as Dictionary)["slots"]))
		return


## A Generation II table is one row per time of day and a Generation I table is
## flat; either way the first row is what is named.
func _names(data: GameData, slots: Array) -> String:
	var row: Array = slots[0] if not slots.is_empty() and slots[0] is Array else slots
	var out: PackedStringArray = PackedStringArray()
	for slot: Dictionary in row:
		out.append("%s %d" % [
			data.species(int(slot["species"])).get("name", "?"), int(slot["level"]),
		])
	return ", ".join(out)


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out


func _stat_line(stats: Dictionary, keys: Array[String]) -> String:
	var out: PackedStringArray = PackedStringArray()
	for key: String in keys:
		out.append(str(int(stats.get(key, 0))))
	return "/".join(out)


func _rules(world: Dictionary, patches: Dictionary, validator: Callable) -> int:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var moves: Dictionary = world[Gen2ContentOverlay.KIND_MOVE]
	var totals: Dictionary = world["totals"]
	var keys: Array[String] = world["stat_keys"]
	var patched: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_SPECIES])
	var numbers: Array[int] = []
	for number: int in patched:
		numbers.append(number)
	numbers.sort()

	var kept_total: bool = true
	var twinned: bool = true
	var armed: bool = true
	var climbs: bool = true
	for number: int in numbers:
		var row: Dictionary = patched[number]
		var stats: Dictionary = row.get("stats", {})
		if not stats.is_empty() and _sum(stats, keys) != int(totals[number]):
			kept_total = false
		if stats.has("special") and not _special_twinned(stats):
			twinned = false
		for entry: Dictionary in _openings(row):
			if int(moves[int(entry["move"])].get("power", 0)) <= 0:
				armed = false
		for evolution: Dictionary in (row.get("evolutions", []) as Array):
			if int(totals[int(evolution["target"])]) < int(totals[number]):
				climbs = false

	var failures: int = 0
	for check: Array in [
		["a species keeps its base stat total", kept_total],
		["a Generation I SPECIAL is mirrored on both halves", twinned],
		["nothing opens without a way to attack", armed],
		["an evolution is never a downgrade", climbs],
		["an evolution line's stats still climb", _lines_climb(species, patched, keys)],
		["a wild slot keeps its level and its place", _wild_keeps_levels(world, patches)],
		["a learnset avoids repeat moves", _learnsets_do_not_repeat(patched)],
		["starting moves are redrawn wherever a row has them",
			_starting_moves_redrawn(species, patched)],
		["a species replacement is not a no-op", _species_replacements_change(world, patches)],
		["extra wild sources keep every non-species field",
			_indexed_wild_keeps_shape(world, patches)],
	]:
		if not _report(String(check[0]), bool(check[1])):
			failures += 1
	return failures + _site_rules(world, patches, validator)


## The rules over the catalog's sites, which the host builds from Generation II
## scripts alone: a cache with none is said so rather than failed, and the
## checks run the day the host carries them.
func _site_rules(world: Dictionary, patches: Dictionary, validator: Callable) -> int:
	if (world[&"check"] as Dictionary).is_empty():
		print("none  no catalog sites on this cache; gifts, starters, trades, items, badges and shops untested")
		return 0
	var failures: int = 0
	for check: Array in [
		["decoded Pokemon sites change both trade halves", _checks_change_species(world, patches)],
		["items, badges and shop stock are permutations", _placement_is_permutation(world, patches)],
		["the host accepts the critical placement", _placement_validates(patches, validator)],
	]:
		if not _report(String(check[0]), bool(check[1])):
			failures += 1
	return failures


## The entries a fresh Pokemon may open with: every starting move, the
## learnset's head, and anything at level 5 or below.
func _openings(row: Dictionary) -> Array:
	var out: Array = []
	for move: Variant in (row.get("starting_moves", []) as Array):
		out.append({"move": int(move), "level": 1})
	var learnset: Array = row.get("learnset", [])
	for index: int in learnset.size():
		var entry: Dictionary = learnset[index]
		if (index == 0 and out.is_empty()) or int(entry.get("level", 1)) <= 5:
			out.append(entry)
	return out


func _special_twinned(stats: Dictionary) -> bool:
	for twin: String in SPECIAL_TWINS:
		if int(stats.get(twin, -1)) != int(stats["special"]):
			return false
	return true


func _starting_moves_redrawn(species: Dictionary, patched: Dictionary) -> bool:
	for number: int in patched:
		var was: Array = (species[number] as Dictionary).get("starting_moves", [])
		var now: Array = (patched[number] as Dictionary).get("starting_moves", [])
		if was.size() != now.size():
			return false
		if not was.is_empty() and _ints(was) == _ints(now):
			return false
	return true


func _learnsets_do_not_repeat(patched: Dictionary) -> bool:
	for fields: Dictionary in patched.values():
		var used: Array[int] = _ints(fields.get("starting_moves", []))
		if used.size() != _distinct(used).size():
			return false
		for entry: Dictionary in (fields.get("learnset", []) as Array):
			var move: int = int(entry.get("move", 0))
			if used.has(move):
				return false
			used.append(move)
	return true


func _distinct(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for value: int in values:
		if not out.has(value):
			out.append(value)
	return out


func _species_replacements_change(world: Dictionary, patches: Dictionary) -> bool:
	var trainer_patches: Dictionary = _by_number(patches[Gen2ContentOverlay.KIND_TRAINER])
	for number: int in trainer_patches:
		var before: Array = (world[Gen2ContentOverlay.KIND_TRAINER] as Dictionary)[number] \
			.get("trainers", [])
		var after: Array = (trainer_patches[number] as Dictionary).get("trainers", [])
		if not _species_changed(_parties(before), _parties(after)):
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
		for key: String in FISHING_LISTS:
			if before.has(key) and not _species_changed(
				before[key], (entry["fields"] as Dictionary).get(key, null)
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


## A roster entry's `special_moves` on Generation I key on the rival's starter
## rather than name a member, so only the parties are compared.
func _parties(roster: Array) -> Array:
	var out: Array = []
	for trainer: Dictionary in roster:
		out.append(trainer.get("party", []))
	return out


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
		for key: String in FISHING_LISTS:
			if was.has(key) and not _same_shape(was[key], (entry["fields"] as Dictionary).get(key, null)):
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


func _lines_climb(species: Dictionary, patched: Dictionary, keys: Array[String]) -> bool:
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
			if _gaps(species[number].get("stats", {}), species[target].get("stats", {}), keys) \
					!= _gaps(now, target_now, keys):
				return false
	return true


func _gaps(low: Dictionary, high: Dictionary, keys: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for key: String in keys:
		out.append(int(high.get(key, 0)) - int(low.get(key, 0)))
	out.sort()
	return out


func _sum(stats: Dictionary, keys: Array[String]) -> int:
	var total: int = 0
	for key: String in keys:
		total += int(stats.get(key, 0))
	return total


func _report(what: String, passed: bool) -> bool:
	print("%s  %s" % ["ok  " if passed else "FAIL", what])
	return passed


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
