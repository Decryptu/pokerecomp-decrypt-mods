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
##       "user://rom_cache/crystal_f2f52230" [seed] [other seed]

const DEFAULT_SEED: int = 1234
const OTHER_SEED: int = 5678


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cache directory> [seed] [other seed]")
		quit(2)
		return
	var data: GameData = GameData.open_directory(args[0])
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

	var first: Dictionary = plan.build(world, settings)
	var again: Dictionary = plan.build(world, settings)
	var elsewhere: Dictionary = plan.build(world, _with_seed(settings, other_seed))
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
	var failures: int = _rules(world, first)
	quit(1 if failures > 0 else 0)


func _with_seed(settings: Dictionary, seed_value: int) -> Dictionary:
	var out: Dictionary = settings.duplicate(true)
	out["seed"] = seed_value
	return out


func _counts(patches: Dictionary) -> void:
	for kind: StringName in [
		Gen2ContentOverlay.KIND_SPECIES,
		Gen2ContentOverlay.KIND_MOVE,
		Gen2ContentOverlay.KIND_TRAINER,
	]:
		print("patched    %-8s %d rows" % [kind, (patches[kind] as Dictionary).size()])


## A few rows written out, because a count says a plan ran and a row says what
## it did.
func _samples(world: Dictionary, patches: Dictionary, data: GameData) -> void:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var patched: Dictionary = patches[Gen2ContentOverlay.KIND_SPECIES]
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
func _rules(world: Dictionary, patches: Dictionary) -> int:
	var species: Dictionary = world[Gen2ContentOverlay.KIND_SPECIES]
	var moves: Dictionary = world[Gen2ContentOverlay.KIND_MOVE]
	var totals: Dictionary = world["totals"]
	var patched: Dictionary = patches[Gen2ContentOverlay.KIND_SPECIES]
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
	var failures: int = 0
	for check: Array in [
		["a species keeps its base stat total", kept_total],
		["nothing opens without a way to attack", armed],
		["an evolution is never a downgrade", climbs],
		["an evolution line's stats still climb", lines],
	]:
		if not _report(String(check[0]), bool(check[1])):
			failures += 1
	return failures


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
