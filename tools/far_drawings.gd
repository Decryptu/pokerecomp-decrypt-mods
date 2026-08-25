extends SceneTree

## WHETHER THE HORIZON NAMES AND CUTS THE SAME DRAWINGS THE MESH DOES.
##
## `shape/far_drawings.gd` reads which drawing stands on which cell off a bare
## map, at a fraction of what a resolve costs, and it does that by carrying a
## copy of the mesher's own box rule. `mesher.far_card_for` then cuts that
## drawing out of the map's own sheet with no resolve behind it. Both are only
## worth having while they are provably the same answer, and this is the proof.
##
## Every outdoor map is resolved and emitted for real, and two things are checked
## against it:
##
## - THE BOXES. Every box the mesher stamped a model into against every box the
##   walk found, name for name and position for position.
## - THE CARDS. The card the factory cuts for each drawing against the cut-outs
##   the resolve built for that drawing's bodies, pixel for pixel.
##
##   Godot --headless --path <pokerecomp> -s tools/far_drawings.gd -- \
##       <cache> [group,number]
##
## Prints one line per map that differs and a total. Zero differing maps is the
## whole result. Named a map, it prints that map's own drawings as well, which is
## what to run when one does differ.
##
## Headless: it resolves and emits, and never renders.

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
		# A FACTORY PER MAP, which is what `far_foliage.gd` builds and why: the
		# mask cache is keyed on tile ids and means nothing on another tileset.
		var cutter: RefCounted = mesher_script.new()
		mesher.resolve(source, shape)
		mesher.emit(atlas)

		var at: int = Time.get_ticks_usec()
		# WALKED INTO THE BORDER RING, which is where the mesher stamps too: route
		# 26 alone puts 798 conifers out there against the 240 on the map, and
		# comparing only the map left three quarters of the answer untested.
		var ring: int = (mesher.get("_margin") as Vector2i).x
		var walked: Dictionary = walk_script.of_map(data, map, profile, ring)
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
	quit(1 if differ > 0 else 0)


## A walked spot back to the tile its box starts at. The walk answers the box's
## MIDDLE in world pixels, and a drawing's box is one size wherever it stands.
func _start(spot: Vector2, across: Vector2i) -> Vector2i:
	# FLOORED and not truncated: a box in the border ring starts at a negative
	# tile, and integer division rounds those the wrong way.
	return Vector2i(
		floori((spot.x - float(across.x * TILE) * 0.5) / float(TILE)),
		floori((spot.y - float(across.y * TILE) * 0.5) / float(TILE))
	)


## Whether the factory's card is one the resolve cut for the same drawing.
##
## AT LEAST ONE BODY and not a named one: the factory takes the drawing's largest
## body and the resolve keys its cut-outs per body, so what is being asked is
## whether the picture the horizon will wear is a picture the mesh cut. A drawing
## holding one body, which is every tree and every bush, has one answer to give.
func _card_agrees(
	card: Array, drawing: String, bodies: Dictionary, cutouts: Dictionary
) -> bool:
	# Never built by the mesher, so there is nothing to differ from: a drawing
	# whose bodies are all under `MODEL_BODY_MIN` reaches this.
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


## Every box the mesh stamped a model into, as `drawing -> {tile position: true}`
## in the MAP'S own tiles, which is what the walk answers in.
##
## `_model_spots` is keyed per BODY and per level of detail, so a drawing that
## flooded into two bodies and swapped one of them for its far twin holds the
## same box under four keys. The box is what is being compared, so they collapse.
##
## THE BORDER RING IS IN, since the walk covers it now: what is compared is every
## box the mesher stamped anywhere in its grid.
##
## A DECLARED OBJECT IS LEFT OUT. `_object_model` names its meshes
## `<object>:<tiles>`, and an object is found by an arrangement of tile ids
## rather than by a class, which is not a question the horizon walk asks or ever
## asked: the fountain and the ship have never stood out there.
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


## The first few tile ids of a drawing, which is enough to tell two apart in a
## report and short enough to read.
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
