extends SceneTree

## Walks a route past the follower against a real cartridge cache and PRINTS
## where it stood, without a game running.

const STEP_FRAMES: int = 8

const HOME: Vector2i = Vector2i(24, 3)
const AWAY: Vector2i = Vector2i(24, 4)

const ROUTE: Array = ["right", "right", "down", "down", "left", "warp", "down"]
const OTHER_ROUTE: Array = ["down", "left", "left", "up", "right", "right"]

const DIRECTIONS: Dictionary = {
	"up": Vector2i.UP, "down": Vector2i.DOWN,
	"left": Vector2i.LEFT, "right": Vector2i.RIGHT,
}
const FACINGS: Dictionary = {
	"up": Gen2WorldSprite.FACING_UP, "down": Gen2WorldSprite.FACING_DOWN,
	"left": Gen2WorldSprite.FACING_LEFT, "right": Gen2WorldSprite.FACING_RIGHT,
}

const PARTY: Array[int] = [155, 172, 25, 249]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cache directory>")
		quit(2)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at %s" % args[0])
		quit(1)
		return

	var mod: String = (get_script() as Script).resource_path.get_base_dir() \
		.get_base_dir().path_join("mods/follower")
	var trail_script: GDScript = load("%s/trail.gd" % mod)
	var party: GDScript = load("%s/party.gd" % mod)
	var finder: GDScript = load("%s/finder.gd" % mod)
	var actor_script: GDScript = load("%s/actor.gd" % mod)
	var options: GDScript = load("%s/options.gd" % mod)
	if trail_script == null or party == null or finder == null \
		or actor_script == null or options == null:
		print("no mod scripts under %s" % mod)
		quit(1)
		return

	print("cartridge  %s" % data.id)
	var summary: Dictionary = _summary()
	var failures: int = 0
	failures += _report_party(party, data, summary)

	var walked: String = _walk(trail_script, ROUTE, true)
	var again: String = _walk(trail_script, ROUTE, false)
	var elsewhere: String = _walk(trail_script, OTHER_ROUTE, false)
	print("route      %s" % ", ".join(ROUTE))
	print("           %d frames, digest %s" % [walked.split("\n").size(), walked.md5_text()])
	print("walked again  digest %s" % again.md5_text())
	print("other route   digest %s" % elsewhere.md5_text())
	failures += 0 if _report("one route twice is one walk", walked == again) else 1
	failures += 0 if _report("two routes are two walks", walked != elsewhere) else 1
	failures += _rules(trail_script)
	failures += _petting(trail_script)
	failures += _finding(finder)
	failures += _picking_up(actor_script, options, data)
	quit(1 if failures > 0 else 0)


func _summary() -> Dictionary:
	var species: Array[int] = PARTY.duplicate()
	return {
		"count": species.size(), "species": species,
		"eggs": [false, true, false, false],
		"fainted": [false, false, false, false],
		"names": ["CYNDA", "EGG", "PIKA", "LUGIA"],
		"lead_fainted": false,
	}


func _report_party(party: GDScript, data: GameData, summary: Dictionary) -> int:
	var failures: int = 0
	for slot: int in range(1, (summary["species"] as Array).size() + 1):
		var member: Dictionary = party.member(summary, data, slot)
		var number: int = int((summary["species"] as Array)[slot - 1])
		var name: String = String(data.species(number).get("name", "?"))
		if bool(member["out"]):
			print("slot %d     %-10s species %3d, icon %d" % [
				slot, name, number, int(member["icon"]),
			])
		else:
			print("slot %d     %-10s stays in its ball: %s" % [
				slot, name, String(member["reason"]),
			])
	failures += 0 if _report(
		"an egg does not walk", not bool(party.member(summary, data, 2)["out"])
	) else 1
	var fainted: Dictionary = summary.duplicate(true)
	(fainted["fainted"] as Array)[0] = true
	failures += 0 if _report(
		"a fainted lead does not walk", not bool(party.member(fainted, data, 1)["out"])
	) else 1
	var legacy_fainted: Dictionary = summary.duplicate(true)
	legacy_fainted.erase("fainted")
	legacy_fainted["lead_fainted"] = true
	failures += 0 if _report(
		"an API 1 fainted lead does not walk",
		not bool(party.member(legacy_fainted, data, 1)["out"])
	) else 1
	var fainted_nonlead: Dictionary = summary.duplicate(true)
	(fainted_nonlead["fainted"] as Array)[2] = true
	failures += 0 if _report(
		"a fainted non-lead does not walk",
		not bool(party.member(fainted_nonlead, data, 3)["out"])
	) else 1
	var empty: Dictionary = summary.duplicate(true)
	empty["species"] = [] as Array[int]
	failures += 0 if _report(
		"an empty party sends nobody", not bool(party.member(empty, data, 1)["out"])
	) else 1
	return failures


func _walk(trail_script: GDScript, route: Array, verbose: bool) -> String:
	var trail: RefCounted = trail_script.new()
	var lines: PackedStringArray = PackedStringArray()
	for observation: Dictionary in _observations(route):
		var pose: Dictionary = trail.observe(observation)
		var line: String = "%s player %s%s  follower %s" % [
			_map_text(observation["map"]),
			_at(observation["cell"], observation["offset"]),
			"" if bool(pose["out"]) else "  (in its ball)",
			_at(pose["cell"], pose["offset"]),
		]
		lines.append(line)
		if verbose:
			print("  %s" % line)
	return "\n".join(lines)


func _observations(route: Array) -> Array:
	var out: Array = []
	var map: Vector2i = HOME
	var cell: Vector2i = Vector2i(5, 5)
	var facing: int = Gen2WorldSprite.FACING_DOWN
	out.append(_observation(map, cell, facing, Vector2.ZERO))
	for command: String in route:
		if command == "warp":
			map = AWAY if map == HOME else HOME
			cell = Vector2i(2, 8)
			out.append(_observation(map, cell, facing, Vector2.ZERO))
			continue
		var direction: Vector2i = DIRECTIONS[command]
		facing = int(FACINGS[command])
		cell += direction
		for frame: int in STEP_FRAMES:
			var left: float = float(STEP_FRAMES - 1 - frame) / float(STEP_FRAMES)
			out.append(_observation(map, cell, facing, -Vector2(direction) * left))
	return out


func _observation(map: Vector2i, cell: Vector2i, facing: int, offset: Vector2) -> Dictionary:
	return {"map": map, "cell": cell, "facing": facing, "offset": offset, "allowed": true}


func _rules(trail_script: GDScript) -> int:
	var failures: int = 0
	for route: Array in [ROUTE, OTHER_ROUTE]:
		var trail: RefCounted = trail_script.new()
		var behind: bool = true
		var close: bool = true
		var apart: bool = true
		var cardinal: bool = true
		var previous_cell: Vector2i = Vector2i.ZERO
		var player_before: Vector2i = Vector2i.ZERO
		var previous_player: Vector2i = Vector2i.ZERO
		var previous_map: Vector2i = Vector2i(-1, -1)
		for observation: Dictionary in _observations(route):
			var pose: Dictionary = trail.observe(observation)
			var cell: Vector2i = pose["cell"]
			var player: Vector2i = observation["cell"]
			var same_map: bool = previous_map == observation["map"]
			if player != previous_player:
				player_before = previous_player
				previous_player = player
			if same_map:
				var moved: Vector2i = cell - previous_cell
				if moved != Vector2i.ZERO and absi(moved.x) + absi(moved.y) != 1:
					cardinal = false
			if bool(pose["out"]):
				if cell == player:
					apart = false
				if same_map and cell != player_before:
					behind = false
				var distance: float = (
					Vector2(player) + (observation["offset"] as Vector2)
					- Vector2(cell) - (pose["offset"] as Vector2)
				).length()
				if distance > 1.0001:
					close = false
			previous_cell = cell
			previous_map = observation["map"]
		for check: Array in [
			["the follower steps one cell at a time", cardinal],
			["the follower is never under the player", apart],
			["the follower is never more than a cell away", close],
			["the follower stands where the player just stood", behind],
		]:
			if not _report("%s (%s)" % [check[0], ", ".join(route)], bool(check[1])):
				failures += 1
	return failures


func _map_text(map: Vector2i) -> String:
	return "map %d,%-3d" % [map.x, map.y]


func _at(cell: Vector2i, offset: Vector2) -> String:
	return "%2d,%-2d %+0.2f,%+0.2f" % [cell.x, cell.y, offset.x, offset.y]


func _report(what: String, passed: bool) -> bool:
	print("%s  %s" % ["ok  " if passed else "FAIL", what])
	return passed


func _petting(trail_script: GDScript) -> int:
	var failures: int = 0
	for pair: Array in [
		["down", Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_UP],
		["up", Gen2WorldSprite.FACING_UP, Gen2WorldSprite.FACING_DOWN],
		["left", Gen2WorldSprite.FACING_LEFT, Gen2WorldSprite.FACING_RIGHT],
		["right", Gen2WorldSprite.FACING_RIGHT, Gen2WorldSprite.FACING_LEFT],
	]:
		var trail: RefCounted = trail_script.new()
		var before: Dictionary = {}
		for observation: Dictionary in _observations(["right", "right"]):
			before = trail.observe(observation)
		trail.face_back(int(pair[1]))
		if not _report(
			"petted while the player looks %s, it looks back" % pair[0],
			trail.facing() == int(pair[2])
		):
			failures += 1
		var after: Dictionary = trail.observe(_observation(
			HOME, (before["cell"] as Vector2i) + Vector2i.RIGHT,
			Gen2WorldSprite.FACING_RIGHT, Vector2.ZERO
		))
		if not _report(
			"petting moves nothing but the facing (%s)" % pair[0],
			(after["cell"] as Vector2i) == (before["cell"] as Vector2i)
		):
			failures += 1
	return failures


func _finding(finder: GDScript) -> int:
	var here: Vector2i = Vector2i(10, 10)
	var wall: Vector2i = here + Vector2i.LEFT
	var open_floor: Vector2i = here + Vector2i.RIGHT
	var walkable: Callable = func(cell: Vector2i, _direction: Vector2i) -> bool:
		return cell != wall
	var under: Dictionary = _record(here, 1)
	var behind: Dictionary = _record(wall, 2)
	var beside: Dictionary = _record(open_floor, 3)
	var taken: Dictionary = _record(here, 4)
	taken["taken"] = true
	var checks: Array = [
		["it takes what it is standing on", [under, behind], 1],
		["it reaches into what it could not walk into", [behind], 2],
		["it leaves what it could have walked over itself", [beside], 0],
		["its own cell comes before the one beside it", [behind, under], 1],
		["a taken record is not asked for twice", [taken], 0],
		["an empty map reaches nothing", [], 0],
	]
	var failures: int = 0
	for check: Array in checks:
		var answer: Dictionary = finder.reach(check[1], here, walkable)
		var item: int = 0 if answer.is_empty() else int(answer["item"])
		if not _report("%s (item %d)" % [check[0], item], item == int(check[2])):
			failures += 1
	var far: Dictionary = finder.reach(
		[_record(here + Vector2i.LEFT * 2, 5)], here, walkable
	)
	failures += 0 if _report("it reaches exactly one cell", far.is_empty()) else 1
	return failures


func _record(cell: Vector2i, item: int) -> Dictionary:
	return {"cell": cell, "item": item, "flag": item, "taken": false}


func _picking_up(actor_script: GDScript, options: GDScript, data: GameData) -> int:
	var site: Dictionary = _a_hidden_item(data)
	if site.is_empty():
		_report("a map carrying a hidden item was found", false)
		return 1
	var world: Gen2WorldAPI = site["world"]
	var cell: Vector2i = site["cell"]
	print("hidden     map %d,%-3d cell %s item %d (%s)" % [
		world.current_map.group, world.current_map.number, str(cell), int(site["item"]),
		String(data.item(int(site["item"])).get("name", "?")),
	])

	var host: Gen2ModHost = Gen2ModHost.instance()
	options.register(host, options.MOD_ID)
	world.set_party_summary(1, false, PARTY.slice(0, 1), [], ["CYNDA"], [false], {}, [false])
	var actor: RefCounted = actor_script.new()
	actor.configure(host, options.MOD_ID)
	actor.set_world(world)

	var failures: int = 0
	host.set_option(options.MOD_ID, options.PICKUP, 0)
	failures += 0 if _report(
		"off, it asks for nothing", _walk_onto(actor, world, cell, host).is_empty()
	) else 1

	host.set_option(options.MOD_ID, options.PICKUP, 1)
	var asked: Array = _walk_onto(actor, world, cell, host)
	failures += 0 if _report(
		"on, it asks for the cell it stands on (%s)" % str(asked), asked == [cell]
	) else 1

	for _frame: int in 120:
		actor.advance_frame()
	failures += 0 if _report(
		"standing on it, it asks once", host.take_hidden_item_requests().is_empty()
	) else 1
	var returned: Array = _walk_onto(actor, world, cell, host)
	failures += 0 if _report(
		"walking on again, it asks again (%s)" % str(returned), returned == [cell]
	) else 1

	var before: int = world.inventory.item_quantity(int(site["item"]))
	var results: Array = world.take_hidden_item(cell)
	for _press: int in 64:
		if not world.script_busy():
			break
		world.finish_script_waits()
		world.run_event_queue(true)
	var after: int = world.inventory.item_quantity(int(site["item"]))
	failures += 0 if _report(
		"the host runs the map's own script", not results.is_empty()
	) else 1
	failures += 0 if _report(
		"the site's flag is set", world.event_flag_active(int(site["flag"]))
	) else 1
	failures += 0 if _report(
		"the item is in the bag (%d -> %d)" % [before, after], after > before
	) else 1
	failures += 0 if _report(
		"a taken site is not offered again", _is_taken(world.hidden_items(), cell)
	) else 1
	return failures


func _walk_onto(
	actor: RefCounted, world: Gen2WorldAPI, cell: Vector2i, host: Gen2ModHost
) -> Array:
	host.take_hidden_item_requests()
	world.player_cell = cell
	actor.advance_frame()
	for direction: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		if not world.can_walk_to(cell + direction, direction):
			continue
		world.move(direction)
		while world.player_step_in_progress():
			world.advance_player_step_pass()
			actor.advance_frame()
		actor.advance_frame()
		break
	return host.take_hidden_item_requests()


func _a_hidden_item(data: GameData) -> Dictionary:
	for group: int in range(1, 27):
		for number: int in range(1, 40):
			var map: Gen2WorldMap = data.world_map(group, number)
			if map == null:
				continue
			var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
			if tileset == null:
				continue
			var world := Gen2WorldAPI.new(data, map, tileset)
			for record: Dictionary in world.hidden_items():
				if bool(record["taken"]):
					continue
				return {
					"world": world, "cell": record["cell"],
					"item": record["item"], "flag": record["flag"],
				}
	return {}


func _is_taken(records: Array, cell: Vector2i) -> bool:
	for record: Dictionary in records:
		if (record["cell"] as Vector2i) == cell:
			return bool(record["taken"])
	return false
