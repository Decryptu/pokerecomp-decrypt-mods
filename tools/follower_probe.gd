extends SceneTree

## Walks a route past the follower against a real cartridge cache and PRINTS
## where it stood, without a game running.
##
## Two things are being shown. The first is that the follower is a pure function
## of what the player did: one route walked twice has to produce the same poses
## byte for byte, and a different route has to produce different ones. The
## second is that the species walking behind the player is the cartridge's own:
## the icon row each one is drawn from is read out of the cache and printed
## beside its name, which is the only art this mod ever names.
##
##   Godot --headless --path <pokerecomp> -s tools/follower_probe.gd -- \
##       "user://rom_cache/crystal_f2f52230"

## Frames one plain overworld step is drawn over, which is the host's own
## STEP_FRAMES_NORMAL. The count changes nothing here: the follower reads the
## player's fraction rather than counting frames, and the probe walks whatever
## it is handed.
const STEP_FRAMES: int = 8

const HOME: Vector2i = Vector2i(24, 3)
const AWAY: Vector2i = Vector2i(24, 4)

## Two routes: a straight run with two corners in it, and one that doubles back.
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

## A party the probe drives the reader with: a starter, an egg in the second
## slot and a species from the middle of the table. Species numbers, so the
## cartridge answers what they are called and what they are drawn as.
const PARTY: Array[int] = [155, 172, 25, 249]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <cache directory>")
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
		.get_base_dir().path_join("mods/follower")
	var trail_script: GDScript = load("%s/trail.gd" % mod)
	var party: GDScript = load("%s/party.gd" % mod)
	if trail_script == null or party == null:
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
	quit(1 if failures > 0 else 0)


## What the world screen mirrors out of a save: the second slot is an egg and
## the lead is on its feet.
func _summary() -> Dictionary:
	var species: Array[int] = PARTY.duplicate()
	return {
		"count": species.size(), "species": species,
		"eggs": [false, true, false, false],
		"fainted": [false, false, false, false],
		"names": ["CYNDA", "EGG", "PIKA", "LUGIA"],
		"lead_fainted": false,
	}


## Which species is out for each slot, and the icon row it is drawn from. Slot 2
## holds an egg and has to stay in its ball.
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


## The route as one line per frame, which is both what is printed and what is
## digested: a pose that moved a pixel moves a character here.
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


## The route as the frames the world would hand the follower: a step commits its
## cell on its first frame and draws the fraction down to zero, which is what
## `player_step_offset_cells()` answers.
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


## What the follower promises, asked of every frame of both routes rather than
## of a sample.
func _rules(trail_script: GDScript) -> int:
	var failures: int = 0
	for route: Array in [ROUTE, OTHER_ROUTE]:
		var trail: RefCounted = trail_script.new()
		var behind: bool = true
		var close: bool = true
		var apart: bool = true
		var cardinal: bool = true
		var previous_cell: Vector2i = Vector2i.ZERO
		## The cell the player stood on before the step being drawn, which is
		## where the follower is walking to, and the cell they are on now.
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
				# The whole rule, checked rather than described: the follower
				# stands on the cell the player last stood on. Not the cell of
				# the previous FRAME: a step commits its cell on its first frame
				# and is drawn for the rest of them.
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
