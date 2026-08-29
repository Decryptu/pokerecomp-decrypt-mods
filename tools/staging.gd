extends RefCounted

## Staging a run through the game's own screen: the named arguments, the window,
## an open cell to stand on, the mod's renderer node, and the settings a run
## borrows and gives back.

const RENDERER := "user://mods/voxel3d/world/renderer.gd"
const ROOM_CELLS: int = 24
const SEARCH_CELLS: int = 40
const PARTY_LEVEL: int = 5
const PARTY_HP: int = 20

var _restore: Dictionary = {}
var _restore_id: StringName = &""


static func named(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(3, args.size()):
		var pair: String = args[index]
		var at: int = pair.find("=")
		if at <= 0:
			continue
		out[pair.substr(0, at)] = pair.substr(at + 1)
	return out


static func window_size(text: String, fallback: Vector2i) -> Vector2i:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2 or int(parts[0]) <= 0 or int(parts[1]) <= 0:
		return fallback
	return Vector2i(int(parts[0]), int(parts[1]))


static func _spec_value(text: String) -> Variant:
	if text.contains("."):
		return float(text)
	return int(text)


## `static=name:value,...`, the renderer's own static fields.
static func apply_statics(spec: String) -> void:
	var script: GDScript = load(RENDERER)
	if script == null:
		print("no renderer script at %s" % RENDERER)
		return
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var name: String = parts[0].strip_edges()
		var value: Variant = _spec_value(parts[1].strip_edges())
		if script.get(name) is bool:
			value = bool(value)
		script.set(name, value)
		print("static     %s = %s" % [name, str(script.get(name))])


## `set=key:value,...`, the mod's own settings. Held so `restore` gives back what
## the player had.
func apply_options(host: Gen2ModHost, id: StringName, spec: String) -> void:
	for pair: String in spec.split(",", false):
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2:
			continue
		var key := StringName(parts[0].strip_edges())
		var value: Variant = _spec_value(parts[1].strip_edges())
		_restore[key] = host.option(id, key)
		print("option     %s = %s %s" % [
			String(key), str(value), str(host.set_option(id, key, value)),
		])
	_restore_id = id


func restore() -> void:
	if _restore.is_empty():
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	for key: StringName in _restore:
		if _restore[key] != null:
			host.set_option(_restore_id, key, _restore[key])


## `party=155,172,...`, the species a staged run walks around with, which is
## what a mod reading the party needs before it will draw anything. Empty text
## answers null and the screen keeps whatever save it was given.
static func party_save(data: GameData, spec: String) -> Gen2SaveData:
	if data == null or spec.strip_edges().is_empty():
		return null
	var members: Array = []
	for number: String in spec.split(",", false):
		var mon := Gen2SaveMon.new()
		mon.species = int(number.strip_edges())
		mon.level = PARTY_LEVEL
		mon.hp = PARTY_HP
		mon.nickname = String(data.species(mon.species).get("name", ""))
		members.append(mon)
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.player_name = "PROBE"
	save.party = members
	return save


static func find_renderer(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.begins_with("user://mods/") \
			and node.has_method("refresh"):
		return node
	for child: Node in node.get_children():
		var found: Node = find_renderer(child)
		if found != null:
			return found
	return null


## The nearest cell to the one asked for that stands in a room rather than in a
## doorway, or `Vector2i.MAX` where the map has none.
static func open_ground(map: Gen2WorldMap, wanted: Vector2i) -> Vector2i:
	var refused: Dictionary = {}
	for radius: int in SEARCH_CELLS:
		for offset: Vector2i in _ring(radius):
			var cell: Vector2i = wanted + offset
			if refused.has(cell) or not walkable(map, cell):
				continue
			var region: Dictionary = _region(map, cell)
			if region.size() >= ROOM_CELLS:
				return cell
			refused.merge(region)
	return Vector2i.MAX


static func _ring(radius: int) -> Array:
	if radius == 0:
		return [Vector2i.ZERO]
	var out: Array = []
	for step: int in radius * 2 + 1:
		var at: int = step - radius
		out.append(Vector2i(at, -radius))
		out.append(Vector2i(at, radius))
		if absi(at) != radius:
			out.append(Vector2i(-radius, at))
			out.append(Vector2i(radius, at))
	return out


static func _region(map: Gen2WorldMap, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty() and seen.size() < ROOM_CELLS * 4:
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = at + step
			if seen.has(next) or not walkable(map, next):
				continue
			seen[next] = true
			queue.append(next)
	return seen


static func walkable(map: Gen2WorldMap, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.collision_width \
			or cell.y >= map.collision_height:
		return false
	return Gen2WorldCollision.is_walkable(map.collision_at(cell.x, cell.y))
