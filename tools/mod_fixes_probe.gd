extends SceneTree

const FIRST_SEED: int = 1234
const SECOND_SEED: int = 5678


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
	var first_seed: int = int(args[1]) if args.size() > 1 else FIRST_SEED
	var second_seed: int = int(args[2]) if args.size() > 2 else SECOND_SEED
	var ok: bool = _ledge_corner(data)
	ok = _jump_offset() and ok
	ok = _population(data, first_seed, second_seed) and ok
	quit(0 if ok else 1)


func _ledge_corner(data: GameData) -> bool:
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var voxel: String = repo.path_join("mods/voxel3d")
	if data.generation == RomRegistry.GEN1:
		print("ledge corner: Route 29 is a Generation 2 map, skipped")
		return true
	var map: Gen2WorldMap = data.world_map(24, 3)
	if map == null:
		print("ledge map 24,3 missing")
		return false
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
	var shape: RefCounted = (load(voxel.path_join("shape/tile_shape.gd")) as GDScript).new(
		(load(voxel.path_join("shape/profiles.gd")) as GDScript).of(data), tileset.name
	)
	var source: RefCounted = (load(voxel.path_join("shape/map_source.gd")) as GDScript).new(
		null, map, tileset, data
	)
	var mesher: RefCounted = (load(voxel.path_join("shape/mesher.gd")) as GDScript).new()
	mesher.resolve(source, shape)
	var rows: Array[String] = []
	for ty: int in range(17, 21):
		var values: PackedStringArray = PackedStringArray()
		for tx: int in range(15, 20):
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			values.append(str(int(mesher._ledge[at])))
		rows.append(" ".join(values))
	print("map 24,3 ledges around cell 7,8:\n%s" % "\n".join(rows))
	var corner: int = int(mesher._ledge[mesher.grid_index(Vector2i(16, 19))])
	var joined: bool = corner == mesher.LEDGE_WEST | mesher.LEDGE_SOUTH
	print("perpendicular ledges form one corner wedge: %s" % ("yes" if joined else "NO"))
	var model_checked: bool = false
	for ty: int in mesher._map_size.y:
		for tx: int in mesher._map_size.x:
			var at: int = mesher.grid_index(Vector2i(tx, ty))
			if int(mesher._modelled[at]) == 0:
				continue
			var position := Vector3((float(tx) + 0.5) * 8.0, 0.0, (float(ty) + 0.5) * 8.0)
			var column: int = mesher.height_at_position(position)
			var occlusion: int = mesher.occlusion_height_at_position(position)
			model_checked = occlusion > column
			print("stamped model occlusion %d exceeds its column %d: %s" % [
				occlusion, column, "yes" if model_checked else "NO",
			])
			break
		if model_checked:
			break
	return joined and model_checked


func _jump_offset() -> bool:
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var renderer: Node = (load(repo.path_join("mods/voxel3d/world/renderer.gd")) as GDScript).new()
	var ground := Vector3(24.0, 7.0, 40.0)
	var lifted: Vector3 = renderer._actor_position(ground, 8.0)
	var ok: bool = lifted == Vector3(24.0, 15.0, 40.0)
	print("host jump offset lifts the card and leaves its ground at y 7: %s" % (
		"yes" if ok else "NO"
	))
	renderer.free()
	return ok


func _population(data: GameData, first_seed: int, second_seed: int) -> bool:
	var repo: String = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var map: Gen2WorldMap = null
	for candidate: Gen2WorldMap in data.world_maps():
		if not data.world_encounter(&"grass", candidate.group, candidate.number).is_empty():
			map = candidate
			break
	if map == null:
		print("no encounter map")
		return false
	var context: Dictionary = _encounter_context(data, map)
	var plan: GDScript = load(repo.path_join("mods/overworld_encounters/plan.gd"))
	var first_population: Array = plan.build(context, first_seed, 8)
	var first: String = JSON.stringify(first_population)
	var again: String = JSON.stringify(plan.build(context, first_seed, 8))
	var other: String = JSON.stringify(plan.build(context, second_seed, 8))
	print("VISIBLE 8 creates %d entries from %d eligible cells" % [
		first_population.size(), (context["eligible"][&"grass"] as PackedVector2Array).size(),
	])
	print("population seed %d twice is byte-identical: %s" % [
		first_seed, "yes" if first == again else "NO",
	])
	print("population seeds %d and %d differ: %s" % [
		first_seed, second_seed, "yes" if first != other else "NO",
	])
	var provider_script: GDScript = load(repo.path_join("mods/overworld_encounters/provider.gd"))
	context["run_seed"] = first_seed
	var provider: RefCounted = provider_script.new()
	provider.set_context(context)
	var paced: bool = _lead_walks_on_its_beat(provider, provider_script.MOVE_FRAMES)
	print("the lead wild holds %d frames, asks one step and lands on it: %s" % [
		provider_script.MOVE_FRAMES - 1, "yes" if paced else "NO",
	])
	return first == again and first != other and first_population.size() == 8 and paced


## The first entry waits out a whole beat, asks the host for one step to an
## adjacent cell, and stands on that cell the frame after.
func _lead_walks_on_its_beat(provider: RefCounted, beat: int) -> bool:
	var lead: Dictionary = provider.encounters()[0]
	for _frame: int in beat - 1:
		provider.advance_frame()
	var held: Dictionary = provider.encounters()[0]
	provider.advance_frame()
	var asked: Dictionary = provider.encounters()[0]
	provider.advance_frame()
	var landed: Dictionary = provider.encounters()[0]
	var step: Vector2i = asked.get("step", Vector2i.ZERO)
	return held["cell"] == lead["cell"] and not held.has("step") \
		and Gen2WorldEncounters.STEP_DIRECTIONS.has(step) \
		and landed["cell"] == Vector2i(lead["cell"]) + step


## The context the host hands a provider, read off a world opened on the map.
func _encounter_context(data: GameData, map: Gen2WorldMap) -> Dictionary:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, map.group, map.number, Vector2i.ZERO, Gen2WorldState.new()
	)
	return {
		"map": world.map_id(),
		"generation": 1,
		"eligible": world.visible_encounter_cells(),
		"occupied": PackedVector2Array(),
		"tables": world.active_encounter_tables(),
		"player": {"cell": Vector2i(-1, -1), "facing": 0},
	}
