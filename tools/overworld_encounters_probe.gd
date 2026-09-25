extends SceneTree

const DEFAULT_SEED: int = 1234
const OTHER_SEED: int = 5678
const ROAM_STEPS: int = 40
const WALK_FRAMES: int = 400
const SPREAD_RUNS: int = 200
const SPREAD_OCTILES: int = 8
const SPREAD_RATIO: float = 1.5
const SHINY_SEED_ATTEMPTS: int = 20000
const SHARE_RUNS: int = 400
const SHARE_TOLERANCE: float = 0.02
const ANNOUNCE_FRAMES: int = 8
const POPULATION: int = 6

## `CheckShininess`: the attack mask and three tens.
const SHINY_DVS: int = (2 << 12) | (10 << 8) | (10 << 4) | 10

var _plan: GDScript = null
var _provider_script: GDScript = null


## What the host hands a provider, kept. The other three are the contract's.
class Capture extends RefCounted:
	var context: Dictionary = {}
	var entries: Array = []

	func set_context(given: Dictionary) -> void:
		context = given

	func advance_frame() -> void:
		pass

	func encounters() -> Array:
		return entries

	func battle_finished(_id: StringName, _result: Variant) -> void:
		pass


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cartridge> [seed] [other seed]")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return
	var world: Gen2WorldAPI = _first_world(data)
	if not _load_mod() or world == null:
		print("no encounter plan or cartridge map")
		quit(1)
		return
	var context: Dictionary = _host_context(world)
	var seed_value: int = int(args[1]) if args.size() > 1 else DEFAULT_SEED
	var other_seed: int = int(args[2]) if args.size() > 2 else OTHER_SEED
	print("cartridge  %s" % data.id)
	print("map %s: %d eligible cells" % [
		str(context["map"]), _eligible_count(context),
	])
	var failures: int = 0
	failures += _determinism(context, seed_value, other_seed)
	failures += _clear_of_objects(context)
	failures += _walking(context)
	failures += _turnover(context)
	failures += _spread(context)
	failures += _glowing(context)
	failures += _shares(context)
	failures += _announced(world, context)
	_print_population(context, seed_value)
	quit(int(failures > 0))


func _load_mod() -> bool:
	var mod: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir() \
		.path_join("mods/overworld_encounters")
	_plan = load(mod.path_join("plan.gd"))
	_provider_script = load(mod.path_join("provider.gd"))
	return _plan != null and _provider_script != null


func _print_population(context: Dictionary, seed_value: int) -> void:
	for entry: Dictionary in _plan.build(context, seed_value, POPULATION):
		print("  id %s cell %s species %d level %d dvs %04x%s" % [
			String(entry["id"]), entry["cell"], int(entry["species"]), int(entry["level"]),
			int(entry["dvs"]), " shiny" if _plan.is_shiny(int(entry["dvs"])) else "",
		])


func _report(what: String, passed: bool) -> int:
	print("%s  %s" % ["ok  " if passed else "FAIL", what])
	return int(not passed)


func _determinism(context: Dictionary, seed_value: int, other_seed: int) -> int:
	var first: String = JSON.stringify(_plan.build(context, seed_value, POPULATION))
	var again: String = JSON.stringify(_plan.build(context, seed_value, POPULATION))
	var other: String = JSON.stringify(_plan.build(context, other_seed, POPULATION))
	var seeded: Dictionary = context.duplicate(true)
	seeded["run_seed"] = seed_value
	var provider: RefCounted = _provider_script.new()
	provider.set_context(seeded)
	var before_pose: String = JSON.stringify(provider.encounters())
	var moved: Dictionary = seeded.duplicate(true)
	moved["player"] = {"cell": Vector2i(1, 1), "facing": 2}
	provider.set_context(moved)
	var after_pose: String = JSON.stringify(provider.encounters())
	return _report("one seed twice is byte-identical", first == again) \
		+ _report("two seeds differ", first != other) \
		+ _report("a pose refresh preserves the population", before_pose == after_pose)


func _clear_of_objects(context: Dictionary) -> int:
	var taken: PackedVector2Array = _taken(context)
	var busy: Dictionary = context.duplicate(true)
	busy["occupied"] = taken
	busy["generation"] = 2
	var crowd: RefCounted = _provider_script.new()
	crowd.set_context(busy)
	var clear_spawn: bool = _clear_of(crowd.encounters(), taken)
	var clear_roam: bool = true
	for _step: int in ROAM_STEPS * int(_provider_script.MOVE_FRAMES):
		crowd.advance_frame()
		if not _clear_of(crowd.encounters(), taken):
			clear_roam = false
			break
	return _report("%d cells taken by an object: spawns clear" % taken.size(), clear_spawn) \
		+ _report("%d moves clear of them" % ROAM_STEPS, clear_roam)


## What a walking population answers, frame by frame. A step is one cardinal
## cell, its target is one the host would accept, and the frame after asking the
## wild stands there: the host holds the walk from the moment it is asked for and
## keeps the wild on its target until this row names that cell, so a row naming
## anything else would put the wild somewhere it never walked.
func _walking(context: Dictionary) -> int:
	var busy: Dictionary = context.duplicate(true)
	busy["occupied"] = _taken(context)
	busy["generation"] = 2
	var provider: RefCounted = _provider_script.new()
	provider.set_context(busy)
	var player_cell := Vector2i((busy.get("player", {}) as Dictionary).get(
		"cell", Vector2i(-1, -1)
	))
	var occupied: PackedVector2Array = busy["occupied"]
	var eligible: Dictionary = busy.get("eligible", {})
	var asked: int = 0
	var landed: int = 0
	var sound: bool = true
	var pending: Dictionary = {}
	for _frame: int in WALK_FRAMES:
		provider.advance_frame()
		var now: Dictionary = {}
		var held: Dictionary = {}
		for entry: Dictionary in provider.encounters():
			now[StringName(entry["id"])] = entry
			held[Vector2i(entry["cell"])] = true
		for id: Variant in pending:
			if not now.has(id):
				continue
			landed += 1
			sound = sound and Vector2i((now[id] as Dictionary)["cell"]) == Vector2i(pending[id])
		pending = {}
		for id: Variant in now:
			var entry: Dictionary = now[id]
			if not entry.has("step"):
				continue
			asked += 1
			var to: Vector2i = Vector2i(entry["cell"]) + Vector2i(entry["step"])
			pending[id] = to
			sound = sound and _step_sound(entry, to, player_cell, occupied, eligible, held)
	return _report("%d steps asked for over %d frames, %d landed where they said" % [
		asked, WALK_FRAMES, landed,
	], sound and asked > 0)


func _step_sound(
	entry: Dictionary, to: Vector2i, player_cell: Vector2i,
	occupied: PackedVector2Array, eligible: Dictionary, held: Dictionary
) -> bool:
	var step := Vector2i(entry["step"])
	if absi(step.x) + absi(step.y) != 1:
		return false
	var cells: PackedVector2Array = eligible.get(
		StringName(entry.get("method", &"")), PackedVector2Array()
	)
	return to != player_cell and cells.has(to) \
		and not occupied.has(Vector2(to)) and not held.has(to)


func _turnover(context: Dictionary) -> int:
	var settings: Dictionary = context.duplicate(true)
	settings["generation"] = 7
	settings["run_seed"] = _a_shiny_map(settings)
	var provider: RefCounted = _provider_script.new()
	provider.set_context(settings)
	var shiny_id: StringName = _shiny_id(provider.encounters())
	var run: Dictionary = _run_turnover(provider)
	var shortest: int = int(run["shortest"])
	var longest: int = int(run["longest"])
	return _report("turnover over %d frames: %d left, %d arrived, cap held" % [
			int(run["frames"]), int(run["left"]), int(run["arrived"]),
		], bool(run["cap_held"]) and int(run["left"]) > 0 and int(run["arrived"]) > 0) \
		+ _report("every id is its own Pokemon", bool(run["ids_unique"])) \
		+ _report("a despawn is between %d and %d frames (%d to %d seen)" % [
			int(_provider_script.DESPAWN_MIN_FRAMES), int(_provider_script.DESPAWN_MAX_FRAMES),
			shortest, longest,
		], shortest >= int(_provider_script.DESPAWN_MIN_FRAMES) \
			and longest <= int(_provider_script.DESPAWN_MAX_FRAMES)) \
		+ _report("a shiny never counts down, and everyone else does",
			shiny_id != &"" and (run["live"] as Dictionary).has(shiny_id) and bool(run["timers"])) \
		+ _battle_refills(provider, shiny_id)


## A full despawn span and a few refills, frame by frame: who left, who arrived,
## how long each stayed, and whether the cap and the timers held throughout.
func _run_turnover(provider: RefCounted) -> Dictionary:
	var out: Dictionary = {
		"left": 0, "arrived": 0, "cap_held": true, "ids_unique": true,
		"timers": _timers_sound(provider.encounters()), "lifetimes": [],
	}
	var live: Dictionary = {}
	var seen: Dictionary = {}
	for entry: Dictionary in provider.encounters():
		live[entry["id"]] = 0
		seen[entry["id"]] = true
	var frames: int = int(_provider_script.DESPAWN_MAX_FRAMES) \
		+ int(_provider_script.REFILL_FRAMES) * 4
	for frame: int in frames:
		provider.advance_frame()
		var entries: Array = provider.encounters()
		out["timers"] = bool(out["timers"]) and _timers_sound(entries)
		out["cap_held"] = bool(out["cap_held"]) and entries.size() <= POPULATION
		var now: Dictionary = {}
		for entry: Dictionary in entries:
			now[entry["id"]] = live.get(entry["id"], frame)
		_count_departures(live, now, frame, out)
		_count_arrivals(live, now, seen, out)
		live = now
	var lifetimes: Array = out["lifetimes"]
	out["shortest"] = lifetimes.min() if not lifetimes.is_empty() else 0
	out["longest"] = lifetimes.max() if not lifetimes.is_empty() else 0
	out["frames"] = frames
	out["live"] = live
	return out


func _count_departures(live: Dictionary, now: Dictionary, frame: int, out: Dictionary) -> void:
	for id: Variant in live:
		if now.has(id):
			continue
		out["left"] = int(out["left"]) + 1
		(out["lifetimes"] as Array).append(frame - int(live[id]))


func _count_arrivals(live: Dictionary, now: Dictionary, seen: Dictionary, out: Dictionary) -> void:
	for id: Variant in now:
		if live.has(id):
			continue
		out["arrived"] = int(out["arrived"]) + 1
		out["ids_unique"] = bool(out["ids_unique"]) and not seen.has(id)
		seen[id] = true


func _shiny_id(entries: Array) -> StringName:
	for entry: Dictionary in entries:
		if _plan.is_shiny(int(entry["dvs"])):
			return StringName(entry["id"])
	return &""


## A shiny carries no countdown and an ordinary Pokemon carries one.
func _timers_sound(entries: Array) -> bool:
	for entry: Dictionary in entries:
		if _plan.is_shiny(int(entry["dvs"])) == entry.has(_provider_script.DESPAWN_AT):
			return false
	return true


func _battle_refills(provider: RefCounted, shiny_id: StringName) -> int:
	var fought: StringName = &""
	var standing: Array = provider.encounters()
	for entry: Dictionary in standing:
		if StringName(entry["id"]) != shiny_id:
			fought = StringName(entry["id"])
			break
	var before: int = standing.size()
	provider.battle_finished(fought, {})
	var emptied: bool = (provider.encounters() as Array).size() == before - 1
	for _frame: int in int(_provider_script.REFILL_FRAMES) * 3:
		provider.advance_frame()
	var after: Array = provider.encounters()
	var gone: bool = true
	for entry: Dictionary in after:
		gone = gone and StringName(entry["id"]) != fought
	return _report("a fought Pokemon frees its slot and is replaced",
		emptied and gone and after.size() == before)


func _a_glowing_map(context: Dictionary) -> int:
	for attempt: int in SHINY_SEED_ATTEMPTS:
		for entry: Dictionary in _plan.build(context, attempt + 1, POPULATION):
			if _plan.is_excellent(int(entry["dvs"])):
				return attempt + 1
	return 1


func _a_shiny_map(context: Dictionary) -> int:
	for attempt: int in SHINY_SEED_ATTEMPTS:
		for entry: Dictionary in _plan.build(context, attempt + 1, POPULATION):
			if _plan.is_shiny(int(entry["dvs"])):
				return attempt + 1
	return 1


func _glowing(context: Dictionary) -> int:
	var settings: Dictionary = context.duplicate(true)
	settings["generation"] = 9
	settings["run_seed"] = _a_glowing_map(settings)
	var provider: RefCounted = _provider_script.new()
	provider.set_context(settings)
	var rungs: Dictionary = {}
	var only_excellent: bool = true
	for _frame: int in int(_provider_script.GLOW_PERIOD_FRAMES):
		provider.advance_frame()
		for entry: Dictionary in provider.encounters():
			if not entry.has("glow"):
				continue
			only_excellent = only_excellent and _plan.is_excellent(int(entry.get("dvs", 0)))
			var landed: Dictionary = Gen2WorldEncounters._glow(entry["glow"])
			rungs[landed.get("amount", 0.0)] = true
	return _report("a glow reaches only an excellent Pokemon, on %d rungs" % rungs.size(),
			only_excellent and rungs.size() in range(1, Gen2WorldEncounters.GLOW_RUNGS + 2))


func _spread(context: Dictionary) -> int:
	var cells: PackedVector2Array = (context["eligible"] as Dictionary)[&"grass"]
	var octiles: Array[int] = []
	octiles.resize(SPREAD_OCTILES)
	octiles.fill(0)
	if cells.size() < SPREAD_OCTILES:
		return _report("the map has %d grass cells, too few to measure" % cells.size(), false)
	var at: Dictionary = {}
	for index: int in cells.size():
		at[cells[index]] = index
	for run: int in SPREAD_RUNS:
		for entry: Dictionary in _plan.build(context, DEFAULT_SEED + run, 16):
			var index: int = int(at.get(Vector2(entry["cell"]), -1))
			if index >= 0:
				octiles[mini(index * SPREAD_OCTILES / cells.size(), SPREAD_OCTILES - 1)] += 1
	var busiest: int = octiles.max()
	var quietest: int = octiles.min()
	return _report("%d seeds by eighth of the map: %s, evenly spread" % [
		SPREAD_RUNS, str(octiles),
	], quietest > 0 and float(busiest) / float(quietest) <= SPREAD_RATIO)


## Every slot the host offers carries its own chance, and a population draws
## each species and level in that share: the whole of what the cartridge's
## slot roll decides, on either generation's table.
func _shares(context: Dictionary) -> int:
	var table: Dictionary = (context["tables"] as Dictionary).get(&"grass", {})
	var slots: Array = table.get("slots", [])
	var expected: Dictionary = {}
	var total: int = 0
	var carried: bool = not slots.is_empty()
	for slot: Dictionary in slots:
		var chance: int = int(slot.get("chance", 0))
		carried = carried and chance > 0
		var key: Array = [int(slot["species"]), int(slot["min_level"])]
		expected[key] = int(expected.get(key, 0)) + chance
		total += chance
	var drawn: Dictionary = {}
	var draws: int = 0
	var grass: Dictionary = context.duplicate(true)
	grass["eligible"] = {&"grass": (context["eligible"] as Dictionary)[&"grass"]}
	for run: int in SHARE_RUNS:
		for entry: Dictionary in _plan.build(grass, DEFAULT_SEED + run, 16):
			var key: Array = [int(entry["species"]), int(entry["level"])]
			drawn[key] = int(drawn.get(key, 0)) + 1
			draws += 1
	var worst: float = 0.0
	for key: Array in expected:
		var share: float = float(expected[key]) / float(maxi(total, 1))
		var seen: float = float(drawn.get(key, 0)) / float(maxi(draws, 1))
		worst = maxf(worst, absf(share - seen))
	return _report("%d slots each carry a chance, summing to %d" % [slots.size(), total],
			carried) \
		+ _report("%d draws follow the chances, %d species and levels within %.3f" % [
			draws, expected.size(), worst,
		], carried and draws > 0 and worst <= SHARE_TOLERANCE)


## A shiny the mod sends with `pulse` is announced by the host on this cartridge:
## the sparkle's sprites or its sound, within a few frames of standing.
func _announced(world: Gen2WorldAPI, context: Dictionary) -> int:
	var slots: Array = ((context["tables"] as Dictionary).get(&"grass", {}) as Dictionary) \
		.get("slots", [])
	var cells: PackedVector2Array = (context["eligible"] as Dictionary)[&"grass"]
	if slots.is_empty() or cells.is_empty():
		return _report("the map offers a grass Pokemon to announce", false)
	var capture := Capture.new()
	capture.entries = [{
		"id": &"probe:shiny", "cell": Vector2i(cells[0]),
		"species": int(slots[0]["species"]), "level": int(slots[0]["min_level"]),
		"dvs": SHINY_DVS, "pulse": true,
	}]
	var encounters := Gen2WorldEncounters.new()
	encounters.set_providers([capture])
	encounters.set_world(world, Gen2BattleAnimData.from_game_data(world.data))
	var sprites: int = 0
	var sounds: int = 0
	for _frame: int in ANNOUNCE_FRAMES:
		encounters.advance_frame()
		sprites += encounters.pulse_sprites().size()
		sounds += encounters.frame_commands().size()
	return _report("a shiny stands: %d entries" % encounters.entries().size(),
			encounters.entries().size() == 1) \
		+ _report("and is announced within %d frames: %d sprites, %d commands" % [
			ANNOUNCE_FRAMES, sprites, sounds,
		], sprites > 0 or sounds > 0)


func _taken(context: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for cells: PackedVector2Array in (context["eligible"] as Dictionary).values():
		for index: int in cells.size():
			if index % 4 == 0:
				out.append(cells[index])
	return out


func _clear_of(entries: Array, taken: PackedVector2Array) -> bool:
	for entry: Dictionary in entries:
		if taken.has(Vector2(entry["cell"])):
			return false
	return true


## The first map with a grass table, stood up as the game would.
func _first_world(data: GameData) -> Gen2WorldAPI:
	for map: Gen2WorldMap in data.world_maps():
		if data.world_encounter(&"grass", map.group, map.number).is_empty():
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset != null:
			return Gen2WorldAPI.new(data, map, tileset)
	return null


## The context the host builds for a provider, taken through the seam itself.
func _host_context(world: Gen2WorldAPI) -> Dictionary:
	var capture := Capture.new()
	var encounters := Gen2WorldEncounters.new()
	encounters.set_providers([capture])
	encounters.set_world(world)
	return capture.context


func _eligible_count(context: Dictionary) -> int:
	var count: int = 0
	for cells: PackedVector2Array in (context["eligible"] as Dictionary).values():
		count += cells.size()
	return count
