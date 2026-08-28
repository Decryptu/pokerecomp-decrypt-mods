extends SceneTree

## WHETHER THE HORIZON NAMES AND CUTS THE SAME DRAWINGS THE MESH DOES.

const MOD := "user://mods/voxel3d"
const TILE: int = 8


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <cache> [group,number]")
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache at ", args[0])
		quit(1)
		return
	var only := Vector2i(-1, -1)
	if args.size() > 1 and args[1].contains(","):
		var parts: PackedStringArray = args[1].split(",")
		only = Vector2i(int(parts[0]), int(parts[1]))

	var profile: GDScript = load("%s/shape/profile.gd" % MOD)
	var atlas_script: GDScript = load("%s/shape/atlas.gd" % MOD)
	var mesher_script: GDScript = load("%s/shape/mesher.gd" % MOD)
	var shape_script: GDScript = load("%s/shape/tile_shape.gd" % MOD)
	var source_script: GDScript = load("%s/shape/map_source.gd" % MOD)
	var walk_script: GDScript = load("%s/shape/far_drawings.gd" % MOD)

	var maps: int = 0
	var differ: int = 0
	var drawings: int = 0
	var spots: int = 0
	var cut: int = 0
	var houses: int = 0
	var walk_usec: int = 0
	var cut_usec: int = 0
	for map: Gen2WorldMap in data.world_maps():
		if only.x >= 0 and Vector2i(map.group, map.number) != only:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		var source: RefCounted = source_script.new(null, map, tileset, data)
		if not source.outside():
			continue
		var atlas: RefCounted = atlas_script.new()
		if not atlas.build(data, map, tileset, 1):
			continue
		var shape: RefCounted = shape_script.new(profile, map.tileset)
		var mesher: RefCounted = mesher_script.new()
		var cutter: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		mesher.emit(atlas)

		var at: int = Time.get_ticks_usec()
		var walked: Dictionary = walk_script.of_map(
			data, map, profile, mesher.stamped_bounds_tiles()
		)
		walk_usec += Time.get_ticks_usec() - at
		var found: Dictionary = walked["drawings"]
		houses += (walked["buildings"] as Array).size()

		var stamped: Dictionary = _stamped(mesher, mesher.get("_margin"))
		var cutouts: Dictionary = mesher.get("_model_cutouts")
		var bodies: Dictionary = mesher.get("_model_bodies")
		maps += 1
		var wrong: Array = []
		for drawing: String in found:
			drawings += 1
			var entry: Dictionary = found[drawing]
			var places: PackedVector2Array = entry["spots"]
			var across: Vector2i = entry["across"]
			spots += places.size()

			at = Time.get_ticks_usec()
			var card: Array = cutter.far_card_for(
				entry["tiles"], across, shape, entry["class"], atlas
			)
			cut_usec += Time.get_ticks_usec() - at
			if card.size() == 2:
				cut += 1
			if not _card_agrees(card, drawing, bodies, cutouts):
				wrong.append("%s: card differs" % _short(drawing))

			if not stamped.has(drawing):
				wrong.append("%s: walked %d, mesh none" % [
					_short(drawing), places.size(),
				])
				continue
			var mine: Dictionary = {}
			for spot: Vector2 in places:
				mine[str(_start(spot, across))] = true
			var boxes: Dictionary = stamped[drawing]
			if mine.size() != boxes.size() or not _same(mine, boxes):
				wrong.append("%s: walked %d, mesh %d" % [
					_short(drawing), mine.size(), boxes.size(),
				])
		for drawing: String in stamped:
			var count: int = (stamped[drawing] as Dictionary).size()
			if count > 0 and not found.has(drawing):
				wrong.append("%s: walked none, mesh %d" % [_short(drawing), count])
		if not wrong.is_empty():
			differ += 1
			print("%d,%d tileset %d: %s" % [
				map.group, map.number, map.tileset, ", ".join(wrong),
			])
		if only.x >= 0:
			_report_map(found, stamped)

	print("maps %d, differ %d, drawings %d, spots %d, cards cut %d, buildings %d,"
		% [maps, differ, drawings, spots, cut, houses]
		+ " walk %.1f ms, cut %.1f ms"
		% [float(walk_usec) / 1000.0, float(cut_usec) / 1000.0])
	quit(int(differ > 0))


func _start(spot: Vector2, across: Vector2i) -> Vector2i:
	return Vector2i(
		floori((spot.x - float(across.x * TILE) * 0.5) / float(TILE)),
		floori((spot.y - float(across.y * TILE) * 0.5) / float(TILE))
	)


func _card_agrees(
	card: Array, drawing: String, bodies: Dictionary, cutouts: Dictionary
) -> bool:
	if not bodies.has(drawing):
		return true
	var wanted: Image = null
	if card.size() == 2 and card[1] != null:
		wanted = (card[1] as ImageTexture).get_image()
	if wanted == null:
		return _all_null(bodies[drawing], cutouts)
	for body: Array in bodies[drawing]:
		var theirs: ImageTexture = cutouts.get(body[0])
		if theirs != null and theirs.get_image().get_data() == wanted.get_data():
			return true
	return false


func _all_null(drawn: Array, cutouts: Dictionary) -> bool:
	for body: Array in drawn:
		if cutouts.get(body[0]) != null:
			return false
	return true


func _stamped(mesher: RefCounted, margin: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var spots: Dictionary = mesher.get("_model_spots")
	for key: String in spots:
		var named: String = key.trim_suffix("~far")
		var at: int = named.rfind("#")
		if at <= 0:
			continue
		var drawing: String = named.substr(0, at)
		if not drawing.begins_with("["):
			continue
		if not out.has(drawing):
			out[drawing] = {}
		for start: String in (spots[key] as Dictionary):
			(out[drawing] as Dictionary)[str(_vector(start) - margin)] = true
	return out


func _same(mine: Dictionary, theirs: Dictionary) -> bool:
	for key: String in mine:
		if not theirs.has(key):
			return false
	return true


func _vector(text: String) -> Vector2i:
	var inside: String = text.replace("(", "").replace(")", "")
	var parts: PackedStringArray = inside.split(",")
	if parts.size() != 2:
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))


func _short(drawing: String) -> String:
	return drawing.substr(0, 28) + ("..." if drawing.length() > 28 else "")


func _report_map(found: Dictionary, stamped: Dictionary) -> void:
	for drawing: String in found:
		var entry: Dictionary = found[drawing]
		print("    %-32s %-10s %4d spots, mesh %d" % [
			_short(drawing), String(entry["class"]),
			(entry["spots"] as PackedVector2Array).size(),
			(stamped.get(drawing, {}) as Dictionary).size(),
		])
