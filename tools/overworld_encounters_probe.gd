extends SceneTree

## Builds visible populations from real cartridge encounter tables and PRINTS
## them. One seed twice must be byte-identical, two seeds must differ, nobody
## may stand where an object is, the placement must be spread over the map
## rather than gathered at one end of it, and no Pokemon may ever wear both the
## shiny mark and the excellent-DV glow.
##
##   Godot --headless --path <pokerecomp> -s tools/overworld_encounters_probe.gd \
##       -- "user://rom_cache/crystal_f2f52230" [seed] [other seed]

const DEFAULT_SEED: int = 1234
const OTHER_SEED: int = 5678
## How many moves to walk the population through when testing the refusal.
const ROAM_STEPS: int = 40
## The spread check: how many seeds it builds, and how far the busiest eighth of
## the candidate list may stand above the quietest before the placement is
## called clustered. A population that favours one end of the collision walk is
## a population standing in one patch of grass, which is what a weak generator
## did here once: see `mods/overworld_encounters/rng.gd`.
const SPREAD_RUNS: int = 200
const SPREAD_OCTILES: int = 8
const SPREAD_RATIO: float = 1.5
## Every DV word there is. The two marks are decided from this one number, so
## the claim that they cannot be worn at once is settled by reading all of them
## rather than by sampling.
const DV_WORDS: int = 0x10000


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
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var plan: GDScript = load(repo.path_join("mods/overworld_encounters/plan.gd"))
	var provider_script: GDScript = load(repo.path_join("mods/overworld_encounters/provider.gd"))
	var rng: GDScript = load(repo.path_join("mods/overworld_encounters/rng.gd"))
	var map: Gen2WorldMap = _first_map(data)
	if plan == null or provider_script == null or rng == null or map == null:
		print("no encounter plan or cartridge map")
		quit(1)
		return
	var context: Dictionary = _context(data, map)
	var seed_value: int = int(args[1]) if args.size() > 1 else DEFAULT_SEED
	var other_seed: int = int(args[2]) if args.size() > 2 else OTHER_SEED
	var first: Array = plan.build(context, seed_value, 6)
	var again: Array = plan.build(context, seed_value, 6)
	var elsewhere: Array = plan.build(context, other_seed, 6)
	var first_text: String = JSON.stringify(first)
	var again_text: String = JSON.stringify(again)
	var other_text: String = JSON.stringify(elsewhere)
	context["run_seed"] = seed_value
	var provider: RefCounted = provider_script.new()
	provider.set_context(context)
	var before_pose: String = JSON.stringify(provider.encounters())
	var moved: Dictionary = context.duplicate(true)
	moved["player"] = {"cell": Vector2i(1, 1), "facing": 2}
	provider.set_context(moved)
	var after_pose: String = JSON.stringify(provider.encounters())
	# NOBODY STANDS ON AN NPC. `occupied` is the host's answer and the refusal is
	# this mod's, on spawn and on every move, so both are walked here: the
	# population is rebuilt on a context that holds the taken cells, then roamed
	# for as many moves as the map has room for.
	var taken: PackedVector2Array = _taken(context)
	var busy: Dictionary = context.duplicate(true)
	busy["occupied"] = taken
	busy["generation"] = 2
	var crowd: RefCounted = provider_script.new()
	crowd.set_context(busy)
	var clear_spawn: bool = _clear_of(crowd.encounters(), taken)
	var clear_roam: bool = true
	for step: int in ROAM_STEPS * int(provider_script.MOVE_FRAMES):
		crowd.advance_frame()
		if not _clear_of(crowd.encounters(), taken):
			clear_roam = false
			break
	print("map %d,%d: %d eligible cells, %d visible" % [
		map.group, map.number, _eligible_count(context), first.size(),
	])
	print("seed %d digest %08x, built twice %08x" % [
		seed_value, rng.text_hash(first_text), rng.text_hash(again_text),
	])
	print("seed %d digest %08x" % [other_seed, rng.text_hash(other_text)])
	print("one seed twice is byte-identical: %s" % ("yes" if first_text == again_text else "NO"))
	print("two seeds differ: %s" % ("yes" if first_text != other_text else "NO"))
	print("pose refresh preserves the population: %s" % (
		"yes" if before_pose == after_pose else "NO"
	))
	print("%d cells taken by an object: spawns clear %s, %d moves clear %s" % [
		taken.size(), "yes" if clear_spawn else "NO",
		ROAM_STEPS, "yes" if clear_roam else "NO",
	])
	# NO POKEMON WEARS BOTH MARKS. Every DV word is read, so this is the claim
	# settled rather than sampled, and the provider is walked a whole cycle to
	# prove it puts a glow on nobody else and stays on its own rungs.
	var glow: Dictionary = _glow_survey(plan, provider_script, crowd)
	var octiles: Array[int] = _octiles(plan, context)
	var busiest: int = octiles.max()
	var quietest: int = maxi(octiles.min(), 1)
	var spread: bool = float(busiest) / float(quietest) <= SPREAD_RATIO
	print("%d seeds by eighth of the map: %s, evenly spread %s" % [
		SPREAD_RUNS, str(octiles), "yes" if spread else "NO",
	])
	print("%d DV words: %d shiny, %d excellent, both %d" % [
		DV_WORDS, glow["shiny"], glow["excellent"], glow["both"],
	])
	print("a glow reaches only an excellent Pokemon: %s, on %d rungs: %s" % [
		"yes" if bool(glow["only_excellent"]) else "NO",
		glow["rungs"],
		"yes" if int(glow["rungs"]) <= Gen2WorldEncounters.GLOW_RUNGS + 1 else "NO",
	])
	for entry: Dictionary in first:
		print("  id %s cell %s species %d level %d dvs %04x%s" % [
			String(entry["id"]), entry["cell"], int(entry["species"]), int(entry["level"]),
			int(entry["dvs"]), " shiny" if plan.is_shiny(int(entry["dvs"])) else "",
		])
	quit(0 if first_text == again_text and first_text != other_text \
		and before_pose == after_pose and clear_spawn and clear_roam and spread \
		and int(glow["both"]) == 0 and bool(glow["only_excellent"]) \
		and int(glow["rungs"]) <= Gen2WorldEncounters.GLOW_RUNGS + 1 else 1)


## The two marks over every DV word there is, and one whole glow cycle out of a
## live provider: who it reaches, and how many distinct strengths it spends.
func _glow_survey(
	plan: GDScript, provider_script: GDScript, provider: RefCounted
) -> Dictionary:
	var out: Dictionary = {"shiny": 0, "excellent": 0, "both": 0}
	for dvs: int in DV_WORDS:
		var shiny: bool = plan.is_shiny(dvs)
		var excellent: bool = plan.is_excellent(dvs)
		out["shiny"] = int(out["shiny"]) + (1 if shiny else 0)
		out["excellent"] = int(out["excellent"]) + (1 if excellent else 0)
		out["both"] = int(out["both"]) + (1 if shiny and excellent else 0)
	var rungs: Dictionary = {}
	var only_excellent: bool = true
	for frame: int in int(provider_script.GLOW_PERIOD_FRAMES):
		provider.advance_frame()
		for entry: Dictionary in provider.encounters():
			if not entry.has("glow"):
				continue
			if not plan.is_excellent(int(entry.get("dvs", 0))):
				only_excellent = false
			# THROUGH THE HOST'S OWN ROUNDING, not the raw amount the mod sends:
			# what bounds the textures a glow spends is `_glow`, so that is what
			# the count has to be taken over.
			var landed: Dictionary = Gen2WorldEncounters._glow(entry["glow"])
			rungs[landed.get("amount", 0.0)] = true
	out["only_excellent"] = only_excellent
	out["rungs"] = rungs.size()
	return out


## Where the picks land inside the candidate list, in eighths. The list is the
## collision walk in map order, so an eighth of it is a band of the map and a
## histogram of it is what clustering shows up in.
func _octiles(plan: GDScript, context: Dictionary) -> Array[int]:
	var cells: PackedVector2Array = (context["eligible"] as Dictionary)[&"grass"]
	var out: Array[int] = []
	out.resize(SPREAD_OCTILES)
	out.fill(0)
	if cells.size() < SPREAD_OCTILES:
		return out
	var at: Dictionary = {}
	for index: int in cells.size():
		at[cells[index]] = index
	for run: int in SPREAD_RUNS:
		for entry: Dictionary in plan.build(context, DEFAULT_SEED + run, 16):
			var index: int = int(at.get(Vector2(entry["cell"]), -1))
			if index >= 0:
				out[mini(index * SPREAD_OCTILES / cells.size(), SPREAD_OCTILES - 1)] += 1
	return out


## Cells an object is standing on, made out of the eligible list so the refusal
## is tested against cells a wild would otherwise be put on. A quarter of them,
## since taking all of them leaves nowhere to stand and proves nothing.
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


func _first_map(data: GameData) -> Gen2WorldMap:
	for map: Gen2WorldMap in data.world_maps():
		if not data.world_encounter(&"grass", map.group, map.number).is_empty():
			return map
	return null


func _context(data: GameData, map: Gen2WorldMap) -> Dictionary:
	var row: Dictionary = data.world_encounter(&"grass", map.group, map.number)
	var times: Array = row.get("slots", [])
	var slots: Array = times[1] if times.size() > 1 else (times[0] if not times.is_empty() else [])
	var cells := PackedVector2Array()
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			var code: int = map.collision_at(x, y)
			var cave: bool = map.environment in [
				Gen2WorldAPI.ENVIRONMENT_CAVE, Gen2WorldAPI.ENVIRONMENT_DUNGEON,
			]
			if (cave or Gen2WorldCollision.gates_encounter(code)) \
				and not Gen2WorldCollision.is_ice(code) \
				and Gen2WorldCollision.permission_for(code) == Gen2WorldCollision.LAND_TILE:
				cells.append(Vector2i(x, y))
	var resolved_slots: Array = []
	for slot: Dictionary in slots:
		var level: int = int(slot.get("level", 1))
		resolved_slots.append({
			"species": int(slot.get("species", 0)),
			"min_level": level,
			"max_level": level,
		})
	return {
		"map": Vector2i(map.group, map.number), "generation": 1,
		"eligible": {&"grass": cells},
		"tables": {&"grass": {"source": &"grass", "slots": resolved_slots}},
		"player": {"cell": Vector2i(-1, -1), "facing": 0},
		"run_seed": DEFAULT_SEED,
	}


func _eligible_count(context: Dictionary) -> int:
	var count: int = 0
	for cells: PackedVector2Array in (context["eligible"] as Dictionary).values():
		count += cells.size()
	return count
