extends SceneTree

## Builds visible populations from real cartridge encounter tables and PRINTS
## them. One seed twice must be byte-identical and two seeds must differ.

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
	var root: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var plan: GDScript = load(root.path_join("mods/overworld_encounters/plan.gd"))
	var provider_script: GDScript = load(root.path_join("mods/overworld_encounters/provider.gd"))
	var rng: GDScript = load(root.path_join("mods/overworld_encounters/rng.gd"))
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
	for entry: Dictionary in first:
		print("  id %s cell %s species %d level %d dvs %04x%s" % [
			String(entry["id"]), entry["cell"], int(entry["species"]), int(entry["level"]),
			int(entry["dvs"]), " shiny" if plan.is_shiny(int(entry["dvs"])) else "",
		])
	quit(0 if first_text == again_text and first_text != other_text \
		and before_pose == after_pose else 1)


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
